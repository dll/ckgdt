import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../core/error_handler.dart';
import 'ai_service.dart';
import 'lecture_deck_service.dart';
import 'ppt_export_service.dart';
import 'video_service.dart';
import 'slide_image_generator.dart';

class LectureVideoSegment {
  final String title;
  final String narration;
  final String visualHint;
  final int durationSeconds;
  final int order;
  final List<String> bullets;

  const LectureVideoSegment({
    required this.title,
    this.narration = '',
    this.visualHint = '',
    this.durationSeconds = 30,
    this.order = 0,
    this.bullets = const [],
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'narration': narration,
        'visual_hint': visualHint,
        'duration_seconds': durationSeconds,
        'order': order,
        'bullets': bullets,
      };

  static LectureVideoSegment fromJson(Map<String, dynamic> m, int i) =>
      LectureVideoSegment(
        title: m['title'] as String? ?? '段落 ${i + 1}',
        narration: m['narration'] as String? ?? '',
        visualHint: m['visual_hint'] as String? ?? '',
        durationSeconds: m['duration_seconds'] as int? ?? 30,
        order: i + 1,
        bullets: (m['bullets'] as List?)
                ?.map((v) => '$v')
                .where((v) => v.trim().isNotEmpty)
                .take(5)
                .toList() ??
            const [],
      );
}

class LectureVideoService {
  final AiService _ai = AiService();
  final VideoService _video = VideoService();
  final SlideImageGenerator _slideGen = SlideImageGenerator();
  final LectureDeckService _deck = LectureDeckService();

  Future<List<LectureVideoSegment>> generateScript({
    required String lectureContent,
    required String courseName,
  }) async {
    final prompt = '''
根据以下说课文档，生成一份专业的说课视频脚本，分段落输出 JSON 数组。

要求：
- 每个段落包含 title（标题）、bullets（PPT页要点数组，3-5条，每条12-28字，不含Markdown符号）、narration（旁白，口语化，100-200字）、duration_seconds（时长秒数，25-40）
- 覆盖：开场→课程定位→教学内容→教学方法→实践→考核→教改→结语
- 开场以"尊敬的各位评委老师，大家好"开头
- 总时长 4-8 分钟
- 必须基于具体内容，不使用通用模板
- bullets 是给现场汇报 PPT 画面用的简洁关键词，不要把整段正文、表格、Markdown 原文放进 bullets
- 仅返回 JSON 数组，不要其他文字

说课文档：
$lectureContent
''';

    final raw = await _ai.chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: '你是一位教学督导专家，擅长为教师说课生成视频脚本。请输出纯净 JSON。',
    );

    final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (match == null) return _fallbackSegments();
    try {
      final list = jsonDecode(match.group(0)!) as List;
      return list
          .asMap()
          .entries
          .map((e) => LectureVideoSegment.fromJson(
              e.value as Map<String, dynamic>, e.key))
          .toList();
    } catch (e) {
      swallow(e, tag: 'LectureVideoService.parse');
      return _fallbackSegments();
    }
  }

