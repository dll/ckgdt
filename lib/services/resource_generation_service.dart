import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';
import '../core/error_handler.dart';
import 'rich_resource_generation_service.dart';

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
    bool rich = true,
    PlannedChapter? plannedChapter,
  }) async {
    final result = GenerationResult(chapter: chapterTitle);

    if (rich && plannedChapter != null) {
      try {
        return await _generateRichResourcesForChapter(
          courseId: courseId,
          chapter: plannedChapter,
          sourceType: sourceType,
        );
      } catch (e, st) {
        swallowDebug(e, tag: 'ResourceGen.richChapter', stack: st);
        result.errors.add('富资源生成失败: $e');
        return result;
      }
    }

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
      where:
          "course_id = ? AND file_type = 'pdf' AND chapter = ? AND source_type = ?",
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
      final fontData =
          await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      font = pw.Font.ttf(fontData);
    } catch (_) {}
    try {
      final boldData =
          await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
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
            style: pw.TextStyle(
                font: font, fontSize: 16, color: PdfColors.grey600),
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
          style: pw.TextStyle(
              font: font, fontSize: 15, fontWeight: pw.FontWeight.bold),
        ));
      } else if (trimmed.startsWith('### ')) {
        children.add(pw.SizedBox(height: 8));
        children.add(pw.Text(
          trimmed.substring(4),
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
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
      where:
          "course_id = ? AND file_type = 'ppt' AND chapter = ? AND source_type = ?",
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
      where:
          "course_id = ? AND file_type = 'video' AND chapter = ? AND source_type = ?",
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
        'description':
            '[${sourceType == 'preset' ? '预制' : 'AI生成'}] $title 视频脚本',
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
    bool rich = true,
  }) async {
    final results = <GenerationResult>[];

    final dir = await _getCourseDir(courseId);
    final planned = await _loadPlannedChapters(dir);
    if (planned.isNotEmpty) {
      await _clearGeneratedResources(courseId, sourceType);
      for (var i = 0; i < planned.length; i++) {
        final chapter = planned[i];
        final title = chapter.title;
        onProgress?.call(title, 'plan', i / planned.length);
        final mdContent = _teachingResourceMarkdown(chapter);
        final chapterMdPath =
            '$dir${Platform.pathSeparator}理论${Platform.pathSeparator}${_safeFileName(title)}-教学资源.md';
        await File(chapterMdPath).parent.create(recursive: true);
        await File(chapterMdPath).writeAsString(mdContent);
        final r = await generateForChapter(
          courseId: courseId,
          chapterTitle: title,
          chapterMdPath: chapterMdPath,
          sourceType: sourceType,
          rich: rich,
          plannedChapter: chapter,
        );
        results.add(r);
      }
      onProgress?.call('', 'done', 1.0);
      return results;
    }

    // 查找课程包的理论目录
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
          final name = mdFile.path
              .split(Platform.pathSeparator)
              .last
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
    final mdFiles = (await theoryDir
        .list()
        .where((f) => f.path.endsWith('.md'))
        .toList())
      ..sort(
          (a, b) => _chapterSortKey(a.path).compareTo(_chapterSortKey(b.path)));

    for (final mdFile in mdFiles) {
      final name = mdFile.path
          .split(Platform.pathSeparator)
          .last
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

  Future<void> _clearGeneratedResources(
      String courseId, String sourceType) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'resource_files',
      columns: ['file_path'],
      where:
          "course_id = ? AND source_type = ? AND file_type IN ('pdf', 'ppt', 'video')",
      whereArgs: [courseId, sourceType],
    );
    for (final row in rows) {
      final path = row['file_path']?.toString() ?? '';
      if (path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        swallowDebug(e, tag: 'ResourceGen.clearFile');
      }
    }
    await db.delete(
      'resource_files',
      where:
          "course_id = ? AND source_type = ? AND file_type IN ('pdf', 'ppt', 'video')",
      whereArgs: [courseId, sourceType],
    );
  }

  Future<List<PlannedChapter>> _loadPlannedChapters(String courseDir) async {
    final lazyFile = File(
      '$courseDir${Platform.pathSeparator}配置${Platform.pathSeparator}lazy_generation.json',
    );
    final chaptersFile = File(
      '$courseDir${Platform.pathSeparator}配置${Platform.pathSeparator}chapters.json',
    );
    final chapterDetails = <int, Map<String, dynamic>>{};
    if (await chaptersFile.exists()) {
      try {
        final list = jsonDecode(await chaptersFile.readAsString()) as List;
        for (final item in list.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final number = int.tryParse(map['number']?.toString() ?? '') ?? 0;
          if (number > 0) chapterDetails[number] = map;
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'ResourceGen.loadChapters', stack: st);
      }
    }
    if (await lazyFile.exists()) {
      try {
        final json =
            jsonDecode(await lazyFile.readAsString()) as Map<String, dynamic>;
        final chapters = (json['chapters'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        final result = <PlannedChapter>[];
        for (final chapter in chapters) {
          final number =
              int.tryParse(chapter['chapter_number']?.toString() ?? '') ?? 0;
          if (number <= 0) continue;
          final detail = chapterDetails[number] ?? const {};
          final titleText =
              chapter['chapter_title']?.toString().trim().isNotEmpty == true
                  ? chapter['chapter_title'].toString().trim()
                  : detail['title']?.toString().trim() ?? '第$number章';
          result.add(PlannedChapter(
            number: number,
            title: _normalizeChapterTitle(number, titleText),
            description: detail['description']?.toString() ?? '',
            objectives: _stringList(detail['objectives']),
            keyPoints: _stringList(detail['key_points']),
            difficultPoints: _stringList(detail['difficult_points']),
          ));
        }
        result.sort((a, b) => a.number.compareTo(b.number));
        if (result.isNotEmpty) return result;
      } catch (e, st) {
        swallowDebug(e, tag: 'ResourceGen.loadLazyPlan', stack: st);
      }
    }
    final chapterDetailsList = chapterDetails.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return chapterDetailsList
        .map((entry) => PlannedChapter(
              number: entry.key,
              title: _normalizeChapterTitle(
                entry.key,
                entry.value['title']?.toString() ?? '第${entry.key}章',
              ),
              description: entry.value['description']?.toString() ?? '',
              objectives: _stringList(entry.value['objectives']),
              keyPoints: _stringList(entry.value['key_points']),
              difficultPoints: _stringList(entry.value['difficult_points']),
            ))
        .toList();
  }

  String _teachingResourceMarkdown(PlannedChapter chapter) {
    final objectives = chapter.objectives.isEmpty
        ? ['理解${chapter.shortTitle}的核心概念', '能够完成${chapter.shortTitle}相关学习任务']
        : chapter.objectives;
    final keyPoints =
        chapter.keyPoints.isEmpty ? [chapter.shortTitle] : chapter.keyPoints;
    final difficultPoints = chapter.difficultPoints.isEmpty
        ? ['知识应用与实践迁移']
        : chapter.difficultPoints;
    final buffer = StringBuffer()
      ..writeln('# ${chapter.title} 教学资源')
      ..writeln()
      ..writeln('## 教学目标')
      ..writeln()
      ..writeln(objectives.map((item) => '- $item').join('\n'))
      ..writeln()
      ..writeln('## 教学内容')
      ..writeln()
      ..writeln(chapter.description.isNotEmpty
          ? chapter.description
          : '${chapter.shortTitle}的概念体系、方法步骤、典型应用和学习证据。')
      ..writeln()
      ..writeln('## 教学重点')
      ..writeln()
      ..writeln(keyPoints.map((item) => '- $item').join('\n'))
      ..writeln()
      ..writeln('## 教学难点')
      ..writeln()
      ..writeln(difficultPoints.map((item) => '- $item').join('\n'))
      ..writeln()
      ..writeln('## PPT结构')
      ..writeln()
      ..writeln('- 章节导入：学习目标与知识图谱定位')
      ..writeln('- 核心讲解：概念、流程、方法与示例')
      ..writeln('- 课堂活动：讨论、演示、训练或案例分析')
      ..writeln('- 评价反馈：测验、作业、实践证据和达成要求')
      ..writeln()
      ..writeln('## PDF讲义')
      ..writeln()
      ..writeln('本讲义用于课前预习、课堂讲解和课后复习，内容与本章视频、PPT保持同一章节顺序，但侧重完整说明和可打印阅读。')
      ..writeln()
      ..writeln('## 视频脚本')
      ..writeln()
      ..writeln('### 00:00-01:00 导入')
      ..writeln('说明${chapter.shortTitle}在课程知识图谱中的位置，明确本节学习目标。')
      ..writeln()
      ..writeln('### 01:00-06:00 核心讲解')
      ..writeln('围绕教学重点展开讲解，并结合大纲要求说明概念、流程和应用场景。')
      ..writeln()
      ..writeln('### 06:00-09:00 示例与任务')
      ..writeln('通过案例、操作、训练或文本分析展示知识应用过程。')
      ..writeln()
      ..writeln('### 09:00-10:00 小结')
      ..writeln('总结本章关键知识点，说明测验、作业和实践证据要求。');
    return buffer.toString();
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
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}${Platform.pathSeparator}courses${Platform.pathSeparator}$courseId';
    } catch (_) {
      return 'courses${Platform.pathSeparator}$courseId';
    }
  }

  String _normalizeChapterTitle(int number, String value) {
    var title = value.trim();
    if (title.startsWith('第$number章')) return title;
    title =
        title.replaceFirst(RegExp(r'^第\s*[一二三四五六七八九十\d]+\s*章\s*'), '').trim();
    return '第$number章 $title'.trim();
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? <String>[] : <String>[text];
  }

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  int _chapterSortKey(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final m = RegExp(r'第\s*([一二三四五六七八九十\d]+)\s*章').firstMatch(name);
    if (m == null) return 9999;
    return _chapterNumber(m.group(1)!) ?? 9999;
  }

  int? _chapterNumber(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) return 10 + (digits[value.substring(1)] ?? 0);
    if (value.endsWith('十')) return (digits[value.substring(0, 1)] ?? 0) * 10;
    if (value.contains('十')) {
      final parts = value.split('十');
      return (digits[parts[0]] ?? 0) * 10 + (digits[parts[1]] ?? 0);
    }
    return digits[value];
  }

  // Rich resource generation: lesson plan -> PDF / PPTX / video

  /// Generates teachable resources driven by an AI lesson plan.
  Future<GenerationResult> _generateRichResourcesForChapter({
    required String courseId,
    required PlannedChapter chapter,
    required String sourceType,
  }) async {
    final result = GenerationResult(chapter: chapter.title);
    final db = await DatabaseHelper.instance.database;
    final courseDir = await _getCourseDir(courseId);

    final rich = RichResourceGenerationService();
    rich.onProgress = (fileType, progress) {
      onProgress?.call(chapter.title, fileType, progress);
    };

    // 查询课程名称，避免 RichResourceGenerationService 重复查库
    final courseRows = await db.query(
      'courses',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [courseId],
    );
    final courseName = courseRows.isNotEmpty
        ? (courseRows.first['name']?.toString() ?? '')
        : '';

    final paths = await rich.generateForChapter(
      courseId: courseId,
      chapterTitle: chapter.title,
      chapterShortTitle: chapter.shortTitle,
      description: chapter.description,
      objectives: chapter.objectives,
      keyPoints: chapter.keyPoints,
      difficultPoints: chapter.difficultPoints,
      sourceType: sourceType,
      outputBaseDir: courseDir,
      courseName: courseName,
    );

    if (paths['pdf'] != null) {
      result.pdfPath = paths['pdf'];
      result.generated.add('pdf');
      await db.insert(
        'resource_files',
        {
          'course_id': courseId,
          'file_name': paths['pdf']!.split(Platform.pathSeparator).last,
          'file_path': paths['pdf']!,
          'file_type': 'pdf',
          'chapter': chapter.title,
          'description': '[LessonPlan] ${chapter.title} PDF',
          'source_type': sourceType,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    if (paths['ppt'] != null) {
      result.pptxPath = paths['ppt'];
      result.generated.add('ppt');
      await db.insert(
        'resource_files',
        {
          'course_id': courseId,
          'file_name': paths['ppt']!.split(Platform.pathSeparator).last,
          'file_path': paths['ppt']!,
          'file_type': 'ppt',
          'chapter': chapter.title,
          'description': '[LessonPlan] ${chapter.title} PPTX',
          'source_type': sourceType,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    if (paths['video'] != null) {
      result.videoScriptPath = paths['video'];
      result.generated.add('video');
      await db.insert(
        'resource_files',
        {
          'course_id': courseId,
          'file_name': paths['video']!.split(Platform.pathSeparator).last,
          'file_path': paths['video']!,
          'file_type': 'video',
          'chapter': chapter.title,
          'description': '[LessonPlan] ${chapter.title} Video',
          'source_type': sourceType,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    return result;
  }
}

class PlannedChapter {
  final int number;
  final String title;
  final String description;
  final List<String> objectives;
  final List<String> keyPoints;
  final List<String> difficultPoints;

  const PlannedChapter({
    required this.number,
    required this.title,
    required this.description,
    required this.objectives,
    required this.keyPoints,
    required this.difficultPoints,
  });

  String get shortTitle =>
      title.replaceFirst(RegExp(r'^第\s*[一二三四五六七八九十\d]+\s*章\s*'), '').trim();
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
