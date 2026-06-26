import 'database_helper.dart';
import '../../services/course_context_service.dart';
import '../../core/error_handler.dart';

class CaseDao {
  final CourseContextService _courseContext = CourseContextService();

  Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teaching_cases(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT NOT NULL,
        name TEXT NOT NULL,
        full_name TEXT,
        description TEXT,
        project_path TEXT,
        repo_url TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
  }

  /// 获取当前课程的教学案例列表
  Future<List<Map<String, dynamic>>> getCases() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere(column: 'course_id');
    return db.query('teaching_cases',
        where: scope.where, whereArgs: scope.args, orderBy: 'id ASC');
  }

  /// 添加教学案例
  Future<int> addCase({
    required String name,
    String? fullName,
    String? description,
    String? projectPath,
    String? repoUrl,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final courseId = await _courseContext.activeCourseId();
    final now = DateTime.now().toIso8601String();
    return db.insert('teaching_cases', {
      'course_id': courseId,
      'name': name,
      'full_name': fullName,
      'description': description,
      'project_path': projectPath,
      'repo_url': repoUrl,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// 更新教学案例
  Future<int> updateCase(int id, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update('teaching_cases', data,
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除教学案例
  Future<int> deleteCase(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('teaching_cases', where: 'id = ?', whereArgs: [id]);
  }
}
