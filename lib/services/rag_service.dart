import 'package:flutter/foundation.dart';
import '../data/local/database_helper.dart';
import '../data/local/knowledge_graph_dao.dart';

/// 检索增强生成（RAG）服务
///
/// 从本地数据库中检索与用户查询相关的知识内容，
/// 用于增强智能体的系统提示词，提供课程特定的上下文。
///
/// 数据源：
/// - `knowledge_concepts` / `concept_relations` — 语义知识图谱
/// - `nodes` — 图谱节点（标题、内容）
/// - `resource_files` — 课程资料（PDF/PPT/视频）
/// - `questions` — 测验题库
class RagService {
  final KnowledgeGraphDao _kgDao = KnowledgeGraphDao();

  /// 根据用户查询检索相关内容，返回增强上下文文本。
  ///
  /// [query] 用户输入的问题/主题
  /// [maxConcepts] 最多返回的概念数（默认 8）
  /// [includeRelations] 是否包含概念间的关系（默认 true）
  /// [includeResources] 是否包含课程资料信息（默认 true）
  /// [includeQuestions] 是否包含相关测验题（默认 false）
  Future<String> retrieveContext(
    String query, {
    int maxConcepts = 8,
    bool includeRelations = true,
    bool includeResources = true,
    bool includeQuestions = false,
  }) async {
    if (query.trim().isEmpty) return '';

    final sections = <String>[];

    // 提取搜索关键词（按空格/逗号/顿号拆分）
    final keywords = _extractKeywords(query);

    // 1. 搜索语义知识概念
    final concepts = await _searchConcepts(keywords, maxConcepts);
    if (concepts.isNotEmpty) {
      sections.add(_formatConcepts(concepts));

      // 2. 检索概念间的关系
      if (includeRelations) {
        final relations = await _getRelationsForConcepts(concepts);
        if (relations.isNotEmpty) {
          sections.add(_formatRelations(relations, concepts));
        }
      }
    }

    // 3. 搜索图谱节点（补充概念未覆盖的内容）
    final nodes = await _searchNodes(keywords, maxConcepts);
    if (nodes.isNotEmpty) {
      sections.add(_formatNodes(nodes));
    }

    // 4. 搜索课程资料
    if (includeResources) {
      final resources = await _searchResources(keywords);
      if (resources.isNotEmpty) {
        sections.add(_formatResources(resources));
      }
    }

    // 5. 搜索相关测验题
    if (includeQuestions) {
      final questions = await _searchQuestions(keywords);
      if (questions.isNotEmpty) {
        sections.add(_formatQuestions(questions));
      }
    }

    if (sections.isEmpty) return '';

    return '## 课程知识库参考\n\n${sections.join('\n\n')}';
  }

  /// 从用户查询中提取搜索关键词
  List<String> _extractKeywords(String query) {
    // 去掉常见停用词和问句助词
    const stopWords = {
      '的', '了', '吗', '呢', '啊', '吧', '是', '在', '有', '和', '与',
      '或', '对', '从', '到', '把', '被', '让', '给', '用', '以',
      '什么', '怎么', '如何', '为什么', '哪些', '哪个', '多少',
      '能', '可以', '请', '帮', '我', '你', '他', '她', '它', '们',
      '这', '那', '些', '个', '一', '不', '也', '都', '还', '就',
      '想', '要', '知道', '了解', '学习', '看看', '介绍', '说说',
    };

    final words = query
        .replaceAll(RegExp(r'[，。！？、；：""''（）\[\]{}【】]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !stopWords.contains(w))
        .toList();

    // 如果分词后太少，用原始查询
    if (words.isEmpty) return [query.trim()];
    return words.take(5).toList(); // 最多 5 个关键词
  }

  /// 搜索语义知识概念
  Future<List<Map<String, dynamic>>> _searchConcepts(
      List<String> keywords, int limit) async {
    final seen = <int>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final hits = await _kgDao.searchConcepts(kw);
        for (final hit in hits) {
          final id = hit['id'] as int;
          if (!seen.contains(id)) {
            seen.add(id);
            results.add(hit);
          }
        }
      } catch (e) {
        debugPrint('RagService: searchConcepts error for "$kw": $e');
      }
    }

    // 按重要性排序：core > important > supplementary
    results.sort((a, b) {
      const order = {'core': 0, 'important': 1, 'supplementary': 2};
      final ai = order[a['importance'] ?? 'supplementary'] ?? 2;
      final bi = order[b['importance'] ?? 'supplementary'] ?? 2;
      return ai.compareTo(bi);
    });

    return results.take(limit).toList();
  }

  /// 获取概念间的关系
  Future<List<Map<String, dynamic>>> _getRelationsForConcepts(
      List<Map<String, dynamic>> concepts) async {
    final conceptIds = concepts.map((c) => c['id'] as int).toSet();
    final allRelations = <Map<String, dynamic>>[];

    for (final id in conceptIds) {
      try {
        final rels = await _kgDao.getRelationsForConcept(id);
        for (final rel in rels) {
          // 只保留两端都在已检索概念中的关系
          final srcId = rel['source_concept_id'] as int?;
          final tgtId = rel['target_concept_id'] as int?;
          if (srcId != null &&
              tgtId != null &&
              conceptIds.contains(srcId) &&
              conceptIds.contains(tgtId)) {
            allRelations.add(rel);
          }
        }
      } catch (e) {
        debugPrint('RagService: getRelations error for concept $id: $e');
      }
    }

    // 去重（按 id）
    final seen = <int>{};
    return allRelations.where((r) => seen.add(r['id'] as int)).toList();
  }

