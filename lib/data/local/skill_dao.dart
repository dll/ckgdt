import 'package:sqflite/sqflite.dart';
import '../../core/error_handler.dart';
import '../../services/course_context_service.dart';
import 'database_helper.dart';

/// AI 技能生成结果 DAO
/// 使用 _ensureTable 模式，不修改 database_helper.dart
class SkillDao {
  static bool _tableReady = false;
  final CourseContextService _courseContext = CourseContextService();

  Future<Database> get _db async => DatabaseHelper.instance.database;

  /// 确保 skill_results 表存在
  Future<void> _ensureTable() async {
    if (_tableReady) return;
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS skill_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        skill_id TEXT NOT NULL,
        course_id TEXT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        content_type TEXT DEFAULT 'markdown',
        chapter TEXT,
        created_at TEXT
      )
    ''');
    try {
      await db.execute('ALTER TABLE skill_results ADD COLUMN course_id TEXT');
    } catch (e) {
      swallow(e, tag: 'SkillDao.courseColumn');
    }
    try {
      final courseId = await _courseContext.activeCourseId();
      await db.update(
        'skill_results',
        {'course_id': courseId},
        where: "course_id IS NULL OR course_id = ''",
      );
    } catch (e) {
      swallow(e, tag: 'SkillDao.backfillCourse');
    }
    _tableReady = true;
  }

  /// 保存生成结果
  Future<int> saveResult({
    required String skillId,
    required String title,
    required String content,
    String contentType = 'markdown',
    String? chapter,
  }) async {
    await _ensureTable();
    final db = await _db;
    final courseId = await _courseContext.activeCourseId();
    return db.insert('skill_results', {
      'skill_id': skillId,
      'course_id': courseId,
      'title': title,
      'content': content,
      'content_type': contentType,
      'chapter': chapter,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取某技能的所有生成结果（按时间倒序）
  Future<List<Map<String, dynamic>>> getResults(String skillId) async {
    await _ensureTable();
    final db = await _db;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'skill_id = ?',
      extraArgs: [skillId],
    );
    return db.query(
      'skill_results',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'created_at DESC',
    );
  }

  /// 获取某条结果详情
  Future<Map<String, dynamic>?> getResult(int id) async {
    await _ensureTable();
    final db = await _db;
    final list = await db.query(
      'skill_results',
      where: 'id = ?',
      whereArgs: [id],
    );
    return list.isNotEmpty ? list.first : null;
  }

  /// 删除某条结果
  Future<int> deleteResult(int id) async {
    await _ensureTable();
    final db = await _db;
    return db.delete('skill_results', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取所有技能的结果统计
  Future<Map<String, int>> getResultCounts() async {
    await _ensureTable();
    final db = await _db;
    final scope = await _courseContext.scopedWhere();
    final rows = await db.rawQuery(
      'SELECT skill_id, COUNT(*) as cnt FROM skill_results '
      'WHERE ${scope.where} GROUP BY skill_id',
      scope.args,
    );
    final map = <String, int>{};
    for (final row in rows) {
      map[row['skill_id'] as String] = (row['cnt'] as int?) ?? 0;
    }
    return map;
  }
}
