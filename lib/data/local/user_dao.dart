import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import 'database_helper.dart';

class UserDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<UserModel?> getUser(String userId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'users',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    if (maps.isNotEmpty) {
      return UserModel.fromMap(maps.first);
    }
    return null;
  }

  Future<List<UserModel>> getAllUsers() async {
    final db = await _dbHelper.database;
    final maps = await db.query('users', orderBy: 'created_at DESC');
    return maps.map((map) => UserModel.fromMap(map)).toList();
  }

  /// 获取学生列表。默认只返回活跃学生（is_active=1）；
  /// 需要看归档/已停用学生（如审计、孤立数据清理）时传 includeInactive: true。
  Future<List<UserModel>> getStudents({bool includeInactive = false}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'users',
      where: includeInactive ? 'role = ?' : 'role = ? AND is_active = 1',
      whereArgs: ['student'],
      orderBy: 'user_id',
    );
    return maps.map((map) => UserModel.fromMap(map)).toList();
  }

  Future<List<UserModel>> getTeachers() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'users',
      where: 'role IN (?, ?)',
      whereArgs: ['teacher', 'admin'],
      orderBy: 'real_name',
    );
    final all = maps.map((map) => UserModel.fromMap(map)).toList();

    // 去重：如果同一 real_name 对应多条记录（如 teacher_206004 和 206004），
    // 优先保留不带 teacher_ 前缀的记录
    final seen = <String, UserModel>{};
    for (final t in all) {
      final key = t.realName ?? t.userId;
      if (seen.containsKey(key)) {
        // 保留不带 teacher_ 前缀的那个
        if (seen[key]!.userId.startsWith('teacher_')) {
          seen[key] = t;
        }
      } else {
        seen[key] = t;
      }
    }
    return seen.values.toList();
  }

  Future<bool> createUser(UserModel user) async {
    final db = await _dbHelper.database;
    try {
      await db.insert('users', user.toMap());
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateUser(UserModel user) async {
    final db = await _dbHelper.database;
    final count = await db.update(
      'users',
      user.toMap(),
      where: 'user_id = ?',
      whereArgs: [user.userId],
    );
    return count > 0;
  }

  Future<bool> deleteUser(String userId) async {
    final db = await _dbHelper.database;
    final count = await db.delete(
      'users',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return count > 0;
  }

  Future<void> setCurrentUser(String userId, String machineCode) async {
    final db = await _dbHelper.database;
    await db.delete('current_session');
    await db.insert('current_session', {
      'id': 1,
      'user_id': userId,
      'machine_code': machineCode,
      'login_time': DateTime.now().toIso8601String(),
    });
  }

  Future<UserModel?> getCurrentUser() async {
    final db = await _dbHelper.database;
    final maps = await db.query('current_session', where: 'id = 1');
    if (maps.isNotEmpty) {
      final userId = maps.first['user_id'] as String?;
      if (userId != null) {
        return await getUser(userId);
      }
    }
    return null;
  }

  Future<void> clearCurrentUser() async {
    final db = await _dbHelper.database;
    await db.delete('current_session');
  }

  Future<bool> login(String userId, String password) async {
    var user = await getUser(userId);

    if (user == null) {
      // 确定角色和姓名
      String role = 'student';
      String? realName;

      if (userId == '419116') {
        role = 'admin';
        realName = '刘老师';
      } else {
        // 必须在 students.json 名单中才允许登录
        realName = await _getStudentRealName(userId);
        if (realName == null) {
          debugPrint(
              '=== UserDao: Login rejected — $userId not in allowed user lists');
          return false;
        }
      }

      // 验证密码（后 6 位 或 完整学号）
      final last6 =
          userId.length >= 6 ? userId.substring(userId.length - 6) : userId;
      if (password != last6 && password != userId) {
        debugPrint(
            '=== UserDao: Login rejected — wrong password for new user $userId');
        return false;
      }

      final newUser = UserModel(
        userId: userId,
        realName: realName,
        role: role,
        createdAt: DateTime.now().toIso8601String(),
      );
      final created = await createUser(newUser);
      if (created) {
        await setCurrentUser(userId, '');
        await _updateLastLogin(userId);
        debugPrint(
            '=== UserDao: Created new user $userId with role $role, name $realName');
        return true;
      }
      return false;
    }

    // 非名单内的学生也禁止登录（防止旧数据库有脏记录）
    if (user.role == 'student') {
      final nameCheck = await _getStudentRealName(userId);
      if (nameCheck == null) {
        debugPrint(
            '=== UserDao: Existing user $userId not in students.json, rejecting');
        return false;
      }
    }

    // Update real name for existing students from students.json. Teacher/admin
    // names and roles are synchronized from data/用户/管理员教师名单.xlsx during
    // database initialization, so login does not overwrite the roster source.
    String? realNameUpdate;
    if (user.role == 'student') {
      realNameUpdate = await _getStudentRealName(userId);
    }

    if (realNameUpdate != null && user.realName != realNameUpdate) {
      final updatedUser = user.copyWith(realName: realNameUpdate);
      await updateUser(updatedUser);
      user = updatedUser;
      debugPrint(
          '=== UserDao: Updated real name for $userId to $realNameUpdate');
    }

    if (!user.isActive) {
      return false;
    }

    // 纠正管理员账号的角色（数据库中可能是旧数据）。教师角色来源于
    // data/用户/管理员教师名单.xlsx 的初始化同步。
    String? expectedRole;
    if (userId == '419116') {
      expectedRole = 'admin';
    }
    if (expectedRole != null && user.role != expectedRole) {
      final corrected = user.copyWith(role: expectedRole);
      await updateUser(corrected);
      user = corrected;
      debugPrint('=== UserDao: Corrected role for $userId to $expectedRole');
    }

    // ── 如果用户设置了自定义密码，优先用 hash 验证 ──
    if (user.hasCustomPassword) {
      // 使用 AuthService 的哈希算法验证
      final testHash = _hashPassword(password, userId);
      if (testHash == user.passwordHash) {
        await setCurrentUser(userId, '');
        await _updateLastLogin(userId);
        debugPrint('=== UserDao: Login success (custom password) for $userId');
        return true;
      }
      debugPrint(
          '=== UserDao: Login failed — wrong custom password for $userId');
      return false;
    }

    // ── 默认密码验证（后6位或完整userId） ──

    // Admin login: userId=419116, password=419116 or last 6 digits (9116)
    if (userId == '419116' && (password == '419116' || password == '9116')) {
      await setCurrentUser(userId, '');
      await _updateLastLogin(userId);
      debugPrint('=== UserDao: Admin login success, role=${user.role}');
      return true;
    }

    // For all users: accept last 6 digits of userId or same as userId
    final last6 =
        userId.length >= 6 ? userId.substring(userId.length - 6) : userId;
    if (password == last6 || password == userId) {
      await setCurrentUser(userId, '');
      await _updateLastLogin(userId);
      debugPrint('=== UserDao: Login success for $userId, role=${user.role}');
      return true;
    }

    return false;
  }

  /// SHA-256 哈希（与 AuthService.hashPassword 保持一致）
  String _hashPassword(String password, String userId) {
    final bytes = utf8.encode('$userId:$password');
    return sha256.convert(bytes).toString();
  }

  Future<void> logout() async {
    await clearCurrentUser();
  }

  Future<String?> _getStudentRealName(String userId) async {
    try {
      final jsonStr = await rootBundle.loadString('assets/students.json');
      final students = json.decode(jsonStr) as List;
      for (final s in students) {
        if (s['user_id'] == userId) {
          return s['real_name'] as String?;
        }
      }
    } catch (e) {
      debugPrint('=== UserDao: Error loading students.json: $e');
    }
    return null;
  }

  /// 更新用户 last_login 时间戳
  Future<void> _updateLastLogin(String userId) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      {'last_login': DateTime.now().toIso8601String()},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// 更新用户活跃时间（心跳）
  Future<void> updateLastActive(String userId) async {
    final db = await _dbHelper.database;
    try {
      await db.update(
        'users',
        {'last_active': DateTime.now().toIso8601String()},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    } catch (_) {}
  }

  // ── 密码管理 ──────────────────────────────────────────────────────────

  /// 更新密码哈希
  Future<bool> updatePasswordHash(String userId, String hash) async {
    final db = await _dbHelper.database;
    try {
      final count = await db.update(
        'users',
        {'password_hash': hash},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  /// 重置密码（清除 hash → 恢复默认密码）
  Future<bool> resetPassword(String userId) async {
    final db = await _dbHelper.database;
    try {
      final count = await db.update(
        'users',
        {'password_hash': null},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }
}
