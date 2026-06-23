import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../core/constants/score_colors.dart';
import '../core/error_handler.dart';

/// 考核报告打印服务 — 生成对齐学院模板的整合 PDF。
///
/// 三块内容由 [AuditedReportData] 提供：
///   - cover: 封面信息（标题/学院/课程/班级/姓名/学号/题目/教师/起止日期）
///   - grading: 教师评语 + 4 项分数（项目30% / 小组20% / 个人20% / 答辩30%）
///   - reports: 已提交的 4 项支撑材料（标题+评分+反馈），用于形成一份完整考核报告
class AssessmentPdfService {
  static Future<Uint8List> buildAuditedReportPdf({
    required AuditedReportData data,
    bool includeCover = true,
    bool includeGrading = true,
    bool includeReports = true,
    bool includeFinalReport = true,
    double pageMarginMm = 20,
  }) async {
    final fonts = await _loadChineseFonts();
    final theme = pw.ThemeData.withFont(
      base: fonts.regular,
      bold: fonts.bold,
    );
    final pdf = pw.Document(theme: theme);

    if (includeCover) {
      pdf.addPage(_buildCover(data.cover, pageMarginMm));
    }
    if (includeGrading) {
      pdf.addPage(_buildGradingPage(data.grading, pageMarginMm));
    }
    final finalReport = data.finalReport;
    final hasLocalFinalReport = finalReport?.filePath.isNotEmpty == true &&
        File(finalReport!.filePath).existsSync();
    if (includeReports && data.reports.isNotEmpty) {
      pdf.addPage(_buildReportsPage(data.reports, pageMarginMm));
    }
    if (includeFinalReport && finalReport != null && !hasLocalFinalReport) {
      pdf.addPage(_buildFinalReportReferencePage(finalReport, pageMarginMm));
    }

    final generatedBytes = await pdf.save();
    if (!includeFinalReport || finalReport == null || !hasLocalFinalReport) {
      return generatedBytes;
    }

    final attachmentBytes = await File(finalReport.filePath).readAsBytes();
    return _appendPdfPages(
      baseBytes: generatedBytes,
      attachmentBytes: attachmentBytes,
      pageMarginMm: pageMarginMm,
    );
  }

