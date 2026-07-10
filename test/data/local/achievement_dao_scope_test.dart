import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/achievement_dao.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';

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
      CREATE TABLE classes(
        id INTEGER PRIMARY KEY,
        name TEXT,
        semester TEXT,
        is_archived INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE class_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        user_id TEXT,
        role TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE users(
        user_id TEXT PRIMARY KEY,
        real_name TEXT,
        role TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_batches(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_name TEXT,
        course_name TEXT,
        class_name TEXT,
        semester TEXT,
        syllabus_version TEXT,
        status TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER,
        student_id TEXT,
        student_name TEXT,
        obj1_score REAL DEFAULT 0,
        obj1_achievement REAL DEFAULT 0,
        obj2_score REAL DEFAULT 0,
        obj2_achievement REAL DEFAULT 0,
        obj3_score REAL DEFAULT 0,
        obj3_achievement REAL DEFAULT 0,
        obj4_score REAL DEFAULT 0,
        obj4_achievement REAL DEFAULT 0,
        total_score REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
  }

  test('getScores returns scores even when students only belong to archived class', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);

    await db.insert('courses', {
      'id': 'mad',
      'name': '移动应用开发',
      'is_active': 1,
    });
    await db.insert('classes', {
      'id': 1,
      'name': '软件23',
      'is_archived': 1,
    });
    await db.insert('users', {
      'user_id': '2023001',
      'real_name': '张三',
      'role': 'student',
      'is_active': 1,
    });
    await db.insert('class_members', {
      'class_id': 1,
      'user_id': '2023001',
      'role': 'student',
    });
    final batchId = await db.insert('achievement_batches', {
      'batch_name': '移动应用开发-软件23-2025-2026年第2学期-刘东良',
      'course_name': '移动应用开发',
      'class_name': '软件23',
      'semester': '2025-2026年第2学期',
      'syllabus_version': '2023版',
      'status': 'draft',
    });
    await db.insert('achievement_scores', {
      'batch_id': batchId,
      'student_id': '2023001',
      'student_name': '张三',
      'obj1_score': 80,
      'obj1_achievement': 0.8,
      'total_score': 80,
    });

    final scores = await AchievementDao().getScores(batchId);

    expect(scores.length, 1);
    expect(scores.first['student_id'], '2023001');
  });

  test('buildBatchName follows course-class-semester-teacher format', () {
    expect(
      AchievementDao.buildBatchName(
        courseName: '移动应用开发',
        className: '软件23',
        semester: '2025-2026年第2学期',
        teacherName: '刘东良',
      ),
      '移动应用开发-软件23-2025_2026年第2学期-刘东良',
    );
  });

  test('normalizeAcademicSemester parses and defaults correctly', () {
    expect(
      AchievementDao.normalizeAcademicSemester('2024-2025学年第1学期'),
      '2024-2025年第1学期',
    );
    expect(
      AchievementDao.normalizeAcademicSemester('2024-2025学年第2学期'),
      '2024-2025年第2学期',
    );
    final now = DateTime(2026, 3, 1);
    expect(
      AchievementDao.normalizeAcademicSemester(null, now: now),
      '2025-2026年第2学期',
    );
  });

  test('selectClassForBatch prefers non-demo software classes', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await db.insert('classes', {'id': 1, 'name': 'CKGDT演示班', 'is_archived': 0});
    await db.insert('classes', {'id': 2, 'name': '软件23', 'is_archived': 0});

    final classes = await db.query('classes');
    expect(AchievementDao.selectClassForBatch(classes), '软件23');
  });
}
