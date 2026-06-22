import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/local/works_dao.dart';

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
        role TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE student_works(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        tech_stack TEXT,
        work_type TEXT DEFAULT '综合项目',
        group_name TEXT,
        leader_name TEXT,
        user_id TEXT,
        file_path TEXT,
        file_size TEXT,
        status TEXT DEFAULT '待提交',
        submit_time TEXT,
        tags TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE work_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_id INTEGER NOT NULL,
        scorer_id TEXT,
        scorer_name TEXT,
        score_functionality INTEGER DEFAULT 0,
        score_tech_depth INTEGER DEFAULT 0,
        score_integration INTEGER DEFAULT 0,
        score_quality INTEGER DEFAULT 0,
        score_documentation INTEGER DEFAULT 0,
        total_score INTEGER DEFAULT 0,
        comment TEXT,
        scored_at TEXT
      )
    ''');
  }

  test('cleanupFakeData preserves real submissions and recalculates counts',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    final dao = WorksDao();
    await dao.getDatabase();

    final submittedId = await db.insert('student_works', {
      'course_id': 'mad',
      'title': '真实作品',
      'user_id': 's001',
      'file_path': r'C:\videos\demo.mp4',
      'video_url': r'C:\videos\demo.mp4',
      'status': '已提交',
      'submit_time': '2026-06-01T10:00:00',
      'view_count': 99,
      'like_count': 99,
      'comment_count': 99,
      'created_at': '2026-06-01T09:00:00',
      'updated_at': '2026-06-01T10:00:00',
    });
    final repairedId = await db.insert('student_works', {
      'course_id': 'mad',
      'title': '被旧清理误标的作品',
      'user_id': 's002',
      'file_path': r'C:\videos\demo2.mp4',
      'status': '待提交',
      'created_at': '2026-06-02T09:00:00',
      'updated_at': '2026-06-02T10:00:00',
    });
    final fakeId = await db.insert('student_works', {
      'course_id': 'mad',
      'title': '旧版假作品',
      'user_id': 's003',
      'status': '已提交',
      'view_count': 42,
      'like_count': 42,
      'comment_count': 42,
      'created_at': '2026-06-03T09:00:00',
      'updated_at': '2026-06-03T10:00:00',
    });

    await db.insert('work_comments', {
      'work_id': submittedId,
      'user_id': 's004',
      'content': '不错',
      'created_at': '2026-06-04T10:00:00',
    });
    await db.insert('work_likes', {
      'work_id': submittedId,
      'user_id': 's004',
      'created_at': '2026-06-04T10:01:00',
    });
    await db.insert('work_views', {
      'work_id': submittedId,
      'user_id': 's004',
      'viewed_at': '2026-06-04T10:02:00',
    });

    await dao.cleanupFakeData();

    final submitted = (await db.query(
      'student_works',
      where: 'id = ?',
      whereArgs: [submittedId],
    ))
        .single;
    expect(submitted['status'], '已提交');
    expect(submitted['video_url'], r'C:\videos\demo.mp4');
    expect(submitted['view_count'], 1);
    expect(submitted['like_count'], 1);
    expect(submitted['comment_count'], 1);

    final repaired = (await db.query(
      'student_works',
      where: 'id = ?',
      whereArgs: [repairedId],
    ))
        .single;
    expect(repaired['status'], '已提交');
    expect(repaired['submit_time'], isNotNull);

    final fake = (await db.query(
      'student_works',
      where: 'id = ?',
      whereArgs: [fakeId],
    ))
        .single;
    expect(fake['status'], '待提交');
    expect(fake['view_count'], 0);
    expect(fake['like_count'], 0);
    expect(fake['comment_count'], 0);
  });

  test('scorer_role identifies teacher score without local teacher user',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    final dao = WorksDao();
    await dao.getDatabase();

    final workId = await db.insert('student_works', {
      'course_id': 'mad',
      'title': '同步回传作品',
      'user_id': 's001',
      'status': '已评分',
      'created_at': '2026-06-01T09:00:00',
      'updated_at': '2026-06-01T10:00:00',
    });
    await db.insert('work_scores', {
      'work_id': workId,
      'scorer_id': 't001',
      'scorer_name': '刘老师',
      'scorer_role': 'teacher',
      'score_functionality': 13,
      'score_tech_depth': 10,
      'score_integration': 10,
      'score_quality': 10,
      'score_documentation': 10,
      'total_score': 53,
      'comment': '已完成教师审核',
      'scored_at': '2026-06-02T10:00:00',
    });

    final work = await dao.getWork(workId);
    expect(work?['score'], 53);
    expect(work?['scorer_name'], '刘老师');

    final leaderboard = await dao.getLeaderboard(dimension: 'score');
    expect(leaderboard, hasLength(1));
    expect(leaderboard.single['score'], 53);
  });
}
