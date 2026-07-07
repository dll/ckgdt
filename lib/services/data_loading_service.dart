import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/init_logger.dart';
import '../data/local/database_helper.dart';
import '../data/local/quiz_dao.dart';
import '../data/local/puml_dao.dart';
import '../data/local/homework_dao.dart';
import 'course_context_service.dart';
import 'graph_import_service.dart';
import 'course_package_loader.dart';
import 'ckgdt_quiz_importer.dart';
import 'ckgdt_resource_importer.dart';
import 'gitee_service.dart';
import 'course_resource_service.dart';

/// 统一数据加载服务 — 启动时一次性初始化所有预置数据
class DataLoadingService {
  static final DataLoadingService instance = DataLoadingService._();
  factory DataLoadingService() => instance;
  DataLoadingService._();

  final QuizDao _quizDao = QuizDao();
  final PumlDao _pumlDao = PumlDao();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _dbHelper.database;
      await _loadResourceFiles();
      await _importActiveCoursePackage();
      await _importCkgdtResources();
      await _initPumlSamples();
      await _importMdGraphs();
      await _importCkgdtQuizzes();
      await _cleanEmptyGraphs();
      await _initGiteeToken();
      await _prefetchRemoteConfigs();
      InitLogger.log('ds', 'Initialization complete');
    } catch (e, st) {
      InitLogger.error('ds', 'Initialization error: $e', st);
    }
    _isInitialized = true;
  }

  // ── Gitee Token 自动初始化 ──────────────────────────────────────────

  /// 如果 Gitee Token 尚未配置，提示用户在设置中配置
  Future<void> _initGiteeToken() async {
    try {
      final gitee = GiteeService();
      final existing = await gitee.getToken();
      if (existing == null || existing.isEmpty) {
        InitLogger.log('ds', 'Gitee token not configured, sync disabled');
      }
    } catch (e) {
      InitLogger.log('ds', 'Gitee token check error: $e');
    }
  }

  // ── 远程配置预取 ──────────────────────────────────────────────────────

  /// 启动时异步预取远程课程配置到本地缓存（静默失败，不阻塞启动流程）
  Future<void> _prefetchRemoteConfigs() async {
    try {
      final resource = CourseResourceService();
      // 并行预取所有配置，缓存到 SharedPreferences
      await Future.wait([
        resource.getLabTasks().then((_) =>
            InitLogger.log('ds', 'Lab tasks config cached')),
        resource.getChapters().then((_) =>
            InitLogger.log('ds', 'Chapters config cached')),
        resource.getAssessment().then((_) =>
            InitLogger.log('ds', 'Assessment config cached')),
        resource.getReportTemplates().then((_) =>
            InitLogger.log('ds', 'Report templates cached')),
      ]);
      InitLogger.log('ds', 'Remote configs pre-fetched');
    } catch (e) {
      InitLogger.log('ds', 'Remote config prefetch error (non-fatal): $e');
    }
  }

  // ── 资源文件初始化（视频/PDF/PPT）────────────────────────────────────────

  /// 每章子部分数（视频/PDF/PPT 按章节生成子条目）
  static const _subPartCounts = [2, 2, 3, 2, 3, 3];

  Future<void> _loadResourceFiles() async {
    try {
      final db = await _dbHelper.database;

      // 计算课件根目录：基于可执行文件所在目录向上查找 data/ 文件夹
      final dataDir = _resolveDataDir();
      final videoDir = '$dataDir/视频';
      final pdfDir = '$dataDir/课件/清言智谱';
      final pptDir = '$dataDir/课件/秒出PPT';

      InitLogger.log('ds', 'Resolved dataDir=$dataDir');
      InitLogger.log('ds', 'videoDir=$videoDir');

      // 检查是否已有数据 且 路径正确（包含当前 dataDir 前缀）
      final existing =
          await db.rawQuery('SELECT COUNT(*) as c FROM resource_files');
      final count = existing.first['c'] as int? ?? 0;

      if (count > 0) {
        // 取一行样本检查路径是否和当前 dataDir 一致
        final sample =
            await db.rawQuery("SELECT file_path FROM resource_files LIMIT 1");
        final samplePath = sample.isNotEmpty
            ? (sample.first['file_path'] as String? ?? '')
            : '';
        if (samplePath.startsWith(dataDir)) {
          InitLogger.log('ds', 'resource_files paths OK ($count rows, prefix=$dataDir)');
          return;
        }
        InitLogger.log('ds', 'Paths mismatch! sample=$samplePath, expected prefix=$dataDir');
      }

      // 清空旧数据（无论是 assets/ 前缀还是其他错误路径）
      await db.delete('resource_files');
      InitLogger.log('ds', 'Cleared old resource_files, re-inserting with correct paths');

      // 从课程上下文动态加载章节名
      final courseCtx = CourseContextService();
      final chapterTitles = await courseCtx.chapterTitles();
      final chapterNames = <String>[];
      for (var i = 0;
          i < chapterTitles.length && i < _subPartCounts.length;
          i++) {
        for (var p = 1; p <= _subPartCounts[i]; p++) {
          chapterNames.add('${chapterTitles[i]}$p');
        }
      }
      if (chapterNames.isEmpty) {
        InitLogger.log('ds', 'No chapters from course context, skipping resource insert');
        return;
      }

      final batch = db.batch();

      for (final chapter in chapterNames) {
        // 视频
        batch.insert('resource_files', {
          'file_name': '$chapter.mp4',
          'file_path': '$videoDir/$chapter.mp4',
          'file_type': 'video',
          'chapter': chapter,
          'description': '视频教程',
          'source_type': 'preset',
        });

        // PDF
        batch.insert('resource_files', {
          'file_name': '$chapter.pdf',
          'file_path': '$pdfDir/$chapter.pdf',
          'file_type': 'pdf',
          'chapter': chapter,
          'description': '$chapter 课件',
          'source_type': 'preset',
        });

        // PPT
        batch.insert('resource_files', {
          'file_name': '$chapter.pptx',
          'file_path': '$pptDir/$chapter.pptx',
          'file_type': 'ppt',
          'chapter': chapter,
          'description': '$chapter 课件',
          'source_type': 'preset',
        });
      }

      await batch.commit(noResult: true);
      InitLogger.log('ds', 'Inserted ${chapterNames.length * 3} resource files');

      // 验证插入结果
      final verify =
          await db.rawQuery("SELECT file_path FROM resource_files LIMIT 1");
      if (verify.isNotEmpty) {
        InitLogger.log('ds', 'Verify → ${verify.first['file_path']}');
      }
    } catch (e) {
      InitLogger.log('ds', 'Error loading resource files: $e');
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
          InitLogger.log('ds', 'Found data dir: $candidate');
          return candidate;
        }
        final parent = Directory(dir).parent.path.replaceAll('\\', '/');
        if (parent == dir) break; // 到达根目录
        dir = parent;
      }

      // 策略 2: 发布模式 — exe 同级 data/
      final fallback = '$exeDir/data';
      InitLogger.log('ds', 'Using fallback data dir: $fallback');
      return fallback;
    } catch (e) {
      InitLogger.log('ds', '_resolveDataDir error: $e');
      return 'data';
    }
  }

  // ── PUML 样例初始化 ──────────────────────────────────────────────────────

  Future<void> _initPumlSamples() async {
    try {
      await _pumlDao.initSamples();
    } catch (e) {
      InitLogger.log('ds', 'Error initializing PUML samples: $e');
    }
  }

  // ── 导入 Markdown 图谱 ──────────────────────────────────────────────────

  Future<void> _importMdGraphs() async {
    try {
      await GraphImportService.instance.importAll();
    } catch (e) {
      InitLogger.log('ds', 'Error importing MD graphs: $e');
    }
  }

  Future<void> _importCkgdtQuizzes() async {
    try {
      await CkgdtQuizImporter.instance.importCkgdtQuizzes();
    } catch (e) {
      InitLogger.log('ds', 'Error importing CKGDT quizzes: $e');
    }
    // 导入作业数据
    await _importCkgdtHomework();
  }

  Future<void> _importCkgdtHomework() async {
    try {
      final db = await _dbHelper.database;
      // 获取当前课程 ID
      String courseId = 'ckgdt';
      try {
        courseId = await CourseContextService().activeCourseId();
      } catch (_) {}

      // 检查是否已导入
      final existing = await db.rawQuery(
        "SELECT COUNT(*) as c FROM homeworks WHERE course_id = ?",
        [courseId],
      );
      final count = (existing.first['c'] as int?) ?? 0;
      if (count > 0) return;

      // 尝试从当前课程目录读取 homework.json
      String? content;
      try {
        content = await rootBundle.loadString('data/$courseId/配置/homework.json');
      } catch (_) {
        // 回退到 CKGDT 默认目录
        try {
          content = await rootBundle.loadString('data/CKGDT/配置/homework.json');
        } catch (_) {}
      }

      if (content == null) return;

      final homeworkDao = HomeworkDao();
      final imported = await homeworkDao.importFromJson(courseId, content);
      InitLogger.log('ds', 'Imported $imported homework sets for $courseId');
    } catch (e) {
      InitLogger.log('ds', 'Error importing homework: $e');
    }
  }

  Future<void> _importActiveCoursePackage() async {
    try {
      await CoursePackageLoader.instance.importActiveCourse();
    } catch (e) {
      InitLogger.log('ds', 'Error importing course package: $e');
    }
  }

  Future<void> _importCkgdtResources() async {
    try {
      final count = await CkgdtResourceImporter.instance.importCkgdtResources();
      InitLogger.log('ds', 'Imported $count course resources');
    } catch (e) {
      InitLogger.log('ds', 'Error importing course resources: $e');
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
        final ids = emptyGraphs.map((r) => "'${r['id']}'").join(',');
        final deleted =
            await db.rawDelete('DELETE FROM graphs WHERE id IN ($ids)');
        InitLogger.log('ds', 'Cleaned $deleted empty graphs');
      }

      // 2) 删除非 md_import 类型的旧图谱（保留 md_import 图谱为唯一数据源）
      final oldGraphs = await db.rawQuery('''
        SELECT g.id FROM graphs g
        WHERE g.graph_type != 'md_import' OR g.graph_type IS NULL
      ''');
      if (oldGraphs.isNotEmpty) {
        final ids = oldGraphs.map((r) => "'${r['id']}'").join(',');
        // 先删除关联的节点和边
        await db.rawDelete('DELETE FROM edges WHERE graph_id IN ($ids)');
        await db.rawDelete('DELETE FROM nodes WHERE graph_id IN ($ids)');
        final deleted =
            await db.rawDelete('DELETE FROM graphs WHERE id IN ($ids)');
        InitLogger.log('ds', 'Cleaned $deleted old non-md_import graphs');
      }
    } catch (e) {
      InitLogger.log('ds', 'Error cleaning graphs: $e');
    }
  }

  // ── 查询接口 ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getVideos() async {
    final db = await _dbHelper.database;
    return await db.query(
      'resource_files',
      where: 'file_type = ?',
      whereArgs: ['video'],
      orderBy: 'chapter',
    );
  }

  Future<List<Map<String, dynamic>>> getDocuments({String? type}) async {
    final db = await _dbHelper.database;
    if (type != null) {
      return await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: [type],
        orderBy: 'chapter',
      );
    }
    return await db.query(
      'resource_files',
      where: 'file_type IN (?, ?)',
      whereArgs: ['pdf', 'ppt'],
      orderBy: 'file_type, chapter',
    );
  }

  Future<List<String>> getChapters() async {
    return await _quizDao.getChapters();
  }
}
