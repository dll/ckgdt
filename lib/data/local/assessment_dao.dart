import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// 考核管理 DAO — 分组 / 项目 / 评分 / 答辩
class AssessmentDao {
  // ══════════════════════════════════════════════════════════
  //  分组管理
  // ══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getGroups() async {
    final db = await DatabaseHelper.instance.database;
    return db.query('assessment_groups', orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getGroup(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list =
        await db.query('assessment_groups', where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  Future<int> addGroup({
    required String name,
    String? leader,
    List<String>? memberIds,
    List<String>? memberNames,
    String? projectName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('assessment_groups', {
      'name': name,
      'leader': leader,
      'member_ids': memberIds != null ? jsonEncode(memberIds) : null,
      'member_names': memberNames != null ? jsonEncode(memberNames) : null,
      'project_name': projectName,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateGroup(int id, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db
        .update('assessment_groups', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteGroup(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('assessment_groups', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取分组统计
  Future<Map<String, dynamic>> getGroupStats() async {
    final db = await DatabaseHelper.instance.database;
    final groups = await db.query('assessment_groups');
    int totalMembers = 0;
    for (final g in groups) {
      final names = g['member_names'] as String?;
      if (names != null && names.isNotEmpty) {
        try {
          totalMembers += (jsonDecode(names) as List).length;
        } catch (_) {}
      }
    }
    return {
      'group_count': groups.length,
      'total_members': totalMembers,
      'avg_members': groups.isEmpty ? 0.0 : (totalMembers / groups.length),
    };
  }

  // ══════════════════════════════════════════════════════════
  //  项目管理
  // ══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getProjects() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT p.*, g.name as group_name
      FROM assessment_projects p
      LEFT JOIN assessment_groups g ON p.group_id = g.id
      ORDER BY p.id ASC
    ''');
  }

  Future<int> addProject({
    int? groupId,
    required String name,
    String? description,
    String? techStack,
    String status = '设计阶段',
    double progress = 0,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('assessment_projects', {
      'group_id': groupId,
      'name': name,
      'description': description,
      'tech_stack': techStack,
      'status': status,
      'progress': progress,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateProject(int id, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db
        .update('assessment_projects', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProject(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('assessment_projects', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════
  //  项目评分
  // ══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getScores({int? projectId}) async {
    final db = await DatabaseHelper.instance.database;
    if (projectId != null) {
      return db.rawQuery('''
        SELECT s.*, p.name as project_name, g.name as group_name
        FROM project_scores s
        LEFT JOIN assessment_projects p ON s.project_id = p.id
        LEFT JOIN assessment_groups g ON s.group_id = g.id
        WHERE s.project_id = ?
        ORDER BY s.scored_at DESC
      ''', [projectId]);
    }
    return db.rawQuery('''
      SELECT s.*, p.name as project_name, g.name as group_name
      FROM project_scores s
      LEFT JOIN assessment_projects p ON s.project_id = p.id
      LEFT JOIN assessment_groups g ON s.group_id = g.id
      ORDER BY s.total_score DESC
    ''');
  }

  Future<int> addScore({
    required int projectId,
    int? groupId,
    String? scorerId,
    required int functionality,
    required int techDepth,
    required int integration,
    required int quality,
    required int documentation,
    String? comment,
  }) async {
    final total =
        functionality + techDepth + integration + quality + documentation;
    final db = await DatabaseHelper.instance.database;
    return db.insert('project_scores', {
      'project_id': projectId,
      'group_id': groupId,
      'scorer_id': scorerId,
      'score_functionality': functionality,
      'score_tech_depth': techDepth,
      'score_integration': integration,
      'score_quality': quality,
      'score_documentation': documentation,
      'total_score': total,
      'comment': comment,
      'scored_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取成绩排行
  Future<List<Map<String, dynamic>>> getScoreRanking() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT s.*, p.name as project_name, g.name as group_name
      FROM project_scores s
      LEFT JOIN assessment_projects p ON s.project_id = p.id
      LEFT JOIN assessment_groups g ON s.group_id = g.id
      ORDER BY s.total_score DESC
    ''');
  }

  /// 获取成绩统计概览
  Future<Map<String, dynamic>> getScoreOverview() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as count,
        AVG(total_score) as avg_score,
        MAX(total_score) as max_score,
        MIN(total_score) as min_score
      FROM project_scores
    ''');
    if (result.isNotEmpty) {
      final r = result.first;
      final count = (r['count'] as int?) ?? 0;
      return {
        'count': count,
        'avg_score':
            count > 0 ? ((r['avg_score'] as num?)?.toDouble() ?? 0.0) : 0.0,
        'max_score': (r['max_score'] as int?) ?? 0,
        'min_score': (r['min_score'] as int?) ?? 0,
        'pass_rate': count > 0 ? '100%' : '0%', // simplified
      };
    }
    return {
      'count': 0,
      'avg_score': 0.0,
      'max_score': 0,
      'min_score': 0,
      'pass_rate': '0%'
    };
  }

  // ══════════════════════════════════════════════════════════
  //  答辩管理
  // ══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getDefenseRecords() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT d.*, g.name as group_name, p.name as project_name
      FROM defense_records d
      LEFT JOIN assessment_groups g ON d.group_id = g.id
      LEFT JOIN assessment_projects p ON d.project_id = p.id
      ORDER BY d.scheduled_time ASC
    ''');
  }

  Future<int> addDefenseRecord({
    required int groupId,
    int? projectId,
    required String scheduledTime,
    String location = '实验楼A301',
    int durationMinutes = 15,
    String status = '待答辩',
    String? notes,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('defense_records', {
      'group_id': groupId,
      'project_id': projectId,
      'scheduled_time': scheduledTime,
      'location': location,
      'duration_minutes': durationMinutes,
      'status': status,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateDefenseStatus(int id, String status) async {
    final db = await DatabaseHelper.instance.database;
    return db.update('defense_records', {'status': status},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteDefenseRecord(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('defense_records', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════
  //  示例数据初始化（教学演示用）
  // ══════════════════════════════════════════════════════════

  Future<void> initDemoDataIfEmpty() async {
    final db = await DatabaseHelper.instance.database;
    final count =
        await db.rawQuery('SELECT COUNT(*) as c FROM assessment_groups');
    if ((count.first['c'] as int? ?? 0) > 0) return;

    // 插入示例分组
    final g1 = await addGroup(
      name: '第1组',
      leader: '张三',
      memberNames: ['张三', '李四', '王五', '赵六', '孙七', '周八'],
      projectName: '智慧校园生活服务平台',
    );
    final g2 = await addGroup(
      name: '第2组',
      leader: '陈九',
      memberNames: ['陈九', '吴十', '郑一', '钱二', '冯三', '褚四'],
      projectName: '在线学习辅助平台',
    );
    final g3 = await addGroup(
      name: '第3组',
      leader: '卫五',
      memberNames: ['卫五', '蒋六', '沈七', '韩八', '杨九', '朱十'],
      projectName: '智能健康运动记录平台',
    );
    final g4 = await addGroup(
      name: '第4组',
      leader: '秦一',
      memberNames: ['秦一', '许二', '何三', '吕四', '施五', '张六'],
      projectName: '二手物品交易平台',
    );

    // 插入示例项目
    final p1 = await addProject(
        groupId: g1,
        name: '智慧校园生活服务平台',
        description: '面向高校师生的跨平台校园服务，整合课表、场馆预约、校园导航等功能',
        techStack: 'Flutter + Android 原生 + UniApp',
        status: '开发中',
        progress: 0.65);
    final p2 = await addProject(
        groupId: g2,
        name: '在线学习辅助平台',
        description: '提供在线学习、笔记管理、学习计划和协作讨论功能',
        techStack: 'Flutter + React Native + 小程序',
        status: '开发中',
        progress: 0.50);
    final p3 = await addProject(
        groupId: g3,
        name: '智能健康运动记录平台',
        description: '记录运动轨迹、健康数据分析、社交分享健身成果',
        techStack: 'Flutter + HarmonyOS + iOS',
        status: '设计阶段',
        progress: 0.30);
    final p4 = await addProject(
        groupId: g4,
        name: '二手物品交易平台',
        description: '校园二手商品发布、搜索、即时聊天、交易管理',
        techStack: 'Flutter + 小程序 + Android',
        status: '测试阶段',
        progress: 0.80);

    // 插入示例评分
    await addScore(
        projectId: p1,
        groupId: g1,
        scorerId: '206004',
        functionality: 23,
        techDepth: 18,
        integration: 22,
        quality: 13,
        documentation: 14,
        comment: '功能完整，技术栈选型合理，UI 交互流畅');
    await addScore(
        projectId: p2,
        groupId: g2,
        scorerId: '206004',
        functionality: 21,
        techDepth: 17,
        integration: 20,
        quality: 13,
        documentation: 12,
        comment: '学习功能全面，建议优化笔记同步性能');
    await addScore(
        projectId: p3,
        groupId: g3,
        scorerId: '206004',
        functionality: 20,
        techDepth: 16,
        integration: 20,
        quality: 12,
        documentation: 12,
        comment: '运动记录功能扎实，HarmonyOS 适配值得肯定');
    await addScore(
        projectId: p4,
        groupId: g4,
        scorerId: '206004',
        functionality: 22,
        techDepth: 18,
        integration: 21,
        quality: 14,
        documentation: 13,
        comment: '交易流程完善，即时聊天功能亮点突出');

    // 插入示例答辩
    await addDefenseRecord(
        groupId: g1, projectId: p1, scheduledTime: '第16周 周一 9:00-9:15');
    await addDefenseRecord(
        groupId: g2, projectId: p2, scheduledTime: '第16周 周一 9:15-9:30');
    await addDefenseRecord(
        groupId: g3, projectId: p3, scheduledTime: '第16周 周一 9:30-9:45');
    await addDefenseRecord(
        groupId: g4, projectId: p4, scheduledTime: '第16周 周一 9:45-10:00');
  }

  // ══════════════════════════════════════════════════════════
  //  报告提交（学生提交考核报告）
  // ══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getSubmittedReports(
      {String? userId}) async {
    final db = await DatabaseHelper.instance.database;
    if (userId != null) {
      return db.query('student_reports',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'created_at DESC');
    }
    return db.query('student_reports', orderBy: 'created_at DESC');
  }

  Future<int> submitReport({
    required String userId,
    required String title,
    required String content,
    String? groupId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('student_reports', {
      'user_id': userId,
      'title': title,
      'content_json': content,
      'status': '已提交',
      'task_id': groupId != null ? int.tryParse(groupId) : null,
      'submit_time': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> deleteSubmittedReport(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('student_reports', where: 'id = ?', whereArgs: [id]);
  }
}
