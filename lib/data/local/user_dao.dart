import 'package:sqflite/sqflite.dart';
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
      // Auto-create student account if doesn't exist
      final newUser = UserModel(
        userId: userId,
        realName: userId,
        role: userId == '419116' ? 'admin' : 'student',
        createdAt: DateTime.now().toIso8601String(),
      );
      final created = await createUser(newUser);
      if (created) {
        await setCurrentUser(userId, '');
        return true;
      }
      return false;
    }
    
    if (!user.isActive) {
      return false;
    }

    // Admin login with special password
    if (userId == '419116' && password == 'osgis123') {
      await setCurrentUser(userId, '');
      return true;
    }
    
    // For students: accept last 6 digits, empty, or same as userId
    if (user.role == 'student') {
      final last6 = userId.length >= 6 ? userId.substring(userId.length - 6) : userId;
      if (password == last6 || password.isEmpty || password == userId) {
        await setCurrentUser(userId, '');
        return true;
      }
    }
    
    // For teachers: accept same as userId or any 6+ chars
    if (user.role == 'teacher' || user.role == 'admin') {
      if (password == userId || password.length >= 6) {
        await setCurrentUser(userId, '');
        return true;
      }
    }
    
    return false;
  }

  Future<void> logout() async {
    await clearCurrentUser();
  }
}
