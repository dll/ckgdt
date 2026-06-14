import '../../services/course_context_service.dart';
import 'database_helper.dart';

class FavoriteDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  Future<int> addFavorite({
    required String userId,
    required String nodeId,
    required String nodeTitle,
  }) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ? AND node_id = ?',
      extraArgs: [userId, nodeId],
    );

    // 检查是否已存在
    final existing = await db.query(
      'favorites',
      where: scope.where,
      whereArgs: scope.args,
    );

    if (existing.isNotEmpty) {
      return (existing.first['id'] as int?) ?? 0;
    }

    return await db.insert('favorites', {
      'course_id': await _courseContext.activeCourseId(),
      'user_id': userId,
      'node_id': nodeId,
      'node_title': nodeTitle,
      'favorite_time': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getFavorites(String userId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ?',
      extraArgs: [userId],
    );
    return await db.query(
      'favorites',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'favorite_time DESC',
    );
  }

  Future<bool> isFavorite(String userId, String nodeId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ? AND node_id = ?',
      extraArgs: [userId, nodeId],
    );
    final result = await db.query(
      'favorites',
      where: scope.where,
      whereArgs: scope.args,
    );
    return result.isNotEmpty;
  }

  Future<void> removeFavorite(String userId, String nodeId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ? AND node_id = ?',
      extraArgs: [userId, nodeId],
    );
    await db.delete(
      'favorites',
      where: scope.where,
      whereArgs: scope.args,
    );
  }

  Future<int> getFavoriteCount(String userId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'user_id = ?',
      extraArgs: [userId],
    );
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM favorites WHERE ${scope.where}',
      scope.args,
    );
    return (result.first['count'] as int?) ?? 0;
  }
}
