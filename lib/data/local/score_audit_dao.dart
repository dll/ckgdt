import 'database_helper.dart';

/// 成绩录入/修改审计 DAO。
///
/// **设计**：只追加不改写。任何成绩字段（project_scores / work_scores /
/// defense_records / contribution_scores）的录入或修改都通过 [logChange]
/// 写一行。事后教师可在 "成绩录入中心" 查记录原因 + 操作人。
///
/// **失败兜底**：写日志失败不能阻断主流程（评分本身要保存成功）。
/// 调用方在 try-catch 里 swallow [logChange] 的异常，但**业务关键** —
/// 因此 dao 内不再二次 swallow。
class ScoreAuditDao {
  static final ScoreAuditDao instance = ScoreAuditDao._();
  ScoreAuditDao._();

  /// 记一笔字段变更。
  /// [op] = 'create' | 'update' | 'delete'
  Future<int> logChange({
    required String tableName,
    required int rowId,
    required String field,
    String? oldValue,
    String? newValue,
    String? reason,
    required String scorerId,
    String? scorerName,
    String op = 'update',
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('score_audit_log', {
      'table_name': tableName,
      'row_id': rowId,
      'field': field,
      'old_value': oldValue,
      'new_value': newValue,
      'reason': reason,
      'scorer_id': scorerId,
      'scorer_name': scorerName,
      'op': op,
      'changed_at': DateTime.now().toIso8601String(),
    });
  }

  /// 批量记一组字段（同一行 + 同一原因 + 同一操作人）。
  /// 用在录入/修改 5 维度分这种"一次提交多字段"场景。
  Future<void> logChanges({
    required String tableName,
    required int rowId,
    required Map<String, ({String? oldValue, String? newValue})> fields,
    String? reason,
    required String scorerId,
    String? scorerName,
    String op = 'update',
  }) async {
    final db = await DatabaseHelper.instance.database;
    final ts = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final entry in fields.entries) {
      // 跳过未变化的字段（节省日志噪音）
      if (entry.value.oldValue == entry.value.newValue) continue;
      batch.insert('score_audit_log', {
        'table_name': tableName,
        'row_id': rowId,
        'field': entry.key,
        'old_value': entry.value.oldValue,
        'new_value': entry.value.newValue,
        'reason': reason,
        'scorer_id': scorerId,
        'scorer_name': scorerName,
        'op': op,
        'changed_at': ts,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 取某条记录的全部修改历史（按时间倒序）。
  Future<List<Map<String, dynamic>>> getHistory(
      String tableName, int rowId) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'score_audit_log',
      where: 'table_name = ? AND row_id = ?',
      whereArgs: [tableName, rowId],
      orderBy: 'changed_at DESC',
    );
  }

  /// 教师 / 管理员视角：自己最近的修改记录。
  Future<List<Map<String, dynamic>>> getRecentByScorer(
    String scorerId, {
    int limit = 50,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'score_audit_log',
      where: 'scorer_id = ?',
      whereArgs: [scorerId],
      orderBy: 'changed_at DESC',
      limit: limit,
    );
  }

  /// 全局最近的修改（管理员审计视图用）。
  Future<List<Map<String, dynamic>>> getRecentAll({int limit = 100}) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'score_audit_log',
      orderBy: 'changed_at DESC',
      limit: limit,
    );
  }
}
