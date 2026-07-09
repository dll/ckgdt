import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/error_handler.dart';
import 'course_template_registry.dart';
import 'resource_persistence_service.dart';

/// 课程数据统一入口 — 从 data/{courseId}/ 或 Gitee 仓库动态加载所有课程资源
/// 优先级：本地 assets → 本地文档目录 → Gitee 远程仓库
class CourseDataService {
  static final CourseDataService instance = CourseDataService._();
  CourseDataService._();

  /// 缓存：courseId → 数据包
  final Map<String, CourseDataPackage> _cache = {};

  /// 获取课程数据包（带缓存）
  Future<CourseDataPackage> getPackage(String courseId) async {
    if (_cache.containsKey(courseId)) return _cache[courseId]!;
    final pkg = await _loadPackage(courseId);
    _cache[courseId] = pkg;
    return pkg;
  }

  /// 清除缓存（切换课程时调用）
  void invalidate(String courseId) => _cache.remove(courseId);

  Future<CourseDataPackage> _loadPackage(String courseId) async {
    try {
      // 1) 尝试从本地 assets 加载
      final manifest = await _loadJson('data/$courseId/配置/manifest.json');
      if (manifest != null) {
        return await _loadFromAssets(courseId, manifest);
      }

      // 2) 尝试从本地文档目录加载（之前生成的课程）
      final localPkg = await _loadFromLocalDir(courseId);
      if (localPkg != null) return localPkg;

      // 3) 尝试从 Gitee 拉取
      final remotePkg = await _loadFromGitee(courseId);
      if (remotePkg != null) return remotePkg;

      return CourseDataPackage.empty(courseId);
    } catch (e, st) {
      swallowDebug(e,
          tag: 'CourseDataService._loadPackage.$courseId', stack: st);
      return CourseDataPackage.empty(courseId);
    }
  }

  /// 从 Flutter assets 加载（内置课程如 CKGDT）
  Future<CourseDataPackage> _loadFromAssets(
      String courseId, Map<String, dynamic> manifest) async {
    final chaptersRaw = await _loadJsonList('data/$courseId/配置/chapters.json');
    final chapters =
        chaptersRaw?.map((e) => ChapterDef.fromMap(e)).toList() ?? [];
    final quizFiles = await _scanMdFiles(courseId, '理论', r'-测验\.md$');
    final videoFiles = await _scanMdFiles(courseId, '视频', r'-视频脚本\.md$');
    final pptFiles = await _scanMdFiles(courseId, '课件', r'\.md$',
        exclude: r'第.*章.*\d+\.md$');
    final graphDirs = await _scanGraphDirs(courseId);
    final usersManifest = await _loadJson('data/$courseId/配置/mock_data.json');
    final courseTemplate = await _loadJson(
      'data/$courseId/配置/course_template.json',
    );
    final courseProfile = await _loadJson(
      'data/$courseId/配置/course_profile.json',
    );

    return CourseDataPackage(
      courseId: courseId,
      manifest: _manifestWithTemplate(
        manifest: manifest,
        courseTemplate: courseTemplate,
        courseProfile: courseProfile,
      ),
      chapters: chapters,
      quizFiles: quizFiles,
      videoFiles: videoFiles,
      pptFiles: pptFiles,
      graphDirs: graphDirs,
      extraConfig: usersManifest,
      courseTemplate: _resolveCourseTemplate(
        manifest: manifest,
        courseTemplate: courseTemplate,
        courseProfile: courseProfile,
      ),
    );
  }

