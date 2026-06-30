import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/case_dao.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';

import '../../helpers/test_db.dart';

void main() {
  setupTestSqflite();

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    DatabaseHelper.databaseForTest = null;
  });

  Future<void> createCourseSchema(dynamic db) async {
    await db.execute('''
      CREATE TABLE courses(
        id TEXT PRIMARY KEY,
        name TEXT,
        description TEXT,
        chapter_count INTEGER,
        chapters TEXT,
        is_active INTEGER,
        created_at TEXT
      )
    ''');
    await db.insert('courses', {
      'id': 'ckgdt',
      'name': '课程知识图谱与数字孪生',
      'description': '',
      'chapter_count': 6,
      'chapters': '[]',
      'is_active': 1,
      'created_at': '2026-06-30T00:00:00',
    });
  }

  test('old teaching_cases table is backfilled and new cases are course scoped',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createCourseSchema(db);

    await db.execute('''
      CREATE TABLE teaching_cases(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        project_path TEXT,
        project_type TEXT DEFAULT '',
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.insert('teaching_cases', {
      'name': '旧版案例',
      'project_path': r'D:\legacy-case',
      'project_type': 'unknown',
      'created_at': '2026-06-01T00:00:00',
      'updated_at': '2026-06-01T00:00:00',
    });

    final dao = CaseDao();
    final existing = await dao.getCases();

    expect(existing, hasLength(1));
    expect(existing.single['course_id'], 'ckgdt');
    expect(existing.single['name'], '旧版案例');

    final id = await dao.addCase(
      name: '新教学案例',
      projectPath: r'D:\new-case',
      demoAppType: 'Windows EXE 应用',
    );
    expect(id, greaterThan(0));

    final rows = await db.query(
      'teaching_cases',
      orderBy: 'id ASC',
    );
    expect(rows, hasLength(2));
    expect(rows.every((row) => row['course_id'] == 'ckgdt'), isTrue);
    expect(rows.last['name'], '新教学案例');
    expect(rows.last['demo_app_type'], 'Windows EXE 应用');
  });
}
