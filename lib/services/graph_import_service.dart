import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import 'course_context_service.dart';
import 'course_data_service.dart';

/// 从 assets/graphs/ 目录导入 Markdown 图谱文件到 SQLite
class GraphImportService {
  static final GraphImportService instance = GraphImportService._();
  GraphImportService._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  /// 从 data/{courseId}/配置/graph_categories.json 动态加载分类
  Future<List<_Category>> _getCategories(String courseId) async {
    try {
      final content = await rootBundle.loadString('data/$courseId/配置/graph_categories.json');
      final data = jsonDecode(content) as Map<String, dynamic>;
      final cats = data['categories'] as List? ?? [];
      return cats.map((c) => _Category(
        c['dir'] as String,
        c['label'] as String,
        c['color'] as String? ?? '#667eea',
      )).toList();
    } catch (_) {
      // 回退：从 chapters.json 动态生成分类
      return _generateCategoriesFromChapters(courseId);
    }
  }

  /// 从 chapters.json 动态生成图谱分类（回退方案）
  Future<List<_Category>> _generateCategoriesFromChapters(String courseId) async {
    final pkg = await CourseDataService.instance.getPackage(courseId);
    if (pkg.chapters.isEmpty) return [];
    final cats = <_Category>[];
    final colors = ['#E53935', '#1E88E5', '#FB8C00', '#43A047', '#8E24AA', '#00897B', '#C62828', '#5C6BC0'];
    for (var i = 0; i < pkg.chapters.length && i < 8; i++) {
      final ch = pkg.chapters[i];
      final dir = '${(i + 1).toString().padLeft(2, '0')}-${ch.title}图谱';
      cats.add(_Category(dir, '${ch.title}图谱', colors[i % colors.length]));
    }
    return cats;
  }