  /// 从本地文档目录加载（之前通过"一键生课"生成的课程）
  Future<CourseDataPackage?> _loadFromLocalDir(String courseId) async {
    try {
      final persistence = ResourcePersistenceService.instance;
      final courseDir = await persistence.getCourseDir(courseId);
      final manifestFile =
          await _loadJsonFromFile('$courseDir/配置/manifest.json');
      if (manifestFile == null) return null;

      final chaptersRaw =
          await _loadJsonListFromFile('$courseDir/配置/chapters.json');
      final chapters =
          chaptersRaw?.map((e) => ChapterDef.fromMap(e)).toList() ?? [];
      final courseTemplate =
          await _loadJsonFromFile('$courseDir/配置/course_template.json');
      final courseProfile =
          await _loadJsonFromFile('$courseDir/配置/course_profile.json');

      return CourseDataPackage(
        courseId: courseId,
        manifest: _manifestWithTemplate(
          manifest: manifestFile,
          courseTemplate: courseTemplate,
          courseProfile: courseProfile,
        ),
        chapters: chapters,
        courseTemplate: _resolveCourseTemplate(
          manifest: manifestFile,
          courseTemplate: courseTemplate,
          courseProfile: courseProfile,
        ),
        packageRootPath: courseDir,
        source: CourseSource.localDir,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseDataService', stack: st);
    }
    return null;
  }

  /// 从 Gitee 远程仓库加载
  Future<CourseDataPackage?> _loadFromGitee(String courseId) async {
    try {
      final persistence = ResourcePersistenceService.instance;
      final result = await persistence.pullFromGitee(courseId);
      if (result == null) return null;

      return CourseDataPackage(
        courseId: courseId,
        manifest: result.config,
        chapters: result.chapters.map((e) => ChapterDef.fromMap(e)).toList(),
        courseTemplate: result.courseTemplate,
        configFiles: {
          'config.json': result.config,
          'assessment.json': result.assessmentConfig,
          'achievement_calc.json': result.achievementConfig,
          'report_templates.json': result.reportTemplates,
          'lab_tasks.json': result.labTasks,
          'homework.json': result.homeworks,
          'course_profile.json': result.courseProfile,
          'platform_readiness.json': result.platformReadiness,
          'course_template.json': result.courseTemplate,
          'graphs': result.graphs,
        },
        source: CourseSource.gitee,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseDataService', stack: st);
    }
    return null;
  }

  /// 加载单个 JSON 文件
  Future<Map<String, dynamic>?> _loadJson(String path) async {
    try {
      final content = await rootBundle.loadString(path);
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 加载 JSON 数组文件
  Future<List<Map<String, dynamic>>?> _loadJsonList(String path) async {
    try {
      final content = await rootBundle.loadString(path);
      final list = jsonDecode(content) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      return null;
    }
  }

  /// 扫描目录中的 MD 文件（基于已知的章节编号模式）
  Future<List<QuizFileInfo>> _scanMdFiles(
      String courseId, String subDir, String pattern,
      {String? exclude}) async {
    final files = <QuizFileInfo>[];
    final manifestKeys = await _assetManifestKeys();
    final prefix = 'data/$courseId/$subDir/';
    final matcher = RegExp(pattern);
    final excludeMatcher = exclude == null ? null : RegExp(exclude);

    final paths = manifestKeys.where((key) {
      final decoded = _safeDecode(key);
      final normalized = decoded.startsWith(prefix) ? decoded : key;
      if (!normalized.startsWith(prefix)) return false;
      final fileName = normalized.split('/').last;
      if (!fileName.endsWith('.md')) return false;
      if (!matcher.hasMatch(fileName)) return false;
      if (excludeMatcher != null && excludeMatcher.hasMatch(fileName)) {
        return false;
      }
      return true;
    }).toList()
      ..sort(_compareChapterPath);

    for (final path in paths) {
      try {
        final content = await rootBundle.loadString(path);
        final fileName = _safeDecode(path.split('/').last);
        files.add(QuizFileInfo(
          path: path,
          chapterNumber: _extractChapterNumber(fileName),
          fileName: fileName,
          title: _extractTitle(content),
        ));
      } catch (e, st) {
        swallowDebug(e, tag: 'CourseDataService', stack: st);
      }
    }
    return files;
  }

  Future<List<String>> _assetManifestKeys() async {
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.keys.map((e) => e.toString()).toList();
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseDataService', stack: st);
    }
    return const [];
  }

  /// 扫描图谱目录
  Future<List<GraphDirInfo>> _scanGraphDirs(String courseId) async {
    final dirs = <GraphDirInfo>[];
    final manifestKeys = await _assetManifestKeys();
    final prefix = 'data/$courseId/图谱/';
    final grouped = <String, List<String>>{};

    for (final rawKey in manifestKeys) {
      final key = _safeDecode(rawKey);
      if (!key.startsWith(prefix) || !key.endsWith('.md')) continue;
      final rest = key.substring(prefix.length);
      final parts = rest.split('/');
      if (parts.length < 2) continue;
      grouped
          .putIfAbsent(parts.first, () => [])
          .add(parts.sublist(1).join('/'));
    }

    for (final entry in grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final files = entry.value..sort();
      dirs.add(GraphDirInfo(
        dirName: entry.key,
        assetPrefix: '$prefix${entry.key}',
        files: files,
      ));
    }
    return dirs;
  }

  int _compareChapterPath(String a, String b) {
    final ca = _extractChapterNumber(_safeDecode(a.split('/').last));
    final cb = _extractChapterNumber(_safeDecode(b.split('/').last));
    if (ca != cb) return ca.compareTo(cb);
    return a.compareTo(b);
  }

  int _extractChapterNumber(String fileName) {
    final digit = RegExp(r'第\s*(\d+)\s*章').firstMatch(fileName);
    if (digit != null) return int.tryParse(digit.group(1)!) ?? 0;
    final cn = RegExp(r'第\s*([一二三四五六七八九十]+)\s*章').firstMatch(fileName);
    if (cn != null) return _parseChineseNumber(cn.group(1)!);
    return 0;
  }

  int _parseChineseNumber(String raw) {
    const values = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (raw == '十') return 10;
    if (raw.startsWith('十')) {
      return 10 + (values[raw.substring(1)] ?? 0);
    }
    if (raw.contains('十')) {
      final parts = raw.split('十');
      return (values[parts.first] ?? 0) * 10 +
          (parts.length > 1 && parts.last.isNotEmpty
              ? values[parts.last] ?? 0
              : 0);
    }
    return values[raw] ?? 0;
  }

  String _safeDecode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      // AssetManifest keys are paths, not guaranteed URI strings. A literal
      // percent sign in a file name is valid and should not flood logs.
    }
    return value;
  }

  /// 从 MD 内容提取标题
  String _extractTitle(String content) {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ') && trimmed.length > 2) {
        return trimmed.substring(2).trim();
      }
    }
    return '';
  }

  /// 从文件系统加载 JSON
  Future<Map<String, dynamic>?> _loadJsonFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString(encoding: utf8);
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseDataService', stack: st);
    }
    return null;
  }

  /// 从文件系统加载 JSON 数组
  Future<List<Map<String, dynamic>>?> _loadJsonListFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString(encoding: utf8);
      final list = jsonDecode(content) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseDataService', stack: st);
    }
    return null;
  }

  Map<String, dynamic> _manifestWithTemplate({
    required Map<String, dynamic> manifest,
    Map<String, dynamic>? courseTemplate,
    Map<String, dynamic>? courseProfile,
  }) {
    final template = _resolveCourseTemplate(
      manifest: manifest,
      courseTemplate: courseTemplate,
      courseProfile: courseProfile,
    );
    return {
      ...manifest,
      'template': template,
      'template_version': template['version'],
    };
  }

  Map<String, dynamic> _resolveCourseTemplate({
    required Map<String, dynamic> manifest,
    Map<String, dynamic>? courseTemplate,
    Map<String, dynamic>? courseProfile,
  }) {
    if (courseTemplate != null && courseTemplate.isNotEmpty) {
      return courseTemplate;
    }
    final manifestTemplate = manifest['template'];
    if (manifestTemplate is Map && manifestTemplate.isNotEmpty) {
      return Map<String, dynamic>.from(manifestTemplate);
    }
    return CourseTemplateRegistry.resolve(courseProfile: courseProfile).toMap();
  }
}

