import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// AI 聊天历史 DAO
///
/// 管理 ai_chat_history 表，支持智能体和技能的对话持久化。
class AiHistoryDao {
  Future<Database> get _db async => DatabaseHelper.instance.database;

  /// 保存一条消息
  Future<int> saveMessage({
    required String sessionId,
    String? agentId,
    String? skillId,
    required String role,
    required String content,
    int tokensUsed = 0,
  }) async {
    final db = await _db;
    return db.insert('ai_chat_history', {
      'session_id': sessionId,
      'agent_id': agentId,
      'skill_id': skillId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'tokens_used': tokensUsed,
    });
  }

  /// 获取某个会话的所有消息
  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId) async {
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

    // 总会话数
    final sessionCount = await db.rawQuery(
      'SELECT COUNT(DISTINCT session_id) as cnt FROM ai_chat_history',
    );
    final totalSessions = (sessionCount.first['cnt'] as int?) ?? 0;

    // 总消息数
    final msgCount = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM ai_chat_history',
    );
    final totalMessages = (msgCount.first['cnt'] as int?) ?? 0;

    // 各智能体使用次数（按会话数）
    final agentStats = await db.rawQuery('''
      SELECT agent_id, COUNT(DISTINCT session_id) as cnt
      FROM ai_chat_history
      WHERE agent_id IS NOT NULL AND agent_id != ''
      GROUP BY agent_id
      ORDER BY cnt DESC
    ''');

    // 各技能使用次数
    final skillStats = await db.rawQuery('''
      SELECT skill_id, COUNT(DISTINCT session_id) as cnt
      FROM ai_chat_history
      WHERE skill_id IS NOT NULL AND skill_id != ''
      GROUP BY skill_id
      ORDER BY cnt DESC
    ''');

    // 本周使用次数
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr =
        DateTime(weekStart.year, weekStart.month, weekStart.day)
            .toIso8601String();
    final weekCount = await db.rawQuery(
      'SELECT COUNT(DISTINCT session_id) as cnt FROM ai_chat_history WHERE created_at >= ?',
      [weekStartStr],
    );
    final weekSessions = (weekCount.first['cnt'] as int?) ?? 0;

    // 最活跃智能体
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

  /// 导出历史为 JSON 格式的 List
  Future<List<Map<String, dynamic>>> exportHistory() async {
    final db = await _db;
    return db.query('ai_chat_history', orderBy: 'created_at ASC');
  }
}