  List<LectureVideoSegment> _fallbackSegments() {
    return [
      const LectureVideoSegment(
          order: 1,
          title: '开场',
          bullets: ['课程主题与说课对象', '课程建设总体思路', '汇报结构清晰展开'],
          narration: '尊敬的各位评委老师，大家好。今天我说课的主题是本课程的教学设计与实施成效。',
          durationSeconds: 20),
      const LectureVideoSegment(
          order: 2,
          title: '课程定位',
          bullets: ['面向专业人才培养', '支撑课程目标达成', '强调能力递进培养'],
          narration: '本课程面向相关专业学生，注重理论与实践相结合。',
          durationSeconds: 30),
      const LectureVideoSegment(
          order: 3,
          title: '教学内容',
          bullets: ['章节体系循序渐进', '核心知识突出重点', '任务驱动贯穿教学'],
          narration: '课程内容涵盖多个章节，系统全面。',
          durationSeconds: 40),
      const LectureVideoSegment(
          order: 4,
          title: '教学方法',
          bullets: ['案例教学促进理解', '课堂互动提升参与', '平台数据支持改进'],
          narration: '采用项目驱动、案例教学等多种教学方法。',
          durationSeconds: 30),
      const LectureVideoSegment(
          order: 5,
          title: '实践环节',
          bullets: ['实践任务贴合课程', '过程证据持续沉淀', '成果评价强调应用'],
          narration: '课程设置了多个实践项目。',
          durationSeconds: 30),
      const LectureVideoSegment(
          order: 6,
          title: '考核评价',
          bullets: ['过程评价结合终评', '量规评价公开透明', '支撑持续改进闭环'],
          narration: '采用过程性评价与终结性评价相结合的方式。',
          durationSeconds: 25),
      const LectureVideoSegment(
          order: 7,
          title: '教学改革',
          bullets: ['数据驱动教学改进', '资源建设持续迭代', '智能助手辅助教学'],
          narration: '课程团队持续进行教学改革与创新。',
          durationSeconds: 25),
      const LectureVideoSegment(
          order: 8,
          title: '结语',
          bullets: ['总结课程建设成效', '欢迎专家批评指导', '持续提升课程质量'],
          narration: '以上就是我的说课内容，恳请各位评委老师批评指正。谢谢。',
          durationSeconds: 15),
    ];
  }

