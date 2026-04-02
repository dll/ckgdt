import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// 作品管理 DAO — 作品提交 / 评分 / 排行
class WorksDao {
  // ══════════════════════════════════════════════════════════
  //  作品 CRUD
  // ══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getWorks({
    String? workType,
    String? userId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    String sql = '''
      SELECT w.*, ws.total_score as score, ws.comment as score_comment,
             ws.scorer_name, ws.scored_at
      FROM student_works w
      LEFT JOIN work_scores ws ON ws.work_id = w.id
      WHERE 1=1
    ''';
    final args = <dynamic>[];
    if (workType != null && workType != '全部') {
      sql += ' AND w.work_type = ?';
      args.add(workType);
    }
    if (userId != null) {
      sql += ' AND w.user_id = ?';
      args.add(userId);
    }
    sql += ' ORDER BY w.created_at DESC';
    return db.rawQuery(sql, args);
  }

  Future<Map<String, dynamic>?> getWork(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list = await db.rawQuery('''
      SELECT w.*, ws.total_score as score, ws.comment as score_comment,
             ws.scorer_name, ws.scored_at,
             ws.score_functionality, ws.score_tech_depth,
             ws.score_integration, ws.score_quality, ws.score_documentation
      FROM student_works w
      LEFT JOIN work_scores ws ON ws.work_id = w.id
      WHERE w.id = ?
    ''', [id]);
    return list.isNotEmpty ? list.first : null;
  }

  Future<int> addWork({
    required String title,
    String? description,
    String? techStack,
    String workType = '综合项目',
    String? groupName,
    String? leaderName,
    String? userId,
    String? filePath,
    String? fileSize,
    String status = '待提交',
    List<String>? tags,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('student_works', {
      'title': title,
      'description': description,
      'tech_stack': techStack,
      'work_type': workType,
      'group_name': groupName,
      'leader_name': leaderName,
      'user_id': userId,
      'file_path': filePath,
      'file_size': fileSize,
      'status': status,
      'tags': tags != null ? jsonEncode(tags) : null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateWork(int id, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update('student_works', data,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> submitWork(int id) async {
    return updateWork(id, {
      'status': '已提交',
      'submit_time': DateTime.now().toIso8601String(),
    });
  }

  Future<int> deleteWork(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('student_works', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════
  //  作品评分
  // ══════════════════════════════════════════════════════════

  Future<int> scoreWork({
    required int workId,
    String? scorerId,
    String? scorerName,
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

    // 先检查是否已评分
    final existing = await db.query('work_scores',
        where: 'work_id = ?', whereArgs: [workId]);
    if (existing.isNotEmpty) {
      // 更新评分
      return db.update(
          'work_scores',
          {
            'scorer_id': scorerId,
            'scorer_name': scorerName,
            'score_functionality': functionality,
            'score_tech_depth': techDepth,
            'score_integration': integration,
            'score_quality': quality,
            'score_documentation': documentation,
            'total_score': total,
            'comment': comment,
            'scored_at': DateTime.now().toIso8601String(),
          },
          where: 'work_id = ?',
          whereArgs: [workId]);
    }

    // 新增评分
    final result = await db.insert('work_scores', {
      'work_id': workId,
      'scorer_id': scorerId,
      'scorer_name': scorerName,
      'score_functionality': functionality,
      'score_tech_depth': techDepth,
      'score_integration': integration,
      'score_quality': quality,
      'score_documentation': documentation,
      'total_score': total,
      'comment': comment,
      'scored_at': DateTime.now().toIso8601String(),
    });

    // 更新作品状态
    await updateWork(workId, {'status': '已评分'});
    return result;
  }

  Future<List<Map<String, dynamic>>> getScoreRecords() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT ws.*, sw.title as work_title, sw.group_name, sw.work_type
      FROM work_scores ws
      JOIN student_works sw ON ws.work_id = sw.id
      ORDER BY ws.scored_at DESC
    ''');
  }

  // ══════════════════════════════════════════════════════════
  //  排行榜
  // ══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT sw.*, ws.total_score as score, ws.comment,
             ws.scorer_name
      FROM student_works sw
      JOIN work_scores ws ON ws.work_id = sw.id
      ORDER BY ws.total_score DESC
    ''');
  }

  /// 统计概览
  Future<Map<String, dynamic>> getOverview() async {
    final db = await DatabaseHelper.instance.database;
    final totalWorks = await db.rawQuery(
        'SELECT COUNT(*) as c FROM student_works');
    final scored = await db.rawQuery('''
      SELECT COUNT(*) as c, AVG(total_score) as avg, MAX(total_score) as max
      FROM work_scores
    ''');
    final count = (totalWorks.first['c'] as int?) ?? 0;
    final scoredCount = (scored.first['c'] as int?) ?? 0;
    return {
      'total_works': count,
      'scored_count': scoredCount,
      'avg_score': scoredCount > 0
          ? ((scored.first['avg'] as num?)?.toDouble() ?? 0.0)
          : 0.0,
      'max_score': (scored.first['max'] as int?) ?? 0,
    };
  }

  // ══════════════════════════════════════════════════════════
  //  示例数据初始化
  // ══════════════════════════════════════════════════════════

  Future<void> initDemoDataIfEmpty() async {
    final db = await DatabaseHelper.instance.database;
    final count = await db.rawQuery(
        'SELECT COUNT(*) as c FROM student_works');
    if ((count.first['c'] as int? ?? 0) > 0) return;

    // 插入示例作品
    final w1 = await addWork(
      title: '智慧校园生活服务平台',
      description: '面向高校师生的跨平台校园服务，整合课表、场馆预约、校园导航等功能',
      techStack: 'Flutter + Android 原生',
      workType: '综合项目',
      groupName: '第1组',
      leaderName: '张三',
      status: '已提交',
      tags: ['Flutter', 'Android', '跨平台'],
    );
    final w2 = await addWork(
      title: '在线学习辅助平台',
      description: '提供在线学习、笔记管理、学习计划和协作讨论功能',
      techStack: 'Flutter + React Native',
      workType: '综合项目',
      groupName: '第2组',
      leaderName: '陈九',
      status: '已提交',
      tags: ['Flutter', 'React Native', '学习'],
    );
    final w3 = await addWork(
      title: '智能健康运动记录',
      description: '记录运动轨迹、健康数据分析、社交分享健身成果',
      techStack: 'Flutter + HarmonyOS',
      workType: '综合项目',
      groupName: '第3组',
      leaderName: '卫五',
      status: '已提交',
      tags: ['Flutter', 'HarmonyOS', '健康'],
    );
    final w4 = await addWork(
      title: '二手物品交易平台',
      description: '校园二手商品发布、搜索、即时聊天、交易管理',
      techStack: 'Flutter + 小程序',
      workType: '综合项目',
      groupName: '第4组',
      leaderName: '秦一',
      status: '已提交',
      tags: ['Flutter', '小程序', '电商'],
    );
    final w5 = await addWork(
      title: 'Android 原生 TODO 应用',
      description: '基于 Room + MVVM 架构的本地待办事项管理应用',
      techStack: 'Android (Kotlin)',
      workType: '实验作业',
      groupName: '第1组',
      leaderName: '张三',
      status: '已提交',
      tags: ['Android', 'Kotlin', 'MVVM'],
    );
    await addWork(
      title: '微信小程序天气查询',
      description: '基于和风天气 API 的小程序，支持城市搜索和 7 天预报',
      techStack: '微信小程序',
      workType: '实验作业',
      groupName: '第2组',
      leaderName: '陈九',
      status: '待提交',
      tags: ['小程序', 'API', '天气'],
    );

    // 评分
    await scoreWork(
        workId: w1,
        scorerName: '刘东良教师',
        functionality: 23,
        techDepth: 18,
        integration: 22,
        quality: 13,
        documentation: 14,
        comment: '功能完整，技术栈选型合理，UI 交互流畅');
    await scoreWork(
        workId: w2,
        scorerName: '刘东良教师',
        functionality: 21,
        techDepth: 17,
        integration: 20,
        quality: 13,
        documentation: 12,
        comment: '学习功能全面，建议优化笔记同步性能');
    await scoreWork(
        workId: w3,
        scorerName: '刘东良教师',
        functionality: 20,
        techDepth: 16,
        integration: 20,
        quality: 12,
        documentation: 12,
        comment: '运动记录功能扎实，HarmonyOS 适配值得肯定');
    await scoreWork(
        workId: w4,
        scorerName: '刘东良教师',
        functionality: 22,
        techDepth: 18,
        integration: 21,
        quality: 14,
        documentation: 13,
        comment: '交易流程完善，即时聊天功能亮点突出');
  }
}
