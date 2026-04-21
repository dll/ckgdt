import 'database_helper.dart';

class WrongAnswerDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> addWrongAnswer({
    required String userId,
    required int questionId,
    required String question,
    required String userAnswer,
    required String correctAnswer,
    required String chapter,
  }) async {
    final db = await _dbHelper.database;
    
    // 检查是否已存在
    final existing = await db.query(
      'wrong_answers',
      where: 'user_id = ? AND question_id = ?',
      whereArgs: [userId, questionId],
    );
    
    if (existing.isNotEmpty) {
      // 更新
      final currentTimes = (existing.first['times'] as int?) ?? 1;
      await db.update(
        'wrong_answers',
        {
          'user_answer': userAnswer,
          'times': currentTimes + 1,
          'last_wrong_time': DateTime.now().toIso8601String(),
        },
        where: 'user_id = ? AND question_id = ?',
        whereArgs: [userId, questionId],
      );
      return (existing.first['id'] as int?) ?? 0;
    }
    
    return await db.insert('wrong_answers', {
      'user_id': userId,
      'question_id': questionId,
      'question': question,
      'user_answer': userAnswer,
      'correct_answer': correctAnswer,
      'chapter': chapter,
      'times': 1,
      'wrong_time': DateTime.now().toIso8601String(),
      'last_wrong_time': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getWrongAnswers(String userId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'wrong_answers',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'wrong_time DESC',
    );
  }

  Future<int> getWrongCount(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM wrong_answers WHERE user_id = ?',
      [userId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> removeWrongAnswer(int id, String userId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'wrong_answers',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<void> clearWrongAnswers(String userId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'wrong_answers',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// 更新错题的 AI 解释
  Future<void> updateExplanation(int id, String explanation) async {
    final db = await _dbHelper.database;
    await db.update(
      'wrong_answers',
      {'explanation': explanation},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取没有解释的错题列表
  Future<List<Map<String, dynamic>>> getWrongAnswersWithoutExplanation(
      String userId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'wrong_answers',
      where: 'user_id = ? AND (explanation IS NULL OR explanation = ?)',
      whereArgs: [userId, ''],
    );
  }
}
