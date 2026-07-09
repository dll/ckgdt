import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/local/teaching_dao.dart';

import '../../helpers/test_db.dart';

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
    await db.execute('''
      CREATE TABLE syllabus_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_name TEXT DEFAULT '',
        chapter_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        objectives TEXT,
        hours INTEGER DEFAULT 2,
        week_start INTEGER,
        week_end INTEGER,
        resources_json TEXT,
        status TEXT DEFAULT 'planned',
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE lesson_plans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter INTEGER NOT NULL,
        title TEXT NOT NULL,
        objectives TEXT,
        key_points TEXT,
        difficult_points TEXT,
        content TEXT,
        activities TEXT,
        homework TEXT,
        reflection TEXT,
        resources_json TEXT,
        ai_generated INTEGER DEFAULT 0,
        status TEXT DEFAULT 'draft',
        teacher_id TEXT,
        course_name TEXT,
        plan_type TEXT DEFAULT 'theory',
        hours INTEGER DEFAULT 2,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE teaching_progress(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        course_name TEXT,
        chapter INTEGER NOT NULL,
        topic TEXT,
        planned_date TEXT,
        actual_date TEXT,
        status TEXT DEFAULT 'planned',
        notes TEXT,
        attendance INTEGER DEFAULT 0,
        homework_completion REAL DEFAULT 0,
        teacher_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
  }

  Future<void> seedCourses(dynamic db) async {
    await db.insert('courses', {
      'id': 'ckgdt',
      'name': '课程知识图谱与数字孪生',
      'description': '',
      'chapter_count': 2,
      'chapters': jsonEncode(['旧课一', '旧课二']),
      'is_active': 0,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.insert('courses', {
      'id': 'mad',
      'name': '移动应用开发',
      'description': '',
      'chapter_count': 3,
      'chapters': jsonEncode(['Android基础', 'Flutter开发', '综合项目']),
      'is_active': 1,
      'created_at': '2026-01-02T00:00:00',
    });
  }

  test(
      'teaching dao scopes syllabus, lesson plans and progress to active course',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedCourses(db);

    await db.insert('syllabus_items', {
      'course_name': '课程知识图谱与数字孪生',
      'chapter_number': 1,
      'title': '旧课程大纲',
      'status': 'completed',
    });
    await db.insert('lesson_plans', {
      'course_name': '课程知识图谱与数字孪生',
      'chapter': 1,
      'title': '旧课程教案',
      'status': 'used',
    });
    await db.insert('teaching_progress', {
      'course_name': '课程知识图谱与数字孪生',
      'chapter': 1,
      'topic': '旧课程进度',
      'status': 'completed',
    });

    final dao = TeachingDao();

    await dao.initDefaultSyllabus();
    await dao.initDefaultLessonPlans();
    final progressCreated = await dao.generateProgressFromSyllabus(classId: 1);

    expect(progressCreated, 3);

    final syllabus = await dao.getAllSyllabusItems();
    expect(syllabus.map((row) => row['title']), [
      'Android基础',
      'Flutter开发',
      '综合项目',
    ]);
    expect(syllabus.every((row) => row['course_name'] == '移动应用开发'), isTrue);

    final syllabusStats = await dao.getSyllabusStats();
    expect(syllabusStats['total'], 3);
    expect(syllabusStats['planned'], 3);
    expect(syllabusStats['completed'], 0);

    final lessonPlans = await dao.getAllLessonPlans();
    expect(lessonPlans, hasLength(9));
    expect(
      lessonPlans.every((row) => row['course_name'] == '移动应用开发'),
      isTrue,
    );
    final lessonStats = await dao.getLessonPlanStats();
    expect(lessonStats['total'], 9);
    expect(lessonStats['ready'], 9);
    expect(lessonStats['used'], 0);

    final progress = await dao.getAllTeachingProgress();
    expect(progress, hasLength(3));
    expect(
      progress.every((row) => row['course_name'] == '移动应用开发'),
      isTrue,
    );
    final progressStats = await dao.getProgressStats();
    expect(progressStats['total'], 3);
    expect(progressStats['planned'], 3);
    expect(progressStats['completed'], 0);
  });

  test('teaching dao reads legacy rows stored with course id', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedCourses(db);

    await db.insert('syllabus_items', {
      'course_name': 'mad',
      'chapter_number': 1,
      'title': '按课程ID保存的大纲',
      'status': 'planned',
    });

    final rows = await TeachingDao().getAllSyllabusItems();

    expect(rows.map((row) => row['title']), ['按课程ID保存的大纲']);
  });
}
