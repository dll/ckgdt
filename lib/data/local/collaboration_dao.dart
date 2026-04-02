import 'database_helper.dart';

/// 协作讨论 DAO — 管理讨论消息和互评数据
class CollaborationDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 确保协作相关表存在（首次调用时自动创建）
  Future<void> ensureTables() async {
    final db = await _dbHelper.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS collaboration_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER,
        group_id INTEGER,
        sender_id TEXT NOT NULL,
        sender_name TEXT,
        message TEXT NOT NULL,
        message_type TEXT DEFAULT 'text',
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS peer_reviews(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER,
        reviewer_id TEXT NOT NULL,
        reviewer_name TEXT,
        reviewee_id TEXT NOT NULL,
        reviewee_name TEXT,
        score INTEGER DEFAULT 0,
        comment TEXT,
        created_at TEXT,
        UNIQUE(task_id, reviewer_id, reviewee_id)
      )
    ''');
  }

  // ── 讨论消息 ───────────────────────────────────────────────

  /// 发送消息
  Future<int> sendMessage({
    int? taskId,
    int? groupId,
    required String senderId,
    required String senderName,
    required String message,
    String messageType = 'text',
  }) async {
    final db = await _dbHelper.database;
    return await db.insert('collaboration_messages', {
      'task_id': taskId,
      'group_id': groupId,
      'sender_id': senderId,
      'sender_name': senderName,
      'message': message,
      'message_type': messageType,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取讨论消息列表
  Future<List<Map<String, dynamic>>> getMessages({
    int? taskId,
    int? groupId,
    int limit = 100,
  }) async {
    final db = await _dbHelper.database;

    String where = '1=1';
    final args = <dynamic>[];

    if (taskId != null) {
      where += ' AND task_id = ?';
      args.add(taskId);
    }
    if (groupId != null) {
      where += ' AND group_id = ?';
      args.add(groupId);
    }

    return await db.query(
      'collaboration_messages',
      where: where,
      whereArgs: args,
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  /// 删除消息
  Future<void> deleteMessage(int id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'collaboration_messages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 清空讨论区消息
  Future<void> clearMessages({int? taskId, int? groupId}) async {
    final db = await _dbHelper.database;
    String where = '1=1';
    final args = <dynamic>[];
    if (taskId != null) {
      where += ' AND task_id = ?';
      args.add(taskId);
    }
    if (groupId != null) {
      where += ' AND group_id = ?';
      args.add(groupId);
    }
    await db.delete('collaboration_messages', where: where, whereArgs: args);
  }

  // ── 互评 ───────────────────────────────────────────────────

  /// 提交互评
  Future<int> addPeerReview({
    int? taskId,
    required String reviewerId,
    required String reviewerName,
    required String revieweeId,
    required String revieweeName,
    required int score,
    String? comment,
  }) async {
    final db = await _dbHelper.database;

    // 先检查是否已评过（同一任务、同一评审人、同一被评人）
    final existing = await db.query(
      'peer_reviews',
      where: 'task_id = ? AND reviewer_id = ? AND reviewee_id = ?',
      whereArgs: [taskId, reviewerId, revieweeId],
    );

    if (existing.isNotEmpty) {
      // 更新已有评分
      await db.update(
        'peer_reviews',
        {
          'score': score,
          'comment': comment,
          'created_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return (existing.first['id'] as int?) ?? 0;
    }

    return await db.insert('peer_reviews', {
      'task_id': taskId,
      'reviewer_id': reviewerId,
      'reviewer_name': reviewerName,
      'reviewee_id': revieweeId,
      'reviewee_name': revieweeName,
      'score': score,
      'comment': comment,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取某任务的所有互评
  Future<List<Map<String, dynamic>>> getPeerReviews({int? taskId}) async {
    final db = await _dbHelper.database;
    if (taskId != null) {
      return await db.query(
        'peer_reviews',
        where: 'task_id = ?',
        whereArgs: [taskId],
        orderBy: 'created_at DESC',
      );
    }
    return await db.query('peer_reviews', orderBy: 'created_at DESC');
  }

  /// 获取某用户收到的互评
  Future<List<Map<String, dynamic>>> getReviewsForUser({
    int? taskId,
    required String userId,
  }) async {
    final db = await _dbHelper.database;
    String where = 'reviewee_id = ?';
    final args = <dynamic>[userId];
    if (taskId != null) {
      where += ' AND task_id = ?';
      args.add(taskId);
    }
    return await db.query(
      'peer_reviews',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
  }

  /// 获取某用户给出的互评
  Future<List<Map<String, dynamic>>> getReviewsByUser({
    int? taskId,
    required String userId,
  }) async {
    final db = await _dbHelper.database;
    String where = 'reviewer_id = ?';
    final args = <dynamic>[userId];
    if (taskId != null) {
      where += ' AND task_id = ?';
      args.add(taskId);
    }
    return await db.query(
      'peer_reviews',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
  }

  /// 删除互评
  Future<void> deletePeerReview(int id) async {
    final db = await _dbHelper.database;
    await db.delete('peer_reviews', where: 'id = ?', whereArgs: [id]);
  }
}
