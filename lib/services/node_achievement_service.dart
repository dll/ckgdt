import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';

/// 节点级达成度服务 — 聚合 quiz/lab/work 分数到图谱节点
class NodeAchievementService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 重算某用户指定节点的综合达成度
  /// 权重：quiz 30% + lab 40% + work 30%
  Future<void> recompute(String userId, List<int> nodeIds) async {
    if (nodeIds.isEmpty) return;
    final db = await _dbHelper.database;

    for (final nodeId in nodeIds) {
      double quizScore = 0;
      double labScore = 0;
      double workScore = 0;

      // quiz_results 中关联该节点的平均分
      try {
        final qr = await db.rawQuery('''
          SELECT AVG(qr.score) as avg_score
          FROM quiz_results qr
          JOIN questions q ON qr.chapter = q.source
          WHERE qr.user_id = ? AND q.node_id = ?
        ''', [userId, nodeId]);
        quizScore = (qr.first['avg_score'] as num?)?.toDouble() ?? 0;
      } catch (_) {}

      // lab_submissions 关联该节点的平均分
      try {
        final lr = await db.rawQuery('''
          SELECT AVG(ls.score) as avg_score
          FROM lab_submissions ls
          JOIN lab_tasks lt ON ls.task_id = lt.id
          WHERE ls.user_id = ? AND ls.score IS NOT NULL
            AND lt.related_node_ids LIKE ?
        ''', [userId, '%$nodeId%']);
        labScore = (lr.first['avg_score'] as num?)?.toDouble() ?? 0;
      } catch (_) {}

      // student_works 关联该节点的平均分
      try {
        final wr = await db.rawQuery('''
          SELECT AVG(ws.total_score) as avg_score
          FROM work_scores ws
          JOIN student_works sw ON ws.work_id = sw.id
          WHERE sw.user_id = ? AND sw.related_node_ids LIKE ?
        ''', [userId, '%$nodeId%']);
        workScore = (wr.first['avg_score'] as num?)?.toDouble() ?? 0;
      } catch (_) {}

      final overall = quizScore * 0.3 + labScore * 0.4 + workScore * 0.3;

      await db.insert(
        'node_achievement',
        {
          'user_id': userId,
          'node_id': nodeId,
          'quiz_score': quizScore,
          'lab_score': labScore,
          'work_score': workScore,
          'overall': overall,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 获取全班或单生的节点热力图 → Map<nodeId, 0-100>
  Future<Map<int, double>> getHeatmap({String? userId, int? batchId}) async {
    final db = await _dbHelper.database;
    final map = <int, double>{};

    try {
      String sql;
      List<Object?> args;

      if (userId != null) {
        sql =
            'SELECT node_id, overall FROM node_achievement WHERE user_id = ?';
        args = [userId];
      } else {
        sql =
            'SELECT node_id, AVG(overall) as overall FROM node_achievement GROUP BY node_id';
        args = [];
      }

      final rows = await db.rawQuery(sql, args);
      for (final r in rows) {
        final nid = r['node_id'] as int;
        final val = (r['overall'] as num?)?.toDouble() ?? 0;
        map[nid] = val;
      }
    } catch (e) {
      debugPrint('NodeAchievementService.getHeatmap error: $e');
    }

    return map;
  }

  /// 获取 Top N 薄弱节点（全班平均最低）
  Future<List<Map<String, dynamic>>> getWeakNodes({int limit = 5}) async {
    final db = await _dbHelper.database;
    try {
      return await db.rawQuery('''
        SELECT na.node_id, n.label as node_title, AVG(na.overall) as avg_score
        FROM node_achievement na
        LEFT JOIN nodes n ON na.node_id = n.id
        GROUP BY na.node_id
        ORDER BY avg_score ASC
        LIMIT ?
      ''', [limit]);
    } catch (_) {
      return [];
    }
  }

  /// 节点掌握统计 → {mastered, learning, weak}
  Future<Map<String, int>> getNodeStats(String userId) async {
    final heatmap = await getHeatmap(userId: userId);
    int mastered = 0, learning = 0, weak = 0;
    for (final score in heatmap.values) {
      if (score >= 80) {
        mastered++;
      } else if (score >= 60) {
        learning++;
      } else {
        weak++;
      }
    }
    return {'mastered': mastered, 'learning': learning, 'weak': weak};
  }
}
