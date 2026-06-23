import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local/knowledge_graph_dao.dart';
import 'ai_service.dart';

/// AI-powered service for extracting knowledge concepts and semantic relations
/// from course content text, then persisting them into the knowledge graph
/// (V9 tables: knowledge_concepts + concept_relations).
///
/// Usage:
/// ```dart
/// final service = KnowledgeExtractService();
/// final result = await service.extractFromChapter(3, chapterText);
/// print('Extracted ${result['concepts']} concepts, ${result['relations']} relations');
/// ```
class KnowledgeExtractService {
  final AiService _aiService = AiService();
  final KnowledgeGraphDao _dao = KnowledgeGraphDao();

  // ── 1. Extract concepts from raw text ─────────────────────────────────────

  /// Sends [text] to the AI model and asks it to extract knowledge concepts.
  ///
  /// If [chapter] is provided it is included in the prompt context and written
  /// into each concept row.  Returns the list of concept maps that were
  /// successfully inserted (empty list on total failure).
  Future<List<Map<String, dynamic>>> extractConceptsFromText(
    String text, {
    int? chapter,
  }) async {
    if (text.trim().isEmpty) return [];

    const systemPrompt = '''
你是一位课程知识图谱构建专家。
请从给定的教学内容中提取知识概念，每个概念包含以下字段：
- concept_name: 概念名称（简洁，2-8个字）
- concept_type: 类型（concept/technology/tool/framework/language/platform/pattern 之一）
- description: 简短描述（一句话）
- importance: 重要性（core/important/supplementary 之一）
- keywords: 关键词（逗号分隔，3-5个）

请以JSON数组格式输出，不要包含其他内容。提取10-20个核心概念。''';

    final chapterHint = chapter != null ? '第$chapter章的' : '';
    final userPrompt = '以下是$chapterHint教学内容，请提取知识概念：\n\n$text';

    try {
      final raw = await _aiService.chat(
        [
          {'role': 'user', 'content': userPrompt},
        ],
        systemPrompt: systemPrompt,
      );

      final parsed = _parseJsonFromResponse(raw);
      if (parsed == null || parsed is! List) {
        debugPrint('[KnowledgeExtractService] AI 返回的内容无法解析为 JSON 数组');
        return [];
      }

      final inserted = <Map<String, dynamic>>[];
      for (final item in parsed) {
        if (item is! Map) continue;
        final concept = Map<String, dynamic>.from(item);

        // Validate required field
        final name = concept['concept_name'];
        if (name == null || (name as String).trim().isEmpty) continue;

        // Normalise fields
        concept['concept_type'] = _normaliseConceptType(
          concept['concept_type']?.toString() ?? 'concept',
        );
        concept['importance'] = _normaliseImportance(
          concept['importance']?.toString() ?? 'important',
        );
        if (chapter != null) concept['chapter'] = chapter;

        // Mark as AI-generated in description if not already noted
        final desc = concept['description']?.toString() ?? '';
        if (!desc.contains('[AI生成]')) {
          concept['description'] = '[AI生成] $desc';
        }

        try {
          final id = await _dao.addConcept(concept);
          if (id > 0) {
            concept['id'] = id;
            inserted.add(concept);
          }
        } catch (e) {
          debugPrint('[KnowledgeExtractService] 插入概念失败: $e');
        }
      }

      debugPrint('[KnowledgeExtractService] 成功提取并插入 ${inserted.length} 个概念');
      return inserted;
    } catch (e) {
      debugPrint('[KnowledgeExtractService] extractConceptsFromText 异常: $e');
      rethrow;
    }
  }

  // ── 2. Extract relations from a list of concept names ─────────────────────

