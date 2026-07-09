import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/services/course_terminology_service.dart';

import '../helpers/test_db.dart';

void main() {
  setupTestSqflite();

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    DatabaseHelper.databaseForTest = null;
  });

  Future<void> createSchema(dynamic db) async {
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
  }

  test('uses latest imported profile terminology for active course', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);

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

    final terms = await CourseTerminologyService().activeTerms();

    expect(terms.practiceLabel, '研读实践');
    expect(terms.taskLabel, '研读实践任务');
    expect(terms.reportLabel, '研读实践报告');
    expect(terms.materialLabel, '研读实践材料');
  });

  test('falls back to syllabus/profile inference when no imported template',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);

    await db.insert('courses', {
      'id': 'skill',
      'name': '师范教学技能训练',
      'description': '教学技能、模拟授课、操作规范和课堂情境判断训练。',
      'chapter_count': 2,
      'chapters': '["教学技能规范","课堂情境模拟"]',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00',
    });

    final terms = await CourseTerminologyService().activeTerms();

    expect(terms.practiceLabel, '技能实践');
    expect(terms.taskLabel, '技能实践任务');
    expect(terms.reportLabel, '技能实践报告');
  });
}
