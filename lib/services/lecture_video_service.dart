import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/error_handler.dart';
import 'ai_service.dart';
import 'video_service.dart';
import 'slide_image_generator.dart';

class LectureVideoSegment {
  final String title;
  final String narration;
  final String visualHint;
  final int durationSeconds;
  final int order;

  const LectureVideoSegment({
    required this.title,
    this.narration = '',
    this.visualHint = '',
    this.durationSeconds = 30,
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'narration': narration,
        'visual_hint': visualHint,
        'duration_seconds': durationSeconds,
        'order': order,
      };

  static LectureVideoSegment fromJson(Map<String, dynamic> m, int i) =>
      LectureVideoSegment(
        title: m['title'] as String? ?? '段落 ${i + 1}',
        narration: m['narration'] as String? ?? '',
        visualHint: m['visual_hint'] as String? ?? '',
        durationSeconds: m['duration_seconds'] as int? ?? 30,
        order: i + 1,
      );
}

class LectureVideoService {
  final AiService _ai = AiService();
  final VideoService _video = VideoService();
  final SlideImageGenerator _slideGen = SlideImageGenerator();

  Future<List<LectureVideoSegment>> generateScript({
    required String lectureContent,
    required String courseName,
  }) async {
    final prompt = '''
根据以下说课文档，生成一份专业的说课视频脚本，分段落输出 JSON 数组。

要求：
- 每个段落包含 title（标题）、narration（旁白，口语化，100-200字）、duration_seconds（时长秒数，25-40）
- 覆盖：开场→课程定位→教学内容→教学方法→实践→考核→教改→结语
- 开场以"尊敬的各位评委老师，大家好"开头
- 总时长 4-8 分钟
- 必须基于具体内容，不使用通用模板
- 仅返回 JSON 数组，不要其他文字

说课文档：
$lectureContent
''';

    final raw = await _ai.chat(
      [{'role': 'user', 'content': prompt}],
      systemPrompt: '你是一位教学督导专家，擅长为教师说课生成视频脚本。请输出纯净 JSON。',
    );

    final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (match == null) return _fallbackSegments();
    try {
      final list = jsonDecode(match.group(0)!) as List;
      return list.asMap().entries
          .map((e) => LectureVideoSegment.fromJson(e.value as Map<String, dynamic>, e.key))
          .toList();
    } catch (e) {
      swallow(e, tag: 'LectureVideoService.parse');
      return _fallbackSegments();
    }
  }

