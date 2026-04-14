import 'database_helper.dart';

/// 课堂管理 DAO — 在线状态 / 签到管理 / 课堂互动
class ClassroomDao {
  // ══════════════════════════════════════════════════════════════════════════
  //  表结构保障（懒迁移，WorksDao 模式）
  // ══════════════════════════════════════════════════════════════════════════

  bool _tableEnsured = false;

  Future<void> _ensureTable() async {
    if (_tableEnsured) return;
    final db = await DatabaseHelper.instance.database;

    // 1) users 表补 last_active 列
    try {
      await db.execute('ALTER TABLE users ADD COLUMN last_active TEXT');
    } catch (_) {}

    // 2) 签到会话表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checkin_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        title TEXT,
        started_at TEXT,
        ended_at TEXT,
        late_minutes INTEGER DEFAULT 10,
        status TEXT DEFAULT 'active',
        created_by TEXT
      )
    ''');

    // 3) 签到记录表
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

    // 4) 课堂消息表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS classroom_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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

    _tableEnsured = true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  在线状态
  // ══════════════════════════════════════════════════════════════════════════

  /// 更新用户心跳时间戳
  Future<void> updateLastActive(String userId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    try {
      await db.update(
        'users',
        {'last_active': DateTime.now().toIso8601String()},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    } catch (_) {}
  }

  /// 获取所有学生及其在线状态
  Future<List<Map<String, dynamic>>> getStudentsWithStatus({
    int? classId,
    int onlineThresholdMinutes = 5,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;

    List<Map<String, dynamic>> students;
    if (classId != null) {
      students = await db.rawQuery('''
        SELECT u.user_id, u.real_name, u.role, u.last_login, u.last_active,
               u.is_active, u.repository_url
        FROM users u
        INNER JOIN class_members cm ON cm.user_id = u.user_id
        WHERE cm.class_id = ? AND u.role = 'student' AND u.is_active = 1
        ORDER BY u.real_name
      ''', [classId]);
    } else {
      students = await db.query(
        'users',
        where: "role = 'student' AND is_active = 1",
        orderBy: 'real_name',
      );
    }

    final now = DateTime.now();
    return students.map((s) {
      final m = Map<String, dynamic>.from(s);
      final lastActive = m['last_active'] as String?;
      bool isOnline = false;
      if (lastActive != null && lastActive.isNotEmpty) {
        try {
          final dt = DateTime.parse(lastActive);
          isOnline = now.difference(dt).inMinutes < onlineThresholdMinutes;
        } catch (_) {}
      }
      m['is_online'] = isOnline ? 1 : 0;
      return m;
    }).toList();
  }

  /// 获取在线统计
  Future<Map<String, int>> getOnlineStats({
    int? classId,
    int onlineThresholdMinutes = 5,
  }) async {
    final students = await getStudentsWithStatus(
      classId: classId,
      onlineThresholdMinutes: onlineThresholdMinutes,
    );
    final total = students.length;
    final online = students.where((s) => s['is_online'] == 1).length;
    return {'total': total, 'online': online, 'offline': total - online};
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  签到管理
  // ══════════════════════════════════════════════════════════════════════════

  /// 创建签到会话，自动为所有学生生成 absent 记录
  Future<int> createCheckinSession({
    int? classId,
    required String title,
    required String createdBy,
    int lateMinutes = 10,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    final sessionId = await db.insert('checkin_sessions', {
      'class_id': classId,
      'title': title,
      'started_at': now,
      'late_minutes': lateMinutes,
      'status': 'active',
      'created_by': createdBy,
    });

    // 获取学生列表
    List<Map<String, dynamic>> students;
    if (classId != null) {
      students = await db.rawQuery('''
        SELECT u.user_id, u.real_name FROM users u
        INNER JOIN class_members cm ON cm.user_id = u.user_id
        WHERE cm.class_id = ? AND u.role = 'student' AND u.is_active = 1
      ''', [classId]);
    } else {
      students = await db.query('users',
          where: "role = 'student' AND is_active = 1");
    }

    // 批量插入签到记录
    final batch = db.batch();
    for (final s in students) {
      batch.insert('checkin_records', {
        'session_id': sessionId,
        'user_id': s['user_id'],
        'user_name': s['real_name'] ?? s['user_id'],
        'status': 'absent',
      });
    }
    await batch.commit(noResult: true);

    return sessionId;
  }

  /// 结束签到会话
  Future<void> endCheckinSession(int sessionId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'checkin_sessions',
      {'status': 'ended', 'ended_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 获取活跃的签到会话
  Future<Map<String, dynamic>?> getActiveSession({int? classId}) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final where = classId != null
        ? "status = 'active' AND class_id = ?"
        : "status = 'active'";
    final args = classId != null ? [classId] : null;
    final results = await db.query('checkin_sessions',
        where: where, whereArgs: args, orderBy: 'id DESC', limit: 1);
    return results.isNotEmpty ? Map<String, dynamic>.from(results.first) : null;
  }

  /// 获取签到会话列表（历史）
  Future<List<Map<String, dynamic>>> getCheckinSessions({
    int? classId,
    int limit = 20,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final where = classId != null ? 'class_id = ?' : null;
    final args = classId != null ? [classId] : null;
    return await db.query('checkin_sessions',
        where: where, whereArgs: args, orderBy: 'id DESC', limit: limit);
  }

  /// 获取某次签到的所有记录
  Future<List<Map<String, dynamic>>> getCheckinRecords(int sessionId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    return await db.query('checkin_records',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'user_name');
  }

  /// 教师手动标记学生签到状态
  Future<void> markCheckin({
    required int sessionId,
    required String userId,
    required String status,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final now = status == 'absent' ? null : DateTime.now().toIso8601String();
    await db.update(
      'checkin_records',
      {'status': status, 'checked_at': now},
      where: 'session_id = ? AND user_id = ?',
      whereArgs: [sessionId, userId],
    );
  }

  /// 批量标记全部签到
  Future<void> markAllPresent(int sessionId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'checkin_records',
      {'status': 'present', 'checked_at': now},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 获取签到统计
  Future<Map<String, int>> getCheckinStats(int sessionId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final records = await db.query('checkin_records',
        where: 'session_id = ?', whereArgs: [sessionId]);
    final total = records.length;
    final present = records.where((r) => r['status'] == 'present').length;
    final late_ = records.where((r) => r['status'] == 'late').length;
    final absent = records.where((r) => r['status'] == 'absent').length;
    return {
      'total': total,
      'present': present,
      'late': late_,
      'absent': absent,
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  课堂互动（公告/提问/回答）
  // ══════════════════════════════════════════════════════════════════════════

  /// 发送消息
  Future<int> sendMessage({
    int? classId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String content,
    String messageType = 'announcement',
    int? parentId,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    return await db.insert('classroom_messages', {
      'class_id': classId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'content': content,
      'message_type': messageType,
      'parent_id': parentId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取消息列表
  Future<List<Map<String, dynamic>>> getMessages({
    int? classId,
    String? messageType,
    int limit = 50,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final conditions = <String>[];
    final args = <dynamic>[];
    if (classId != null) {
      conditions.add('class_id = ?');
      args.add(classId);
    }
    if (messageType != null && messageType.isNotEmpty) {
      conditions.add('message_type = ?');
      args.add(messageType);
    }
    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;
    return await db.query('classroom_messages',
        where: where,
        whereArgs: args.isNotEmpty ? args : null,
        orderBy: 'created_at DESC',
        limit: limit);
  }

  /// 删除消息
  Future<void> deleteMessage(int messageId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    // 同时删除子回复
    await db.delete('classroom_messages',
        where: 'parent_id = ?', whereArgs: [messageId]);
    await db.delete('classroom_messages',
        where: 'id = ?', whereArgs: [messageId]);
  }

  /// 获取消息统计
  Future<Map<String, int>> getMessageStats({int? classId}) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final classWhere = classId != null ? ' AND class_id = $classId' : '';
    final ann = await db.rawQuery(
        "SELECT COUNT(*) as c FROM classroom_messages WHERE message_type='announcement'$classWhere");
    final que = await db.rawQuery(
        "SELECT COUNT(*) as c FROM classroom_messages WHERE message_type='question'$classWhere");
    final ans = await db.rawQuery(
        "SELECT COUNT(*) as c FROM classroom_messages WHERE message_type='answer'$classWhere");
    return {
      'announcement': (ann.first['c'] as int?) ?? 0,
      'question': (que.first['c'] as int?) ?? 0,
      'answer': (ans.first['c'] as int?) ?? 0,
    };
  }

}
