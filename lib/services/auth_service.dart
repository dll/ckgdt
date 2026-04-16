import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../data/local/user_dao.dart';
import '../data/local/database_helper.dart';
import '../data/models/user_model.dart';
import 'sync_service.dart';
import 'gitee_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final UserDao _userDao = UserDao();
  final SyncService _syncService = SyncService();
  UserModel? _currentUser;
  Timer? _heartbeatTimer;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isTeacher => _currentUser?.isTeacher ?? false;

  Future<void> checkLoginStatus() async {
    _currentUser = await _userDao.getCurrentUser();
    if (_currentUser != null) {
      startHeartbeat();
      _startSyncIfEnabled();
    }
  }

  Future<bool> login(String userId, String password) async {
    final success = await _userDao.login(userId, password);
    if (success) {
      _currentUser = await _userDao.getUser(userId);
      startHeartbeat();
      _startSyncIfEnabled();
    }
    return success;
  }

  /// 仅凭 userId 登录（跳过密码验证，用于扫码登录桌面端自动登录）
  Future<bool> loginById(String userId) async {
    final user = await _userDao.getUser(userId);
    if (user == null) return false;
    // 写入 session 表
    await _userDao.setCurrentUser(userId, '');
    _currentUser = user;
    startHeartbeat();
    _startSyncIfEnabled();
    return true;
  }

  Future<void> logout() async {
    stopHeartbeat();
    _syncService.stopAutoSync();
    await _userDao.logout();
    _currentUser = null;
  }

  Future<List<UserModel>> getStudents() async {
    return await _userDao.getStudents();
  }

  Future<bool> createStudent(UserModel student) async {
    return await _userDao.createUser(student);
  }

  Future<bool> updateStudent(UserModel student) async {
    return await _userDao.updateUser(student);
  }

  /// 删除学生 — 级联清理所有关联数据 + 远程同步文件
  Future<bool> deleteStudent(String userId) async {
    final db = await DatabaseHelper.instance.database;

    // 1. 删除所有关联表数据（user_id 字段）
    final userIdTables = [
      'quiz_results',
      'learning_records',
      'wrong_answers',
      'favorites',
      'class_members',
      'notification_recipients',
      'feedback',
      'ai_chat_history',
      'learning_paths',
      'lab_submissions',
      'student_reports',
      'student_works',
      'survey_responses',
      'checkin_records',
      'work_comments',
      'work_likes',
      'work_views',
    ];
    for (final table in userIdTables) {
      try {
        await db.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      } catch (_) {} // 表可能不存在
    }

    // 1b. 特殊字段名的表
    try {
      await db.delete('peer_reviews',
          where: 'reviewer_id = ?', whereArgs: [userId]);
    } catch (_) {}
    try {
      await db.delete('collaboration_messages',
          where: 'sender_id = ?', whereArgs: [userId]);
    } catch (_) {}
    try {
      await db.delete('classroom_messages',
          where: 'sender_id = ?', whereArgs: [userId]);
    } catch (_) {}
    try {
      await db.delete('contribution_scores',
          where: 'scorer_user_id = ? OR target_user_id = ?',
          whereArgs: [userId, userId]);
    } catch (_) {}

    // 1c. path_nodes — 通过 learning_paths 关联
    try {
      final paths = await db.query('learning_paths',
          columns: ['id'], where: 'user_id = ?', whereArgs: [userId]);
      for (final p in paths) {
        await db.delete('path_nodes',
            where: 'path_id = ?', whereArgs: [p['id']]);
      }
    } catch (_) {}

    // 2. 删除用户记录
    final deleted = await _userDao.deleteUser(userId);

    // 3. 删除远程 Gitee 同步文件（异步，静默失败）
    _deleteRemoteSyncFile(userId);

    return deleted;
  }

  /// 清理孤立数据 — 删除所有 user_id 不在 users 表中的关联记录
  /// 返回清理的总记录数
  Future<int> cleanOrphanedData() async {
    final db = await DatabaseHelper.instance.database;
    int totalCleaned = 0;

    // user_id 字段的表
    final userIdTables = [
      'quiz_results',
      'learning_records',
      'wrong_answers',
      'favorites',
      'class_members',
      'notification_recipients',
      'feedback',
      'ai_chat_history',
      'learning_paths',
      'lab_submissions',
      'student_reports',
      'student_works',
      'survey_responses',
      'checkin_records',
      'work_comments',
      'work_likes',
      'work_views',
    ];

    for (final table in userIdTables) {
      try {
        final count = await db.rawDelete(
          'DELETE FROM $table WHERE user_id NOT IN (SELECT user_id FROM users)',
        );
        if (count > 0) {
          debugPrint('AuthService: 清理 $table 中 $count 条孤立记录');
          totalCleaned += count;
        }
      } catch (_) {} // 表可能不存在
    }

    // 特殊字段名的表
    for (final entry in {
      'peer_reviews': 'reviewer_id',
      'collaboration_messages': 'sender_id',
      'classroom_messages': 'sender_id',
    }.entries) {
      try {
        final count = await db.rawDelete(
          'DELETE FROM ${entry.key} WHERE ${entry.value} NOT IN (SELECT user_id FROM users)',
        );
        if (count > 0) {
          debugPrint('AuthService: 清理 ${entry.key} 中 $count 条孤立记录');
          totalCleaned += count;
        }
      } catch (_) {}
    }

    // 同时清理远程同步文件（查找 Gitee 上存在但本地 users 表中不存在的文件）
    _cleanOrphanedRemoteFiles();

    debugPrint('AuthService: 共清理 $totalCleaned 条孤立记录');
    return totalCleaned;
  }

  /// 异步清理远程孤立同步文件
  void _cleanOrphanedRemoteFiles() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final gitee = GiteeService();

      // 获取远程文件列表
      List<Map<String, dynamic>> files;
      try {
        files = await gitee.listDir(
          SyncService.repoOwner,
          SyncService.repoName,
          'sync/students',
          ref: SyncService.repoBranch,
        );
      } catch (_) {
        return; // 目录不存在
      }

      // 获取本地所有学生 user_id
      final users = await db.query('users', columns: ['user_id']);
      final localUserIds = users.map((u) => u['user_id'] as String).toSet();

      // 找出远程存在但本地不存在的文件
      for (final file in files) {
        final name = file['name']?.toString() ?? '';
        if (!name.endsWith('.json')) continue;
        final userId = name.replaceAll('.json', '');
        if (!localUserIds.contains(userId)) {
          _deleteRemoteSyncFile(userId);
        }
      }
    } catch (e) {
      debugPrint('AuthService: 清理远程孤立文件失败: $e');
    }
  }

  /// 异步删除远程同步文件
  void _deleteRemoteSyncFile(String userId) {
    final gitee = GiteeService();
    gitee.deleteFile(
      owner: SyncService.repoOwner,
      repo: SyncService.repoName,
      path: 'sync/students/$userId.json',
      message: '删除学生同步数据: $userId',
      branch: SyncService.repoBranch,
    ).then((_) {
      debugPrint('AuthService: 已删除远程同步文件 $userId.json');
    }).catchError((e) {
      debugPrint('AuthService: 删除远程同步文件失败: $e');
    });
  }

  String? getCurrentUserId() {
    return _currentUser?.userId;
  }

  // ── 密码管理 ──────────────────────────────────────────────────────────

  /// 对密码进行 SHA-256 哈希（加盐 = userId）
  static String hashPassword(String password, String userId) {
    final bytes = utf8.encode('$userId:$password');
    return sha256.convert(bytes).toString();
  }

  /// 验证密码（支持 hash 和默认密码双模式）
  bool verifyPassword(String password, UserModel user) {
    if (user.hasCustomPassword) {
      return hashPassword(password, user.userId) == user.passwordHash;
    }
    // 默认密码：后6位或全userId
    final last6 = user.defaultPassword;
    return password == last6 || password == user.userId;
  }

  /// 修改密码：验证旧密码 → 存储新密码哈希
  Future<bool> changePassword(
      String userId, String currentPassword, String newPassword) async {
    final user = await _userDao.getUser(userId);
    if (user == null) return false;

    // 验证当前密码
    if (!verifyPassword(currentPassword, user)) return false;

    // 存储新密码哈希
    final hash = hashPassword(newPassword, userId);
    final success = await _userDao.updatePasswordHash(userId, hash);
    if (success) {
      // 刷新内存中的用户
      _currentUser = await _userDao.getUser(userId);
    }
    return success;
  }

  /// 管理员重置学生密码（清除 hash → 恢复默认密码）
  Future<bool> resetStudentPassword(String userId) async {
    return await _userDao.resetPassword(userId);
  }

  // ── 心跳机制 ──────────────────────────────────────────────────────────

  /// 启动心跳定时器，每 2 分钟更新 last_active
  void startHeartbeat() {
    stopHeartbeat();
    _updateHeartbeat(); // 立即更新一次
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _updateHeartbeat(),
    );
  }

  /// 停止心跳定时器
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _updateHeartbeat() async {
    final userId = _currentUser?.userId;
    if (userId != null) {
      await _userDao.updateLastActive(userId);
    }
  }

  // ── 数据同步 ──────────────────────────────────────────────────────────

  /// 启动自动同步（如果已启用）
  Future<void> _startSyncIfEnabled() async {
    final userId = _currentUser?.userId;
    final role = _currentUser?.role;
    if (userId != null && role != null) {
      await _syncService.startAutoSync(userId: userId, role: role);
    }
  }

  /// 手动重启同步定时器（配置变更后调用）
  Future<void> restartSync() async {
    _syncService.stopAutoSync();
    await _startSyncIfEnabled();
  }
}
