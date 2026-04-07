import 'package:flutter/foundation.dart';
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
      // Auto-create user account if doesn't exist
      String role = 'student';
      if (userId == '419116') {
        role = 'admin';
      } else if (userId == '206004') {
        role = 'teacher';
      }

      final newUser = UserModel(
        userId: userId,
        realName: role == 'admin'
            ? '管理员 ($userId)'
            : (role == 'teacher' ? '刘老师 ($userId)' : userId),
        role: role,
        createdAt: DateTime.now().toIso8601String(),
      );
      final created = await createUser(newUser);
      if (created) {
        await setCurrentUser(userId, '');
        debugPrint('=== UserDao: Created new user $userId with role $role');
        return true;
      }
      return false;
    }

    if (!user.isActive) {
      return false;
    }

    // 纠正特殊账号的角色（数据库中可能是旧数据）
    String? expectedRole;
    if (userId == '419116') {
      expectedRole = 'admin';
    } else if (userId == '206004') {
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

    // Admin login: userId=419116, password=419116 (last 6 digits)
    if (userId == '419116' && password == '419116') {
      await setCurrentUser(userId, '');
      debugPrint('=== UserDao: Admin login success, role=${user.role}');
      return true;
    }

    // For all users: accept last 6 digits of userId or same as userId
    final last6 =
        userId.length >= 6 ? userId.substring(userId.length - 6) : userId;
    if (password == last6 || password == userId) {
      await setCurrentUser(userId, '');
      debugPrint('=== UserDao: Login success for $userId, role=${user.role}');
      return true;
    }

    return false;
  }

  Future<void> logout() async {
    await clearCurrentUser();
  }
}
