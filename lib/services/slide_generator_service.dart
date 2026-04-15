import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/local/material_dao.dart';
import '../data/models/material_model.dart';
import 'ai_service.dart';

// 条件导入
import 'slide_generator_service_stub.dart'
    if (dart.library.io) 'slide_generator_service_native.dart' as impl;

class SlideGeneratorService {
  final MaterialDao _materialDao = MaterialDao();

  // ── 从 AI 生成内容并保存为 PDF ──────────────────────────────────────────
  Future<MaterialModel?> generateFromAI({
    required AiService aiService,
    required String topic,
    String? chapter,
    int slideCount = 8,
  }) async {
    final slides = await aiService.generateSlides(
      topic,
      chapter: chapter,
      slideCount: slideCount,
    );
    return generatePdf(
      title: topic,
      slides: slides,
      chapter: chapter,
    );
  }

  // ── 将幻灯片数据保存为 PDF ───────────────────────────────────────────────
  Future<MaterialModel?> generatePdf({
    required String title,
    required List<Map<String, dynamic>> slides,
    String? chapter,
  }) async {
    if (kIsWeb) return null; // Web 平台暂不支持 PDF 文件保存
    try {
      final pdf = pw.Document();

      // 尝试加载中文字体（优先微软雅黑，回退 NotoSansSC）
      pw.Font? font;
      try {
        final fontData =
            await rootBundle.load('assets/fonts/msyh.ttc');
        font = pw.Font.ttf(fontData);
      } catch (_) {
        try {
          final fontData =
              await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
          font = pw.Font.ttf(fontData);
        } catch (_) {
          // 无中文字体则用默认字体（部分中文可能显示为方块）
        }
      }

      // 有字体时使用自定义主题，否则使用默认主题
      final pw.ThemeData? baseTheme =
          font != null ? pw.ThemeData.withFont(base: font) : null;

      // 封面页
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: baseTheme,
        build: (ctx) => _buildCoverSlide(ctx, title, chapter, font),
      ));

      // 内容页
      for (var i = 0; i < slides.length; i++) {
        final slide = slides[i];
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: baseTheme,
          build: (ctx) =>
              _buildContentSlide(ctx, slide, i + 1, slides.length, font),
        ));
      }

      // 保存文件（原生平台）
      final pdfBytes = await pdf.save();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          '${title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')}_$timestamp.pdf';

      final result = await impl.savePdfFile(fileName, pdfBytes);
      if (result == null) return null;

      final filePath = result['path'] as String;
      final fileSize = result['size'] as int;

      final material = MaterialModel(
        title: '$title - 课件',
        type: 'pdf',
        filePath: filePath,
        chapter: chapter,
        createdAt: DateTime.now().toIso8601String(),
        size: fileSize,
      );

      final id = await _materialDao.insert(material);
      return MaterialModel(
        id: id,
        title: material.title,
        type: material.type,
        filePath: material.filePath,
        chapter: material.chapter,
        createdAt: material.createdAt,
        size: material.size,
      );
    } catch (e) {
      return null;
    }
  }

  // ── 保存视频脚本为文本材料 ───────────────────────────────────────────────
  Future<MaterialModel?> saveScript({
    required String title,
    required String script,
    String? chapter,
  }) async {
    try {
      final material = MaterialModel(
        title: '$title - 讲解脚本',
        type: 'script',
        content: script,
        chapter: chapter,
        createdAt: DateTime.now().toIso8601String(),
      );
      final id = await _materialDao.insert(material);
      return MaterialModel(
        id: id,
        title: material.title,
        type: material.type,
        content: material.content,
        chapter: material.chapter,
        createdAt: material.createdAt,
      );
    } catch (_) {
      return null;
    }
  }

  // ── PDF 封面页 ───────────────────────────────────────────────────────────
  pw.Widget _buildCoverSlide(
    pw.Context ctx,
    String title,
    String? chapter,
    pw.Font? font,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [
            PdfColor.fromInt(0xFF1677FF),
            PdfColor.fromInt(0xFF0958D9),
          ],
          begin: const pw.Alignment(0, 0),
          end: const pw.Alignment(1, 0),
        ),
      ),
      child: pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: font,
                fontSize: 36,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (chapter != null) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                chapter,
                style: pw.TextStyle(
                  font: font,
                  fontSize: 20,
                  color: const PdfColor(1, 1, 1, 0.7),
                ),
              ),
            ],
            pw.SizedBox(height: 32),
            pw.Text(
              '移动应用开发知识图谱教学系统',
              style: pw.TextStyle(
                font: font,
                fontSize: 14,
                color: const PdfColor(1, 1, 1, 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PDF 内容页 ───────────────────────────────────────────────────────────
  pw.Widget _buildContentSlide(
    pw.Context ctx,
    Map<String, dynamic> slide,
    int index,
    int total,
    pw.Font? font,
  ) {
    final bullets = (slide['bullets'] as List?)?.cast<String>() ?? [];
    return pw.Container(
      padding: const pw.EdgeInsets.all(32),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // 标题区域（底部蓝色边框）
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
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
                  child: pw.Text(
                    slide['title'] as String? ?? '幻灯片 $index',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF1677FF),
                    ),
                  ),
                ),
                pw.Text(
                  '$index / $total',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 12,
                    color: PdfColors.grey,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          // 要点列表
          ...bullets.map(
            (b) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 6,
                    height: 6,
                    margin: const pw.EdgeInsets.only(top: 6, right: 12),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF1677FF),
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      b,
                      style: pw.TextStyle(font: font, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.Spacer(),
          // 讲师备注
          if ((slide['notes'] as String?)?.isNotEmpty == true)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF5F7FA),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                '备注：${slide['notes']}',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
