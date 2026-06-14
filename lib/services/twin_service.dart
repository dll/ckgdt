import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import '../data/models/twin_profile_model.dart';
import 'course_context_service.dart';

/// 数字孪生画像服务 — 高保真教育教学数字镜像
///
/// 对课程、课堂、师生及教学全过程进行高保真、实时动态映射，
/// 实现数据驱动、智能诊断与个性化教学，贯穿教学练评研全流程。
class TwinService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  // ══════════════════════════════════════════════════════════════════════════
  // 学生画像 — 全维度映射
  // ══════════════════════════════════════════════════════════════════════════

  Future<StudentTwinProfile> buildStudentProfile(String userId) async {
    final db = await _dbHelper.database;

    // 1. 测验均分
    double quizAvg = 0;
    try {
      final scope = await _courseContext.scopedWhere(
        extraWhere: 'user_id = ?',
        extraArgs: [userId],
      );
      final r = await db.rawQuery(
        'SELECT AVG(score) as avg FROM quiz_results WHERE ${scope.where}',
        scope.args,
      );
      quizAvg = (r.first['avg'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 2. 实验完成率
    double labRate = 0;
    int totalTasks = 0;
    int doneTasks = 0;
    try {
      final taskScope = await _courseContext.scopedWhere(
        extraWhere: 'status = ?',
        extraArgs: ['active'],
      );
      final total = await db.rawQuery(
        'SELECT COUNT(*) as c FROM lab_tasks WHERE ${taskScope.where}',
        taskScope.args,
      );
      final doneScope = await _courseContext.scopedWhere(
        column: 'lt.course_id',
        extraWhere: "ls.user_id = ? AND ls.status IN ('已提交','已批改')",
        extraArgs: [userId],
      );
      final done = await db.rawQuery(
        '''
        SELECT COUNT(*) as c
        FROM lab_submissions ls
        JOIN lab_tasks lt ON ls.task_id = lt.id
        WHERE ${doneScope.where}
        ''',
        doneScope.args,
      );
      totalTasks = (total.first['c'] as int?) ?? 0;
      doneTasks = (done.first['c'] as int?) ?? 0;
      labRate =
          totalTasks > 0 ? (doneTasks / totalTasks * 100).clamp(0, 100) : 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 3. 错题消化率
    double wrongDigest = 0;
    try {
      final allScope = await _courseContext.scopedWhere(
        extraWhere: 'user_id = ?',
        extraArgs: [userId],
      );
      final allWrong = await db.rawQuery(
        'SELECT COUNT(*) as c FROM wrong_answers WHERE ${allScope.where}',
        allScope.args,
      );
      final explainedScope = await _courseContext.scopedWhere(
        extraWhere:
            "user_id = ? AND explanation IS NOT NULL AND explanation != ''",
        extraArgs: [userId],
      );
      final explained = await db.rawQuery(
        'SELECT COUNT(*) as c FROM wrong_answers WHERE ${explainedScope.where}',
        explainedScope.args,
      );
      final a = (allWrong.first['c'] as int?) ?? 0;
      final e = (explained.first['c'] as int?) ?? 0;
      wrongDigest = a > 0 ? (e / a * 100).clamp(0, 100) : 100;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 4. 概念覆盖率
    double conceptCov = 0;
    int totalNodes = 0;
    try {
      final graphScope =
          await _courseContext.scopedWhere(column: 'g.course_id');
      final tn = await db.rawQuery('''
        SELECT COUNT(*) as c
        FROM nodes n
        JOIN graphs g ON n.graph_id = g.id
        WHERE ${graphScope.where}
      ''', graphScope.args);
      final ln = await db.rawQuery(
        "SELECT COUNT(DISTINCT concept_id) as c FROM concept_progress WHERE user_id = ? AND status != 'not_started'",
        [userId],
      );
      totalNodes = (tn.first['c'] as int?) ?? 0;
      final learnedNodes = (ln.first['c'] as int?) ?? 0;
      conceptCov =
          totalNodes > 0 ? (learnedNodes / totalNodes * 100).clamp(0, 100) : 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 5. 总学习时长（分钟）
    int studyMin = 0;
    try {
      final scope = await _courseContext.scopedWhere(
        extraWhere: 'user_id = ?',
        extraArgs: [userId],
      );
      final r = await db.rawQuery(
        'SELECT SUM(study_time) as total FROM learning_records WHERE ${scope.where}',
        scope.args,
      );
      studyMin = (r.first['total'] as num?)?.toInt() ?? 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 6. 近 8 周每周学习时长
    final weeklyMinutes = <double>[];
    try {
      for (int i = 7; i >= 0; i--) {
        final start = DateTime.now().subtract(Duration(days: (i + 1) * 7));
        final end = DateTime.now().subtract(Duration(days: i * 7));
        final scope = await _courseContext.scopedWhere(
          extraWhere: 'user_id = ? AND created_at >= ? AND created_at < ?',
          extraArgs: [userId, start.toIso8601String(), end.toIso8601String()],
        );
        final r = await db.rawQuery(
          'SELECT COALESCE(SUM(study_time),0) as total FROM learning_records WHERE ${scope.where}',
          scope.args,
        );
        weeklyMinutes.add((r.first['total'] as num?)?.toDouble() ?? 0);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService.learningPattern', stack: st);
      weeklyMinutes.addAll(List.filled(8, 0));
    }

    // 7. 章节掌握度（按章测验正确率）
    final chapterMastery = <int, double>{};
    try {
      final chapters = await _courseContext.chapterTitles();
      for (int ch = 1; ch <= chapters.length; ch++) {
        final patterns = await _courseContext.chapterQueryPatterns(ch);
        final scope = await _courseContext.scopedWhere(
          extraWhere:
              'user_id = ? AND (${List.filled(patterns.length, 'chapter LIKE ?').join(' OR ')})',
          extraArgs: [userId, ...patterns],
        );
        final r = await db.rawQuery(
          'SELECT AVG(score) as avg FROM quiz_results WHERE ${scope.where}',
          scope.args,
        );
        final avg = (r.first['avg'] as num?)?.toDouble();
        if (avg != null) {
          chapterMastery[ch] = avg.clamp(0, 100);
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 8. 每日活跃热力图（近 30 天）
    final dailyActivity = <double>[];
    try {
      for (int i = 29; i >= 0; i--) {
        final day = DateTime.now().subtract(Duration(days: i));
        final dayStart = DateTime(day.year, day.month, day.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        final scope = await _courseContext.scopedWhere(
          extraWhere: 'user_id = ? AND created_at >= ? AND created_at < ?',
          extraArgs: [
            userId,
            dayStart.toIso8601String(),
            dayEnd.toIso8601String()
          ],
        );
        final r = await db.rawQuery(
          'SELECT COALESCE(SUM(study_time),0) as total FROM learning_records WHERE ${scope.where}',
          scope.args,
        );
        dailyActivity.add((r.first['total'] as num?)?.toDouble() ?? 0);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService.dailyActivity', stack: st);
      dailyActivity.addAll(List.filled(30, 0));
    }

    // 9. 学习行为模式分析
    final learningPattern =
        await _analyzeLearningPattern(db, userId, weeklyMinutes, dailyActivity);

    // 10. 5 维能力雷达
    final radar = <String, double>{
      '基础知识': quizAvg.clamp(0, 100),
      '实践能力': labRate,
      '创新思维': conceptCov * 0.8,
      '学习韧性': wrongDigest,
      '学习速度': (studyMin > 0 ? (conceptCov / studyMin * 60).clamp(0, 100) : 0),
    };

    // 11. 等级
    final avg = radar.values.fold(0.0, (s, v) => s + v) / radar.length;
    String level;
    if (avg >= 85) {
      level = '精通';
    } else if (avg >= 70) {
      level = '熟练';
    } else if (avg >= 50) {
      level = '进阶';
    } else {
      level = '入门';
    }

    // 12. 风险评估
    final riskResult = _assessStudentRisk(
      quizAvg: quizAvg,
      labRate: labRate,
      pattern: learningPattern,
      weeklyMinutes: weeklyMinutes,
    );

    // 13. 里程碑检测
    final milestones = _detectMilestones(
      quizAvg: quizAvg,
      labRate: labRate,
      conceptCov: conceptCov,
      wrongDigest: wrongDigest,
      studyMin: studyMin,
      streakDays: learningPattern.streakDays,
      totalTasks: totalTasks,
      doneTasks: doneTasks,
    );

    // 14. 趋势对比
    final trend = await _buildStudentTrend(
        db, userId, quizAvg, labRate, conceptCov, weeklyMinutes);

    final profile = StudentTwinProfile(
      quizAvg: quizAvg,
      labCompletionRate: labRate,
      wrongDigestRate: wrongDigest,
      conceptCoverage: conceptCov,
      studyMinutesTotal: studyMin,
      weeklyMinutes: weeklyMinutes,
      radar: radar,
      level: level,
      chapterMastery: chapterMastery,
      learningPattern: learningPattern,
      dailyActivity: dailyActivity,
      riskLevel: riskResult['level'] as String,
      riskReasons: (riskResult['reasons'] as List).cast<String>(),
      milestones: milestones,
      trend: trend,
    );

    // 保存快照（追加历史）
    _unawaited(_saveSnapshot(userId, 'student', profile.toJson()));

    return profile;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 教师画像 — 全维度映射
  // ══════════════════════════════════════════════════════════════════════════

  Future<TeacherTwinProfile> buildTeacherProfile(String teacherId) async {
    final db = await _dbHelper.database;

    // 班级人数
    int classSize = 0;
    try {
      final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM users WHERE role = 'student' AND is_active = 1",
      );
      classSize = (r.first['c'] as int?) ?? 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 班级均分（测验）
    double classAvg = 0;
    try {
      final scope = await _courseContext.scopedWhere(
        extraWhere:
            "user_id IN (SELECT user_id FROM users WHERE role = 'student')",
      );
      final r = await db.rawQuery(
        'SELECT AVG(score) as avg FROM quiz_results WHERE ${scope.where}',
        scope.args,
      );
      classAvg = (r.first['avg'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 节点覆盖率（全班均值）
    final nodeCov = <int, double>{};
    try {
      final rows = await db.rawQuery('''
        SELECT node_id, AVG(overall) as avg
        FROM node_achievement
        GROUP BY node_id
      ''');
      for (final r in rows) {
        nodeCov[(r['node_id'] as int)] = (r['avg'] as num?)?.toDouble() ?? 0;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 薄弱节点 Top 5
    final weakSpots = <WeakSpot>[];
    try {
      final rows = await db.rawQuery('''
        SELECT na.node_id, n.label as node_title, AVG(na.overall) as avg_score
        FROM node_achievement na
        LEFT JOIN nodes n ON na.node_id = n.id
        GROUP BY na.node_id
        ORDER BY avg_score ASC
        LIMIT 5
      ''');
      for (final r in rows) {
        weakSpots.add(WeakSpot(
          nodeId: (r['node_id'] as int),
          nodeTitle: (r['node_title'] as String?) ?? '未知节点',
          avgScore: (r['avg_score'] as num?)?.toDouble() ?? 0,
        ));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 待批阅数
    int pending = 0;
    try {
      final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lab_submissions WHERE status = '已提交'",
      );
      pending = (r.first['c'] as int?) ?? 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // ── 新增维度 ──

    // 班级成绩分布
    final classDistribution = <String, int>{
      'excellent': 0,
      'good': 0,
      'average': 0,
      'atRisk': 0
    };
    try {
      final scope = await _courseContext.scopedWhere(
        extraWhere:
            "user_id IN (SELECT user_id FROM users WHERE role = 'student')",
      );
      final rows = await db.rawQuery('''
        SELECT
          CASE
            WHEN avg_score >= 85 THEN 'excellent'
            WHEN avg_score >= 70 THEN 'good'
            WHEN avg_score >= 60 THEN 'average'
            ELSE 'atRisk'
          END as tier,
          COUNT(*) as cnt
        FROM (
          SELECT user_id, AVG(score) as avg_score
          FROM quiz_results
          WHERE ${scope.where}
          GROUP BY user_id
        )
        GROUP BY tier
      ''', scope.args);
      for (final r in rows) {
        final tier = r['tier'] as String;
        classDistribution[tier] = (r['cnt'] as int?) ?? 0;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 教学进度（教学大纲执行率）
    double teachingProgress = 0;
    try {
      final total = await db.rawQuery(
        'SELECT COUNT(*) as c FROM teaching_progress',
      );
      final done = await db.rawQuery(
        "SELECT COUNT(*) as c FROM teaching_progress WHERE status = '已完成'",
      );
      final t = (total.first['c'] as int?) ?? 0;
      final d = (done.first['c'] as int?) ?? 0;
      teachingProgress = t > 0 ? (d / t * 100).clamp(0, 100) : 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 班级参与度（近7天有学习记录的学生占比）
    double classEngagement = 0;
    try {
      final weekAgo =
          DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final scope = await _courseContext.scopedWhere(
        extraWhere: 'created_at >= ?',
        extraArgs: [weekAgo],
      );
      final r = await db.rawQuery(
        'SELECT COUNT(DISTINCT user_id) as c FROM learning_records WHERE ${scope.where}',
        scope.args,
      );
      final active = (r.first['c'] as int?) ?? 0;
      classEngagement =
          classSize > 0 ? (active / classSize * 100).clamp(0, 100) : 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 批阅及时性（3天内批完的占比）
    double gradingTimeliness = 0;
    try {
      final totalGraded = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lab_submissions WHERE status = '已批改'",
      );
      final timelyGraded = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lab_submissions WHERE status = '已批改' AND julianday(updated_at) - julianday(submitted_at) <= 3",
      );
      final tg = (totalGraded.first['c'] as int?) ?? 0;
      final tl = (timelyGraded.first['c'] as int?) ?? 0;
      gradingTimeliness = tg > 0 ? (tl / tg * 100).clamp(0, 100) : 100;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 截止日期预警
    int deadlineWarnings = 0;
    try {
      final threeDaysLater =
          DateTime.now().add(const Duration(days: 3)).toIso8601String();
      final now = DateTime.now().toIso8601String();
      final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lab_tasks WHERE status = 'active' AND due_date IS NOT NULL AND due_date >= ? AND due_date <= ?",
        [now, threeDaysLater],
      );
      deadlineWarnings = (r.first['c'] as int?) ?? 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 学生预警
    final alerts = await _buildStudentAlerts(db, classSize);

    // 趋势对比
    final trend = await _buildTeacherTrend(db, teacherId, classAvg, pending);

    final profile = TeacherTwinProfile(
      classSize: classSize,
      classAvg: classAvg,
      nodeCoverage: nodeCov,
      weakSpots: weakSpots,
      pendingGrading: pending,
      classDistribution: classDistribution,
      teachingProgress: teachingProgress,
      alerts: alerts,
      classEngagement: classEngagement,
      gradingTimeliness: gradingTimeliness,
      deadlineWarnings: deadlineWarnings,
      trend: trend,
    );

    _unawaited(_saveSnapshot(teacherId, 'teacher', profile.toJson()));
    return profile;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 学习行为模式分析
  // ══════════════════════════════════════════════════════════════════════════

  Future<LearningPattern> _analyzeLearningPattern(
    Database db,
    String userId,
    List<double> weeklyMinutes,
    List<double> dailyActivity,
  ) async {
    // 高峰学习时段
    final peakHours = <int>[];
    try {
      final scope = await _courseContext.scopedWhere(
        extraWhere: 'user_id = ?',
        extraArgs: [userId],
      );
      final rows = await db.rawQuery(
        "SELECT CAST(strftime('%H', created_at) AS INTEGER) as hour, SUM(study_time) as total "
        "FROM learning_records WHERE ${scope.where} GROUP BY hour ORDER BY total DESC LIMIT 3",
        scope.args,
      );
      for (final r in rows) {
        peakHours.add((r['hour'] as int?) ?? 0);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }

    // 学习稳定度（weeklyMinutes 的变异系数取反）
    double consistency = 50;
    if (weeklyMinutes.isNotEmpty) {
      final mean =
          weeklyMinutes.fold(0.0, (s, v) => s + v) / weeklyMinutes.length;
      if (mean > 0) {
        final variance =
            weeklyMinutes.fold(0.0, (s, v) => s + (v - mean) * (v - mean)) /
                weeklyMinutes.length;
        final cv = sqrt(variance) / mean; // 变异系数
        consistency = ((1 - cv.clamp(0, 2) / 2) * 100).clamp(0, 100);
      }
    }

    // 学习风格推断
    String style = '均衡型';
    if (peakHours.isNotEmpty) {
      final primaryHour = peakHours.first;
      if (primaryHour < 9) {
        style = '晨型';
      } else if (primaryHour >= 21) {
        style = '夜型';
      }
    }
    if (consistency < 30) {
      style = '冲刺型';
    } else if (consistency > 80) {
      style = '稳健型';
    }

    // 近7天活跃天数
    final activeDays7 = dailyActivity.length >= 7
        ? dailyActivity
            .sublist(dailyActivity.length - 7)
            .where((d) => d > 0)
            .length
        : 0;

    // 连续学习天数（从今天往回数）
    int streak = 0;
    for (int i = dailyActivity.length - 1; i >= 0; i--) {
      if (dailyActivity[i] > 0) {
        streak++;
      } else {
        break;
      }
    }

    // 上次学习距今
    int daysSince = 0;
    for (int i = dailyActivity.length - 1; i >= 0; i--) {
      if (dailyActivity[i] > 0) break;
      daysSince++;
    }

    return LearningPattern(
      peakHours: peakHours,
      consistency: consistency,
      style: style,
      activeDaysLast7: activeDays7,
      streakDays: streak,
      daysSinceLastStudy: daysSince,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 风险评估 — 智能诊断
  // ══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _assessStudentRisk({
    required double quizAvg,
    required double labRate,
    required LearningPattern pattern,
    required List<double> weeklyMinutes,
  }) {
    final reasons = <String>[];
    int score = 0; // 风险分，越高越危险

    // 维度1：学习断连
    if (pattern.daysSinceLastStudy >= 7) {
      score += 3;
      reasons.add('已超过 ${pattern.daysSinceLastStudy} 天未学习');
    } else if (pattern.daysSinceLastStudy >= 3) {
      score += 1;
      reasons.add('近 ${pattern.daysSinceLastStudy} 天未学习');
    }

    // 维度2：成绩低迷
    if (quizAvg > 0 && quizAvg < 50) {
      score += 2;
      reasons.add('测验均分仅 ${quizAvg.toStringAsFixed(0)}，低于及格线');
    } else if (quizAvg > 0 && quizAvg < 60) {
      score += 1;
      reasons.add('测验均分 ${quizAvg.toStringAsFixed(0)}，接近及格线');
    }

    // 维度3：实验欠交
    if (labRate < 30) {
      score += 2;
      reasons.add('实验完成率仅 ${labRate.toStringAsFixed(0)}%');
    } else if (labRate < 50) {
      score += 1;
      reasons.add('实验完成率偏低 ${labRate.toStringAsFixed(0)}%');
    }

    // 维度4：学习时长骤降
    if (weeklyMinutes.length >= 2) {
      final lastWeek = weeklyMinutes[weeklyMinutes.length - 1];
      final prevWeek = weeklyMinutes[weeklyMinutes.length - 2];
      if (prevWeek > 30 && lastWeek < prevWeek * 0.3) {
        score += 2;
        reasons.add(
            '学习时长骤降 ${((1 - lastWeek / prevWeek) * 100).toStringAsFixed(0)}%');
      }
    }

    // 维度5：活跃度极低
    if (pattern.activeDaysLast7 <= 1) {
      score += 1;
      reasons.add('近7天仅活跃 ${pattern.activeDaysLast7} 天');
    }

    String level;
    if (score >= 4) {
      level = 'critical';
    } else if (score >= 2) {
      level = 'warning';
    } else {
      level = 'healthy';
    }

    return {'level': level, 'reasons': reasons};
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 里程碑检测
  // ══════════════════════════════════════════════════════════════════════════

  List<Milestone> _detectMilestones({
    required double quizAvg,
    required double labRate,
    required double conceptCov,
    required double wrongDigest,
    required int studyMin,
    required int streakDays,
    required int totalTasks,
    required int doneTasks,
  }) {
    final now = DateTime.now().toIso8601String();
    return [
      Milestone(
        id: 'first_quiz',
        title: '初次测验',
        icon: '📝',
        achieved: quizAvg > 0,
        achievedAt: quizAvg > 0 ? now : '',
      ),
      Milestone(
        id: 'first_lab',
        title: '首次提交实验',
        icon: '🔬',
        achieved: doneTasks > 0,
        achievedAt: doneTasks > 0 ? now : '',
      ),
      Milestone(
        id: 'quiz_80',
        title: '测验达到80分',
        icon: '🏆',
        achieved: quizAvg >= 80,
        achievedAt: quizAvg >= 80 ? now : '',
      ),
      Milestone(
        id: 'lab_50',
        title: '完成一半实验',
        icon: '🧪',
        achieved: labRate >= 50,
        achievedAt: labRate >= 50 ? now : '',
      ),
      Milestone(
        id: 'lab_all',
        title: '完成全部实验',
        icon: '🎓',
        achieved: totalTasks > 0 && doneTasks >= totalTasks,
        achievedAt: (totalTasks > 0 && doneTasks >= totalTasks) ? now : '',
      ),
      Milestone(
        id: 'concept_50',
        title: '覆盖50%知识点',
        icon: '🧠',
        achieved: conceptCov >= 50,
        achievedAt: conceptCov >= 50 ? now : '',
      ),
      Milestone(
        id: 'concept_all',
        title: '知识点全覆盖',
        icon: '🌟',
        achieved: conceptCov >= 95,
        achievedAt: conceptCov >= 95 ? now : '',
      ),
      Milestone(
        id: 'wrong_clear',
        title: '错题全消化',
        icon: '✅',
        achieved: wrongDigest >= 100,
        achievedAt: wrongDigest >= 100 ? now : '',
      ),
      Milestone(
        id: 'study_600',
        title: '累计学习10小时',
        icon: '⏰',
        achieved: studyMin >= 600,
        achievedAt: studyMin >= 600 ? now : '',
      ),
      Milestone(
        id: 'streak_7',
        title: '连续学习7天',
        icon: '🔥',
        achieved: streakDays >= 7,
        achievedAt: streakDays >= 7 ? now : '',
      ),
    ];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 教师端：学生预警列表
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<StudentAlert>> _buildStudentAlerts(
      Database db, int classSize) async {
    final alerts = <StudentAlert>[];
    try {
      // 预警1：超过7天未学习的学生
      final weekAgo =
          DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final activeScope = await _courseContext.scopedWhere(
        extraWhere: 'created_at >= ?',
        extraArgs: [weekAgo],
      );
      final inactiveStudents = await db.rawQuery('''
        SELECT u.user_id, u.real_name
        FROM users u
        WHERE u.role = 'student' AND u.is_active = 1
        AND u.user_id NOT IN (
          SELECT DISTINCT user_id FROM learning_records WHERE ${activeScope.where}
        )
        LIMIT 10
      ''', activeScope.args);
      for (final s in inactiveStudents) {
        alerts.add(StudentAlert(
          userId: s['user_id'] as String? ?? '',
          realName: s['real_name'] as String? ?? '',
          alertType: 'inactive',
          message: '超过7天未学习',
        ));
      }

      // 预警2：测验平均分低于50的学生
      final quizScope = await _courseContext.scopedWhere(
        column: 'qr.course_id',
      );
      final lowScoreStudents = await db.rawQuery('''
        SELECT qr.user_id, u.real_name, AVG(qr.score) as avg_score
        FROM quiz_results qr
        LEFT JOIN users u ON qr.user_id = u.user_id
        WHERE u.role = 'student' AND ${quizScope.where}
        GROUP BY qr.user_id
        HAVING avg_score < 50
        LIMIT 10
      ''', quizScope.args);
      for (final s in lowScoreStudents) {
        final avg = (s['avg_score'] as num?)?.toDouble() ?? 0;
        alerts.add(StudentAlert(
          userId: s['user_id'] as String? ?? '',
          realName: s['real_name'] as String? ?? '',
          alertType: 'low_score',
          message: '测验均分 ${avg.toStringAsFixed(0)}，低于及格线',
        ));
      }

      // 预警3：实验未提交的学生（有active任务但0提交）
      final labTaskScope = await _courseContext.scopedWhere(
        column: 'lt.course_id',
      );
      final noSubStudents = await db.rawQuery('''
        SELECT u.user_id, u.real_name
        FROM users u
        WHERE u.role = 'student' AND u.is_active = 1
        AND u.user_id NOT IN (
          SELECT DISTINCT ls.user_id
          FROM lab_submissions ls
          JOIN lab_tasks lt ON ls.task_id = lt.id
          WHERE ${labTaskScope.where}
        )
        LIMIT 10
      ''', labTaskScope.args);
      for (final s in noSubStudents) {
        alerts.add(StudentAlert(
          userId: s['user_id'] as String? ?? '',
          realName: s['real_name'] as String? ?? '',
          alertType: 'no_submission',
          message: '尚未提交任何实验',
        ));
      }
    } catch (e) {
      debugPrint('TwinService: 构建学生预警失败 — $e');
    }
    return alerts;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 趋势对比 — 本周 vs 上周
  // ══════════════════════════════════════════════════════════════════════════

  Future<TrendComparison?> _buildStudentTrend(
    Database db,
    String userId,
    double currentQuizAvg,
    double currentLabRate,
    double currentConceptCov,
    List<double> weeklyMinutes,
  ) async {
    try {
      // 从历史快照中取上一次的数据
      final prevSnapshot = await _loadPreviousSnapshot(userId);
      if (prevSnapshot == null) return null;

      final prev = StudentTwinProfile.fromJson(prevSnapshot);
      final studyTimeDelta =
          weeklyMinutes.isNotEmpty && weeklyMinutes.length >= 2
              ? weeklyMinutes.last - weeklyMinutes[weeklyMinutes.length - 2]
              : 0.0;

      final quizDelta = currentQuizAvg - prev.quizAvg;
      final labDelta = currentLabRate - prev.labCompletionRate;
      final covDelta = currentConceptCov - prev.conceptCoverage;

      // 生成趋势摘要
      final parts = <String>[];
      if (quizDelta.abs() > 1) {
        parts.add(
            '测验${quizDelta > 0 ? "↑" : "↓"}${quizDelta.abs().toStringAsFixed(1)}');
      }
      if (labDelta.abs() > 1) {
        parts.add(
            '实验${labDelta > 0 ? "↑" : "↓"}${labDelta.abs().toStringAsFixed(1)}%');
      }
      if (covDelta.abs() > 1) {
        parts.add(
            '覆盖${covDelta > 0 ? "↑" : "↓"}${covDelta.abs().toStringAsFixed(1)}%');
      }

      return TrendComparison(
        quizAvgDelta: quizDelta,
        labRateDelta: labDelta,
        conceptCovDelta: covDelta,
        studyTimeDelta: studyTimeDelta,
        summary: parts.isEmpty ? '整体保持稳定' : parts.join('，'),
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }
    return null;
  }

  Future<TrendComparison?> _buildTeacherTrend(
    Database db,
    String teacherId,
    double currentClassAvg,
    int currentPending,
  ) async {
    try {
      final prevSnapshot = await _loadPreviousSnapshot(teacherId);
      if (prevSnapshot == null) return null;

      final prev = TeacherTwinProfile.fromJson(prevSnapshot);
      final avgDelta = currentClassAvg - prev.classAvg;
      final pendingDelta = (currentPending - prev.pendingGrading).toDouble();

      final parts = <String>[];
      if (avgDelta.abs() > 0.5) {
        parts.add(
            '班级均分${avgDelta > 0 ? "↑" : "↓"}${avgDelta.abs().toStringAsFixed(1)}');
      }
      if (pendingDelta.abs() > 0) {
        parts.add(
            '待批${pendingDelta > 0 ? "增加" : "减少"}${pendingDelta.abs().toInt()}份');
      }

      return TrendComparison(
        quizAvgDelta: avgDelta,
        studyTimeDelta: pendingDelta,
        summary: parts.isEmpty ? '教学状态稳定' : parts.join('，'),
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 快照管理 — 保留历史，支持趋势
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _saveSnapshot(
      String userId, String role, Map<String, dynamic> json) async {
    try {
      final db = await _dbHelper.database;
      await db.insert('twin_snapshots', {
        'user_id': userId,
        'role': role,
        'snapshot_json': jsonEncode(json),
        'generated_at': DateTime.now().toIso8601String(),
      });
      // 清理超过30天的旧快照
      final cutoff =
          DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      await db.delete(
        'twin_snapshots',
        where: 'user_id = ? AND generated_at < ?',
        whereArgs: [userId, cutoff],
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }
  }

  /// 获取上一次的快照（跳过最新的，取前一个）
  Future<Map<String, dynamic>?> _loadPreviousSnapshot(String userId) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        'twin_snapshots',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'generated_at DESC',
        limit: 1,
        offset: 1, // 跳过当前最新的
      );
      if (rows.isEmpty) return null;
      return jsonDecode(rows.first['snapshot_json'] as String)
          as Map<String, dynamic>;
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }
    return null;
  }

  /// 加载缓存的最新快照（带有效期检查）
  Future<Map<String, dynamic>?> loadCachedSnapshot(String userId) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        'twin_snapshots',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'generated_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final generatedAt =
          DateTime.tryParse(rows.first['generated_at'] as String? ?? '');
      // 1h 缓存有效期（从24h降低到1h以实现更实时的映射）
      if (generatedAt != null &&
          DateTime.now().difference(generatedAt).inMinutes < 60) {
        return jsonDecode(rows.first['snapshot_json'] as String)
            as Map<String, dynamic>;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'TwinService', stack: st);
    }
    return null;
  }

  // ── unawaited helper ──
  static void _unawaited(Future<void> future) {
    future.catchError((_) {});
  }
}
