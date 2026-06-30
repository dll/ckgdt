import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import '../../services/course_context_service.dart';
import '../../services/project_detector.dart';
import '../../core/utils/path_utils.dart';

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
          demo_app_type TEXT,
          launch_method TEXT,
          view_steps TEXT,
          feature_intro TEXT,
          screenshot_path TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');
    } catch (e) {
      // 表已存在或创建失败，尝试用旧 schema 重建
      debugPrint(
          '=== CaseDao._ensureTable: $e — falling back to minimal schema');
      try {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS teaching_cases('
          'id INTEGER PRIMARY KEY AUTOINCREMENT,'
          'course_id TEXT NOT NULL,'
          'name TEXT NOT NULL,'
          'full_name TEXT,'
          'description TEXT,'
          'project_path TEXT,'
          'project_type TEXT DEFAULT "",'
          'auto_detect INTEGER DEFAULT 1,'
          'entry_command TEXT,'
          'repo_url TEXT,'
          'demo_app_type TEXT,'
          'launch_method TEXT,'
          'view_steps TEXT,'
          'feature_intro TEXT,'
          'screenshot_path TEXT,'
          'created_at TEXT,'
          'updated_at TEXT'
          ')',
        );
      } catch (_) {}
    }
    // 兼容旧表：补齐缺失列
    try {
      await db.execute(
          'ALTER TABLE teaching_cases ADD COLUMN project_type TEXT DEFAULT ""');
    } catch (_) {}
    try {
      await db.execute(
          'ALTER TABLE teaching_cases ADD COLUMN auto_detect INTEGER DEFAULT 1');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE teaching_cases ADD COLUMN entry_command TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN full_name TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE teaching_cases ADD COLUMN description TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN repo_url TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE teaching_cases ADD COLUMN demo_app_type TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE teaching_cases ADD COLUMN launch_method TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN view_steps TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE teaching_cases ADD COLUMN feature_intro TEXT');
    } catch (_) {}
    try {
      await db.execute(
          'ALTER TABLE teaching_cases ADD COLUMN screenshot_path TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN created_at TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE teaching_cases ADD COLUMN updated_at TEXT');
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
    String? demoAppType,
    String? launchMethod,
    String? viewSteps,
    String? featureIntro,
    String? screenshotPath,
  }) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final courseId = await _courseContext.activeCourseId();
    final now = DateTime.now().toIso8601String();
    String projectType = '';
    int autoDetect = 1;
    // 关键：规范化路径（去除用户复制时带入的多余引号）
    final cleanPath = PathUtils.normalize(projectPath);
    if (cleanPath.isNotEmpty) {
      final detected = ProjectDetector.detectType(cleanPath);
      projectType = detected.name;
    }
    return db.insert('teaching_cases', {
      'course_id': courseId,
      'name': name,
      'full_name': fullName,
      'description': description,
      'project_path': cleanPath,
      'project_type': projectType,
      'auto_detect': autoDetect,
      'entry_command': entryCommand,
      'repo_url': repoUrl,
      'demo_app_type': demoAppType,
      'launch_method': launchMethod,
      'view_steps': viewSteps,
      'feature_intro': featureIntro,
      'screenshot_path': PathUtils.normalize(screenshotPath),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> updateCase(int id, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update('teaching_cases', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCase(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('teaching_cases', where: 'id = ?', whereArgs: [id]);
  }
}
