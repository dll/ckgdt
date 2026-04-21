import 'dart:convert';
import 'dart:math';
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

  /// 已废弃：不再插入虚拟数据（张三李四等）。
  /// 改由 [syncGroupsFromStudentData] 从 JSON 同步真实学生数据。
  Future<void> initDemoDataIfEmpty() async {
    // no-op — 保留方法签名以兼容旧调用点
  }

  /// 从学生列表同步分组 / 项目 / 答辩数据（替代旧的虚拟数据）。
  /// 以 `repo` 字段为单位分组，幂等操作。
  Future<void> syncGroupsFromStudentData(
      List<Map<String, dynamic>> students) async {
    if (students.isEmpty) return;
    final db = await DatabaseHelper.instance.database;

    // ── 1. 清理不属于真实 repo 的旧数据 ─────────────────────────
    final validRepos = students
        .map((s) => s['repo'] as String?)
        .where((r) => r != null && r.isNotEmpty)
        .toSet();
    final oldGroups = await db.query('assessment_groups');
    for (final g in oldGroups) {
      final groupName = g['name'] as String? ?? '';
      if (!validRepos.contains(groupName)) {
        final gId = g['id'] as int;
        // 级联删除关联的答辩、评分、项目
        await db.delete('defense_records',
            where: 'group_id = ?', whereArgs: [gId]);
        final linkedProjects = await db.query('assessment_projects',
            where: 'group_id = ?', whereArgs: [gId]);
        for (final p in linkedProjects) {
          await db.delete('project_scores',
              where: 'project_id = ?', whereArgs: [p['id'] as int]);
        }
        await db.delete('assessment_projects',
            where: 'group_id = ?', whereArgs: [gId]);
        await db.delete('assessment_groups',
            where: 'id = ?', whereArgs: [gId]);
      }
    }

    // ── 2. 按 repo 分组 ───────────────────────────────────────
    final Map<String, List<Map<String, dynamic>>> byRepo = {};
    for (final s in students) {
      final repo = s['repo'] as String? ?? '';
      if (repo.isEmpty) continue;
      byRepo.putIfAbsent(repo, () => []).add(s);
    }

    // ── 3. 为每个 repo 创建 group + project + defense（幂等）────
    final rng = Random(42);
    int defenseIdx = 0;
    final sortedEntries = byRepo.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (final entry in sortedEntries) {
      final repo = entry.key;
      final members = entry.value;

      // 已存在则跳过
      final existing = await db.query('assessment_groups',
          where: 'name = ?', whereArgs: [repo]);
      if (existing.isNotEmpty) continue;

      final leader = members.first;
      final projectName = leader['project'] as String? ?? '未命名项目';
      final memberNames =
          members.map((m) => m['name'] as String? ?? '').toList();
      final memberIds =
          members.map((m) => m['userId'] as String? ?? '').toList();
      final techStacks = members
          .map((m) => m['techStack'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .join(' / ');

      // 创建分组
      final gId = await addGroup(
        name: repo,
        leader: leader['name'] as String?,
        memberIds: memberIds,
        memberNames: memberNames,
        projectName: projectName,
      );

      // 创建项目
      final pId = await addProject(
        groupId: gId,
        name: projectName,
        description: leader['feature_detail'] as String? ??
            leader['features'] as String? ??
            '',
        techStack: techStacks,
        status: '开发中',
        progress: 0.3 + rng.nextDouble() * 0.5,
      );

      // 创建答辩安排
      defenseIdx++;
      final days = ['周一', '周二', '周三', '周四', '周五'];
      final day = days[(defenseIdx - 1) % 5];
      final hour = 9 + ((defenseIdx - 1) ~/ 5);
      final minute = ((defenseIdx - 1) % 4) * 15;
      final timeStr =
          '第16周 $day ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      await addDefenseRecord(
        groupId: gId,
        projectId: pId,
        scheduledTime: timeStr,
      );
    }
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
    String? studentName,
    String? reportType,
    String? fileName,
    String? filePath,
    String? groupId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('student_reports', {
      'user_id': userId,
      'title': reportType ?? '考核报告',
      'content_json': fileName ?? '',
      'file_path': filePath ?? '',
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

  // ══════════════════════════════════════════════════════════
  //  贡献度评分
  // ══════════════════════════════════════════════════════════

  /// 确保贡献度评分表存在
  Future<void> _ensureContributionTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contribution_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_user_id TEXT NOT NULL,
        target_user_name TEXT,
        scorer_user_id TEXT NOT NULL,
        scorer_user_name TEXT,
        scorer_type TEXT NOT NULL DEFAULT 'peer',
        repo TEXT,
        dimension TEXT NOT NULL DEFAULT 'individual',
        code_contribution INTEGER DEFAULT 0,
        doc_contribution INTEGER DEFAULT 0,
        teamwork_score INTEGER DEFAULT 0,
        initiative_score INTEGER DEFAULT 0,
        quality_score INTEGER DEFAULT 0,
        overall_score INTEGER DEFAULT 0,
        comment TEXT,
        scored_at TEXT,
        UNIQUE(target_user_id, scorer_user_id, dimension)
      )
    ''');
  }

  /// 提交贡献度评分（upsert：已存在则更新）
  Future<int> submitContributionScore({
    required String targetUserId,
    String? targetUserName,
    required String scorerUserId,
    String? scorerUserName,
    required String scorerType, // self / peer / teacher
    String? repo,
    required String dimension, // individual / group / project
    required int codeContribution,
    required int docContribution,
    required int teamworkScore,
    required int initiativeScore,
    required int qualityScore,
    String? comment,
  }) async {
    await _ensureContributionTable();
    final db = await DatabaseHelper.instance.database;
    final overall = codeContribution + docContribution + teamworkScore +
        initiativeScore + qualityScore;

    // 先查是否已存在
    final existing = await db.query('contribution_scores',
        where:
            'target_user_id = ? AND scorer_user_id = ? AND dimension = ?',
        whereArgs: [targetUserId, scorerUserId, dimension]);

    if (existing.isNotEmpty) {
      return db.update(
          'contribution_scores',
          {
            'target_user_name': targetUserName,
            'scorer_user_name': scorerUserName,
            'scorer_type': scorerType,
            'repo': repo,
            'code_contribution': codeContribution,
            'doc_contribution': docContribution,
            'teamwork_score': teamworkScore,
            'initiative_score': initiativeScore,
            'quality_score': qualityScore,
            'overall_score': overall,
            'comment': comment,
            'scored_at': DateTime.now().toIso8601String(),
          },
          where:
              'target_user_id = ? AND scorer_user_id = ? AND dimension = ?',
          whereArgs: [targetUserId, scorerUserId, dimension]);
    }

    return db.insert('contribution_scores', {
      'target_user_id': targetUserId,
      'target_user_name': targetUserName,
      'scorer_user_id': scorerUserId,
      'scorer_user_name': scorerUserName,
      'scorer_type': scorerType,
      'repo': repo,
      'dimension': dimension,
      'code_contribution': codeContribution,
      'doc_contribution': docContribution,
      'teamwork_score': teamworkScore,
      'initiative_score': initiativeScore,
      'quality_score': qualityScore,
      'overall_score': overall,
      'comment': comment,
      'scored_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取某用户收到的所有评分
  Future<List<Map<String, dynamic>>> getContributionScoresForUser(
      String userId) async {
    await _ensureContributionTable();
    final db = await DatabaseHelper.instance.database;
    return db.query('contribution_scores',
        where: 'target_user_id = ?',
        whereArgs: [userId],
        orderBy: 'scored_at DESC');
  }

  /// 获取某用户给出的所有评分
  Future<List<Map<String, dynamic>>> getContributionScoresByScorer(
      String scorerUserId) async {
    await _ensureContributionTable();
    final db = await DatabaseHelper.instance.database;
    return db.query('contribution_scores',
        where: 'scorer_user_id = ?',
        whereArgs: [scorerUserId],
        orderBy: 'scored_at DESC');
  }

  /// 获取某仓库（项目组）的所有贡献度评分
  Future<List<Map<String, dynamic>>> getContributionScoresByRepo(
      String repo) async {
    await _ensureContributionTable();
    final db = await DatabaseHelper.instance.database;
    return db.query('contribution_scores',
        where: 'repo = ?', whereArgs: [repo], orderBy: 'overall_score DESC');
  }

  /// 获取某用户某维度的综合得分（平均值）
  Future<Map<String, double>> getContributionSummary(String userId) async {
    await _ensureContributionTable();
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('''
      SELECT
        AVG(code_contribution) as avg_code,
        AVG(doc_contribution) as avg_doc,
        AVG(teamwork_score) as avg_teamwork,
        AVG(initiative_score) as avg_initiative,
        AVG(quality_score) as avg_quality,
        AVG(overall_score) as avg_overall,
        COUNT(*) as total_reviews
      FROM contribution_scores
      WHERE target_user_id = ?
    ''', [userId]);
    if (result.isNotEmpty) {
      final r = result.first;
      return {
        'code': (r['avg_code'] as num?)?.toDouble() ?? 0,
        'doc': (r['avg_doc'] as num?)?.toDouble() ?? 0,
        'teamwork': (r['avg_teamwork'] as num?)?.toDouble() ?? 0,
        'initiative': (r['avg_initiative'] as num?)?.toDouble() ?? 0,
        'quality': (r['avg_quality'] as num?)?.toDouble() ?? 0,
        'overall': (r['avg_overall'] as num?)?.toDouble() ?? 0,
        'totalReviews': (r['total_reviews'] as num?)?.toDouble() ?? 0,
      };
    }
    return {'code': 0, 'doc': 0, 'teamwork': 0, 'initiative': 0, 'quality': 0, 'overall': 0, 'totalReviews': 0};
  }

  /// 检查是否已评分
  Future<bool> hasScored(
      String scorerUserId, String targetUserId, String dimension) async {
    await _ensureContributionTable();
    final db = await DatabaseHelper.instance.database;
    final result = await db.query('contribution_scores',
        where:
            'scorer_user_id = ? AND target_user_id = ? AND dimension = ?',
        whereArgs: [scorerUserId, targetUserId, dimension]);
    return result.isNotEmpty;
  }
}
