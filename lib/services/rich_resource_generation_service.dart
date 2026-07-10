import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../core/error_handler.dart';
import '../data/local/ai_config_dao.dart';
import '../data/models/ai_config_model.dart';
import '../data/local/database_helper.dart';
import 'courseware_service.dart';
import 'tts_service.dart';
import 'video_service.dart';

/// 高质量资源生成服务
/// 以教案为驱动，生成可直接授课的 PDF / PPTX / MP4
class RichResourceGenerationService {
  final CoursewareService _courseware;
  final TtsService _tts;
  final VideoService _video;

  RichResourceGenerationService({
    CoursewareService? courseware,
    TtsService? tts,
    VideoService? video,
  })  : _courseware = courseware ?? CoursewareService(),
        _tts = tts ?? TtsService(),
        _video = video ?? VideoService();

  /// 生成进度回调
  void Function(String fileType, double progress)? onProgress;

  /// 从数据库查询课程名称
  Future<String> _lookupCourseName(String courseId) async {
    final db = await DatabaseHelper.instance.database;
    final courseRows = await db.query(
      'courses',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [courseId],
    );
    return courseRows.isNotEmpty
        ? (courseRows.first['name']?.toString() ?? '')
        : '';
  }

  /// 为单个章节生成高质量资源
  /// 返回 { 'pdf': path, 'ppt': path, 'video': path }
  Future<Map<String, String>> generateForChapter({
    required String courseId,
    required String chapterTitle,
    required String chapterShortTitle,
    String description = '',
    List<String> objectives = const [],
    List<String> keyPoints = const [],
    List<String> difficultPoints = const [],
    String sourceType = 'preset',
    String outputBaseDir = '',
    String? courseName,
    AiConfigModel? aiConfig,
  }) async {
    final result = <String, String>{};

    // 1. 课程名称
    final effectiveCourseName = courseName ?? await _lookupCourseName(courseId);

    // 2. 生成教案
    onProgress?.call('plan', 0.0);
    final effectiveAiConfig = aiConfig ?? await AiConfigDao().getConfig();
    final additional = StringBuffer();
    additional.writeln('课程：$effectiveCourseName');
    additional.writeln('章节描述：$description');
    if (objectives.isNotEmpty) {
      additional.writeln('教学目标：${objectives.join('、')}');
    }
    if (keyPoints.isNotEmpty) {
      additional.writeln('教学重点：${keyPoints.join('、')}');
    }
    if (difficultPoints.isNotEmpty) {
      additional.writeln('教学难点：${difficultPoints.join('、')}');
    }
    additional.writeln('请生成内容详实、可直接授课的教案，包含完整教学环节、示例、实践任务和评价方式。');

    final lessonPlan = await _courseware.generateLessonPlan(
      topic: chapterShortTitle,
      chapter: chapterTitle,
      classHours: 2,
      additionalRequirements: additional.toString(),
      configOverride: effectiveAiConfig,
    );
    onProgress?.call('plan', 1.0);

    // 3. 生成 UML 图（用于 PDF 增强）
    final List<Uint8List> umlImages = [];
    try {
      final pumlResults = await _courseware.generateAllPuml(
        lessonPlan,
        configOverride: effectiveAiConfig,
      );
      for (final r in pumlResults) {
        final png = await _courseware.renderPumlToPng(r['puml'] ?? '');
        if (png != null && png.isNotEmpty) umlImages.add(png);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'RichResourceGen.uml', stack: st);
    }

    // 4. PDF
    onProgress?.call('pdf', 0.0);
    try {
      final pdfDir = p.join(outputBaseDir, 'PDF');
      Directory(pdfDir).createSync(recursive: true);
      final pdfPath = await _courseware.generateEnhancedPdf(
        lessonPlan: lessonPlan,
        outputDir: pdfDir,
        umlImages: umlImages.isEmpty ? null : umlImages,
      );
      if (pdfPath != null && pdfPath.isNotEmpty) {
        result['pdf'] = pdfPath;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'RichResourceGen.pdf', stack: st);
    }
    onProgress?.call('pdf', 1.0);

    // 5. PPTX
    onProgress?.call('ppt', 0.0);
    final slides = _courseware.lessonPlanToSlides(lessonPlan);
    try {
      final hasPptx = await _courseware.isPythonPptxInstalled();
      if (hasPptx && slides.isNotEmpty) {
        final pptxDir = p.join(outputBaseDir, '课件');
        Directory(pptxDir).createSync(recursive: true);
        final pptxPath = await _courseware.generatePptx(
          title: chapterShortTitle,
          slides: slides,
          chapter: chapterTitle,
          outputDir: pptxDir,
        );
        if (pptxPath != null && pptxPath.isNotEmpty) {
          result['ppt'] = pptxPath;
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'RichResourceGen.pptx', stack: st);
    }
    onProgress?.call('ppt', 1.0);

    // 6. 视频
    onProgress?.call('video', 0.0);
    try {
      final hasTts = await _tts.isEdgeTtsInstalled();
      final hasFfmpeg = await _video.isFfmpegInstalled();
      if (hasTts && hasFfmpeg && slides.isNotEmpty) {
        final scripts = await _courseware.generateNarrationScriptsForSlides(
          title: chapterShortTitle,
          chapter: chapterTitle,
          slides: slides,
          configOverride: effectiveAiConfig,
        );
        if (scripts.isNotEmpty) {
          final sessionDir = await _courseware.createSessionDir();
          final audioDir = p.join(sessionDir, 'audio');
          final audioPaths = await _tts.generateBatchAudio(
            scripts: scripts,
            outputDir: audioDir,
          );

          final slidesDir = p.join(sessionDir, 'slides');
          final slideImages = await _courseware.generateSlideImages(
            title: chapterShortTitle,
            slides: slides,
            outputDir: slidesDir,
            chapter: chapterTitle,
          );

          if (slideImages.isNotEmpty) {
            final videoDir = p.join(outputBaseDir, '视频');
            Directory(videoDir).createSync(recursive: true);
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final safeTitle =
                chapterShortTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
            final rawPath = p.join(videoDir, '${safeTitle}_raw_$timestamp.mp4');
            final finalPath = p.join(videoDir, '${safeTitle}_$timestamp.mp4');

            final success = await _video.generateVideo(
              slides: slideImages,
              audios: audioPaths,
              outputPath: rawPath,
              clipDirPath: p.join(sessionDir, 'video_clips'),
            );

            if (success) {
              final narrations =
                  scripts.map((s) => s['narration'] ?? '').toList();
              final srtPath = p.join(videoDir, '${safeTitle}_$timestamp.srt');
              final srtResult = await _video.generateSrt(
                narrations: narrations,
                audioPaths: audioPaths,
                outputPath: srtPath,
              );

              String videoPath = rawPath;
              if (srtResult != null) {
                final burned = await _video.burnSubtitles(
                  videoPath: rawPath,
                  srtPath: srtPath,
                  outputPath: finalPath,
                );
                if (burned != null) {
                  try {
                    File(rawPath).deleteSync();
                  } catch (_) {}
                  videoPath = burned;
                } else {
                  try {
                    File(rawPath).renameSync(finalPath);
                    videoPath = finalPath;
                  } catch (_) {
                    videoPath = rawPath;
                  }
                }
              } else {
                try {
                  File(rawPath).renameSync(finalPath);
                  videoPath = finalPath;
                } catch (_) {
                  videoPath = rawPath;
                }
              }

              result['video'] = videoPath;
            }
          }
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'RichResourceGen.video', stack: st);
    }
    onProgress?.call('video', 1.0);

    return result;
  }
}
