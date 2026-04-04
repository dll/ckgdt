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

  /// 生成示例班级数据（计科22 已归档 + 软件23 当前学期）
  Future<void> generateDemoData() async {
    final db = await _dbHelper.database;
    final count = await db.rawQuery('SELECT COUNT(*) as c FROM classes');
    if (((count.first['c'] as int?) ?? 0) > 0) return; // 已有数据则跳过

    // ── 计科22：已结课归档（上一学年） ──────────────────────────────────
    final classIdJK22 = await createClass(
      name: '计科22 移动应用开发',
      semester: '2024-2025学年第一学期',
      teacherId: '206004',
      teacherName: '刘东良',
      description: '计算机科学与技术2022级，86名学生，3个班组，9个实验项目。'
          '每组6人，实验中每人选择一个技术栈独立完成对应实验任务。',
    );
    await archiveClass(classIdJK22);

    // ── 软件23：当前活跃学期 ──────────────────────────────────────────
    final classIdRJ23 = await createClass(
      name: '软件23 移动应用开发',
      semester: '2025-2026学年第一学期',
      teacherId: '206004',
      teacherName: '刘东良',
      description: '软件工程2023级，项目分组待定（占位模拟中）。'
          '每组6人协作探究模式，每人负责一个技术栈。',
    );

    // 将所有在册学生分配到软件23（计科22已归档，无需分配）
    final students = await db.query('users',
        where: 'role = ? AND is_active = 1',
        whereArgs: ['student'],
        orderBy: 'user_id');

    for (final s in students) {
      final uid = s['user_id'] as String;
      await addMember(classIdRJ23, uid);
    }

    debugPrint('ClassDao: 示例数据生成完成 — '
        '计科22(id=$classIdJK22, archived), '
        '软件23(id=$classIdRJ23, active, ${students.length}名学生)');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 项目分组
  // ─────────────────────────────────────────────────────────────────────────

  /// 课程实验项目定义（9 个项目 × 3 个班组）
  static const List<Map<String, String>> _projectDefinitions = [
    // ── 班组1 ──
    {
      'group_name': '班组1',
      'project_name': '适老居家生活辅助系统',
      'project_abbr': 'EHLAS',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    {
      'group_name': '班组1',
      'project_name': '智慧社区生活服务平台开发与整合',
      'project_abbr': 'SCLSPDI',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    {
      'group_name': '班组1',
      'project_name': '智能健康运动记录平台开发与整合',
      'project_abbr': 'IHFTPDI',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    // ── 班组2 ──
    {
      'group_name': '班组2',
      'project_name': '云端智能畜牧养殖管理系统',
      'project_abbr': 'CIFMS',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    {
      'group_name': '班组2',
      'project_name': '线上购物平台开发与整合',
      'project_abbr': 'OSPDI',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    {
      'group_name': '班组2',
      'project_name': '二手物品交易平台开发与整合',
      'project_abbr': 'SGTPDI',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    // ── 班组3 ──
    {
      'group_name': '班组3',
      'project_name': '在线学习辅助平台开发与整合',
      'project_abbr': 'OLAPDI',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    {
      'group_name': '班组3',
      'project_name': '智慧校园生活服务平台开发与整合',
      'project_abbr': 'SCLSPI',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
    {
      'group_name': '班组3',
      'project_name': '农业大棚监控系统',
      'project_abbr': 'AGMS',
      'tech_stacks': 'Android开发, iOS/HarmonyOS开发, Uniapp开发, Flutter开发, 小程序开发, MAUI开发',
    },
  ];

  /// 获取班级的项目分组数据
  ///
  /// - 归档的"计科22"班级返回历史分组（含真实人数分布）
  /// - 活跃的"软件23"班级返回待分组占位数据
  /// - 其他班级返回空列表
  Future<List<Map<String, dynamic>>> getProjectGroups(int classId) async {
    final classInfo = await getClass(classId);
    if (classInfo == null) return [];

    final name = classInfo['name'] as String? ?? '';
    final isArchived = (classInfo['is_archived'] as int? ?? 0) == 1;

    // ── 计科22（已归档）：返回历史真实分组数据 ───────────────────────
    if (name.contains('计科22') && isArchived) {
      // 班组1: 29人, 班组2: 29人, 班组3: 28人  →  总计86人
      const groupSizes = {'班组1': 29, '班组2': 29, '班组3': 28};
      const projectsPerGroup = 3; // 每个班组 3 个项目
      return _projectDefinitions.map((p) {
        final group = p['group_name']!;
        final totalInGroup = groupSizes[group] ?? 0;
        // 每个项目 6 人（一个项目组）
        final memberCount = (totalInGroup / projectsPerGroup).round();
        return <String, dynamic>{
          'group_name': group,
          'project_name': p['project_name'],
          'project_abbr': p['project_abbr'],
          'member_count': memberCount,
          'tech_stacks': p['tech_stacks'],
        };
      }).toList();
    }

    // ── 软件23（活跃）：返回待分组占位数据 ───────────────────────────
    if (name.contains('软件23') && !isArchived) {
      // 获取实际学生总数用于显示
      final members = await getClassMembers(classId);
      final studentCount = members
          .where((m) => (m['role'] ?? m['user_role']) == 'student')
          .length;

      return _projectDefinitions.map((p) {
        return <String, dynamic>{
          'group_name': '待分组',
          'project_name': p['project_name'],
          'project_abbr': p['project_abbr'],
          'member_count': 0, // 尚未分配
          'tech_stacks': p['tech_stacks'],
          'status': '待分组',
          'total_students': studentCount, // 附加：班级学生总数，供 UI 参考
        };
      }).toList();
    }

    // 其他班级暂无分组数据
    return [];
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
