import 'dart:convert';
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

  Future<List<UserModel>> getStudents() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'users',
      where: 'role = ?',
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
    return maps.map((map) => UserModel.fromMap(map)).toList();
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
        realName = '刘畅';
      } else if (userId == '206004') {
        role = 'teacher';
        realName = '刘东良';
      } else if (userId == '203014') {
        role = 'teacher';
        realName = '徐志红';
      } else {
        // 必须在 students.json 名单中才允许登录
        realName = await _getStudentRealName(userId);
        if (realName == null) {
          debugPrint('=== UserDao: Login rejected — $userId not in students.json');
          return false;
        }
      }

      // 验证密码（后 6 位 或 完整学号）
      final last6 = userId.length >= 6
          ? userId.substring(userId.length - 6)
          : userId;
      if (password != last6 && password != userId) {
        debugPrint('=== UserDao: Login rejected — wrong password for new user $userId');
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
      if (nameCheck == null &&
          userId != '419116' && userId != '206004' && userId != '203014') {
        debugPrint('=== UserDao: Existing user $userId not in students.json, rejecting');
        return false;
      }
    }

    // Update real name for existing users (including admin and teacher)
    String? realNameUpdate;
    if (userId == '419116') {
      realNameUpdate = '刘畅';
    } else if (userId == '206004') {
      realNameUpdate = '刘东良';
    } else if (userId == '203014') {
      realNameUpdate = '徐志红';
    } else {
      realNameUpdate = await _getStudentRealName(userId);
    }

    if (realNameUpdate != null && user.realName != realNameUpdate) {
      final updatedUser = UserModel(
        userId: user.userId,
        realName: realNameUpdate,
        machineCode: user.machineCode,
        role: user.role,
        createdAt: user.createdAt,
        lastLogin: user.lastLogin,
        isActive: user.isActive,
      );
      await updateUser(updatedUser);
      user = updatedUser;
      debugPrint(
          '=== UserDao: Updated real name for $userId to $realNameUpdate');
    }

    if (!user.isActive) {
      return false;
    }

    // 纠正特殊账号的角色（数据库中可能是旧数据）
    String? expectedRole;
    if (userId == '419116') {
      expectedRole = 'admin';
    } else if (userId == '206004' || userId == '203014') {
      expectedRole = 'teacher';
    }
    if (expectedRole != null && user.role != expectedRole) {
      final corrected = UserModel(
        userId: user.userId,
        realName: user.realName,
        machineCode: user.machineCode,
        role: expectedRole,
        createdAt: user.createdAt,
        lastLogin: user.lastLogin,
        isActive: user.isActive,
      );
      await updateUser(corrected);
      user = corrected;
      debugPrint('=== UserDao: Corrected role for $userId to $expectedRole');
    }

    // Teacher login: userId=206004 or 203014, password=账号 or 后6位
    if ((userId == '206004' || userId == '203014') &&
        (password == userId ||
            password == userId.substring(userId.length - 6))) {
      await setCurrentUser(userId, '');
      await _updateLastLogin(userId);
      debugPrint(
          '=== UserDao: Teacher login success for $userId, role=${user.role}');
      return true;
    }

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
}
