import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/archive_dao.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/models/archive_document_model.dart';

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
      CREATE TABLE archive_documents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        document_type TEXT NOT NULL,
        period TEXT NOT NULL,
        course_id TEXT,
        course_type TEXT,
        status TEXT DEFAULT 'draft',
        content TEXT,
        file_path TEXT,
        is_generated INTEGER DEFAULT 0,
        review_json TEXT DEFAULT '',
        reviewed_at TEXT DEFAULT '',
        origin_doc_id INTEGER,
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
      'chapter_count': 8,
      'chapters': '[]',
      'is_active': 0,
      'created_at': '2026-01-01T00:00:00',
    });
    await db.insert('courses', {
      'id': 'mad',
      'name': '移动应用开发',
      'description': '',
      'chapter_count': 6,
      'chapters': '[]',
      'is_active': 1,
      'created_at': '2026-01-02T00:00:00',
    });
  }

  test('getDocuments defaults to strict active course scope', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedCourses(db);

    await db.insert('archive_documents', {
      'title': 'CKGDT教学大纲',
      'document_type': 'syllabus',
      'period': 'beginning',
      'course_id': 'ckgdt',
      'course_type': 'assess',
      'content': 'old',
    });
    await db.insert('archive_documents', {
      'title': '旧未绑定教学大纲',
      'document_type': 'syllabus',
      'period': 'beginning',
      'course_id': '',
      'course_type': 'assess',
      'content': 'legacy',
    });

    final dao = ArchiveDao();
    final id = await dao.saveDocument(ArchiveDocument(
      title: 'MAD教学大纲',
      documentType: 'syllabus',
      period: 'beginning',
      courseType: 'assess',
      content: 'current',
    ));

    final docs = await dao.getDocuments(period: 'beginning');

    expect(docs.map((d) => d.id), [id]);
    expect(docs.single.courseId, 'mad');
    expect(docs.single.title, 'MAD教学大纲');
  });

  test('legacy unbound archive docs are opt-in only', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedCourses(db);

    await db.insert('archive_documents', {
      'title': '未绑定旧材料',
      'document_type': 'calendar',
      'period': 'beginning',
      'course_id': null,
      'course_type': 'assess',
      'content': 'legacy',
    });

    final dao = ArchiveDao();

    expect(await dao.getDocuments(period: 'beginning'), isEmpty);
    final legacy = await dao.getDocuments(
      period: 'beginning',
      includeUnboundLegacy: true,
    );
    expect(legacy.map((d) => d.title), ['未绑定旧材料']);
  });

  test('saveDocument normalizes blank course id to active course', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedCourses(db);

    final dao = ArchiveDao();
    final id = await dao.saveDocument(ArchiveDocument(
      title: '新课程期末总结',
      documentType: 'final_summary',
      period: 'final',
      courseId: '',
      courseType: 'assess',
      content: 'summary',
    ));

    final saved = await dao.getDocumentById(id);
    expect(saved, isNotNull);
    expect(saved!.courseId, 'mad');

    final docs = await dao.getDocuments(period: 'final');
    expect(docs.map((d) => d.title), ['新课程期末总结']);
  });

  test('archiveCount only counts active course archived documents', () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await seedCourses(db);

    await db.insert('archive_documents', {
      'title': 'MAD已归档',
      'document_type': 'syllabus',
      'period': 'final',
      'course_id': 'mad',
      'course_type': 'assess',
      'status': 'archived',
    });
    await db.insert('archive_documents', {
      'title': 'CKGDT已归档',
      'document_type': 'syllabus',
      'period': 'final',
      'course_id': 'ckgdt',
      'course_type': 'assess',
      'status': 'archived',
    });
    await db.insert('archive_documents', {
      'title': '旧未绑定已归档',
      'document_type': 'syllabus',
      'period': 'final',
      'course_id': '',
      'course_type': 'assess',
      'status': 'archived',
    });

    expect(await ArchiveDao().archiveCount('final'), 1);
  });
}
