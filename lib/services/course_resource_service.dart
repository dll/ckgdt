import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'gitee_service.dart';

/// 课程资源同步服务
/// 职责：
/// 1. 从 mad-data 仓库读取系统级课程配置（实验定义、模板、章节、考核方案）
/// 2. 从 chzuczldl 企业下 cg1-*/cg2-*/cg3-* 仓库读取学生项目组数据
/// 3. 本地缓存 + 版本化增量同步
class CourseResourceService {
  final GiteeService _gitee = GiteeService();

  // ── 仓库常量 ────────────────────────────────────────────────────────

  /// 系统资源仓库（mad-data — 课件数据独立仓库）
  static const String sysOwner = 'osgisOne';
  static const String sysRepo = 'mad-data';
  static const String configDir = 'course_config';

  /// 学生项目仓库所在企业
  static const String enterprise = 'chzuczldl';

  /// 学生仓库前缀分组
  static const List<String> cgPrefixes = ['cg1-', 'cg2-', 'cg3-'];

  /// 仓库路径匹配正则：cg + 1/2/3 + 可选连字符
  /// 兼容 Gitee 上 path 无连字符的情况（如 cg1cifms → 应归入 CG1 组）
  static final RegExp cgRepoPattern =
      RegExp(r'^cg([123])-?', caseSensitive: false);

  /// 从仓库 path 提取组号（1/2/3）
  static String? extractGroupNumber(String path) {
    final m = cgRepoPattern.firstMatch(path.toLowerCase());
    return m?.group(1);
  }

  /// 学生分支正则：feat- 后跟全小写拼音首字母（2~5个字母）
  /// 例: feat-cjn, feat-ldl, feat-zwq
  static final RegExp studentBranchPattern = RegExp(r'^feat-[a-z]{2,5}$');

  // ── 缓存键 ──────────────────────────────────────────────────────────

  static const _kLabTasks = 'cr_lab_tasks';
  static const _kTemplates = 'cr_report_templates';
  static const _kChapters = 'cr_chapters';
  static const _kAssessment = 'cr_assessment';
  static const _kStudentRepos = 'cr_student_repos';
  static const _kLastSync = 'cr_last_sync';

  // ══════════════════════════════════════════════════════════════════════
  // 底层：从 Gitee 读取单个文件
  // ══════════════════════════════════════════════════════════════════════

