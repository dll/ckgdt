import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/class_dao.dart';
import 'package:knowledge_graph_app/data/local/classroom_dao.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/local/notification_dao.dart';

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
      CREATE TABLE users(
        user_id TEXT PRIMARY KEY,
        real_name TEXT,
        role TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE classes(
        id INTEGER PRIMARY KEY,
        name TEXT,
        is_archived INTEGER DEFAULT 0,
        student_count INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE class_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        user_id TEXT,
        role TEXT DEFAULT 'student',
        joined_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE notifications(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        type TEXT,
        creator_id TEXT,
        target_type TEXT,
        target_id TEXT,
        related_entity_type TEXT,
        related_entity_id TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE notification_recipients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_id INTEGER,
        user_id TEXT,
        is_read INTEGER DEFAULT 0,
        read_at TEXT
      )
    ''');
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
  }

  Future<void> seedStudents(dynamic db) async {
    await db.insert('users', {
      'user_id': 'active_class',
      'real_name': '当前班级学生',
      'role': 'student',
      'is_active': 1,
    });
    await db.insert('users', {
      'user_id': 'archived_only',
      'real_name': '归档班级学生',
      'role': 'student',
      'is_active': 1,
    });
    await db.insert('users', {
      'user_id': 'unassigned',
      'real_name': '未分班学生',
      'role': 'student',
      'is_active': 1,
    });
    await db.insert('users', {
      'user_id': 'inactive',
      'real_name': '停用学生',
      'role': 'student',
      'is_active': 0,
    });
    await db.insert('classes', {
      'id': 1,
      'name': '当前班',
      'is_archived': 0,
    });
    await db.insert('classes', {
      'id': 2,
      'name': '归档班',
      'is_archived': 1,
    });
    await db.insert('class_members', {
      'class_id': 1,
      'user_id': 'active_class',
      'role': 'student',
    });
    await db.insert('class_members', {
      'class_id': 2,
      'user_id': 'archived_only',
      'role': 'student',
    });
  }

  test('全体通知排除只属于归档班级的学生', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedStudents(db);

    await NotificationDao().createNotification(
      title: '问卷调查',
      content: '请查看问卷',
      targetType: 'all',
    );

    final rows = await db.query(
      'notification_recipients',
      orderBy: 'user_id',
    );
    final ids = rows.map((r) => r['user_id']).toList();

    expect(ids, ['active_class', 'unassigned']);
  });

  test('无指定班级签到只为当前活跃学生生成记录', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedStudents(db);

    await ClassroomDao().createCheckinSession(
      title: '课堂签到',
      createdBy: 'teacher01',
    );

    final rows = await db.query('checkin_records', orderBy: 'user_id');
    final ids = rows.map((r) => r['user_id']).toList();

    expect(ids, ['active_class', 'unassigned']);
  });

  test('班级管理待添加学生排除只属于归档班级的学生', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedStudents(db);

    final students = await ClassDao().getUnassignedStudents();
    final ids = students.map((s) => s.userId).toList();

    expect(ids, ['unassigned']);
  });

  test('批量同步学生到班级不会重新拉回归档班级学生', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedStudents(db);
    await db.insert('classes', {
      'id': 3,
      'name': '新当前班',
      'is_archived': 0,
    });

    await ClassDao().syncAllStudentsToClass(3);

    final rows = await db.query(
      'class_members',
      where: 'class_id = ?',
      whereArgs: [3],
      orderBy: 'user_id',
    );
    final ids = rows.map((r) => r['user_id']).toList();

    expect(ids, ['active_class', 'unassigned']);
  });
}
