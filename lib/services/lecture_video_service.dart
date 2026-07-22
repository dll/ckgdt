import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/error_handler.dart';
import 'ai_service.dart';
import 'tts_service.dart';
import 'video_service.dart';

/// 说课视频脚本的单个段落
class LectureVideoSegment {
  final String title;
  final String narration;
  final String visualHint;
  final int durationSeconds;
  final int order;

  const LectureVideoSegment({
    required this.title,
    required this.narration,
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
}

/// 说课视频生成服务 — AI 驱动：读说课内容 → 生成视频脚本 → 制作幻灯片 → TTS → 合成
class LectureVideoService {
  final AiService _ai = AiService();
  final TtsService _tts = TtsService();
  final VideoService _video = VideoService();

  pw.Font? _font;

  Future<void> _ensureFont() async {
    if (_font != null) return;
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      _font = pw.Font.ttf(data);
    } catch (_) {
      try {
        final data = await rootBundle.load('assets/fonts/msyh.ttc');
        _font = pw.Font.ttf(data);
      } catch (_) {}
    }
  }

  Future<List<LectureVideoSegment>> generateScript({
    required String lectureContent,
    required String courseName,
    String teacherName = '',
    List<Map<String, dynamic>> classes = const [],
    int totalStudents = 0,
  }) async {
    final prompt = _buildScriptPrompt(
      lectureContent: lectureContent,
      courseName: courseName,
      teacherName: teacherName,
      classes: classes,
      totalStudents: totalStudents,
    );

    final raw = await _ai.chat(
      [
        {'role': 'user', 'content': prompt},
      ],
      systemPrompt: '你是一位资深的教学督导专家，擅长从教师说课文档中提取精华，'
          '生成结构清晰、内容生动的说课视频脚本。'
          '请用专业、规范的中文输出，适合 TTS 朗读。',
    );

    return _parseScriptResult(raw);
  }

  String _buildScriptPrompt({
    required String lectureContent,
    required String courseName,
    String teacherName = '',
    List<Map<String, dynamic>> classes = const [],
    int totalStudents = 0,
  }) {
    final buf = StringBuffer();
    buf.writeln('## 任务');
    buf.writeln('根据以下说课文档，生成一份专业的说课视频脚本。');
    buf.writeln();
    buf.writeln('## 说课文档');
    buf.writeln(lectureContent);
    buf.writeln();
    if (teacherName.isNotEmpty) {
      buf.writeln('## 说课教师');
      buf.writeln(teacherName);
      buf.writeln();
    }
    if (classes.isNotEmpty) {
      buf.writeln('## 授课班级');
      buf.writeln('共 ${classes.length} 个班，${totalStudents} 名学生');
      buf.writeln();
    }
    buf.writeln('## 输出要求');
    buf.writeln('请生成 8-12 个段落的视频脚本，覆盖以下环节：');
    buf.writeln('1. 开场 — 教师自我介绍、课程名称');
    buf.writeln('2. 课程定位 — 课程性质、目标、面向对象');
    buf.writeln('3. 教学内容 — 章节体系、知识点结构');
    buf.writeln('4. 教学方法与手段 — 创新教学法、平台特色');
    buf.writeln('5. 实践环节 — 实验/实践项目');
    buf.writeln('6. 考核评价 — 考核方式、评价量规');
    buf.writeln('7. 教学改革 — 持续改进、已实施改革及成效');
    buf.writeln('8. 结尾 — 总结提升、致谢');
    buf.writeln();
    buf.writeln('返回 JSON 数组，格式：');
    buf.writeln('''[
  {
    "title": "段落标题（如"课程定位与目标"）",
    "narration": "旁白文本，口语化，适合 TTS 朗读，每段 100-200 字",
    "visual_hint": "视觉提示（如"显示课程大纲结构"），用于匹配幻灯片内容",
    "duration_seconds": 25
  }
]''');
    buf.writeln();
    buf.writeln('要求：');
    buf.writeln('- 每段 narration 以"尊敬的各位评委老师"或类似自然称呼开头');
    buf.writeln('- 总时长控制在 4-8 分钟');
    buf.writeln('- 语言自然流畅、有感染力，适合教师说课场景');
    buf.writeln('- 必须体现当前课程的实际内容，不可使用通用模板');
    buf.writeln('- 仅返回 JSON，不要其他文字');
    return buf.toString();
  }

  List<LectureVideoSegment> _parseScriptResult(String raw) {
    final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (match == null) {
      return _fallbackSegments();
    }
    try {
      final list = jsonDecode(match.group(0)!) as List;
      return list.asMap().entries.map((entry) {
        final i = entry.key;
        final m = entry.value as Map<String, dynamic>;
        return LectureVideoSegment(
          title: m['title'] as String? ?? '段落 ${i + 1}',
          narration: m['narration'] as String? ?? '',
          visualHint: m['visual_hint'] as String? ?? '',
          durationSeconds: m['duration_seconds'] as int? ?? 30,
          order: i + 1,
        );
      }).toList();
    } catch (e) {
      swallow(e, tag: 'LectureVideoService.parseScript');
      return _fallbackSegments();
    }
  }

  List<LectureVideoSegment> _fallbackSegments() {
    return [
      const LectureVideoSegment(
        order: 1, title: '开场', narration: '尊敬的各位评委老师，大家好。今天我说课的主题是《课程名称》。',
        visualHint: '课程封面', durationSeconds: 20),
      const LectureVideoSegment(
        order: 2, title: '课程定位', narration: '本课程面向相关专业学生，注重理论与实践相结合，培养学生的专业素养和创新能力。',
        visualHint: '课程定位', durationSeconds: 30),
      const LectureVideoSegment(
        order: 3, title: '教学内容', narration: '课程内容涵盖多个章节，系统全面地介绍了该领域的核心知识与技能。',
        visualHint: '内容大纲', durationSeconds: 40),
      const LectureVideoSegment(
        order: 4, title: '教学方法', narration: '采用项目驱动、案例教学等多种教学方法，充分利用数字化教学平台提升教学效果。',
        visualHint: '教学方法', durationSeconds: 30),
      const LectureVideoSegment(
        order: 5, title: '实践环节', narration: '课程设置了多个实践项目，让学生在实际操作中巩固所学知识。',
        visualHint: '实践项目', durationSeconds: 30),
      const LectureVideoSegment(
        order: 6, title: '考核评价', narration: '采用过程性评价与终结性评价相结合的方式，全面客观地评价学生学习成效。',
        visualHint: '考核方案', durationSeconds: 25),
      const LectureVideoSegment(
        order: 7, title: '教学改革', narration: '课程团队持续进行教学改革与创新，不断提升课程质量和教学效果。',
        visualHint: '教改成果', durationSeconds: 25),
      const LectureVideoSegment(
        order: 8, title: '结语', narration: '以上就是我的说课内容，恳请各位评委老师批评指正。谢谢。',
        visualHint: '结语致谢', durationSeconds: 15),
    ];
  }

  Future<String> generateSlidesPdf({
    required List<LectureVideoSegment> segments,
    required String courseName,
    required String teacherName,
    required String outputDir,
  }) async {
    await _ensureFont();
    final pdf = pw.Document();

    final segmentsWithVisual = segments.where((s) => s.narration.isNotEmpty).toList();
    if (segmentsWithVisual.isEmpty) return '';

    for (var i = 0; i < segmentsWithVisual.length; i++) {
      final seg = segmentsWithVisual[i];
      final isFirst = i == 0;
      final isLast = i == segmentsWithVisual.length - 1;

      pw.Widget slideWidget;
      if (isFirst) {
        slideWidget = _buildTitleSlide(seg, courseName, teacherName);
      } else if (isLast) {
        slideWidget = _buildClosingSlide(seg);
      } else {
        slideWidget = _buildContentSlide(seg, i, segmentsWithVisual.length, courseName);
      }

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(1920, 1080),
        theme: _font != null ? pw.ThemeData.withFont(base: _font!) : null,
        build: (_) => slideWidget,
      ));
    }

