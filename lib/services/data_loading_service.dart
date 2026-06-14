import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants/app_urls.dart';
import '../data/local/database_helper.dart';
import '../data/local/quiz_dao.dart';
import '../data/local/puml_dao.dart';
import 'graph_import_service.dart';
import 'gitee_service.dart';
import 'course_resource_service.dart';
import 'course_context_service.dart';
import 'rag_bootstrap_service.dart';

/// 统一数据加载服务 — 启动时一次性初始化所有预置数据
class DataLoadingService {
  static final DataLoadingService instance = DataLoadingService._();
  factory DataLoadingService() => instance;
  DataLoadingService._();

  final QuizDao _quizDao = QuizDao();
  final PumlDao _pumlDao = PumlDao();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _dbHelper.database;
      await _loadResourceFiles();
      await _initPumlSamples();
      await _importMdGraphs();
      await _cleanEmptyGraphs();
      await _initGiteeToken();
      // 远程配置预取放后台异步执行，避免离线时阻塞启动
      unawaited(_prefetchRemoteConfigs());
      // 向量 RAG 索引后台构建（首次启动 / 版本升级时灌入 concepts/resources/questions）
      unawaited(RagBootstrapService.instance.ensureIndexed());
      debugPrint('=== DataLoadingService: Initialization complete');
    } catch (e) {
      debugPrint('=== DataLoadingService: Initialization error: $e');
    }
    _isInitialized = true;
  }

  // ── Gitee Token 自动初始化 ──────────────────────────────────────────

  /// 如果 Gitee Token 尚未配置或为旧令牌，则自动设置预置 Token
  Future<void> _initGiteeToken() async {
    try {
      final gitee = GiteeService();
      final existing = await gitee.getToken();
      if (existing == null ||
          existing.isEmpty ||
          existing == GiteeCredentials.legacyTokenForMigration) {
        await gitee.saveToken(GiteeCredentials.syncToken);
        await gitee.saveDefaultOwner('chzuczldl');
        await gitee.saveRepoPrefix('cg1-,cg2-,cg3-');
        debugPrint('=== DataLoadingService: Gitee token auto-configured');
      }
    } catch (e) {
      debugPrint('=== DataLoadingService: Gitee token init error: $e');
    }
  }

  // ── 远程配置预取 ──────────────────────────────────────────────────────

  /// 启动时异步预取远程课程配置到本地缓存（静默失败，每个调用 10 秒超时）
  Future<void> _prefetchRemoteConfigs() async {
    try {
      final resource = CourseResourceService();
      const timeout = Duration(seconds: 10);
      // 并行预取所有配置，缓存到 SharedPreferences；任一失败不影响其他
      await Future.wait([
        resource.getLabTasks().timeout(timeout, onTimeout: () => null).then(
            (_) =>
                debugPrint('=== DataLoadingService: Lab tasks config cached')),
        resource.getChapters().timeout(timeout, onTimeout: () => null).then(
            (_) =>
                debugPrint('=== DataLoadingService: Chapters config cached')),
        resource.getAssessment().timeout(timeout, onTimeout: () => null).then(
            (_) =>
                debugPrint('=== DataLoadingService: Assessment config cached')),
        resource
            .getReportTemplates()
            .timeout(timeout, onTimeout: () => null)
            .then((_) =>
                debugPrint('=== DataLoadingService: Report templates cached')),
      ]);
      debugPrint('=== DataLoadingService: Remote configs pre-fetched');
    } catch (e) {
      debugPrint(
          '=== DataLoadingService: Remote config prefetch error (non-fatal): $e');
    }
  }

  // ── 资源文件初始化（视频/PDF/PPT）────────────────────────────────────────

  /// 章节名列表（15个章节，视频/PDF/PPT 共用）
  static const _chapterNames = [
    '第一章 移动应用开发技术体系1',
    '第一章 移动应用开发技术体系2',
    '第二章 原生开发基础1',
    '第二章 原生开发基础2',
    '第三章 混合开发技术1',
    '第三章 混合开发技术2',
    '第三章 混合开发技术3',
    '第四章 小程序开发1',
    '第四章 小程序开发2',
    '第五章 华为多端应用开发1',
    '第五章 华为多端应用开发2',
    '第五章 华为多端应用开发3',
    '第六章 综合开发实践1',
    '第六章 综合开发实践2',
    '第六章 综合开发实践3',
  ];

  Future<void> _loadResourceFiles() async {
    try {
      final db = await _dbHelper.database;
      final course = await _courseContext.getActiveCourse();
      final courseId = course.id;
      if (!CourseContextService.isDefaultMobileCourseName(course.name)) {
        debugPrint(
            '=== DataLoadingService: Skip default mobile resources for ${course.name}');
        return;
      }

      // 计算课件根目录：基于可执行文件所在目录向上查找 data/ 文件夹
      final dataDir = _resolveDataDir();
      final videoDir = '$dataDir/视频';
      final pdfDir = '$dataDir/课件/清言智谱';
      final pptDir = '$dataDir/课件/秒出PPT';

      debugPrint('=== DataLoadingService: Resolved dataDir=$dataDir');
      debugPrint('=== DataLoadingService: videoDir=$videoDir');

      // 检查是否已有数据 且 路径正确（包含当前 dataDir 前缀）
      final existing = await db.rawQuery(
          "SELECT COUNT(*) as c FROM resource_files WHERE course_id = ? OR course_id IS NULL OR course_id = ''",
          [courseId]);
      final count = existing.first['c'] as int? ?? 0;

      if (count > 0) {
        // 取一行样本检查路径是否和当前 dataDir 一致
        final sample = await db.rawQuery(
            "SELECT file_path FROM resource_files WHERE (course_id = ? OR course_id IS NULL OR course_id = '') AND file_path IS NOT NULL AND file_path != '' LIMIT 1",
            [courseId]);
        final samplePath = sample.isNotEmpty
            ? (sample.first['file_path'] as String? ?? '')
            : '';
        if (samplePath.isEmpty) {
          debugPrint(
              '=== DataLoadingService: resource_files has $count generated rows without local paths, keep as-is');
          return;
        }
        if (samplePath.startsWith(dataDir)) {
          debugPrint(
              '=== DataLoadingService: resource_files paths OK ($count rows, prefix=$dataDir)');
          return;
        }
        debugPrint(
            '=== DataLoadingService: Paths mismatch! sample=$samplePath, expected prefix=$dataDir');
      }

      // 仅清理旧版预置资源的本地路径，不删除其它课程由 AI/大纲生成的资源条目。
      await db.delete(
        'resource_files',
        where:
            "source_type = 'preset' AND (course_id = ? OR course_id IS NULL OR course_id = '') AND file_path IS NOT NULL AND file_path != ''",
        whereArgs: [courseId],
      );
      debugPrint(
          '=== DataLoadingService: Cleared stale preset resource paths, preserving generated course resources');

      final batch = db.batch();

      for (final chapter in _chapterNames) {
        // 视频
        batch.insert('resource_files', {
          'course_id': courseId,
          'file_name': '$chapter.mp4',
          'file_path': '$videoDir/$chapter.mp4',
          'file_type': 'video',
          'chapter': chapter,
          'description': '视频教程',
          'source_type': 'preset',
        });

        // PDF
        batch.insert('resource_files', {
          'course_id': courseId,
          'file_name': '$chapter.pdf',
          'file_path': '$pdfDir/$chapter.pdf',
          'file_type': 'pdf',
          'chapter': chapter,
          'description': '$chapter 课件',
          'source_type': 'preset',
        });

        // PPT
        batch.insert('resource_files', {
          'course_id': courseId,
          'file_name': '$chapter.pptx',
          'file_path': '$pptDir/$chapter.pptx',
          'file_type': 'ppt',
          'chapter': chapter,
          'description': '$chapter 课件',
          'source_type': 'preset',
        });
      }

      await batch.commit(noResult: true);
      debugPrint(
          '=== DataLoadingService: Inserted ${_chapterNames.length * 3} resource files');

      // 验证插入结果
      final verify = await db.rawQuery(
          "SELECT file_path FROM resource_files WHERE course_id = ? LIMIT 1",
          [courseId]);
      if (verify.isNotEmpty) {
        debugPrint(
            '=== DataLoadingService: Verify → ${verify.first['file_path']}');
      }
    } catch (e) {
      debugPrint('=== DataLoadingService: Error loading resource files: $e');
    }
  }

  /// 解析课件 data 目录的绝对路径
  /// 优先查找可执行文件同级或上级的 data/ 文件夹
  static String _resolveDataDir() {
    if (kIsWeb) return 'data';
    try {
      // 可执行文件所在目录
      final exeDir =
          File(Platform.resolvedExecutable).parent.path.replaceAll('\\', '/');

      // 策略 1: 开发模式 — 项目根目录/data
      // 从 exe 目录向上查找 data/ 文件夹
      var dir = exeDir;
      for (var i = 0; i < 6; i++) {
        final candidate = '$dir/data';
        if (Directory(candidate).existsSync() &&
            (Directory('$candidate/视频').existsSync() ||
                Directory('$candidate/课件').existsSync())) {
          debugPrint('=== DataLoadingService: Found data dir: $candidate');
          return candidate;
        }
        final parent = Directory(dir).parent.path.replaceAll('\\', '/');
        if (parent == dir) break; // 到达根目录
        dir = parent;
      }

      // 策略 2: 发布模式 — exe 同级 data/
      final fallback = '$exeDir/data';
      debugPrint('=== DataLoadingService: Using fallback data dir: $fallback');
      return fallback;
    } catch (e) {
      debugPrint('=== DataLoadingService: _resolveDataDir error: $e');
      return 'data';
    }
  }

  // ── PUML 样例初始化 ──────────────────────────────────────────────────────

  Future<void> _initPumlSamples() async {
    try {
      await _pumlDao.initSamples();
    } catch (e) {
      debugPrint('=== DataLoadingService: Error initializing PUML samples: $e');
    }
  }

  // ── 导入 Markdown 图谱 ──────────────────────────────────────────────────

  Future<void> _importMdGraphs() async {
    try {
      await GraphImportService.instance.importAll();
    } catch (e) {
      debugPrint('=== DataLoadingService: Error importing MD graphs: $e');
    }
  }

  // ── 清理空图谱 ──────────────────────────────────────────────────────────

  Future<void> _cleanEmptyGraphs() async {
    try {
      final db = await _dbHelper.database;

      // 1) 删除没有任何节点的图谱（空壳数据）
      final emptyGraphs = await db.rawQuery('''
        SELECT g.id FROM graphs g
        LEFT JOIN nodes n ON n.graph_id = g.id
        GROUP BY g.id
        HAVING COUNT(n.id) = 0
      ''');
      if (emptyGraphs.isNotEmpty) {
        final ids = emptyGraphs.map((r) => r['id']).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        final deleted = await db.rawDelete(
            'DELETE FROM graphs WHERE id IN ($placeholders)', ids);
        debugPrint('=== DataLoadingService: Cleaned $deleted empty graphs');
      }

      // 2) 删除非 md_import 类型的旧图谱（保留 md_import 图谱为唯一数据源）
      final oldGraphs = await db.rawQuery('''
        SELECT g.id FROM graphs g
        WHERE (g.graph_type != 'md_import' OR g.graph_type IS NULL)
          AND (g.course_id = 'mad' OR g.course_id IS NULL OR g.course_id = '')
          AND g.id NOT LIKE 'g_%'
      ''');
      if (oldGraphs.isNotEmpty) {
        final ids = oldGraphs.map((r) => r['id']).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        // 先删除关联的节点和边
        await db.rawDelete(
            'DELETE FROM edges WHERE graph_id IN ($placeholders)', ids);
        await db.rawDelete(
            'DELETE FROM nodes WHERE graph_id IN ($placeholders)', ids);
        final deleted = await db.rawDelete(
            'DELETE FROM graphs WHERE id IN ($placeholders)', ids);
        debugPrint(
            '=== DataLoadingService: Cleaned $deleted old non-md_import graphs');
      }
    } catch (e) {
      debugPrint('=== DataLoadingService: Error cleaning graphs: $e');
    }
  }

  // ── 查询接口 ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getVideos() async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'file_type = ?',
      extraArgs: ['video'],
    );
    return await db.query(
      'resource_files',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'chapter',
    );
  }

  Future<List<Map<String, dynamic>>> getDocuments({String? type}) async {
    final db = await _dbHelper.database;
    if (type != null) {
      final scope = await _courseContext.scopedWhere(
        extraWhere: 'file_type = ?',
        extraArgs: [type],
      );
      return await db.query(
        'resource_files',
        where: scope.where,
        whereArgs: scope.args,
        orderBy: 'chapter',
      );
    }
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'file_type IN (?, ?)',
      extraArgs: ['pdf', 'ppt'],
    );
    return await db.query(
      'resource_files',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'file_type, chapter',
    );
  }

  Future<List<String>> getChapters() async {
    return await _quizDao.getChapters();
  }
}
