import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/models/ai_config_model.dart';
import 'package:knowledge_graph_app/services/courseware_service.dart';
import 'package:knowledge_graph_app/services/tts_service.dart';
import 'package:knowledge_graph_app/services/video_service.dart';
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
    tempRoot = await Directory.systemTemp.createTemp('kg_real_ai_video_');
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
    'real AI slide images + TTS + ffmpeg produce a burned-subtitle MP4',
    () async {
      final keyFile = File('assets/ai_key.txt');
      final apiKey = keyFile.existsSync()
          ? (await keyFile.readAsString()).trim()
          : '';
      if (apiKey.isEmpty) {
        markTestSkipped('assets/ai_key.txt not found');
        return;
      }

      final courseware = CoursewareService();
      final aiConfig = AiConfigModel(
        provider: 'deepseek',
        model: 'deepseek-chat',
        apiKey: apiKey,
        baseUrl: 'https://api.deepseek.com',
        maxTokens: 4096,
        timeout: 180,
      );

      final plan = await courseware.generateLessonPlan(
        topic: '知识图谱概述',
        chapter: '第1章 知识图谱概述',
        classHours: 2,
        additionalRequirements:
            '面向计算机专业本科生，要求包含真实案例、代码示例和分层作业',
        configOverride: aiConfig,
      );

      final slidesDir = Directory('${tempRoot.path}/slides');
      final slides = courseware.lessonPlanToSlides(plan);
      final slideImages = await courseware.generateSlideImages(
        title: '知识图谱概述',
        slides: slides,
        outputDir: slidesDir.path,
        chapter: '第1章 知识图谱概述',
      );
      expect(slideImages.length, greaterThanOrEqualTo(slides.length + 2));

      final scripts = <Map<String, String>>[];
      scripts.add({'slide': '封面', 'narration': '同学们好，今天我们来学习知识图谱概述。'});
      for (var i = 0; i < slides.length; i++) {
        final title = (slides[i]['title'] as String?) ?? '第${i + 1}页';
        scripts.add({
          'slide': title,
          'narration': '接下来我们看$title。',
        });
      }
      scripts.add({'slide': '结束页', 'narration': '本节内容到此结束，谢谢大家。'});

      final tts = TtsService();
      final hasTts = await tts.isEdgeTtsInstalled();
      if (!hasTts) {
        markTestSkipped('edge-tts not installed');
        return;
      }
      final audioDir = Directory('${tempRoot.path}/audio');
      final audioPaths = await tts.generateBatchAudio(
        scripts: scripts,
        outputDir: audioDir.path,
      );
      expect(audioPaths.length, scripts.length);

      final video = VideoService();
      final hasFfmpeg = await video.isFfmpegInstalled();
      if (!hasFfmpeg) {
        markTestSkipped('ffmpeg not installed');
        return;
      }
      final outDir = Directory('${tempRoot.path}/output');
      outDir.createSync(recursive: true);
      final rawPath = '${outDir.path}/video_raw.mp4';
      final videoOk = await video.generateVideo(
        slides: slideImages,
        audios: audioPaths,
        outputPath: rawPath,
      );
      expect(videoOk, isTrue);
      expect(File(rawPath).existsSync(), isTrue);

      final narrations = scripts.map((s) => s['narration']!).toList();
      final srtPath = '${outDir.path}/video.srt';
      final srtResult = await video.generateSrt(
        narrations: narrations,
        audioPaths: audioPaths,
        outputPath: srtPath,
      );
      expect(srtResult, isNotNull);

      final burnedPath = '${outDir.path}/video_burned.mp4';
      final burnedResult = await video.burnSubtitles(
        videoPath: rawPath,
        srtPath: srtPath,
        outputPath: burnedPath,
      );
      expect(burnedResult, isNotNull);
      expect(File(burnedPath).existsSync(), isTrue);
      expect(File(burnedPath).lengthSync(), greaterThan(4096));

    },
    timeout: const Timeout(Duration(seconds: 300)),
  );
}
