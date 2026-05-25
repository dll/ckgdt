import 'package:sqflite/sqflite.dart';
import '../../core/init_logger.dart';
import '../models/question_model.dart';
import '../models/quiz_result_model.dart';
import 'database_helper.dart';

class QuizDao {
  static const _tag = 'quiz_dao';
  static const _maxAttempts = 3;
  static const _retryBackoff = Duration(milliseconds: 100);

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<QuestionModel>> getAllQuestions() async {
    final db = await _dbHelper.database;
    final maps = await db.query('questions');
    return maps.map((map) => QuestionModel.fromMap(map)).toList();
  }

  Future<List<QuestionModel>> getQuestionsByChapter(String chapter) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'questions',
      where: 'source = ?',
      whereArgs: [chapter],
    );
    return maps.map((map) => QuestionModel.fromMap(map)).toList();
  }

  Future<List<String>> getChapters() async {
    // 失败抛出（曾经吞错导致 UI 显示"暂无题目"误导排查）。
    // sqflite singleInstance 在多进程偶发瞬时锁，遇 BUSY/locked 才退避重试。
    final db = await _dbHelper.database;
    Object? lastError;
    StackTrace? lastSt;
    for (int attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        final maps = await db.rawQuery(
          // SQL 标准：双引号是标识符，空字符串必须用单引号。
          // sqflite_common_ffi (桌面/Web) 严格按标准；Android 原生 sqflite 容忍 ""。
          "SELECT DISTINCT source FROM questions WHERE source IS NOT NULL AND source != '' ORDER BY source",
        );
        if (attempt > 0) {
          InitLogger.log(_tag,
              'getChapters succeeded after $attempt retries (${maps.length} rows)');
        }
        return maps.map((map) => map['source'] as String).toList();
      } catch (e, st) {
        if (!_isTransient(e)) {
          InitLogger.error(_tag, 'getChapters non-transient: $e', st);
          rethrow;
        }
        lastError = e;
        lastSt = st;
        InitLogger.log(_tag,
            'getChapters attempt ${attempt + 1} BUSY: $e — retrying after ${_retryBackoff.inMilliseconds}ms');
        await Future<void>.delayed(_retryBackoff);
      }
    }
    InitLogger.error(
        _tag, 'getChapters all $_maxAttempts attempts failed: $lastError', lastSt);
    throw lastError ?? StateError('getChapters: unreachable');
  }

  /// 仅 SQLite BUSY/LOCKED 算瞬时；语法/schema 错误不重试，立即抛出。
  /// sqflite_common 2.5.x 没有 isDatabaseBusyError，只能按 message 匹配。
  static bool _isTransient(Object e) {
    if (e is! DatabaseException) return false;
    final msg = e.toString().toLowerCase();
    return msg.contains('locked') || msg.contains('busy');
  }

  Future<int> saveQuizResult(QuizResultModel result) async {
    final db = await _dbHelper.database;
    return await db.insert('quiz_results', result.toMap());
  }

  Future<List<QuizResultModel>> getQuizResults(String userId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'quiz_results',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'quiz_timestamp DESC',
    );
    return maps.map((map) => QuizResultModel.fromMap(map)).toList();
  }

  Future<List<QuizResultModel>> getAllQuizResults() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'quiz_results',
      orderBy: 'quiz_timestamp DESC',
    );
    return maps.map((map) => QuizResultModel.fromMap(map)).toList();
  }

  Future<Map<String, dynamic>> getQuizSummary(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as total_count,
        SUM(num_correct) as total_correct,
        SUM(num_total) as total_questions,
        AVG(score) as avg_score
      FROM quiz_results
      WHERE user_id = ?
    ''', [userId]);

    if (result.isNotEmpty) {
      return result.first;
    }
    return {};
  }

  // ══════════════════════════════════════════════════════════
  //  题库管理 CRUD（教师/管理员用）
  // ══════════════════════════════════════════════════════════

  /// 添加题目
  Future<int> addQuestion(QuestionModel question) async {
    final db = await _dbHelper.database;
    return db.insert('questions', question.toMap());
  }

  /// 更新题目
  Future<int> updateQuestion(int id, QuestionModel question) async {
    final db = await _dbHelper.database;
    return db.update('questions', question.toMap(),
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除题目
  Future<int> deleteQuestion(int id) async {
    final db = await _dbHelper.database;
    return db.delete('questions', where: 'id = ?', whereArgs: [id]);
  }

  /// 按章节统计题目数量
  Future<List<Map<String, dynamic>>> getChapterStats() async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT source, COUNT(*) as count
      FROM questions
      WHERE source IS NOT NULL AND source != ''
      GROUP BY source
      ORDER BY source
    ''');
  }

  /// 获取题目总数
  Future<int> getQuestionCount() async {
    final db = await _dbHelper.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as c FROM questions');
    return (result.first['c'] as int?) ?? 0;
  }

  /// 批量删除题目
  Future<int> deleteQuestionsByChapter(String chapter) async {
    final db = await _dbHelper.database;
    return db.delete('questions',
        where: 'source = ?', whereArgs: [chapter]);
  }

  // ══════════════════════════════════════════════════════════
  //  教师分析方法
  // ══════════════════════════════════════════════════════════

  /// 获取全班测验概览统计
  Future<Map<String, dynamic>> getClassQuizOverview() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT user_id) as student_count,
        COUNT(*) as total_attempts,
        AVG(score) as avg_score,
        CASE WHEN COUNT(*) > 0
          THEN SUM(CASE WHEN score >= 60 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
          ELSE 0 END as pass_rate
      FROM quiz_results
    ''');
    if (result.isNotEmpty) return Map<String, dynamic>.from(result.first);
    return {
      'student_count': 0,
      'total_attempts': 0,
      'avg_score': 0.0,
      'pass_rate': 0.0,
    };
  }

  /// 获取各章节测验统计（教师用）
  Future<List<Map<String, dynamic>>> getChapterQuizPerformance() async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT chapter,
             COUNT(*) as attempt_count,
             COUNT(DISTINCT user_id) as student_count,
             AVG(score) as avg_score,
             CASE WHEN COUNT(*) > 0
               THEN SUM(CASE WHEN score >= 60 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
               ELSE 0 END as pass_rate,
             MAX(score) as max_score,
             MIN(score) as min_score
      FROM quiz_results
      WHERE chapter IS NOT NULL AND chapter != ''
      GROUP BY chapter
      ORDER BY chapter
    ''');
  }

  /// 获取最近的测验记录（全班，教师用）
  Future<List<Map<String, dynamic>>> getRecentAllResults({int limit = 20}) async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT qr.*, u.real_name
      FROM quiz_results qr
      LEFT JOIN users u ON qr.user_id = u.user_id
      ORDER BY qr.quiz_timestamp DESC
      LIMIT ?
    ''', [limit]);
  }
}
