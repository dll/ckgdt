import 'package:flutter/foundation.dart';
import '../data/local/database_helper.dart';
import '../data/local/knowledge_graph_dao.dart';
import '../data/local/rag_embedding_dao.dart';
import 'course_context_service.dart';
import 'embedding_service.dart';

/// 检索增强生成（RAG）服务
///
/// 从本地数据库中检索与用户查询相关的知识内容，
/// 用于增强智能体的系统提示词，提供课程特定的上下文。
///
/// 检索策略：
/// - 优先使用 TF-IDF 向量嵌入做语义检索（余弦相似度）
/// - 索引为空时自动退化为关键词 LIKE 匹配
///
/// 数据源：
/// - `knowledge_concepts` / `concept_relations` — 语义知识图谱
/// - `nodes` — 图谱节点（标题、内容）
/// - `resource_files` — 课程资料（PDF/PPT/视频）
/// - `questions` — 测验题库
class RagService {
  final KnowledgeGraphDao _kgDao = KnowledgeGraphDao();
  final CourseContextService _courseContext = CourseContextService();

  // ── TF-IDF 索引数据结构 ──────────────────────────────────────────────

  /// term → termId
  final Map<String, int> _vocabulary = {};

  /// termId → 出现该词的文档数
  final Map<int, int> _docFrequency = {};

  /// docKey → {termId: tf}
  /// docKey 格式: "concept:{id}", "node:{graphId}:{nodeId}", "resource:{id}"
  final Map<String, Map<int, double>> _docVectors = {};

  /// docKey → 原始行数据
  final Map<String, Map<String, dynamic>> _docMeta = {};

  /// 文档总数
  int _docCount = 0;

  /// 索引是否已构建
  bool _indexBuilt = false;
  String? _indexedCourseId;

  // ── 中文停用词 ──────────────────────────────────────────────────────

  static const _stopWords = {
    '的',
    '了',
    '吗',
    '呢',
    '啊',
    '吧',
    '是',
    '在',
    '有',
    '和',
    '与',
    '或',
    '对',
    '从',
    '到',
    '把',
    '被',
    '让',
    '给',
    '用',
    '以',
    '什么',
    '怎么',
    '如何',
    '为什么',
    '哪些',
    '哪个',
    '多少',
    '能',
    '可以',
    '请',
    '帮',
    '我',
    '你',
    '他',
    '她',
    '它',
    '们',
    '这',
    '那',
    '些',
    '个',
    '一',
    '不',
    '也',
    '都',
    '还',
    '就',
    '想',
    '要',
    '知道',
    '了解',
    '学习',
    '看看',
    '介绍',
    '说说',
    '一个',
    '一种',
    '这个',
    '那个',
    '我们',
    '他们',
    '自己',
    '其中',
    '通过',
    '以及',
    '使用',
    '进行',
    '基于',
    '需要',
    '包括',
    '主要',
    '不同',
    '之间',
    '相关',
    '用于',
    '提供',
    '实现',
    '开发',
    '应用',
    '技术',
    '移动',
    '系统',
    '设计',
    '方式',
    '方法',
    '过程',
    '内容',
    '功能',
    '特点',
    '作用',
    '什么是',
    '是指',
    '称为',
    '属于',
    '具有',
    '能够',
    '必须',
    '因此',
    '所以',
    '但是',
    '虽然',
    '如果',
    '因为',
    '并且',
  };

  // ── 公共 API ───────────────────────────────────────────────────────