  /// Given a list of [conceptNames], asks the AI to identify semantic relations
  /// between them.  Resolves names → DB IDs before inserting.
  ///
  /// Returns the list of relation maps that were successfully inserted.
  Future<List<Map<String, dynamic>>> extractRelationsFromConcepts(
    List<String> conceptNames, {
    int? chapter,
  }) async {
    if (conceptNames.length < 2) return [];

    const systemPrompt = '''
你是一位课程知识图谱构建专家。
请分析以下知识概念之间的语义关系，每条关系包含：
- source: 源概念名称
- target: 目标概念名称
- relation_type: 关系类型，必须是以下之一：
  prerequisite（前置知识）、related_to（相关概念）、part_of（组成部分）、
  compared_with（对比技术）、applied_in（应用于）、builds_upon（递进关系）、
  alternative_to（替代方案）、extends（扩展）
- relation_label: 中文关系标签
- description: 关系描述（一句话）
- bidirectional: 是否双向（0或1）
- weight: 关系强度（0.5-1.0）

请以JSON数组格式输出。注意：
1. prerequisite表示学习A之前需要先学B
2. related_to和compared_with通常是双向的
3. 只输出确定存在的关系，不要编造

请提取15-30条关系。''';

    final userPrompt = '以下是需要分析关系的知识概念列表：\n${conceptNames.join(', ')}';

    try {
      final raw = await _aiService.chat(
        [
          {'role': 'user', 'content': userPrompt},
        ],
        systemPrompt: systemPrompt,
      );

      final parsed = _parseJsonFromResponse(raw);
      if (parsed == null || parsed is! List) {
        debugPrint('[KnowledgeExtractService] AI 返回的关系内容无法解析');
        return [];
      }

      // Build a name → id lookup (from DB) for resolving references
      final nameIdMap = await _buildNameIdMap(conceptNames);

      final inserted = <Map<String, dynamic>>[];
      for (final item in parsed) {
        if (item is! Map) continue;
        final rel = Map<String, dynamic>.from(item);

        final sourceName = rel['source']?.toString();
        final targetName = rel['target']?.toString();
        if (sourceName == null || targetName == null) continue;

        final sourceId = nameIdMap[sourceName];
        final targetId = nameIdMap[targetName];
        if (sourceId == null || targetId == null) {
          debugPrint(
            '[KnowledgeExtractService] 跳过关系：未找到概念 '
            '"$sourceName" (id=$sourceId) → "$targetName" (id=$targetId)',
          );
          continue;
        }

        final relationType = _normaliseRelationType(
          rel['relation_type']?.toString() ?? 'related_to',
        );

        final relation = <String, dynamic>{
          'source_concept_id': sourceId,
          'target_concept_id': targetId,
          'relation_type': relationType,
          'relation_label': rel['relation_label']?.toString() ?? relationType,
          'description': rel['description']?.toString() ?? '',
          'bidirectional': _parseBidirectional(rel['bidirectional']),
          'weight': _parseWeight(rel['weight']),
          'ai_generated': 1,
          'confidence': 0.85,
        };

        try {
          final id = await _dao.addRelation(relation);
          if (id > 0) {
            relation['id'] = id;
            inserted.add(relation);
          }
        } catch (e) {
          debugPrint('[KnowledgeExtractService] 插入关系失败: $e');
        }
      }

      debugPrint('[KnowledgeExtractService] 成功提取并插入 ${inserted.length} 条关系');
      return inserted;
    } catch (e) {
      debugPrint(
          '[KnowledgeExtractService] extractRelationsFromConcepts 异常: $e');
      rethrow;
    }
  }

  // ── 3. Convenience: extract everything for a chapter ──────────────────────

