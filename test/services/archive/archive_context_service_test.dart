import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/models/archive_document_model.dart';
import 'package:knowledge_graph_app/services/archive_context_service.dart';
import 'package:knowledge_graph_app/services/archive_package_service.dart';

import '../../helpers/test_db.dart';

void main() {
  setupTestSqflite();

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    DatabaseHelper.databaseForTest = null;
  });

  Future<void> createArchiveSchema(dynamic db) async {
    await db.execute('''
      CREATE TABLE courses(
        id TEXT PRIMARY KEY, name TEXT, description TEXT,
        chapter_count INTEGER, chapters TEXT, is_active INTEGER,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE graphs(
        id TEXT PRIMARY KEY, title TEXT, course_id TEXT,
        graph_type TEXT, layout TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE nodes(
        id TEXT PRIMARY KEY, graph_id TEXT, title TEXT, content TEXT,
        node_type TEXT, level INTEGER, x REAL, y REAL, color TEXT,
        parent_id TEXT, visible INTEGER, metadata_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE lab_tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, title TEXT,
        chapter TEXT, hours INTEGER, duration INTEGER, created_at TEXT
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
      CREATE TABLE classes(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, semester TEXT,
        major TEXT, grade TEXT, teacher_id TEXT, teacher_name TEXT,
        student_count INTEGER, is_archived INTEGER DEFAULT 0,
        created_at TEXT, updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE class_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT, class_id INTEGER,
        user_id TEXT, role TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE users(
        user_id TEXT PRIMARY KEY, real_name TEXT, role TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE current_session(
        id INTEGER PRIMARY KEY CHECK(id=1), user_id TEXT,
        machine_code TEXT, login_time TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_batches(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_name TEXT, course_name TEXT, class_name TEXT, semester TEXT,
        syllabus_version TEXT, teacher_id TEXT, status TEXT,
        objective_weights_json TEXT, calc_results_json TEXT,
        report_content TEXT, created_at TEXT, updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER, student_id TEXT, student_name TEXT,
        obj1_achievement REAL DEFAULT 0, obj2_achievement REAL DEFAULT 0,
        obj3_achievement REAL DEFAULT 0, obj4_achievement REAL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_component_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER, student_id TEXT, student_name TEXT,
        kind TEXT, objective INTEGER, label TEXT, score REAL,
        achievement REAL, ratio REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE course_objectives(
        id INTEGER PRIMARY KEY AUTOINCREMENT, course_name TEXT, idx INTEGER,
        weight REAL, full_mark REAL, syllabus_version TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE assessment_groups(
        id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE assessment_projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, group_id INTEGER,
        name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE defense_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER,
        project_id INTEGER, status TEXT, scheduled_time TEXT
      )
    ''');
  }

  test('archive context only uses active course graph and achievement batch',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createArchiveSchema(db);

    await db.insert('courses', {
      'id': 'old',
      'name': '旧课程',
      'description': '',
      'chapter_count': 1,
      'chapters': '["旧章节"]',
      'is_active': 0,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.insert('courses', {
      'id': 'new',
      'name': '新课程',
      'description': '',
      'chapter_count': 1,
      'chapters': '["新章节"]',
      'is_active': 1,
      'created_at': '2026-01-02T00:00:00',
    });
    await db.insert('graphs', {
      'id': 'g_old',
      'title': '旧图谱',
      'course_id': 'old',
      'graph_type': 'course',
    });
    await db.insert('graphs', {
      'id': 'g_new',
      'title': '新图谱',
      'course_id': 'new',
      'graph_type': 'course',
    });
    await db.insert('nodes', {
      'id': 'old_root',
      'graph_id': 'g_old',
      'title': '旧课程根章节',
      'level': 0,
    });
    await db.insert('nodes', {
      'id': 'new_root',
      'graph_id': 'g_new',
      'title': '新课程根章节',
      'level': 0,
    });
    await db.insert('achievement_batches', {
      'batch_name': '旧课程-旧班级-2024-2025年第2学期-旧教师',
      'course_name': '旧课程',
      'class_name': '旧班级',
      'semester': '2024-2025年第2学期',
      'syllabus_version': '2023版',
      'teacher_id': 't_old',
      'created_at': '2026-01-03T00:00:00',
    });
    final batchId = await db.insert('achievement_batches', {
      'batch_name': '新课程-新班级-2025-2026年第2学期-刘东良',
      'course_name': '新课程',
      'class_name': '新班级',
      'semester': '2025-2026年第2学期',
      'syllabus_version': '2026版',
      'teacher_id': 't_new',
      'created_at': '2026-01-04T00:00:00',
    });
    await db.insert('course_objectives', {
      'course_name': '新课程',
      'idx': 1,
      'weight': 0.5,
      'full_mark': 50,
      'syllabus_version': '2026版',
    });
    await db.insert('course_objectives', {
      'course_name': '新课程',
      'idx': 2,
      'weight': 0.5,
      'full_mark': 50,
      'syllabus_version': '2026版',
    });
    await db.insert('achievement_component_scores', {
      'batch_id': batchId,
      'student_id': 's1',
      'student_name': '学生1',
      'kind': 'total',
      'objective': 1,
      'achievement': 0.8,
      'ratio': 1.0,
    });
    await db.insert('achievement_component_scores', {
      'batch_id': batchId,
      'student_id': 's1',
      'student_name': '学生1',
      'kind': 'total',
      'objective': 2,
      'achievement': 0.9,
      'ratio': 1.0,
    });

    final context = await ArchiveContextService().collectForPrompt();

    expect(context, contains('新课程根章节'));
    expect(context, isNot(contains('旧课程根章节')));
    expect(context, contains('新课程-新班级-2025-2026年第2学期-刘东良'));
    expect(context, contains('大纲版本：2026版'));
    expect(context, isNot(contains('旧课程-旧班级')));
  });

  test('archive naming uses document course latest achievement semester',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createArchiveSchema(db);

    await db.insert('courses', {
      'id': 'mad',
      'name': '移动应用开发',
      'description': '',
      'chapter_count': 6,
      'chapters': '[]',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.insert('users', {
      'user_id': '419116',
      'real_name': '刘东良',
      'role': 'teacher',
      'is_active': 1,
    });
    await db.insert('achievement_batches', {
      'batch_name': '移动应用开发-软件23-2025-2026年第2学期-刘东良',
      'course_name': '移动应用开发',
      'class_name': '软件23',
      'semester': '2025-2026年第2学期',
      'syllabus_version': '2023版',
      'teacher_id': '419116',
      'created_at': '2026-01-04T00:00:00',
    });

    final naming = await ArchivePackageService.instance.buildNaming(
      doc: ArchiveDocument(
        title: '期末成绩登记表',
        documentType: 'final_score_register',
        period: 'final',
        courseId: 'mad',
        courseType: 'assessment',
      ),
      docLabel: '成绩登记表',
    );

    expect(naming.course, '移动应用开发');
    expect(naming.teacher, '刘东良');
    expect(naming.semester, '2025-2026年第2学期');
  });

  test('archive context uses course profile terminology for practice tasks',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createArchiveSchema(db);

    await db.insert('courses', {
      'id': 'literature',
      'name': '文学鉴赏',
      'description': '',
      'chapter_count': 2,
      'chapters': '["诗歌意象","小说叙事"]',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.insert('course_package_versions', {
      'course_id': 'literature',
      'version': '1.0.0',
      'template_id': 'universal_smart_course',
      'template_version': '1.0.0',
      'template_profile': 'literature_reading',
      'imported_at': '2026-01-02T00:00:00',
    });
    await db.insert('lab_tasks', {
      'course_id': 'literature',
      'title': '诗歌意象细读研读实践',
      'chapter': '第1章',
      'hours': 2,
      'created_at': '2026-01-03T00:00:00',
    });

    final context = await ArchiveContextService().collectForPrompt();

    expect(context, contains('### 4. 研读实践任务'));
    expect(context, contains('诗歌意象细读研读实践'));
    expect(context, isNot(contains('### 4. 实验任务')));
  });
}
