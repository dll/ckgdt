import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import '../models/question_model.dart';
import '../models/quiz_result_model.dart';
import 'database_helper.dart';

class QuizDao {
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
    try {
      final db = await _dbHelper.database;
      debugPrint('=== QuizDao: Getting chapters');
      final maps = await db.rawQuery(
        'SELECT DISTINCT source FROM questions WHERE source IS NOT NULL AND source != "" ORDER BY source',
      );
      debugPrint('=== QuizDao: Got ${maps.length} chapters');
      if (maps.isNotEmpty) {
        debugPrint('=== QuizDao: First chapter record: ${maps.first}');
      }
      return maps.map((map) => map['source'] as String).toList();
    } catch (e) {
      debugPrint('=== QuizDao: Error getting chapters: $e');
      return [];
    }
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
}
