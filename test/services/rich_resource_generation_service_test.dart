import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:knowledge_graph_app/data/models/ai_config_model.dart';
import 'package:knowledge_graph_app/services/courseware_service.dart';
import 'package:knowledge_graph_app/services/rich_resource_generation_service.dart';
import 'package:knowledge_graph_app/services/tts_service.dart';
import 'dart:typed_data';
import 'package:knowledge_graph_app/services/video_service.dart';

class _FakeCoursewareService extends CoursewareService {
  final Map<String, dynamic> lessonPlan;
  final String? pdfPath;
  final String? pptxPath;
  final List<Map<String, String>> scripts;
  final List<String> slideImages;

  _FakeCoursewareService({
    required this.lessonPlan,
    this.pdfPath,
    this.pptxPath,
    required this.scripts,
    required this.slideImages,
  });

  @override
  Future<Map<String, dynamic>> generateLessonPlan({
    required String topic,
    String? chapter,
    int classHours = 2,
    String? additionalRequirements,
    AiConfigModel? configOverride,
  }) async =>
      lessonPlan;

  @override
  Future<List<Map<String, String>>> generateAllPuml(
    Map<String, dynamic> lessonPlan, {
    AiConfigModel? configOverride,
  }) async =>
      [];

  @override
  Future<String?> generateEnhancedPdf({
    required Map<String, dynamic> lessonPlan,
    List<Uint8List>? umlImages,
    String? outputDir,
  }) async =>
      pdfPath;

  @override
  Future<String?> generatePptx({
    required String title,
    required List<Map<String, dynamic>> slides,
    String? chapter,
    String? outputDir,
  }) async =>
      pptxPath;

  @override
  Future<List<Map<String, String>>> generateNarrationScripts(
    Map<String, dynamic> lessonPlan, {
    AiConfigModel? configOverride,
  }) async =>
      scripts;

  @override
  Future<List<Map<String, String>>> generateNarrationScriptsForSlides({
    required String title,
    required String chapter,
    required List<Map<String, dynamic>> slides,
    AiConfigModel? configOverride,
  }) async =>
      scripts;

  @override
  Future<List<String>> generateSlideImages({
    required String title,
    required List<Map<String, dynamic>> slides,
    required String outputDir,
    String? chapter,
  }) async =>
      slideImages;

  @override
  Future<String> createSessionDir() async => '/tmp/session';

  @override
  Future<bool> isPythonPptxInstalled() async => true;

  @override
  List<Map<String, dynamic>> lessonPlanToSlides(
          Map<String, dynamic> lessonPlan) =>
      [
        {
          'title': 'Slide 1',
          'bullets': ['point']
        },
      ];
}

class _FakeTtsService extends TtsService {
  final List<String> audioPaths;

  _FakeTtsService({required this.audioPaths});

  @override
  Future<bool> isEdgeTtsInstalled() async => true;

  @override
  Future<List<String>> generateBatchAudio({
    required List<Map<String, String>> scripts,
    required String outputDir,
    String voice = TtsService.defaultVoice,
    String rate = TtsService.defaultRate,
    void Function(int current, int total)? onProgress,
  }) async =>
      audioPaths;
}

class _FakeVideoService extends VideoService {
  final bool generateVideoSuccess;
  final String? srtPath;
  final String? burnedVideoPath;

  _FakeVideoService({
    this.generateVideoSuccess = true,
    this.srtPath,
    this.burnedVideoPath,
  });

  @override
  Future<bool> isFfmpegInstalled() async => true;

  @override
  Future<bool> generateVideo({
    required List<String> slides,
    required List<String> audios,
    required String outputPath,
    String? clipDirPath,
    double defaultDuration = 5.0,
    void Function(int current, int total, String message)? onProgress,
  }) async =>
      generateVideoSuccess;

  @override
  Future<String?> generateSrt({
    required List<String> narrations,
    required List<String> audioPaths,
    required String outputPath,
    double defaultDuration = 5.0,
    double extraDuration = 1.5,
  }) async =>
      srtPath;

  @override
  Future<String?> burnSubtitles({
    required String videoPath,
    required String srtPath,
    required String outputPath,
  }) async =>
      burnedVideoPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aiConfig = AiConfigModel(
    provider: 'test',
    model: 'test-model',
    baseUrl: 'http://localhost',
    apiKey: 'key',
  );

  test('generateForChapter returns pdf, pptx and video paths', () async {
    const base = '/tmp/course';
    final courseware = _FakeCoursewareService(
      lessonPlan: {
        'title': 'Test Lesson',
        'chapter': 'Chapter 1',
        'objectives': ['obj1'],
      },
      pdfPath: p.join(base, 'PDF', 'test.pdf'),
      pptxPath: p.join(base, '课件', 'test.pptx'),
      scripts: [
        {'slide': 'cover', 'narration': 'hello'},
      ],
      slideImages: [p.join('/tmp', 'slides', '001.png')],
    );
    final tts =
        _FakeTtsService(audioPaths: [p.join('/tmp', 'audio', '01.mp3')]);
    final video = _FakeVideoService(
      srtPath: p.join(base, '视频', 'test.srt'),
      burnedVideoPath: p.join(base, '视频', 'test_burned.mp4'),
    );

    final service = RichResourceGenerationService(
      courseware: courseware,
      tts: tts,
      video: video,
    );

    final paths = await service.generateForChapter(
      courseId: 'c1',
      chapterTitle: '第1章 测试',
      chapterShortTitle: '测试',
      description: 'desc',
      objectives: ['o1'],
      keyPoints: ['k1'],
      difficultPoints: ['d1'],
      outputBaseDir: base,
      courseName: 'TestCourse',
      aiConfig: aiConfig,
    );

    expect(paths['pdf'], p.join(base, 'PDF', 'test.pdf'));
    expect(paths['ppt'], p.join(base, '课件', 'test.pptx'));
    expect(paths['video'], p.join(base, '视频', 'test_burned.mp4'));
  });

  test('generateForChapter returns only pdf when video env missing', () async {
    const base = '/tmp/course';
    final courseware = _FakeCoursewareService(
      lessonPlan: {
        'title': 'Test Lesson',
        'chapter': 'Chapter 1',
      },
      pdfPath: p.join(base, 'PDF', 'test.pdf'),
      pptxPath: p.join(base, '课件', 'test.pptx'),
      scripts: [],
      slideImages: [],
    );
    final tts = _FakeTtsService(audioPaths: []);
    final video = _FakeVideoService(generateVideoSuccess: false);

    final service = RichResourceGenerationService(
      courseware: courseware,
      tts: tts,
      video: video,
    );

    final paths = await service.generateForChapter(
      courseId: 'c1',
      chapterTitle: '第1章 测试',
      chapterShortTitle: '测试',
      outputBaseDir: base,
      courseName: 'TestCourse',
      aiConfig: aiConfig,
    );

    expect(paths['pdf'], p.join(base, 'PDF', 'test.pdf'));
    expect(paths['ppt'], p.join(base, '课件', 'test.pptx'));
    expect(paths.containsKey('video'), isFalse);
  });
}
