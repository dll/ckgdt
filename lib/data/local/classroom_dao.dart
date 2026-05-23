import '../../core/error_handler.dart';
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
    } catch (e) {
      // 列已存在 → 静默；这是预期行为
      swallow(e, tag: 'ClassroomDao.migrate.last_active');
    }

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

    // 5) 分层点名会话表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS roll_call_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        created_by TEXT,
        created_at TEXT
      )
    ''');

    // 6) 分层点名记录表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS roll_call_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT,
        difficulty TEXT NOT NULL,
        tier TEXT NOT NULL,
        is_correct INTEGER DEFAULT 0,
        score_delta REAL DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (session_id) REFERENCES roll_call_sessions(id)
      )
    ''');

    // 7) 课堂提问题库
    await db.execute('''
      CREATE TABLE IF NOT EXISTS classroom_questions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_type TEXT NOT NULL DEFAULT 'quiz',
        source_id INTEGER,
        chapter TEXT,
        difficulty TEXT DEFAULT 'medium',
        question TEXT NOT NULL,
        option_a TEXT,
        option_b TEXT,
        option_c TEXT,
        option_d TEXT,
        answer_index INTEGER DEFAULT -1,
        reference_answer TEXT,
        question_type TEXT DEFAULT 'choice',
        created_by TEXT,
        created_at TEXT,
        asked_at TEXT,
        class_id INTEGER
      )
    ''');

    _tableEnsured = true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  在线状态
  // ══════════════════════════════════════════════════════════════════════════

  /// 清除某个用户的在线记录（将 last_active 设为 NULL）
  Future<bool> clearLastActive(String userId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    try {
      final count = await db.update(
        'users',
        {'last_active': null},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      return count > 0;
    } catch (e) {
      swallowDebug(e, tag: 'ClassroomDao.checkin');
      return false;
    }
  }

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
    } catch (e) {
      swallowDebug(e, tag: 'ClassroomDao.touchActive');
    }
  }

  /// 获取所有学生及其在线状态
  Future<List<Map<String, dynamic>>> getStudentsWithStatus({
    int? classId,
    int onlineThresholdMinutes = 10,
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
        } catch (e) {
          swallow(e, tag: 'ClassroomDao.parseLastActive');
        }
      }
      m['is_online'] = isOnline ? 1 : 0;
      return m;
    }).toList();
  }

  /// 获取在线统计
  Future<Map<String, int>> getOnlineStats({
    int? classId,
    int onlineThresholdMinutes = 10,
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

  // ══════════════════════════════════════════════════════════════════════════
  //  分层点名
  // ══════════════════════════════════════════════════════════════════════════

  /// 创建点名会话
  Future<int> createRollCallSession({int? classId, required String createdBy}) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    return await db.insert('roll_call_sessions', {
      'class_id': classId,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 记录一次点名结果
  Future<int> addRollCallRecord({
    required int sessionId,
    required String userId,
    required String userName,
    required String difficulty,
    required String tier,
    required bool isCorrect,
    required double scoreDelta,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    return await db.insert('roll_call_records', {
      'session_id': sessionId,
      'user_id': userId,
      'user_name': userName,
      'difficulty': difficulty,
      'tier': tier,
      'is_correct': isCorrect ? 1 : 0,
      'score_delta': scoreDelta,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取某班级的点名历史（按会话）
  Future<List<Map<String, dynamic>>> getRollCallSessions({int? classId, int limit = 20}) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final classWhere = classId != null ? 'WHERE class_id = ?' : '';
    final args = classId != null ? [classId] : <dynamic>[];
    return await db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM roll_call_records WHERE session_id = s.id) as record_count,
        (SELECT SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) FROM roll_call_records WHERE session_id = s.id) as correct_count
      FROM roll_call_sessions s
      $classWhere
      ORDER BY s.created_at DESC
      LIMIT ?
    ''', [...args, limit]);
  }

  /// 获取某次会话的所有点名记录
  Future<List<Map<String, dynamic>>> getRollCallRecords(int sessionId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    return await db.query('roll_call_records',
        where: 'session_id = ?', whereArgs: [sessionId],
        orderBy: 'created_at ASC');
  }

  /// 获取学生的点名累计得分排行
  Future<List<Map<String, dynamic>>> getRollCallScoreboard({int? classId}) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final classWhere = classId != null
        ? 'WHERE r.session_id IN (SELECT id FROM roll_call_sessions WHERE class_id = ?)'
        : '';
    final args = classId != null ? [classId] : <dynamic>[];
    return await db.rawQuery('''
      SELECT r.user_id, r.user_name,
        SUM(r.score_delta) as total_score,
        COUNT(*) as call_count,
        SUM(CASE WHEN r.is_correct = 1 THEN 1 ELSE 0 END) as correct_count
      FROM roll_call_records r
      $classWhere
      GROUP BY r.user_id
      ORDER BY total_score DESC
    ''', args);
  }

  /// 根据测验成绩对学生分层（优/中/差）
  Future<Map<String, List<Map<String, dynamic>>>> classifyStudentsByPerformance({
    int? classId,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;

    // 获取班级学生
    String studentQuery;
    List<dynamic> args;
    if (classId != null) {
      studentQuery = '''
        SELECT u.user_id, u.real_name
        FROM users u
        INNER JOIN class_members cm ON cm.user_id = u.user_id AND cm.role = 'student'
        WHERE cm.class_id = ? AND u.is_active = 1
        ORDER BY u.user_id
      ''';
      args = [classId];
    } else {
      studentQuery = '''
        SELECT user_id, real_name FROM users
        WHERE role = 'student' AND is_active = 1
        ORDER BY user_id
      ''';
      args = [];
    }
    final students = await db.rawQuery(studentQuery, args);
    if (students.isEmpty) return {'high': [], 'mid': [], 'low': []};

    // 获取每个学生的平均测验分
    final scored = <Map<String, dynamic>>[];
    for (final s in students) {
      final uid = s['user_id'] as String;
      final name = s['real_name'] as String? ?? uid;
      final result = await db.rawQuery('''
        SELECT AVG(score) as avg_score, COUNT(*) as quiz_count
        FROM quiz_results WHERE user_id = ?
      ''', [uid]);
      final avgScore = (result.first['avg_score'] as num?)?.toDouble() ?? 0;
      final quizCount = (result.first['quiz_count'] as int?) ?? 0;
      scored.add({
        'user_id': uid,
        'real_name': name,
        'avg_score': avgScore,
        'quiz_count': quizCount,
      });
    }

    // 按平均分排序后三等分
    scored.sort((a, b) => (b['avg_score'] as double).compareTo(a['avg_score'] as double));
    final total = scored.length;
    final third = (total / 3).ceil();
    final high = scored.take(third).toList();
    final low = scored.skip(total - third).toList();
    final mid = scored.skip(third).take(total - 2 * third).toList();

    return {'high': high, 'mid': mid, 'low': low};
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  课堂提问（题库管理）
  // ══════════════════════════════════════════════════════════════════════════

  /// 从测验题库批量导入
  Future<int> importFromQuizBank() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;

    final existing = await db.query('classroom_questions',
        columns: ['source_id'],
        where: "source_type = 'quiz'");
    final existingIds = existing.map((e) => e['source_id'] as int?).toSet();

    final questions = await db.query('questions');
    int imported = 0;
    final batch = db.batch();
    for (final q in questions) {
      final qId = q['id'] as int?;
      if (existingIds.contains(qId)) continue;

      final answerIndex = (q['answer_index'] as int?) ?? 0;
      final options = [
        q['option_a'] as String? ?? '',
        q['option_b'] as String? ?? '',
        q['option_c'] as String? ?? '',
        q['option_d'] as String? ?? '',
      ];
      final letter = String.fromCharCode(65 + answerIndex.clamp(0, 3));
      final refAnswer = '$letter. ${options[answerIndex.clamp(0, 3)]}';

      batch.insert('classroom_questions', {
        'source_type': 'quiz',
        'source_id': qId,
        'chapter': q['source'],
        'difficulty': 'medium',
        'question': q['question'],
        'option_a': q['option_a'],
        'option_b': q['option_b'],
        'option_c': q['option_c'],
        'option_d': q['option_d'],
        'answer_index': answerIndex,
        'reference_answer': refAnswer,
        'question_type': 'choice',
        'created_at': DateTime.now().toIso8601String(),
      });
      imported++;
    }
    await batch.commit(noResult: true);
    return imported;
  }

  /// 从实验任务导入
  Future<int> importFromLabTasks() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;

    final existing = await db.query('classroom_questions',
        columns: ['source_id'],
        where: "source_type = 'lab'");
    final existingIds = existing.map((e) => e['source_id'] as int?).toSet();

    List<Map<String, dynamic>> tasks;
    try {
      tasks = await db.query('lab_tasks');
    } catch (e) {
      // 表不存在是预期路径（首次启动 / 旧 schema），不需打日志
      swallow(e, tag: 'ClassroomDao.importLabTasks');
      return 0;
    }

    int imported = 0;
    final batch = db.batch();
    for (final t in tasks) {
      final tId = t['id'] as int?;
      if (existingIds.contains(tId)) continue;

      final title = t['title'] as String? ?? '';
      final desc = t['description'] as String? ?? '';
      final chapter = t['chapter'] as String? ?? '';
      final rawDiff = t['difficulty'] as String? ?? '';
      String diffLevel;
      switch (rawDiff) {
        case '简单':
          diffLevel = 'easy';
          break;
        case '较难':
          diffLevel = 'hard';
          break;
        default:
          diffLevel = 'medium';
      }

      batch.insert('classroom_questions', {
        'source_type': 'lab',
        'source_id': tId,
        'chapter': chapter,
        'difficulty': diffLevel,
        'question': '【实验】$title\n$desc',
        'reference_answer': desc,
        'question_type': 'open',
        'answer_index': -1,
        'created_at': DateTime.now().toIso8601String(),
      });
      imported++;
    }
    await batch.commit(noResult: true);
    return imported;
  }

  /// 从考核项目导入
  Future<int> importFromAssessment() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;

    final existing = await db.query('classroom_questions',
        columns: ['source_id'],
        where: "source_type = 'assessment'");
    final existingIds = existing.map((e) => e['source_id'] as int?).toSet();

    List<Map<String, dynamic>> projects;
    try {
      projects = await db.query('assessment_projects');
    } catch (e) {
      // 表不存在是预期路径，不需打日志
      swallow(e, tag: 'ClassroomDao.importAssessment');
      return 0;
    }

    int imported = 0;
    final batch = db.batch();
    for (final p in projects) {
      final pId = p['id'] as int?;
      if (existingIds.contains(pId)) continue;

      final title = p['title'] as String? ?? '';
      final desc = p['description'] as String? ?? '';
      final requirements = p['requirements'] as String? ?? desc;

      batch.insert('classroom_questions', {
        'source_type': 'assessment',
        'source_id': pId,
        'difficulty': 'hard',
        'question': '【考核】$title\n$desc',
        'reference_answer': requirements,
        'question_type': 'open',
        'answer_index': -1,
        'created_at': DateTime.now().toIso8601String(),
      });
      imported++;
    }
    await batch.commit(noResult: true);
    return imported;
  }

  /// 获取课堂提问列表（带筛选）
  Future<List<Map<String, dynamic>>> getClassroomQuestions({
    String? sourceType,
    String? chapter,
    String? difficulty,
    bool? isAsked,
    int limit = 200,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;

    final conditions = <String>[];
    final args = <dynamic>[];
    if (sourceType != null && sourceType.isNotEmpty) {
      conditions.add('source_type = ?');
      args.add(sourceType);
    }
    if (chapter != null && chapter.isNotEmpty) {
      conditions.add('chapter = ?');
      args.add(chapter);
    }
    if (difficulty != null && difficulty.isNotEmpty) {
      conditions.add('difficulty = ?');
      args.add(difficulty);
    }
    if (isAsked != null) {
      conditions.add(isAsked ? 'asked_at IS NOT NULL' : 'asked_at IS NULL');
    }

    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;
    return await db.query('classroom_questions',
        where: where,
        whereArgs: args.isNotEmpty ? args : null,
        orderBy: 'asked_at DESC, created_at DESC',
        limit: limit);
  }

  /// 获取去重章节列表
  Future<List<String>> getQuestionChapters() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
        'SELECT DISTINCT chapter FROM classroom_questions '
        'WHERE chapter IS NOT NULL AND chapter != "" ORDER BY chapter');
    return result.map((r) => r['chapter'] as String).toList();
  }

  /// 按来源统计题目数
  Future<Map<String, int>> getQuestionSourceStats() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('''
      SELECT source_type, COUNT(*) as count
      FROM classroom_questions GROUP BY source_type
    ''');
    return {
      for (var r in result)
        r['source_type'] as String: (r['count'] as int?) ?? 0
    };
  }

  /// 题库总数
  Future<int> getClassroomQuestionCount() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final r = await db
        .rawQuery('SELECT COUNT(*) as c FROM classroom_questions');
    return (r.first['c'] as int?) ?? 0;
  }

  /// 新增课堂提问
  Future<int> addClassroomQuestion({
    required String sourceType,
    String? chapter,
    String difficulty = 'medium',
    required String question,
    String? optionA,
    String? optionB,
    String? optionC,
    String? optionD,
    int answerIndex = -1,
    String? referenceAnswer,
    String questionType = 'open',
    String? createdBy,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    return await db.insert('classroom_questions', {
      'source_type': sourceType,
      'chapter': chapter,
      'difficulty': difficulty,
      'question': question,
      'option_a': optionA,
      'option_b': optionB,
      'option_c': optionC,
      'option_d': optionD,
      'answer_index': answerIndex,
      'reference_answer': referenceAnswer,
      'question_type': questionType,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 更新课堂提问
  Future<void> updateClassroomQuestion(
      int id, Map<String, dynamic> data) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.update('classroom_questions', data,
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除课堂提问
  Future<void> deleteClassroomQuestion(int id) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.delete('classroom_questions',
        where: 'id = ?', whereArgs: [id]);
  }

  /// 标记已提问
  Future<void> markQuestionAsked(int id, {int? classId}) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.update(
        'classroom_questions',
        {
          'asked_at': DateTime.now().toIso8601String(),
          'class_id': classId,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// 取消提问标记
  Future<void> unmarkQuestionAsked(int id) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.update(
        'classroom_questions',
        {'asked_at': null, 'class_id': null},
        where: 'id = ?',
        whereArgs: [id]);
  }
}
