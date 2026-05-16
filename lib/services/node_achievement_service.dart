import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';

/// 节点级达成度服务 — 聚合 quiz/lab/work 分数到图谱节点
class NodeAchievementService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 检查表是否存在
  Future<bool> _tableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  /// 检查表中是否存在指定列
  Future<bool> _columnExists(Database db, String tableName, String columnName) async {
    try {
      await db.rawQuery('SELECT $columnName FROM $tableName LIMIT 0');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 确保 node_achievement 表存在
  Future<void> _ensureNodeAchievementTable(Database db) async {
    if (!await _tableExists(db, 'node_achievement')) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS node_achievement (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          node_id INTEGER NOT NULL,
          quiz_score REAL DEFAULT 0,
          lab_score REAL DEFAULT 0,
          work_score REAL DEFAULT 0,
          overall REAL DEFAULT 0,
          updated_at TEXT,
          UNIQUE(user_id, node_id)
        )
      ''');
    }
  }

  /// 重算某用户指定节点的综合达成度
  /// 权重：quiz 30% + lab 40% + work 30%
  Future<void> recompute(String userId, List<int> nodeIds) async {
    if (nodeIds.isEmpty) return;
    final db = await _dbHelper.database;
    await _ensureNodeAchievementTable(db);

    final hasQuestions = await _tableExists(db, 'questions');
    final hasQuizResults = await _tableExists(db, 'quiz_results');
    final hasLabSubmissions = await _tableExists(db, 'lab_submissions');
    final hasLabTasks = await _tableExists(db, 'lab_tasks');
    final hasWorkScores = await _tableExists(db, 'work_scores');
    final hasStudentWorks = await _tableExists(db, 'student_works');

    for (final nodeId in nodeIds) {
      double quizScore = 0;
      double labScore = 0;
      double workScore = 0;

      if (hasQuizResults && hasQuestions) {
        try {
          final hasNodeId = await _columnExists(db, 'questions', 'node_id');
          if (hasNodeId) {
            final qr = await db.rawQuery('''
              SELECT AVG(qr.score) as avg_score
              FROM quiz_results qr
              JOIN questions q ON qr.chapter = q.source
              WHERE qr.user_id = ? AND q.node_id = ?
            ''', [userId, nodeId]);
            quizScore = (qr.first['avg_score'] as num?)?.toDouble() ?? 0;
          }
        } catch (_) {}
      }

      if (hasLabSubmissions && hasLabTasks) {
        try {
          final hasRelatedNodeIds = await _columnExists(db, 'lab_tasks', 'related_node_ids');
          if (hasRelatedNodeIds) {
            final lr = await db.rawQuery('''
              SELECT AVG(ls.score) as avg_score
              FROM lab_submissions ls
              JOIN lab_tasks lt ON ls.task_id = lt.id
              WHERE ls.user_id = ? AND ls.score IS NOT NULL
                AND lt.related_node_ids LIKE ?
            ''', [userId, '%$nodeId%']);
            labScore = (lr.first['avg_score'] as num?)?.toDouble() ?? 0;
          }
        } catch (_) {}
      }

      if (hasWorkScores && hasStudentWorks) {
        try {
          final hasRelatedNodeIds = await _columnExists(db, 'student_works', 'related_node_ids');
          if (hasRelatedNodeIds) {
            final wr = await db.rawQuery('''
              SELECT AVG(ws.total_score) as avg_score
              FROM work_scores ws
              JOIN student_works sw ON ws.work_id = sw.id
              WHERE sw.user_id = ? AND sw.related_node_ids LIKE ?
            ''', [userId, '%$nodeId%']);
            workScore = (wr.first['avg_score'] as num?)?.toDouble() ?? 0;
          }
        } catch (_) {}
      }

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