  static Future<bool> printPdf(
    Uint8List bytes, {
    String name = '考核报告',
    double pageMarginMm = 20,
  }) async {
    final margin = _mmToPdf(pageMarginMm);
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: name,
      format: PdfPageFormat.a4.copyWith(
        marginLeft: margin,
        marginRight: margin,
        marginTop: margin,
        marginBottom: margin,
      ),
      usePrinterSettings: true,
    );
  }

  static Future<String?> saveToFile(Uint8List bytes, String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory('${dir.path}/assessment_audited');
      await reportsDir.create(recursive: true);
      final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${reportsDir.path}/$safe.pdf');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e, st) {
      swallowDebug(e, tag: 'AssessmentPdfService._savePdfFile', stack: st);
      return null;
    }
  }

  // ════════════════════════════════════════════════════════
  //  封面（对齐学院模板首页）
  // ════════════════════════════════════════════════════════
  static pw.Page _buildCover(CoverInfo c, double pageMarginMm) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(_mmToPdf(pageMarginMm)),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(height: 40),
          pw.Text(c.docTitle,
              style: pw.TextStyle(
                  fontSize: 30,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 4)),
          pw.SizedBox(height: 90),
          _coverField('学院名称', c.collegeName),
          _coverField('课程名称', c.courseName),
          _coverField('班级名称', c.className),
          _coverField('学生姓名', c.studentName),
          _coverField('学    号', c.studentId),
          _coverField('题    目', c.projectTitle),
          _coverField('指导教师', c.advisorName),
          _coverField('起止日期', c.dateRange),
          pw.SizedBox(height: 80),
          pw.Text('计算机软件课程组  制',
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2)),
        ],
      ),
    );
  }

  static pw.Widget _coverField(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text('$label：',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Container(
            width: 280,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
              ),
            ),
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              value.isNotEmpty ? value : ' ',
              style: const pw.TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  指导教师评语 + 成绩评定（对齐模板第 2 页）
  // ════════════════════════════════════════════════════════
  static pw.Page _buildGradingPage(GradingInfo g, double pageMarginMm) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(_mmToPdf(pageMarginMm)),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text('指导教师评语',
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            constraints: const pw.BoxConstraints(minHeight: 220),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey700),
            ),
            child: pw.Text(
              g.advisorComment.isNotEmpty ? g.advisorComment : ' ',
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('成绩评定',
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 12),
          _scoreTable(g),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('指导教师签名：${g.advisorName}',
                  style: const pw.TextStyle(fontSize: 13)),
              pw.Text('填表日期：${g.signDate}',
                  style: const pw.TextStyle(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _scoreTable(GradingInfo g) {
    pw.TableRow row(String idx, String type, int? score, int weight,
        {bool bold = false, bool isTotal = false}) {
      final scoreText = score?.toString() ?? '—';
      final weighted =
          (score == null) ? '—' : (score * weight / 100).toStringAsFixed(1);
      return pw.TableRow(
        decoration:
            bold ? const pw.BoxDecoration(color: PdfColors.indigo50) : null,
        children: [
          _tCell(idx, bold: bold),
          _tCell(type, bold: bold),
          _tCell(scoreText,
              bold: bold,
              color: isTotal ? PdfColors.indigo800 : scoreColorPdf(score)),
          _tCell('$weight%', bold: bold),
          _tCell(weighted, bold: bold),
        ],
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.7),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1),
        4: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.indigo100),
          children: [
            _tCell('序号', bold: true),
            _tCell('类型', bold: true),
            _tCell('成绩', bold: true),
            _tCell('权重', bold: true),
            _tCell('得分', bold: true),
          ],
        ),
        row('1', '项目', g.projectScore, 30),
        row('2', '小组', g.groupScore, 20),
        row('3', '个人', g.personalScore, 20),
        row('4', '答辩', g.defenseScore, 30),
        row('5', '总成绩', g.totalScore, 100, bold: true, isTotal: true),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  4 项支撑材料审核明细（最终仍输出为一份完整报告）
  // ════════════════════════════════════════════════════════
  static pw.Page _buildReportsPage(
      List<AuditedReport> reports, double pageMarginMm) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(_mmToPdf(pageMarginMm)),
      build: (context) => [
        pw.Center(
          child: pw.Text('附：课程考核大作业支撑材料审核明细',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 16),
        for (final r in reports) ...[
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.indigo400, width: 3),
              ),
            ),
            padding: const pw.EdgeInsets.all(10),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${r.type} - ${r.title}',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo800),
                  ),
                ),
                pw.Text(
                  r.score == null ? '未批改' : '${r.score} 分',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: scoreColorPdf(r.score)),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4),
            child: pw.Text(
              r.feedback?.isNotEmpty == true ? r.feedback! : '（无批阅意见）',
              style: pw.TextStyle(
                fontSize: 11,
                lineSpacing: 4,
                color: r.feedback?.isNotEmpty == true
                    ? PdfColors.grey900
                    : PdfColors.grey500,
              ),
            ),
          ),
          pw.SizedBox(height: 16),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  通用工具
  // ════════════════════════════════════════════════════════
  static pw.Widget _tCell(String text, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Center(
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? PdfColors.grey900,
          ),
        ),
      ),
    );
  }

  static pw.Page _buildFinalReportReferencePage(
      FinalReportAttachment report, double pageMarginMm) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(_mmToPdf(pageMarginMm)),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text('附：学生终稿 PDF',
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 24),
          _referenceRow('报告名称', report.title),
          _referenceRow('提交文件', report.fileName),
          _referenceRow('提交状态', report.status),
          if (report.submittedAt.isNotEmpty)
            _referenceRow('提交时间', report.submittedAt),
          pw.SizedBox(height: 20),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey700),
              color: PdfColors.grey100,
            ),
            child: pw.Text(
              '当前设备未找到学生提交的原始 PDF 文件，审核版本已保留封面、指导教师评语和成绩页。请先同步或在提交设备上生成全文审核版本。',
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _referenceRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 72,
            child: pw.Text('$label：',
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text(value.isNotEmpty ? value : '—',
                style: const pw.TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static Future<Uint8List> _appendPdfPages({
    required Uint8List baseBytes,
    required Uint8List attachmentBytes,
    required double pageMarginMm,
  }) async {
    sf.PdfDocument? target;
    sf.PdfDocument? source;
    try {
      target = sf.PdfDocument(inputBytes: baseBytes);
      source = sf.PdfDocument(inputBytes: attachmentBytes);
      final margin = _mmToPdf(pageMarginMm);

      for (var i = 0; i < source.pages.count; i++) {
        final sourcePage = source.pages[i];
        final template = sourcePage.createTemplate();
        final templateSize = template.size;
        final page = target.pages.add();
        final pageSize = page.getClientSize();
        final usableWidth = math.max(1.0, pageSize.width - margin * 2);
        final usableHeight = math.max(1.0, pageSize.height - margin * 2);
        final scale = math.min(
          usableWidth / templateSize.width,
          usableHeight / templateSize.height,
        );
        final drawWidth = templateSize.width * scale;
        final drawHeight = templateSize.height * scale;
        final dx = margin + (usableWidth - drawWidth) / 2;
        final dy = margin + (usableHeight - drawHeight) / 2;
        page.graphics.drawPdfTemplate(
          template,
          ui.Offset(dx, dy),
          ui.Size(drawWidth, drawHeight),
        );
      }

      final saved = await target.save();
      return Uint8List.fromList(saved);
    } catch (e, st) {
      swallowDebug(e, tag: 'AssessmentPdfService.appendPdfPages', stack: st);
      return baseBytes;
    } finally {
      source?.dispose();
      target?.dispose();
    }
  }

  static double _mmToPdf(double mm) => mm * PdfPageFormat.mm;

  static Future<_ChineseFonts>? _fontsFuture;

  static Future<_ChineseFonts> _loadChineseFonts() {
    return _fontsFuture ??= () async {
      pw.Font? toFont(ByteData? data) =>
          data == null ? null : pw.Font.ttf(data);
      final results = await Future.wait<ByteData?>([
        rootBundle
            .load('assets/fonts/msyh.ttc')
            .then<ByteData?>((d) => d)
            .catchError((_) => null),
        rootBundle
            .load('assets/fonts/msyhbd.ttc')
            .then<ByteData?>((d) => d)
            .catchError((_) => null),
      ]);
      final regular = toFont(results[0]);
      final bold = toFont(results[1]) ?? regular;
      return _ChineseFonts(regular: regular, bold: bold);
    }();
  }
}

// ════════════════════════════════════════════════════════
//  数据模型
// ════════════════════════════════════════════════════════

class AuditedReportData {
  final CoverInfo cover;
  final GradingInfo grading;
  final List<AuditedReport> reports;
  final FinalReportAttachment? finalReport;

  const AuditedReportData({
    required this.cover,
    required this.grading,
    required this.reports,
    this.finalReport,
  });
}

/// 封面字段
class CoverInfo {
  final String docTitle;
  final String collegeName;
  final String courseName;
  final String className;
  final String studentName;
  final String studentId;
  final String projectTitle;
  final String advisorName;
  final String dateRange;

  const CoverInfo({
    this.docTitle = '软件开发类课程考查报告',
    required this.collegeName,
    required this.courseName,
    required this.className,
    required this.studentName,
    required this.studentId,
    required this.projectTitle,
    required this.advisorName,
    required this.dateRange,
  });
}

/// 成绩评定 + 教师评语
class GradingInfo {
  final String advisorComment;
  final int? projectScore;
  final int? groupScore;
  final int? personalScore;
  final int? defenseScore;
  final String advisorName;
  final String signDate;

  const GradingInfo({
    required this.advisorComment,
    this.projectScore,
    this.groupScore,
    this.personalScore,
    this.defenseScore,
    required this.advisorName,
    required this.signDate,
  });

  /// 加权总分：项目30% + 小组20% + 个人20% + 答辩30%
  /// 缺项按 0 计入。返回 null 当且仅当全部缺失。
  int? get totalScore {
    if (projectScore == null &&
        groupScore == null &&
        personalScore == null &&
        defenseScore == null) {
      return null;
    }
    final weighted = (projectScore ?? 0) * 0.30 +
        (groupScore ?? 0) * 0.20 +
        (personalScore ?? 0) * 0.20 +
        (defenseScore ?? 0) * 0.30;
    return weighted.round();
  }
}

class AuditedReport {
  final String type;
  final String title;
  final int? score;
  final String? feedback;
  final String status;

  const AuditedReport({
    required this.type,
    required this.title,
    this.score,
    this.feedback,
    this.status = '已提交',
  });
}

class FinalReportAttachment {
  final String title;
  final String fileName;
  final String filePath;
  final String status;
  final String submittedAt;

  const FinalReportAttachment({
    required this.title,
    required this.fileName,
    required this.filePath,
    this.status = '已提交',
    this.submittedAt = '',
  });
}

class _ChineseFonts {
  final pw.Font? regular;
  final pw.Font? bold;
  const _ChineseFonts({this.regular, this.bold});
}
