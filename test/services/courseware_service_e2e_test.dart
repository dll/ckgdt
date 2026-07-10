import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/services/courseware_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_db.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getTemporaryPath() async => root.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    setupTestSqflite();
    tempRoot = await Directory.systemTemp.createTemp('kg_courseware_e2e_');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot);

    final db = await openDatabase(
      ':memory:',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE generated_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            course_id TEXT,
            title TEXT NOT NULL,
            type TEXT NOT NULL,
            file_path TEXT,
            content TEXT,
            chapter TEXT,
            created_at TEXT,
            size INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE courses (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            chapter_count INTEGER DEFAULT 6,
            chapters TEXT,
            is_active INTEGER DEFAULT 0,
            created_at TEXT
          )
        ''');
        await db.insert('courses', {
          'id': 'test-course',
          'name': '测试课程',
          'description': '',
          'chapter_count': 3,
          'chapters': '["第一章 引言", "第二章 知识建模", "第三章 应用"]',
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
        });
      },
    );
    DatabaseHelper.databaseForTest = db;
  });

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    DatabaseHelper.databaseForTest = null;
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  final sampleSlides = [
    {
      'title': '什么是知识图谱',
      'content': '知识图谱是一种用于描述实体及其关系的语义网络。',
      'type': 'content',
    },
    {
      'title': '知识图谱的组成',
      'content': '实体\\n关系\\n属性',
      'type': 'content',
    },
    {
      'title': '应用场景',
      'content': '智能问答、推荐系统、语义搜索',
      'type': 'content',
    },
  ];

  test('generatePptx creates a non-empty PPTX file', () async {
    final service = CoursewareService();
    final outputDir = Directory('${tempRoot.path}/output');

    final result = await service.generatePptx(
      title: '测试课程',
      slides: sampleSlides,
      chapter: '第一章 引言',
      outputDir: outputDir.path,
    );

    expect(result, isNotNull);
    final outputFile = File(result!);
    expect(outputFile.existsSync(), isTrue);
    expect(outputFile.lengthSync(), greaterThan(1024));
  });

  test('generateEnhancedPdf creates a non-empty PDF file', () async {
    final service = CoursewareService();
    final outputDir = Directory('${tempRoot.path}/pdf');

    final result = await service.generateEnhancedPdf(
      lessonPlan: {
      'title': '测试课程',
      'chapter': '第一章 测试',
      'classHours': 2,
      'objectives': ['掌握核心概念', '能够动手实践'],
      'keyPoints': ['核心概念'],
      'difficulties': ['综合应用'],
      'sections': [
        {
          'title': '引入',
          'duration': '10分钟',
          'content': '通过生活化案例引出学习价值。\n1. 为什么要学习？\n2. 本节课目标。',
          'activities': '讲授+讨论',
          'notes': '用案例吸引注意',
        },
        {
          'title': '核心讲解',
          'duration': '30分钟',
          'content': '系统讲解核心概念与步骤。\n1. 定义。\n2. 工作流程。\n3. 最小示例。\n4. 常见误区。',
          'activities': '讲授+演示',
          'codeExample': 'print("hello")',
          'notes': '强调关键步骤',
        },
      ],
      'experiments': [
        {
          'name': '动手练习',
          'objective': '加深理解',
          'steps': ['明确任务', '完成操作', '记录结果'],
          'deliverables': '实验报告',
        }
      ],
      'umlDiagrams': [],
      'homework': '基础题+提高题',
      'references': ['教材'],
    },
      outputDir: outputDir.path,
    );

    expect(result, isNotNull);
    final outputFile = File(result!);
    expect(outputFile.existsSync(), isTrue);
    expect(outputFile.lengthSync(), greaterThan(1024));
  });

  test('generateSlideImages creates cover, slide and end PNGs', () async {
    final service = CoursewareService();
    final outputDir = Directory('${tempRoot.path}/slides');

    final images = await service.generateSlideImages(
      title: '测试课程',
      slides: sampleSlides,
      outputDir: outputDir.path,
      chapter: '第一章 引言',
    );

    expect(images.length, greaterThanOrEqualTo(sampleSlides.length + 2));
    for (final path in images) {
      final file = File(path);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1024));
    }
  });
}