/// 课程数据来源
enum CourseSource { assets, localDir, gitee }

/// 课程数据包
class CourseDataPackage {
  final String courseId;
  final Map<String, dynamic>? manifest;
  final List<ChapterDef> chapters;
  final List<QuizFileInfo> quizFiles;
  final List<QuizFileInfo> videoFiles;
  final List<QuizFileInfo> pptFiles;
  final List<GraphDirInfo> graphDirs;
  final Map<String, dynamic>? extraConfig;
  final Map<String, dynamic> courseTemplate;
  final Map<String, dynamic> configFiles;
  final String? packageRootPath;
  final CourseSource source;

  const CourseDataPackage({
    required this.courseId,
    this.manifest,
    this.chapters = const [],
    this.quizFiles = const [],
    this.videoFiles = const [],
    this.pptFiles = const [],
    this.graphDirs = const [],
    this.extraConfig,
    this.courseTemplate = const {},
    this.configFiles = const {},
    this.packageRootPath,
    this.source = CourseSource.assets,
  });

  factory CourseDataPackage.empty(String courseId) =>
      CourseDataPackage(courseId: courseId);

  /// 章节标题列表
  List<String> get chapterTitles =>
      chapters.map((c) => '第${c.number}章 ${c.title}').toList();

  /// 章节数量
  int get chapterCount => chapters.length;
}

/// 章节定义
class ChapterDef {
  final int id;
  final int number;
  final String title;
  final List<String> subChapters;
  final String color;
  final String icon;

  const ChapterDef({
    required this.id,
    required this.number,
    required this.title,
    this.subChapters = const [],
    this.color = '#667eea',
    this.icon = 'school',
  });

  factory ChapterDef.fromMap(Map<String, dynamic> m) => ChapterDef(
        id: m['id'] as int? ?? 0,
        number: m['number'] as int? ?? 0,
        title: m['title'] as String? ?? '',
        subChapters: (m['sub_chapters'] as List?)?.cast<String>() ?? [],
        color: m['color'] as String? ?? '#667eea',
        icon: m['icon'] as String? ?? 'school',
      );
}

/// MD 文件信息
class QuizFileInfo {
  final String path;
  final int chapterNumber;
  final String fileName;
  final String title;

  const QuizFileInfo({
    required this.path,
    required this.chapterNumber,
    required this.fileName,
    this.title = '',
  });
}

/// 图谱目录信息
class GraphDirInfo {
  final String dirName;
  final String assetPrefix;
  final List<String> files;

  const GraphDirInfo({
    required this.dirName,
    required this.assetPrefix,
    this.files = const [],
  });
}
