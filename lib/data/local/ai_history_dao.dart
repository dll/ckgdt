import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../../core/error_handler.dart';
import '../../services/course_context_service.dart';

/// AI 聊天历史 DAO
///
/// 管理 ai_chat_history 表，支持智能体和技能的对话持久化。
class AiHistoryDao {
  final CourseContextService _courseContext = CourseContextService();
  bool _courseColumnEnsured = false;

  Future<Database> get _db async => DatabaseHelper.instance.database;

  Future<void> _ensureCourseColumn(Database db) async {
    if (_courseColumnEnsured) return;
    try {
      await db.execute('ALTER TABLE ai_chat_history ADD COLUMN course_id TEXT');
    } catch (e) {
      swallow(e, tag: 'AiHistoryDao.courseColumn');
    }
    try {
      final courseId = await _courseContext.activeCourseId();
      await db.update(
        'ai_chat_history',
        {'course_id': courseId},
        where: "course_id IS NULL OR course_id = ''",
      );
    } catch (e) {
      swallow(e, tag: 'AiHistoryDao.defaultCourse');
    }
    _courseColumnEnsured = true;
  }

  /// 保存一条消息
  Future<int> saveMessage({
    required String sessionId,
    String? agentId,
    String? skillId,
    required String role,
    required String content,
    int tokensUsed = 0,
    int promptTokens = 0,
    int completionTokens = 0,
    String? provider,
    String? model,
    String? userId,
    String? courseId,
  }) async {
    final db = await _db;
    await _ensureCourseColumn(db);
    final resolvedCourseId = courseId ?? await _courseContext.activeCourseId();
    return db.insert('ai_chat_history', {
      'session_id': sessionId,
      'agent_id': agentId,
      'skill_id': skillId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'tokens_used': tokensUsed,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'provider': provider,
      'model': model,
      'user_id': userId ?? '',
      'course_id': resolvedCourseId,
    });
  }

  /// 获取 Token 统计：按天汇总
  Future<List<Map<String, dynamic>>> getDailyTokenStats({int days = 30}) async {
    final db = await _db;
    final since =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return db.rawQuery('''
      SELECT DATE(created_at) as date,
             SUM(prompt_tokens) as prompt_tokens,
             SUM(completion_tokens) as completion_tokens,
             SUM(tokens_used) as total_tokens,
             COUNT(*) as request_count
      FROM ai_chat_history
      WHERE role = 'assistant' AND created_at >= ?
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    ''', [since]);
  }

