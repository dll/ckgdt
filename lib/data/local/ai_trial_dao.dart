import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class AiTrialDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  Future<Map<String, dynamic>?> getSettings() async {
    final db = await _db;
    final rows = await db.query('ai_trial_settings', where: 'id = 1');
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> updateSettings({
    required bool trialEnabled,
    required int trialMaxCalls,
    required int trialMaxTokens,
  }) async {
    final db = await _db;
    await db.update(
      'ai_trial_settings',
      {
        'trial_enabled': trialEnabled ? 1 : 0,
        'trial_max_calls': trialMaxCalls,
        'trial_max_tokens': trialMaxTokens,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = 1',
    );
  }

  Future<int> getCurrentCalls() async {
    final db = await _db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM ai_chat_history WHERE created_at >= ?',
      ['$today 00:00:00'],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<int> getCurrentTokens() async {
    final db = await _db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(prompt_tokens), 0) + COALESCE(SUM(completion_tokens), 0) as total FROM ai_chat_history WHERE created_at >= ?',
      ['$today 00:00:00'],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<bool> hasTrialRemaining() async {
    final settings = await getSettings();
    if (settings == null) return true;
    if (settings['trial_enabled'] != 1) return true;
    final currentCalls = await getCurrentCalls();
    final currentTokens = await getCurrentTokens();
    final maxCalls = (settings['trial_max_calls'] as int?) ?? 10;
    final maxTokens = (settings['trial_max_tokens'] as int?) ?? 50000;
    return currentCalls < maxCalls && currentTokens < maxTokens;
  }

  Future<Map<String, dynamic>> getRemaining() async {
    final settings = await getSettings();
    if (settings == null) {
      return {'remainingCalls': -1, 'remainingTokens': -1, 'enabled': false};
    }
    final enabled = settings['trial_enabled'] == 1;
    if (!enabled) {
      return {'remainingCalls': -1, 'remainingTokens': -1, 'enabled': false};
    }
    final maxCalls = (settings['trial_max_calls'] as int?) ?? 10;
    final maxTokens = (settings['trial_max_tokens'] as int?) ?? 50000;
    final currentCalls = await getCurrentCalls();
    final currentTokens = await getCurrentTokens();
    return {
      'remainingCalls': maxCalls - currentCalls,
      'remainingTokens': maxTokens - currentTokens,
      'enabled': true,
    };
  }
}
