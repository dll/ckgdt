import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/database_helper.dart';
import 'gitee_service.dart';

/// 数据同步服务
///
/// 直接使用本项目的 Gitee 仓库 osgisOne/mad-fd。
/// 同步使用独立的读写 Token（sync_gitee_token），与 GiteeService 的只读 Token 分开。
/// 学生端：定时将本地学习数据上传到 sync/students/{user_id}.json
/// 教师端：定时从 sync/students/ 拉取所有学生数据合并到本地 DB
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final GiteeService _gitee = GiteeService();

  // ── 固定仓库配置（本项目仓库）──────────────────────────────────────────

  static const repoOwner = 'osgisOne';
  static const repoName = 'mad-fd';
  static const repoBranch = 'master';
  static const _syncDir = 'sync/students';

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

  /// 预置读写 Token（osgisOne/mad-fd 仓库，具有 projects 读写权限）
  /// 如果没有配置过同步 Token，自动使用此默认值
  static const _defaultSyncToken = '64a07762f8a3ab4415b8c943651bfb91';

  /// 确保同步 Token 已配置（首次使用时自动设置）
  Future<void> _ensureSyncToken() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_syncTokenKey);
    if (existing == null || existing.isEmpty) {
      await prefs.setString(_syncTokenKey, _defaultSyncToken);
      // 同时确保 GiteeService 也配置了此 Token
      final giteeToken = await _gitee.getToken();
      if (giteeToken == null || giteeToken.isEmpty) {
        await _gitee.saveToken(_defaultSyncToken);
      }
    }
  }

  /// 获取同步专用 Token
  Future<String?> getSyncToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_syncTokenKey) ?? _defaultSyncToken;
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
    return prefs.getInt(_syncIntervalKey) ?? 3;
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
  Future<void> saveConfig({required bool enabled, required int interval}) async {
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
    debugPrint('SyncService: 自动同步已启动 (每 $interval 分钟, 仓库: $repoOwner/$repoName)');
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
        await uploadStudentData(userId);
      } else {
        await downloadAllStudentData();
      }
    } catch (e) {
      debugPrint('SyncService: 自动同步失败: $e');
    }
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
      } catch (_) {}

      // 1. 收集本地数据
      final data = await _collectStudentData(userId);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      // 2. 上传到 Gitee
      final path = '$_syncDir/$userId.json';
      await _gitee.createOrUpdateFile(
        owner: repoOwner,
        repo: repoName,
        path: path,
        content: jsonStr,
        message: '同步学生数据: $userId (${DateTime.now().toIso8601String()})',
        branch: repoBranch,
      );

      // 3. 记录同步时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastUploadTimeKey, DateTime.now().toIso8601String());

      final recordCount = (data['quiz_results'] as List).length +
          (data['learning_records'] as List).length +
          (data['wrong_answers'] as List).length;

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

  /// 收集学生本地数据
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
    final lastActive = userRows.isNotEmpty
        ? (userRows.first['last_active'] as String?)
        : null;

    // 测验成绩
    final quizResults = await db.query(
      'quiz_results',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'quiz_timestamp DESC',
    );

    // 学习记录
    final learningRecords = await db.query(
      'learning_records',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'completed_at DESC',
    );

    // 错题记录
    final wrongAnswers = await db.query(
      'wrong_answers',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    // 收藏记录
    final favorites = await db.query(
      'favorites',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    return {
      'version': '1.0',
      'user_id': userId,
      'user_name': userName,
      'role': 'student',
      'synced_at': DateTime.now().toIso8601String(),
      'last_active': lastActive ?? DateTime.now().toIso8601String(),
      'quiz_results': quizResults
          .map((r) => Map<String, dynamic>.from(r)..remove('id'))
          .toList(),
      'learning_records': learningRecords
          .map((r) => Map<String, dynamic>.from(r)..remove('id'))
          .toList(),
      'wrong_answers': wrongAnswers
          .map((r) => Map<String, dynamic>.from(r)..remove('id'))
          .toList(),
      'favorites': favorites
          .map((r) => Map<String, dynamic>.from(r)..remove('id'))
          .toList(),
    };
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
      // 1. 列出 sync/students/ 目录下的所有文件
      List<Map<String, dynamic>> files;
      try {
        files = await _gitee.listDir(
            repoOwner, repoName, _syncDir, ref: repoBranch);
      } catch (e) {
        // 目录不存在说明还没有学生上传过数据
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _lastDownloadTimeKey, DateTime.now().toIso8601String());
        status.value = SyncStatus.idle;
        return SyncResult(
          success: true,
          message: '暂无学生同步数据（sync 目录尚未创建）',
          recordCount: 0,
        );
      }

      final jsonFiles = files
          .where((f) =>
              f['type'] == 'file' &&
              (f['name']?.toString() ?? '').endsWith('.json'))
          .toList();

      if (jsonFiles.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _lastDownloadTimeKey, DateTime.now().toIso8601String());
        status.value = SyncStatus.idle;
        return SyncResult(
          success: true,
          message: '暂无学生数据',
          recordCount: 0,
        );
      }

      // 2. 逐个下载并解析
      int totalRecords = 0;
      int studentCount = 0;
      final db = await DatabaseHelper.instance.database;

      for (final file in jsonFiles) {
        final filePath = file['path']?.toString() ?? '';
        if (filePath.isEmpty) continue;

        try {
          final content = await _gitee.getFileContent(
            repoOwner, repoName, filePath,
            ref: repoBranch,
          );
          if (content == null) continue;

          final data = jsonDecode(content) as Map<String, dynamic>;
          final count = await _importStudentSyncData(db, data);
          totalRecords += count;
          studentCount++;
        } catch (e) {
          debugPrint('SyncService: 解析 $filePath 失败: $e');
        }
      }

      // 3. 记录同步时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastDownloadTimeKey, DateTime.now().toIso8601String());

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
      // 用户不存在，创建新记录
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
      // 用户已存在，更新 last_active 和 real_name
      final updates = <String, dynamic>{};
      if (lastActive != null) updates['last_active'] = lastActive;
      if (userName.isNotEmpty) updates['real_name'] = userName;
      if (updates.isNotEmpty) {
        try {
          await db.update(
            'users',
            updates,
            where: 'user_id = ?',
            whereArgs: [userId],
          );
        } catch (_) {}
      }
    }

    // ── 确保班级成员关联（加入默认班级）──────────────────────────────────
    try {
      // 检查是否已有班级关联
      final memberCheck = await db.query(
        'class_members',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (memberCheck.isEmpty) {
        // 查找第一个班级（默认班级）
        final classes = await db.query('classes', limit: 1, orderBy: 'id');
        int classId;
        if (classes.isNotEmpty) {
          classId = classes.first['id'] as int;
        } else {
          // 没有班级则创建一个默认班级
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

    // 导入测验成绩
    final quizResults = data['quiz_results'] as List?;
    if (quizResults != null && quizResults.isNotEmpty) {
      await db.delete('quiz_results',
          where: 'user_id = ?', whereArgs: [userId]);
      for (final r in quizResults) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;
          await db.insert('quiz_results', row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 quiz_result 失败: $e');
        }
      }
    }

    // 导入学习记录
    final learningRecords = data['learning_records'] as List?;
    if (learningRecords != null && learningRecords.isNotEmpty) {
      await db.delete('learning_records',
          where: 'user_id = ?', whereArgs: [userId]);
      for (final r in learningRecords) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;
          await db.insert('learning_records', row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 learning_record 失败: $e');
        }
      }
    }

    // 导入错题记录
    final wrongAnswers = data['wrong_answers'] as List?;
    if (wrongAnswers != null && wrongAnswers.isNotEmpty) {
      await db.delete('wrong_answers',
          where: 'user_id = ?', whereArgs: [userId]);
      for (final r in wrongAnswers) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;
          await db.insert('wrong_answers', row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 wrong_answer 失败: $e');
        }
      }
    }

    // 导入收藏记录
    final favorites = data['favorites'] as List?;
    if (favorites != null && favorites.isNotEmpty) {
      await db.delete('favorites',
          where: 'user_id = ?', whereArgs: [userId]);
      for (final r in favorites) {
        try {
          final row = Map<String, dynamic>.from(r as Map);
          row.remove('id');
          row['user_id'] = userId;
          await db.insert('favorites', row);
          count++;
        } catch (e) {
          debugPrint('SyncService: 导入 favorite 失败: $e');
        }
      }
    }

    return count;
  }

  // ── 查询已同步的学生数据概览（教师端 UI 用）──────────────────────────

  /// 列出已同步的学生文件概览
  Future<List<Map<String, dynamic>>> listSyncedStudents() async {
    try {
      final files = await _gitee.listDir(
          repoOwner, repoName, _syncDir, ref: repoBranch);
      final jsonFiles = files
          .where((f) =>
              f['type'] == 'file' &&
              (f['name']?.toString() ?? '').endsWith('.json'))
          .toList();

      final students = <Map<String, dynamic>>[];

      for (final file in jsonFiles) {
        final filePath = file['path']?.toString() ?? '';
        if (filePath.isEmpty) continue;

        try {
          final content = await _gitee.getFileContent(
              repoOwner, repoName, filePath, ref: repoBranch);
          if (content == null) continue;

          final data = jsonDecode(content) as Map<String, dynamic>;
          students.add({
            'user_id': data['user_id'] ?? '',
            'user_name': data['user_name'] ?? '',
            'synced_at': data['synced_at'] ?? '',
            'last_active': data['last_active'] ?? '',
            'quiz_count': (data['quiz_results'] as List?)?.length ?? 0,
            'record_count':
                (data['learning_records'] as List?)?.length ?? 0,
            'wrong_count': (data['wrong_answers'] as List?)?.length ?? 0,
          });
        } catch (e) {
          debugPrint('SyncService: 读取 $filePath 概览失败: $e');
        }
      }

      students.sort((a, b) =>
          (a['user_id'] as String).compareTo(b['user_id'] as String));
      return students;
    } catch (e) {
      debugPrint('SyncService: 列出已同步学生失败: $e');
      return [];
    }
  }

  /// 测试同步仓库连接
  Future<SyncResult> testConnection() async {
    try {
      await _ensureSyncToken();
      final detail = await _gitee.getRepoDetail(repoOwner, repoName);
      final fullName = detail['full_name'] ?? '$repoOwner/$repoName';
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