  List<LectureVideoSegment> _fallbackSegments() {
    return [
      const LectureVideoSegment(order: 1, title: '开场', narration: '尊敬的各位评委老师，大家好。今天我说课的主题是《课程名称》。', durationSeconds: 20),
      const LectureVideoSegment(order: 2, title: '课程定位', narration: '本课程面向相关专业学生，注重理论与实践相结合。', durationSeconds: 30),
      const LectureVideoSegment(order: 3, title: '教学内容', narration: '课程内容涵盖多个章节，系统全面。', durationSeconds: 40),
      const LectureVideoSegment(order: 4, title: '教学方法', narration: '采用项目驱动、案例教学等多种教学方法。', durationSeconds: 30),
      const LectureVideoSegment(order: 5, title: '实践环节', narration: '课程设置了多个实践项目。', durationSeconds: 30),
      const LectureVideoSegment(order: 6, title: '考核评价', narration: '采用过程性评价与终结性评价相结合的方式。', durationSeconds: 25),
      const LectureVideoSegment(order: 7, title: '教学改革', narration: '课程团队持续进行教学改革与创新。', durationSeconds: 25),
      const LectureVideoSegment(order: 8, title: '结语', narration: '以上就是我的说课内容，恳请各位评委老师批评指正。谢谢。', durationSeconds: 15),
    ];
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
    final workDir = p.join(outDir, 'video_${DateTime.now().millisecondsSinceEpoch}');
    Directory(workDir).createSync(recursive: true);

    try {
      onProgress('第 1 步：正在用 AI 生成视频脚本...');
      final segments = await generateScript(lectureContent: lectureContent, courseName: courseName);
      final valid = segments.where((s) => s.narration.isNotEmpty).toList();
      if (valid.isEmpty) {
        onProgress('✗ AI 脚本生成失败，点击取消');
        return null;
      }
      onProgress('✓ 脚本已生成（${valid.length} 段），第 2 步：正在制作幻灯片...');

      final slideList = <SlideData>[
        SlideData(title: '说课', narration: valid.first.narration, courseName: courseName, teacherName: teacherName, isTitle: true),
        ...valid.skip(1).take(valid.length - 2).map((s) => SlideData(
          title: s.title, narration: s.narration, courseName: courseName, teacherName: teacherName,
          index: valid.indexOf(s) + 1, total: valid.length,
        )),
        if (valid.length > 1)
          SlideData(title: '感谢聆听', narration: valid.last.narration, courseName: courseName, isClosing: true),
      ].where((s) => s.title.isNotEmpty).toList();

      final slideImages = await _slideGen.generateSlides(context: context, slides: slideList, outputDir: workDir);
      if (slideImages.isNotEmpty) {
        onProgress('✓ 幻灯片已生成（${slideImages.length} 张），第 3 步：正在生成语音...');
      } else {
        onProgress('⚠ 幻灯片生成失败，跳过图片，第 3 步：正在生成语音...');
      }

      final audioDir = p.join(workDir, 'audio');
      Directory(audioDir).createSync(recursive: true);
      final audioPaths = <String>[];

      for (var i = 0; i < valid.length; i++) {
        onProgress('第 3 步：正在生成语音 ${i + 1}/${valid.length}...');
        final outPath = p.join(audioDir, 'audio_${(i + 1).toString().padLeft(2, '0')}.mp3');

        if (File(outPath).existsSync() && File(outPath).lengthSync() > 100) {
          audioPaths.add(outPath);
          continue;
        }

        var ok = false;
        if (await _hasCmd('edge-tts')) {
          final txtFile = File(p.join(audioDir, 'tts_$i.txt'));
          await txtFile.writeAsString(valid[i].narration);
          final r = await Process.run('edge-tts', [
            '--voice', 'zh-CN-XiaoxiaoNeural', '--rate', '-5%',
            '--file', txtFile.path, '--write-media', outPath,
          ], runInShell: true).timeout(const Duration(seconds: 60));
          txtFile.deleteSync();
          ok = r.exitCode == 0 && File(outPath).existsSync() && File(outPath).lengthSync() > 100;
        }
        if (!ok && Platform.isWindows) {
          onProgress('尝试 Windows 语音合成 ${i + 1}/${valid.length}...');
          final outWav = outPath.replaceAll('.mp3', '.wav');
          final escaped = valid[i].narration.replaceAll("'", "''");
          final outEsc = outWav.replaceAll('\\', '\\\\');
          final ps = '''
Add-Type -AssemblyName System.Speech
\$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$synth.SetOutputToWaveFile("$outEsc")
\$synth.Speak('$escaped')
\$synth.Dispose()
''';
          final psFile = File(p.join(audioDir, 'gen_$i.ps1'));
          await psFile.writeAsString(ps);
          final r = await Process.run('powershell', ['-ExecutionPolicy', 'Bypass', '-File', psFile.path],
              runInShell: true).timeout(const Duration(seconds: 60));
          psFile.deleteSync();
          if (r.exitCode == 0 && File(outWav).existsSync() && File(outWav).lengthSync() > 100) {
            audioPaths.add(outWav);
            ok = true;
          }
        }
        if (!ok) {
          audioPaths.add('');
        } else {
          audioPaths.add(outPath);
        }
      }

      final matched = <int>{};
      for (var i = 0; i < audioPaths.length; i++) {
        if (audioPaths[i].isNotEmpty) matched.add(i);
      }
      if (matched.isEmpty) {
        onProgress('✗ 所有语音生成失败。请安装 edge-tts（pip install edge-tts）后重试');
        return null;
      }
      onProgress('✓ 语音已生成（${matched.length}/${valid.length} 段），第 4 步：正在合成视频...');

      final matchedAudios = <String>[];
      final matchedSlides = <String>[];
      final narrations = <String>[];
      for (final i in matched.toList()..sort()) {
        matchedAudios.add(audioPaths.elementAt(i));
        matchedSlides.add(i < slideImages.length ? slideImages[i] : '');
        narrations.add(valid[i].narration);
      }

      final videoPath = p.join(outDir, '说课演示_$courseName.mp4');
      var videoOk = false;

      if (await _hasCmd('ffmpeg') && matchedSlides.any((s) => s.isNotEmpty)) {
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
        await _video.generateSrt(narrations: narrations, audioPaths: matchedAudios, outputPath: srtPath);
        onProgress('✓ 全部完成！视频已生成');
        return LectureVideoResult(videoPath: videoPath, srtPath: srtPath, segments: valid, workDir: workDir);
      } else {
        if (await _hasCmd('ffmpeg') == false) {
          onProgress('✓ 脚本和语音已完成。要生成 MP4 视频需要 FFmpeg，请安装后重试。幻灯片和语音文件保存在：$workDir');
        } else {
          onProgress('✓ 脚本和语音已完成。视频合成遇到问题，幻灯片和语音已保存到：$workDir');
        }
        return LectureVideoResult(videoPath: '', srtPath: '', segments: valid, workDir: workDir);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureVideoService', stack: st);
      onProgress('✗ 出错：$e');
      return null;
    }
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

class LectureVideoResult {
  final String videoPath;
  final String srtPath;
  final List<LectureVideoSegment> segments;
  final String workDir;

  const LectureVideoResult({
    required this.videoPath,
    required this.srtPath,
    required this.segments,
    required this.workDir,
  });
}
