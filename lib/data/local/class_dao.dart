import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'database_helper.dart';

/// 班级管理 DAO — 班级 CRUD、成员管理、归档功能
class ClassDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // 班级 CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取所有未归档班级
  Future<List<Map<String, dynamic>>> getActiveClasses() async {
    final db = await _dbHelper.database;
    return await db.query(
      'classes',
      where: 'is_archived = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );
  }

  /// 获取所有已归档班级
  Future<List<Map<String, dynamic>>> getArchivedClasses() async {
    final db = await _dbHelper.database;
    return await db.query(
      'classes',
      where: 'is_archived = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC',
    );
  }

  /// 获取所有班级（含归档）
  Future<List<Map<String, dynamic>>> getAllClasses() async {
    final db = await _dbHelper.database;
    return await db.query('classes', orderBy: 'is_archived ASC, created_at DESC');
  }

  /// 获取单个班级
  Future<Map<String, dynamic>?> getClass(int classId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'classes',
      where: 'id = ?',
      whereArgs: [classId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// 创建班级
  Future<int> createClass({
    required String name,
    String? semester,
    String? teacherId,
    String? teacherName,
    String? description,
  }) async {
    final db = await _dbHelper.database;
    return await db.insert('classes', {
      'name': name,
      'semester': semester,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'description': description,
      'student_count': 0,
      'is_archived': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// 更新班级
  Future<bool> updateClass(int classId, Map<String, dynamic> data) async {
    final db = await _dbHelper.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    final count = await db.update(
      'classes',
      data,
      where: 'id = ?',
      whereArgs: [classId],
    );
    return count > 0;
  }

  /// 删除班级（同时删除成员关联）
  Future<bool> deleteClass(int classId) async {
    final db = await _dbHelper.database;
    await db.delete('class_members', where: 'class_id = ?', whereArgs: [classId]);
    final count = await db.delete('classes', where: 'id = ?', whereArgs: [classId]);
    return count > 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 归档功能
  // ─────────────────────────────────────────────────────────────────────────

  /// 归档班级
  Future<bool> archiveClass(int classId) async {
    return await updateClass(classId, {'is_archived': 1});
  }

  /// 取消归档
  Future<bool> unarchiveClass(int classId) async {
    return await updateClass(classId, {'is_archived': 0});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 成员管理
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取班级成员列表
  Future<List<Map<String, dynamic>>> getClassMembers(int classId) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT cm.*, u.real_name, u.role as user_role, u.is_active
      FROM class_members cm
      LEFT JOIN users u ON cm.user_id = u.user_id
      WHERE cm.class_id = ?
      ORDER BY u.user_id
    ''', [classId]);
  }

  /// 获取班级学生列表
  Future<List<UserModel>> getClassStudents(int classId) async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT u.*
      FROM class_members cm
      INNER JOIN users u ON cm.user_id = u.user_id
      WHERE cm.class_id = ? AND cm.role = 'student'
      ORDER BY u.user_id
    ''', [classId]);
    return maps.map((m) => UserModel.fromMap(m)).toList();
  }

  /// 添加成员到班级
  Future<bool> addMember(int classId, String userId, {String role = 'student'}) async {
    final db = await _dbHelper.database;
    try {
      await db.insert('class_members', {
        'class_id': classId,
        'user_id': userId,
        'role': role,
        'joined_at': DateTime.now().toIso8601String(),
      });
      await _updateStudentCount(classId);
      return true;
    } catch (e) {
      debugPrint('ClassDao.addMember error: $e');
      return false; // 重复添加会触发 UNIQUE 约束
    }
  }

  /// 批量添加成员
  Future<int> addMembers(int classId, List<String> userIds, {String role = 'student'}) async {
    final db = await _dbHelper.database;
    int added = 0;
    final batch = db.batch();
    for (final uid in userIds) {
      batch.insert(
        'class_members',
        {
          'class_id': classId,
          'user_id': uid,
          'role': role,
          'joined_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: null, // 忽略重复
      );
    }
    try {
      await batch.commit(noResult: true);
      // 重新统计实际数量
      await _updateStudentCount(classId);
      final members = await getClassMembers(classId);
      added = members.length;
    } catch (e) {
      debugPrint('ClassDao.addMembers error: $e');
    }
    return added;
  }

  /// 移除成员
  Future<bool> removeMember(int classId, String userId) async {
    final db = await _dbHelper.database;
    final count = await db.delete(
      'class_members',
      where: 'class_id = ? AND user_id = ?',
      whereArgs: [classId, userId],
    );
    if (count > 0) {
      await _updateStudentCount(classId);
    }
    return count > 0;
  }

  /// 获取未分配到任何班级的学生
  Future<List<UserModel>> getUnassignedStudents() async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT u.*
      FROM users u
      WHERE u.role = 'student' AND u.is_active = 1
        AND u.user_id NOT IN (
          SELECT cm.user_id FROM class_members cm
          INNER JOIN classes c ON cm.class_id = c.id
          WHERE c.is_archived = 0
        )
      ORDER BY u.user_id
    ''');
    return maps.map((m) => UserModel.fromMap(m)).toList();
  }

  /// 获取学生所属班级
  Future<List<Map<String, dynamic>>> getStudentClasses(String userId) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT c.*
      FROM class_members cm
      INNER JOIN classes c ON cm.class_id = c.id
      WHERE cm.user_id = ?
      ORDER BY c.is_archived ASC, c.created_at DESC
    ''', [userId]);
  }

  /// 获取教师负责的班级
  Future<List<Map<String, dynamic>>> getTeacherClasses(String teacherId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'classes',
      where: 'teacher_id = ?',
      whereArgs: [teacherId],
      orderBy: 'is_archived ASC, created_at DESC',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 统计
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取班级统计概览
  Future<Map<String, int>> getClassStats() async {
    final db = await _dbHelper.database;
    final total = await db.rawQuery('SELECT COUNT(*) as c FROM classes');
    final active = await db.rawQuery(
        'SELECT COUNT(*) as c FROM classes WHERE is_archived = 0');
    final archived = await db.rawQuery(
        'SELECT COUNT(*) as c FROM classes WHERE is_archived = 1');
    return {
      'total': (total.first['c'] as int?) ?? 0,
      'active': (active.first['c'] as int?) ?? 0,
      'archived': (archived.first['c'] as int?) ?? 0,
    };
  }

  /// 获取学期列表（去重）
  Future<List<String>> getSemesters() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
        'SELECT DISTINCT semester FROM classes WHERE semester IS NOT NULL ORDER BY semester DESC');
    return result.map((r) => r['semester'] as String).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 示例数据
  // ─────────────────────────────────────────────────────────────────────────

  /// 生成示例班级数据
  Future<void> generateDemoData() async {
    final db = await _dbHelper.database;
    final count = await db.rawQuery('SELECT COUNT(*) as c FROM classes');
    if (((count.first['c'] as int?) ?? 0) > 0) return; // 已有数据则跳过

    // 创建示例班级
    final classId1 = await createClass(
      name: '移动应用开发 2024-A班',
      semester: '2024-2025学年第一学期',
      teacherId: '206004',
      teacherName: '刘老师',
      description: '《移动应用开发》课程A班，Flutter方向',
    );

    final classId2 = await createClass(
      name: '移动应用开发 2024-B班',
      semester: '2024-2025学年第一学期',
      teacherId: '206004',
      teacherName: '刘老师',
      description: '《移动应用开发》课程B班，React Native方向',
    );

    // 归档一个旧班级做示例
    final classId3 = await createClass(
      name: '移动应用开发 2023-A班',
      semester: '2023-2024学年第二学期',
      teacherId: '206004',
      teacherName: '刘老师',
      description: '已结课归档',
    );
    await archiveClass(classId3);

    // 将现有学生分配到班级
    final students = await db.query('users',
        where: 'role = ? AND is_active = 1',
        whereArgs: ['student'],
        orderBy: 'user_id');

    for (int i = 0; i < students.length; i++) {
      final uid = students[i]['user_id'] as String;
      if (i < students.length ~/ 2) {
        await addMember(classId1, uid);
      } else {
        await addMember(classId2, uid);
      }
    }

    debugPrint('ClassDao: 示例数据生成完成 — $classId1, $classId2, $classId3');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 私有方法
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _updateStudentCount(int classId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM class_members WHERE class_id = ? AND role = ?',
      [classId, 'student'],
    );
    final count = (result.first['c'] as int?) ?? 0;
    await db.update('classes', {'student_count': count},
        where: 'id = ?', whereArgs: [classId]);
  }
}