  /// Extracts concepts *and* relations for the given chapter in one call.
  ///
  /// Returns `{'concepts': int, 'relations': int}` with the counts of
  /// successfully inserted rows.
  Future<Map<String, int>> extractFromChapter(
    int chapter,
    String content,
  ) async {
    // Step 1 – extract concepts
    final concepts = await extractConceptsFromText(content, chapter: chapter);
    final newNames =
        concepts.map((c) => c['concept_name']?.toString() ?? '').toList();

    // Step 2 – also include existing concepts for the same chapter so the
    //          AI can discover cross-concept relations
    final existingRows = await _dao.getConceptsByChapter(chapter);
    final existingNames =
        existingRows.map((r) => r['concept_name']?.toString() ?? '').toList();

    // Merge & deduplicate
    final allNames = <String>{...newNames, ...existingNames}
        .where((n) => n.isNotEmpty)
        .toList();

    // Step 3 – extract relations
    final relations = await extractRelationsFromConcepts(
      allNames,
      chapter: chapter,
    );

    return {
      'concepts': concepts.length,
      'relations': relations.length,
    };
  }

  // ── 4. Enrich a single concept's description ─────────────────────────────

  /// Asks AI to produce a more detailed educational description for the
  /// concept identified by [conceptId].  Updates the DB row and returns the
  /// new description.  Throws if the concept doesn't exist.
  Future<String> enrichConceptDescription(int conceptId) async {
    final concept = await _dao.getConceptById(conceptId);
    if (concept == null) {
      throw Exception('概念不存在 (id=$conceptId)');
    }

    final name = concept['concept_name'] ?? '未知概念';
    final currentDesc = concept['description'] ?? '';
    final keywords = concept['keywords'] ?? '';
    final chapter = concept['chapter'];

    const systemPrompt = '你是课程教学专家。请用中文为给定的知识概念撰写一段详细的'
        '教学描述（150-250字），包含定义、核心要点和在课程中的作用。';

    final chapterHint = chapter != null ? '（第$chapter章）' : '';
    final userPrompt = '概念名称：$name$chapterHint\n'
        '当前描述：$currentDesc\n'
        '关键词：$keywords\n'
        '请生成更详细的教学描述。';

    try {
      final enriched = await _aiService.chat(
        [
          {'role': 'user', 'content': userPrompt},
        ],
        systemPrompt: systemPrompt,
      );

      final cleanDesc = enriched.trim();
      await _dao.updateConcept(conceptId, {
        'description': '[AI增强] $cleanDesc',
      });

      debugPrint('[KnowledgeExtractService] 已丰富概念描述: $name');
      return cleanDesc;
    } catch (e) {
      debugPrint('[KnowledgeExtractService] enrichConceptDescription 异常: $e');
      rethrow;
    }
  }

  // ── 5. Batch enrich descriptions ─────────────────────────────────────────

  /// Enriches descriptions for all concepts that haven't been enriched yet
  /// (i.e. description does not start with "[AI增强]").
  /// Returns the number of concepts enriched.
  Future<int> batchEnrichDescriptions({int? chapter}) async {
    final concepts = chapter != null
        ? await _dao.getConceptsByChapter(chapter)
        : await _dao.getAllConcepts();

    int enriched = 0;
    for (final c in concepts) {
      final desc = c['description']?.toString() ?? '';
      if (desc.startsWith('[AI增强]')) continue;

      final id = c['id'] as int?;
      if (id == null) continue;

      try {
        await enrichConceptDescription(id);
        enriched++;
        // Small delay to avoid hammering the API
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[KnowledgeExtractService] 跳过概念 id=$id: $e');
      }
    }
    return enriched;
  }

  // ── 6. Get extraction statistics ─────────────────────────────────────────