  /// 获取 Token 统计：按模型汇总
  Future<List<Map<String, dynamic>>> getModelTokenStats() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT COALESCE(model, '未知模型') as model,
             COALESCE(provider, '未知服务商') as provider,
             SUM(prompt_tokens) as prompt_tokens,
             SUM(completion_tokens) as completion_tokens,
             SUM(tokens_used) as total_tokens,
             COUNT(*) as request_count
      FROM ai_chat_history
      WHERE role = 'assistant'
      GROUP BY model, provider
      ORDER BY total_tokens DESC
    ''');
  }

  /// 获取 Token 统计：按服务商汇总
  Future<List<Map<String, dynamic>>> getProviderTokenStats() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT COALESCE(provider, '未知服务商') as provider,
             SUM(prompt_tokens) as prompt_tokens,
             SUM(completion_tokens) as completion_tokens,
             SUM(tokens_used) as total_tokens,
             COUNT(*) as request_count
      FROM ai_chat_history
      WHERE role = 'assistant'
      GROUP BY provider
      ORDER BY total_tokens DESC
    ''');
  }

  /// 获取 Token 总计（可选按用户过滤）
  Future<Map<String, int>> getTokenTotals({String? userId}) async {
    final db = await _db;
    String where = "role = 'assistant'";
    final args = <dynamic>[];
    if (userId != null && userId.isNotEmpty) {
      where += ' AND user_id = ?';
      args.add(userId);
    }
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(prompt_tokens), 0) as prompt_total,
             COALESCE(SUM(completion_tokens), 0) as completion_total,
             COALESCE(SUM(tokens_used), 0) as grand_total,
             COUNT(DISTINCT DATE(created_at)) as active_days
      FROM ai_chat_history
      WHERE $where
    ''', args);
    final row = result.first;
    return {
      'promptTotal': (row['prompt_total'] as int?) ?? 0,
      'completionTotal': (row['completion_total'] as int?) ?? 0,
      'grandTotal': (row['grand_total'] as int?) ?? 0,
      'activeDays': (row['active_days'] as int?) ?? 0,
    };
  }

  /// 获取按用户分组的 Token 统计（教师/管理员查看）
  Future<List<Map<String, dynamic>>> getTokenTotalsByUser(
      {String? classId}) async {
    final db = await _db;
    if (classId != null && classId.isNotEmpty) {
      return db.rawQuery('''
        SELECT h.user_id,
               u.real_name,
               COALESCE(SUM(h.prompt_tokens), 0) as prompt_tokens,
               COALESCE(SUM(h.completion_tokens), 0) as completion_tokens,
               COALESCE(SUM(h.tokens_used), 0) as total_tokens,
               COUNT(*) as request_count,
               COUNT(DISTINCT DATE(h.created_at)) as active_days,
               MAX(h.created_at) as last_active
        FROM ai_chat_history h
        LEFT JOIN users u ON h.user_id = u.user_id
        WHERE h.role = 'assistant' AND h.user_id != ''
          AND h.user_id IN (SELECT user_id FROM class_members WHERE class_id = ?)
        GROUP BY h.user_id
        ORDER BY total_tokens DESC
      ''', [classId]);
    }
    return db.rawQuery('''
      SELECT h.user_id,
             u.real_name,
             COALESCE(SUM(h.prompt_tokens), 0) as prompt_tokens,
             COALESCE(SUM(h.completion_tokens), 0) as completion_tokens,
             COALESCE(SUM(h.tokens_used), 0) as total_tokens,
             COUNT(*) as request_count,
             COUNT(DISTINCT DATE(h.created_at)) as active_days,
             MAX(h.created_at) as last_active
      FROM ai_chat_history h
      LEFT JOIN users u ON h.user_id = u.user_id
      WHERE h.role = 'assistant' AND h.user_id != ''
      GROUP BY h.user_id
      ORDER BY total_tokens DESC
    ''');
  }

  /// 获取按班级分组的 Token 统计
  Future<List<Map<String, dynamic>>> getTokenTotalsByClass() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT c.id as class_id,
             c.name as class_name,
             COUNT(DISTINCT h.user_id) as student_count,
             COALESCE(SUM(h.prompt_tokens), 0) as prompt_tokens,
             COALESCE(SUM(h.completion_tokens), 0) as completion_tokens,
             COALESCE(SUM(h.tokens_used), 0) as total_tokens,
             COUNT(*) as request_count
      FROM classes c
      LEFT JOIN class_members cm ON c.id = cm.class_id
      LEFT JOIN ai_chat_history h ON cm.user_id = h.user_id AND h.role = 'assistant'
      WHERE c.is_archived = 0
      GROUP BY c.id
      ORDER BY total_tokens DESC
    ''');
  }

  /// 获取指定用户的每日 Token 趋势
  Future<List<Map<String, dynamic>>> getDailyTokenStatsByUser(String userId,
      {int days = 30}) async {
    final db = await _db;
    final since =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return db.rawQuery('''
      SELECT DATE(created_at) as date,
             SUM(prompt_tokens) as prompt_tokens,
             SUM(completion_tokens) as completion_tokens,
             SUM(tokens_used) as total_tokens,
             COUNT(*) as request_count
      FROM ai_chat_history
      WHERE role = 'assistant' AND user_id = ? AND created_at >= ?
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    ''', [userId, since]);
  }

  /// 获取某个会话的所有消息
  Future<List<Map<String, dynamic>>> getSessionMessages(
      String sessionId) async {
    final db = await _db;
    return db.query(
      'ai_chat_history',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  /// 获取会话列表（按最新消息时间倒序，去重 session_id）
  Future<List<Map<String, dynamic>>> getSessions({
    String? agentId,
    String? skillId,
  }) async {
    final db = await _db;
    String where = '1=1';
    final args = <dynamic>[];
    if (agentId != null) {
      where += ' AND agent_id = ?';
      args.add(agentId);
    }
    if (skillId != null) {
      where += ' AND skill_id = ?';
      args.add(skillId);
    }
    return db.rawQuery('''
      SELECT session_id,
             agent_id,
             skill_id,
             MIN(created_at) as started_at,
             MAX(created_at) as last_at,
             COUNT(*) as message_count,
             MAX(starred) as starred,
             MAX(title) as title,
             (SELECT content FROM ai_chat_history h2
              WHERE h2.session_id = h1.session_id AND h2.role = 'user'
              ORDER BY h2.created_at ASC LIMIT 1) as first_user_msg
      FROM ai_chat_history h1
      WHERE $where
      GROUP BY session_id
      ORDER BY last_at DESC
    ''', args);
  }

  /// 获取统计数据
  Future<Map<String, dynamic>> getStats() async {
    final db = await _db;

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr =
        DateTime(weekStart.year, weekStart.month, weekStart.day)
            .toIso8601String();

    final results = await Future.wait([
      db.rawQuery(
        'SELECT COUNT(DISTINCT session_id) as cnt FROM ai_chat_history',
      ),
      db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ai_chat_history',
      ),
      db.rawQuery('''
        SELECT agent_id, COUNT(DISTINCT session_id) as cnt
        FROM ai_chat_history
        WHERE agent_id IS NOT NULL AND agent_id != ''
        GROUP BY agent_id
        ORDER BY cnt DESC
      '''),
      db.rawQuery('''
        SELECT skill_id, COUNT(DISTINCT session_id) as cnt
        FROM ai_chat_history
        WHERE skill_id IS NOT NULL AND skill_id != ''
        GROUP BY skill_id
        ORDER BY cnt DESC
      '''),
      db.rawQuery(
        'SELECT COUNT(DISTINCT session_id) as cnt FROM ai_chat_history WHERE created_at >= ?',
        [weekStartStr],
      ),
    ]);

    final totalSessions = (results[0].first['cnt'] as int?) ?? 0;
    final totalMessages = (results[1].first['cnt'] as int?) ?? 0;
    final agentStats = results[2] as List<Map<String, dynamic>>;
    final skillStats = results[3] as List<Map<String, dynamic>>;
    final weekSessions = (results[4].first['cnt'] as int?) ?? 0;

    String? topAgentId;
    int topAgentCount = 0;
    if (agentStats.isNotEmpty) {
      topAgentId = agentStats.first['agent_id'] as String?;
      topAgentCount = (agentStats.first['cnt'] as int?) ?? 0;
    }

    return {
      'totalSessions': totalSessions,
      'totalMessages': totalMessages,
      'weekSessions': weekSessions,
      'topAgentId': topAgentId,
      'topAgentCount': topAgentCount,
      'agentStats': agentStats,
      'skillStats': skillStats,
    };
  }

  /// 清除历史记录
  Future<int> clearHistory({
    String? agentId,
    DateTime? before,
  }) async {
    final db = await _db;
    String where = '1=1';
    final args = <dynamic>[];
    if (agentId != null) {
      where += ' AND agent_id = ?';
      args.add(agentId);
    }
    if (before != null) {
      where += ' AND created_at < ?';
      args.add(before.toIso8601String());
    }
    return db.delete('ai_chat_history', where: where, whereArgs: args);
  }

  /// 删除单个会话
  Future<int> deleteSession(String sessionId) async {
    final db = await _db;
    return db.delete(
      'ai_chat_history',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 清除全部历史
  Future<int> clearAll() async {
    final db = await _db;
    return db.delete('ai_chat_history');
  }

  /// 收藏/取消收藏整个会话
  Future<void> toggleStar(String sessionId) async {
    final db = await _db;
    // 取当前 starred 值（取第一条记录即可）
    final rows = await db.query(
      'ai_chat_history',
      columns: ['starred'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    final current = (rows.isNotEmpty ? rows.first['starred'] as int? : 0) ?? 0;
    await db.update(
      'ai_chat_history',
      {'starred': current == 0 ? 1 : 0},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 设置会话标题（用于收藏时自定义标题）
  Future<void> setSessionTitle(String sessionId, String title) async {
    final db = await _db;
    await db.update(
      'ai_chat_history',
      {'title': title},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 获取收藏的会话列表
  Future<List<Map<String, dynamic>>> getStarredSessions() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT session_id,
             agent_id,
             skill_id,
             MIN(created_at) as started_at,
             MAX(created_at) as last_at,
             COUNT(*) as message_count,
             MAX(starred) as starred,
             MAX(title) as title,
             (SELECT content FROM ai_chat_history h2
              WHERE h2.session_id = h1.session_id AND h2.role = 'user'
              ORDER BY h2.created_at ASC LIMIT 1) as first_user_msg
      FROM ai_chat_history h1
      WHERE starred = 1
      GROUP BY session_id
      ORDER BY last_at DESC
    ''');
  }

  /// 获取请求明细日志（分页，仅 assistant 消息）
  Future<List<Map<String, dynamic>>> getRequestLogs({
    int limit = 50,
    int offset = 0,
    String? userId,
  }) async {
    final db = await _db;
    String where = "role = 'assistant'";
    final args = <dynamic>[];
    if (userId != null && userId.isNotEmpty) {
      where += ' AND user_id = ?';
      args.add(userId);
    }
    args.addAll([limit, offset]);
    return db.rawQuery('''
      SELECT id, created_at, model, provider,
             prompt_tokens, completion_tokens, tokens_used,
             agent_id, skill_id, session_id, user_id
      FROM ai_chat_history
      WHERE $where
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    ''', args);
  }

  /// 获取请求总数（用于分页）
  Future<int> getRequestCount({String? userId}) async {
    final db = await _db;
    String where = "role = 'assistant'";
    final args = <dynamic>[];
    if (userId != null && userId.isNotEmpty) {
      where += ' AND user_id = ?';
      args.add(userId);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM ai_chat_history WHERE $where',
      args,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// 导出历史为 JSON 格式的 List
  Future<List<Map<String, dynamic>>> exportHistory() async {
    final db = await _db;
    return db.query('ai_chat_history', orderBy: 'created_at ASC');
  }
}
