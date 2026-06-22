import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_urls.dart';
import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import 'course_context_service.dart';
import 'gitee_service.dart';

/// 数据同步服务（分组项目仓库模型）
///
/// 学生数据**分散存储**在各自的"分组项目仓库"中，不再集中到单一仓库（避免仓库膨胀）。
/// - 仓库归属：命名空间 [groupRepoOwner]（chzuczldl），仓库名来自实验分组 Excel 的
///   "仓库"列（已导入 users.repository_url，如 cg1-cifms）。
/// - 学生端：把本地学习数据写到**自己组仓库**的 `mad/{user_id}.json` + 附件
///   `mad/files/{user_id}/{分类}/...`。
/// - 教师端：遍历所有去重的组仓库，从每个仓库的 `mad/*.json` 拉取并合并到本地 DB。
/// 同步使用独立的读写 Token（sync_gitee_token），需对 chzuczldl 命名空间有写权限。
/// 通知广播 / 连接诊断仍走系统仓库 [systemRepoOwner]/[systemRepoName]（chzcldl/mad-data）。
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final GiteeService _gitee = GiteeService();

  // ── 仓库配置 ──────────────────────────────────────────────────────────

  /// 学生分组仓库默认命名空间（"仓库"列仅给裸仓库名时拼到此命名空间下）
  static const groupRepoOwner = 'chzuczldl';

  /// 组仓库内存放 App 同步数据的目录（mad/{userId}.json + mad/files/...）
  static const madDir = 'mad';

  /// 系统仓库（通知广播 / 连接诊断等非学生数据用）
  static const systemRepoOwner = 'chzcldl';
  static const systemRepoName = 'mad-data';
  static const repoBranch = 'master';

  // ── SharedPreferences 键名 ──────────────────────────────────────────

  static const _syncEnabledKey = 'sync_enabled';
  static const _syncIntervalKey = 'sync_interval_minutes';
  static const _lastUploadTimeKey = 'sync_last_upload';
  static const _lastDownloadTimeKey = 'sync_last_download';
  static const _syncTokenKey = 'sync_gitee_token';

  // ── 定时器 ──────────────────────────────────────────────────────────

  Timer? _syncTimer;
  bool _isSyncing = false;

  /// 同步状态（UI 可监听）
  final ValueNotifier<SyncStatus> status = ValueNotifier(SyncStatus.idle);

  // ── 同步专用 Token（读写权限）──────────────────────────────────────────

  /// 预置读写 Token — 集中维护在 `lib/core/constants/app_urls.dart` 的
  /// [GiteeCredentials.syncToken]。详见该常量的设计权衡说明。
  static String get _defaultSyncToken => GiteeCredentials.syncToken;

  /// 确保同步 Token 已配置（首次使用时自动设置）
  Future<void> _ensureSyncToken() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_syncTokenKey);
    final shouldResetSyncToken = existing == null ||
        existing.isEmpty ||
        existing == GiteeCredentials.legacyTokenForMigration;
    if (shouldResetSyncToken) {
      await prefs.setString(_syncTokenKey, _defaultSyncToken);
    }

    // 同时确保 GiteeService 也配置了此 Token。
    final giteeToken = await _gitee.getToken();
    if (giteeToken == null ||
        giteeToken.isEmpty ||
        giteeToken == GiteeCredentials.legacyTokenForMigration) {
      await _gitee.saveToken(_defaultSyncToken);
    }
  }

  /// 获取同步专用 Token（首次使用时自动 bootstrap，见 [_ensureSyncToken]）
  Future<String?> getSyncToken() async {
    await _ensureSyncToken();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_syncTokenKey);
  }

  /// 设置同步 Token
  Future<void> setSyncToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncTokenKey, token);
    // 也同步更新 GiteeService 的 Token
    await _gitee.saveToken(token);
  }

  // ── 配置读写（仅 开关 + 间隔）────────────────────────────────────────

  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_syncEnabledKey) ?? true;
  }

  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncEnabledKey, enabled);
  }

  Future<int> getSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_syncIntervalKey) ?? 10).clamp(5, 60);
  }

  Future<void> setSyncInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncIntervalKey, minutes);
  }

  Future<String?> getLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastUploadTimeKey);
  }

  Future<String?> getLastDownloadTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastDownloadTimeKey);
  }

  /// 获取同步配置（UI 用）
  Future<SyncConfig> getConfig() async {
    return SyncConfig(
      enabled: await isSyncEnabled(),
      intervalMinutes: await getSyncInterval(),
      lastUpload: await getLastUploadTime(),
      lastDownload: await getLastDownloadTime(),
    );
  }

  /// 保存同步配置
  Future<void> saveConfig(
      {required bool enabled, required int interval}) async {
    await setSyncEnabled(enabled);
    await setSyncInterval(interval);
  }

  // ── 定时同步控制 ──────────────────────────────────────────────────────

  /// 启动自动同步定时器
  Future<void> startAutoSync({
    required String userId,
    required String role,
  }) async {
    stopAutoSync();

    final enabled = await isSyncEnabled();
    if (!enabled) return;

    // 确保同步 Token 已配置
    await _ensureSyncToken();

    final interval = await getSyncInterval();

    // 立即执行一次
    _doAutoSync(userId, role);

    _syncTimer = Timer.periodic(
      Duration(minutes: interval),
      (_) => _doAutoSync(userId, role),
    );
    debugPrint('SyncService: 自动同步已启动 (每 $interval 分钟, 分组项目仓库模式)');
  }

  /// 停止自动同步
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> _doAutoSync(String userId, String role) async {
    if (_isSyncing) return;
    try {
      if (role == 'student') {
        // 先下载自己在其他设备上传的数据（跨设备同步）
        await downloadOwnData(userId);
        await uploadStudentData(userId);
      } else {
        await downloadAllStudentData();
      }
    } catch (e) {
      debugPrint('SyncService: 自动同步失败: $e');
    }
  }

  // ── 分组项目仓库解析 ──────────────────────────────────────────────────

  /// 把"仓库列"的值解析成 (owner, repo)。支持完整 Gitee URL、owner/repo、或裸仓库名。
  ({String owner, String repo})? _parseRepoSpec(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.contains('gitee.com')) {
      final parsed = GiteeService.parseRepoUrl(v);
      if (parsed != null) return (owner: parsed.owner, repo: parsed.repo);
      return null;
    }
    if (v.contains('/')) {
      final parts = v.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 2) {
        return (
          owner: parts[parts.length - 2],
          repo: parts.last.replaceAll('.git', '')
        );
      }
      return null;
    }
    // 裸仓库名（如 cg1-cifms）→ 默认命名空间下的该仓库
    return (owner: groupRepoOwner, repo: v.replaceAll('.git', ''));
  }

  /// 解析某学生的分组项目仓库（来自 users.repository_url ← 实验分组 Excel 仓库列）。
  Future<({String owner, String repo})?> _resolveRepoForUser(
      dynamic db, String userId) async {
    try {
      final rows = await db.query('users',
          columns: ['repository_url'],
          where: 'user_id = ?',
          whereArgs: [userId],
          limit: 1);
      final raw =
          rows.isNotEmpty ? (rows.first['repository_url'] as String?) : null;
      return _parseRepoSpec(raw);
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.resolveRepo', stack: st);
      return null;
    }
  }

  /// 教师端：收集所有学生的去重分组仓库列表。
  Future<List<({String owner, String repo})>> _allGroupRepos(dynamic db) async {
    final repos = <String, ({String owner, String repo})>{};
    try {
      final rows = await db.query('users',
          columns: ['repository_url'],
          where: "repository_url IS NOT NULL AND repository_url != ''");
      for (final r in rows) {
        final spec = _parseRepoSpec(r['repository_url'] as String?);
        if (spec != null) repos['${spec.owner}/${spec.repo}'] = spec;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.allGroupRepos', stack: st);
    }
    return repos.values.toList();
  }

  // ── 学生端：上传数据 ──────────────────────────────────────────────────

  /// 将当前学生的学习数据上传到 Gitee 仓库
  Future<SyncResult> uploadStudentData(String userId) async {
    if (_isSyncing) return SyncResult(success: false, message: '同步正在进行中');

    _isSyncing = true;
    status.value = SyncStatus.uploading;

    try {
      // 确保同步 Token 可用
      await _ensureSyncToken();
      // 0. 刷新 last_active 确保上传时间戳是最新的
      final db = await DatabaseHelper.instance.database;
      try {
        await db.update(
          'users',
          {'last_active': DateTime.now().toIso8601String()},
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      } catch (e, st) {
        swallowDebug(e, tag: 'SyncService', stack: st);
      }

      // 1. 收集本地数据
      final data = await _collectStudentData(userId);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      // 2. 校验数据是否变更（去重：无变化则跳过 commit）
      final hash = sha256.convert(utf8.encode(jsonStr)).toString();
      final prefs = await SharedPreferences.getInstance();
      final lastHash = prefs.getString('sync_hash_$userId');
      if (lastHash == hash) {
        try {
          await _uploadSubmissionFiles(userId, data);
        } catch (e) {
          debugPrint('SyncService: 附件补传失败（不影响主同步）: $e');
        }
        _isSyncing = false;
        status.value = SyncStatus.idle;
        debugPrint('SyncService: $userId 数据未变更，跳过同步');
        return SyncResult(success: true, message: '数据未变更，已检查附件同步');
      }

      // 3. 解析该学生的分组项目仓库（来自实验分组 Excel 仓库列 → users.repository_url）
      final repo = await _resolveRepoForUser(db, userId);
      if (repo == null) {
        status.value = SyncStatus.idle;
        debugPrint('SyncService: $userId 未配置分组仓库(repository_url)，跳过上传');
        return SyncResult(success: false, message: '未配置分组项目仓库，请联系教师导入实验分组');
      }

      // 4. 写入组仓库 mad/{userId}.json
      final path = '$madDir/$userId.json';
      await _gitee.createOrUpdateFile(
        owner: repo.owner,
        repo: repo.repo,
        path: path,
        content: jsonStr,
        message: '同步学生数据: $userId (${DateTime.now().toIso8601String()})',
        branch: repoBranch,
      );

      // 5. 上传实验/考核/作品附件到组仓库（静默失败，不影响主流程）
      try {
        await _uploadSubmissionFiles(userId, data);
      } catch (e) {
        debugPrint('SyncService: 附件上传失败（不影响主同步）: $e');
      }

      // 3. 记录同步时间
      await prefs.setString(
          _lastUploadTimeKey, DateTime.now().toIso8601String());
      await prefs.setString('sync_hash_$userId', hash);

      final recordCount = (data['quiz_results'] as List).length +
          (data['learning_records'] as List).length +
          (data['wrong_answers'] as List).length +
          (data['favorites'] as List).length +
          (data['feedback'] as List).length +
          (data['learning_paths'] as List).length +
          (data['lab_submissions'] as List).length +
          (data['student_reports'] as List).length +
          (data['assessment_reports'] as List).length +
          (data['student_works'] as List).length +
          (data['survey_responses'] as List).length +
          (data['checkin_records'] as List).length;

      debugPrint('SyncService: 上传成功 ($recordCount 条记录)');
      status.value = SyncStatus.idle;
      return SyncResult(
        success: true,
        message: '上传成功，共 $recordCount 条记录',
        recordCount: recordCount,
      );
    } catch (e) {
      debugPrint('SyncService: 上传失败: $e');
      status.value = SyncStatus.error;
      return SyncResult(success: false, message: '上传失败: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ── 学生端：下载自己在其他设备上传的数据 ──────────────────────────────

  /// 从 Gitee 下载当前学生自己的同步数据（跨设备同步）
  Future<SyncResult> downloadOwnData(String userId) async {
    if (_isSyncing) return SyncResult(success: false, message: '同步正在进行中');

    _isSyncing = true;
    status.value = SyncStatus.downloading;

    try {
      await _ensureSyncToken();

      final db = await DatabaseHelper.instance.database;
      final repo = await _resolveRepoForUser(db, userId);
      if (repo == null) {
        status.value = SyncStatus.idle;
        _isSyncing = false;
        return SyncResult(success: true, message: '未配置分组仓库', recordCount: 0);
      }

      final path = '$madDir/$userId.json';
      String? content;
      try {
        content = await _gitee.getFileContent(
          repo.owner,
          repo.repo,
          path,
          ref: repoBranch,
        );
      } catch (e) {
        // 文件不存在 → 该学生从未在其他设备同步过
        debugPrint('SyncService: 学生 $userId 无云端同步数据: $e');
        status.value = SyncStatus.idle;
        _isSyncing = false;
        return SyncResult(
          success: true,
          message: '无云端数据',
          recordCount: 0,
        );
      }

      if (content == null || content.isEmpty) {
        status.value = SyncStatus.idle;
        _isSyncing = false;
        return SyncResult(
          success: true,
          message: '云端数据为空',
          recordCount: 0,
        );
      }

      final data = jsonDecode(content) as Map<String, dynamic>;
      final count = await _importStudentSyncData(db, data);

      debugPrint('SyncService: 学生 $userId 跨设备同步完成，$count 条记录');
      status.value = SyncStatus.idle;
      _isSyncing = false;
      return SyncResult(
        success: true,
        message: '跨设备同步完成，$count 条记录',
        recordCount: count,
      );
    } catch (e) {
      debugPrint('SyncService: 学生跨设备同步失败: $e');
      status.value = SyncStatus.error;
      _isSyncing = false;
      return SyncResult(success: false, message: '同步失败: $e');
    }
  }

  /// 上传提交引用的附件文件到组仓库
  ///
  /// 目录规范（写入学生自己的组仓库）：
  ///   mad/files/{userId}/实验/{fileName}  — 实验报告
  ///   mad/files/{userId}/考核/{fileName}  — 项目考核
  ///   mad/files/{userId}/作品/{fileName}  — 学生作品
  Future<void> _uploadSubmissionFiles(
      String userId, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    final repo = await _resolveRepoForUser(db, userId);
    if (repo == null) return;
    // 实验报告
    final submissions = data['lab_submissions'] as List? ?? [];
    for (final sub in submissions) {
      await _uploadSingleFile(repo, userId, sub, '实验');
    }
    // 考核报告（student_reports 表）
    final reports = data['student_reports'] as List? ?? [];
    for (final report in reports) {
      await _uploadSingleFile(repo, userId, report, '考核');
    }
    // 考核报告（assessment_reports 表 — 分离后的考核报告）
    final assessmentReports = data['assessment_reports'] as List? ?? [];
    for (final report in assessmentReports) {
      await _uploadSingleFile(repo, userId, report, '考核');
    }
    // 项目考核
    final projectScores = data['project_scores'] as List? ?? [];
    for (final score in projectScores) {
      await _uploadSingleFile(repo, userId, score, '考核');
    }
    // 学生作品
    final works = data['student_works'] as List? ?? [];
    for (final work in works) {
      await _uploadSingleFile(repo, userId, work, '作品');
    }
  }

  /// 上传单个文件到组仓库的分类目录（mad/files/{userId}/{category}/）
  Future<void> _uploadSingleFile(({String owner, String repo}) repo,
      String userId, Map<String, dynamic> row, String category) async {
    final filePaths = (row['file_paths'] as String?) ??
        (row['file_path'] as String?) ??
        (row['attachment_url'] as String?) ??
        '';
    final fileNames = (row['file_names'] as String?) ??
        (row['file_name'] as String?) ??
        (row['content_json'] as String?) ??
        '';
    if (filePaths.isEmpty) return;

    final file = File(filePaths);
    if (!file.existsSync()) return;

    final fileName = fileNames.isNotEmpty
        ? fileNames
        : filePaths.split('/').last.split('\\').last;
    final remotePath = '$madDir/files/$userId/$category/$fileName';

    try {
      final bytes = await file.readAsBytes();
      // 作品视频会明显大于 PDF。与上传入口保持一致，100MB 以内尝试同步。
      if (bytes.length > 100 * 1024 * 1024) {
        debugPrint('SyncService: 跳过超大文件 $fileName (${bytes.length} bytes)');
        return;
      }
      if (bytes.length <= 500 * 1024) {
        // ≤500KB → Contents API（快速写入）
        await _gitee.createOrUpdateBinaryFile(
          owner: repo.owner,
          repo: repo.repo,
          path: remotePath,
          bytes: bytes,
          message: '上传$category文件: $fileName ($userId)',
          branch: repoBranch,
        );
      } else {
        // >500KB → Git Data API（绕过 Contents API 1MB 限制）
        try {
          await _gitee.uploadBinaryViaGitDataApi(
            owner: repo.owner,
            repo: repo.repo,
            path: remotePath,
            bytes: bytes,
            message: '上传$category文件: $fileName ($userId)',
            branch: repoBranch,
          );
        } catch (e2) {
          debugPrint('Git Data API 上传 $fileName 失败，回退 Contents API: $e2');
          // 回退：Git Data API 失败时尝试 Contents API（小文件或网络问题）
          await _gitee.createOrUpdateBinaryFile(
            owner: repo.owner,
            repo: repo.repo,
            path: remotePath,
            bytes: bytes,
            message: '上传$category文件: $fileName ($userId)',
            branch: repoBranch,
          );
        }
      }
      debugPrint('SyncService: 已上传 $remotePath (${bytes.length} bytes)');
    } catch (e) {
      debugPrint('SyncService: 上传 $fileName 失败: $e');
    }
  }

  /// 收集学生本地数据（全量）
  Future<Map<String, dynamic>> _collectStudentData(String userId) async {
    final db = await DatabaseHelper.instance.database;

    // 用户基本信息
    final userRows = await db.query(
      'users',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    final userName = userRows.isNotEmpty
        ? (userRows.first['real_name'] as String? ?? '')
        : '';
    final lastActive =
        userRows.isNotEmpty ? (userRows.first['last_active'] as String?) : null;

    // ── 按 user_id 收集的表 ─────────────────────────────────────────
    // 表名 → 排序字段（null 则不排序）
    const userIdTables = <String, String?>{
      'quiz_results': 'quiz_timestamp DESC',
      'learning_records': 'completed_at DESC',
      'wrong_answers': null,
      'favorites': null,
      'feedback': 'created_at DESC',
      'learning_paths': 'created_at DESC',
      'lab_submissions': 'submit_time DESC',
      'student_reports': 'updated_at DESC',
      'assessment_reports': 'updated_at DESC',
      'student_works': 'created_at DESC',
      'survey_responses': 'submitted_at DESC',
      'checkin_records': 'checked_at DESC',
      // notification_recipients 不同步：notification_id 是本地自增主键，
      // 跨设备导入会导致孤儿行（引用不存在的通知），造成 badge 计数与列表不一致
    };

    final result = <String, dynamic>{
      'version': '2.0',
      'user_id': userId,
      'user_name': userName,
      'role': 'student',
      'synced_at': DateTime.now().toIso8601String(),
      'last_active': lastActive ?? DateTime.now().toIso8601String(),
    };

    for (final entry in userIdTables.entries) {
      result[entry.key] = await _safeQuery(
        db,
        entry.key,
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: entry.value,
      );
    }

    // 作品互动表需要携带作品自然键，导入端不能直接复用本机自增 work_id。
    result['work_comments'] = await _safeWorkScopedQuery(
      db,
      'work_comments',
      userIdColumn: 'user_id',
      userId: userId,
      orderBy: 'created_at DESC',
    );
    result['work_likes'] = await _safeWorkScopedQuery(
      db,
      'work_likes',
      userIdColumn: 'user_id',
      userId: userId,
    );
    result['work_views'] = await _safeWorkScopedQuery(
      db,
      'work_views',
      userIdColumn: 'user_id',
      userId: userId,
      orderBy: 'viewed_at DESC',
    );

    // ── 按其他字段收集的表 ────────────────────────────────────────────
    // peer_reviews 使用 reviewer_id
    result['peer_reviews'] = await _safeQuery(
      db,
      'peer_reviews',
      where: 'reviewer_id = ?',
      whereArgs: [userId],
    );

    // collaboration_messages 使用 sender_id
    result['collaboration_messages'] = await _safeQuery(
      db,
      'collaboration_messages',
      where: 'sender_id = ?',
      whereArgs: [userId],
    );

    // contribution_scores — 学生作为评分人或被评人
    result['contribution_scores'] = await _safeQuery(
      db,
      'contribution_scores',
      where: 'scorer_user_id = ? OR target_user_id = ?',
      whereArgs: [userId, userId],
    );

    // work_scores — 学生作为评分人（同学互评）
    result['work_scores'] = await _safeWorkScopedQuery(
      db,
      'work_scores',
      userIdColumn: 'scorer_id',
      userId: userId,
      orderBy: 'scored_at DESC',
    );

    // project_scores — 学生作为评分人（项目互评）
    result['project_scores'] = await _safeQuery(
      db,
      'project_scores',
      where: 'scorer_id = ?',
      whereArgs: [userId],
      orderBy: 'scored_at DESC',
    );

    // lab_tasks — 全量携带（非 user_id 表，但需要对齐 task_id）
    // 保留 id 以便教师端按 title 匹配后重映射 task_id
    try {
      final tasks = await db.query('lab_tasks', orderBy: 'id');
      result['lab_tasks'] = (tasks as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.collectLabTasks', stack: st);
      result['lab_tasks'] = <Map<String, dynamic>>[];
    }

    // report_templates — 同上
    try {
      final templates = await db.query('report_templates', orderBy: 'id');
      result['report_templates'] = (templates as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.collectReportTemplates', stack: st);
      result['report_templates'] = <Map<String, dynamic>>[];
    }

    // classroom_messages 使用 sender_id
    result['classroom_messages'] = await _safeQuery(
      db,
      'classroom_messages',
      where: 'sender_id = ?',
      whereArgs: [userId],
    );

    // path_nodes — 通过 learning_paths 的 id 关联
    final paths = result['learning_paths'] as List;
    if (paths.isNotEmpty) {
      final allPathNodes = <Map<String, dynamic>>[];
      for (final p in paths) {
        final pathId = (p as Map)['id'];
        if (pathId != null) {
          final nodes = await _safeQuery(
            db,
            'path_nodes',
            where: 'path_id = ?',
            whereArgs: [pathId],
            orderBy: 'sort_order',
          );
          allPathNodes.addAll(nodes.cast<Map<String, dynamic>>());
        }
      }
      result['path_nodes'] = allPathNodes;
    } else {
      result['path_nodes'] = <Map<String, dynamic>>[];
    }

    return result;
  }

  /// 安全查询 — 表不存在时返回空列表
  Future<List<Map<String, dynamic>>> _safeQuery(
    dynamic db,
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    try {
      final rows = await db.query(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
      );
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map)..remove('id'))
          .toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.safeQuery', stack: st);
      return []; // 表可能不存在
    }
  }

  Future<List<Map<String, dynamic>>> _safeWorkScopedQuery(
    dynamic db,
    String table, {
    required String userIdColumn,
    required String userId,
    String? orderBy,
  }) async {
    try {
      final orderSql = orderBy == null ? '' : 'ORDER BY i.$orderBy';
      final rows = await db.rawQuery('''
        SELECT i.*,
               w.user_id AS work_user_id,
               w.title AS work_title,
               w.course_id AS work_course_id
        FROM $table i
        LEFT JOIN student_works w ON w.id = i.work_id
        WHERE i.$userIdColumn = ?
        $orderSql
      ''', [userId]);
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map)..remove('id'))
          .toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.safeWorkScopedQuery', stack: st);
      return [];
    }
  }

  // ── 教师端：下载数据 ──────────────────────────────────────────────────

  /// 从 Gitee 仓库拉取所有学生的同步数据
  Future<SyncResult> downloadAllStudentData() async {
    if (_isSyncing) return SyncResult(success: false, message: '同步正在进行中');

    _isSyncing = true;
    status.value = SyncStatus.downloading;

    try {
      // 确保同步 Token 可用
      await _ensureSyncToken();
      // 1. 收集所有去重的分组项目仓库（来自 users.repository_url ← 实验分组 Excel 仓库列）
      final db = await DatabaseHelper.instance.database;
      final groupRepos = await _allGroupRepos(db);
      if (groupRepos.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _lastDownloadTimeKey, DateTime.now().toIso8601String());
        status.value = SyncStatus.idle;
        return SyncResult(
          success: true,
          message: '暂无分组仓库（请先导入实验分组 Excel 设置 repository_url）',
          recordCount: 0,
        );
      }

      // 2. 逐个仓库拉取 mad/*.json 并导入
      int totalRecords = 0;
      int studentCount = 0;

      for (final repo in groupRepos) {
        List<Map<String, dynamic>> files;
        try {
          files = await _gitee.listDir(repo.owner, repo.repo, madDir,
              ref: repoBranch);
        } catch (e) {
          // 该仓库还没有 mad/ 目录（学生未同步过）
          swallow(e, tag: 'SyncService.downloadAll.listMadDir');
          continue;
        }
        final jsonFiles = files
            .where((f) =>
                f['type'] == 'file' &&
                (f['name']?.toString() ?? '').endsWith('.json'))
            .toList();
        for (final file in jsonFiles) {
          final filePath = file['path']?.toString() ?? '';
          if (filePath.isEmpty) continue;
          try {
            final content = await _gitee.getFileContent(
              repo.owner,
              repo.repo,
              filePath,
              ref: repoBranch,
            );
            if (content == null) continue;
            final data = jsonDecode(content) as Map<String, dynamic>;
            final count = await _importStudentSyncData(db, data);
            totalRecords += count;
            studentCount++;
          } catch (e) {
            debugPrint(
                'SyncService: 解析 ${repo.owner}/${repo.repo}/$filePath 失败: $e');
          }
        }
      }

      // 3. 记录同步时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastDownloadTimeKey, DateTime.now().toIso8601String());

      // 3.5 备份到教师个人仓库（静默失败）
      try {
        final session = await db.query('current_session', limit: 1);
        if (session.isNotEmpty) {
          final teacherId = session.first['user_id'] as String?;
          if (teacherId != null) {
            final teacherInfo = await db.query(
              'users',
              columns: ['repository_url'],
              where: 'user_id = ?',
              whereArgs: [teacherId],
              limit: 1,
            );
            final repoUrl = teacherInfo.isNotEmpty
                ? (teacherInfo.first['repository_url'] as String?)
                : null;
            if (repoUrl != null && repoUrl.isNotEmpty) {
              final parsed = GiteeService.parseRepoUrl(repoUrl);
              if (parsed != null) {
                final backupData = {
                  'synced_at': DateTime.now().toIso8601String(),
                  'student_count': studentCount,
                  'total_records': totalRecords,
                  'teacher_id': teacherId,
                };
                await _gitee.createOrUpdateFile(
                  owner: parsed.owner,
                  repo: parsed.repo,
                  path: 'sync/teacher_sync_log.json',
                  content:
                      const JsonEncoder.withIndent('  ').convert(backupData),
                  message: '教师同步备份 ($studentCount 学生, $totalRecords 条记录)',
                  branch: repoBranch,
                );
                debugPrint(
                    'SyncService: 已备份到教师仓库 ${parsed.owner}/${parsed.repo}');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService: 教师仓库备份失败（不影响主同步）: $e');
      }

      debugPrint('SyncService: 下载完成 ($studentCount 学生, $totalRecords 条记录)');
      status.value = SyncStatus.idle;
      return SyncResult(
        success: true,
        message: '拉取成功，共 $studentCount 名学生, $totalRecords 条记录',
        recordCount: totalRecords,
        studentCount: studentCount,
      );
    } catch (e) {
      debugPrint('SyncService: 下载失败: $e');
      status.value = SyncStatus.error;
      return SyncResult(success: false, message: '拉取失败: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// 将单个学生的同步数据导入本地 DB
  /// 策略：按 user_id 全量替换（先删后插）
  Future<int> _importStudentSyncData(
    dynamic db,
    Map<String, dynamic> data,
  ) async {
    final userId = data['user_id'] as String?;
    if (userId == null || userId.isEmpty) return 0;

    int count = 0;

    // ── 确保用户记录存在（INSERT OR UPDATE）────────────────────────────
    final userName = data['user_name'] as String? ?? '';
    final lastActive = data['last_active'] as String?;
    final existingUser = await db.query(
      'users',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (existingUser.isEmpty) {
      try {
        await db.insert('users', {
          'user_id': userId,
          'real_name': userName.isNotEmpty ? userName : null,
          'role': 'student',
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'last_active': lastActive ?? DateTime.now().toIso8601String(),
        });
        debugPrint('SyncService: 创建用户记录 $userId ($userName)');
      } catch (e) {
        debugPrint('SyncService: 创建用户失败: $e');
      }
    } else {
      final updates = <String, dynamic>{};
      if (lastActive != null) updates['last_active'] = lastActive;
      if (userName.isNotEmpty) updates['real_name'] = userName;
      if (updates.isNotEmpty) {
        try {
          await db.update('users', updates,
              where: 'user_id = ?', whereArgs: [userId]);
        } catch (e, st) {
          swallowDebug(e, tag: 'SyncService', stack: st);
        }
      }
    }

    // ── 确保班级成员关联（加入默认班级）──────────────────────────────────
    try {
      final memberCheck = await db.query(
        'class_members',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (memberCheck.isEmpty) {
        final classes = await db.query('classes', limit: 1, orderBy: 'id');
        int classId;
        if (classes.isNotEmpty) {
          classId = classes.first['id'] as int;
        } else {
          classId = await db.insert('classes', {
            'name': '默认班级',
            'description': '自动创建的默认班级',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        await db.insert('class_members', {
          'class_id': classId,
          'user_id': userId,
          'joined_at': DateTime.now().toIso8601String(),
        });
        debugPrint('SyncService: 已将 $userId 加入班级 $classId');
      }
    } catch (e) {
      debugPrint('SyncService: 班级关联失败: $e');
    }

    // ── 同步 lab_tasks：按 title 匹配，构建 task_id 映射 ─────────────
    // 学生端和教师端各自独立生成 lab_tasks（auto-increment ID），
    // 同一实验任务在不同设备上 ID 可能不同。
    // 解决方案：以 title 为自然键匹配，建立"学生端ID → 教师端ID"映射表。
    final taskIdRemap = <int, int>{}; // studentTaskId → localTaskId
    try {
      final remoteTasks = data['lab_tasks'] as List?;
      if (remoteTasks != null && remoteTasks.isNotEmpty) {
        for (final rt in remoteTasks) {
          final remoteTask = Map<String, dynamic>.from(rt as Map);
          final remoteId = remoteTask['id'] as int?;
          final title = remoteTask['title'] as String? ?? '';
          if (remoteId == null || title.isEmpty) continue;

          // 按 title 查找本地是否已有该任务
          final localMatch = await db.query('lab_tasks',
              where: 'title = ?', whereArgs: [title], limit: 1);

          int localId;
          if (localMatch.isNotEmpty) {
            localId = localMatch.first['id'] as int;
          } else {
            // 本地没有 → 插入（教师端自动获得该实验任务定义）
            remoteTask.remove('id');
            localId = await db.insert('lab_tasks', remoteTask);
            debugPrint('SyncService: 新建 lab_task "$title" → id=$localId');
          }
          taskIdRemap[remoteId] = localId;
        }
        debugPrint('SyncService: task_id 映射表: $taskIdRemap');
      }
    } catch (e) {
      debugPrint('SyncService: lab_tasks 同步失败: $e');
    }

    // ── 同步 report_templates：按 name+category 匹配 ──────────────────
    final templateIdRemap = <int, int>{};
    try {
      final remoteTemplates = data['report_templates'] as List?;
      if (remoteTemplates != null && remoteTemplates.isNotEmpty) {
        for (final rt in remoteTemplates) {
          final remoteTpl = Map<String, dynamic>.from(rt as Map);
          final remoteId = remoteTpl['id'] as int?;
          final name = remoteTpl['name'] as String? ?? '';
          final category = remoteTpl['category'] as String? ?? '';
          if (remoteId == null || name.isEmpty) continue;

          final localMatch = await db.query('report_templates',
              where: 'name = ? AND category = ?',
              whereArgs: [name, category],
              limit: 1);

          int localId;
          if (localMatch.isNotEmpty) {
            localId = localMatch.first['id'] as int;
          } else {
            remoteTpl.remove('id');
            localId = await db.insert('report_templates', remoteTpl);
          }
          templateIdRemap[remoteId] = localId;
        }
      }
    } catch (e) {
      debugPrint('SyncService: report_templates 同步失败: $e');
    }

    // ── 使用事务保护批量导入（先删后插）──────────────────────────────────
    // 所有表的删除+插入在同一事务中完成，防止中途失败导致数据丢失
    try {
      count = await db.transaction((txn) async {
        int txnCount = 0;

        // ── 按 user_id 批量导入所有表 ─────────────────────────────────
        // 注意：lab_submissions、student_reports、student_works 需要特殊处理，不在通用列表中
        const userIdTables = [
          'quiz_results',
          'learning_records',
          'wrong_answers',
          'favorites',
          'feedback',
          'learning_paths',
          'survey_responses',
          'checkin_records',
          // notification_recipients 不同步：notification_id 跨设备不匹配，导入会产生孤儿行
          'assessment_reports',
        ];

        for (final table in userIdTables) {
          txnCount += await _importTable(
            txn,
            data,
            table,
            userIdColumn: 'user_id',
            userId: userId,
          );
        }

        // ── lab_submissions 特殊处理 ─────────────────────────────────
        // 1) task_id 重映射（学生端ID → 教师端ID）
        // 2) 保护教师已批改的评分数据不被覆盖
        txnCount += await _importLabSubmissions(
          txn,
          data,
          userId,
          taskIdRemap,
        );

        // ── student_reports 特殊处理 ─────────────────────────────────
        // task_id / template_id 重映射
        txnCount += await _importStudentReports(
          txn,
          data,
          userId,
          taskIdRemap,
          templateIdRemap,
        );

        // ── 按其他字段导入的表 ──────────────────────────────────────
        txnCount += await _importTable(
          txn,
          data,
          'peer_reviews',
          userIdColumn: 'reviewer_id',
          userId: userId,
        );
        txnCount += await _importTable(
          txn,
          data,
          'collaboration_messages',
          userIdColumn: 'sender_id',
          userId: userId,
        );
        txnCount += await _importTable(
          txn,
          data,
          'classroom_messages',
          userIdColumn: 'sender_id',
          userId: userId,
        );

        // ── student_works 特殊处理 ──────────────────────────────────
        // 保护已评分的作品不被覆盖
        txnCount += await _importStudentWorks(txn, data, userId);

        // ── 作品互动表：按作品自然键重映射 work_id ───────────────────
        txnCount += await _importWorkInteractionTable(
          txn,
          data,
          'work_comments',
          userId,
        );
        txnCount += await _importWorkInteractionTable(
          txn,
          data,
          'work_likes',
          userId,
        );
        txnCount += await _importWorkInteractionTable(
          txn,
          data,
          'work_views',
          userId,
        );
        await _recalculateWorkInteractionCounts(txn);

        // ── work_scores — 学生互评（按 scorer_id 导入）────────────────
        // 保护教师评分不被覆盖
        txnCount += await _importWorkScores(txn, data, userId);

        // ── project_scores — 项目互评（按 scorer_id 导入）─────────────
        txnCount += await _importProjectScores(txn, data, userId);

        // contribution_scores — 删除该用户相关的所有记录再导入
        final contribList = data['contribution_scores'] as List?;
        if (contribList != null && contribList.isNotEmpty) {
          try {
            await txn.delete('contribution_scores',
                where: 'scorer_user_id = ? OR target_user_id = ?',
                whereArgs: [userId, userId]);
            for (final r in contribList) {
              try {
                final row = Map<String, dynamic>.from(r as Map);
                row.remove('id');
                await txn.insert('contribution_scores', row);
                txnCount++;
              } catch (e, st) {
                swallowDebug(e, tag: 'SyncService', stack: st);
              }
            }
          } catch (e, st) {
            swallowDebug(e, tag: 'SyncService', stack: st);
          }
        }

        // path_nodes — 先删除该用户所有 path 的节点，再导入
        final pathNodes = data['path_nodes'] as List?;
        if (pathNodes != null && pathNodes.isNotEmpty) {
          try {
            final paths = await txn.query('learning_paths',
                columns: ['id'], where: 'user_id = ?', whereArgs: [userId]);
            for (final p in paths) {
              await txn.delete('path_nodes',
                  where: 'path_id = ?', whereArgs: [p['id']]);
            }
            for (final r in pathNodes) {
              try {
                final row = Map<String, dynamic>.from(r as Map);
                row.remove('id');
                await txn.insert('path_nodes', row);
                txnCount++;
              } catch (e, st) {
                swallowDebug(e, tag: 'SyncService', stack: st);
              }
            }
          } catch (e, st) {
            swallowDebug(e, tag: 'SyncService', stack: st);
          }
        }

        return txnCount;
      });
    } catch (e) {
      debugPrint('SyncService: 事务导入失败，已回滚: $e');
    }

    return count;
  }

  /// 通用表导入 — 先删后插
  Future<int> _importTable(
    dynamic db,
    Map<String, dynamic> data,
    String table, {
    required String userIdColumn,
    required String userId,
  }) async {
    final list = data[table] as List?;
    if (list == null || list.isEmpty) return 0;

    int count = 0;
    try {
      await db.delete(table, where: '$userIdColumn = ?', whereArgs: [userId]);
      for (final r in list) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row[userIdColumn] = userId;
          await db.insert(table, row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 $table 失败: $e');
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService', stack: st);
    } // 表可能不存在
    return count;
  }

  /// lab_submissions 特殊导入：
  /// - task_id 重映射（学生端 → 教师端）
  /// - 保护教师已批改的评分数据（score/feedback/scorer_id/scored_at）
  Future<int> _importLabSubmissions(
    dynamic db,
    Map<String, dynamic> data,
    String userId,
    Map<int, int> taskIdRemap,
  ) async {
    final list = data['lab_submissions'] as List?;
    if (list == null || list.isEmpty) return 0;

    int count = 0;
    try {
      // 先查出教师端已有的、已批改的提交（需要保护评分数据）
      final existingGraded = <String, Map<String, dynamic>>{};
      try {
        final graded = await db.query('lab_submissions',
            where: 'user_id = ? AND score IS NOT NULL', whereArgs: [userId]);
        for (final g in graded) {
          // 以 task_id 为 key（已是教师端 ID）
          final taskId = g['task_id'] as int?;
          if (taskId != null) {
            existingGraded['$taskId'] = Map<String, dynamic>.from(g as Map);
          }
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'SyncService', stack: st);
      }

      // 删除该学生的所有未批改提交（已批改的保留）
      await db.delete('lab_submissions',
          where: 'user_id = ? AND score IS NULL', whereArgs: [userId]);

      for (final r in list) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;

          // 重映射 task_id
          final originalTaskId = row['task_id'] as int?;
          if (originalTaskId != null &&
              taskIdRemap.containsKey(originalTaskId)) {
            row['task_id'] = taskIdRemap[originalTaskId];
          }

          final localTaskId = row['task_id'] as int?;

          // 检查教师端是否已有该任务的已批改提交
          if (localTaskId != null &&
              existingGraded.containsKey('$localTaskId')) {
            // 已批改 → 只更新学生端字段（content/file_paths 等），保留评分
            final graded = existingGraded['$localTaskId']!;
            row['score'] = graded['score'];
            row['feedback'] = graded['feedback'];
            row['scorer_id'] = graded['scorer_id'];
            row['scored_at'] = graded['scored_at'];
            row['status'] = graded['status']; // 保持"已批改"状态

            // 尝试下载 PDF 文件到本地
            await _downloadSubmissionFile(row, userId);

            // 更新而非插入
            await db.update('lab_submissions', row,
                where: 'id = ?', whereArgs: [graded['id']]);
            count++;
          } else {
            // 尝试下载 PDF 文件到本地
            await _downloadSubmissionFile(row, userId);

            // 未批改 → 直接插入
            await db.insert('lab_submissions', row);
            count++;
          }
        } catch (e) {
          debugPrint('SyncService: 导入 lab_submissions 失败: $e');
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService', stack: st);
    }
    return count;
  }

  /// 从 Gitee 仓库下载实验提交的 PDF 文件到本地
  ///
  /// 按新目录规范依次尝试：实验/ → files/（兼容旧数据）
  Future<void> _downloadSubmissionFile(Map<String, dynamic> row, String userId,
      {String category = '实验'}) async {
    try {
      final fileNames = (row['file_names'] as String?) ??
          (row['file_name'] as String?) ??
          (row['content_json'] as String?) ??
          '';

      // 本地已存在则跳过
      final filePaths =
          (row['file_paths'] as String?) ?? (row['file_path'] as String?) ?? '';
      final fileName = fileNames.isNotEmpty
          ? fileNames
          : filePaths.split('/').last.split('\\').last;
      if (fileName.isEmpty) return;
      if (filePaths.isNotEmpty && File(filePaths).existsSync()) return;

      // 解析该学生的分组仓库，从 mad/files/{userId}/{category}/ 下载
      final db = await DatabaseHelper.instance.database;
      final repo = await _resolveRepoForUser(db, userId);
      if (repo == null) return;

      List<int>? bytes;
      final remotePath = '$madDir/files/$userId/$category/$fileName';
      try {
        bytes = await _gitee.downloadBinaryFile(
          owner: repo.owner,
          repo: repo.repo,
          path: remotePath,
          branch: repoBranch,
        );
      } catch (e, st) {
        swallowDebug(e, tag: 'SyncService', stack: st);
      }
      if (bytes == null || bytes.isEmpty) return;

      // 保存到本地应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final syncFilesDir = Directory('${appDir.path}/sync_files/$userId');
      if (!syncFilesDir.existsSync()) {
        syncFilesDir.createSync(recursive: true);
      }
      final localFile = File('${syncFilesDir.path}/$fileName');
      await localFile.writeAsBytes(bytes);

      // 更新 file_paths / file_path / video_url 为本地同步路径
      row['file_paths'] = localFile.path;
      row['file_path'] = localFile.path;
      row['video_url'] = localFile.path;
      debugPrint('SyncService: 已下载 $fileName -> ${localFile.path}');
    } catch (e) {
      debugPrint('SyncService: 下载 PDF 失败: $e');
    }
  }

  /// student_reports 特殊导入：
  /// - task_id / template_id 重映射
  /// - 保护教师已评分的报告
  Future<int> _importStudentReports(
    dynamic db,
    Map<String, dynamic> data,
    String userId,
    Map<int, int> taskIdRemap,
    Map<int, int> templateIdRemap,
  ) async {
    final list = data['student_reports'] as List?;
    if (list == null || list.isEmpty) return 0;

    int count = 0;
    try {
      // 查出已评分的报告（保护评分数据）
      final existingScored = <String, Map<String, dynamic>>{};
      try {
        final scored = await db.query('student_reports',
            where: 'user_id = ? AND score IS NOT NULL', whereArgs: [userId]);
        for (final s in scored) {
          final title = s['title'] as String? ?? '';
          final taskId = s['task_id']?.toString() ?? '';
          existingScored['$title|$taskId'] =
              Map<String, dynamic>.from(s as Map);
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'SyncService', stack: st);
      }

      // 删除该学生的未评分报告
      await db.delete('student_reports',
          where: 'user_id = ? AND score IS NULL', whereArgs: [userId]);

      for (final r in list) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;

          // 重映射 task_id
          final originalTaskId = row['task_id'] as int?;
          if (originalTaskId != null &&
              taskIdRemap.containsKey(originalTaskId)) {
            row['task_id'] = taskIdRemap[originalTaskId];
          }

          // 重映射 template_id
          final originalTemplateId = row['template_id'] as int?;
          if (originalTemplateId != null &&
              templateIdRemap.containsKey(originalTemplateId)) {
            row['template_id'] = templateIdRemap[originalTemplateId];
          }

          final title = row['title'] as String? ?? '';
          final taskId = row['task_id']?.toString() ?? '';
          final key = '$title|$taskId';
          await _downloadSubmissionFile(row, userId, category: '考核');

          if (existingScored.containsKey(key)) {
            // 已评分 → 保留评分，更新内容
            final scored = existingScored[key]!;
            row['score'] = scored['score'];
            row['feedback'] = scored['feedback'];
            await db.update('student_reports', row,
                where: 'id = ?', whereArgs: [scored['id']]);
            count++;
          } else {
            await db.insert('student_reports', row);
            count++;
          }
        } catch (e) {
          debugPrint('SyncService: 导入 student_reports 失败: $e');
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService', stack: st);
    }
    return count;
  }

  /// student_works 特殊导入：
  /// - 保护已有评分（work_scores 关联）的作品不被覆盖
  Future<int> _importStudentWorks(
    dynamic db,
    Map<String, dynamic> data,
    String userId,
  ) async {
    final list = data['student_works'] as List?;
    if (list == null || list.isEmpty) return 0;

    int count = 0;
    try {
      // 查出已有评分的作品 ID（需要保护）
      final scoredWorkIds = <int>{};
      try {
        final scored = await db.rawQuery('''
          SELECT DISTINCT w.id FROM student_works w
          INNER JOIN work_scores ws ON ws.work_id = w.id
          WHERE w.user_id = ?
        ''', [userId]);
        for (final r in scored) {
          final id = r['id'] as int?;
          if (id != null) scoredWorkIds.add(id);
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'SyncService', stack: st);
      }

      // 构建已有作品的 title → id 映射（用于匹配跨设备数据）
      final existingById = <int, Map<String, dynamic>>{};
      final existingByTitle = <String, int>{};
      try {
        final existing = await db
            .query('student_works', where: 'user_id = ?', whereArgs: [userId]);
        for (final r in existing) {
          final id = r['id'] as int?;
          final title = r['title'] as String? ?? '';
          if (id != null) {
            existingById[id] = Map<String, dynamic>.from(r as Map);
            if (title.isNotEmpty) existingByTitle[title] = id;
          }
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'SyncService', stack: st);
      }

      for (final r in list) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;

          final title = row['title'] as String? ?? '';
          await _downloadSubmissionFile(row, userId, category: '作品');

          final existingId = existingByTitle[title];
          if (existingId != null) {
            final isScored = scoredWorkIds.contains(existingId);
            if (!isScored) {
              // 未评分 → 全量更新，保持本地 id 不变
              await db.update('student_works', row,
                  where: 'id = ?', whereArgs: [existingId]);
            } else {
              // 已评分 → 只更新非评分字段（评分由 work_scores 管理）
              row.remove('score');
              row.remove('score_comment');
              row.remove('scorer_name');
              row.remove('scored_at');
              await db.update('student_works', row,
                  where: 'id = ?', whereArgs: [existingId]);
            }
            count++;
          } else {
            await db.insert('student_works', row);
            count++;
          }
        } catch (e) {
          debugPrint('SyncService: 导入 student_works 失败: $e');
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService', stack: st);
    }
    return count;
  }

  Future<int?> _resolveLocalWorkId(
    dynamic db,
    Map<String, dynamic> row,
  ) async {
    final workUserId = (row['work_user_id'] as String?)?.trim() ?? '';
    final workTitle = (row['work_title'] as String?)?.trim() ?? '';
    final workCourseId = (row['work_course_id'] as String?)?.trim() ?? '';

    if (workUserId.isNotEmpty && workTitle.isNotEmpty) {
      final where = workCourseId.isEmpty
          ? 'user_id = ? AND title = ?'
          : "user_id = ? AND title = ? AND (course_id = ? OR course_id IS NULL OR course_id = '')";
      final args = workCourseId.isEmpty
          ? <Object?>[workUserId, workTitle]
          : <Object?>[workUserId, workTitle, workCourseId];
      final matches = await db.query(
        'student_works',
        columns: ['id'],
        where: where,
        whereArgs: args,
        limit: 1,
      );
      if (matches.isNotEmpty) return matches.first['id'] as int?;

      final now = DateTime.now().toIso8601String();
      return db.insert('student_works', {
        'course_id': workCourseId.isNotEmpty
            ? workCourseId
            : CourseContextService.defaultCourseId,
        'title': workTitle,
        'user_id': workUserId,
        'status': '待提交',
        'created_at': now,
        'updated_at': now,
      });
    }

    final rawWorkId = row['work_id'];
    final workId = rawWorkId is int ? rawWorkId : int.tryParse('$rawWorkId');
    if (workId == null) return null;
    final exists = await db.query(
      'student_works',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [workId],
      limit: 1,
    );
    return exists.isNotEmpty ? workId : null;
  }

  void _stripWorkSyncMetadata(Map<String, dynamic> row) {
    row
      ..remove('work_user_id')
      ..remove('work_title')
      ..remove('work_course_id');
  }

  Future<int> _importWorkInteractionTable(
    dynamic db,
    Map<String, dynamic> data,
    String table,
    String userId,
  ) async {
    final list = data[table] as List?;
    if (list == null) return 0;

    int count = 0;
    try {
      await db.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      if (list.isEmpty) return 0;
      for (final r in list) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;
          final localWorkId = await _resolveLocalWorkId(db, row);
          if (localWorkId == null) continue;
          row['work_id'] = localWorkId;
          _stripWorkSyncMetadata(row);
          await db.insert(table, row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 $table 失败: $e');
        }
      }
    } catch (e, st) {
      swallowDebug(e,
          tag: 'SyncService.importWorkInteraction.$table', stack: st);
    }
    return count;
  }

  Future<void> _recalculateWorkInteractionCounts(dynamic db) async {
    try {
      await db.rawUpdate('''
        UPDATE student_works
        SET view_count = (
              SELECT COUNT(*) FROM work_views v WHERE v.work_id = student_works.id
            ),
            like_count = (
              SELECT COUNT(*) FROM work_likes l WHERE l.work_id = student_works.id
            ),
            comment_count = (
              SELECT COUNT(*) FROM work_comments c WHERE c.work_id = student_works.id
            )
      ''');
    } catch (e, st) {
      swallowDebug(e,
          tag: 'SyncService.recalculateWorkInteractionCounts', stack: st);
    }
  }

  /// work_scores 导入：
  /// - 仅导入该学生作为评分人（scorer_id）的互评记录
  /// - 不删除/覆盖其他评分人（教师或其他同学）的评分
  Future<int> _importWorkScores(
    dynamic db,
    Map<String, dynamic> data,
    String userId,
  ) async {
    final list = data['work_scores'] as List?;
    if (list == null) return 0;

    int count = 0;
    try {
      // 删除该学生作为评分人的旧评分（重新导入）
      await db
          .delete('work_scores', where: 'scorer_id = ?', whereArgs: [userId]);
      if (list.isEmpty) return 0;

      for (final r in list) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['scorer_id'] = userId; // 确保 scorer_id 一致

          final localWorkId = await _resolveLocalWorkId(db, row);
          if (localWorkId == null) continue;
          row['work_id'] = localWorkId;
          _stripWorkSyncMetadata(row);
          await db.insert('work_scores', row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 work_scores 失败: $e');
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService', stack: st);
    }
    return count;
  }

  /// project_scores 导入：
  /// - 仅导入该学生作为评分人（scorer_id）的互评记录
  /// - 不删除/覆盖其他评分人的评分
  Future<int> _importProjectScores(
    dynamic db,
    Map<String, dynamic> data,
    String userId,
  ) async {
    final list = data['project_scores'] as List?;
    if (list == null || list.isEmpty) return 0;

    int count = 0;
    try {
      // 删除该学生作为评分人的旧评分（重新导入）
      await db.delete('project_scores',
          where: 'scorer_id = ?', whereArgs: [userId]);

      for (final r in list) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['scorer_id'] = userId;

          await db.insert('project_scores', row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 project_scores 失败: $e');
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService', stack: st);
    }
    return count;
  }

  // ── 查询已同步的学生数据概览（教师端 UI 用）──────────────────────────

  /// 列出已同步的学生文件概览
  Future<List<Map<String, dynamic>>> listSyncedStudents() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final groupRepos = await _allGroupRepos(db);
      final students = <Map<String, dynamic>>[];

      for (final repo in groupRepos) {
        List<Map<String, dynamic>> files;
        try {
          files = await _gitee.listDir(repo.owner, repo.repo, madDir,
              ref: repoBranch);
        } catch (e) {
          // 该仓库还没有 mad/ 目录（学生未同步过）
          swallow(e, tag: 'SyncService.listSynced.listMadDir');
          continue;
        }
        final jsonFiles = files
            .where((f) =>
                f['type'] == 'file' &&
                (f['name']?.toString() ?? '').endsWith('.json'))
            .toList();

        for (final file in jsonFiles) {
          final filePath = file['path']?.toString() ?? '';
          if (filePath.isEmpty) continue;

          try {
            final content = await _gitee.getFileContent(
                repo.owner, repo.repo, filePath,
                ref: repoBranch);
            if (content == null) continue;

            final data = jsonDecode(content) as Map<String, dynamic>;
            students.add({
              'user_id': data['user_id'] ?? '',
              'user_name': data['user_name'] ?? '',
              'synced_at': data['synced_at'] ?? '',
              'last_active': data['last_active'] ?? '',
              'quiz_count': (data['quiz_results'] as List?)?.length ?? 0,
              'record_count': (data['learning_records'] as List?)?.length ?? 0,
              'wrong_count': (data['wrong_answers'] as List?)?.length ?? 0,
              'feedback_count': (data['feedback'] as List?)?.length ?? 0,
              'favorite_count': (data['favorites'] as List?)?.length ?? 0,
              'path_count': (data['learning_paths'] as List?)?.length ?? 0,
              'lab_count': (data['lab_submissions'] as List?)?.length ?? 0,
              'report_count': (data['student_reports'] as List?)?.length ?? 0,
              'work_count': (data['student_works'] as List?)?.length ?? 0,
              'checkin_count': (data['checkin_records'] as List?)?.length ?? 0,
              'survey_count': (data['survey_responses'] as List?)?.length ?? 0,
            });
          } catch (e) {
            debugPrint('SyncService: 读取 $filePath 概览失败: $e');
          }
        }
      }

      students.sort(
          (a, b) => (a['user_id'] as String).compareTo(b['user_id'] as String));
      return students;
    } catch (e) {
      debugPrint('SyncService: 列出已同步学生失败: $e');
      return [];
    }
  }

  // ── 通知同步 ────────────────────────────────────────────────────────

  /// 上传单个通知到 Gitee
  Future<void> uploadNotification(int notificationId) async {
    try {
      await _ensureSyncToken();
      final db = await DatabaseHelper.instance.database;

      // 查询通知详情
      final notifRows = await db
          .query('notifications', where: 'id = ?', whereArgs: [notificationId]);
      if (notifRows.isEmpty) {
        debugPrint('SyncService: 通知 $notificationId 不存在');
        return;
      }

      final notif = notifRows.first;

      // 查询接收人列表
      final recipientRows = await db.query(
        'notification_recipients',
        where: 'notification_id = ?',
        whereArgs: [notificationId],
      );

      // 构建 JSON
      final data = {
        ...notif,
        'recipients': recipientRows,
      };

      // 生成文件名：notif_{id}_{timestamp}.json
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'notif_${notificationId}_$timestamp.json';
      final content = jsonEncode(data);

      // 上传到 sync/notifications/
      await _gitee.createOrUpdateFile(
        owner: systemRepoOwner,
        repo: systemRepoName,
        path: 'sync/notifications/$fileName',
        content: content,
        message: 'upload notification $notificationId',
        branch: repoBranch,
      );

      debugPrint('SyncService: 通知 $notificationId 已上传到 Gitee');
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.uploadNotification', stack: st);
    }
  }

  /// 从 Gitee 下载所有通知
  Future<void> downloadNotifications() async {
    try {
      await _ensureSyncToken();

      // 列出 sync/notifications/ 目录下的所有文件
      final files = await _gitee.listDir(
        systemRepoOwner,
        systemRepoName,
        'sync/notifications',
        ref: repoBranch,
      );

      for (final file in files) {
        final path = file['path'] as String?;
        if (path == null || !path.endsWith('.json')) continue;

        try {
          // 下载文件内容
          final content = await _gitee.getFileContent(
            systemRepoOwner,
            systemRepoName,
            path,
            ref: repoBranch,
          );

          if (content != null) {
            final data = jsonDecode(content) as Map<String, dynamic>;
            await _importNotification(data);
          }
        } catch (e, st) {
          swallowDebug(e, tag: 'SyncService.downloadNotification', stack: st);
        }
      }

      debugPrint('SyncService: 通知下载完成');
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.downloadNotifications', stack: st);
    }
  }

  /// 导入单个通知到本地数据库（使用自然键去重）
  Future<void> _importNotification(Map<String, dynamic> data) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // 提取通知数据
      final notif = Map<String, dynamic>.from(data);
      final recipients = notif.remove('recipients') as List<dynamic>? ?? [];

      // 使用自然键检查是否已存在：(entity_type, entity_id, created_at, target_id)
      final entityType = notif['related_entity_type'] as String?;
      final entityId = notif['related_entity_id'] as String?;
      final createdAt = notif['created_at'] as String?;
      final targetId = notif['target_id'] as String?;

      if (entityType == null || entityId == null || createdAt == null) {
        return; // 缺少自然键字段
      }

      // 检查是否已存在
      final existing = await db.query(
        'notifications',
        where:
            'related_entity_type = ? AND related_entity_id = ? AND created_at = ? AND target_type = ? AND target_id = ?',
        whereArgs: [
          entityType,
          entityId,
          createdAt,
          notif['target_type'],
          targetId
        ],
        limit: 1,
      );

      int notificationId;
      if (existing.isNotEmpty) {
        // 已存在，使用现有 ID
        notificationId = existing.first['id'] as int;
        debugPrint('SyncService: 通知已存在，跳过 (id=$notificationId)');
      } else {
        // 插入新通知（不指定 id，让数据库自动生成）
        final insertData = Map<String, dynamic>.from(notif);
        insertData.remove('id'); // 移除原 ID
        notificationId = await db.insert('notifications', insertData);
        debugPrint('SyncService: 导入通知 id=$notificationId');
      }

      // 导入接收人记录（使用自然键去重）
      for (final r in recipients) {
        final recipient = r as Map<String, dynamic>;
        final recipientId = recipient['recipient_id'] as String?;
        if (recipientId == null) continue;

        // 检查是否已存在
        final existingRecipient = await db.query(
          'notification_recipients',
          where: 'notification_id = ? AND recipient_id = ?',
          whereArgs: [notificationId, recipientId],
          limit: 1,
        );

        if (existingRecipient.isEmpty) {
          await db.insert('notification_recipients', {
            'notification_id': notificationId,
            'recipient_id': recipientId,
            'is_read': recipient['is_read'] ?? 0,
            'read_at': recipient['read_at'],
          });
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SyncService.importNotification', stack: st);
    }
  }

  /// 测试同步仓库连接
  Future<SyncResult> testConnection() async {
    try {
      await _ensureSyncToken();
      final detail =
          await _gitee.getRepoDetail(systemRepoOwner, systemRepoName);
      final fullName =
          detail['full_name'] ?? '$systemRepoOwner/$systemRepoName';
      final isPrivate = detail['private'] == true ? '私有' : '公开';

      return SyncResult(
        success: true,
        message: '连接成功: $fullName ($isPrivate)',
      );
    } on GiteeApiException catch (e) {
      if (e.statusCode == 404) {
        return SyncResult(success: false, message: '仓库不存在');
      }
      return SyncResult(success: false, message: '连接失败: ${e.message}');
    } catch (e) {
      return SyncResult(success: false, message: '连接失败: $e');
    }
  }
}

// ── 数据类 ──────────────────────────────────────────────────────────────

/// 同步状态
enum SyncStatus { idle, uploading, downloading, error }

/// 同步结果
class SyncResult {
  final bool success;
  final String message;
  final int recordCount;
  final int studentCount;

  SyncResult({
    required this.success,
    required this.message,
    this.recordCount = 0,
    this.studentCount = 0,
  });
}

/// 同步配置（仅开关 + 间隔）
class SyncConfig {
  final bool enabled;
  final int intervalMinutes;
  final String? lastUpload;
  final String? lastDownload;

  SyncConfig({
    this.enabled = true,
    this.intervalMinutes = 3,
    this.lastUpload,
    this.lastDownload,
  });
}
