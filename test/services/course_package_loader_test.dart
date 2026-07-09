import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/services/archive/archive_template_source_service.dart';
import 'package:knowledge_graph_app/services/course_generation_service.dart';
import 'package:knowledge_graph_app/services/course_package_loader.dart';
import 'package:knowledge_graph_app/services/resource_persistence_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/test_db.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  setupTestSqflite();

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    DatabaseHelper.databaseForTest = null;
    ArchiveTemplateSourceService.clearRegisteredCourseArchiveRoots();
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
    await db.execute('''
      CREATE TABLE course_objectives(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_name TEXT NOT NULL DEFAULT '',
        idx INTEGER NOT NULL,
        name TEXT,
        indicator TEXT,
        weight REAL DEFAULT 0,
        full_mark REAL DEFAULT 0,
        pingshi_ratio REAL DEFAULT 0.20,
        experiment_ratio REAL DEFAULT 0.30,
        exam_ratio REAL DEFAULT 0.50,
        chapters TEXT,
        description TEXT,
        assess_content TEXT,
        experiments TEXT,
        pingshi_standard TEXT,
        experiment_standard TEXT,
        assessment_items_json TEXT,
        extra_columns_json TEXT,
        syllabus_version TEXT,
        created_at TEXT,
        updated_at TEXT,
        UNIQUE(course_name, idx)
      )
    ''');
    await db.execute('''
      CREATE TABLE graphs(
        id TEXT PRIMARY KEY,
        title TEXT,
        course_id TEXT,
        graph_type TEXT,
        layout TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE nodes(
        id TEXT PRIMARY KEY,
        graph_id TEXT,
        title TEXT,
        content TEXT,
        node_type TEXT,
        level INTEGER,
        x REAL,
        y REAL,
        color TEXT,
        parent_id TEXT,
        visible INTEGER,
        metadata_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE edges(
        id TEXT PRIMARY KEY,
        graph_id TEXT,
        source_id TEXT,
        target_id TEXT,
        edge_type TEXT,
        label TEXT,
        weight REAL,
        color TEXT,
        width REAL,
        style TEXT,
        visible INTEGER
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
    expect(result.objectivesImported, 5);
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
    expect(packageRows.single['template_id'], 'universal_smart_course');
    expect(packageRows.single['template_version'], '1.0.0');
    expect(packageRows.single['template_profile'], 'general_smart_course');
    expect(packageRows.single['profile_template_id'],
        'profile_general_smart_course');
    expect(packageRows.single['profile_template_name'], '通用数智课程画像模板');
    expect(packageRows.single['profile_template_version'], '1.0.0');

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

    final objectives = await db.query(
      'course_objectives',
      where: 'course_name = ?',
      whereArgs: ['课程知识图谱与数字孪生平台'],
      orderBy: 'idx ASC',
    );
    expect(objectives.length, 5);
    expect(objectives.last['name'], contains('教师端'));
    expect((objectives.last['weight'] as num).toDouble(), closeTo(0.20, 0.001));

    final resourceCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM resource_files WHERE course_id = ? AND source_type = ?',
      ['ckgdt', 'course_package'],
    ))
        .single['c'] as int;
    expect(resourceCount, greaterThan(20));

    final configResourceCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM resource_files WHERE course_id = ? AND source_type = ? AND file_path LIKE ?',
      ['ckgdt', 'course_package', 'data/ckgdt/配置/%'],
    ))
        .single['c'] as int;
    expect(configResourceCount, greaterThan(5));
  });

  test(
      'imports package into legacy version table and backfills template columns',
      () async {
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);
    await db.execute('''
      CREATE TABLE course_package_versions(
        course_id TEXT PRIMARY KEY,
        package_version TEXT,
        imported_at TEXT,
        manifest_hash TEXT,
        status TEXT,
        message TEXT
      )
    ''');

    final result = await CoursePackageLoader.instance.importCourse('ckgdt');

    expect(result.failed, isFalse);
    final columns =
        await db.rawQuery('PRAGMA table_info(course_package_versions)');
    final names = columns.map((row) => row['name']).toSet();
    expect(
        names,
        containsAll([
          'template_id',
          'template_version',
          'template_profile',
          'profile_template_id',
          'profile_template_name',
          'profile_template_version',
        ]));

    final packageRows = await db.query('course_package_versions');
    expect(packageRows.single['template_id'], 'universal_smart_course');
    expect(packageRows.single['template_version'], '1.0.0');
    expect(packageRows.single['template_profile'], 'general_smart_course');
    expect(packageRows.single['profile_template_id'],
        'profile_general_smart_course');
    expect(packageRows.single['profile_template_name'], '通用数智课程画像模板');
    expect(packageRows.single['profile_template_version'], '1.0.0');
  });

  test('imports generated local course package with resource contract',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('ckgdt_loader_pkg_test_');
    PathProviderPlatform.instance = _FakePathProvider(temp);
    final db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await createSchema(db);

    const syllabus = '''
# 《文学鉴赏》教学大纲

课程名称：文学鉴赏

## 一、课程目标
1. 能够理解文学作品的文本结构、主题意蕴和审美特征。
2. 能够运用细读、比较和批评方法开展作品分析。
3. 能够形成有证据支撑的审美判断和表达。

## 二、教学内容
### 第1章 文学鉴赏导论
### 第2章 诗歌意象与节奏
### 第3章 小说叙事与人物
### 第4章 戏剧冲突与舞台表达

## 三、考核方式
平时成绩占30%，研读报告成绩占30%，期末赏析论文成绩占40%。
''';
    final result = await CourseGenerationService().generateAll(
      courseName: '文学鉴赏',
      chapters: CourseGenerationService.extractChaptersFromSyllabus(syllabus),
      syllabusContent: syllabus,
      lazy: true,
    );
    await ResourcePersistenceService.instance.saveLocally(result);

    final imported =
        await CoursePackageLoader.instance.importCourse(result.courseId);

    expect(imported.failed, isFalse);
    expect(imported.courseUpdated, isTrue);
    expect(imported.objectivesImported, 4);
    expect(imported.labTasksImported, 4);
    expect(imported.homeworksImported, 4);
    expect(imported.graphsImported, greaterThanOrEqualTo(4));
    expect(imported.resourcesImported, greaterThan(20));
    expect(imported.templateProfile, 'literature_reading');
    expect(imported.profileTemplateId, 'profile_literature_reading');

    final courseRows = await db.query(
      'courses',
      where: 'id = ?',
      whereArgs: [result.courseId],
    );
    expect(courseRows.single['name'], '文学鉴赏');
    expect(courseRows.single['chapter_count'], 4);

    final tasks = await db.query(
      'lab_tasks',
      where: 'course_id = ? AND creator_id = ?',
      whereArgs: [result.courseId, 'course_package'],
      orderBy: 'id ASC',
    );
    expect(tasks.length, 4);
    expect(tasks.every((t) => !t['title'].toString().contains('实验')), isTrue);

    final homeworkCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM homeworks WHERE course_id = ?',
      [result.courseId],
    ))
        .single['c'] as int;
    expect(homeworkCount, 4);

    final objectives = await db.query(
      'course_objectives',
      where: 'course_name = ?',
      whereArgs: ['文学鉴赏'],
      orderBy: 'idx ASC',
    );
    expect(objectives.length, 4);
    expect(objectives.first['name'], isNot('课程目标1'));

    final graphRows = await db.query(
      'graphs',
      where: 'course_id = ?',
      whereArgs: [result.courseId],
    );
    expect(graphRows.map((g) => g['title']), contains('课程图谱'));
    expect(graphRows.map((g) => g['title']), contains('文本研读图谱'));

    final courseGraphId =
        graphRows.firstWhere((g) => g['title'] == '课程图谱')['id'].toString();
    final rootNodes = await db.query(
      'nodes',
      where: 'graph_id = ? AND (parent_id IS NULL OR parent_id = "")',
      whereArgs: [courseGraphId],
    );
    expect(rootNodes.map((n) => n['title']?.toString() ?? ''),
        anyElement(contains('文学鉴赏')));
    final edgeCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM edges WHERE graph_id = ?',
      [courseGraphId],
    ))
        .single['c'] as int;
    expect(edgeCount, greaterThan(0));

    final resources = await db.query(
      'resource_files',
      where: 'course_id = ? AND source_type = ?',
      whereArgs: [result.courseId, 'course_package'],
    );
    expect(
      resources.map((r) => r['file_path']?.toString() ?? ''),
      anyElement(contains('platform_readiness.json')),
    );
    expect(
      resources.map((r) => r['file_path']?.toString() ?? ''),
      anyElement(contains('archive_templates.json')),
    );
    expect(
      resources.map((r) => r['file_path']?.toString() ?? ''),
      everyElement(isNot(startsWith('data/${result.courseId}/'))),
    );

    final packageRows = await db.query(
      'course_package_versions',
      where: 'course_id = ?',
      whereArgs: [result.courseId],
    );
    expect(packageRows.single['template_profile'], 'literature_reading');
    expect(
      packageRows.single['profile_template_id'],
      'profile_literature_reading',
    );

    final archiveTemplate = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'final',
      documentType: 'final_archive_catalog',
      label: '课程档案袋目录',
    );
    expect(archiveTemplate, isNotNull);
    expect(archiveTemplate!.sourcePath, contains(result.courseId));
    expect(archiveTemplate.sourcePath, contains('归档'));
    expect(archiveTemplate.content, contains('文学鉴赏'));

    await temp.delete(recursive: true);
  });
}
