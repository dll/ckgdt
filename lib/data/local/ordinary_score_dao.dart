import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'active_student_scope.dart';
import 'database_helper.dart';
import '../../core/error_handler.dart';
import '../../services/course_context_service.dart';

/// 平时成绩聚合 DAO。
///
/// 数据口径：
/// - 课堂表现：课堂积分为主，默认直接折算到 20 分。
/// - 期间测验：教学测验平均分折算到 30 分。
/// - 课外学习：课件学习、AI 自主学习、扩展资源、推荐学习综合折算到 50 分。
class OrdinaryScoreDao {
  final CourseContextService _courseContext = CourseContextService();

  static const double defaultClassroomWeight = 20;
  static const double defaultQuizWeight = 30;
  static const double defaultExtraWeight = 50;

  bool _tablesEnsured = false;

  Future<void> _ensureTables() async {
    if (_tablesEnsured) return;
    final db = await DatabaseHelper.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ordinary_score_settings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT NOT NULL UNIQUE,
        classroom_weight REAL DEFAULT 20,
        quiz_weight REAL DEFAULT 30,
        extra_weight REAL DEFAULT 50,
        classroom_points_ratio REAL DEFAULT 100,
        classroom_checkin_ratio REAL DEFAULT 0,
        classroom_answer_ratio REAL DEFAULT 0,
        quiz_average_ratio REAL DEFAULT 100,
        quiz_completion_ratio REAL DEFAULT 0,
        extra_courseware_ratio REAL DEFAULT 40,
        extra_ai_ratio REAL DEFAULT 25,
        extra_extended_ratio REAL DEFAULT 20,
        extra_recommend_ratio REAL DEFAULT 15,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS roll_call_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        class_id INTEGER,
        created_by TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checkin_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        class_id INTEGER,
        title TEXT,
        started_at TEXT,
        ended_at TEXT,
        late_minutes INTEGER DEFAULT 10,
        status TEXT DEFAULT 'active',
        created_by TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS roll_call_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT,
        difficulty TEXT NOT NULL,
        tier TEXT NOT NULL,
        is_correct INTEGER DEFAULT 0,
        score_delta REAL DEFAULT 0,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checkin_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT,
        status TEXT DEFAULT 'absent',
        checked_at TEXT,
        UNIQUE(session_id, user_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS classroom_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        class_id INTEGER,
        sender_id TEXT,
        sender_name TEXT,
        sender_role TEXT,
        content TEXT,
        message_type TEXT DEFAULT 'announcement',
        parent_id INTEGER,
        created_at TEXT
      )
    ''');

    for (final sql in const [
      'ALTER TABLE roll_call_sessions ADD COLUMN course_id TEXT',
      'ALTER TABLE checkin_sessions ADD COLUMN course_id TEXT',
      'ALTER TABLE classroom_messages ADD COLUMN course_id TEXT',
      'ALTER TABLE ai_chat_history ADD COLUMN course_id TEXT',
      'ALTER TABLE hot_video_favorites ADD COLUMN course_id TEXT',
    ]) {
      try {
        await db.execute(sql);
      } catch (e) {
        swallow(e, tag: 'OrdinaryScore.ensureCourseColumns');
      }
    }
    for (final table in const [
      'roll_call_sessions',
      'checkin_sessions',
      'classroom_messages',
      'ai_chat_history',
      'hot_video_favorites',
    ]) {
      try {
        await db.update(
          table,
          {'course_id': CourseContextService.defaultCourseId},
          where: "course_id IS NULL OR course_id = ''",
        );
      } catch (e) {
        swallow(e, tag: 'OrdinaryScore.defaultCourse');
      }
    }

    _tablesEnsured = true;
  }

  Future<OrdinaryScoreSettings> getSettings() async {
    await _ensureTables();
    final db = await DatabaseHelper.instance.database;
    final courseId = await _courseContext.activeCourseId();
    final rows = await db.query(
      'ordinary_score_settings',
      where: 'course_id = ?',
      whereArgs: [courseId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return OrdinaryScoreSettings.fromMap(rows.first).normalizedMainWeights();
    }

    final settings = OrdinaryScoreSettings.defaults(courseId);
    await saveSettings(settings);
    return settings;
  }

  Future<void> saveSettings(OrdinaryScoreSettings settings) async {
    await _ensureTables();
    final db = await DatabaseHelper.instance.database;
    final normalized = settings.normalizedMainWeights();
    await db.insert(
      'ordinary_score_settings',
      normalized.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OrdinaryScoreSnapshot> loadSnapshot() async {
    await _ensureTables();
    final settings = await getSettings();
    final courseId = await _courseContext.activeCourseId();
    final courseName =
        await _courseContext.activeCourseName(fallback: '移动应用开发');

    final students = await _loadStudents();
    final classroom = await _loadClassroomMetrics();
    final quiz = await _loadQuizMetrics();
    final learning = await _loadLearningMetrics();
    final ai = await _loadAiMetrics();
    final recommend = await _loadRecommendMetrics();

    final maxAnswerCount = _maxOf(classroom.values.map((m) => m.answerCount));
    final maxQuizAttempts = _maxOf(quiz.values.map((m) => m.attemptCount));
    final maxCourseware = _maxOf(learning.values.map((m) => m.coursewareValue));
    final maxExtended = _maxOf(learning.values.map((m) => m.extendedValue));
    final maxAi = _maxOf(ai.values.map((m) => m.activityValue));
    final maxRecommend = _maxOf([
      ...learning.values.map((m) => m.recommendValue),
      ...recommend.values.map((m) => m.favoriteCount.toDouble()),
    ]);

    final rows = <OrdinaryStudentScore>[];
    for (final student in students) {
      final studentId = student['user_id']?.toString() ?? '';
      if (studentId.isEmpty) continue;
      final name = (student['real_name']?.toString().trim().isNotEmpty ?? false)
          ? student['real_name'].toString()
          : studentId;

      final c = classroom[studentId] ?? const _ClassroomMetrics();
      final q = quiz[studentId] ?? const _QuizMetrics();
      final l = learning[studentId] ?? const _LearningMetrics();
      final a = ai[studentId] ?? const _AiMetrics();
      final r = recommend[studentId] ?? const _RecommendMetrics();

      final classroomPointPct = settings.classroomWeight > 0
          ? _percent(c.earnedPoints, settings.classroomWeight)
          : 0.0;
      final checkinPct = c.checkinCount > 0
          ? _clampPercent(c.checkinCredit / c.checkinCount * 100)
          : 0.0;
      final answerPct =
          maxAnswerCount > 0 ? _percent(c.answerCount, maxAnswerCount) : 0.0;
      final classroomPct = _weightedPercent([
        MapEntry(settings.classroomPointsRatio, classroomPointPct),
        MapEntry(settings.classroomCheckinRatio, checkinPct),
        MapEntry(settings.classroomAnswerRatio, answerPct),
      ]);

      final quizAvgPct = _clampPercent(q.averageScore);
      final quizCompletionPct =
          maxQuizAttempts > 0 ? _percent(q.attemptCount, maxQuizAttempts) : 0.0;
      final quizPct = _weightedPercent([
        MapEntry(settings.quizAverageRatio, quizAvgPct),
        MapEntry(settings.quizCompletionRatio, quizCompletionPct),
      ]);

      final coursewarePct =
          maxCourseware > 0 ? _percent(l.coursewareValue, maxCourseware) : 0.0;
      final aiPct = maxAi > 0 ? _percent(a.activityValue, maxAi) : 0.0;
      final extendedPct =
          maxExtended > 0 ? _percent(l.extendedValue, maxExtended) : 0.0;
      final recommendValue = l.recommendValue + r.favoriteCount;
      final recommendPct =
          maxRecommend > 0 ? _percent(recommendValue, maxRecommend) : 0.0;
      final extraPct = _weightedPercent([
        MapEntry(settings.extraCoursewareRatio, coursewarePct),
        MapEntry(settings.extraAiRatio, aiPct),
        MapEntry(settings.extraExtendedRatio, extendedPct),
        MapEntry(settings.extraRecommendRatio, recommendPct),
      ]);

      rows.add(OrdinaryStudentScore(
        studentId: studentId,
        studentName: name,
        classroomPercent: classroomPct,
        quizPercent: quizPct,
        extraPercent: extraPct,
        classroomScore: classroomPct / 100 * settings.classroomWeight,
        quizScore: quizPct / 100 * settings.quizWeight,
        extraScore: extraPct / 100 * settings.extraWeight,
        metrics: OrdinaryScoreMetrics(
          earnedClassroomPoints: c.earnedPoints,
          rollCallCount: c.callCount,
          rollCallCorrectCount: c.correctCount,
          checkinCount: c.checkinCount,
          answerCount: c.answerCount,
          quizAverage: q.averageScore,
          quizBest: q.bestScore,
          quizAttempts: q.attemptCount,
          coursewareRecords: l.coursewareRecords,
          coursewareMinutes: l.coursewareMinutes,
          extendedRecords: l.extendedRecords,
          recommendRecords: l.recommendRecords,
          recommendFavorites: r.favoriteCount,
          aiRequests: a.requestCount,
          aiTokens: a.totalTokens,
          aiActiveDays: a.activeDays,
        ),
      ));
    }

    rows.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return OrdinaryScoreSnapshot(
      courseId: courseId,
      courseName: courseName,
      settings: settings,
      rows: rows,
      generatedAt: DateTime.now(),
    );
  }

  Future<List<Map<String, dynamic>>> _loadStudents() async {
    final db = await DatabaseHelper.instance.database;
    try {
      final activeWhere = ActiveStudentScope.where(alias: 'u');
      return await db.rawQuery('''
        SELECT u.user_id, u.real_name
        FROM users u
        WHERE $activeWhere
        ORDER BY u.user_id ASC
      ''');
    } catch (e, st) {
      swallowDebug(e, tag: 'OrdinaryScore.loadStudents', stack: st);
      return await db.rawQuery('''
        SELECT user_id, real_name
        FROM users
        WHERE role = 'student' AND COALESCE(is_active, 1) = 1
        ORDER BY user_id ASC
      ''');
    }
  }

  Future<Map<String, _ClassroomMetrics>> _loadClassroomMetrics() async {
    final db = await DatabaseHelper.instance.database;
    final result = <String, _ClassroomMetrics>{};
    final rollScope = await _courseContext.scopedWhere(column: 's.course_id');

    final rollCallRows = await db.rawQuery('''
      SELECT r.user_id,
             COALESCE(SUM(r.score_delta), 0) AS earned_points,
             COUNT(*) AS call_count,
             COALESCE(SUM(CASE WHEN r.is_correct = 1 THEN 1 ELSE 0 END), 0)
               AS correct_count
      FROM roll_call_records r
      LEFT JOIN roll_call_sessions s ON s.id = r.session_id
      WHERE ${rollScope.where}
      GROUP BY r.user_id
    ''', rollScope.args);
    for (final row in rollCallRows) {
      final userId = row['user_id']?.toString() ?? '';
      if (userId.isEmpty) continue;
      result[userId] = (result[userId] ?? const _ClassroomMetrics()).copyWith(
        earnedPoints: math.max(
          0,
          (row['earned_points'] as num?)?.toDouble() ?? 0,
        ),
        callCount: (row['call_count'] as num?)?.toInt() ?? 0,
        correctCount: (row['correct_count'] as num?)?.toInt() ?? 0,
      );
    }

    final checkinScope =
        await _courseContext.scopedWhere(column: 's.course_id');
    final checkinRows = await db.rawQuery('''
      SELECT cr.user_id,
             COUNT(*) AS checkin_count,
             COALESCE(SUM(
               CASE cr.status
                 WHEN 'present' THEN 1.0
                 WHEN 'late' THEN 0.6
                 ELSE 0.0
               END
             ), 0) AS checkin_credit
      FROM checkin_records cr
      LEFT JOIN checkin_sessions s ON s.id = cr.session_id
      WHERE ${checkinScope.where}
      GROUP BY cr.user_id
    ''', checkinScope.args);
    for (final row in checkinRows) {
      final userId = row['user_id']?.toString() ?? '';
      if (userId.isEmpty) continue;
      result[userId] = (result[userId] ?? const _ClassroomMetrics()).copyWith(
        checkinCount: (row['checkin_count'] as num?)?.toInt() ?? 0,
        checkinCredit: (row['checkin_credit'] as num?)?.toDouble() ?? 0,
      );
    }

    final answerScope = await _courseContext.scopedWhere(
      column: 'cm.course_id',
      extraWhere:
          "cm.sender_role = 'student' AND cm.message_type IN ('answer', 'reply')",
    );
    final answerRows = await db.rawQuery('''
      SELECT sender_id AS user_id, COUNT(*) AS answer_count
      FROM classroom_messages cm
      WHERE ${answerScope.where}
      GROUP BY sender_id
    ''', answerScope.args);
    for (final row in answerRows) {
      final userId = row['user_id']?.toString() ?? '';
      if (userId.isEmpty) continue;
      result[userId] = (result[userId] ?? const _ClassroomMetrics()).copyWith(
        answerCount: (row['answer_count'] as num?)?.toInt() ?? 0,
      );
    }

    return result;
  }

  Future<Map<String, _QuizMetrics>> _loadQuizMetrics() async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere();
    final rows = await db.rawQuery('''
      SELECT user_id,
             AVG(score) AS avg_score,
             MAX(score) AS best_score,
             COUNT(*) AS attempt_count
      FROM quiz_results
      WHERE ${scope.where}
      GROUP BY user_id
    ''', scope.args);
    return {
      for (final row in rows)
        if ((row['user_id']?.toString() ?? '').isNotEmpty)
          row['user_id'].toString(): _QuizMetrics(
            averageScore: (row['avg_score'] as num?)?.toDouble() ?? 0,
            bestScore: (row['best_score'] as num?)?.toDouble() ?? 0,
            attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
          )
    };
  }

  Future<Map<String, _LearningMetrics>> _loadLearningMetrics() async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere(column: 'lr.course_id');
    final rows = await db.rawQuery('''
      SELECT lr.user_id, lr.node_id, lr.node_title, lr.study_time,
             rf.source_type, rf.file_type
      FROM learning_records lr
      LEFT JOIN resource_files rf
        ON lr.node_id = CAST(rf.id AS TEXT)
        OR lr.node_id = 'resource_' || CAST(rf.id AS TEXT)
        OR lr.node_title = rf.file_name
      WHERE ${scope.where}
    ''', scope.args);

    final result = <String, _LearningMetrics>{};
    for (final row in rows) {
      final userId = row['user_id']?.toString() ?? '';
      if (userId.isEmpty) continue;

      final nodeId = (row['node_id'] ?? '').toString().toLowerCase();
      final title = (row['node_title'] ?? '').toString().toLowerCase();
      final sourceType = (row['source_type'] ?? '').toString().toLowerCase();
      final minutes = _parseStudyMinutes(row['study_time']);
      final unitValue = 1.0 + minutes / 30.0;
      final current = result[userId] ?? const _LearningMetrics();

      if (nodeId.startsWith('hot_video_') ||
          title.contains('推荐') ||
          title.contains('hot video')) {
        result[userId] = current.copyWith(
          recommendRecords: current.recommendRecords + 1,
          recommendValue: current.recommendValue + unitValue,
        );
      } else if (sourceType == 'extended' ||
          nodeId.contains('extended') ||
          title.contains('扩展')) {
        result[userId] = current.copyWith(
          extendedRecords: current.extendedRecords + 1,
          extendedValue: current.extendedValue + unitValue,
        );
      } else {
        result[userId] = current.copyWith(
          coursewareRecords: current.coursewareRecords + 1,
          coursewareMinutes: current.coursewareMinutes + minutes,
          coursewareValue: current.coursewareValue + unitValue,
        );
      }
    }

    return result;
  }

  Future<Map<String, _AiMetrics>> _loadAiMetrics() async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere:
          "role = 'assistant' AND user_id IS NOT NULL AND user_id != ''",
    );
    final rows = await db.rawQuery('''
      SELECT user_id,
             COUNT(*) AS request_count,
             COALESCE(SUM(tokens_used), 0) AS total_tokens,
             COUNT(DISTINCT DATE(created_at)) AS active_days
      FROM ai_chat_history
      WHERE ${scope.where}
      GROUP BY user_id
    ''', scope.args);
    return {
      for (final row in rows)
        if ((row['user_id']?.toString() ?? '').isNotEmpty)
          row['user_id'].toString(): _AiMetrics(
            requestCount: (row['request_count'] as num?)?.toInt() ?? 0,
            totalTokens: (row['total_tokens'] as num?)?.toInt() ?? 0,
            activeDays: (row['active_days'] as num?)?.toInt() ?? 0,
          )
    };
  }

  Future<Map<String, _RecommendMetrics>> _loadRecommendMetrics() async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere();
    final rows = await db.rawQuery('''
      SELECT user_id, COUNT(*) AS favorite_count
      FROM hot_video_favorites
      WHERE ${scope.where}
      GROUP BY user_id
    ''', scope.args);
    return {
      for (final row in rows)
        if ((row['user_id']?.toString() ?? '').isNotEmpty)
          row['user_id'].toString(): _RecommendMetrics(
            favoriteCount: (row['favorite_count'] as num?)?.toInt() ?? 0,
          )
    };
  }

  static double _weightedPercent(Iterable<MapEntry<double, double>> entries) {
    var weighted = 0.0;
    var weightSum = 0.0;
    for (final entry in entries) {
      final weight = entry.key;
      final value = entry.value;
      if (weight <= 0) continue;
      weighted += weight * _clampPercent(value);
      weightSum += weight;
    }
    if (weightSum <= 0) return 0;
    return _clampPercent(weighted / weightSum);
  }

  static double _percent(num value, num full) {
    if (full <= 0) return 0;
    return _clampPercent(value.toDouble() / full.toDouble() * 100);
  }

  static double _clampPercent(num value) =>
      value.toDouble().clamp(0.0, 100.0).toDouble();

  static double _maxOf(Iterable<num> values) {
    var max = 0.0;
    for (final value in values) {
      if (value > max) max = value.toDouble();
    }
    return max;
  }

  static double _parseStudyMinutes(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 0;

    final numeric = double.tryParse(text);
    if (numeric != null) {
      if (numeric <= 0) return 0;
      return numeric > 600 ? numeric / 60.0 : numeric;
    }

    final hms =
        RegExp(r'^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(text);
    if (hms != null) {
      final h = int.tryParse(hms.group(1) ?? '') ?? 0;
      final m = int.tryParse(hms.group(2) ?? '') ?? 0;
      final s = int.tryParse(hms.group(3) ?? '') ?? 0;
      return h * 60 + m + s / 60.0;
    }

    return 0;
  }
}

class OrdinaryScoreSettings {
  final String courseId;
  final double classroomWeight;
  final double quizWeight;
  final double extraWeight;
  final double classroomPointsRatio;
  final double classroomCheckinRatio;
  final double classroomAnswerRatio;
  final double quizAverageRatio;
  final double quizCompletionRatio;
  final double extraCoursewareRatio;
  final double extraAiRatio;
  final double extraExtendedRatio;
  final double extraRecommendRatio;

  const OrdinaryScoreSettings({
    required this.courseId,
    required this.classroomWeight,
    required this.quizWeight,
    required this.extraWeight,
    required this.classroomPointsRatio,
    required this.classroomCheckinRatio,
    required this.classroomAnswerRatio,
    required this.quizAverageRatio,
    required this.quizCompletionRatio,
    required this.extraCoursewareRatio,
    required this.extraAiRatio,
    required this.extraExtendedRatio,
    required this.extraRecommendRatio,
  });

  factory OrdinaryScoreSettings.defaults(String courseId) {
    return OrdinaryScoreSettings(
      courseId: courseId,
      classroomWeight: OrdinaryScoreDao.defaultClassroomWeight,
      quizWeight: OrdinaryScoreDao.defaultQuizWeight,
      extraWeight: OrdinaryScoreDao.defaultExtraWeight,
      classroomPointsRatio: 100,
      classroomCheckinRatio: 0,
      classroomAnswerRatio: 0,
      quizAverageRatio: 100,
      quizCompletionRatio: 0,
      extraCoursewareRatio: 40,
      extraAiRatio: 25,
      extraExtendedRatio: 20,
      extraRecommendRatio: 15,
    );
  }

  factory OrdinaryScoreSettings.fromMap(Map<String, dynamic> map) {
    double d(String key, double fallback) =>
        (map[key] as num?)?.toDouble() ?? fallback;
    return OrdinaryScoreSettings(
      courseId:
          map['course_id']?.toString() ?? CourseContextService.defaultCourseId,
      classroomWeight: d('classroom_weight', 20),
      quizWeight: d('quiz_weight', 30),
      extraWeight: d('extra_weight', 50),
      classroomPointsRatio: d('classroom_points_ratio', 100),
      classroomCheckinRatio: d('classroom_checkin_ratio', 0),
      classroomAnswerRatio: d('classroom_answer_ratio', 0),
      quizAverageRatio: d('quiz_average_ratio', 100),
      quizCompletionRatio: d('quiz_completion_ratio', 0),
      extraCoursewareRatio: d('extra_courseware_ratio', 40),
      extraAiRatio: d('extra_ai_ratio', 25),
      extraExtendedRatio: d('extra_extended_ratio', 20),
      extraRecommendRatio: d('extra_recommend_ratio', 15),
    );
  }

  OrdinaryScoreSettings normalizedMainWeights() {
    final safeClassroom = math.max(0, classroomWeight);
    final safeQuiz = math.max(0, quizWeight);
    final safeExtra = math.max(0, extraWeight);
    final sum = safeClassroom + safeQuiz + safeExtra;
    if (sum <= 0) return OrdinaryScoreSettings.defaults(courseId);
    final factor = 100 / sum;
    return copyWith(
      classroomWeight: safeClassroom * factor,
      quizWeight: safeQuiz * factor,
      extraWeight: safeExtra * factor,
    );
  }

  OrdinaryScoreSettings copyWith({
    String? courseId,
    double? classroomWeight,
    double? quizWeight,
    double? extraWeight,
    double? classroomPointsRatio,
    double? classroomCheckinRatio,
    double? classroomAnswerRatio,
    double? quizAverageRatio,
    double? quizCompletionRatio,
    double? extraCoursewareRatio,
    double? extraAiRatio,
    double? extraExtendedRatio,
    double? extraRecommendRatio,
  }) {
    return OrdinaryScoreSettings(
      courseId: courseId ?? this.courseId,
      classroomWeight: classroomWeight ?? this.classroomWeight,
      quizWeight: quizWeight ?? this.quizWeight,
      extraWeight: extraWeight ?? this.extraWeight,
      classroomPointsRatio: classroomPointsRatio ?? this.classroomPointsRatio,
      classroomCheckinRatio:
          classroomCheckinRatio ?? this.classroomCheckinRatio,
      classroomAnswerRatio: classroomAnswerRatio ?? this.classroomAnswerRatio,
      quizAverageRatio: quizAverageRatio ?? this.quizAverageRatio,
      quizCompletionRatio: quizCompletionRatio ?? this.quizCompletionRatio,
      extraCoursewareRatio: extraCoursewareRatio ?? this.extraCoursewareRatio,
      extraAiRatio: extraAiRatio ?? this.extraAiRatio,
      extraExtendedRatio: extraExtendedRatio ?? this.extraExtendedRatio,
      extraRecommendRatio: extraRecommendRatio ?? this.extraRecommendRatio,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'course_id': courseId,
      'classroom_weight': classroomWeight,
      'quiz_weight': quizWeight,
      'extra_weight': extraWeight,
      'classroom_points_ratio': classroomPointsRatio,
      'classroom_checkin_ratio': classroomCheckinRatio,
      'classroom_answer_ratio': classroomAnswerRatio,
      'quiz_average_ratio': quizAverageRatio,
      'quiz_completion_ratio': quizCompletionRatio,
      'extra_courseware_ratio': extraCoursewareRatio,
      'extra_ai_ratio': extraAiRatio,
      'extra_extended_ratio': extraExtendedRatio,
      'extra_recommend_ratio': extraRecommendRatio,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class OrdinaryScoreSnapshot {
  final String courseId;
  final String courseName;
  final OrdinaryScoreSettings settings;
  final List<OrdinaryStudentScore> rows;
  final DateTime generatedAt;

  const OrdinaryScoreSnapshot({
    required this.courseId,
    required this.courseName,
    required this.settings,
    required this.rows,
    required this.generatedAt,
  });

  int get studentCount => rows.length;

  double get averageClassroomScore =>
      _avg(rows.map((row) => row.classroomScore));

  double get averageQuizScore => _avg(rows.map((row) => row.quizScore));

  double get averageExtraScore => _avg(rows.map((row) => row.extraScore));

  double get averageTotalScore => _avg(rows.map((row) => row.totalScore));

  static double _avg(Iterable<double> values) {
    var count = 0;
    var sum = 0.0;
    for (final value in values) {
      count++;
      sum += value;
    }
    return count == 0 ? 0 : sum / count;
  }
}

class OrdinaryStudentScore {
  final String studentId;
  final String studentName;
  final double classroomPercent;
  final double quizPercent;
  final double extraPercent;
  final double classroomScore;
  final double quizScore;
  final double extraScore;
  final OrdinaryScoreMetrics metrics;

  const OrdinaryStudentScore({
    required this.studentId,
    required this.studentName,
    required this.classroomPercent,
    required this.quizPercent,
    required this.extraPercent,
    required this.classroomScore,
    required this.quizScore,
    required this.extraScore,
    required this.metrics,
  });

  double get totalScore => classroomScore + quizScore + extraScore;

  Map<String, dynamic> toPingshiComponentRow() {
    return {
      'student_id': studentId,
      'student_name': studentName,
      'class_activity_score': classroomPercent,
      'quiz_homework_score': quizPercent,
      'extra_learning_score': extraPercent,
    };
  }
}

class OrdinaryScoreMetrics {
  final double earnedClassroomPoints;
  final int rollCallCount;
  final int rollCallCorrectCount;
  final int checkinCount;
  final int answerCount;
  final double quizAverage;
  final double quizBest;
  final int quizAttempts;
  final int coursewareRecords;
  final double coursewareMinutes;
  final int extendedRecords;
  final int recommendRecords;
  final int recommendFavorites;
  final int aiRequests;
  final int aiTokens;
  final int aiActiveDays;

  const OrdinaryScoreMetrics({
    required this.earnedClassroomPoints,
    required this.rollCallCount,
    required this.rollCallCorrectCount,
    required this.checkinCount,
    required this.answerCount,
    required this.quizAverage,
    required this.quizBest,
    required this.quizAttempts,
    required this.coursewareRecords,
    required this.coursewareMinutes,
    required this.extendedRecords,
    required this.recommendRecords,
    required this.recommendFavorites,
    required this.aiRequests,
    required this.aiTokens,
    required this.aiActiveDays,
  });
}

class _ClassroomMetrics {
  final double earnedPoints;
  final int callCount;
  final int correctCount;
  final int checkinCount;
  final double checkinCredit;
  final int answerCount;

  const _ClassroomMetrics({
    this.earnedPoints = 0,
    this.callCount = 0,
    this.correctCount = 0,
    this.checkinCount = 0,
    this.checkinCredit = 0,
    this.answerCount = 0,
  });

  _ClassroomMetrics copyWith({
    double? earnedPoints,
    int? callCount,
    int? correctCount,
    int? checkinCount,
    double? checkinCredit,
    int? answerCount,
  }) {
    return _ClassroomMetrics(
      earnedPoints: earnedPoints ?? this.earnedPoints,
      callCount: callCount ?? this.callCount,
      correctCount: correctCount ?? this.correctCount,
      checkinCount: checkinCount ?? this.checkinCount,
      checkinCredit: checkinCredit ?? this.checkinCredit,
      answerCount: answerCount ?? this.answerCount,
    );
  }
}

class _QuizMetrics {
  final double averageScore;
  final double bestScore;
  final int attemptCount;

  const _QuizMetrics({
    this.averageScore = 0,
    this.bestScore = 0,
    this.attemptCount = 0,
  });
}

class _LearningMetrics {
  final int coursewareRecords;
  final double coursewareMinutes;
  final double coursewareValue;
  final int extendedRecords;
  final double extendedValue;
  final int recommendRecords;
  final double recommendValue;

  const _LearningMetrics({
    this.coursewareRecords = 0,
    this.coursewareMinutes = 0,
    this.coursewareValue = 0,
    this.extendedRecords = 0,
    this.extendedValue = 0,
    this.recommendRecords = 0,
    this.recommendValue = 0,
  });

  _LearningMetrics copyWith({
    int? coursewareRecords,
    double? coursewareMinutes,
    double? coursewareValue,
    int? extendedRecords,
    double? extendedValue,
    int? recommendRecords,
    double? recommendValue,
  }) {
    return _LearningMetrics(
      coursewareRecords: coursewareRecords ?? this.coursewareRecords,
      coursewareMinutes: coursewareMinutes ?? this.coursewareMinutes,
      coursewareValue: coursewareValue ?? this.coursewareValue,
      extendedRecords: extendedRecords ?? this.extendedRecords,
      extendedValue: extendedValue ?? this.extendedValue,
      recommendRecords: recommendRecords ?? this.recommendRecords,
      recommendValue: recommendValue ?? this.recommendValue,
    );
  }
}

class _AiMetrics {
  final int requestCount;
  final int totalTokens;
  final int activeDays;

  const _AiMetrics({
    this.requestCount = 0,
    this.totalTokens = 0,
    this.activeDays = 0,
  });

  double get activityValue =>
      requestCount + activeDays * 0.5 + totalTokens / 2000;
}

class _RecommendMetrics {
  final int favoriteCount;

  const _RecommendMetrics({this.favoriteCount = 0});
}
