import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

/// 问题反馈 DAO
class FeedbackDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  bool _tableEnsured = false;

  Future<void> _ensureTable() async {
    if (_tableEnsured) return;
    final db = await _dbHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feedback(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        user_name TEXT,
        user_role TEXT,
        page_name TEXT,
        content TEXT NOT NULL,
        suggestion TEXT,
        screenshot_path TEXT,
        screenshot_data TEXT,
        status TEXT DEFAULT 'pending',
        admin_reply TEXT,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
    // 确保 screenshot_data 列存在（兼容旧表）
    try {
      await db.execute('ALTER TABLE feedback ADD COLUMN screenshot_data TEXT');
    } catch (e) { swallowDebug(e, tag: 'feedback_dao'); }
    _tableEnsured = true;
  }

  /// 提交反馈
  Future<int> addFeedback({
    required String userId,
    String? userName,
    String? userRole,
    String? pageName,
    required String content,
    String? suggestion,
    String? screenshotPath,
    String? screenshotData,
  }) async {
    await _ensureTable();
    final db = await _dbHelper.database;
    final id = await db.insert('feedback', {
      'user_id': userId,
      'user_name': userName,
      'user_role': userRole,
      'page_name': pageName,
      'content': content,
      'suggestion': suggestion,
      'screenshot_path': screenshotPath,
      'screenshot_data': screenshotData,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
    debugPrint('FeedbackDao: 反馈已提交 id=$id');
    return id;
  }

  /// 获取所有反馈（管理员用），按时间倒序
  Future<List<Map<String, dynamic>>> getAllFeedback({
    String? status,
    int limit = 100,
  }) async {
    await _ensureTable();
    final db = await _dbHelper.database;
    final where = status != null ? 'status = ?' : null;
    final args = status != null ? [status] : null;
    return await db.query(
      'feedback',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// 获取指定用户的反馈
  Future<List<Map<String, dynamic>>> getUserFeedback(String userId) async {
    await _ensureTable();
    final db = await _dbHelper.database;
    return await db.query(
      'feedback',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  /// 获取反馈统计
  Future<Map<String, int>> getStats() async {
    await _ensureTable();
    final db = await _dbHelper.database;
    final total = await db.rawQuery(
        'SELECT COUNT(*) as c FROM feedback');
    final pending = await db.rawQuery(
        "SELECT COUNT(*) as c FROM feedback WHERE status = 'pending'");
    final resolved = await db.rawQuery(
        "SELECT COUNT(*) as c FROM feedback WHERE status = 'resolved'");
    return {
      'total': (total.first['c'] as int?) ?? 0,
      'pending': (pending.first['c'] as int?) ?? 0,
      'resolved': (resolved.first['c'] as int?) ?? 0,
    };
  }

  /// 更新反馈状态
  Future<void> updateStatus(int id, String status, {String? reply}) async {
    await _ensureTable();
    final db = await _dbHelper.database;
    final updates = <String, dynamic>{
      'status': status,
    };
    if (reply != null) updates['admin_reply'] = reply;
    if (status == 'resolved') {
      updates['resolved_at'] = DateTime.now().toIso8601String();
    }
    await db.update('feedback', updates, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除反馈
  Future<void> deleteFeedback(int id) async {
    await _ensureTable();
    final db = await _dbHelper.database;
    await db.delete('feedback', where: 'id = ?', whereArgs: [id]);
  }

  /// 清空所有反馈
  Future<void> clearAll() async {
    await _ensureTable();
    final db = await _dbHelper.database;
    await db.delete('feedback');
  }
}
