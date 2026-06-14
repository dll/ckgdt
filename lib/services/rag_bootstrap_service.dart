import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/database_helper.dart';
import '../data/local/rag_embedding_dao.dart';
import 'course_context_service.dart';
import 'rag_service.dart';

/// 向量 RAG 启动初始化器。
///
/// **第二轮 + 第三轮审核背景**：rag_embeddings 表建好了，retrieveContextVector
/// 接进了 BaseAgent，但全项目无 indexDocument 调用方 → 表永远是空的，
/// BaseAgent 走向量分支永远立即 fallback 到 TF-IDF。本服务把"灌索引"
/// 接通：
///
/// 1. App 启动后 [DataLoadingService.initialize] 后台 unawaited 调用
/// 2. 守卫：rag_embeddings 已有数据则跳过（等 [bumpVersionToReindex] 主动触发）
/// 3. 数据源：knowledge_concepts（语义图谱）+ resource_files（章节资料）+
///    questions（测验题）—— 选择"教学最常被问"的三类
///
/// **代价提示**：每次重新索引会发起 N 次 embed http 请求；本地 ollama < 1s/条，
/// 远程 GLM 智谱可能 < 200ms/条。教学场景文档 < 500 条，全量重建 < 2 分钟。
class RagBootstrapService {
  RagBootstrapService._();
  static final RagBootstrapService instance = RagBootstrapService._();

  static const _prefIndexedVersion = 'rag_bootstrap.indexed_version';

  /// 当前索引版本号。每次"种子内容有结构性变化"时手工 +1 触发重建。
  /// 历史值：v1 = 初始（concepts + resources + questions 三类）。
  static const _indexedVersion = 1;

  bool _running = false;
  final CourseContextService _courseContext = CourseContextService();

