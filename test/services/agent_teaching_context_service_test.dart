import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/services/agent/teaching_context_service.dart';

import '../helpers/test_db.dart';

void main() {
  setupTestSqflite();

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    DatabaseHelper.databaseForTest = null;
  });

  test('agent teaching context uses active course terminology', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;

    await db.execute('''
      CREATE TABLE courses(
        id TEXT PRIMARY KEY, name TEXT, description TEXT,
        chapter_count INTEGER, chapters TEXT, is_active INTEGER,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE course_package_versions(
        id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, version TEXT,
        template_id TEXT, template_version TEXT, template_profile TEXT,
        imported_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE lab_tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, title TEXT
      )
    ''');

    await db.insert('courses', {
      'id': 'lit',
      'name': '文学鉴赏',
      'description': '',
      'chapter_count': 2,
      'chapters': '["诗歌意象","小说叙事"]',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.insert('course_package_versions', {
      'course_id': 'lit',
      'version': '1.0.0',
      'template_id': 'universal_smart_course',
      'template_version': '1.0.0',
      'template_profile': 'literature_reading',
      'imported_at': '2026-01-02T00:00:00',
    });
    await db.insert('lab_tasks', {
      'course_id': 'lit',
      'title': '诗歌意象细读研读实践',
    });

    final context =
        await AgentTeachingContextService.instance.buildPromptContext();

    expect(context, contains('研读实践与作品：1 个研读实践任务'));
    expect(context, contains('教学设计、研读实践任务、考核评价'));
    expect(context, isNot(contains('实验与作品')));
    expect(context, isNot(contains('实验任务、考核评价')));
  });
}
