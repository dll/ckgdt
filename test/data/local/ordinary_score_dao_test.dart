import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/local/ordinary_score_dao.dart';

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
    await db.insert('courses', {
      'id': 'mad',
      'name': '移动应用开发',
      'description': '',
      'chapter_count': 6,
      'chapters': '[]',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.execute('''
      CREATE TABLE users(
        user_id TEXT PRIMARY KEY,
        real_name TEXT,
        role TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE roll_call_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        user_id TEXT,
        user_name TEXT,
        difficulty TEXT,
        tier TEXT,
        is_correct INTEGER,
        score_delta REAL,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE checkin_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        user_id TEXT,
        user_name TEXT,
        status TEXT,
        checked_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE classroom_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender_id TEXT,
        sender_role TEXT,
        message_type TEXT,
        content TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE quiz_results(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        user_id TEXT,
        score INTEGER,
        num_correct INTEGER,
        num_total INTEGER,
        chapter TEXT,
        quiz_timestamp TEXT,
        completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE learning_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        user_id TEXT,
        node_id TEXT,
        node_title TEXT,
        study_time TEXT,
        completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE resource_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        file_name TEXT,
        file_type TEXT,
        source_type TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ai_chat_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        role TEXT,
        content TEXT,
        created_at TEXT,
        tokens_used INTEGER DEFAULT 0,
        user_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE hot_video_favorites(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        video_id INTEGER,
        favorite_time TEXT
      )
    ''');
  }

  test('汇总平台数据为平时成绩并输出达成度百分制分项', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);

    await db.insert('users', {
      'user_id': '2022001',
      'real_name': '王义琳',
      'role': 'student',
      'is_active': 1,
    });
    await db.insert('users', {
      'user_id': '2022002',
      'real_name': '李同学',
      'role': 'student',
      'is_active': 1,
    });

    await db.insert('roll_call_records', {
      'session_id': 1,
      'user_id': '2022001',
      'user_name': '王义琳',
      'difficulty': 'medium',
      'tier': 'A',
      'is_correct': 1,
      'score_delta': 12,
      'created_at': '2026-06-01T10:00:00',
    });
    await db.insert('roll_call_records', {
      'session_id': 1,
      'user_id': '2022001',
      'user_name': '王义琳',
      'difficulty': 'hard',
      'tier': 'A',
      'is_correct': 1,
      'score_delta': 5,
      'created_at': '2026-06-01T10:05:00',
    });
    await db.insert('roll_call_records', {
      'session_id': 1,
      'user_id': '2022002',
      'user_name': '李同学',
      'difficulty': 'easy',
      'tier': 'B',
      'is_correct': 1,
      'score_delta': 5,
      'created_at': '2026-06-01T10:10:00',
    });

    await db.insert('quiz_results', {
      'course_id': 'mad',
      'user_id': '2022001',
      'score': 80,
      'num_correct': 8,
      'num_total': 10,
      'chapter': '第1章',
      'quiz_timestamp': '2026-06-02T10:00:00',
    });
    await db.insert('quiz_results', {
      'course_id': 'mad',
      'user_id': '2022001',
      'score': 100,
      'num_correct': 10,
      'num_total': 10,
      'chapter': '第2章',
      'quiz_timestamp': '2026-06-03T10:00:00',
    });
    await db.insert('quiz_results', {
      'course_id': 'mad',
      'user_id': '2022002',
      'score': 60,
      'num_correct': 6,
      'num_total': 10,
      'chapter': '第1章',
      'quiz_timestamp': '2026-06-02T10:00:00',
    });

    final pptId = await db.insert('resource_files', {
      'course_id': 'mad',
      'file_name': '第1章课件.pptx',
      'file_type': 'ppt',
      'source_type': 'preset',
    });
    final extendedId = await db.insert('resource_files', {
      'course_id': 'mad',
      'file_name': '扩展案例.pdf',
      'file_type': 'pdf',
      'source_type': 'extended',
    });
    await db.insert('learning_records', {
      'course_id': 'mad',
      'user_id': '2022001',
      'node_id': 'resource_$pptId',
      'node_title': '第1章课件.pptx',
      'study_time': '30',
      'completed_at': '2026-06-04T10:00:00',
    });
    await db.insert('learning_records', {
      'course_id': 'mad',
      'user_id': '2022001',
      'node_id': 'resource_$extendedId',
      'node_title': '扩展案例.pdf',
      'study_time': '1',
      'completed_at': '2026-06-04T11:00:00',
    });
    await db.insert('learning_records', {
      'course_id': 'mad',
      'user_id': '2022001',
      'node_id': 'hot_video_7',
      'node_title': '推荐视频：Flutter',
      'study_time': '1',
      'completed_at': '2026-06-05T10:00:00',
    });
    await db.insert('ai_chat_history', {
      'session_id': 'a1',
      'role': 'assistant',
      'content': 'answer',
      'created_at': '2026-06-06T10:00:00',
      'tokens_used': 1200,
      'user_id': '2022001',
    });
    await db.insert('ai_chat_history', {
      'session_id': 'a2',
      'role': 'assistant',
      'content': 'answer',
      'created_at': '2026-06-06T11:00:00',
      'tokens_used': 1800,
      'user_id': '2022001',
    });
    await db.insert('hot_video_favorites', {
      'user_id': '2022001',
      'video_id': 7,
      'favorite_time': '2026-06-05T10:05:00',
    });

    final snapshot = await OrdinaryScoreDao().loadSnapshot();
    expect(snapshot.studentCount, 2);

    final wang = snapshot.rows.firstWhere((r) => r.studentId == '2022001');
    final li = snapshot.rows.firstWhere((r) => r.studentId == '2022002');
    expect(wang.classroomScore, closeTo(17, 0.001));
    expect(wang.quizScore, closeTo(27, 0.001));
    expect(wang.extraScore, closeTo(50, 0.001));
    expect(wang.totalScore, greaterThan(li.totalScore));

    final component = wang.toPingshiComponentRow();
    expect(component['class_activity_score'], closeTo(85, 0.001));
    expect(component['quiz_homework_score'], closeTo(90, 0.001));
    expect(component['extra_learning_score'], closeTo(100, 0.001));
  });
}
