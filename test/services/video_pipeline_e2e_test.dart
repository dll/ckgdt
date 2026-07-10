import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/services/courseware_service.dart';
import 'package:knowledge_graph_app/services/tts_service.dart';
import 'package:knowledge_graph_app/services/video_service.dart';
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
    tempRoot = await Directory.systemTemp.createTemp('kg_video_e2e_');
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
      'content': '知识图谱是一种描述实体及其关系的语义网络。',
      'type': 'content',
    },
    {
      'title': '知识图谱的组成',
      'content': '实体、关系、属性',
      'type': 'content',
    },
  ];

  final scripts = [
    {'slide': '封面', 'narration': '同学们好，今天我们来学习知识图谱。'},
    {'slide': '组成', 'narration': '知识图谱由实体、关系和属性组成。'},
  ];

  test(
    'TTS + ffmpeg video pipeline produces a burned-subtitle MP4',
    () async {
      final courseware = CoursewareService();
      final tts = TtsService();
      final video = VideoService();

      // 1. 生成幻灯片图片
      final slidesDir = Directory('${tempRoot.path}/slides');
      final slideImages = await courseware.generateSlideImages(
        title: '测试课程',
        slides: sampleSlides,
        outputDir: slidesDir.path,
        chapter: '第一章 引言',
      );
      expect(slideImages.length, greaterThanOrEqualTo(sampleSlides.length + 2));

      // 2. 生成 TTS 音频
      final audioDir = Directory('${tempRoot.path}/audio');
      final audioPaths = await tts.generateBatchAudio(
        scripts: scripts,
        outputDir: audioDir.path,
      );
      expect(audioPaths.length, scripts.length);
      for (final path in audioPaths) {
        expect(File(path).existsSync(), isTrue);
        expect(File(path).lengthSync(), greaterThan(1024));
      }

      // 3. 合成视频
      final videoPath = '${tempRoot.path}/output/test_video.mp4';
      Directory('${tempRoot.path}/output').createSync(recursive: true);
      final videoSuccess = await video.generateVideo(
        slides: slideImages,
        audios: audioPaths,
        outputPath: videoPath,
      );
      expect(videoSuccess, isTrue);
      expect(File(videoPath).existsSync(), isTrue);
      expect(File(videoPath).lengthSync(), greaterThan(1024));

      // 4. 生成并烧录字幕
      final srtPath = '${tempRoot.path}/output/test_video.srt';
      final narrations = scripts.map((s) => s['narration']!).toList();
      final srtResult = await video.generateSrt(
        narrations: narrations,
        audioPaths: audioPaths,
        outputPath: srtPath,
      );
      expect(srtResult, isNotNull);
      expect(File(srtPath).existsSync(), isTrue);

      final burnedPath = '${tempRoot.path}/output/test_video_burned.mp4';
      final burnedResult = await video.burnSubtitles(
        videoPath: videoPath,
        srtPath: srtPath,
        outputPath: burnedPath,
      );
      expect(burnedResult, isNotNull);
      expect(File(burnedPath).existsSync(), isTrue);
      expect(File(burnedPath).lengthSync(), greaterThan(1024));
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
