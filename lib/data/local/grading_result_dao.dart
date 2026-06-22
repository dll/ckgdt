import 'dart:convert';
import 'database_helper.dart';

/// AI 批阅结果持久化 DAO
///
/// 管理 grading_results 表，实现 pending → approved/rejected 工作流。
class GradingResultDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 保存 AI 批阅结果（status = 'pending'）
  Future<int> saveResult({
    required String domain,
    required int targetId,
    required String scorerId,
    String? modelProvider,
    String? modelName,
    String? rawJson,
    double? score,
    String? feedback,
    Map<String, dynamic>? dimensions,
    List<String>? strengths,
    List<String>? improvements,
    bool aiFlag = false,
  }) async {
    final db = await _dbHelper.database;
    return db.insert('grading_results', {
      'domain': domain,
      'target_id': targetId,
      'scorer_id': scorerId,
      'model_provider': modelProvider,
      'model_name': modelName,
      'raw_json': rawJson,
      'score': score,
      'feedback': feedback,
      'dimensions': dimensions != null ? jsonEncode(dimensions) : null,
      'strengths': strengths != null ? jsonEncode(strengths) : null,
      'improvements': improvements != null ? jsonEncode(improvements) : null,
      'ai_flag': aiFlag ? 1 : 0,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取指定域名的待审核批阅结果
  Future<List<Map<String, dynamic>>> getPendingResults(
    String domain, {
    int? targetId,
  }) async {
    final db = await _dbHelper.database;
    String where = "domain = ? AND status = 'pending'";
    final args = <dynamic>[domain];
    if (targetId != null) {
      where += ' AND target_id = ?';
      args.add(targetId);
    }
    return db.query('grading_results',
        where: where, whereArgs: args, orderBy: 'created_at DESC');
  }

  /// 审核通过
  Future<void> approveResult(int id, String approvedBy) async {
    final db = await _dbHelper.database;
    await db.update(
        'grading_results',
        {
          'status': 'approved',
          'approved_at': DateTime.now().toIso8601String(),
          'approved_by': approvedBy,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// 拒绝
  Future<void> rejectResult(int id, String rejectedBy) async {
    final db = await _dbHelper.database;
    await db.update(
        'grading_results',
        {
          'status': 'rejected',
          'approved_at': DateTime.now().toIso8601String(),
          'approved_by': rejectedBy,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// 更新待审核草稿内容。用于教师手工调整，或修复历史 raw JSON 未结构化的问题。
  Future<void> updateDraftResult({
    required int id,
    String? rawJson,
    double? score,
    String? feedback,
    Map<String, dynamic>? dimensions,
    List<String>? strengths,
    List<String>? improvements,
    bool? aiFlag,
  }) async {
    final db = await _dbHelper.database;
    final updates = <String, dynamic>{};
    if (rawJson != null) updates['raw_json'] = rawJson;
    if (score != null) updates['score'] = score;
    if (feedback != null) updates['feedback'] = feedback;
    if (dimensions != null) updates['dimensions'] = jsonEncode(dimensions);
    if (strengths != null) updates['strengths'] = jsonEncode(strengths);
    if (improvements != null) {
      updates['improvements'] = jsonEncode(improvements);
    }
    if (aiFlag != null) updates['ai_flag'] = aiFlag ? 1 : 0;
    if (updates.isEmpty) return;
    await db.update(
      'grading_results',
      updates,
      where: 'id = ? AND status = ?',
      whereArgs: [id, 'pending'],
    );
  }

  /// 获取批阅历史
  Future<List<Map<String, dynamic>>> getHistory(
    String domain, {
    int? targetId,
    int limit = 50,
  }) async {
    final db = await _dbHelper.database;
    String where = 'domain = ?';
    final args = <dynamic>[domain];
    if (targetId != null) {
      where += ' AND target_id = ?';
      args.add(targetId);
    }
    return db.query('grading_results',
        where: where,
        whereArgs: args,
        orderBy: 'created_at DESC',
        limit: limit);
  }

  /// 删除指定 target 的旧 pending 结果
  Future<void> deletePendingForTarget(String domain, int targetId) async {
    final db = await _dbHelper.database;
    await db.delete('grading_results',
        where: "domain = ? AND target_id = ? AND status = 'pending'",
        whereArgs: [domain, targetId]);
  }
}