  /// 根据用户查询检索相关内容，返回增强上下文文本。
  Future<String> retrieveContext(
    String query, {
    int maxConcepts = 8,
    bool includeRelations = true,
    bool includeResources = true,
    bool includeQuestions = false,
  }) async {
    if (query.trim().isEmpty) return '';

    // 首次调用时构建索引
    final activeCourseId = await _courseContext.activeCourseId();
    if (!_indexBuilt || _indexedCourseId != activeCourseId) {
      await rebuildIndex();
    }

    final sections = <String>[];

    List<Map<String, dynamic>> concepts;
    if (_docCount > 0) {
      concepts = _searchConceptsSemantic(query, maxConcepts);
    } else {
      final keywords = _extractKeywords(query);
      concepts = await _searchConceptsKeyword(keywords, maxConcepts);
    }

    if (concepts.isNotEmpty) {
      sections.add(_formatConcepts(concepts));

      if (includeRelations) {
        final relations = await _getRelationsForConcepts(concepts);
        if (relations.isNotEmpty) {
          sections.add(_formatRelations(relations, concepts));
        }
      }
    }

    List<Map<String, dynamic>> nodes;
    if (_docCount > 0) {
      nodes = _searchNodesSemantic(query, maxConcepts);
    } else {
      final keywords = _extractKeywords(query);
      nodes = await _searchNodesKeyword(keywords, maxConcepts);
    }
    if (nodes.isNotEmpty) {
      sections.add(_formatNodes(nodes));
    }

    if (includeResources) {
      List<Map<String, dynamic>> resources;
      if (_docCount > 0) {
        resources = _searchResourcesSemantic(query);
      } else {
        final keywords = _extractKeywords(query);
        resources = await _searchResourcesKeyword(keywords);
      }
      if (resources.isNotEmpty) {
        sections.add(_formatResources(resources));
      }
    }

    if (includeQuestions) {
      final keywords = _extractKeywords(query);
      final questions = await _searchQuestionsKeyword(keywords);
      if (questions.isNotEmpty) {
        sections.add(_formatQuestions(questions));
      }
    }

    if (sections.isEmpty) return '';
    return '## 课程知识库参考\n\n${sections.join('\n\n')}';
  }

  /// 强制重建索引（数据更新后调用）
  Future<void> rebuildIndex() async {
    _vocabulary.clear();
    _docFrequency.clear();
    _docVectors.clear();
    _docMeta.clear();
    _docCount = 0;
    _indexBuilt = false;
    await _buildIndex();
  }

  // ── 索引构建 ──────────────────────────────────────────────────────

  Future<void> _buildIndex() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final conceptScope = await _courseContext.scopedWhere();
      final graphScope =
          await _courseContext.scopedWhere(column: 'g.course_id');
      final resourceScope = await _courseContext.scopedWhere();

      // 1. 索引 knowledge_concepts
      final concepts = await db.query(
        'knowledge_concepts',
        where: conceptScope.where,
        whereArgs: conceptScope.args,
      );
      for (final c in concepts) {
        final id = c['id'];
        if (id == null) continue;
        final text = [
          c['concept_name'] ?? '',
          c['description'] ?? '',
          c['keywords'] ?? '',
        ].join(' ');
        if (text.trim().isEmpty) continue;
        final docKey = 'concept:$id';
        _addDocument(docKey, text, c);
      }

      // 2. 索引 nodes 表
      final nodes = await db.rawQuery('''
        SELECT n.*
        FROM nodes n
        INNER JOIN graphs g ON g.id = n.graph_id
        WHERE ${graphScope.where}
      ''', graphScope.args);
      for (final n in nodes) {
        final gid = n['graph_id'] ?? '0';
        final nid = n['id'] ?? '';
        final text = [
          n['title'] ?? '',
          n['content'] ?? '',
          n['node_type'] ?? '',
        ].join(' ');
        if (text.trim().isEmpty) continue;
        final docKey = 'node:$gid:$nid';
        _addDocument(docKey, text, n);
      }

      // 3. 索引 resource_files
      final resources = await db.query(
        'resource_files',
        where: resourceScope.where,
        whereArgs: resourceScope.args,
      );
      for (final r in resources) {
        final id = r['id'];
        if (id == null) continue;
        final text = [
          r['file_name'] ?? '',
          r['description'] ?? '',
          r['file_type'] ?? '',
        ].join(' ');
        if (text.trim().isEmpty) continue;
        final docKey = 'resource:$id';
        _addDocument(docKey, text, r);
      }

