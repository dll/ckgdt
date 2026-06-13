import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 教学任务书官方版式 PDF 构建器（原生 pdf 包，零外部依赖 —— 不需 LibreOffice/pandoc）。
///
/// 复刻学校样式：标题「教 学 任 务 书」+（存根）+「经学校批准聘请…」抬头 +
/// 10 列课程表 + 院长/签章/日期签字行 + 虚线分隔 + 下半正本。
///
/// 数据来源：解析 [markdown]（ArchiveImporters.parseTeachingTask 产出的横排 10 列表）。
class TeachingTaskPdf {
  TeachingTaskPdf._();

  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static const _columns = [
    '课程名称', '课程类别', '总学时', '讲授', '实验', '实践', '课外自主学时', '教学班级', '计划人数', '备注',
  ];
  // 各列宽权重（与样图比例接近：课程名/班级宽，学时列窄）。须与 _columns 等长。
  static const _weights = [3.2, 2.0, 1.0, 0.9, 0.9, 0.9, 1.3, 2.6, 1.0, 1.6];

  static int get _colCount {
    assert(_columns.length == _weights.length,
        '_columns(${_columns.length}) 与 _weights(${_weights.length}) 必须等长');
    return _columns.length;
  }

  /// 从导入文档的 markdown 解析出抬头与课程行。
  static TeachingTaskData parse(String markdown) {
    final header = RegExp(r'经学校批准聘请(.*?)老师担任(.*?)以下教学任务')
        .firstMatch(markdown);
    final teacher = header?.group(1)?.trim() ?? '';
    final semester = header?.group(2)?.trim() ?? '';

    final rows = <List<String>>[];
    for (final line in markdown.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (!t.startsWith('|') || !t.endsWith('|')) continue;
      final cells = t.substring(1, t.length - 1).split('|').map((c) => c.trim()).toList();
      if (cells.length < 10) continue;
      if (cells[0] == '课程名称') continue; // 表头
      if (cells.every((c) => c.isEmpty || RegExp(r'^-+$').hasMatch(c))) continue; // 分隔行
      rows.add(cells.take(_colCount).toList());
    }
    return TeachingTaskData(teacher: teacher, semester: semester, rows: rows);
  }

  /// 生成 PDF 字节。中文字体内嵌（仿宋正文 + 黑体标题），跨平台不依赖系统字体。
  static Future<Uint8List> build(String markdown, {DateTime? now}) async {
    final data = parse(markdown);
    await _ensureFonts();
    final date = now ?? DateTime.now();
    final dateStr =
        '${date.year}年${date.month.toString().padLeft(2, '0')}月${date.day.toString().padLeft(2, '0')}日';

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _fontRegular!, bold: _fontBold!);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 28, marginRight: 28, marginTop: 28, marginBottom: 28,
        ),
        theme: theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _copy(data, dateStr, isStub: true),
            pw.SizedBox(height: 14),
            _dashedDivider(),
            pw.SizedBox(height: 14),
            _copy(data, dateStr, isStub: false),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// 一份任务书（存根或正本）。[isStub] 为真时显示「（存根）」与「领取签名」。
  static pw.Widget _copy(TeachingTaskData data, String dateStr, {required bool isStub}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text('教 学 任 务 书',
              style: pw.TextStyle(font: _fontBold, fontSize: 17, fontWeight: pw.FontWeight.bold)),
        ),
        if (isStub) ...[
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('（存根）', style: const pw.TextStyle(fontSize: 12))),
        ],
        pw.SizedBox(height: 10),
        pw.Text(
          '经学校批准聘请${data.teacher}老师担任${data.semester}以下教学任务：',
          style: const pw.TextStyle(fontSize: 10.5),
        ),
        pw.SizedBox(height: 8),
        _table(data.rows),
        pw.SizedBox(height: 16),
        _signatureRow(dateStr, isStub: isStub),
      ],
    );
  }

  static pw.Widget _table(List<List<String>> rows) {
    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < _weights.length; i++) i: pw.FlexColumnWidth(_weights[i]),
    };
    const border = pw.TableBorder(
      top: pw.BorderSide(width: 0.5),
      bottom: pw.BorderSide(width: 0.5),
      left: pw.BorderSide(width: 0.5),
      right: pw.BorderSide(width: 0.5),
      horizontalInside: pw.BorderSide(width: 0.5),
      verticalInside: pw.BorderSide(width: 0.5),
    );

    pw.Widget cell(String text, {bool header = false}) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: pw.Text(text,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  font: header ? _fontBold : _fontRegular,
                  fontSize: header ? 8.5 : 8,
                  fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    final bodyRows = <pw.TableRow>[
      pw.TableRow(children: [for (final c in _columns) cell(c, header: true)]),
    ];
    for (final r in rows) {
      bodyRows.add(pw.TableRow(children: [for (final c in r) cell(c)]));
    }
    // 样图空表也保留若干空行，至少 6 行数据区。
    final padTo = rows.length < 6 ? 6 - rows.length : 0;
    for (var i = 0; i < padTo; i++) {
      bodyRows.add(pw.TableRow(children: [for (var j = 0; j < _colCount; j++) cell('')]));
    }

    return pw.Table(border: border, columnWidths: widths, children: bodyRows);
  }

  static pw.Widget _signatureRow(String dateStr, {required bool isStub}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (isStub)
          pw.Expanded(
            flex: 3,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('教学任务书', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 12),
              pw.Text('领取签名：', style: const pw.TextStyle(fontSize: 10)),
            ]),
          ),
        pw.Expanded(
          flex: 3,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Text('院长', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 12),
            pw.Text('签章', style: const pw.TextStyle(fontSize: 10)),
          ]),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.SizedBox(height: 14),
            pw.Text(dateStr, style: const pw.TextStyle(fontSize: 10)),
          ]),
        ),
      ],
    );
  }

  static pw.Widget _dashedDivider() {
    return pw.Row(
      children: List.generate(
        60,
        (_) => pw.Expanded(
          child: pw.Container(
            height: 0.6,
            margin: const pw.EdgeInsets.symmetric(horizontal: 2),
            color: PdfColors.grey600,
          ),
        ),
      ),
    );
  }

  static Future<void> _ensureFonts() async {
    if (_fontRegular != null && _fontBold != null) return;
    // 单一 simhei.ttf（黑体）兼作正文与标题：pdf 包不支持 .ttc(msyh) 字形解析，
    // 必须用单脸 TTF；只捆一个字体，兼顾官方版式观感与包体积。
    final data = await rootBundle.load('assets/fonts/simhei.ttf');
    _fontRegular = pw.Font.ttf(data);
    _fontBold = _fontRegular;
  }
}

/// 解析后的任务书数据。
class TeachingTaskData {
  final String teacher;
  final String semester;
  final List<List<String>> rows;
  const TeachingTaskData({required this.teacher, required this.semester, required this.rows});
}
