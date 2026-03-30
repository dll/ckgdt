import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class FavoriteDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> addFavorite({
    required String userId,
    required String nodeId,
    required String nodeTitle,
  }) async {
    final db = await _dbHelper.database;
    
    // 检查是否已存在
    final existing = await db.query(
      'favorites',
      where: 'user_id = ? AND node_id = ?',
      whereArgs: [userId, nodeId],
    );
    
    if (existing.isNotEmpty) {
      return (existing.first['id'] as int?) ?? 0;
    }
    
    return await db.insert('favorites', {
      'user_id': userId,
      'node_id': nodeId,
      'node_title': nodeTitle,
      'favorite_time': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getFavorites(String userId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'favorites',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'favorite_time DESC',
    );
  }

  Future<bool> isFavorite(String userId, String nodeId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'favorites',
      where: 'user_id = ? AND node_id = ?',
      whereArgs: [userId, nodeId],
    );
    return result.isNotEmpty;
  }

  Future<void> removeFavorite(String userId, String nodeId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'favorites',
      where: 'user_id = ? AND node_id = ?',
      whereArgs: [userId, nodeId],
    );
  }

  Future<int> getFavoriteCount(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM favorites WHERE user_id = ?',
      [userId],
    );
    return (result.first['count'] as int?) ?? 0;
  }
}