  /// 入口：首次启动 / 版本号升级时构建向量索引；其余情况直接返回。
  ///
  /// **可重入安全**：用 [_running] 标志防多次并发；用 SharedPreferences
  /// 防版本号重复入库。
  Future<void> ensureIndexed() async {
    if (_running) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final courseId = await _courseContext.activeCourseId();
      final prefKey = '$_prefIndexedVersion.$courseId';
      final lastIndexed = prefs.getInt(prefKey) ?? 0;
      final existing = await RagEmbeddingDao.instance.count();

      // 已有数据 + 版本一致 → 跳过
      if (existing > 0 && lastIndexed >= _indexedVersion) {
        debugPrint('=== RagBootstrap: skip ($existing chunks, v$lastIndexed)');
        return;
      }

      debugPrint(
          '=== RagBootstrap: indexing (v$lastIndexed → v$_indexedVersion)…');
      final rag = RagService();

      // 三类源相互独立 + embedBatch 是 HTTP 瓶颈 → 并行起跑，整体耗时从串行 ~2min
      // 缩到 ~40-60s。RagEmbeddingDao 的写入由 sqflite 单连接序列化，并发安全。
      final counts = await Future.wait([
        _indexConcepts(rag),
        _indexResources(rag),
        _indexQuestions(rag),
      ]);
      final totalChunks = counts.fold<int>(0, (a, b) => a + b);

      await prefs.setInt(prefKey, _indexedVersion);
      debugPrint('=== RagBootstrap: indexed $totalChunks chunks total');
    } catch (e) {
      debugPrint('=== RagBootstrap: failed (non-fatal): $e');
    } finally {
      _running = false;
    }
  }

  /// 主动触发重建（清空索引 + 重新 embed），用于：
  /// - 一键生课后切换课程
  /// - 课程资料大批量更新
  /// - 调试时验证向量检索效果
  Future<int> bumpVersionToReindex() async {
    final prefs = await SharedPreferences.getInstance();
    final courseId = await _courseContext.activeCourseId();
    await prefs.remove('$_prefIndexedVersion.$courseId');
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'rag_embeddings',
      where: 'doc_id LIKE ?',
      whereArgs: ['$courseId:%'],
    );
    await ensureIndexed();
    return await RagEmbeddingDao.instance.count();
  }

  // ── 内部：按数据源切片 ──────────────────────────────────────────────

  Future<int> _indexConcepts(RagService rag) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final scope = await _courseContext.scopedWhere();
      final rows = await db.query(
        'knowledge_concepts',
        where: scope.where,
        whereArgs: scope.args,
        orderBy: 'chapter, id',
        limit: 500,
      );
      if (rows.isEmpty) return 0;
      final buf = StringBuffer();
      for (final r in rows) {
        final name = r['concept_name'] ?? r['name'] ?? '';
        final desc = r['description']?.toString() ?? '';
        final ch = r['chapter'];
        buf.writeln('## $name${ch != null ? '（第$ch章）' : ''}');
        if (desc.isNotEmpty) buf.writeln(desc);
        buf.writeln();
      }
      final courseId = await _courseContext.activeCourseId();
      return await rag.indexDocument(
        docId: '$courseId:concepts',
        content: buf.toString(),
        chunkSize: 500,
        overlap: 50,
        meta: 'knowledge_concepts',
      );
    } catch (e) {
      debugPrint('=== RagBootstrap: indexConcepts failed: $e');
      return 0;
    }
  }

  Future<int> _indexResources(RagService rag) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final scope = await _courseContext.scopedWhere(
        // SQL 标准：双引号是标识符，空字符串必须用单引号（'' 而非 ""）。
        // sqflite_common_ffi (桌面/Web) 严格按标准；不要回写 ""。
        extraWhere: "description IS NOT NULL AND description != ''",
      );
      final rows = await db.query(
        'resource_files',
        where: scope.where,
        whereArgs: scope.args,
        orderBy: 'chapter, file_type',
        limit: 500,
      );
      if (rows.isEmpty) return 0;
      final buf = StringBuffer();
      for (final r in rows) {
        final name = r['file_name'] ?? '';
        final ch = r['chapter'] ?? '';
        final type = r['file_type'] ?? '';
        final desc = r['description'] ?? '';
        buf.writeln('## $name [$type] - $ch');
        buf.writeln(desc);
        buf.writeln();
      }
      final courseId = await _courseContext.activeCourseId();
      return await rag.indexDocument(
        docId: '$courseId:resources',
        content: buf.toString(),
        chunkSize: 400,
        overlap: 40,
        meta: 'resource_files',
      );
    } catch (e) {
      debugPrint('=== RagBootstrap: indexResources failed: $e');
      return 0;
    }
  }

  Future<int> _indexQuestions(RagService rag) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final scope = await _courseContext.scopedWhere();
      final rows = await db.query(
        'questions',
        where: scope.where,
        whereArgs: scope.args,
        orderBy: 'source, id',
        limit: 500,
      );
      if (rows.isEmpty) return 0;
      final buf = StringBuffer();
      for (final r in rows) {
        final src = r['source'] ?? '';
        final q = r['question'] ?? '';
        final a = r['option_a'] ?? '';
        final b = r['option_b'] ?? '';
        final c = r['option_c'] ?? '';
        final d = r['option_d'] ?? '';
        final idx = r['answer_index'] ?? 0;
        final correct = [a, b, c, d][(idx as int).clamp(0, 3)];
        buf.writeln('## [$src] $q');
        buf.writeln('A. $a / B. $b / C. $c / D. $d');
        buf.writeln('正确答案: $correct');
        buf.writeln();
      }
      final courseId = await _courseContext.activeCourseId();
      return await rag.indexDocument(
        docId: '$courseId:questions',
        content: buf.toString(),
        chunkSize: 600,
        overlap: 60,
        meta: 'questions',
      );
    } catch (e) {
      debugPrint('=== RagBootstrap: indexQuestions failed: $e');
      return 0;
    }
  }
}