    final bytes = await pdf.save();
    final pdfPath = p.join(outputDir, '说课幻灯片_$courseName.pdf');
    await File(pdfPath).writeAsBytes(bytes);
    return pdfPath;
  }

  pw.Widget _buildTitleSlide(LectureVideoSegment seg, String courseName, String teacherName) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [PdfColor.fromInt(0xFF1A237E), PdfColor.fromInt(0xFF3949AB)],
          begin: pw.Alignment(0, 0), end: pw.Alignment(1, 1),
        ),
      ),
      child: pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text('说课', style: pw.TextStyle(font: _font, fontSize: 64, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 24),
            pw.Text('《${courseName}》', style: pw.TextStyle(font: _font, fontSize: 40, color: PdfColors.white)),
            pw.SizedBox(height: 32),
            if (teacherName.isNotEmpty)
              pw.Text('说课教师：$teacherName', style: pw.TextStyle(font: _font, fontSize: 28, color: PdfColor.fromInt(0xFFB3E5FC))),
            pw.SizedBox(height: 48),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              decoration: pw.BoxDecoration(
                color: PdfColors.white.withOpacity(0.15),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Text(seg.narration, style: pw.TextStyle(font: _font, fontSize: 18, color: PdfColors.white), textAlign: pw.TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildContentSlide(LectureVideoSegment seg, int index, int total, String courseName) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(40),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF1A237E),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(seg.title, style: pw.TextStyle(font: _font, fontSize: 28, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Text('$index / $total', style: pw.TextStyle(font: _font, fontSize: 14, color: PdfColors.grey)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(height: 3, color: PdfColor.fromInt(0xFF3949AB)),
          pw.SizedBox(height: 32),
          pw.Expanded(
            child: pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(32),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF5F5F5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Text(
                  seg.narration,
                  style: pw.TextStyle(font: _font, fontSize: 22, color: PdfColors.grey800, height: 1.8),
                  textAlign: pw.TextAlign.left,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          if (seg.visualHint.isNotEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE3F2FD),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                children: [
                  pw.Text('📌 ', style: pw.TextStyle(font: _font, fontSize: 16)),
                  pw.Text('视觉提示：${seg.visualHint}', style: pw.TextStyle(font: _font, fontSize: 14, color: PdfColor.fromInt(0xFF1565C0))),
                ],
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Text(courseName, style: pw.TextStyle(font: _font, fontSize: 12, color: PdfColors.grey500), textAlign: pw.TextAlign.right),
        ],
      ),
    );
  }

  pw.Widget _buildClosingSlide(LectureVideoSegment seg) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [PdfColor.fromInt(0xFF3949AB), PdfColor.fromInt(0xFF1A237E)],
          begin: pw.Alignment(0, 0), end: pw.Alignment(1, 1),
        ),
      ),
      child: pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text('感谢聆听', style: pw.TextStyle(font: _font, fontSize: 56, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 32),
            pw.Container(
              padding: const pw.EdgeInsets.all(32),
              margin: const pw.EdgeInsets.symmetric(horizontal: 80),
              decoration: pw.BoxDecoration(
                color: PdfColors.white.withOpacity(0.15),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Text(seg.narration, style: pw.TextStyle(font: _font, fontSize: 20, color: PdfColors.white), textAlign: pw.TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<String>> pdfToImages(String pdfPath, String outputDir) async {
    final images = <String>[];
    final baseName = p.basenameWithoutExtension(pdfPath);

    try {
      final result = await Process.run('python', [
        '-c', '''
import sys
try:
    from pdf2image import convert_from_path
    images = convert_from_path(r"$pdfPath", dpi=150)
    for i, img in enumerate(images):
        out = r"$outputDir/${baseName}_slide_{i:03d}.png"
        img.save(out, "PNG")
        print(out)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
''',
      ]);

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().trim().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && !trimmed.startsWith('ERROR')) {
            images.add(trimmed);
          }
        }
      }
    } catch (e) {
      swallow(e, tag: 'LectureVideoService.pdfToImages.py');
    }

    if (images.isEmpty) {
      try {
        final result = await Process.run('mutool', ['draw', '-o', '$outputDir/${baseName}_slide_%03d.png', '-r', '150', pdfPath]);
        if (result.exitCode == 0) {
          for (var i = 0; i < 20; i++) {
            final imgPath = p.join(outputDir, '${baseName}_slide_${i.toString().padLeft(3, '0')}.png');
            if (await File(imgPath).exists()) images.add(imgPath);
            else break;
          }
        }
      } catch (e) {
        swallow(e, tag: 'LectureVideoService.pdfToImages.mutool');
      }
    }
    return images;
  }

  Future<LectureVideoResult?> generateVideo({
    required String lectureContent,
    required String courseName,
    required String teacherName,
    List<Map<String, dynamic>> classes = const [],
    int totalStudents = 0,
    String? outputDir,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    final outDir = outputDir ?? Directory.current.path;
    final workDir = p.join(outDir, '说课_video_${DateTime.now().millisecondsSinceEpoch}');
    Directory(workDir).createSync(recursive: true);

    try {
      onProgress?.call(0, 6, '正在生成视频脚本...');
      final segments = await generateScript(
        lectureContent: lectureContent,
        courseName: courseName,
        teacherName: teacherName,
        classes: classes,
        totalStudents: totalStudents,
      );

      final validSegments = segments.where((s) => s.narration.isNotEmpty).toList();
      if (validSegments.isEmpty) return null;

      onProgress?.call(1, 6, '正在生成幻灯片...');
      final pdfPath = await generateSlidesPdf(
        segments: validSegments,
        courseName: courseName,
        teacherName: teacherName,
        outputDir: workDir,
      );
      if (pdfPath.isEmpty) return null;

      onProgress?.call(2, 6, '正在转换幻灯片为图片...');
      var slideImages = await pdfToImages(pdfPath, workDir);
      if (slideImages.isEmpty) {
        final baseName = p.basenameWithoutExtension(pdfPath);
        slideImages = List.generate(validSegments.length, (i) {
          final imgPath = p.join(workDir, '${baseName}_slide_${i.toString().padLeft(3, '0')}.png');
          return imgPath;
        });
      }

      onProgress?.call(3, 6, '正在生成语音...');
      final audioDir = p.join(workDir, 'audio');
      Directory(audioDir).createSync(recursive: true);

      final narrations = validSegments.map((s) => {
        'narration': s.narration,
        'voice': 'zh-CN-XiaoxiaoNeural',
        'rate': '+0%',
      }).toList();

      await _tts.generateBatchAudio(
        scripts: narrations,
        outputDir: audioDir,
        onProgress: (current, total) {
          onProgress?.call(3, 6, '正在生成语音... $current/$total');
        },
      );

      final audios = <String>[];
      final subtitles = <String>[];
      final matchedSlides = <String>[];

      for (var i = 0; i < validSegments.length; i++) {
        final audioPath = p.join(audioDir, 'slide_${i.toString().padLeft(3, '0')}.mp3');
        if (await File(audioPath).exists()) {
          audios.add(audioPath);
          subtitles.add(validSegments[i].narration);
          matchedSlides.add(slideImages.isNotEmpty ? slideImages[i % slideImages.length] : '');
        }
      }

      if (audios.isEmpty) return null;

      onProgress?.call(4, 6, '正在合成视频...');
      final videoPath = p.join(outDir, '说课演示_${courseName}.mp4');

      final videoSuccess = await _video.generateVideo(
        slides: matchedSlides,
        audios: audios,
        outputPath: videoPath,
        onProgress: (c, t, m) {
          onProgress?.call(4, 6, '正在合成视频... $m');
        },
      );

      if (!videoSuccess || !await File(videoPath).exists()) return null;

      onProgress?.call(5, 6, '正在生成字幕...');
      final srtPath = p.join(outDir, '说课演示_${courseName}.srt');
      await _video.generateSrt(
        narrations: validSegments.map((s) => s.narration).toList(),
        audioPaths: audios,
        outputPath: srtPath,
      );

      onProgress?.call(6, 6, '完成');

      return LectureVideoResult(
        videoPath: videoPath,
        srtPath: srtPath,
        pdfPath: pdfPath,
        segments: validSegments,
        workDir: workDir,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureVideoService.generateVideo', stack: st);
      return null;
    }
  }
}

class LectureVideoResult {
  final String videoPath;
  final String srtPath;
  final String pdfPath;
  final List<LectureVideoSegment> segments;
  final String workDir;

  const LectureVideoResult({
    required this.videoPath,
    required this.srtPath,
    required this.pdfPath,
    required this.segments,
    required this.workDir,
  });
}
