import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class LearningRecordDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

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

  Future<void> deleteRecord(int id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'learning_records',
      where: 'id = ?',
      whereArgs: [id],
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