      _indexBuilt = true;
      _indexedCourseId = await _courseContext.activeCourseId();
      debugPrint('RagService: index built — $_docCount docs, '
          '${_vocabulary.length} terms');
    } catch (e) {
      debugPrint('RagService: _buildIndex failed: $e');
      _docCount = 0;
      _indexBuilt = true; // 标记为已尝试，避免反复重试
    }
  }

  void _addDocument(String docKey, String text, Map<String, dynamic> meta) {
    final tokens = _tokenize(text);
    if (tokens.isEmpty) return;

    final tf = <int, double>{};
    for (final t in tokens) {
      final termId = _vocabulary.putIfAbsent(t, () {
        final id = _vocabulary.length;
        _docFrequency[id] = 0;
        return id;
      });
      tf[termId] = (tf[termId] ?? 0.0) + 1.0;
    }

    // 归一化 TF
    final norm = tf.values.fold(0.0, (a, b) => a + b);
    if (norm > 0) {
      tf.forEach((k, v) => tf[k] = v / norm);
    }

    // 更新 DF
    for (final termId in tf.keys) {
      _docFrequency[termId] = (_docFrequency[termId] ?? 0) + 1;
    }

    _docVectors[docKey] = tf;
    _docMeta[docKey] = meta;
    _docCount++;
  }

  // ── 分词 ──────────────────────────────────────────────────────────

  /// 中文 uni-gram + bi-gram + 英文单词分词
  List<String> _tokenize(String text) {
    final tokens = <String>[];
    final chars = text.split('');
    final letters = RegExp(r'[a-zA-Z]');
    final digits = RegExp(r'[0-9]');

    // 英文/数字块提取
    int i = 0;
    while (i < chars.length) {
      final ch = chars[i];
      if (letters.hasMatch(ch)) {
        final buf = StringBuffer();
        while (i < chars.length && letters.hasMatch(chars[i])) {
          buf.write(chars[i]);
          i++;
        }
        final word = buf.toString().toLowerCase();
        if (word.length >= 2 && !_stopWords.contains(word)) {
          tokens.add(word);
        }
      } else if (digits.hasMatch(ch)) {
        final buf = StringBuffer();
        while (i < chars.length && digits.hasMatch(chars[i])) {
          buf.write(chars[i]);
          i++;
        }
        tokens.add(buf.toString());
      } else if (ch.trim().isNotEmpty &&
          !RegExp(r'[，。！？、；：""' '（）[\]{}【】,.!?;:()-]').hasMatch(ch)) {
        // 中文字符：uni-gram
        final uni = ch.toLowerCase();
        if (!_stopWords.contains(uni)) {
          tokens.add(uni);
        }
        // bi-gram（与前一个中文字符组合）
        if (i > 0) {
          final prev = chars[i - 1];
          if (prev.trim().isNotEmpty &&
              !RegExp(r'[a-zA-Z0-9，。！？、；：""' '（）[\]{}【】,.!?;:()-]')
                  .hasMatch(prev)) {
            final bi = '${prev.toLowerCase()}$uni';
            tokens.add(bi);
          }
        }
        i++;
      } else {
        i++;
      }
    }

    // 去停用词 + 去重保留词频统计用原始列表
    return tokens.where((t) => t.isNotEmpty).toList();
  }

  // ── TF-IDF 计算 ───────────────────────────────────────────────────

  /// 逆文档频率（加 1 平滑）
  double _idf(int termId) {
    final df = _docFrequency[termId] ?? 0;
    return _log2((_docCount + 1) / (df + 1)) + 1.0;
  }

  double _log2(double x) {
    if (x <= 0) return 0;
    return _natLog(x) / _natLog(2.0);
  }

  static double _natLog(double x) {
    // Taylor series approximation for ln(x) around x=1
    if (x <= 0) return double.negativeInfinity;
    double result = 0;
    double term = (x - 1) / (x + 1);
    double termSquared = term * term;
    double current = term;
    for (int n = 1; n < 20; n += 2) {
      result += current / n;
      current *= termSquared;
    }
    return 2 * result;
  }

  /// 查询文本 → TF-IDF 向量
  Map<int, double> _queryVector(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return {};

    final tf = <int, double>{};
    for (final t in tokens) {
      final termId = _vocabulary[t];
      if (termId != null) {
        tf[termId] = (tf[termId] ?? 0.0) + 1.0;
      }
    }

    // TF-IDF 加权
    final result = <int, double>{};
    tf.forEach((termId, freq) {
      result[termId] = freq * _idf(termId);
    });

    // L2 归一化
    final norm = _l2Norm(result);
    if (norm > 0) {
      result.forEach((k, v) => result[k] = v / norm);
    }
    return result;
  }

  double _l2Norm(Map<int, double> vec) {
    double sum = 0;
    for (final v in vec.values) {
      sum += v * v;
    }
    return sum > 0 ? _sqrt(sum) : 0;
  }

  double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  /// 余弦相似度：queryVec · docVec（docVec 中 term 的值是归一化 TF）
  double _cosineSimilarity(Map<int, double> queryVec, Map<int, double> docVec) {
    double dot = 0;
    queryVec.forEach((termId, qWeight) {
      final dWeight = docVec[termId];
      if (dWeight != null) {
        dot += qWeight * dWeight * _idf(termId);
      }
    });

    final qNorm = _l2Norm(queryVec);
    // docVec IDF-weighted L2 norm
    double dSum = 0;
    docVec.forEach((termId, tfNorm) {
      final w = tfNorm * _idf(termId);
      dSum += w * w;
    });
    final dNorm = dSum > 0 ? _sqrt(dSum) : 0;

    if (qNorm == 0 || dNorm == 0) return 0;
    return dot / (qNorm * dNorm);
  }

  // ── 语义搜索（TF-IDF） ────────────────────────────────────────────

  List<Map<String, dynamic>> _searchConceptsSemantic(String query, int limit) {
    final qVec = _queryVector(query);
    if (qVec.isEmpty) return [];

    final scored = <_DocScore>[];
    for (final entry in _docVectors.entries) {
      if (!entry.key.startsWith('concept:')) continue;
      final sim = _cosineSimilarity(qVec, entry.value);
      if (sim > 0.05) {
        scored.add(_DocScore(entry.key, sim));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final results = <Map<String, dynamic>>[];
    for (final s in scored.take(limit)) {
      final meta = _docMeta[s.docKey];
      if (meta != null) results.add(meta);
    }

    // 按重要性排序：core > important > supplementary
    results.sort((a, b) {
      const order = {'core': 0, 'important': 1, 'supplementary': 2};
      final ai = order[a['importance'] ?? 'supplementary'] ?? 2;
      final bi = order[b['importance'] ?? 'supplementary'] ?? 2;
      return ai.compareTo(bi);
    });

    return results;
  }

  List<Map<String, dynamic>> _searchNodesSemantic(String query, int limit) {
    final qVec = _queryVector(query);
    if (qVec.isEmpty) return [];

    final scored = <_DocScore>[];
    for (final entry in _docVectors.entries) {
      if (!entry.key.startsWith('node:')) continue;
      final sim = _cosineSimilarity(qVec, entry.value);
      if (sim > 0.05) {
        scored.add(_DocScore(entry.key, sim));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final results = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final s in scored) {
      final meta = _docMeta[s.docKey];
      if (meta != null) {
        final id = meta['id']?.toString() ?? '';
        if (id.isNotEmpty && seen.add(id)) {
          results.add(meta);
        }
      }
    }
    return results.take(limit).toList();
  }

  List<Map<String, dynamic>> _searchResourcesSemantic(String query) {
    final qVec = _queryVector(query);
    if (qVec.isEmpty) return [];

    final scored = <_DocScore>[];
    for (final entry in _docVectors.entries) {
      if (!entry.key.startsWith('resource:')) continue;
      final sim = _cosineSimilarity(qVec, entry.value);
      if (sim > 0.05) {
        scored.add(_DocScore(entry.key, sim));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(8).map((s) => _docMeta[s.docKey]!).toList();
  }

  // ── 关键词搜索（fallback） ────────────────────────────────────────

  /// 从用户查询中提取搜索关键词
  List<String> _extractKeywords(String query) {
    final words = query
        .replaceAll(RegExp(r'[，。！？、；：""' '（）[\]{}【】]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !_stopWords.contains(w))
        .toList();

    if (words.isEmpty) return [query.trim()];
    return words.take(5).toList();
  }

  Future<List<Map<String, dynamic>>> _searchConceptsKeyword(
      List<String> keywords, int limit) async {
    final seen = <int>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final hits = await _kgDao.searchConcepts(kw);
        for (final hit in hits) {
          final id = hit['id'] as int;
          if (seen.add(id)) results.add(hit);
        }
      } catch (e) {
        debugPrint('RagService: searchConcepts error for "$kw": $e');
      }
    }

    results.sort((a, b) {
      const order = {'core': 0, 'important': 1, 'supplementary': 2};
      final ai = order[a['importance'] ?? 'supplementary'] ?? 2;
      final bi = order[b['importance'] ?? 'supplementary'] ?? 2;
      return ai.compareTo(bi);
    });

    return results.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> _getRelationsForConcepts(
      List<Map<String, dynamic>> concepts) async {
    final conceptIds = concepts.map((c) => c['id'] as int).toSet();
    final allRelations = <Map<String, dynamic>>[];

    for (final id in conceptIds) {
      try {
        final rels = await _kgDao.getRelationsForConcept(id);
        for (final rel in rels) {
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

    final seen = <int>{};
    return allRelations.where((r) => seen.add(r['id'] as int)).toList();
  }

  Future<List<Map<String, dynamic>>> _searchNodesKeyword(
      List<String> keywords, int limit) async {
    final db = await DatabaseHelper.instance.database;
    final seen = <String>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final graphScope = await _courseContext.scopedWhere(
          column: 'g.course_id',
          extraWhere: 'n.title LIKE ? OR n.content LIKE ?',
          extraArgs: ['%$kw%', '%$kw%'],
        );
        final hits = await db.rawQuery('''
          SELECT n.*
          FROM nodes n
          INNER JOIN graphs g ON g.id = n.graph_id
          WHERE ${graphScope.where}
          LIMIT ?
        ''', [...graphScope.args, limit]);
        for (final hit in hits) {
          final id = hit['id'] as String? ?? '';
          if (id.isNotEmpty && seen.add(id)) results.add(hit);
        }
      } catch (e) {
        debugPrint('RagService: searchNodes error for "$kw": $e');
      }
    }

    return results.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> _searchResourcesKeyword(
      List<String> keywords) async {
    final db = await DatabaseHelper.instance.database;
    final seen = <int>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final scope = await _courseContext.scopedWhere(
          extraWhere: 'file_name LIKE ? OR description LIKE ?',
          extraArgs: ['%$kw%', '%$kw%'],
        );
        final hits = await db.query(
          'resource_files',
          where: scope.where,
          whereArgs: scope.args,
          limit: 5,
        );
        for (final hit in hits) {
          final id = hit['id'] as int? ?? 0;
          if (id > 0 && seen.add(id)) results.add(hit);
        }
      } catch (e) {
        debugPrint('RagService: searchResources error for "$kw": $e');
      }
    }

    return results.take(8).toList();
  }

  Future<List<Map<String, dynamic>>> _searchQuestionsKeyword(
      List<String> keywords) async {
    final db = await DatabaseHelper.instance.database;
    final seen = <int>{};
    final results = <Map<String, dynamic>>[];

    for (final kw in keywords) {
      try {
        final scope = await _courseContext.scopedWhere(
          extraWhere: 'question LIKE ?',
          extraArgs: ['%$kw%'],
        );
        final hits = await db.query(
          'questions',
          where: scope.where,
          whereArgs: scope.args,
          limit: 3,
        );
        for (final hit in hits) {
          final id = hit['id'] as int? ?? 0;
          if (id > 0 && seen.add(id)) results.add(hit);
        }
      } catch (e) {
        debugPrint('RagService: searchQuestions error for "$kw": $e');
      }
    }

    return results.take(5).toList();
  }

  // ── 格式化输出 ────────────────────────────────────────────────────

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
      if (chapter != null) buf.write(' [第$chapter章]');
      if (importance.isNotEmpty) buf.write(' [$importance]');
      buf.writeln();
      if (desc.isNotEmpty) buf.writeln('  $desc');
      if (keywords.isNotEmpty) buf.writeln('  关键词: $keywords');
    }
    return buf.toString();
  }

  String _formatRelations(List<Map<String, dynamic>> relations,
      List<Map<String, dynamic>> concepts) {
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
        final truncated =
            content.length > 100 ? '${content.substring(0, 100)}...' : content;
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
      if (chapter != null) buf.write(' [第$chapter章]');
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

  // ════════════════════════════════════════════════════════════════════════
  //  向量化 RAG（升级路径）— 用 LLM embedding API + 余弦相似度 top-k
  // ════════════════════════════════════════════════════════════════════════

  /// 用向量索引检索，返回拼接好的上下文。
  /// 索引为空 / 调用失败时回退到 TF-IDF 版 [retrieveContext]。
  Future<String> retrieveContextVector(
    String userMessage, {
    int topK = 6,
    String? docIdFilter,
  }) async {
    try {
      final count = await RagEmbeddingDao.instance.count();
      if (count == 0) {
        // 向量索引未建立 → 回退
        return retrieveContext(userMessage, maxConcepts: topK);
      }
      final courseId = await _courseContext.activeCourseId();
      final qEmb = await EmbeddingService.instance.embed(userMessage);
      final hits = await RagEmbeddingDao.instance.search(
        qEmb,
        topK: topK,
        docIdFilter: docIdFilter,
        docIdPrefix: docIdFilter == null ? '$courseId:' : null,
      );
      if (hits.isEmpty) {
        return retrieveContext(userMessage, maxConcepts: topK);
      }
      final buf = StringBuffer('## 课程参考资料（向量检索）\n\n');
      for (var i = 0; i < hits.length; i++) {
        final h = hits[i];
        buf.writeln(
            '【${i + 1}】 [${h.docId}#${h.chunkId}] (相似度 ${h.score.toStringAsFixed(3)})');
        buf.writeln(h.content);
        buf.writeln();
      }
      return buf.toString();
    } catch (e) {
      debugPrint('RagService: 向量检索失败 → 回退 TF-IDF: $e');
      return retrieveContext(userMessage, maxConcepts: topK);
    }
  }

  /// 把一段文本切片 + embedding + 入库（建索引入口）。
  ///
  /// 简单按字符切片（每片 [chunkSize] 字 ± 重叠 [overlap]），适合中文长文档。
  /// 实际场景可换 markdown / 段落级切片。
  Future<int> indexDocument({
    required String docId,
    required String content,
    int chunkSize = 500,
    int overlap = 50,
    String? meta,
  }) async {
    if (content.trim().isEmpty) return 0;
    // 先清旧片段
    await RagEmbeddingDao.instance.deleteByDoc(docId);

    // 切片
    final chunks = <String>[];
    for (var i = 0; i < content.length; i += chunkSize - overlap) {
      final end =
          (i + chunkSize) < content.length ? i + chunkSize : content.length;
      chunks.add(content.substring(i, end));
      if (end >= content.length) break;
    }

    // 并行 embed（注意大批量需要分批以免触发 provider 限流）
    final embeddings = await EmbeddingService.instance.embedBatch(chunks);

    var inserted = 0;
    for (var i = 0; i < chunks.length; i++) {
      final id = await RagEmbeddingDao.instance.insert(
        docId: docId,
        chunkId: 'c$i',
        content: chunks[i],
        embedding: embeddings[i],
        meta: meta,
      );
      if (id > 0) inserted++;
    }
    return inserted;
  }
}

/// 文档得分辅助类
class _DocScore {
  final String docKey;
  final double score;
  _DocScore(this.docKey, this.score);
}