  List<String> _extractBullets(String lectureContent, String sectionTitle) {
    final lines = lectureContent.split('\n');
    final sectionHeaders = <int>{};
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('## ')) sectionHeaders.add(i);
    }

    int? bestStart;
    int? bestEnd;
    for (final start in sectionHeaders) {
      final header = lines[start].trim().replaceAll('## ', '').trim();
      if (header.contains(sectionTitle) || sectionTitle.contains(header)) {
        bestStart = start;
        break;
      }
    }
    if (bestStart == null) return [];

    for (final end in sectionHeaders) {
      if (end > bestStart) {
        bestEnd = end;
        break;
      }
    }

    final bullets = <String>[];
    final end = bestEnd ?? lines.length;
    for (var i = bestStart + 1; i < end; i++) {
      final line = lines[i].trim();
      if (line.startsWith('- ') || line.startsWith('* ')) {
        final bullet =
            _cleanSlideText(line.replaceFirst(RegExp(r'^[-*]\s+'), '').trim());
        if (bullet.isNotEmpty && bullet.length < 100) {
          bullets.add(bullet);
        }
      }
    }

    return bullets.take(6).toList();
  }

  List<String> _slideBulletsFor(
      LectureVideoSegment segment, String lectureContent) {
    final aiBullets = segment.bullets
        .map(_cleanSlideText)
        .where((v) => v.isNotEmpty)
        .take(5)
        .toList();
    if (aiBullets.length >= 3) return aiBullets;

    final sectionBullets = _extractBullets(lectureContent, segment.title)
        .map(_cleanSlideText)
        .where((v) => v.isNotEmpty)
        .take(5)
        .toList();
    if (sectionBullets.length >= 3) return sectionBullets;

    return _fallbackBulletsFromNarration(segment.narration);
  }

  List<String> _fallbackBulletsFromNarration(String narration) {
    final sentences = narration
        .split(RegExp(r'[。；;！？!?]'))
        .map(_cleanSlideText)
        .where((v) => v.length >= 6)
        .map((v) => v.length > 28 ? '${v.substring(0, 28)}…' : v)
        .take(4)
        .toList();
    return sentences.isNotEmpty ? sentences : ['课程目标清晰', '教学设计完整', '评价改进闭环'];
  }

  String _cleanSlideText(String input) {
    var text = input.trim();
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    text = text.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'^#{1,6}\s*'), '');
    text = text.replaceAll(RegExp(r'^[-*+]\s+'), '');
    text = text.replaceAll(RegExp(r'^\d+[.、)]\s*'), '');
    text = text.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    text = text.replaceAll(RegExp(r'[*_~>|#`]+'), '');
    text = text.replaceAll(RegExp(r'\s*\|\s*'), ' ');
    text = text.replaceAll(RegExp(r'[-:]{3,}'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 42) text = '${text.substring(0, 42)}…';
    return text;
  }

  Future<LectureVideoResult?> generateVideo({
    required BuildContext context,
    required String lectureContent,
    required String courseName,
    required String teacherName,
    String? outputDir,
    required void Function(String message) onProgress,
  }) async {
    final outDir = outputDir ?? Directory.current.path;
    final workDir =
        p.join(outDir, 'video_${DateTime.now().millisecondsSinceEpoch}');
    Directory(workDir).createSync(recursive: true);

    try {
      onProgress('第 1 步：正在用 AI 生成视频脚本...');
      final segments = await generateScript(
          lectureContent: lectureContent, courseName: courseName);
      final valid = segments.where((s) => s.narration.isNotEmpty).toList();
      if (valid.isEmpty) {
        onProgress('✗ AI 脚本生成失败');
        return null;
      }
      onProgress('✓ 脚本已生成（${valid.length} 段），第 2 步：正在生成专业 PPTX...');

      final deck = await _deck.generateDeck(
        courseName: courseName,
        teacherName: teacherName,
        lectureContent: lectureContent,
        segments: valid.map((s) => s.toJson()).toList(),
        outputDir: workDir,
      );

      List<String> slideImages = [];
      if (deck != null) {
        onProgress('✓ 专业 PPTX 已生成，正在通过 PowerPoint/WPS 导出高清页图...');
        final exported = await PptExportService.exportSlides(deck.pptxPath);
        if (exported != null && exported.isNotEmpty) {
          final slideDir = Directory(p.join(workDir, 'pptx_slides'))
            ..createSync(recursive: true);
          for (var i = 0; i < exported.length; i++) {
            final target = File(p.join(
                slideDir.path, 'slide_${i.toString().padLeft(3, '0')}.png'));
            await exported[i].copy(target.path);
            slideImages.add(target.path);
          }
        }
      }

      if (slideImages.isEmpty) {
        onProgress(deck == null
            ? '⚠ 专业 PPTX 生成失败，回退到应用内幻灯片...'
            : '⚠ PPTX 已生成但 Office 导出失败，回退到应用内幻灯片...');
        final slideList = <SlideData>[
          SlideData(
            title: '说课',
            narration: valid.first.narration,
            courseName: courseName,
            teacherName: teacherName,
            isTitle: true,
            bullets: _slideBulletsFor(valid.first, lectureContent),
          ),
          ...valid.skip(1).take(valid.length - 2).map((s) => SlideData(
                title: s.title,
                narration: s.narration,
                courseName: courseName,
                teacherName: teacherName,
                index: valid.indexOf(s) + 1,
                total: valid.length,
                bullets: _slideBulletsFor(s, lectureContent),
              )),
          if (valid.length > 1)
            SlideData(
              title: '感谢聆听',
              narration: valid.last.narration,
              courseName: courseName,
              isClosing: true,
            ),
        ].where((s) => s.title.isNotEmpty).toList();
        slideImages = await _slideGen.generateSlides(
            context: context, slides: slideList, outputDir: workDir);
      }
      if (slideImages.isNotEmpty) {
        onProgress('✓ 幻灯片已生成（${slideImages.length} 张），第 3 步：正在生成语音...');
      } else {
        onProgress('⚠ 跳过幻灯片，第 3 步：正在生成语音...');
      }

      final audioDir = p.join(workDir, 'audio');
      Directory(audioDir).createSync(recursive: true);
      final audioPaths = <String>[];

      for (var i = 0; i < valid.length; i++) {
        onProgress('第 3 步：正在生成语音 ${i + 1}/${valid.length}...');
        final outWav =
            p.join(audioDir, 'audio_${(i + 1).toString().padLeft(2, '0')}.wav');

        if (File(outWav).existsSync() && File(outWav).lengthSync() > 100) {
          audioPaths.add(outWav);
          continue;
        }

        if (!Platform.isWindows) {
          audioPaths.add('');
          continue;
        }

        audioPaths.add(await _generateTtsWav(
                narration: valid[i].narration, outputPath: outWav)
            ? outWav
            : '');
      }

      final matched = <int>{};
      for (var i = 0; i < audioPaths.length; i++) {
        if (audioPaths[i].isNotEmpty) matched.add(i);
      }
      if (matched.isEmpty) {
        onProgress('✗ 语音生成失败：Windows 语音合成不可用，请检查系统语音功能');
        return LectureVideoResult(
            videoPath: '',
            srtPath: '',
            segments: valid,
            workDir: workDir,
            pptxPath: deck?.pptxPath ?? '');
      }
      onProgress('✓ 语音已生成（${matched.length}/${valid.length} 段）');

      final matchedAudios = <String>[];
      final matchedSlides = <String>[];
      final narrations = <String>[];
      for (final i in matched.toList()..sort()) {
        matchedAudios.add(audioPaths.elementAt(i));
        matchedSlides.add(i < slideImages.length ? slideImages[i] : '');
        narrations.add(valid[i].narration);
      }

      final ffmpeg = await _resolveFfmpeg(onProgress);
      final hasFfmpeg = ffmpeg != null;
      if (ffmpeg != null) {
        _video.ffmpegCommand = ffmpeg.ffmpegPath;
        _video.ffprobeCommand = ffmpeg.ffprobePath;
        onProgress('第 4 步：正在合成视频（使用 FFmpeg）...');
      } else {
        onProgress('第 4 步：正在保存幻灯片（FFmpeg 未安装，将在应用内播放）...');
      }

      final videoPath = p.join(outDir, '说课演示_$courseName.mp4');
      var videoOk = false;

      if (hasFfmpeg && matchedSlides.any((s) => s.isNotEmpty)) {
        videoOk = await _video.generateVideo(
          slides: matchedSlides,
          audios: matchedAudios,
          outputPath: videoPath,
          onProgress: (c, t, m) => onProgress('正在合成视频... $m'),
        );
      }

      if (videoOk && await File(videoPath).exists()) {
        onProgress('第 5 步：正在生成字幕...');
        final srtPath = p.join(outDir, '说课演示_$courseName.srt');
        await _video.generateSrt(
            narrations: narrations,
            audioPaths: matchedAudios,
            outputPath: srtPath);
        onProgress('✓ 全部完成！视频已生成');
        return LectureVideoResult(
            videoPath: videoPath,
            srtPath: srtPath,
            segments: valid,
            workDir: workDir,
            pptxPath: deck?.pptxPath ?? '');
      } else {
        onProgress(hasFfmpeg
            ? '✗ 视频合成失败，已保留幻灯片和语音素材：$workDir'
            : '✗ 未能取得 FFmpeg，无法生成 MP4 视频。已保留素材：$workDir');
        return LectureVideoResult(
            videoPath: '',
            srtPath: '',
            segments: valid,
            workDir: workDir,
            pptxPath: deck?.pptxPath ?? '');
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureVideoService', stack: st);
      onProgress('✗ 出错：$e');
      return null;
    }
  }

  Future<bool> _generateTtsWav({
    required String narration,
    required String outputPath,
  }) async {
    try {
      final escaped = narration
          .replaceAll("'", "''")
          .replaceAll('"', '""')
          .replaceAll('\r\n', ' ')
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ')
          .trim();
      final outEsc = outputPath.replaceAll('\\', '\\\\');
      final ps1 = '''
Add-Type -AssemblyName System.Speech
\$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$synth.SetOutputToWaveFile("$outEsc")
\$synth.Speak('$escaped')
\$synth.Dispose()
''';
      final ps1File = File(outputPath.replaceAll('.wav', '.ps1'));
      await ps1File.writeAsString(ps1, flush: true);

      final r = await Process.run(
              'powershell',
              [
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                ps1File.path,
              ],
              runInShell: true)
          .timeout(const Duration(seconds: 120));
      ps1File.deleteSync();

      if (r.exitCode != 0) {
        swallowDebug('SAPI exit=${r.exitCode} stderr=${r.stderr}',
            tag: 'TtsWav');
      }

      return r.exitCode == 0 &&
          File(outputPath).existsSync() &&
          File(outputPath).lengthSync() > 100;
    } catch (e, st) {
      swallowDebug(e, tag: 'TtsWav', stack: st);
      return false;
    }
  }

  Future<_FfmpegPaths?> _resolveFfmpeg(
      void Function(String message) onProgress) async {
    if (await _hasCmd('ffmpeg')) return const _FfmpegPaths('ffmpeg', 'ffprobe');

    final candidates = <String>[
      p.join(Directory.current.path, 'tools', 'ffmpeg', 'bin', 'ffmpeg.exe'),
      p.join(Directory.current.path, 'ffmpeg', 'bin', 'ffmpeg.exe'),
      p.join(Directory.current.path, 'ffmpeg.exe'),
    ];
    for (final ffmpegPath in candidates) {
      final probe = ffmpegPath.replaceAll('ffmpeg.exe', 'ffprobe.exe');
      if (File(ffmpegPath).existsSync() && File(probe).existsSync()) {
        return _FfmpegPaths(ffmpegPath, probe);
      }
    }

    if (!Platform.isWindows) return null;
    try {
      onProgress('未发现 FFmpeg，正在下载应用内视频合成组件...');
      final toolRoot =
          Directory(p.join(Directory.current.path, 'tools', 'ffmpeg'));
      toolRoot.createSync(recursive: true);
      final zipPath = p.join(toolRoot.path, 'ffmpeg-release-essentials.zip');
      if (!File(zipPath).existsSync() ||
          File(zipPath).lengthSync() < 1024 * 1024) {
        final request = await HttpClient().getUrl(Uri.parse(
            'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'));
        final response =
            await request.close().timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return null;
        final out = File(zipPath).openWrite();
        await response.pipe(out).timeout(const Duration(minutes: 5));
      }

      onProgress('正在解压视频合成组件...');
      final archive =
          ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        if (!name.endsWith('/bin/ffmpeg.exe') &&
            !name.endsWith('/bin/ffprobe.exe')) continue;
        final targetName =
            name.endsWith('ffmpeg.exe') ? 'ffmpeg.exe' : 'ffprobe.exe';
        final outPath = p.join(toolRoot.path, 'bin', targetName);
        Directory(p.dirname(outPath)).createSync(recursive: true);
        await File(outPath)
            .writeAsBytes(file.content as List<int>, flush: true);
      }
      final ffmpegPath = p.join(toolRoot.path, 'bin', 'ffmpeg.exe');
      final ffprobePath = p.join(toolRoot.path, 'bin', 'ffprobe.exe');
      if (File(ffmpegPath).existsSync() && File(ffprobePath).existsSync()) {
        return _FfmpegPaths(ffmpegPath, ffprobePath);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureVideoService.resolveFfmpeg', stack: st);
    }
    return null;
  }

  Future<bool> _hasCmd(String cmd) async {
    try {
      final r = await Process.run(cmd, ['--version'], runInShell: true);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

class _FfmpegPaths {
  final String ffmpegPath;
  final String ffprobePath;
  const _FfmpegPaths(this.ffmpegPath, this.ffprobePath);
}

class LectureVideoResult {
  final String videoPath;
  final String srtPath;
  final List<LectureVideoSegment> segments;
  final String workDir;
  final String pptxPath;

  const LectureVideoResult({
    required this.videoPath,
    required this.srtPath,
    required this.segments,
    required this.workDir,
    this.pptxPath = '',
  });
}