  /// 搜索图谱节点
  Future<List<Map<String, dynamic>>> _searchNodes(
      List<String> keywords, int limit) async {
    final db = await DatabaseHelper.instance.database;
    final seen = <String>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final hits = await db.query(
          'nodes',
          where: 'title LIKE ? OR content LIKE ?',
          whereArgs: ['%$kw%', '%$kw%'],
          limit: limit,
        );
        for (final hit in hits) {
          final id = hit['id'] as String? ?? '';
          if (id.isNotEmpty && !seen.contains(id)) {
            seen.add(id);
            results.add(hit);
          }
        }
      } catch (e) {
        debugPrint('RagService: searchNodes error for "$kw": $e');
      }
    }

    return results.take(limit).toList();
  }

  /// 搜索课程资料
  Future<List<Map<String, dynamic>>> _searchResources(
      List<String> keywords) async {
    final db = await DatabaseHelper.instance.database;
    final seen = <int>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final hits = await db.query(
          'resource_files',
          where: 'file_name LIKE ? OR description LIKE ?',
          whereArgs: ['%$kw%', '%$kw%'],
          limit: 5,
        );
        for (final hit in hits) {
          final id = hit['id'] as int? ?? 0;
          if (id > 0 && !seen.contains(id)) {
            seen.add(id);
            results.add(hit);
          }
        }
      } catch (e) {
        debugPrint('RagService: searchResources error for "$kw": $e');
      }
    }

    return results.take(8).toList();
  }

  /// 搜索相关测验题
  Future<List<Map<String, dynamic>>> _searchQuestions(
      List<String> keywords) async {
    final db = await DatabaseHelper.instance.database;
    final seen = <int>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final hits = await db.query(
          'questions',
          where: 'question LIKE ?',
          whereArgs: ['%$kw%'],
          limit: 3,
        );
        for (final hit in hits) {
          final id = hit['id'] as int? ?? 0;
          if (id > 0 && !seen.contains(id)) {
            seen.add(id);
            results.add(hit);
          }
        }
      } catch (e) {
        debugPrint('RagService: searchQuestions error for "$kw": $e');
      }
    }

    return results.take(5).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 格式化输出
  // ─────────────────────────────────────────────────────────────────────────

  String _formatConcepts(List<Map<String, dynamic>> concepts) {
    final buf = StringBuffer('### 相关知识概念\n\n');
    for (final c in concepts) {
      final name = c['concept_name'] ?? '未知';
      final type = c['concept_type'] ?? '';
      final chapter = c['chapter'];
      final importance = c['importance'] ?? '';
      final desc = c['description'] ?? '';
      final keywords = c['keywords'] ?? '';

      buf.write('- **$name**');
      if (type.isNotEmpty) buf.write('（$type）');
      if (chapter != null) buf.write(' [第${chapter}章]');
      if (importance.isNotEmpty) buf.write(' [$importance]');
      buf.writeln();
      if (desc.isNotEmpty) buf.writeln('  $desc');
      if (keywords.isNotEmpty) buf.writeln('  关键词: $keywords');
    }
    return buf.toString();
  }

  String _formatRelations(List<Map<String, dynamic>> relations,
      List<Map<String, dynamic>> concepts) {
    // 建立 ID → 名称映射
    final nameMap = <int, String>{};
    for (final c in concepts) {
      nameMap[c['id'] as int] = c['concept_name'] as String? ?? '?';
    }

    final buf = StringBuffer('### 概念关系\n\n');
    for (final r in relations) {
      final srcId = r['source_concept_id'] as int?;
      final tgtId = r['target_concept_id'] as int?;
      if (srcId == null || tgtId == null) continue;
      final srcName = nameMap[srcId] ?? '#$srcId';
      final tgtName = nameMap[tgtId] ?? '#$tgtId';
      final relType = r['relation_type'] ?? 'related_to';
      final label = r['relation_label'] ?? '';
      buf.write('- $srcName --[$relType]--> $tgtName');
      if (label.isNotEmpty) buf.write('（$label）');
      buf.writeln();
    }
    return buf.toString();
  }

  String _formatNodes(List<Map<String, dynamic>> nodes) {
    final buf = StringBuffer('### 图谱节点\n\n');
    for (final n in nodes) {
      final title = n['title'] ?? '';
      final content = n['content'] ?? '';
      final nodeType = n['node_type'] ?? '';
      if (title.isEmpty) continue;
      buf.write('- **$title**');
      if (nodeType.isNotEmpty) buf.write('（$nodeType）');
      buf.writeln();
      if (content.isNotEmpty) {
        // 截断过长的内容
        final truncated = content.length > 100
            ? '${content.substring(0, 100)}...'
            : content;
        buf.writeln('  $truncated');
      }
    }
    return buf.toString();
  }

  String _formatResources(List<Map<String, dynamic>> resources) {
    final buf = StringBuffer('### 相关课程资料\n\n');
    for (final r in resources) {
      final name = r['file_name'] ?? '';
      final type = r['file_type'] ?? '';
      final chapter = r['chapter'];
      final desc = r['description'] ?? '';
      buf.write('- 📄 $name ($type)');
      if (chapter != null) buf.write(' [第${chapter}章]');
      buf.writeln();
      if (desc.isNotEmpty) buf.writeln('  $desc');
    }
    return buf.toString();
  }

  String _formatQuestions(List<Map<String, dynamic>> questions) {
    final buf = StringBuffer('### 相关测验题\n\n');
    for (final q in questions) {
      final question = q['question'] ?? '';
      final source = q['source'] ?? '';
      buf.writeln('- [$source] $question');
    }
    return buf.toString();
  }
}
