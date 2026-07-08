import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';
import '../core/error_handler.dart';

/// 资源生成服务 — 从课程包 MD 文件生成 PDF / PPT / 视频脚本
///
/// 课程生成时会在 `courses/{courseId}/理论/` 下保存各章节 MD 文件，
/// 本服务读取这些 MD 并转换为 PDF 和 PPTX，注册到 resource_files 表。
class ResourceGenerationService {
  /// 生成进度回调：(chapter, fileType, progress)
  void Function(String chapter, String fileType, double progress)? onProgress;

  ResourceGenerationService({this.onProgress});

  // ═══════════════════════════════════════════════════════════════════════════
  // 核心：为某章节生成三种资源
  // ═══════════════════════════════════════════════════════════════════════════

  /// 为指定章节生成 PDF + PPT + 视频脚本，结果写入 resource_files 表
  /// [sourceType] = 'preset'（教师预制）或 'extended'（学生扩展）
  Future<GenerationResult> generateForChapter({
    required String courseId,
    required String chapterTitle,
    required String chapterMdPath,
    String sourceType = 'preset',
  }) async {
    final result = GenerationResult(chapter: chapterTitle);

    // 1. 读取 MD 内容
    String mdContent = '';
    try {
      final mdFile = File(chapterMdPath);
      if (await mdFile.exists()) {
        mdContent = await mdFile.readAsString();
      }
    } catch (e) {
      swallowDebug(e, tag: 'ResourceGen.readMd');
    }

    if (mdContent.trim().isEmpty) {
      result.error = 'MD 文件为空或不存在: $chapterMdPath';
      return result;
    }

    final title = chapterTitle.replaceAll(RegExp(r'^第[一二三四五六七八九十\d]+章\s*'), '');

    // 2. 生成 PDF
    onProgress?.call(chapterTitle, 'pdf', 0.0);
    try {
      final pdfPath = await _generatePdf(
        courseId: courseId,
        title: title,
        chapter: chapterTitle,
        mdContent: mdContent,
        sourceType: sourceType,
      );
      if (pdfPath != null) {
        result.pdfPath = pdfPath;
        result.generated.add('pdf');
      }
    } catch (e) {
      swallowDebug(e, tag: 'ResourceGen.generatePdf');
      result.errors.add('PDF: $e');
    }
    onProgress?.call(chapterTitle, 'pdf', 1.0);

    // 3. 生成 PPT（从 MD 解析幻灯片结构）
    onProgress?.call(chapterTitle, 'ppt', 0.0);
    try {
      final pptxPath = await _generatePptx(
        courseId: courseId,
        title: title,
        chapter: chapterTitle,
        mdContent: mdContent,
        sourceType: sourceType,
      );
      if (pptxPath != null) {
        result.pptxPath = pptxPath;
        result.generated.add('ppt');
      }
    } catch (e) {
      swallowDebug(e, tag: 'ResourceGen.generatePptx');
      result.errors.add('PPT: $e');
    }
    onProgress?.call(chapterTitle, 'ppt', 1.0);

    // 4. 生成视频脚本（MD 本身就是脚本，直接注册）
    onProgress?.call(chapterTitle, 'video', 0.0);
    try {
      final scriptPath = await _registerVideoScript(
        courseId: courseId,
        title: title,
        chapter: chapterTitle,
        mdContent: mdContent,
        sourceType: sourceType,
      );
      if (scriptPath != null) {
        result.videoScriptPath = scriptPath;
        result.generated.add('video');
      }
    } catch (e) {
      swallowDebug(e, tag: 'ResourceGen.registerVideoScript');
      result.errors.add('视频脚本: $e');
    }
    onProgress?.call(chapterTitle, 'video', 1.0);

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF 生成
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> _generatePdf({
    required String courseId,
    required String title,
    required String chapter,
    required String mdContent,
    required String sourceType,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // 检查是否已存在同章节同 source_type 的 PDF
    final existing = await db.query(
      'resource_files',
      where: "course_id = ? AND file_type = 'pdf' AND chapter = ? AND source_type = ?",
      whereArgs: [courseId, chapter, sourceType],
    );
    if (existing.isNotEmpty) {
      final path = existing.first['file_path']?.toString() ?? '';
      if (path.isNotEmpty && await File(path).exists()) {
        return path; // 已存在且文件有效
      }
    }

    // 解析 MD 为 PDF 内容
    final pdf = pw.Document();
    pw.Font? font;
    pw.Font? boldFont;

    // 加载中文字体
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      font = pw.Font.ttf(fontData);
    } catch (_) {}
    try {
      final boldData = await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
      boldFont = pw.Font.ttf(boldData);
    } catch (_) {
      boldFont = font;
    }

    final theme = font != null
        ? pw.ThemeData.withFont(base: font, bold: boldFont ?? font)
        : null;

    // 解析 MD 内容为段落
    final lines = mdContent.split('\n');
    final List<pw.Widget> children = [];
    bool firstHeading = true;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('# ')) {
        if (firstHeading) {
          // 第一个 # 作为标题页
          children.add(pw.SizedBox(height: 40));
          children.add(pw.Text(
            trimmed.substring(2),
            style: pw.TextStyle(
              font: font,
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF1677FF),
            ),
          ));
          children.add(pw.SizedBox(height: 8));
          children.add(pw.Text(
            chapter,
            style: pw.TextStyle(font: font, fontSize: 16, color: PdfColors.grey600),
          ));
          children.add(pw.SizedBox(height: 20));
          firstHeading = false;
        } else {
          children.add(pw.SizedBox(height: 16));
          children.add(pw.Text(
            trimmed.substring(2),
            style: pw.TextStyle(
              font: font,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ));
          children.add(pw.Divider(color: PdfColor.fromInt(0xFF1677FF)));
        }
      } else if (trimmed.startsWith('## ')) {
        children.add(pw.SizedBox(height: 12));
        children.add(pw.Text(
          trimmed.substring(3),
          style: pw.TextStyle(font: font, fontSize: 15, fontWeight: pw.FontWeight.bold),
        ));
      } else if (trimmed.startsWith('### ')) {
        children.add(pw.SizedBox(height: 8));
        children.add(pw.Text(
          trimmed.substring(4),
          style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
        ));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, top: 2),
          child: pw.Text(
            '• ${trimmed.substring(2)}',
            style: pw.TextStyle(font: font, fontSize: 11),
          ),
        ));
      } else if (trimmed.startsWith('```')) {
        // 代码块标记，跳过
        continue;
      } else {
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            trimmed,
            style: pw.TextStyle(font: font, fontSize: 11, lineSpacing: 4),
          ),
        ));
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      build: (_) => children.isEmpty
          ? [pw.Text('（空内容）', style: pw.TextStyle(font: font))]
          : children,
    ));

    // 写入文件
    final dir = await _getCourseDir(courseId);
    final pdfPath = '$dir${Platform.pathSeparator}$title.pdf';
    final file = File(pdfPath);
    await file.writeAsBytes(await pdf.save());

    // 注册到 resource_files
    await db.insert(
      'resource_files',
      {
        'course_id': courseId,
        'file_name': '$title.pdf',
        'file_path': pdfPath,
        'file_type': 'pdf',
        'chapter': chapter,
        'description': '[${sourceType == 'preset' ? '预制' : 'AI生成'}] $title 课件',
        'source_type': sourceType,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return pdfPath;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PPT 生成（从 MD 解析结构生成 JSON 格式幻灯片）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> _generatePptx({
    required String courseId,
    required String title,
    required String chapter,
    required String mdContent,
    required String sourceType,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // 检查已存在
    final existing = await db.query(
      'resource_files',
      where: "course_id = ? AND file_type = 'ppt' AND chapter = ? AND source_type = ?",
      whereArgs: [courseId, chapter, sourceType],
    );
    if (existing.isNotEmpty) {
      final path = existing.first['file_path']?.toString() ?? '';
      if (path.isNotEmpty && await File(path).exists()) {
        return path;
      }
    }

    // 解析 MD 为幻灯片 JSON
    final slides = _parseMdToSlides(mdContent, title);
    final slideJson = jsonEncode({
      'title': title,
      'chapter': chapter,
      'slides': slides,
    });

    final dir = await _getCourseDir(courseId);
    final pptxPath = '$dir${Platform.pathSeparator}$title-课件.json';
    await File(pptxPath).writeAsString(slideJson);

    await db.insert(
      'resource_files',
      {
        'course_id': courseId,
        'file_name': '$title-课件.json',
        'file_path': pptxPath,
        'file_type': 'ppt',
        'chapter': chapter,
        'description': '[${sourceType == 'preset' ? '预制' : 'AI生成'}] $title 课件',
        'source_type': sourceType,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return pptxPath;
  }

  /// 将 MD 内容解析为幻灯片结构
  List<Map<String, String>> _parseMdToSlides(String md, String courseTitle) {
    final slides = <Map<String, String>>[];
    final lines = md.split('\n');
    String? currentTitle;
    final currentContent = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('## ')) {
        // 保存上一张幻灯片
        if (currentTitle != null) {
          slides.add({
            'title': currentTitle,
            'content': currentContent.toString().trim(),
          });
          currentContent.clear();
        }
        currentTitle = trimmed.substring(3);
      } else if (trimmed.startsWith('# ') && currentTitle == null) {
        currentTitle = courseTitle;
        currentContent.writeln(trimmed.substring(2));
      } else {
        currentContent.writeln(trimmed);
      }
    }

    // 保存最后一张
    if (currentTitle != null) {
      slides.add({
        'title': currentTitle,
        'content': currentContent.toString().trim(),
      });
    }

    // 至少要有一张幻灯片
    if (slides.isEmpty) {
      slides.add({
        'title': courseTitle,
        'content': md.length > 500 ? md.substring(0, 500) : md,
      });
    }

    return slides;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 视频脚本注册
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> _registerVideoScript({
    required String courseId,
    required String title,
    required String chapter,
    required String mdContent,
    required String sourceType,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // 检查已存在
    final existing = await db.query(
      'resource_files',
      where: "course_id = ? AND file_type = 'video' AND chapter = ? AND source_type = ?",
      whereArgs: [courseId, chapter, sourceType],
    );
    if (existing.isNotEmpty) {
      final path = existing.first['file_path']?.toString() ?? '';
      if (path.isNotEmpty) return path;
    }

    // MD 本身就是视频脚本，保存并注册
    final dir = await _getCourseDir(courseId);
    final scriptPath = '$dir${Platform.pathSeparator}$title-视频脚本.md';
    await File(scriptPath).writeAsString(mdContent);

    await db.insert(
      'resource_files',
      {
        'course_id': courseId,
        'file_name': '$title-视频脚本.md',
        'file_path': scriptPath,
        'file_type': 'video',
        'chapter': chapter,
        'description': '[${sourceType == 'preset' ? '预制' : 'AI生成'}] $title 视频脚本',
        'source_type': sourceType,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return scriptPath;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 批量生成：扫描课程包目录，为所有章节生成资源
  // ═══════════════════════════════════════════════════════════════════════════

  /// 扫描课程包的「理论」目录，为每个 MD 文件生成三种资源
  Future<List<GenerationResult>> generateAll({
    required String courseId,
    String sourceType = 'preset',
  }) async {
    final results = <GenerationResult>[];

    // 查找课程包的理论目录
    final dir = await _getCourseDir(courseId);
    final theoryDir = Directory('$dir${Platform.pathSeparator}理论');
    if (!await theoryDir.exists()) {
      // 尝试 courses/{courseId}/ 目录下的 MD 文件
      final courseDir = Directory(dir);
      if (await courseDir.exists()) {
        final mdFiles = await courseDir
            .list()
            .where((f) => f.path.endsWith('.md'))
            .toList();
        for (final mdFile in mdFiles) {
          final name = mdFile.path.split(Platform.pathSeparator).last
              .replaceAll(RegExp(r'\.md$'), '');
          final r = await generateForChapter(
            courseId: courseId,
            chapterTitle: name,
            chapterMdPath: mdFile.path,
            sourceType: sourceType,
          );
          results.add(r);
        }
      }
      return results;
    }

    // 遍历理论目录下的 MD 文件
    final mdFiles = await theoryDir
        .list()
        .where((f) => f.path.endsWith('.md'))
        .toList();

    for (final mdFile in mdFiles) {
      final name = mdFile.path.split(Platform.pathSeparator).last
          .replaceAll(RegExp(r'\.md$'), '');
      final r = await generateForChapter(
        courseId: courseId,
        chapterTitle: name,
        chapterMdPath: mdFile.path,
        sourceType: sourceType,
      );
      results.add(r);
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 检查资源是否存在
  // ═══════════════════════════════════════════════════════════════════════════

  /// 检查指定章节的三种资源是否存在（文件实际存在）
  Future<ChapterResourceStatus> checkStatus({
    required String courseId,
    required String chapter,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final result = ChapterResourceStatus(chapter: chapter);

    final rows = await db.query(
      'resource_files',
      where: "course_id = ? AND chapter = ?",
      whereArgs: [courseId, chapter],
    );

    for (final row in rows) {
      final fileType = row['file_type']?.toString() ?? '';
      final filePath = row['file_path']?.toString() ?? '';
      final sourceType = row['source_type']?.toString() ?? 'preset';
      final exists = filePath.isNotEmpty && await File(filePath).exists();

      switch (fileType) {
        case 'pdf':
          result.pdfExists = exists;
          result.pdfSource = sourceType;
          result.pdfPath = filePath;
          break;
        case 'ppt':
          result.pptExists = exists;
          result.pptSource = sourceType;
          result.pptPath = filePath;
          break;
        case 'video':
          result.videoExists = exists;
          result.videoSource = sourceType;
          result.videoPath = filePath;
          break;
      }
    }

    return result;
  }

  Future<String> _getCourseDir(String courseId) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      return '${appDir.path}${Platform.pathSeparator}courses${Platform.pathSeparator}$courseId';
    } catch (_) {
      return 'courses${Platform.pathSeparator}$courseId';
    }
  }
}

/// 单章节生成结果
class GenerationResult {
  final String chapter;
  String? pdfPath;
  String? pptxPath;
  String? videoScriptPath;
  final List<String> generated = [];
  final List<String> errors = [];
  String? error;

  GenerationResult({required this.chapter});

  bool get hasError => error != null || errors.isNotEmpty;
  bool get isEmpty => generated.isEmpty;
}

/// 单章节资源状态
class ChapterResourceStatus {
  final String chapter;
  bool pdfExists = false;
  bool pptExists = false;
  bool videoExists = false;
  String pdfSource = '';
  String pptSource = '';
  String videoSource = '';
  String pdfPath = '';
  String pptPath = '';
  String videoPath = '';

  ChapterResourceStatus({required this.chapter});

  int get existCount =>
      [pdfExists, pptExists, videoExists].where((e) => e).length;

  bool get allExist => existCount == 3;
}