  /// 从 data/{courseId}/配置/graph_categories.json 动态加载交叉引用
  Future<List<_CrossRef>> _getCrossRefs(String courseId) async {
    try {
      final content = await rootBundle.loadString('data/$courseId/配置/graph_categories.json');
      final data = jsonDecode(content) as Map<String, dynamic>;
      final refs = data['cross_refs'] as List? ?? [];
      return refs.map((r) => _CrossRef(
        r['from'] as String,
        r['to'] as String,
        r['type'] as String? ?? 'related',
        r['label'] as String? ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// 从 graph_categories.json 或 chapters.json 动态加载分类对应的 MD 文件列表
  Future<List<String>> _getCategoryFiles(String courseId, String dir) async {
    return _categoryFilesForCourse(courseId)[dir] ?? [];
  }

  /// 获取资产路径前缀
  String _getAssetPrefix(String courseId) {
    return courseId == 'ckgdt' ? 'assets/graphs/ckgdt' : 'assets/graphs';
  }

  /// 入口方法：检查并导入全部图谱
  Future<void> importAll() async {
    final db = await _dbHelper.database;
    final course = await _courseContext.getActiveCourse();

    // 检查是否已导入（用 graph_type='md_import' 标记）
    final scope = await _courseContext.scopedWhere();
    final existing = await db.rawQuery(
      "SELECT COUNT(*) as c FROM graphs WHERE graph_type = 'md_import' AND ${scope.where}",
      scope.args,
    );
    final count = (existing.first['c'] as int?) ?? 0;
    if (count > 0) {
      debugPrint(
          '=== GraphImportService: Already imported $count MD graphs, skip');
      return;
    }

    debugPrint('=== GraphImportService: Starting import of MD graphs...');

    final courseId = course.id;
    final categories = await _getCategories(courseId);
    final crossRefs = await _getCrossRefs(courseId);

    // 1) 创建总图谱（包含所有分类的根图谱）
    await _importMainGraph(db, courseId, course.name, categories);

    // 2) 为每个分类创建详细图谱
    for (final cat in categories) {
      await _importCategoryGraph(db, cat, courseId);
    }

    // 3) 创建分类间交叉引用边
    await _importCrossRefs(db, courseId, crossRefs);

    debugPrint('=== GraphImportService: Import complete');
  }

  // ── 总图谱 ──────────────────────────────────────────────────────────────

  Future<void> _importMainGraph(
      Database db, String courseId, String courseName, List<_Category> categories) async {
    const graphId = 'graph_main_overview';
    const rootId = 'node_root_main';

    // 插入图谱记录
    await db.insert(
        'graphs',
        {
          'id': graphId,
          'title': '$courseName课程总图谱',
          'course_id': courseId,
          'graph_type': 'md_import',
          'layout': 'tree',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    // 根节点
    await _insertNode(db, rootId, graphId, '课程：$courseName', '', 'root', 0,
        color: '#2E7D32');

    // 分类节点 + 边
    for (var i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final catNodeId = 'node_cat_${cat.dir}';
      await _insertNode(db, catNodeId, graphId, cat.label, '', 'category', 1,
          color: cat.color, parentId: rootId);
      await _insertEdge(
          db, 'edge_main_$i', graphId, rootId, catNodeId, 'contains', '包含');

      // 加载该分类下的 MD 文件名作为子节点
      final fileNames = await _listMdFiles(cat.dir);
      for (var j = 0; j < fileNames.length; j++) {
        final fileName = fileNames[j];
        final fileTitle = fileName.replaceAll('.md', '');
        final fileNodeId = 'node_file_${cat.dir}_$j';
        await _insertNode(db, fileNodeId, graphId, fileTitle, '', 'file', 2,
            color: cat.color, parentId: catNodeId);
        await _insertEdge(db, 'edge_cat${i}_file$j', graphId, catNodeId,
            fileNodeId, 'contains', '包含');
      }
    }

    debugPrint('=== GraphImportService: Main overview graph created');
  }

  // ── 分类详细图谱 ────────────────────────────────────────────────────────

  Future<void> _importCategoryGraph(
      Database db, _Category cat, String courseId) async {
    final graphId = 'graph_detail_${cat.dir}';

    await db.insert(
        'graphs',
        {
          'id': graphId,
          'title': '${cat.label}详细图谱',
          'course_id': courseId,
          'graph_type': 'md_import',
          'layout': 'tree',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    // 分类根节点
    final catRootId = 'node_${cat.dir}_root';
    await _insertNode(db, catRootId, graphId, cat.label, '', 'root', 0,
        color: cat.color);

    // 加载并解析每个 MD 文件
    final assetPrefix = _getAssetPrefix(courseId);
    final fileNames = await _getCategoryFiles(courseId, cat.dir);
    for (var fi = 0; fi < fileNames.length; fi++) {
      final fileName = fileNames[fi];
      final fileTitle = fileName.replaceAll('.md', '');
      final fileNodeId = 'node_${cat.dir}_f$fi';

      try {
        final content =
            await rootBundle.loadString('$assetPrefix/${cat.dir}/$fileName');
        final sections = _parseMdSections(content);

        // 文件节点
        await _insertNode(db, fileNodeId, graphId, fileTitle,
            sections.isEmpty ? '' : sections.first.content, 'file', 1,
            color: cat.color, parentId: catRootId);
        await _insertEdge(db, 'edge_${cat.dir}_f$fi', graphId, catRootId,
            fileNodeId, 'contains', '包含');

        // 解析 ## 和 ### 标题为子节点（限制最多15个）
        int secIdx = 0;
        for (final sec in sections) {
          if (secIdx >= 15) break;
          if (sec.level < 2) continue; // 跳过 # 标题

          final secNodeId = 'node_${cat.dir}_f${fi}_s$secIdx';
          final parentForSec = sec.level == 2
              ? fileNodeId
              : (secIdx > 0
                  ? 'node_${cat.dir}_f${fi}_s${_findParentSection(sections, secIdx)}'
                  : fileNodeId);

          final nodeLevel = sec.level; // 2 or 3
          await _insertNode(db, secNodeId, graphId, sec.title, sec.content,
              'section', nodeLevel,
              color: _lightenColor(cat.color, nodeLevel),
              parentId: parentForSec);
          await _insertEdge(db, 'edge_${cat.dir}_f${fi}_s$secIdx', graphId,
              parentForSec, secNodeId, 'contains', '包含');
          secIdx++;
        }

        debugPrint(
            '=== GraphImportService: ${cat.dir}/$fileName → $secIdx sections');
      } catch (e) {
        debugPrint(
            '=== GraphImportService: Error loading ${cat.dir}/$fileName: $e');
      }
    }
  }

  // ── 交叉引用 ──────────────────────────────────────────────────────────

  Future<void> _importCrossRefs(
      Database db, String courseId, List<_CrossRef> crossRefs) async {
    const graphId = 'graph_main_overview';
    for (var i = 0; i < crossRefs.length; i++) {
      final ref = crossRefs[i];
      await _insertEdge(
        db,
        'edge_cross_$i',
        graphId,
        'node_cat_${ref.from}',
        'node_cat_${ref.to}',
        ref.type,
        ref.label,
        color: '#FF5722',
        style: 'dashed',
      );
    }
  }

  // ── Markdown 解析 ───────────────────────────────────────────────────────

  List<_MdSection> _parseMdSections(String content) {
    final sections = <_MdSection>[];
    final lines = const LineSplitter().convert(content);
    String currentTitle = '';
    int currentLevel = 0;
    final contentBuffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) {
        // 保存前一个 section
        if (currentTitle.isNotEmpty) {
          sections.add(_MdSection(
            title: _cleanTitle(currentTitle),
            level: currentLevel,
            content: contentBuffer.toString().trim(),
          ));
          contentBuffer.clear();
        }
        // 计算层级
        int hashes = 0;
        for (int i = 0; i < trimmed.length && trimmed[i] == '#'; i++) {
          hashes++;
        }
        currentLevel = hashes;
        currentTitle = trimmed.substring(hashes).trim();
      } else if (currentTitle.isNotEmpty) {
        // 收集内容（跳过代码块标记和空行）
        if (!trimmed.startsWith('```') && trimmed.isNotEmpty) {
          contentBuffer.writeln(trimmed);
        }
      }
    }
    // 最后一个 section
    if (currentTitle.isNotEmpty) {
      sections.add(_MdSection(
        title: _cleanTitle(currentTitle),
        level: currentLevel,
        content: contentBuffer.toString().trim(),
      ));
    }
    return sections;
  }

  /// 清理标题中的 emoji 和多余符号
  String _cleanTitle(String title) {
    // 移除常见 emoji 前缀
    return title
        .replaceAll(
            RegExp(
                r'^[📚📖🎯🔄💡🏗️✅📋🔍💻🌐📱🎓🧪⚡🛠️📊📝🎨🔧⭐🏆📦🔑💡🎪🌟🎯✨🔬📐🎭💎🔮🎲🎸🎺🎻🎹🎵]\s*'),
            '')
        .trim();
  }

  int _findParentSection(List<_MdSection> sections, int currentIdx) {
    final currentLevel = sections[currentIdx].level;
    // 向上查找第一个 level < currentLevel 的 section
    for (int i = currentIdx - 1; i >= 0; i--) {
      if (sections[i].level < currentLevel && sections[i].level >= 2) {
        // 因为 secIdx 是从 level>=2 开始计数的，需要重新计算索引
        int secCount = 0;
        for (int j = 0; j < sections.length && j < i; j++) {
          if (sections[j].level >= 2) secCount++;
        }
        return secCount;
      }
    }
    return 0;
  }

  // ── 工具方法 ────────────────────────────────────────────────────────────

  Future<List<String>> _listMdFiles(String dir) async {
    // 由于 Flutter 无法直接列出 asset 目录，使用硬编码文件列表
    return _categoryFiles[dir] ?? [];
  }

  /// 所有 MD 文件名（排除总结文件）— 默认MAD
  static const _categoryFiles = {
    '01-课程图谱': [
      '知识体系图谱.md',
      '课程目标图谱.md',
      '课程思政图谱.md',
      '学习问题图谱.md',
      '能力培养图谱.md',
    ],
    '02-技术栈图谱': [
      'Android原生开发图谱.md',
      'iOS原生开发图谱.md',
      '华为多端开发图谱.md',
      '跨平台开发图谱.md',
    ],
    '03-实验图谱': [
      '实验一 开发环境搭建.md',
      '实验二 原生应用开发.md',
      '实验三 跨平台应用开发.md',
      '实验四 微信小程序开发.md',
      '实验五 鸿蒙多端应用开发.md',
      '实验六 跨平台综合项目实战.md',
    ],
    '04-项目图谱': [
      '项目1-智慧校园生活服务平台.md',
      '项目1-个人记账应用.md',
      '项目2-在线学习辅助平台开发与整合.md',
      '项目2-在线学习平台.md',
      '项目3-智能健康运动记录平台开发与整合.md',
      '项目3-智能健康助手.md',
      '项目4-二手物品交易平台开发与整合.md',
    ],
    '05-教学图谱': [
      '教学内容体系图谱.md',
      '教学方法策略图谱.md',
      '考核实施指导图谱.md',
      '教学资源配置图谱.md',
    ],
    '06-学习图谱': [
      '学习内容导航图谱.md',
      '实验学习指导图谱.md',
      '考核应对策略图谱.md',
      '学习方法指导图谱.md',
    ],
  };

  /// CKGDT 课程文件列表
  static const _ckgdtCategoryFiles = {
    '01-课程图谱': [
      '知识体系图谱.md',
      '课程目标图谱.md',
      '学习问题图谱.md',
      '能力培养图谱.md',
    ],
    '02-平台技术图谱': [
      '知识图谱技术.md',
      '数字孪生技术.md',
      '学习分析技术.md',
      '多智能体系统.md',
    ],
    '03-实验图谱': [
      '实验一 平台基础操作.md',
      '实验二 知识图谱建模.md',
      '实验三 数字孪生场景设计.md',
      '实验四 学习分析仪表盘.md',
      '实验五 实验管理与AI批阅.md',
      '实验六 综合项目.md',
      '实验七 教师端教学管理.md',
      '实验八 学生端自主学习.md',
    ],
    '04-项目图谱': [
      '课程知识图谱构建项目.md',
      '数字孪生教学设计项目.md',
      '学习分析实践项目.md',
    ],
    '05-教学图谱': [
      '教学内容体系图谱.md',
      '教学方法策略图谱.md',
      '考核实施指导图谱.md',
      '教学资源配置图谱.md',
    ],
    '06-学习图谱': [
      '学习内容导航图谱.md',
      '实验学习指导图谱.md',
      '考核应对策略图谱.md',
      '学习方法指导图谱.md',
    ],
    '07-思政图谱': [
      '课程思政图谱.md',
    ],
  };

  /// 根据课程ID获取文件列表
  Map<String, List<String>> _categoryFilesForCourse(String courseId) {
    if (courseId == 'ckgdt') return _ckgdtCategoryFiles;
    return _categoryFiles;
  }

  Future<void> _insertNode(
    Database db,
    String id,
    String graphId,
    String title,
    String content,
    String nodeType,
    int level, {
    String color = '#667eea',
    String? parentId,
  }) async {
    await db.insert(
        'nodes',
        {
          'id': id,
          'graph_id': graphId,
          'title': title,
          'content': content.length > 500 ? content.substring(0, 500) : content,
          'node_type': nodeType,
          'level': level,
          'x': 0.0,
          'y': 0.0,
          'color': color,
          'parent_id': parentId,
          'visible': 1,
          'metadata_json': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _insertEdge(
    Database db,
    String id,
    String graphId,
    String sourceId,
    String targetId,
    String edgeType,
    String label, {
    String color = '#888888',
    String style = 'solid',
  }) async {
    await db.insert(
        'edges',
        {
          'id': id,
          'graph_id': graphId,
          'source_id': sourceId,
          'target_id': targetId,
          'edge_type': edgeType,
          'label': label,
          'weight': 1.0,
          'color': color,
          'width': edgeType == 'contains' ? 1.0 : 1.5,
          'style': style,
          'visible': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 根据层级调浅颜色
  String _lightenColor(String hexColor, int level) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      final factor = 0.15 * level;
      final nr = (r + (255 - r) * factor).clamp(0, 255).toInt();
      final ng = (g + (255 - g) * factor).clamp(0, 255).toInt();
      final nb = (b + (255 - b) * factor).clamp(0, 255).toInt();
      return '#${nr.toRadixString(16).padLeft(2, '0')}${ng.toRadixString(16).padLeft(2, '0')}${nb.toRadixString(16).padLeft(2, '0')}';
    } catch (e) {
      swallow(e, tag: 'GraphImportService._lightenHexColor');
      return hexColor;
    }
  }
}

class _Category {
  final String dir;
  final String label;
  final String color;
  const _Category(this.dir, this.label, this.color);
}

class _CrossRef {
  final String from;
  final String to;
  final String type;
  final String label;
  const _CrossRef(this.from, this.to, this.type, this.label);
}

class _MdSection {
  final String title;
  final int level;
  final String content;
  const _MdSection({
    required this.title,
    required this.level,
    required this.content,
  });
}
