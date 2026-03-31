import 'package:flutter/foundation.dart';
import '../data/local/database_helper.dart';
import '../data/local/quiz_dao.dart';
import '../data/local/puml_dao.dart';
import 'graph_import_service.dart';

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
      await _initPumlSamples();
      await _importMdGraphs();
      await _cleanEmptyGraphs();
      debugPrint('=== DataLoadingService: Initialization complete');
    } catch (e) {
      debugPrint('=== DataLoadingService: Initialization error: $e');
    }
    _isInitialized = true;
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

      // 检查是否已有数据
      final existing = await db.rawQuery(
          'SELECT COUNT(*) as c FROM resource_files');
      final count = existing.first['c'] as int? ?? 0;
      if (count > 0) {
        debugPrint('=== DataLoadingService: resource_files already has $count rows, skip');
        return;
      }

      debugPrint('=== DataLoadingService: Inserting resource files...');
      final batch = db.batch();

      for (final chapter in _chapterNames) {
        // 视频
        batch.insert('resource_files', {
          'file_name': '$chapter.mp4',
          'file_path': 'assets/video/$chapter.mp4',
          'file_type': 'video',
          'chapter': chapter,
          'description': '视频教程',
        });

        // PDF
        batch.insert('resource_files', {
          'file_name': '$chapter.pdf',
          'file_path': 'assets/清言智谱/$chapter.pdf',
          'file_type': 'pdf',
          'chapter': chapter,
          'description': '$chapter 课件',
        });

        // PPT
        batch.insert('resource_files', {
          'file_name': '$chapter.pptx',
          'file_path': 'assets/秒出PPT/$chapter.pptx',
          'file_type': 'ppt',
          'chapter': chapter,
          'description': '$chapter 课件',
        });
      }

      await batch.commit(noResult: true);
      debugPrint('=== DataLoadingService: Inserted ${_chapterNames.length * 3} resource files');
    } catch (e) {
      debugPrint('=== DataLoadingService: Error loading resource files: $e');
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
        final ids = emptyGraphs.map((r) => "'${r['id']}'").join(',');
        final deleted = await db.rawDelete('DELETE FROM graphs WHERE id IN ($ids)');
        debugPrint('=== DataLoadingService: Cleaned $deleted empty graphs');
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
        final deleted = await db.rawDelete('DELETE FROM graphs WHERE id IN ($ids)');
        debugPrint('=== DataLoadingService: Cleaned $deleted old non-md_import graphs');
      }
    } catch (e) {
      debugPrint('=== DataLoadingService: Error cleaning graphs: $e');
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
