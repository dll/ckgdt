import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class LearningRecordDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  bool _conceptTableReady = false;

  // ══════════════════════════════════════════════════════════════════════════
  // concept_progress 表懒迁移
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _ensureConceptProgressTable() async {
    if (_conceptTableReady) return;
    final db = await _dbHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS concept_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        concept_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'not_started',
        learned_at TEXT,
        UNIQUE(user_id, concept_id)
      )
    ''');
    _conceptTableReady = true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 概念达成度 — CRUD
  // ══════════════════════════════════════════════════════════════════════════

  /// 获取用户所有概念的达成状态  conceptId → status
  Future<Map<int, String>> getConceptProgress(String userId) async {
    await _ensureConceptProgressTable();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'concept_progress',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final map = <int, String>{};
    for (final r in rows) {
      map[(r['concept_id'] as int)] = (r['status'] as String?) ?? 'not_started';
    }
    return map;
  }

  /// 更新单个概念的达成状态
  Future<void> updateConceptStatus(
      String userId, int conceptId, String status) async {
    await _ensureConceptProgressTable();
    final db = await _dbHelper.database;
    await db.insert(
      'concept_progress',
      {
        'user_id': userId,
        'concept_id': conceptId,
        'status': status,
        'learned_at': status == 'completed'
            ? DateTime.now().toIso8601String()
            : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 从已有的 quiz_results + learning_records 自动推导概念达成度
  /// [concepts] 为 knowledge_concepts 表的行列表
  Future<Map<int, String>> autoSyncConceptProgress(
      String userId, List<Map<String, dynamic>> concepts) async {
    await _ensureConceptProgressTable();
    final db = await _dbHelper.database;

    // ── 1. 收集已有的手动标记（优先级最高） ──
    final existing = await getConceptProgress(userId);

    // ── 2. 章节维度：quiz 成绩 ──
    final quizRows = await db.rawQuery(
      'SELECT chapter, AVG(score) as avg_score, COUNT(*) as cnt '
      'FROM quiz_results WHERE user_id = ? GROUP BY chapter',
      [userId],
    );
    final chapterQuiz = <int, double>{}; // chapter → avgScore
    for (final r in quizRows) {
      final ch = r['chapter'];
      if (ch == null) continue;
      final chInt = ch is int ? ch : int.tryParse(ch.toString().replaceAll(RegExp(r'[^0-9]'), ''));
      if (chInt != null) {
        chapterQuiz[chInt] = (r['avg_score'] as num?)?.toDouble() ?? 0;
      }
    }

    // ── 3. 学习记录中学过的节点标题集合 ──
    final learnedTitles = <String>{};
    final lrRows = await db.query(
      'learning_records',
      columns: ['node_title'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    for (final r in lrRows) {
      final t = r['node_title'] as String?;
      if (t != null && t.isNotEmpty) learnedTitles.add(t);
    }

    // ── 4. 推导每个概念的状态 ──
    final result = <int, String>{};
    for (final c in concepts) {
      final cId = c['id'] as int;

      // 已有手动标记 completed 的不覆盖
      if (existing[cId] == 'completed') {
        result[cId] = 'completed';
        continue;
      }

      final cName = (c['concept_name'] ?? c['name'] ?? '') as String;
      final chapter = c['chapter'] as int?;

      // 名称精确匹配学习记录 → completed
      if (learnedTitles.contains(cName)) {
        result[cId] = 'completed';
        await updateConceptStatus(userId, cId, 'completed');
        continue;
      }

      // 章节有测验且平均分 ≥ 80 → completed
      if (chapter != null && (chapterQuiz[chapter] ?? 0) >= 80) {
        result[cId] = 'completed';
        await updateConceptStatus(userId, cId, 'completed');
        continue;
      }

      // 章节有测验但分低，或有学习记录 → in_progress
      if (chapter != null && chapterQuiz.containsKey(chapter)) {
        result[cId] = 'in_progress';
        await updateConceptStatus(userId, cId, 'in_progress');
        continue;
      }

      // 保留已有的手动状态
      if (existing.containsKey(cId)) {
        result[cId] = existing[cId]!;
        continue;
      }

      result[cId] = 'not_started';
    }
    return result;
  }

  /// 获取达成度统计概览
  Future<Map<String, int>> getProgressStats(String userId) async {
    await _ensureConceptProgressTable();
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) as cnt FROM concept_progress '
      'WHERE user_id = ? GROUP BY status',
      [userId],
    );
    final stats = <String, int>{
      'completed': 0,
      'in_progress': 0,
      'not_started': 0,
    };
    for (final r in rows) {
      final s = r['status'] as String? ?? 'not_started';
      stats[s] = (r['cnt'] as int?) ?? 0;
    }
    return stats;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 原有学习记录方法
  // ══════════════════════════════════════════════════════════════════════════

  Future<int> addRecord({
    required String userId,
    required String nodeId,
    required String nodeTitle,
    String? studyTime,
  }) async {
    final db = await _dbHelper.database;
    return await db.insert('learning_records', {
      'user_id': userId,
      'node_id': nodeId,
      'node_title': nodeTitle,
      'study_time': studyTime ?? DateTime.now().toIso8601String(),
      'completed_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getRecords(String userId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'learning_records',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'completed_at DESC',
    );
  }

  Future<int> getTotalTime(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM learning_records WHERE user_id = ?',
      [userId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getCompletedNodes(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(DISTINCT node_id) as count FROM learning_records WHERE user_id = ?',
      [userId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<bool> hasLearned(String userId, String nodeId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'learning_records',
      where: 'user_id = ? AND node_id = ?',
      whereArgs: [userId, nodeId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> deleteRecord(int id, String userId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'learning_records',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<Map<String, dynamic>> getStatistics(String userId) async {
    final db = await _dbHelper.database;
    
    final totalRecords = await db.rawQuery(
      'SELECT COUNT(*) as count FROM learning_records WHERE user_id = ?',
      [userId],
    );
    
    final uniqueNodes = await db.rawQuery(
      'SELECT COUNT(DISTINCT node_id) as count FROM learning_records WHERE user_id = ?',
      [userId],
    );
    
    final thisWeek = await db.rawQuery(
      '''SELECT COUNT(*) as count FROM learning_records 
      WHERE user_id = ? AND completed_at >= date('now', '-7 days')''',
      [userId],
    );
    
    return {
      'total_records': totalRecords.first['count'] ?? 0,
      'unique_nodes': uniqueNodes.first['count'] ?? 0,
      'this_week': thisWeek.first['count'] ?? 0,
    };
  }
}
