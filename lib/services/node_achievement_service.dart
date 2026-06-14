import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import 'course_context_service.dart';

/// 节点级达成度服务 — 聚合 quiz/lab/work 分数到图谱节点
class NodeAchievementService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  /// 检查表是否存在
  Future<bool> _tableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  /// 检查表中是否存在指定列
  Future<bool> _columnExists(
      Database db, String tableName, String columnName) async {
    try {
      await db.rawQuery('SELECT $columnName FROM $tableName LIMIT 0');
      return true;
    } catch (e) {
      // schema 探测：列不存在属正常路径，不打日志
      swallow(e, tag: 'NodeAchievement._columnExists');
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

  /// 将课程达成度总表同步为知识节点达成度。
  ///
  /// 数据链路：achievement_scores(学生×课程目标) -> course_objectives(目标×章节)
  /// -> knowledge_concepts(章节×知识节点) -> node_achievement(学生×节点)。
  /// 返回写入的节点达成度行数；没有可同步的批次、成绩或节点时返回 0。
  Future<int> syncFromAchievementScores({
    int? batchId,
    List<Map<String, dynamic>> concepts = const [],
  }) async {
    final db = await _dbHelper.database;
    await _ensureNodeAchievementTable(db);

    final batch = await _resolveAchievementBatch(db, batchId);
    if (batch == null) return 0;

    final resolvedBatchId = _asInt(batch['id']);
    if (resolvedBatchId == null) return 0;

    final scores = await db.query(
      'achievement_scores',
      where: 'batch_id = ?',
      whereArgs: [resolvedBatchId],
      orderBy: 'student_id ASC',
    );
    if (scores.isEmpty) return 0;

    final courseNameValue = (batch['course_name'] ?? '').toString().trim();
    final courseName = courseNameValue.isNotEmpty ? courseNameValue : '移动应用开发';
    final objectives = await db.query(
      'course_objectives',
      where: 'course_name = ?',
      whereArgs: [courseName],
      orderBy: 'idx ASC',
    );

    final conceptRows =
        concepts.isNotEmpty ? concepts : await _loadKnowledgeConcepts(db);
    if (conceptRows.isEmpty) return 0;

    final nodeIdsByObjective =
        _mapConceptsToObjectives(conceptRows, objectives);
    if (nodeIdsByObjective.values.every((ids) => ids.isEmpty)) return 0;

    final allVisibleNodeIds = conceptRows
        .map((c) => _asInt(c['id']))
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final now = DateTime.now().toIso8601String();
    var upserted = 0;

    await db.transaction((txn) async {
      if (allVisibleNodeIds.isNotEmpty) {
        final nodePlaceholders =
            List.filled(allVisibleNodeIds.length, '?').join(',');
        await txn.delete(
          'node_achievement',
          where: 'node_id IN ($nodePlaceholders)',
          whereArgs: allVisibleNodeIds,
        );
      }

      for (final score in scores) {
        final studentId = (score['student_id'] ?? '').toString().trim();
        if (studentId.isEmpty) continue;

        for (var objectiveIdx = 1; objectiveIdx <= 4; objectiveIdx++) {
          final nodeIds = nodeIdsByObjective[objectiveIdx] ?? const <int>{};
          if (nodeIds.isEmpty) continue;
          final percent =
              _achievementToPercent(score['obj${objectiveIdx}_achievement']);

          for (final nodeId in nodeIds) {
            await txn.insert(
              'node_achievement',
              {
                'user_id': studentId,
                'node_id': nodeId,
                'quiz_score': 0,
                'lab_score': 0,
                'work_score': 0,
                'overall': percent,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            upserted++;
          }
        }
      }
    });

    return upserted;
  }

  Future<Map<String, dynamic>?> _resolveAchievementBatch(
    Database db,
    int? batchId,
  ) async {
    if (!await _tableExists(db, 'achievement_batches') ||
        !await _tableExists(db, 'achievement_scores')) {
      return null;
    }

    if (batchId != null) {
      final rows = await db.query(
        'achievement_batches',
        where: 'id = ?',
        whereArgs: [batchId],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    }

    final rows = await db.rawQuery('''
      SELECT ab.*
      FROM achievement_batches ab
      WHERE EXISTS (
        SELECT 1 FROM achievement_scores s WHERE s.batch_id = ab.id
      )
      ORDER BY
        CASE WHEN ab.status = 'completed' THEN 0 ELSE 1 END,
        COALESCE(ab.updated_at, ab.created_at, '') DESC,
        ab.id DESC
      LIMIT 1
    ''');
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> _loadKnowledgeConcepts(Database db) async {
    if (!await _tableExists(db, 'knowledge_concepts')) return const [];
    final scope = await _courseContext.scopedWhere();
    return db.query(
      'knowledge_concepts',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'id ASC',
    );
  }

  Map<int, Set<int>> _mapConceptsToObjectives(
    List<Map<String, dynamic>> concepts,
    List<Map<String, dynamic>> objectives,
  ) {
    final result = <int, Set<int>>{
      1: <int>{},
      2: <int>{},
      3: <int>{},
      4: <int>{},
    };
    final objectivesByIdx = <int, Map<String, dynamic>>{};
    for (final objective in objectives) {
      final idx = _asInt(objective['idx']);
      if (idx != null && idx >= 1 && idx <= 4) {
        objectivesByIdx[idx] = objective;
      }
    }

    for (final concept in concepts) {
      final nodeId = _asInt(concept['id']);
      if (nodeId == null) continue;

      final chapter = _asInt(concept['chapter']);
      final matchedObjectives = <int>{};

      for (var idx = 1; idx <= 4; idx++) {
        final objective = objectivesByIdx[idx];
        if (objective == null) continue;

        final chapters = _objectiveChapters(objective);
        if (chapter != null && chapters.contains(chapter)) {
          matchedObjectives.add(idx);
          continue;
        }

        if (chapters.isEmpty && _objectiveMentionsConcept(objective, concept)) {
          matchedObjectives.add(idx);
        }
      }

      if (matchedObjectives.isEmpty && chapter != null) {
        matchedObjectives.add(_fallbackObjectiveForChapter(chapter));
      }

      for (final idx in matchedObjectives) {
        result[idx]!.add(nodeId);
      }
    }

    return result;
  }

  Set<int> _objectiveChapters(Map<String, dynamic> objective) {
    final explicit =
        _extractChapterNumbers(objective['chapters'], allowStandalone: true);
    if (explicit.isNotEmpty) return explicit;

    return _extractChapterNumbers(
      [
        objective['description'],
        objective['assess_content'],
        objective['experiments'],
      ].whereType<Object>().join(' '),
      allowStandalone: false,
    );
  }

  Set<int> _extractChapterNumbers(
    Object? value, {
    required bool allowStandalone,
  }) {
    final text = (value ?? '').toString();
    final chapters = <int>{};

    for (final match in RegExp(r'第\s*(\d{1,2})\s*章').allMatches(text)) {
      final chapter = int.tryParse(match.group(1) ?? '');
      if (chapter != null) chapters.add(chapter);
    }

    for (final match in RegExp(r'第\s*([一二三四五六七八九十]+)\s*章').allMatches(text)) {
      final chapter = _chineseNumberToInt(match.group(1) ?? '');
      if (chapter != null) chapters.add(chapter);
    }

    for (final match
        in RegExp(r'(\d{1,2})\s*[-~至到]\s*(\d{1,2})').allMatches(text)) {
      final start = int.tryParse(match.group(1) ?? '');
      final end = int.tryParse(match.group(2) ?? '');
      if (start == null || end == null) continue;
      final lower = start <= end ? start : end;
      final upper = start <= end ? end : start;
      for (var chapter = lower; chapter <= upper; chapter++) {
        chapters.add(chapter);
      }
    }

    if (allowStandalone && chapters.isEmpty) {
      for (final part in text.split(RegExp(r'[^0-9]+'))) {
        final chapter = int.tryParse(part);
        if (chapter != null && chapter > 0 && chapter <= 30) {
          chapters.add(chapter);
        }
      }
    }

    return chapters;
  }

  int? _chineseNumberToInt(String value) {
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) {
      return 10 + (digits[value.substring(1)] ?? 0);
    }
    if (value.endsWith('十')) {
      return (digits[value.substring(0, 1)] ?? 0) * 10;
    }
    if (value.contains('十')) {
      final parts = value.split('十');
      return (digits[parts[0]] ?? 0) * 10 + (digits[parts[1]] ?? 0);
    }
    return digits[value];
  }

  bool _objectiveMentionsConcept(
    Map<String, dynamic> objective,
    Map<String, dynamic> concept,
  ) {
    final objectiveText = _normalizeText([
      objective['name'],
      objective['indicator'],
      objective['description'],
      objective['assess_content'],
      objective['experiments'],
    ].whereType<Object>().join(' '));
    if (objectiveText.isEmpty) return false;

    for (final term in _conceptTerms(concept)) {
      final normalized = _normalizeText(term);
      if (normalized.length >= 2 && objectiveText.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  Set<String> _conceptTerms(Map<String, dynamic> concept) {
    final terms = <String>{};
    void addTerm(Object? value) {
      final text = (value ?? '').toString().trim();
      if (text.length >= 2) terms.add(text);
    }

    addTerm(concept['concept_name'] ?? concept['name']);
    final keywords = (concept['keywords'] ?? '').toString();
    for (final part in keywords.split(RegExp(r'[,，、;；/\s]+'))) {
      addTerm(part);
    }
    return terms;
  }

  String _normalizeText(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  int _fallbackObjectiveForChapter(int chapter) {
    if (chapter <= 2) return 1;
    if (chapter <= 4) return 2;
    if (chapter == 5) return 3;
    return 4;
  }

  double _achievementToPercent(Object? value) {
    final raw = value is num
        ? value.toDouble()
        : double.tryParse((value ?? '').toString()) ?? 0;
    if (raw <= 1) return (raw * 100).clamp(0.0, 100.0).toDouble();
    return raw.clamp(0.0, 100.0).toDouble();
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString());
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
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
            final scope = await _courseContext.scopedWhere(
              column: 'qr.course_id',
              extraWhere: 'qr.user_id = ? AND q.node_id = ?',
              extraArgs: [userId, nodeId],
            );
            final qr = await db.rawQuery('''
              SELECT AVG(qr.score) as avg_score
              FROM quiz_results qr
              JOIN questions q ON qr.chapter = q.source
              WHERE ${scope.where}
            ''', scope.args);
            quizScore = (qr.first['avg_score'] as num?)?.toDouble() ?? 0;
          }
        } catch (e, st) {
          swallowDebug(e, tag: 'NodeAchievement.quizScore', stack: st);
        }
      }

      if (hasLabSubmissions && hasLabTasks) {
        try {
          final hasRelatedNodeIds =
              await _columnExists(db, 'lab_tasks', 'related_node_ids');
          if (hasRelatedNodeIds) {
            final scope = await _courseContext.scopedWhere(
              column: 'lt.course_id',
              extraWhere:
                  'ls.user_id = ? AND ls.score IS NOT NULL AND lt.related_node_ids LIKE ?',
              extraArgs: [userId, '%$nodeId%'],
            );
            final lr = await db.rawQuery('''
              SELECT AVG(ls.score) as avg_score
              FROM lab_submissions ls
              JOIN lab_tasks lt ON ls.task_id = lt.id
              WHERE ${scope.where}
            ''', scope.args);
            labScore = (lr.first['avg_score'] as num?)?.toDouble() ?? 0;
          }
        } catch (e, st) {
          swallowDebug(e, tag: 'NodeAchievement.labScore', stack: st);
        }
      }

      if (hasWorkScores && hasStudentWorks) {
        try {
          final hasRelatedNodeIds =
              await _columnExists(db, 'student_works', 'related_node_ids');
          if (hasRelatedNodeIds) {
            final scope = await _courseContext.scopedWhere(
              column: 'sw.course_id',
              extraWhere: 'sw.user_id = ? AND sw.related_node_ids LIKE ?',
              extraArgs: [userId, '%$nodeId%'],
            );
            final wr = await db.rawQuery('''
              SELECT AVG(ws.total_score) as avg_score
              FROM work_scores ws
              JOIN student_works sw ON ws.work_id = sw.id
              WHERE ${scope.where}
            ''', scope.args);
            workScore = (wr.first['avg_score'] as num?)?.toDouble() ?? 0;
          }
        } catch (e, st) {
          swallowDebug(e, tag: 'NodeAchievement.workScore', stack: st);
        }
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
    await _ensureNodeAchievementTable(db);
    final map = <int, double>{};

    try {
      String sql;
      List<Object?> args;

      if (userId != null) {
        sql = 'SELECT node_id, overall FROM node_achievement WHERE user_id = ?';
        args = [userId];
      } else {
        sql =
            'SELECT node_id, AVG(overall) as overall FROM node_achievement GROUP BY node_id';
        args = [];
      }

      final rows = await db.rawQuery(sql, args);
      for (final r in rows) {
        final nid = _asInt(r['node_id']);
        if (nid == null) continue;
        final val = _asDouble(r['overall']);
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
    } catch (e, st) {
      swallowDebug(e, tag: 'NodeAchievement.getWeakNodes', stack: st);
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
