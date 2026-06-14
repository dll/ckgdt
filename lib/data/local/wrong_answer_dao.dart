import '../../services/course_context_service.dart';
import 'database_helper.dart';

class WrongAnswerDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  Future<int> addWrongAnswer({
    required String userId,
    required int questionId,
    required String question,
    required String userAnswer,
    required String correctAnswer,
    required String chapter,
  }) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ? AND question_id = ?',
      extraArgs: [userId, questionId],
    );

    // 检查是否已存在
    final existing = await db.query(
      'wrong_answers',
      where: scope.where,
      whereArgs: scope.args,
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
        where: scope.where,
        whereArgs: scope.args,
      );
      return (existing.first['id'] as int?) ?? 0;
    }

    return await db.insert('wrong_answers', {
      'course_id': await _courseContext.activeCourseId(),
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
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ?',
      extraArgs: [userId],
    );
    return await db.query(
      'wrong_answers',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'wrong_time DESC',
    );
  }

  Future<int> getWrongCount(String userId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ?',
      extraArgs: [userId],
    );
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM wrong_answers WHERE ${scope.where}',
      scope.args,
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> removeWrongAnswer(int id, String userId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'id = ? AND user_id = ?',
      extraArgs: [id, userId],
    );
    await db.delete(
      'wrong_answers',
      where: scope.where,
      whereArgs: scope.args,
    );
  }

  Future<void> clearWrongAnswers(String userId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ?',
      extraArgs: [userId],
    );
    await db.delete(
      'wrong_answers',
      where: scope.where,
      whereArgs: scope.args,
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
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ? AND (explanation IS NULL OR explanation = ?)',
      extraArgs: [userId, ''],
    );
    return await db.query(
      'wrong_answers',
      where: scope.where,
      whereArgs: scope.args,
    );
  }
}
