import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import '../data/local/material_dao.dart';
import '../data/models/material_model.dart';
import 'ai_service.dart';
import 'plantuml_service.dart';

/// 课件工坊服务 — 教案→MD→PDF/UML/语音/视频 全流水线
class CoursewareService {
  final AiService _aiService = AiService();
  final MaterialDao _materialDao = MaterialDao();

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 1: 教案生成
  // ═══════════════════════════════════════════════════════════════════════════

  /// 生成结构化教案（JSON 格式）
  /// 返回: { title, chapter, classHours, objectives[], keyPoints[],
  ///         sections: [{ title, duration, content, activities, notes }],
  ///         experiments: [{ name, objective, steps[], deliverables }],
  ///         homework }
  Future<Map<String, dynamic>> generateLessonPlan({
    required String topic,
    String? chapter,
    int classHours = 2,
    String? additionalRequirements,
  }) async {
    const system = '''你是一位资深的移动应用开发课程教师，擅长制定教学教案。
请用中文回复，回复必须是合法的 JSON 对象。
你的教案应结构清晰、内容专业、可操作性强。''';

    final prompt = '''
请为"$topic"${chapter != null ? '（$chapter）' : ''}生成一份 $classHours 课时的教学教案。
${additionalRequirements != null ? '额外要求: $additionalRequirements' : ''}

要求返回 JSON 对象，格式如下：
{
  "title": "课程标题",
  "chapter": "章节",
  "classHours": $classHours,
  "objectives": ["教学目标1", "教学目标2", "教学目标3"],
  "keyPoints": ["重点1", "重点2"],
  "difficulties": ["难点1", "难点2"],
  "sections": [
    {
      "title": "章节标题",
      "duration": "15分钟",
      "content": "详细教学内容描述...",
      "activities": "教学活动描述（如讲授、演示、练习）",
      "codeExample": "相关代码示例（如有）",
      "notes": "教师备注"
    }
  ],
  "experiments": [
    {
      "name": "实验名称",
      "objective": "实验目标",
      "steps": ["步骤1", "步骤2", "步骤3"],
      "deliverables": "实验提交物"
    }
  ],
  "umlDiagrams": [
    {
      "type": "class/sequence/activity",
      "title": "图表标题",
      "description": "图表描述"
    }
  ],
  "homework": "课后作业描述",
  "references": ["参考资料1", "参考资料2"]
}

仅返回 JSON，不要包含其他文字。''';

    final raw = await _aiService.chat(
      [{'role': 'user', 'content': prompt}],
      systemPrompt: system,
    );

    // 提取 JSON 对象
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (match == null) {
      return _fallbackLessonPlan(topic, chapter, classHours);
    }
    try {
      return jsonDecode(match.group(0)!) as Map<String, dynamic>;
    } catch (_) {
      return _fallbackLessonPlan(topic, chapter, classHours);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 2: 内容生成 — Markdown
  // ═══════════════════════════════════════════════════════════════════════════

  /// 从教案生成完整的 Markdown 文档
  String generateMarkdown(Map<String, dynamic> lessonPlan) {
    final buf = StringBuffer();
    final title = lessonPlan['title'] ?? '教学课件';
    final chapter = lessonPlan['chapter'] ?? '';
    final classHours = lessonPlan['classHours'] ?? 2;

    // 标题
    buf.writeln('# $title');
    if (chapter.toString().isNotEmpty) buf.writeln('\n> $chapter');
    buf.writeln('\n**课时**: ${classHours}课时\n');

    // 教学目标
    final objectives = lessonPlan['objectives'] as List? ?? [];
    if (objectives.isNotEmpty) {
      buf.writeln('## 一、教学目标\n');
      for (var i = 0; i < objectives.length; i++) {
        buf.writeln('${i + 1}. ${objectives[i]}');
      }
      buf.writeln();
    }

    // 重点难点
    final keyPoints = lessonPlan['keyPoints'] as List? ?? [];
    final difficulties = lessonPlan['difficulties'] as List? ?? [];
    if (keyPoints.isNotEmpty || difficulties.isNotEmpty) {
      buf.writeln('## 二、重点与难点\n');
      if (keyPoints.isNotEmpty) {
        buf.writeln('### 教学重点');
        for (final kp in keyPoints) {
          buf.writeln('- $kp');
        }
        buf.writeln();
      }
      if (difficulties.isNotEmpty) {
        buf.writeln('### 教学难点');
        for (final d in difficulties) {
          buf.writeln('- $d');
        }
        buf.writeln();
      }
    }

    // 教学过程
    final sections = lessonPlan['sections'] as List? ?? [];
    if (sections.isNotEmpty) {
      buf.writeln('## 三、教学过程\n');
      for (var i = 0; i < sections.length; i++) {
        final s = sections[i] as Map<String, dynamic>;
        buf.writeln('### ${i + 1}. ${s['title'] ?? '环节${i + 1}'}');
        buf.writeln('\n**时间**: ${s['duration'] ?? '—'}');
        if (s['activities'] != null) {
          buf.writeln('\n**教学活动**: ${s['activities']}');
        }
        buf.writeln('\n${s['content'] ?? ''}');
        if (s['codeExample'] != null &&
            s['codeExample'].toString().isNotEmpty) {
          buf.writeln('\n```java');
          buf.writeln(s['codeExample']);
          buf.writeln('```');
        }
        if (s['notes'] != null && s['notes'].toString().isNotEmpty) {
          buf.writeln('\n> 💡 **教师备注**: ${s['notes']}');
        }
        buf.writeln();
      }
    }

    // 实验项目
    final experiments = lessonPlan['experiments'] as List? ?? [];
    if (experiments.isNotEmpty) {
      buf.writeln('## 四、实验项目\n');
      for (var i = 0; i < experiments.length; i++) {
        final e = experiments[i] as Map<String, dynamic>;
        buf.writeln('### 实验${i + 1}: ${e['name'] ?? ''}');
        buf.writeln('\n**目标**: ${e['objective'] ?? ''}');
        final steps = e['steps'] as List? ?? [];
        if (steps.isNotEmpty) {
          buf.writeln('\n**实验步骤**:');
          for (var j = 0; j < steps.length; j++) {
            buf.writeln('${j + 1}. ${steps[j]}');
          }
        }
        buf.writeln('\n**提交物**: ${e['deliverables'] ?? ''}');
        buf.writeln();
      }
    }

    // UML 图表说明
    final umlDiagrams = lessonPlan['umlDiagrams'] as List? ?? [];
    if (umlDiagrams.isNotEmpty) {
      buf.writeln('## 五、UML 图表\n');
      for (final uml in umlDiagrams) {
        final u = uml as Map<String, dynamic>;
        buf.writeln('### ${u['title'] ?? 'UML图'}');
        buf.writeln('\n- **类型**: ${u['type'] ?? 'class'}');
        buf.writeln('- **说明**: ${u['description'] ?? ''}');
        buf.writeln();
      }
    }

    // 课后作业
    if (lessonPlan['homework'] != null) {
      buf.writeln('## 六、课后作业\n');
      buf.writeln(lessonPlan['homework']);
      buf.writeln();
    }

    // 参考资料
    final refs = lessonPlan['references'] as List? ?? [];
    if (refs.isNotEmpty) {
      buf.writeln('## 参考资料\n');
      for (var i = 0; i < refs.length; i++) {
        buf.writeln('${i + 1}. ${refs[i]}');
      }
    }

    buf.writeln('\n---\n*由 AI 课件工坊自动生成*');
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 2b: 从代码生成 PUML
  // ═══════════════════════════════════════════════════════════════════════════

  /// 从 Java/Dart/Kotlin 源代码分析并生成 PlantUML 代码
  Future<String> generatePumlFromCode({
    required String code,
    required String diagramType, // class, sequence, activity
    String? language,
    String? context,
  }) async {
    const system = '''你是一位资深软件架构师和 UML 专家。
根据提供的源代码，分析其结构并生成对应的 PlantUML 代码。
只返回 @startuml ... @enduml 代码块，不要其他内容。
使用中文标签和注释。''';

    final typeDesc = {
          'class': '类图（展示类的属性、方法和类之间的关系）',
          'sequence': '时序图（展示方法调用的交互流程）',
          'activity': '活动图（展示业务逻辑的流程）',
          'component': '组件图（展示模块间的依赖关系）',
        }[diagramType] ??
        '类图';

    final prompt = '''
请分析以下${language ?? ''}源代码，生成一个 $typeDesc 的 PlantUML 代码：

```
$code
```

${context != null ? '上下文说明: $context' : ''}

要求：
- 使用中文标签
- 包含完整的 @startuml 和 @enduml
- 类图需包含属性和方法
- 时序图需展示主要交互流程
- 风格专业简洁、配色美观
''';

    final raw = await _aiService.chat(
      [{'role': 'user', 'content': prompt}],
      systemPrompt: system,
    );
    final match = RegExp(r'@startuml[\s\S]*?@enduml').firstMatch(raw);
    return match?.group(0) ?? raw;
  }

  /// 生成教案中所有 UML 图的 PUML 代码
  Future<List<Map<String, String>>> generateAllPuml(
    Map<String, dynamic> lessonPlan,
  ) async {
    final umlDiagrams = lessonPlan['umlDiagrams'] as List? ?? [];
    final results = <Map<String, String>>[];

    for (final uml in umlDiagrams) {
      final u = uml as Map<String, dynamic>;
      final type = u['type']?.toString() ?? 'class';
      final title = u['title']?.toString() ?? 'UML图';
      final desc = u['description']?.toString() ?? '';

      try {
        final puml = await _aiService.generatePuml(
          '$title - $desc',
          diagramType: type,
        );
        results.add({
          'title': title,
          'type': type,
          'puml': puml,
        });
      } catch (e) {
        debugPrint('CoursewareService: generatePuml failed for $title: $e');
      }
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 2c: PUML → PNG 渲染
  // ═══════════════════════════════════════════════════════════════════════════

  /// 渲染 PUML 代码为 PNG 图片（通过 Kroki 或 PlantUML 服务）
  Future<Uint8List?> renderPumlToPng(String pumlCode) async {
    try {
      final service = PlantUmlService();
      return await service.render(pumlCode);
    } catch (e) {
      debugPrint('CoursewareService: renderPumlToPng error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 3: 导出 — PDF 增强版（含 UML 图）
  // ═══════════════════════════════════════════════════════════════════════════

  /// 从教案生成增强版 PDF（含 UML 图）
  Future<String?> generateEnhancedPdf({
    required Map<String, dynamic> lessonPlan,
    List<Uint8List>? umlImages,
  }) async {
    if (kIsWeb) return null;

    try {
      final pdf = pw.Document();
      final title = lessonPlan['title']?.toString() ?? '教学课件';
      final chapter = lessonPlan['chapter']?.toString();

      // 加载中文字体 — pdf 包只支持 .ttf，不支持 .ttc
      pw.Font? font;
      pw.Font? boldFont;

      // 尝试多个字体源（按优先级）
      final fontCandidates = <String>[
        // Windows 系统字体（优先选择纯 .ttf 格式）
        if (Platform.isWindows) ...[
          'C:\\Windows\\Fonts\\simhei.ttf',   // 黑体（纯 TTF，兼容性最好）
          'C:\\Windows\\Fonts\\msyh.ttf',     // 微软雅黑（部分系统有 ttf 版）
        ],
        if (Platform.isMacOS) ...[
          '/System/Library/Fonts/PingFang.ttc',
        ],
        if (Platform.isLinux) ...[
          '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
          '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
        ],
      ];

      // 尝试从系统字体加载
      for (final fontPath in fontCandidates) {
        if (font != null) break;
        try {
          final file = File(fontPath);
          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            font = pw.Font.ttf(bytes.buffer.asByteData());
            debugPrint('CoursewareService: PDF font loaded from $fontPath');
          }
        } catch (e) {
          debugPrint('CoursewareService: font $fontPath failed: $e');
        }
      }

      // 回退到 assets 字体（NotoSansSC 是纯 TTF）
      if (font == null) {
        try {
          final fontData =
              await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
          font = pw.Font.ttf(fontData);
          debugPrint('CoursewareService: PDF font loaded from NotoSansSC asset');
        } catch (e) {
          debugPrint('CoursewareService: NotoSansSC asset failed: $e');
        }
      }

      // 最后尝试 assets 中的 ttc（可能在某些平台/pdf版本中可用）
      if (font == null) {
        try {
          final fontData =
              await rootBundle.load('assets/fonts/msyh.ttc');
          font = pw.Font.ttf(fontData);
          debugPrint('CoursewareService: PDF font loaded from msyh.ttc asset');
        } catch (e) {
          debugPrint('CoursewareService: msyh.ttc asset failed: $e');
        }
      }

      // 加载粗体字体
      if (Platform.isWindows) {
        for (final boldPath in [
          'C:\\Windows\\Fonts\\simhei.ttf',  // 黑体可同时作粗体
          'C:\\Windows\\Fonts\\msyhbd.ttf',  // 微软雅黑粗体（可能不存在）
        ]) {
          if (boldFont != null) break;
          try {
            final file = File(boldPath);
            if (file.existsSync()) {
              final bytes = file.readAsBytesSync();
              boldFont = pw.Font.ttf(bytes.buffer.asByteData());
            }
          } catch (_) {}
        }
      }
      boldFont ??= font;

      if (font == null) {
        debugPrint('CoursewareService: WARNING — no Chinese font available, '
            'PDF will use Helvetica (Chinese text will not render)');
      }

      final theme = font != null
          ? pw.ThemeData.withFont(base: font, bold: boldFont ?? font)
          : null;

      // ─── 封面页 ──────────────────────────────────────────────────────
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [
                PdfColor.fromInt(0xFF1677FF),
                PdfColor.fromInt(0xFF0958D9),
              ],
            ),
          ),
          child: pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 36,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
                if (chapter != null) ...[
                  pw.SizedBox(height: 16),
                  pw.Text(chapter,
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 20,
                          color: const PdfColor(1, 1, 1, 0.7))),
                ],
                pw.SizedBox(height: 8),
                pw.Text(
                    '${lessonPlan['classHours'] ?? 2} 课时',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 16,
                        color: const PdfColor(1, 1, 1, 0.5))),
                pw.SizedBox(height: 32),
                pw.Text('移动应用开发知识图谱教学系统',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 14,
                        color: const PdfColor(1, 1, 1, 0.5))),
              ],
            ),
          ),
        ),
      ));

      // ─── 教学目标页 ──────────────────────────────────────────────────
      final objectives = lessonPlan['objectives'] as List? ?? [];
      final keyPoints = lessonPlan['keyPoints'] as List? ?? [];
      final difficulties = lessonPlan['difficulties'] as List? ?? [];

      if (objectives.isNotEmpty) {
        pdf.addPage(_buildContentPage(
          theme: theme,
          font: font,
          title: '教学目标',
          items: objectives.map((o) => '• $o').toList().cast<String>(),
          extras: [
            if (keyPoints.isNotEmpty)
              '重点: ${keyPoints.join(', ')}',
            if (difficulties.isNotEmpty)
              '难点: ${difficulties.join(', ')}',
          ],
          slideNum: 2,
        ));
      }

      // ─── 教学过程 — 每个 section 一页 ──────────────────────────────
      final sections = lessonPlan['sections'] as List? ?? [];
      for (var i = 0; i < sections.length; i++) {
        final s = sections[i] as Map<String, dynamic>;
        final items = <String>[];
        if (s['content'] != null) {
          // 按行拆分内容，每行作为独立条目
          final contentStr = s['content'].toString().trim();
          if (contentStr.isNotEmpty) {
            final lines = contentStr.split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .toList();
            items.addAll(lines);
          }
        }
        if (s['activities'] != null) {
          items.add('教学活动: ${s['activities']}');
        }
        if (s['codeExample'] != null &&
            s['codeExample'].toString().isNotEmpty) {
          items.add('代码示例: ${s['codeExample']}');
        }

        pdf.addPage(_buildContentPage(
          theme: theme,
          font: font,
          title: s['title']?.toString() ?? '环节 ${i + 1}',
          subtitle: '时间: ${s['duration'] ?? '—'}',
          items: items,
          notes: s['notes']?.toString(),
          slideNum: 3 + i,
        ));
      }

      // ─── UML 图表页 ─────────────────────────────────────────────────
      if (umlImages != null) {
        for (var i = 0; i < umlImages.length; i++) {
          final umlList = lessonPlan['umlDiagrams'] as List? ?? [];
          final umlTitle = i < umlList.length
              ? (umlList[i] as Map)['title']?.toString() ?? 'UML图 ${i + 1}'
              : 'UML图 ${i + 1}';

          pdf.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            theme: theme,
            build: (_) => pw.Container(
              padding: const pw.EdgeInsets.all(32),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(umlTitle,
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF1677FF))),
                  pw.SizedBox(height: 16),
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Image(
                        pw.MemoryImage(umlImages[i]),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ));
        }
      }

      // ─── 实验项目页 ─────────────────────────────────────────────────
      final experiments = lessonPlan['experiments'] as List? ?? [];
      for (var i = 0; i < experiments.length; i++) {
        final e = experiments[i] as Map<String, dynamic>;
        final steps = (e['steps'] as List? ?? [])
            .asMap()
            .entries
            .map((entry) => '${entry.key + 1}. ${entry.value}')
            .toList()
            .cast<String>();
        pdf.addPage(_buildContentPage(
          theme: theme,
          font: font,
          title: '实验: ${e['name'] ?? '实验${i + 1}'}',
          subtitle: '目标: ${e['objective'] ?? ''}',
          items: steps,
          notes: '提交物: ${e['deliverables'] ?? ''}',
          slideNum: 3 + sections.length + (umlImages?.length ?? 0) + i,
        ));
      }

      // ─── 总结页 ─────────────────────────────────────────────────────
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [
                PdfColor.fromInt(0xFF0958D9),
                PdfColor.fromInt(0xFF1677FF),
              ],
            ),
          ),
          child: pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('课后作业',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 28,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Text(
                  lessonPlan['homework']?.toString() ?? '无',
                  style: pw.TextStyle(
                      font: font,
                      fontSize: 16,
                      color: const PdfColor(1, 1, 1, 0.8)),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 40),
                pw.Text('谢谢！',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 36,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ),
      ));

      // ─── 保存 ──────────────────────────────────────────────────────
      final pdfBytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final coursewareDir =
          Directory('${dir.path}/courseware');
      if (!coursewareDir.existsSync()) {
        coursewareDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeTitle =
          title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final filePath =
          '${coursewareDir.path}/${safeTitle}_$timestamp.pdf';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      // 保存到素材库
      final material = MaterialModel(
        title: '$title - 教案课件',
        type: 'pdf',
        filePath: filePath,
        chapter: chapter,
        createdAt: DateTime.now().toIso8601String(),
        size: pdfBytes.length,
      );
      await _materialDao.insert(material);

      return filePath;
    } catch (e, st) {
      debugPrint('CoursewareService: generateEnhancedPdf error: $e');
      debugPrint('CoursewareService: stackTrace: $st');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 3b: 导出 Markdown 文件
  // ═══════════════════════════════════════════════════════════════════════════

  /// 将 Markdown 内容保存为文件
  Future<String?> exportMarkdownFile({
    required String markdown,
    required String title,
    String? chapter,
  }) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final coursewareDir = Directory('${dir.path}/courseware');
      if (!coursewareDir.existsSync()) {
        coursewareDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeTitle =
          title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final filePath =
          '${coursewareDir.path}/${safeTitle}_$timestamp.md';
      final file = File(filePath);
      await file.writeAsString(markdown, encoding: utf8);

      // 保存到素材库
      final material = MaterialModel(
        title: '$title - 教案文档',
        type: 'script',
        content: markdown,
        filePath: filePath,
        chapter: chapter,
        createdAt: DateTime.now().toIso8601String(),
        size: utf8.encode(markdown).length,
      );
      await _materialDao.insert(material);

      return filePath;
    } catch (e) {
      debugPrint('CoursewareService: exportMarkdownFile error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 4: 生成讲解脚本（TTS 文本）
  // ═══════════════════════════════════════════════════════════════════════════

  /// 从教案生成 TTS 朗读脚本（分段，每段对应一张幻灯片）
  Future<List<Map<String, String>>> generateNarrationScripts(
    Map<String, dynamic> lessonPlan,
  ) async {
    const system = '''你是一位专业的移动应用开发课程讲师，正在录制教学视频。
请用中文、口语化、清晰的语言生成教学视频旁白脚本。
回复必须是合法的 JSON 数组。''';

    final title = lessonPlan['title'] ?? '';
    final sections = lessonPlan['sections'] as List? ?? [];
    final sectionTitles = sections
        .map((s) => (s as Map)['title']?.toString() ?? '')
        .join(', ');

    final prompt = '''
为教案"$title"生成视频旁白脚本。教案包含以下教学环节: $sectionTitles

请为每个幻灯片（含封面、每个教学环节、实验说明、总结）生成一段旁白。
返回 JSON 数组，格式:
[
  {"slide": "封面", "narration": "同学们好，今天我们学习..."},
  {"slide": "教学目标", "narration": "本节课的教学目标包括..."},
  ...
]

要求:
- 每段旁白 100-200 字，适合 TTS 朗读
- 语言口语化、节奏自然
- 仅返回 JSON，不要其他文字
''';

    final raw = await _aiService.chat(
      [{'role': 'user', 'content': prompt}],
      systemPrompt: system,
    );

    final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (match == null) return [];
    try {
      final list = jsonDecode(match.group(0)!) as List;
      return list
          .map((item) => {
                'slide': (item as Map)['slide']?.toString() ?? '',
                'narration': item['narration']?.toString() ?? '',
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 辅助：保存 UML 图片
  // ═══════════════════════════════════════════════════════════════════════════

  /// 保存 UML PNG 图片到课件目录
  Future<String?> saveUmlImage({
    required Uint8List imageBytes,
    required String title,
  }) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final umlDir = Directory('${dir.path}/courseware/uml');
      if (!umlDir.existsSync()) {
        umlDir.createSync(recursive: true);
      }

      final safeTitle =
          title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${umlDir.path}/${safeTitle}_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      return filePath;
    } catch (e) {
      debugPrint('CoursewareService: saveUmlImage error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 获取课件目录
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> getCoursewareDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final coursewareDir = Directory('${dir.path}/courseware');
    if (!coursewareDir.existsSync()) {
      coursewareDir.createSync(recursive: true);
    }
    return coursewareDir.path;
  }

  // ─── 内部 ──────────────────────────────────────────────────────────────────

  /// 构建单个内容项的 widget（根据内容类型智能选择样式）
  pw.Widget _buildContentItem(String item, pw.Font? font) {
    final trimmed = item.trim();

    // ── 代码示例：灰色背景 + 等宽小字体 ──
    if (trimmed.startsWith('代码示例:') || trimmed.startsWith('代码示例：')) {
      final code = trimmed.replaceFirst(RegExp(r'^代码示例[：:]'), '').trim();
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF424242),
                borderRadius:
                    pw.BorderRadius.only(
                      topLeft: pw.Radius.circular(4),
                      topRight: pw.Radius.circular(4)),
              ),
              child: pw.Text('Code',
                  style: pw.TextStyle(
                      font: font,
                      fontSize: 9,
                      color: PdfColors.white)),
            ),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF5F5F5),
                border: pw.Border.all(
                    color: PdfColor.fromInt(0xFFE0E0E0), width: 0.5),
                borderRadius: const pw.BorderRadius.only(
                    topRight: pw.Radius.circular(4),
                    bottomLeft: pw.Radius.circular(4),
                    bottomRight: pw.Radius.circular(4)),
              ),
              child: pw.Text(code,
                  style: pw.TextStyle(
                      font: pw.Font.courier(),
                      fontSize: 11,
                      color: PdfColor.fromInt(0xFF37474F),
                      lineSpacing: 4)),
            ),
          ],
        ),
      );
    }

    // ── 教学活动：带强调色前缀 ──
    if (trimmed.startsWith('教学活动:') || trimmed.startsWith('教学活动：')) {
      final activity =
          trimmed.replaceFirst(RegExp(r'^教学活动[：:]'), '').trim();
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 2, right: 8),
              width: 18,
              height: 18,
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFF9800),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(9)),
              ),
              child: pw.Center(
                child: pw.Text('▶',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 9,
                        color: PdfColors.white)),
              ),
            ),
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: '教学活动  ',
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFFE65100)),
                    ),
                    pw.TextSpan(
                      text: activity,
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 13,
                          color: PdfColor.fromInt(0xFF424242)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── 表格内容：检测以 "|" 开头的行并渲染为 Table ──
    if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.split('|').length >= 4) {
      final cells = trimmed
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      if (cells.length >= 2) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Table(
            border: pw.TableBorder.all(
                color: PdfColor.fromInt(0xFFBDBDBD), width: 0.5),
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE3F2FD)),
                children: cells
                    .map((c) => pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(c,
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFF1565C0))),
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      }
    }

    // ── 普通内容：添加圆点前缀 ──
    final bool alreadyHasBullet = trimmed.startsWith('•') ||
        trimmed.startsWith('-') ||
        trimmed.startsWith('·') ||
        RegExp(r'^\d+[.、]').hasMatch(trimmed);
    final String displayText = alreadyHasBullet ? trimmed : '•  $trimmed';

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Text(displayText,
                style: pw.TextStyle(
                    font: font,
                    fontSize: 14,
                    color: PdfColor.fromInt(0xFF333333),
                    lineSpacing: 3)),
          ),
        ],
      ),
    );
  }

  pw.Page _buildContentPage({
    required pw.ThemeData? theme,
    required pw.Font? font,
    required String title,
    String? subtitle,
    required List<String> items,
    List<String>? extras,
    String? notes,
    int slideNum = 1,
  }) {
    // 限制每页内容量，避免 Column 溢出
    // A4 landscape 可用高度约 500pt，标题/副标题约 80pt，备注约 50pt
    // 每个 content item 约 30pt，安全上限约 12 个条目
    final safeItems = items.length > 12 ? items.sublist(0, 12) : items;

    return pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      theme: theme,
      build: (_) => pw.Container(
        padding: const pw.EdgeInsets.all(32),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // 标题
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: PdfColor.fromInt(0xFF1677FF),
                    width: 2,
                  ),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(title,
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF1677FF))),
                  ),
                  pw.Text('$slideNum',
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: PdfColors.grey)),
                ],
              ),
            ),
            if (subtitle != null) ...[
              pw.SizedBox(height: 10),
              pw.Text(subtitle,
                  style: pw.TextStyle(
                      font: font,
                      fontSize: 14,
                      color: PdfColors.grey700)),
            ],
            pw.SizedBox(height: 20),
            // 内容（智能样式渲染），限制条目数防溢出
            ...safeItems.map((item) {
              // 截断过长文本（单个条目限制 500 字）
              final truncated = item.length > 500
                  ? '${item.substring(0, 500)}...'
                  : item;
              return _buildContentItem(truncated, font);
            }),
            pw.SizedBox(height: 8),
            // 额外信息
            if (extras != null) ...[
              pw.Divider(
                  color: PdfColor.fromInt(0xFFE0E0E0), thickness: 0.5),
              pw.SizedBox(height: 6),
              ...extras.map((e) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(e,
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 12,
                            color: PdfColors.grey700,
                            fontWeight: pw.FontWeight.bold)),
                  )),
            ],
            pw.Spacer(),
            // 备注
            if (notes != null && notes.isNotEmpty)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF5F7FA),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border(
                    left: pw.BorderSide(
                        color: PdfColor.fromInt(0xFF1677FF), width: 3),
                  ),
                ),
                child: pw.Text('💡 $notes',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 10,
                        color: PdfColors.grey700)),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _fallbackLessonPlan(
      String topic, String? chapter, int hours) {
    return {
      'title': topic,
      'chapter': chapter ?? '',
      'classHours': hours,
      'objectives': ['了解$topic的基本概念', '掌握$topic的核心技术', '能够实践$topic相关操作'],
      'keyPoints': ['$topic核心概念'],
      'difficulties': ['$topic高级应用'],
      'sections': [
        {
          'title': '课程导入',
          'duration': '10分钟',
          'content': '介绍$topic的背景和重要性',
          'activities': '讲授+讨论',
          'notes': ''
        },
        {
          'title': '核心讲解',
          'duration': '${hours * 45 - 20}分钟',
          'content': '详细讲解$topic的核心内容',
          'activities': '讲授+演示',
          'notes': ''
        },
        {
          'title': '总结回顾',
          'duration': '10分钟',
          'content': '总结本节课重点',
          'activities': '讨论+答疑',
          'notes': ''
        },
      ],
      'experiments': [],
      'umlDiagrams': [],
      'homework': '复习$topic相关内容',
      'references': [],
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 教案 → 幻灯片（直接转换，不经过 Markdown 中间格式）
  // ═══════════════════════════════════════════════════════════════════════════

  /// 将结构化教案直接转换为高质量幻灯片数据
  ///
  /// 生成的幻灯片包含：封面信息 + 教学目标 + 重难点 + 每个教学环节 +
  /// 实验项目 + UML图表说明 + 课后作业 + 参考资料 + 总结
  List<Map<String, dynamic>> lessonPlanToSlides(
      Map<String, dynamic> lessonPlan) {
    final slides = <Map<String, dynamic>>[];
    final title = lessonPlan['title']?.toString() ?? '教学课件';
    final chapter = lessonPlan['chapter']?.toString() ?? '';
    final classHours = lessonPlan['classHours'] ?? 2;

    // ── 1. 课程概览 ──────────────────────────────────────────────────
    final objectives = lessonPlan['objectives'] as List? ?? [];
    final keyPoints = lessonPlan['keyPoints'] as List? ?? [];
    slides.add({
      'title': '课程概览',
      'subtitle': '$title | $chapter | ${classHours}课时',
      'bullets': [
        '【教学目标】',
        ...objectives.map((o) => '• $o'),
        if (keyPoints.isNotEmpty) '【教学重点】',
        ...keyPoints.map((k) => '• $k'),
      ],
    });

    // ── 2. 重点与难点 ────────────────────────────────────────────────
    final difficulties = lessonPlan['difficulties'] as List? ?? [];
    if (keyPoints.isNotEmpty || difficulties.isNotEmpty) {
      slides.add({
        'title': '重点与难点',
        'bullets': [
          if (keyPoints.isNotEmpty) '【教学重点】',
          ...keyPoints.map((k) => '• $k'),
          if (difficulties.isNotEmpty) '【教学难点】',
          ...difficulties.map((d) => '• $d'),
        ],
      });
    }

    // ── 3. 教学过程 — 每个环节一张幻灯片 ──────────────────────────────
    final sections = lessonPlan['sections'] as List? ?? [];
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i] as Map<String, dynamic>;
      final sTitle = s['title']?.toString() ?? '环节${i + 1}';
      final duration = s['duration']?.toString() ?? '';
      final content = s['content']?.toString() ?? '';
      final activities = s['activities']?.toString() ?? '';
      final codeExample = s['codeExample']?.toString() ?? '';
      final notes = s['notes']?.toString() ?? '';

      final bullets = <String>[];
      if (duration.isNotEmpty) bullets.add('⏱ 时间：$duration');
      if (activities.isNotEmpty) bullets.add('🎯 教学活动：$activities');

      // 解析 content 为要点列表
      final contentLines = content.split('\n');
      for (final line in contentLines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('- ') || trimmed.startsWith('• ')) {
          bullets.add('• ${trimmed.substring(2)}');
        } else if (RegExp(r'^\d+[.、]').hasMatch(trimmed)) {
          bullets.add('• ${trimmed.replaceFirst(RegExp(r'^\d+[.、]\s*'), '')}');
        } else {
          bullets.add('• $trimmed');
        }
      }

      final slide = <String, dynamic>{
        'title': sTitle,
        'subtitle': duration.isNotEmpty ? '时间：$duration' : null,
        'bullets': bullets.take(8).toList(), // 每页最多8个要点
      };

      if (codeExample.isNotEmpty) {
        slide['code'] = codeExample;
        slide['codeLanguage'] = 'java';
      }
      if (notes.isNotEmpty) {
        slide['notes'] = notes;
      }

      slides.add(slide);

      // 如果要点超过8个，创建续页
      if (bullets.length > 8) {
        slides.add({
          'title': '$sTitle（续）',
          'bullets': bullets.skip(8).toList(),
        });
      }
    }

    // ── 4. 实验项目 ──────────────────────────────────────────────────
    final experiments = lessonPlan['experiments'] as List? ?? [];
    for (var i = 0; i < experiments.length; i++) {
      final e = experiments[i] as Map<String, dynamic>;
      final eName = e['name']?.toString() ?? '实验${i + 1}';
      final eObj = e['objective']?.toString() ?? '';
      final eSteps = e['steps'] as List? ?? [];
      final eDeliverables = e['deliverables']?.toString() ?? '';

      slides.add({
        'title': '实验：$eName',
        'bullets': [
          if (eObj.isNotEmpty) '🎯 目标：$eObj',
          if (eSteps.isNotEmpty) '【实验步骤】',
          ...eSteps
              .asMap()
              .entries
              .map((entry) => '${entry.key + 1}. ${entry.value}'),
          if (eDeliverables.isNotEmpty) '📋 提交物：$eDeliverables',
        ],
      });
    }

    // ── 5. UML 图表说明 ──────────────────────────────────────────────
    final umlDiagrams = lessonPlan['umlDiagrams'] as List? ?? [];
    if (umlDiagrams.isNotEmpty) {
      final umlBullets = <String>[];
      for (final uml in umlDiagrams) {
        final u = uml as Map<String, dynamic>;
        umlBullets.add(
            '• ${u['title'] ?? 'UML图'}（${u['type'] ?? 'class'}）：${u['description'] ?? ''}');
      }
      slides.add({
        'title': 'UML 图表',
        'bullets': umlBullets,
      });
    }

    // ── 6. 课后作业 ──────────────────────────────────────────────────
    final homework = lessonPlan['homework']?.toString() ?? '';
    final references = lessonPlan['references'] as List? ?? [];
    if (homework.isNotEmpty || references.isNotEmpty) {
      slides.add({
        'title': '课后作业与参考资料',
        'bullets': [
          if (homework.isNotEmpty) '【课后作业】',
          if (homework.isNotEmpty) '• $homework',
          if (references.isNotEmpty) '【参考资料】',
          ...references.map((r) => '• $r'),
        ],
      });
    }

    // ── 7. 课程总结 ──────────────────────────────────────────────────
    slides.add({
      'title': '课程总结',
      'bullets': [
        '【本节要点回顾】',
        ...objectives.take(4).map((o) => '✅ $o'),
        if (keyPoints.isNotEmpty) '',
        '【下节预告】',
        '• 请完成课后作业，预习下一节内容',
      ],
    });

    return slides;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MD 文件解析 → 幻灯片数据
  // ═══════════════════════════════════════════════════════════════════════════

  /// 解析教学 Markdown 文件为幻灯片数据列表
  /// 支持格式: ### 幻灯片N：标题 → 自动拆分为独立幻灯片
  List<Map<String, dynamic>> parseMarkdownToSlides(String markdown) {
    final slides = <Map<String, dynamic>>[];
    final lines = markdown.split('\n');

    String? currentTitle;
    String? currentSubtitle;
    final currentBullets = <String>[];
    final currentCode = <String>[];
    String? currentNotes;
    bool inCodeBlock = false;
    String codeLanguage = '';

    void flushSlide() {
      if (currentTitle != null) {
        final slide = <String, dynamic>{
          'title': currentTitle,
          if (currentSubtitle != null) 'subtitle': currentSubtitle,
          'bullets':
              List<String>.from(currentBullets.where((b) => b.isNotEmpty)),
          if (currentCode.isNotEmpty)
            'code': currentCode.join('\n'),
          if (codeLanguage.isNotEmpty) 'codeLanguage': codeLanguage,
          if (currentNotes != null) 'notes': currentNotes,
        };
        slides.add(slide);
      }
      currentTitle = null;
      currentSubtitle = null;
      currentBullets.clear();
      currentCode.clear();
      currentNotes = null;
      codeLanguage = '';
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // 代码块
      if (trimmed.startsWith('```')) {
        if (inCodeBlock) {
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
          codeLanguage = trimmed.length > 3
              ? trimmed.substring(3).trim()
              : '';
        }
        continue;
      }

      if (inCodeBlock) {
        currentCode.add(line);
        continue;
      }

      // 幻灯片标题: ### 幻灯片N：xxx
      final slideMatch =
          RegExp(r'^###\s*幻灯片\d+[：:]\s*(.+)$').firstMatch(trimmed);
      if (slideMatch != null) {
        flushSlide();
        currentTitle = slideMatch.group(1)!.trim();
        continue;
      }

      // 标题行: - **标题**：xxx
      final titleMatch =
          RegExp(r'^-\s*\*\*标题\*\*[：:]\s*(.+)$').firstMatch(trimmed);
      if (titleMatch != null) {
        currentSubtitle = titleMatch.group(1)!.trim();
        continue;
      }

      // 章节标题: # or ## (作为新幻灯片)
      if (trimmed.startsWith('## ') && !trimmed.startsWith('### ')) {
        final title = trimmed.replaceFirst(RegExp(r'^##\s+'), '');
        if (title.startsWith('学前测验')) {
          // 学前测验 → 生成测验幻灯片（不跳过）
          flushSlide();
          _parseQuizSection(lines, i, slides);
        } else if (!title.startsWith('课件')) {
          flushSlide();
          currentTitle = title;
        }
        continue;
      }
      // # 标题只有后续有内容才创建幻灯片，避免空页
      if (trimmed.startsWith('# ')) {
        // 向后看是否紧跟 ### 幻灯片 或 ## 章节 → 如果是则跳过此 # 标题
        bool hasOwnContent = false;
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isEmpty) continue;
          if (next.startsWith('### ') || next.startsWith('## ')) break;
          hasOwnContent = true;
          break;
        }
        if (hasOwnContent) {
          final title = trimmed.replaceFirst(RegExp(r'^#\s+'), '');
          flushSlide();
          currentTitle = title;
        }
        continue;
      }

      // 加粗标题行: - **XXX**：(作为子标题)
      final boldLabelMatch =
          RegExp(r'^-?\s*\*\*(.+?)\*\*[：:]?\s*$').firstMatch(trimmed);
      if (boldLabelMatch != null && currentTitle != null) {
        currentBullets.add('【${boldLabelMatch.group(1)}】');
        continue;
      }

      // 普通列表项
      final bulletMatch =
          RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
      if (bulletMatch != null && currentTitle != null) {
        var text = bulletMatch.group(1)!;
        // 清理 Markdown 加粗
        text = text.replaceAll(RegExp(r'\*\*(.+?)\*\*'), '\$1');
        currentBullets.add(text);
        continue;
      }

      // 缩进列表项
      final indentMatch =
          RegExp(r'^\s{2,}[-*]\s+(.+)$').firstMatch(line);
      if (indentMatch != null && currentTitle != null) {
        var text = indentMatch.group(1)!;
        text = text.replaceAll(RegExp(r'\*\*(.+?)\*\*'), '\$1');
        currentBullets.add('  · $text');
        continue;
      }

      // 表格行
      if (trimmed.startsWith('|') && currentTitle != null) {
        if (!trimmed.contains('---')) {
          currentBullets.add(trimmed);
        }
        continue;
      }
    }
    flushSlide();
    return slides;
  }

  /// 解析学前测验章节，生成测验幻灯片
  void _parseQuizSection(
    List<String> lines,
    int startIdx,
    List<Map<String, dynamic>> slides,
  ) {
    // 收集测验题目
    final questions = <Map<String, String>>[];
    Map<String, String>? currentQ;
    final buffer = StringBuffer();

    for (var i = startIdx + 1; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      // 遇到下一个 ## 或 ### 标题就停止
      if (trimmed.startsWith('## ') || trimmed.startsWith('### ')) break;

      // 题目行: 1. / 2. / 3. etc.
      final qMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(trimmed);
      if (qMatch != null) {
        if (currentQ != null) questions.add(currentQ);
        currentQ = {'question': '${qMatch.group(1)}. ${qMatch.group(2)}'};
        buffer.clear();
        continue;
      }

      // 选项行: A) / A. / - A.
      final optMatch =
          RegExp(r'^[-\s]*([A-D])[.)]\s*(.+)$').firstMatch(trimmed);
      if (optMatch != null && currentQ != null) {
        buffer.write('${optMatch.group(1)}. ${optMatch.group(2)}  ');
        currentQ['options'] = buffer.toString();
        continue;
      }

      // 答案行
      if (trimmed.contains('答案') && currentQ != null) {
        currentQ['answer'] = trimmed;
        continue;
      }
    }
    if (currentQ != null) questions.add(currentQ);

    if (questions.isEmpty) return;

    // 每 2-3 道题生成一页幻灯片
    const perSlide = 2;
    for (var start = 0; start < questions.length; start += perSlide) {
      final end = (start + perSlide).clamp(0, questions.length);
      final chunk = questions.sublist(start, end);
      final bullets = <String>[];
      for (final q in chunk) {
        bullets.add('【${q['question']}】');
        if (q['options'] != null) {
          for (final opt in q['options']!.trim().split(RegExp(r'\s{2,}'))) {
            if (opt.trim().isNotEmpty) bullets.add('  · $opt');
          }
        }
      }
      final slideNum = (start ~/ perSlide) + 1;
      final totalPages = (questions.length / perSlide).ceil();
      slides.add({
        'title': '学前测验 ($slideNum/$totalPages)',
        'subtitle': '请思考以下问题',
        'bullets': bullets,
        'notes': chunk.map((q) => q['answer'] ?? '').join('\n'),
      });
    }
  }

  /// 从 MD 文件路径读取并解析
  Future<List<Map<String, dynamic>>> parseMdFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return [];
    final content = await file.readAsString(encoding: utf8);
    return parseMarkdownToSlides(content);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PPTX 生成 (via python-pptx)
  // ═══════════════════════════════════════════════════════════════════════════

  /// 检查 python-pptx 是否安装
  Future<bool> isPythonPptxInstalled() async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
        'pip', ['show', 'python-pptx'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 生成 PPTX 课件
  /// [slides] 每项: {title, subtitle?, bullets:[], code?, codeLanguage?, notes?}
  Future<String?> generatePptx({
    required String title,
    required List<Map<String, dynamic>> slides,
    String? chapter,
  }) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final coursewareDir = Directory('${dir.path}/courseware');
      if (!coursewareDir.existsSync()) {
        coursewareDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeTitle =
          title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final outputPath =
          '${coursewareDir.path}/${safeTitle}_$timestamp.pptx';

      // 将幻灯片数据写为 JSON 临时文件
      final tempDir = await getTemporaryDirectory();
      final dataFile = File('${tempDir.path}/slides_data.json');
      await dataFile.writeAsString(jsonEncode({
        'title': title,
        'chapter': chapter ?? '',
        'slides': slides,
        'output': outputPath.replaceAll('\\', '/'),
      }));

      // 生成 Python 脚本
      final scriptFile = File('${tempDir.path}/gen_pptx.py');
      await scriptFile.writeAsString(_pptxPythonScript());

      final result = await Process.run(
        'python',
        [scriptFile.path, dataFile.path],
        runInShell: true,
      ).timeout(const Duration(seconds: 120));

      // 清理
      if (scriptFile.existsSync()) scriptFile.deleteSync();
      if (dataFile.existsSync()) dataFile.deleteSync();

      if (result.exitCode != 0) {
        debugPrint('PPTX generation error: ${result.stderr}');
        return null;
      }

      final outFile = File(outputPath);
      if (!outFile.existsSync()) return null;

      // 保存到素材库
      final fileSize = outFile.lengthSync();
      final material = MaterialModel(
        title: '$title - PPT课件',
        type: 'pptx',
        filePath: outputPath,
        chapter: chapter,
        createdAt: DateTime.now().toIso8601String(),
        size: fileSize,
      );
      await _materialDao.insert(material);

      return outputPath;
    } catch (e) {
      debugPrint('CoursewareService: generatePptx error: $e');
      return null;
    }
  }

  /// 生成 python-pptx 的 Python 脚本（专业课件风格 — Prezi 动画+渐变+图标+视觉层次）
  String _pptxPythonScript() {
    return r'''
import json, sys, os

def main():
    if len(sys.argv) < 2:
        print("Usage: python gen_pptx.py data.json", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)

    from pptx import Presentation
    from pptx.util import Inches, Pt, Emu
    from pptx.dml.color import RGBColor
    from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
    from pptx.oxml.ns import qn
    from lxml import etree
    import copy

    CJK_FONT = '\u5fae\u8f6f\u96c5\u9ed1'

    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    title = data.get('title', '\u6559\u5b66\u8bfe\u4ef6')
    chapter = data.get('chapter', '')
    slides_data = data.get('slides', [])
    output = data.get('output', 'output.pptx')

    # ── 色彩主题 ──
    PRIMARY = RGBColor(0x0D, 0x47, 0xA1)       # 深蓝
    SECONDARY = RGBColor(0x1E, 0x88, 0xE5)      # 中蓝
    ACCENT = RGBColor(0x00, 0xAC, 0xC1)          # 青色
    WHITE = RGBColor(0xFF, 0xFF, 0xFF)
    LIGHT = RGBColor(0xF5, 0xF7, 0xFA)
    DARK_TEXT = RGBColor(0x1A, 0x1A, 0x2E)
    MID_TEXT = RGBColor(0x4A, 0x4A, 0x5A)
    LIGHT_TEXT = RGBColor(0x8A, 0x8A, 0x9A)
    CODE_BG = RGBColor(0x1E, 0x1E, 0x2E)
    CODE_FG = RGBColor(0xCD, 0xD6, 0xF4)
    SECTION_BG = RGBColor(0xE3, 0xF2, 0xFD)
    CARD_BG = RGBColor(0xFF, 0xFF, 0xFF)
    ORANGE = RGBColor(0xFF, 0x6F, 0x00)

    def set_font(p, size, color, bold=False, name=CJK_FONT):
        p.font.size = Pt(size)
        p.font.color.rgb = color
        p.font.bold = bold
        p.font.name = name
        for run in p.runs:
            run.font.size = Pt(size)
            run.font.color.rgb = color
            run.font.bold = bold
            run.font.name = name
            rPr = run._r.get_or_add_rPr()
            ea = rPr.find(qn('a:ea'))
            if ea is None:
                ea = rPr.makeelement(qn('a:ea'), {})
                rPr.append(ea)
            ea.set('typeface', name)

    def set_p_font(p, text, size, color, bold=False, name=CJK_FONT):
        p.text = text
        set_font(p, size, color, bold, name)

    def add_gradient_bg(slide, c1=PRIMARY, c2=SECONDARY):
        """Set 135-degree gradient background."""
        bg = slide.background
        fill = bg.fill
        fill.gradient()
        fill.gradient_angle = 135
        stops = fill.gradient_stops
        stops[0].color.rgb = c1
        stops[0].position = 0.0
        stops[1].color.rgb = c2
        stops[1].position = 1.0

    def add_solid_bg(slide, color):
        bg = slide.background
        fill = bg.fill
        fill.solid()
        fill.fore_color.rgb = color

    def add_shape_with_gradient(slide, left, top, width, height, c1, c2, corner_radius=0):
        """Add a rounded rectangle with gradient fill."""
        shape = slide.shapes.add_shape(
            5, left, top, width, height  # 5 = rounded rectangle
        )
        shape.fill.gradient()
        shape.fill.gradient_angle = 135
        stops = shape.fill.gradient_stops
        stops[0].color.rgb = c1
        stops[0].position = 0.0
        stops[1].color.rgb = c2
        stops[1].position = 1.0
        shape.line.fill.background()
        shape.shadow.inherit = False
        return shape

    def add_card(slide, left, top, width, height, shadow=True):
        """Add a white card with subtle shadow."""
        shape = slide.shapes.add_shape(
            5, left, top, width, height
        )
        shape.fill.solid()
        shape.fill.fore_color.rgb = CARD_BG
        shape.line.color.rgb = RGBColor(0xE0, 0xE0, 0xE0)
        shape.line.width = Pt(0.5)
        if shadow:
            shape.shadow.inherit = False
        return shape

    def add_entrance_anim(slide, shape, delay_ms=0, effect='fade'):
        """Add entrance animation to a shape."""
        try:
            tree = slide._element
            timing = tree.find(qn('p:timing'))
            if timing is None:
                timing = etree.SubElement(tree, qn('p:timing'))
            tnLst = timing.find(qn('p:tnLst'))
            if tnLst is None:
                tnLst = etree.SubElement(timing, qn('p:tnLst'))

            par = tnLst.find(qn('p:par'))
            if par is None:
                par = etree.SubElement(tnLst, qn('p:par'))
                cTn_root = etree.SubElement(par, qn('p:cTn'), {
                    'id': '1', 'dur': 'indefinite', 'restart': 'never', 'nodeType': 'tmRoot'
                })
                childTnLst = etree.SubElement(cTn_root, qn('p:childTnLst'))
                seq = etree.SubElement(childTnLst, qn('p:seq'), {'concurrent': '1', 'nextAc': 'seek'})
                seq_cTn = etree.SubElement(seq, qn('p:cTn'), {
                    'id': '2', 'dur': 'indefinite', 'nodeType': 'mainSeq'
                })
                etree.SubElement(seq_cTn, qn('p:childTnLst'))
                etree.SubElement(seq, qn('p:prevCondLst')).append(
                    etree.Element(qn('p:cond'), {'evt': 'onPrev', 'delay': '0'})
                )
                etree.SubElement(seq, qn('p:nextCondLst')).append(
                    etree.Element(qn('p:cond'), {'evt': 'onNext', 'delay': '0'})
                )
            else:
                cTn_root = par.find(qn('p:cTn'))
                childTnLst = cTn_root.find(qn('p:childTnLst'))
                seq = childTnLst.find(qn('p:seq'))
                seq_cTn = seq.find(qn('p:cTn'))

            main_childTnLst = seq_cTn.find(qn('p:childTnLst'))

            # Get max ID
            max_id = 2
            for el in tree.iter():
                ctn_id = el.get('id')
                if ctn_id and ctn_id.isdigit():
                    max_id = max(max_id, int(ctn_id))
            next_id = max_id + 1

            # par wrapper for this animation
            anim_par = etree.SubElement(main_childTnLst, qn('p:par'))
            anim_cTn = etree.SubElement(anim_par, qn('p:cTn'), {
                'id': str(next_id), 'fill': 'hold'
            })
            stCondLst = etree.SubElement(anim_cTn, qn('p:stCondLst'))
            etree.SubElement(stCondLst, qn('p:cond'), {'delay': str(delay_ms)})

            inner_childTnLst = etree.SubElement(anim_cTn, qn('p:childTnLst'))
            inner_par = etree.SubElement(inner_childTnLst, qn('p:par'))
            inner_cTn = etree.SubElement(inner_par, qn('p:cTn'), {
                'id': str(next_id + 1), 'presetID': '10' if effect == 'fade' else '2',
                'presetClass': 'entr', 'presetSubtype': '0',
                'fill': 'hold', 'nodeType': 'withEffect'
            })
            inner_stCond = etree.SubElement(inner_cTn, qn('p:stCondLst'))
            etree.SubElement(inner_stCond, qn('p:cond'), {'delay': '0'})

            inner_child = etree.SubElement(inner_cTn, qn('p:childTnLst'))

            # animEffect (fade)
            anim_effect = etree.SubElement(inner_child, qn('p:animEffect'), {
                'transition': 'in', 'filter': 'fade' if effect == 'fade' else 'wipe(down)'
            })
            eff_cBhvr = etree.SubElement(anim_effect, qn('p:cBhvr'))
            eff_cTn2 = etree.SubElement(eff_cBhvr, qn('p:cTn'), {
                'id': str(next_id + 2), 'dur': '500'
            })
            eff_tgtEl = etree.SubElement(eff_cBhvr, qn('p:tgtEl'))
            sp_tgt = etree.SubElement(eff_tgtEl, qn('p:spTgt'), {
                'spid': str(shape.shape_id)
            })

        except Exception as e:
            pass  # Animation is optional enhancement

    def add_slide_transition(slide, trans_type='fade'):
        """Add slide transition."""
        try:
            tree = slide._element
            transition = tree.find(qn('p:transition'))
            if transition is None:
                transition = etree.SubElement(tree, qn('p:transition'))
            transition.set('spd', 'med')
            transition.set('advClick', '1')
            if trans_type == 'fade':
                etree.SubElement(transition, qn('p:fade'))
            elif trans_type == 'push':
                etree.SubElement(transition, qn('p:push'))
            elif trans_type == 'wipe':
                etree.SubElement(transition, qn('p:wipe'))
        except:
            pass

    def parse_table_rows(rows):
        result = []
        for r in rows:
            cols = [c.strip() for c in r.strip().strip('|').split('|')]
            if cols and any(c for c in cols):
                result.append(cols)
        return result

    def add_table(slide, table_rows, left, top, width):
        try:
            parsed = parse_table_rows(table_rows)
            if not parsed:
                return top
            # Filter out separator rows (----)
            parsed = [r for r in parsed if not all(set(c.strip()) <= {'-', ':'} for c in r)]
            if not parsed:
                return top
            n_rows = len(parsed)
            n_cols = max(len(r) for r in parsed)
            for r in parsed:
                while len(r) < n_cols:
                    r.append('')
            row_h = Inches(0.42)
            col_w = Inches(width / n_cols)
            table_shape = slide.shapes.add_table(
                n_rows, n_cols,
                Inches(left), Inches(top),
                Inches(width), row_h * n_rows
            )
            tbl = table_shape.table
            for ci in range(n_cols):
                tbl.columns[ci].width = col_w
            for ri, row in enumerate(parsed):
                for ci, val in enumerate(row):
                    cell = tbl.cell(ri, ci)
                    cell.text = val
                    cell.vertical_anchor = MSO_ANCHOR.MIDDLE
                    p = cell.text_frame.paragraphs[0]
                    p.alignment = PP_ALIGN.CENTER
                    if ri == 0:
                        set_font(p, 13, WHITE, bold=True)
                        cell.fill.solid()
                        cell.fill.fore_color.rgb = PRIMARY
                    else:
                        set_font(p, 12, DARK_TEXT)
                        if ri % 2 == 0:
                            cell.fill.solid()
                            cell.fill.fore_color.rgb = SECTION_BG
                        else:
                            cell.fill.solid()
                            cell.fill.fore_color.rgb = LIGHT
                    cell.margin_left = Inches(0.08)
                    cell.margin_right = Inches(0.08)
                    cell.margin_top = Inches(0.04)
                    cell.margin_bottom = Inches(0.04)
            return top + (n_rows * 0.42) + 0.15
        except Exception as e:
            print(f"add_table error: {e}", file=sys.stderr)
            return top

    # ═══════════════════════════════════════════════════════════════
    # 封面页 — 全屏渐变 + 大标题 + 装饰线
    # ═══════════════════════════════════════════════════════════════
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    add_gradient_bg(slide, PRIMARY, RGBColor(0x1A, 0x23, 0x7E))
    add_slide_transition(slide, 'fade')

    # 顶部装饰圆弧
    deco = slide.shapes.add_shape(
        9, Inches(-2), Inches(-3), Inches(17), Inches(6)  # 椭圆
    )
    deco.fill.solid()
    deco.fill.fore_color.rgb = RGBColor(0x1E, 0x88, 0xE5)
    deco.fill.fore_color.brightness = 0.05
    deco.line.fill.background()

    # 标题
    tx = slide.shapes.add_textbox(Inches(1.5), Inches(2.0), Inches(10.3), Inches(1.8))
    tf = tx.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    set_p_font(p, title, 44, WHITE, bold=True)
    p.alignment = PP_ALIGN.CENTER
    add_entrance_anim(slide, tx, 200, 'fade')

    # 分隔线
    line = slide.shapes.add_shape(
        1, Inches(5), Inches(3.7), Inches(3.3), Emu(18000)
    )
    line.fill.solid()
    line.fill.fore_color.rgb = ACCENT
    line.line.fill.background()

    if chapter:
        tx_ch = slide.shapes.add_textbox(Inches(1.5), Inches(4.0), Inches(10.3), Inches(0.6))
        p_ch = tx_ch.text_frame.paragraphs[0]
        set_p_font(p_ch, chapter, 22, RGBColor(0xBB, 0xDD, 0xFF))
        p_ch.alignment = PP_ALIGN.CENTER
        add_entrance_anim(slide, tx_ch, 500, 'fade')

    # 底部信息
    tx2 = slide.shapes.add_textbox(Inches(1), Inches(6.2), Inches(11.3), Inches(0.5))
    p3 = tx2.text_frame.paragraphs[0]
    set_p_font(p3, '\u79fb\u52a8\u5e94\u7528\u5f00\u53d1\u77e5\u8bc6\u56fe\u8c31\u6559\u5b66\u7cfb\u7edf', 14, RGBColor(0x88, 0x99, 0xCC))
    p3.alignment = PP_ALIGN.CENTER

    # ═══════════════════════════════════════════════════════════════
    # 内容页 — 卡片式布局 + 渐变侧栏 + 动画入场
    # ═══════════════════════════════════════════════════════════════
    for idx, s in enumerate(slides_data):
        slide = prs.slides.add_slide(prs.slide_layouts[6])
        add_solid_bg(slide, LIGHT)
        add_slide_transition(slide, ['fade', 'push', 'wipe'][idx % 3])

        s_title = s.get('title', f'\u5e7b\u706f\u7247 {idx+1}')
        subtitle = s.get('subtitle', '')
        bullets = s.get('bullets', [])
        code = s.get('code', '')
        notes = s.get('notes', '')

        # ── 左侧渐变装饰条 ──
        side_bar = add_shape_with_gradient(
            slide, Inches(0), Inches(0), Inches(0.15), prs.slide_height,
            PRIMARY, SECONDARY
        )

        # ── 顶部标题区域 ──
        title_bg = slide.shapes.add_shape(
            1, Inches(0.15), Inches(0), prs.slide_width - Inches(0.15), Inches(1.2)
        )
        title_bg.fill.solid()
        title_bg.fill.fore_color.rgb = WHITE
        title_bg.line.fill.background()

        # 标题文字
        tx = slide.shapes.add_textbox(Inches(0.6), Inches(0.15), Inches(10.5), Inches(0.7))
        tf = tx.text_frame
        p = tf.paragraphs[0]
        set_p_font(p, s_title, 28, PRIMARY, bold=True)
        add_entrance_anim(slide, tx, 100, 'fade')

        # 副标题
        if subtitle:
            tx_sub = slide.shapes.add_textbox(Inches(0.6), Inches(0.75), Inches(10), Inches(0.35))
            p_sub = tx_sub.text_frame.paragraphs[0]
            set_p_font(p_sub, subtitle, 15, MID_TEXT)

        # 页码标签
        pg_shape = slide.shapes.add_shape(
            5, Inches(12.2), Inches(0.2), Inches(0.9), Inches(0.5)
        )
        pg_shape.fill.solid()
        pg_shape.fill.fore_color.rgb = PRIMARY
        pg_shape.line.fill.background()
        pg_tf = pg_shape.text_frame
        pg_tf.word_wrap = False
        pg_p = pg_tf.paragraphs[0]
        set_p_font(pg_p, f'{idx+1}/{len(slides_data)}', 12, WHITE, bold=True)
        pg_p.alignment = PP_ALIGN.CENTER

        # 蓝色分隔线
        sep = slide.shapes.add_shape(
            1, Inches(0.6), Inches(1.15), Inches(12), Emu(14000)
        )
        sep.fill.solid()
        sep.fill.fore_color.rgb = ACCENT
        sep.line.fill.background()

        # ── 内容区域 ──
        content_y = 1.4
        has_code = bool(code.strip())

        if has_code:
            bullet_width = 5.5
            code_left = 6.5
            code_width = 6.2
        else:
            bullet_width = 11.8
            code_left = 0
            code_width = 0

        # 分离表格行和普通要点
        normal_bullets = []
        table_rows = []
        pending_table = []
        if bullets:
            for b in bullets:
                text = str(b)
                if text.startswith('|'):
                    pending_table.append(text)
                else:
                    if pending_table:
                        table_rows.extend(pending_table)
                        pending_table = []
                    normal_bullets.append(text)
            if pending_table:
                table_rows.extend(pending_table)

        # ── 要点列表 — 卡片式 ──
        bullet_count = 0
        if normal_bullets:
            # 创建白色卡片背景
            card = add_card(slide, Inches(0.5), Inches(content_y - 0.1),
                           Inches(bullet_width + 0.3),
                           Inches(5.6 if not table_rows else 2.8))
            add_entrance_anim(slide, card, 200, 'fade')

            tx_b = slide.shapes.add_textbox(
                Inches(0.8), Inches(content_y),
                Inches(bullet_width), Inches(5.2 if not table_rows else 2.5)
            )
            tf_b = tx_b.text_frame
            tf_b.word_wrap = True
            add_entrance_anim(slide, tx_b, 300, 'fade')

            for bi, text in enumerate(normal_bullets):
                if bi == 0:
                    p = tf_b.paragraphs[0]
                else:
                    p = tf_b.add_paragraph()

                if text.startswith('\u3010'):
                    # 【标签】样式 — 使用强调色
                    set_p_font(p, text, 16, SECONDARY, bold=True)
                    p.space_before = Pt(14)
                elif text.startswith('  \u00b7'):
                    set_p_font(p, text, 14, MID_TEXT)
                    p.space_before = Pt(4)
                    p.level = 1
                else:
                    # 使用圆形图标前缀
                    set_p_font(p, f'\u25b8 {text}', 15, DARK_TEXT)
                    p.space_before = Pt(7)
                bullet_count += 1

        # 表格
        if table_rows:
            if normal_bullets:
                tbl_top = content_y + min(bullet_count * 0.32 + 0.4, 3.2)
            else:
                tbl_top = content_y
            tbl_top = min(tbl_top, 4.5)
            add_table(slide, table_rows, 0.8, tbl_top, bullet_width)

        # ── 代码块 — 暗色主题卡片 ──
        if has_code:
            # 代码卡片背景
            code_card = slide.shapes.add_shape(
                5, Inches(code_left - 0.1), Inches(content_y - 0.1),
                Inches(code_width + 0.2), Inches(5.4)
            )
            code_card.fill.solid()
            code_card.fill.fore_color.rgb = CODE_BG
            code_card.line.color.rgb = RGBColor(0x40, 0x40, 0x50)
            code_card.line.width = Pt(1)
            add_entrance_anim(slide, code_card, 400, 'fade')

            # 代码标题栏
            code_title = slide.shapes.add_shape(
                1, Inches(code_left - 0.1), Inches(content_y - 0.1),
                Inches(code_width + 0.2), Inches(0.35)
            )
            code_title.fill.solid()
            code_title.fill.fore_color.rgb = RGBColor(0x2A, 0x2A, 0x3A)
            code_title.line.fill.background()
            ct_tf = code_title.text_frame
            ct_p = ct_tf.paragraphs[0]
            set_p_font(ct_p, '  \u25cf \u25cf \u25cf  Code', 10, RGBColor(0x88, 0x88, 0x99), name='Consolas')

            # 代码内容
            code_box = slide.shapes.add_textbox(
                Inches(code_left), Inches(content_y + 0.3),
                Inches(code_width), Inches(4.9)
            )
            tf_c = code_box.text_frame
            tf_c.word_wrap = True
            code_lines = code.strip().split('\n')
            for ci, cl in enumerate(code_lines):
                if ci == 0:
                    p = tf_c.paragraphs[0]
                else:
                    p = tf_c.add_paragraph()
                set_p_font(p, cl, 12, CODE_FG, name='Consolas')
                p.space_before = Pt(2)
            add_entrance_anim(slide, code_box, 500, 'fade')

        # 备注
        auto_notes = []
        auto_notes.append(s_title)
        if subtitle:
            auto_notes.append(subtitle)
        for b in normal_bullets[:5]:
            auto_notes.append(f'- {b}')
        final_notes = notes if notes else '\n'.join(auto_notes)
        if final_notes:
            slide.notes_slide.notes_text_frame.text = final_notes

    # ═══════════════════════════════════════════════════════════════
    # 结束页 — 渐变 + 大号"谢谢" + Q&A
    # ═══════════════════════════════════════════════════════════════
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    add_gradient_bg(slide, PRIMARY, RGBColor(0x1A, 0x23, 0x7E))
    add_slide_transition(slide, 'fade')

    # 装饰圆
    deco2 = slide.shapes.add_shape(
        9, Inches(8), Inches(4), Inches(8), Inches(8)
    )
    deco2.fill.solid()
    deco2.fill.fore_color.rgb = SECONDARY
    deco2.fill.fore_color.brightness = 0.05
    deco2.line.fill.background()

    tx = slide.shapes.add_textbox(Inches(1), Inches(2.0), Inches(11.3), Inches(2))
    tf = tx.text_frame
    p = tf.paragraphs[0]
    set_p_font(p, '\u8c22\u8c22\uff01', 54, WHITE, bold=True)
    p.alignment = PP_ALIGN.CENTER
    add_entrance_anim(slide, tx, 200, 'fade')

    p2 = tf.add_paragraph()
    set_p_font(p2, 'Questions & Answers', 22, RGBColor(0xBB, 0xDD, 0xFF))
    p2.alignment = PP_ALIGN.CENTER
    p2.space_before = Pt(20)

    # 底部信息
    tx3 = slide.shapes.add_textbox(Inches(1), Inches(5.5), Inches(11.3), Inches(0.8))
    tf3 = tx3.text_frame
    p3 = tf3.paragraphs[0]
    set_p_font(p3, '\u79fb\u52a8\u5e94\u7528\u5f00\u53d1\u77e5\u8bc6\u56fe\u8c31\u6559\u5b66\u7cfb\u7edf', 14, RGBColor(0x88, 0x99, 0xCC))
    p3.alignment = PP_ALIGN.CENTER

    p4 = tf3.add_paragraph()
    import datetime
    set_p_font(p4, datetime.datetime.now().strftime('%Y\u5e74%m\u6708'), 12, RGBColor(0x77, 0x88, 0xBB))
    p4.alignment = PP_ALIGN.CENTER

    # 保存
    os.makedirs(os.path.dirname(output), exist_ok=True)
    prs.save(output)
    print(f"PPTX saved: {output}")

if __name__ == '__main__':
    main()
''';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 幻灯片 → PNG 图片 (Python PIL 直接渲染，不经过 PDF)
  // ═══════════════════════════════════════════════════════════════════════════

  /// 检查 Pillow 是否安装
  Future<bool> isPillowInstalled() async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
        'python', ['-c', 'from PIL import Image; print("OK")'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 将幻灯片数据直接渲染为 1920×1080 PNG 图片（使用 Python PIL + 微软雅黑）
  /// 返回生成的 PNG 路径列表，顺序为: 封面 + 内容页×N + 结束页
  /// 确保数量 = slides.length + 2，与 TTS 旁白严格对齐
  Future<List<String>> generateSlideImages({
    required String title,
    required List<Map<String, dynamic>> slides,
    required String outputDir,
    String? chapter,
  }) async {
    if (kIsWeb) return [];

    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    try {
      final tempDir = await getTemporaryDirectory();

      // 写入幻灯片数据 JSON
      final dataFile = File('${tempDir.path}/slide_img_data.json');
      await dataFile.writeAsString(jsonEncode({
        'title': title,
        'chapter': chapter ?? '',
        'slides': slides,
        'output_dir': outputDir.replaceAll('\\', '/'),
      }));

      // 写入 Python 渲染脚本
      final scriptFile = File('${tempDir.path}/render_slides.py');
      await scriptFile.writeAsString(_slideImagesPythonScript());

      final result = await Process.run(
        'python', [scriptFile.path, dataFile.path],
        runInShell: true,
      ).timeout(const Duration(seconds: 120));

      // 清理
      if (scriptFile.existsSync()) scriptFile.deleteSync();
      if (dataFile.existsSync()) dataFile.deleteSync();

      if (result.exitCode == 0) {
        final paths = result.stdout
            .toString()
            .trim()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && l.endsWith('.png'))
            .toList();
        debugPrint('CoursewareService: generateSlideImages → ${paths.length} images');
        return paths;
      }
      debugPrint('CoursewareService: render_slides.py failed: ${result.stderr}');
      return [];
    } catch (e) {
      debugPrint('CoursewareService: generateSlideImages error: $e');
      return [];
    }
  }

  /// Python PIL 渲染脚本 — 生成专业课件幻灯片 PNG
  String _slideImagesPythonScript() {
    return r'''
import json, sys, os, textwrap

def main():
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)

    from PIL import Image, ImageDraw, ImageFont

    title = data.get('title', '')
    chapter = data.get('chapter', '')
    slides = data.get('slides', [])
    out_dir = data.get('output_dir', '.')
    os.makedirs(out_dir, exist_ok=True)

    W, H = 1920, 1080

    # ── 加载字体 ──────────────────────────────────────────────
    font_paths = [
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/msyhbd.ttc",
        "C:/Windows/Fonts/simhei.ttf",
        "C:/Windows/Fonts/simsun.ttc",
    ]
    code_paths = [
        "C:/Windows/Fonts/consola.ttf",
        "C:/Windows/Fonts/cour.ttf",
    ]

    def load(paths, size):
        for p in paths:
            try:
                return ImageFont.truetype(p, size)
            except:
                pass
        return ImageFont.load_default()

    ft_cover  = load(font_paths, 72)
    ft_ch     = load(font_paths, 36)
    ft_title  = load(font_paths, 48)
    ft_sub    = load(font_paths, 28)
    ft_body   = load(font_paths, 26)
    ft_bold   = load([font_paths[1]] + font_paths, 28)
    ft_small  = load(font_paths, 22)
    ft_tiny   = load(font_paths, 18)
    ft_code   = load(code_paths, 20)
    ft_tbl    = load(font_paths, 22)
    ft_tblh   = load([font_paths[1]] + font_paths, 22)

    # ── 颜色常量 ──────────────────────────────────────────────
    DARK_BLUE = '#0958D9'
    BLUE      = '#1677FF'
    WHITE     = '#FFFFFF'
    GRAY      = '#666666'
    LIGHT_BG  = '#F0F4F8'
    CODE_BG   = '#282C34'
    CODE_FG   = '#ABB2BF'

    def draw_wrapped(draw, text, x, y, font, fill, max_w, line_h=None):
        """Draw text with word-wrap, return final y."""
        if not text:
            return y
        if line_h is None:
            try:
                line_h = font.getbbox("测")[3] + 8
            except:
                line_h = 36
        # Estimate chars per line
        try:
            cw = font.getbbox("测测")[2] / 2
        except:
            cw = 20
        chars = max(int(max_w / cw), 10)
        lines = textwrap.wrap(text, width=chars)
        for ln in lines:
            draw.text((x, y), ln, font=font, fill=fill)
            y += line_h
        return y

    idx = 0  # output image counter

    # ══════════════════════════════════════════════════════════
    #  封面
    # ══════════════════════════════════════════════════════════
    idx += 1
    img = Image.new('RGB', (W, H), DARK_BLUE)
    draw = ImageDraw.Draw(img)

    # 装饰线
    draw.rectangle([(0, 0), (W, 10)], fill=BLUE)
    draw.rectangle([(0, H-10), (W, H)], fill=BLUE)

    # 标题（居中）
    try:
        bbox = draw.textbbox((0,0), title, font=ft_cover)
        tw = bbox[2] - bbox[0]
    except:
        tw = len(title) * 72
    tx = (W - tw) // 2
    draw.text((tx, H//2 - 100), title, font=ft_cover, fill=WHITE)

    # 章节
    if chapter:
        try:
            bbox = draw.textbbox((0,0), chapter, font=ft_ch)
            tw = bbox[2] - bbox[0]
        except:
            tw = len(chapter) * 36
        draw.text(((W - tw)//2, H//2 + 10), chapter, font=ft_ch, fill='#BBCCFF')

    # 底部
    bot = '移动应用开发知识图谱教学系统'
    try:
        bbox = draw.textbbox((0,0), bot, font=ft_small)
        tw = bbox[2] - bbox[0]
    except:
        tw = len(bot) * 22
    draw.text(((W - tw)//2, H - 80), bot, font=ft_small, fill='#99AADD')

    out = f"{out_dir}/slide_{idx:03d}.png"
    img.save(out)
    print(out)

    # ══════════════════════════════════════════════════════════
    #  内容页
    # ══════════════════════════════════════════════════════════
    for si, s in enumerate(slides):
        idx += 1
        img = Image.new('RGB', (W, H), WHITE)
        draw = ImageDraw.Draw(img)

        s_title  = s.get('title', f'Slide {si+1}')
        subtitle = s.get('subtitle', '')
        bullets  = s.get('bullets', [])
        code     = s.get('code', '')
        has_code = bool(code.strip())

        # 顶部蓝色装饰条
        draw.rectangle([(0, 0), (W, 8)], fill=BLUE)

        # 标题
        draw.text((60, 25), s_title, font=ft_title, fill=DARK_BLUE)

        # 页码
        pg = f'{si+1}/{len(slides)}'
        try:
            bbox = draw.textbbox((0,0), pg, font=ft_small)
            pw_ = bbox[2] - bbox[0]
        except:
            pw_ = len(pg) * 22
        draw.text((W - 60 - pw_, 35), pg, font=ft_small, fill=GRAY)

        # 副标题
        top_y = 85
        if subtitle:
            draw.text((60, top_y), subtitle, font=ft_sub, fill=GRAY)
            top_y += 40

        # 分隔线
        draw.line([(60, top_y), (W - 60, top_y)], fill='#DDDDDD', width=2)
        top_y += 15

        # 内容区域
        content_x = 60
        content_w = (W // 2 - 40) if has_code else (W - 120)
        y = top_y

        # 分离 table rows 和普通 bullets
        normal = []
        table_rows = []
        for b in bullets:
            t = str(b)
            if t.startswith('|'):
                table_rows.append(t)
            else:
                normal.append(t)

        # 绘制普通 bullets
        for b in normal:
            if y > H - 80:
                break
            if b.startswith('\u3010'):
                # 子标题 【xxx】
                y += 8
                draw.text((content_x, y), b, font=ft_bold, fill=DARK_BLUE)
                y += 38
            elif b.startswith('  \u00b7'):
                # 缩进项
                draw.text((content_x + 40, y), b.strip(), font=ft_body, fill=GRAY)
                y += 34
            else:
                # 普通要点
                text = f'\u2022 {b}' if not b.startswith('\u2022') else b
                y = draw_wrapped(draw, text, content_x + 10, y, ft_body, '#333333', content_w - 10, 34)
                y += 4

        # 绘制表格
        if table_rows and y < H - 120:
            y += 10
            parsed = []
            for r in table_rows:
                cols = [c.strip() for c in r.strip().strip('|').split('|')]
                if cols:
                    parsed.append(cols)
            if parsed:
                n_cols = max(len(r) for r in parsed)
                col_w = min(content_w // n_cols, 350)
                row_h = 36
                for ri, row in enumerate(parsed):
                    while len(row) < n_cols:
                        row.append('')
                    rx = content_x + 10
                    for ci, val in enumerate(row):
                        x1, y1 = rx, y
                        x2, y2 = rx + col_w, y + row_h
                        if ri == 0:
                            draw.rectangle([(x1, y1), (x2, y2)], fill=DARK_BLUE, outline='#BBBBBB')
                            draw.text((x1 + 8, y1 + 6), val[:20], font=ft_tblh, fill=WHITE)
                        else:
                            bg = LIGHT_BG if ri % 2 == 0 else WHITE
                            draw.rectangle([(x1, y1), (x2, y2)], fill=bg, outline='#CCCCCC')
                            draw.text((x1 + 8, y1 + 6), val[:25], font=ft_tbl, fill='#333333')
                        rx += col_w
                    y += row_h

        # 代码块
        if has_code:
            code_x = W // 2 + 20
            code_w = W - code_x - 40
            code_y = top_y
            # 背景
            draw.rectangle([(code_x, code_y), (W - 40, H - 40)], fill=CODE_BG)
            # 代码头标签
            draw.rectangle([(code_x, code_y), (code_x + 70, code_y + 24)], fill='#3C4049')
            draw.text((code_x + 8, code_y + 3), 'Code', font=ft_tiny, fill='#999999')
            cy = code_y + 30
            for cl in code.strip().split('\n'):
                if cy > H - 60:
                    break
                draw.text((code_x + 15, cy), cl, font=ft_code, fill=CODE_FG)
                cy += 26

        out = f"{out_dir}/slide_{idx:03d}.png"
        img.save(out)
        print(out)

    # ══════════════════════════════════════════════════════════
    #  结束页
    # ══════════════════════════════════════════════════════════
    idx += 1
    img = Image.new('RGB', (W, H), DARK_BLUE)
    draw = ImageDraw.Draw(img)
    draw.rectangle([(0, 0), (W, 10)], fill=BLUE)
    draw.rectangle([(0, H-10), (W, H)], fill=BLUE)

    txt = '谢谢！'
    try:
        bbox = draw.textbbox((0,0), txt, font=ft_cover)
        tw = bbox[2] - bbox[0]
    except:
        tw = 216
    draw.text(((W - tw)//2, H//2 - 80), txt, font=ft_cover, fill=WHITE)

    txt2 = 'Q & A'
    try:
        bbox = draw.textbbox((0,0), txt2, font=ft_ch)
        tw = bbox[2] - bbox[0]
    except:
        tw = 120
    draw.text(((W - tw)//2, H//2 + 30), txt2, font=ft_ch, fill='#BBCCFF')

    out = f"{out_dir}/slide_{idx:03d}.png"
    img.save(out)
    print(out)

    print(f"Total: {idx} images", file=sys.stderr)

if __name__ == '__main__':
    main()
''';
  }
}
