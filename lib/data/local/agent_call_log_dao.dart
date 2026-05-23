import 'package:flutter/foundation.dart';
import 'database_helper.dart';

/// agent_call_logs 表的访问层。记录每次 LLM 调用的元数据：
/// agent_id, prompt 摘要, response 摘要, 耗时, token 估算, provider/model。
///
/// 用于：教学研究素材（学生与 AI 的对话分布）、成本审计、Agent 调用频次分析。
class AgentCallLogDao {
  AgentCallLogDao._();
  static final AgentCallLogDao instance = AgentCallLogDao._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 写一条调用日志。所有字段已字段级 try/catch，失败静默不影响主调用链。
  Future<void> insert({
    required String agentId,
    required String agentName,
    String? userId,
    String? sessionId,
    String? promptSummary,
    String? responseSummary,
    int? durationMs,
    int? promptChars,
    int? responseChars,
    String? provider,
    String? model,
    String? error,
  }) async {
    try {
      final db = await _dbHelper.database;
      await db.insert('agent_call_logs', {
        'agent_id': agentId,
        'agent_name': agentName,
        'user_id': userId,
        'session_id': sessionId,
        'prompt_summary': _truncate(promptSummary, 500),
        'response_summary': _truncate(responseSummary, 1000),
        'duration_ms': durationMs,
        'prompt_chars': promptChars,
        'response_chars': responseChars,
        'provider': provider,
        'model': model,
        'error': error,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('AgentCallLogDao.insert failed: $e');
    }
  }

  /// 按 agentId 拉日志（最新的在前）。
  Future<List<Map<String, dynamic>>> listByAgent(String agentId,
      {int limit = 100}) async {
    try {
      final db = await _dbHelper.database;
      return await db.query(
        'agent_call_logs',
        where: 'agent_id = ?',
        whereArgs: [agentId],
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (_) {
      return [];
    }
  }

  /// 按 userId 拉日志。
  Future<List<Map<String, dynamic>>> listByUser(String userId,
      {int limit = 200}) async {
    try {
      final db = await _dbHelper.database;
      return await db.query(
        'agent_call_logs',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (_) {
      return [];
    }
  }

  /// 全局调用频次统计（Agent → 调用次数）。
  Future<List<Map<String, dynamic>>> aggregateByAgent() async {
    try {
      final db = await _dbHelper.database;
      return await db.rawQuery(
        'SELECT agent_id, agent_name, COUNT(*) as count, '
        'SUM(prompt_chars) as total_prompt_chars, '
        'SUM(response_chars) as total_response_chars, '
        'AVG(duration_ms) as avg_duration_ms '
        'FROM agent_call_logs GROUP BY agent_id ORDER BY count DESC',
      );
    } catch (_) {
      return [];
    }
  }

  /// 删除超过 [days] 天的旧日志（避免表无限增长）。
  Future<int> purgeOlderThan({int days = 90}) async {
    try {
      final db = await _dbHelper.database;
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      return await db
          .delete('agent_call_logs', where: 'created_at < ?', whereArgs: [cutoff]);
    } catch (_) {
      return 0;
    }
  }

  String? _truncate(String? s, int maxLen) {
    if (s == null) return null;
    return s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';
  }
}
