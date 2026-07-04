import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/services/course_package_loader.dart';

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
      'chapters': jsonEncode(['旧第1章', '旧第2章']),
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.execute('''
      CREATE TABLE lab_tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        title TEXT,
        chapter TEXT,
        description TEXT,
        requirements TEXT,
        deliverables TEXT,
        due_date TEXT,
        difficulty TEXT,
        max_score INTEGER,
        status TEXT,
        creator_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE homeworks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        chapter TEXT,
        chapter_title TEXT,
        course_objective TEXT,
        total_score INTEGER DEFAULT 100,
        deadline TEXT,
        status TEXT DEFAULT 'draft',
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE homework_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        homework_id INTEGER NOT NULL,
        item_index INTEGER,
        type TEXT,
        type_label TEXT,
        question TEXT,
        reference_answer TEXT,
        max_score INTEGER DEFAULT 100,
        objective_mapping TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE homework_submissions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        homework_id INTEGER,
        item_id INTEGER,
        user_id TEXT,
        answer_text TEXT,
        answer_file_path TEXT,
        score INTEGER,
        ai_comment TEXT,
        teacher_comment TEXT,
        status TEXT DEFAULT 'submitted',
        submitted_at TEXT,
        graded_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE resource_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        file_name TEXT,
        file_path TEXT,
        file_type TEXT,
        chapter TEXT,
        description TEXT,
        source_type TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE users(
        user_id TEXT PRIMARY KEY,
        real_name TEXT,
        machine_code TEXT,
        role TEXT,
        created_at TEXT,
        last_login TEXT,
        is_active INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE classes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        semester TEXT,
        teacher_id TEXT,
        teacher_name TEXT,
        description TEXT,
        student_count INTEGER,
        is_archived INTEGER,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE class_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        user_id TEXT,
        role TEXT,
        joined_at TEXT,
        UNIQUE(class_id, user_id)
      )
    ''');
  }

  test('imports CKGDT package as 8-chapter course with demo data', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);

    final result = await CoursePackageLoader.instance.importCourse('ckgdt');

    expect(result.failed, isFalse);
    expect(result.skipped, isFalse);
    expect(result.courseUpdated, isTrue);
    expect(result.labTasksImported, 8);
    expect(result.homeworksImported, 8);
    expect(result.usersImported, greaterThanOrEqualTo(7));
    expect(result.classesImported, 1);

    final course = (await db.query(
      'courses',
      where: 'id = ?',
      whereArgs: ['ckgdt'],
    ))
        .single;
    expect(course['chapter_count'], 8);
    final chapters = jsonDecode(course['chapters'] as String) as List<dynamic>;
    expect(chapters, contains('第8章 教师与管理员平台操作'));

    final packageRows = await db.query('course_package_versions');
    expect(packageRows.single['status'], 'imported');

    final homeworkCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM homeworks WHERE course_id = ?',
      ['ckgdt'],
    ))
        .single['c'] as int;
    expect(homeworkCount, 8);

    final homeworkItemCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM homework_items',
    ))
        .single['c'] as int;
    expect(homeworkItemCount, 24);

    final resourceCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM resource_files WHERE course_id = ? AND source_type = ?',
      ['ckgdt', 'course_package'],
    ))
        .single['c'] as int;
    expect(resourceCount, greaterThan(20));
  });
}