  /// 通过 Contents API 获取文件内容（自动 base64 解码）
  Future<String?> fetchFile(
    String owner,
    String repo,
    String path, {
    String ref = 'master',
  }) async {
    try {
      final token = await _gitee.getToken();
      final params = <String, String>{
        if (token != null && token.isNotEmpty) 'access_token': token,
        'ref': ref,
      };
      final uri = Uri.parse(
              'https://gitee.com/api/v5/repos/$owner/$repo/contents/$path')
          .replace(queryParameters: params);

      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        debugPrint('CourseResourceService: fetchFile $path → ${resp.statusCode}');
        return null;
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data is Map && data.containsKey('content')) {
        final b64 = (data['content'] as String).replaceAll('\n', '');
        return utf8.decode(base64Decode(b64));
      }
      return null;
    } catch (e) {
      debugPrint('CourseResourceService: fetchFile error: $e');
      return null;
    }
  }

  /// 获取目录内容列表
  Future<List<Map<String, dynamic>>?> fetchDir(
    String owner,
    String repo,
    String path, {
    String ref = 'master',
  }) async {
    try {
      final token = await _gitee.getToken();
      final params = <String, String>{
        if (token != null && token.isNotEmpty) 'access_token': token,
        'ref': ref,
      };
      final uri = Uri.parse(
              'https://gitee.com/api/v5/repos/$owner/$repo/contents/$path')
          .replace(queryParameters: params);

      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data is List) {
        return List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e)));
      }
      return null;
    } catch (e) {
      debugPrint('CourseResourceService: fetchDir error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 高层 API：系统级课程资源（从 mad-data 读取 + 本地缓存）
  // ══════════════════════════════════════════════════════════════════════

  /// 获取实验任务定义
  Future<List<Map<String, dynamic>>?> getLabTasks(
      {bool forceRefresh = false}) async {
    return _cachedJsonList(_kLabTasks, '$configDir/lab_tasks.json',
        forceRefresh: forceRefresh);
  }

  /// 获取报告模板
  Future<List<Map<String, dynamic>>?> getReportTemplates(
      {bool forceRefresh = false}) async {
    return _cachedJsonList(_kTemplates, '$configDir/report_templates.json',
        forceRefresh: forceRefresh);
  }

  /// 获取章节配置
  Future<List<Map<String, dynamic>>?> getChapters(
      {bool forceRefresh = false}) async {
    return _cachedJsonList(_kChapters, '$configDir/chapters.json',
        forceRefresh: forceRefresh);
  }

  /// 获取考核方案
  Future<Map<String, dynamic>?> getAssessment(
      {bool forceRefresh = false}) async {
    final list = await _cachedJsonList(
        _kAssessment, '$configDir/assessment.json',
        forceRefresh: forceRefresh);
    if (list != null && list.isNotEmpty) return list.first;
    return null;
  }

  /// 通用带缓存的 JSON 获取
  Future<List<Map<String, dynamic>>?> _cachedJsonList(
    String cacheKey,
    String filePath, {
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. 查缓存
    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        final parsed = _parseJsonList(cached);
        if (parsed != null) return parsed;
      }
    }

    // 2. 从 Gitee 获取
    final content = await fetchFile(sysOwner, sysRepo, filePath);
    if (content != null) {
      await prefs.setString(cacheKey, content);
      final parsed = _parseJsonList(content);
      if (parsed != null) return parsed;
    }

    // 3. 兜底：旧缓存
    final fallback = prefs.getString(cacheKey);
    if (fallback != null) return _parseJsonList(fallback);

    return null;
  }

  List<Map<String, dynamic>>? _parseJsonList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e)));
      } else if (decoded is Map) {
        return [Map<String, dynamic>.from(decoded)];
      }
    } catch (_) {}
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // 学生项目仓库（cg1-*/cg2-*/cg3-*）
  // ══════════════════════════════════════════════════════════════════════

  /// 获取企业下所有 cg 前缀的学生仓库
  Future<List<Map<String, dynamic>>> getStudentRepos({
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 缓存检查（1小时有效）
    if (!forceRefresh) {
      final cached = prefs.getString(_kStudentRepos);
      final lastSync = prefs.getString(_kLastSync);
      if (cached != null && lastSync != null) {
        final syncTime = DateTime.tryParse(lastSync);
        if (syncTime != null &&
            DateTime.now().difference(syncTime).inMinutes < 60) {
          try {
            return List<Map<String, dynamic>>.from(
                (jsonDecode(cached) as List)
                    .map((e) => Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
    }

    // 从企业 API 获取
    try {
      final token = await _gitee.getToken();
      if (token == null || token.isEmpty) return _fallbackStudentRepos(prefs);

      final uri = Uri.parse(
              'https://gitee.com/api/v5/enterprises/$enterprise/repos')
          .replace(queryParameters: {
        'access_token': token,
        'per_page': '100',
        'type': 'all',
      });

      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return _fallbackStudentRepos(prefs);

      final allRepos = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
      final cgRepos = allRepos.where((r) {
        final path = (r['path']?.toString() ?? '').toLowerCase();
        return cgRepoPattern.hasMatch(path);
      }).toList();

      final result = List<Map<String, dynamic>>.from(
          cgRepos.map((e) => Map<String, dynamic>.from(e)));

      // 缓存
      await prefs.setString(_kStudentRepos, jsonEncode(result));
      await prefs.setString(_kLastSync, DateTime.now().toIso8601String());

      return result;
    } catch (e) {
      debugPrint('CourseResourceService: getStudentRepos error: $e');
      return _fallbackStudentRepos(prefs);
    }
  }

  List<Map<String, dynamic>> _fallbackStudentRepos(SharedPreferences prefs) {
    final cached = prefs.getString(_kStudentRepos);
    if (cached != null) {
      try {
        return List<Map<String, dynamic>>.from(
            (jsonDecode(cached) as List)
                .map((e) => Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
    return [];
  }

  /// 获取仓库的学生分支（严格匹配 feat-{小写拼音首字母}，2~5个字母）
  Future<List<Map<String, dynamic>>> getStudentBranches(
      String owner, String repo) async {
    try {
      final branches = await _gitee.getBranches(owner, repo);
      return branches
          .where((b) => studentBranchPattern.hasMatch(
              b['name']?.toString() ?? ''))
          .toList();
    } catch (e) {
      debugPrint('CourseResourceService: getStudentBranches error: $e');
      return [];
    }
  }

  /// 获取指定分支的提交列表
  Future<List<Map<String, dynamic>>> getBranchCommits(
    String owner,
    String repo,
    String branch, {
    int page = 1,
    int perPage = 20,
  }) async {
    return _gitee.getCommits(owner, repo,
        sha: branch, page: page, perPage: perPage);
  }

  /// 仓库按组号分组
  Map<String, List<Map<String, dynamic>>> groupByPrefix(
      List<Map<String, dynamic>> repos) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final repo in repos) {
      final path = (repo['path']?.toString() ?? '').toLowerCase();
      final groupNum = extractGroupNumber(path);
      final group = groupNum != null ? 'CG$groupNum' : '其他';
      grouped.putIfAbsent(group, () => []).add(repo);
    }
    return Map.fromEntries(
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// 获取仓库统计汇总
  Future<Map<String, dynamic>> getRepoStats(
      String owner, String repo) async {
    try {
      final branches = await _gitee.getBranches(owner, repo);
      final feats = branches
          .where((b) => studentBranchPattern.hasMatch(
              b['name']?.toString() ?? ''))
          .toList();

      return {
        'total_branches': branches.length,
        'student_branches': feats.length,
        'student_names': feats.map((b) => b['name']).toList(),
      };
    } catch (e) {
      return {'total_branches': 0, 'student_branches': 0, 'student_names': []};
    }
  }

  // ── 缓存管理 ────────────────────────────────────────────────────────

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _kLabTasks, _kTemplates, _kChapters, _kAssessment,
      _kStudentRepos, _kLastSync,
    ]) {
      await prefs.remove(key);
    }
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kLastSync);
    return str != null ? DateTime.tryParse(str) : null;
  }
}
