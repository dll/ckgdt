import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/models/ai_config_model.dart';
import 'package:knowledge_graph_app/services/courseware_service.dart';
import 'package:knowledge_graph_app/services/lesson_plan_quality_gate.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_db.dart';

class _RealHttpOverrides extends HttpOverrides {}

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
    HttpOverrides.global = _RealHttpOverrides();
    tempRoot = await Directory.systemTemp.createTemp('kg_real_ai_static_');
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
        await db.execute('''
          CREATE TABLE ai_trial_settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trial_enabled INTEGER DEFAULT 0,
            trial_max_calls INTEGER DEFAULT 0,
            trial_max_tokens INTEGER DEFAULT 0,
            updated_at TEXT
          )
        ''');
        await db.insert('ai_trial_settings', {
          'id': 1,
          'trial_enabled': 0,
          'trial_max_calls': 0,
          'trial_max_tokens': 0,
          'updated_at': DateTime.now().toIso8601String(),
        });
        await db.execute('''
          CREATE TABLE ai_chat_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            agent_id TEXT,
            skill_id TEXT,
            role TEXT,
            content TEXT,
            created_at TEXT,
            tokens_used INTEGER DEFAULT 0,
            prompt_tokens INTEGER DEFAULT 0,
            completion_tokens INTEGER DEFAULT 0,
            provider TEXT,
            model TEXT,
            user_id TEXT,
            course_id TEXT
          )
        ''');
      },
    );
    DatabaseHelper.databaseForTest = db;
  });

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    DatabaseHelper.databaseForTest = null;
    HttpOverrides.global = null;
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'real AI produces a teachable lesson plan',
    () async {
      final keyFile = File('assets/ai_key.txt');
      final apiKey = keyFile.existsSync()
          ? (await keyFile.readAsString()).trim()
          : '';
      if (apiKey.isEmpty) {
        markTestSkipped('assets/ai_key.txt not found');
        return;
      }

      final service = CoursewareService();
      final aiConfig = AiConfigModel(
        provider: 'deepseek',
        model: 'deepseek-chat',
        apiKey: apiKey,
        baseUrl: 'https://api.deepseek.com',
        maxTokens: 4096,
        timeout: 180,
      );

      final plan = await service.generateLessonPlan(
        topic: '知识图谱概述',
        chapter: '第1章 知识图谱概述',
        classHours: 2,
        additionalRequirements:
            '面向计算机专业本科生，要求包含真实案例、代码示例和分层作业',
        configOverride: aiConfig,
      );

      expect(plan['title'], isNotEmpty);
      final sections = plan['sections'] as List;
      expect(sections.length, greaterThanOrEqualTo(3));
      var totalContent = 0;
      for (final s in sections) {
        totalContent += (s as Map)['content']?.toString().length ?? 0;
      }
      expect(totalContent, greaterThan(400));
      expect(LessonPlanQualityGate.score(plan), greaterThanOrEqualTo(60));
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );

  test(
    'real AI + quality gate produces PDF, PPTX and slide images',
    () async {
      final keyFile = File('assets/ai_key.txt');
      final apiKey = keyFile.existsSync()
          ? (await keyFile.readAsString()).trim()
          : '';
      if (apiKey.isEmpty) {
        markTestSkipped('assets/ai_key.txt not found');
        return;
      }

      final service = CoursewareService();
      final aiConfig = AiConfigModel(
        provider: 'deepseek',
        model: 'deepseek-chat',
        apiKey: apiKey,
        baseUrl: 'https://api.deepseek.com',
        maxTokens: 4096,
        timeout: 180,
      );

      final plan = await service.generateLessonPlan(
        topic: '知识图谱概述',
        chapter: '第1章 知识图谱概述',
        classHours: 2,
        additionalRequirements:
            '面向计算机专业本科生，要求包含真实案例、代码示例和分层作业',
        configOverride: aiConfig,
      );

      final umlImages = <Uint8List>[];
      try {
        final pumlResults =
            await service.generateAllPuml(plan, configOverride: aiConfig);
        for (final r in pumlResults) {
          final png = await service.renderPumlToPng(r['puml'] ?? '');
          if (png != null && png.isNotEmpty) umlImages.add(png);
        }
      } catch (_) {}

      final outDir = '${tempRoot.path}/out';
      final pdfPath = await service.generateEnhancedPdf(
        lessonPlan: plan,
        outputDir: '$outDir/PDF',
        umlImages: umlImages.isEmpty ? null : umlImages,
      );
      expect(pdfPath, isNotNull);
      expect(File(pdfPath!).lengthSync(), greaterThan(4096));

      final slides = service.lessonPlanToSlides(plan);
      expect(slides.length, greaterThan(4));

      final pptxPath = await service.generatePptx(
        title: '知识图谱概述',
        slides: slides,
        chapter: '第1章 知识图谱概述',
        outputDir: '$outDir/PPTX',
      );
      expect(pptxPath, isNotNull);
      expect(File(pptxPath!).lengthSync(), greaterThan(4096));

      final slideImages = await service.generateSlideImages(
        title: '知识图谱概述',
        slides: slides,
        outputDir: '$outDir/slides',
        chapter: '第1章 知识图谱概述',
      );
      expect(slideImages.length, greaterThanOrEqualTo(slides.length + 2));
      for (final path in slideImages) {
        expect(File(path).lengthSync(), greaterThan(4096));
      }

    },
    timeout: const Timeout(Duration(seconds: 300)),
  );
}
