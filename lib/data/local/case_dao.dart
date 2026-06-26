import 'database_helper.dart';
import '../../services/course_context_service.dart';
import '../../services/project_detector.dart';

class CaseDao {
  final CourseContextService _courseContext = CourseContextService();

  Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS teaching_cases(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          course_id TEXT NOT NULL,
          name TEXT NOT NULL,
          full_name TEXT,
          description TEXT,
          project_path TEXT,
          project_type TEXT DEFAULT '',
          auto_detect INTEGER DEFAULT 1,
          entry_command TEXT,
          repo_url TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');
      await db.rawQuery('SELECT 1 FROM teaching_cases LIMIT 0');
    } catch (e) {
      await db.execute(
        'CREATE TABLE teaching_cases('
        'id INTEGER PRIMARY KEY AUTOINCREMENT,'
        'course_id TEXT NOT NULL,'
        'name TEXT NOT NULL,'
        'full_name TEXT,'
        'description TEXT,'
        'project_path TEXT,'
        'project_type TEXT DEFAULT '','
        'auto_detect INTEGER DEFAULT 1,'
        'entry_command TEXT,'
        'repo_url TEXT,'
        'created_at TEXT,'
        'updated_at TEXT'
        ')',
      );
    }
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN project_type TEXT DEFAULT ""');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN auto_detect INTEGER DEFAULT 1');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN entry_command TEXT');
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getCases() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere(column: 'course_id');
    return db.query('teaching_cases',
        where: scope.where, whereArgs: scope.args, orderBy: 'id ASC');
  }

  Future<int> addCase({
    required String name,
    String? fullName,
    String? description,
    String? projectPath,
    String? repoUrl,
    String? entryCommand,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final courseId = await _courseContext.activeCourseId();
    final now = DateTime.now().toIso8601String();
    String projectType = '';
    int autoDetect = 1;
    if (projectPath != null && projectPath.isNotEmpty) {
      final detected = ProjectDetector.detectType(projectPath);
      projectType = detected.name;
    }
    return db.insert('teaching_cases', {
      'course_id': courseId,
      'name': name,
      'full_name': fullName,
      'description': description,
      'project_path': projectPath,
      'project_type': projectType,
      'auto_detect': autoDetect,
      'entry_command': entryCommand,
      'repo_url': repoUrl,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> updateCase(int id, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update('teaching_cases', data,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCase(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('teaching_cases', where: 'id = ?', whereArgs: [id]);
  }
}