  /// Returns a summary map useful for dashboards.
  Future<Map<String, dynamic>> getStatistics() async {
    final totalConcepts = await _dao.conceptCount();
    final totalRelations = await _dao.relationCount();
    final allConcepts = await _dao.getAllConcepts();

    // Count by chapter
    final chapterCounts = <int, int>{};
    // Count by type
    final typeCounts = <String, int>{};
    // Count by importance
    final importanceCounts = <String, int>{};

    for (final c in allConcepts) {
      final ch = c['chapter'] as int?;
      if (ch != null) chapterCounts[ch] = (chapterCounts[ch] ?? 0) + 1;

      final t = c['concept_type']?.toString() ?? 'concept';
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;

      final imp = c['importance']?.toString() ?? 'important';
      importanceCounts[imp] = (importanceCounts[imp] ?? 0) + 1;
    }

    return {
      'total_concepts': totalConcepts,
      'total_relations': totalRelations,
      'by_chapter': chapterCounts,
      'by_type': typeCounts,
      'by_importance': importanceCounts,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Private helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Attempts to decode [response] as JSON.  If direct decoding fails, tries
  /// to locate a JSON array with a regex and parse that instead.
  dynamic _parseJsonFromResponse(String response) {
    // Strip markdown code-fence wrappers (```json ... ```) that some models add
    final stripped = response
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*$'), '')
        .trim();

    // Attempt 1: direct parse
    try {
      return jsonDecode(stripped);
    } catch (_) {
      // fall through
    }

    // Attempt 2: extract the first JSON array from the text
    final arrayMatch = RegExp(r'\[[\s\S]*\]').firstMatch(stripped);
    if (arrayMatch != null) {
      try {
        return jsonDecode(arrayMatch.group(0)!);
      } catch (_) {
        // fall through
      }
    }

    // Attempt 3: extract a JSON object (single-item response)
    final objMatch = RegExp(r'\{[\s\S]*\}').firstMatch(stripped);
    if (objMatch != null) {
      try {
        final obj = jsonDecode(objMatch.group(0)!);
        return obj is Map ? [obj] : obj;
      } catch (_) {
        // fall through
      }
    }

    debugPrint('[KnowledgeExtractService] JSON 解析全部失败，原始内容: $response');
    return null;
  }

  /// Builds a {conceptName → dbId} map by searching for each name in the DB.
  Future<Map<String, int>> _buildNameIdMap(List<String> names) async {
    final map = <String, int>{};
    for (final name in names) {
      if (name.isEmpty) continue;
      final rows = await _dao.searchConcepts(name);
      // Pick exact match first, otherwise first partial match
      for (final r in rows) {
        if (r['concept_name'] == name) {
          map[name] = r['id'] as int;
          break;
        }
      }
      // If no exact match was found, use the first partial match
      if (!map.containsKey(name) && rows.isNotEmpty) {
        map[name] = rows.first['id'] as int;
      }
    }
    return map;
  }

  /// Normalise concept_type to one of the allowed enum values.
  String _normaliseConceptType(String raw) {
    const allowed = {
      'concept',
      'technology',
      'tool',
      'framework',
      'language',
      'platform',
      'pattern',
    };
    final lower = raw.trim().toLowerCase();
    return allowed.contains(lower) ? lower : 'concept';
  }

  /// Normalise importance to one of core / important / supplementary.
  String _normaliseImportance(String raw) {
    const allowed = {'core', 'important', 'supplementary'};
    final lower = raw.trim().toLowerCase();
    return allowed.contains(lower) ? lower : 'important';
  }

  /// Normalise relation_type to one of the allowed enum values.
  String _normaliseRelationType(String raw) {
    const allowed = {
      'prerequisite',
      'related_to',
      'part_of',
      'compared_with',
      'applied_in',
      'builds_upon',
      'alternative_to',
      'extends',
    };
    final lower = raw.trim().toLowerCase();
    return allowed.contains(lower) ? lower : 'related_to';
  }

  /// Parse the bidirectional field which may arrive as int, bool, or string.
  int _parseBidirectional(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value == 0 ? 0 : 1;
    if (value is bool) return value ? 1 : 0;
    final s = value.toString().toLowerCase();
    return (s == '1' || s == 'true') ? 1 : 0;
  }

  /// Parse the weight field, clamping to [0.5, 1.0].
  double _parseWeight(dynamic value) {
    if (value == null) return 0.8;
    double w;
    if (value is num) {
      w = value.toDouble();
    } else {
      w = double.tryParse(value.toString()) ?? 0.8;
    }
    return w.clamp(0.5, 1.0);
  }
}
