import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';
import '../data/models/twin_profile_model.dart';

/// 数字孪生画像服务 — 聚合真实学习数据构建画像
class TwinService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ══════════════════════════════════════════════════════════════════
  // 学生画像
  // ══════════════════════════════════════════════════════════════════

  Future<StudentTwinProfile> buildStudentProfile(String userId) async {
    final db = await _dbHelper.database;

    // 1. 测验均分
    double quizAvg = 0;
    try {
      final r = await db.rawQuery(
        'SELECT AVG(score) as avg FROM quiz_results WHERE user_id = ?',
        [userId],
      );
      quizAvg = (r.first['avg'] as num?)?.toDouble() ?? 0;
    } catch (_) {}

    // 2. 实验完成率
    double labRate = 0;
    try {
      final total = await db.rawQuery(
        'SELECT COUNT(*) as c FROM lab_tasks WHERE status = ?',
        ['active'],
      );
      final done = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lab_submissions WHERE user_id = ? AND status IN ('已提交','已批改')",
        [userId],
      );
      final t = (total.first['c'] as int?) ?? 0;
      final d = (done.first['c'] as int?) ?? 0;
      labRate = t > 0 ? (d / t * 100).clamp(0, 100) : 0;
    } catch (_) {}

    // 3. 错题消化率
    double wrongDigest = 0;
    try {
      final allWrong = await db.rawQuery(
        'SELECT COUNT(*) as c FROM wrong_answers WHERE user_id = ?',
        [userId],
      );
      final explained = await db.rawQuery(
        "SELECT COUNT(*) as c FROM wrong_answers WHERE user_id = ? AND explanation IS NOT NULL AND explanation != ''",
        [userId],
      );
      final a = (allWrong.first['c'] as int?) ?? 0;
      final e = (explained.first['c'] as int?) ?? 0;
      wrongDigest = a > 0 ? (e / a * 100).clamp(0, 100) : 100;
    } catch (_) {}

    // 4. 概念覆盖率
    double conceptCov = 0;
    try {
      final totalNodes = await db.rawQuery(
        'SELECT COUNT(*) as c FROM nodes',
      );
      final learnedRows = await db.rawQuery(
        "SELECT COUNT(DISTINCT concept_id) as c FROM concept_progress WHERE user_id = ? AND status != 'not_started'",
        [userId],
      );
      final tn = (totalNodes.first['c'] as int?) ?? 0;
      final ln = (learnedRows.first['c'] as int?) ?? 0;
      conceptCov = tn > 0 ? (ln / tn * 100).clamp(0, 100) : 0;
    } catch (_) {}

    // 5. 总学习时长（分钟）
    int studyMin = 0;
    try {
      final r = await db.rawQuery(
        'SELECT SUM(study_time) as total FROM learning_records WHERE user_id = ?',
        [userId],
      );
      studyMin = (r.first['total'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    // 6. 近 8 周每周学习时长
    final weeklyMinutes = <double>[];
    try {
      for (int i = 7; i >= 0; i--) {
        final start = DateTime.now().subtract(Duration(days: (i + 1) * 7));
        final end = DateTime.now().subtract(Duration(days: i * 7));
        final r = await db.rawQuery(
          "SELECT COALESCE(SUM(study_time),0) as total FROM learning_records WHERE user_id = ? AND created_at >= ? AND created_at < ?",
          [userId, start.toIso8601String(), end.toIso8601String()],
        );
        weeklyMinutes.add((r.first['total'] as num?)?.toDouble() ?? 0);
      }
    } catch (_) {
      weeklyMinutes.addAll(List.filled(8, 0));
    }

    // 7. 5 维能力雷达
    final radar = <String, double>{
      '基础知识': quizAvg.clamp(0, 100),
      '实践能力': labRate,
      '创新思维': conceptCov * 0.8, // 近似
      '学习韧性': wrongDigest,
      '学习速度': (studyMin > 0 ? (conceptCov / studyMin * 60).clamp(0, 100) : 0),
    };

    // 8. 等级
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

    final profile = StudentTwinProfile(
      quizAvg: quizAvg,
      labCompletionRate: labRate,
      wrongDigestRate: wrongDigest,
      conceptCoverage: conceptCov,
      studyMinutesTotal: studyMin,
      weeklyMinutes: weeklyMinutes,
      radar: radar,
      level: level,
    );

    // 缓存快照
    unawaited(saveSnapshot(userId, 'student', profile.toJson()));

    return profile;
  }

  // ══════════════════════════════════════════════════════════════════
  // 教师画像
  // ══════════════════════════════════════════════════════════════════

  Future<TeacherTwinProfile> buildTeacherProfile(String teacherId) async {
    final db = await _dbHelper.database;

    // 班级人数
    int classSize = 0;
    try {
      final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM users WHERE role = 'student' AND is_active = 1",
      );
      classSize = (r.first['c'] as int?) ?? 0;
    } catch (_) {}

    // 班级均分（测验）
    double classAvg = 0;
    try {
      final r = await db.rawQuery(
        "SELECT AVG(score) as avg FROM quiz_results WHERE user_id IN (SELECT user_id FROM users WHERE role = 'student')",
      );
      classAvg = (r.first['avg'] as num?)?.toDouble() ?? 0;
    } catch (_) {}

    // 节点覆盖率（全班均值）
    final nodeCov = <int, double>{};
    try {
      final rows = await db.rawQuery('''
        SELECT node_id, AVG(overall) as avg
        FROM node_achievement
        GROUP BY node_id
      ''');
      for (final r in rows) {
        nodeCov[(r['node_id'] as int)] =
            (r['avg'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}

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
    } catch (_) {}

    // 待批阅数
    int pending = 0;
    try {
      final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lab_submissions WHERE status = '已提交'",
      );
      pending = (r.first['c'] as int?) ?? 0;
    } catch (_) {}

    final profile = TeacherTwinProfile(
      classSize: classSize,
      classAvg: classAvg,
      nodeCoverage: nodeCov,
      weakSpots: weakSpots,
      pendingGrading: pending,
    );

    unawaited(saveSnapshot(teacherId, 'teacher', profile.toJson()));
    return profile;
  }

  // ══════════════════════════════════════════════════════════════════
  // 快照缓存
  // ══════════════════════════════════════════════════════════════════

  Future<void> saveSnapshot(
      String userId, String role, Map<String, dynamic> json) async {
    try {
      final db = await _dbHelper.database;
      await db.insert(
        'twin_snapshots',
        {
          'user_id': userId,
          'role': role,
          'snapshot_json': jsonEncode(json),
          'generated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadCachedSnapshot(String userId) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        'twin_snapshots',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final generatedAt =
          DateTime.tryParse(rows.first['generated_at'] as String? ?? '');
      // 24h 缓存有效期
      if (generatedAt != null &&
          DateTime.now().difference(generatedAt).inHours < 24) {
        return jsonDecode(rows.first['snapshot_json'] as String)
            as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ── unawaited helper ──
  static void unawaited(Future<void> future) {
    future.catchError((_) {});
  }
}
