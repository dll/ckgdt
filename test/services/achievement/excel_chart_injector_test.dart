/// 验证 ExcelChartInjector 往 excel 包导出的 xlsx 注入了真实 OOXML 图表：
/// - 条形图(课程目标条形图) + 散点趋势图(目标N散点趋势图)
/// - chart/drawing 部件、content-types、sheet→drawing 关系齐全
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:knowledge_graph_app/services/achievement/excel_chart_injector.dart';

void main() {
  test('注入条形图+散点趋势图后 xlsx 结构合法', () {
    final excel = xl.Excel.createExcel();
    for (final n in excel.tables.keys.toList()) {
      excel.delete(n);
    }
    final bar = excel['课程目标条形图'];
    for (int i = 0; i < 4; i++) {
      bar.appendRow([
        xl.TextCellValue('目标${i + 1}'),
        xl.DoubleCellValue(0.8 - i * 0.05),
      ]);
    }
    final sc = excel['目标1散点趋势图'];
    for (int k = 0; k < 5; k++) {
      sc.appendRow([
        xl.DoubleCellValue((k + 1).toDouble()),
        xl.DoubleCellValue(0.7 + k * 0.02),
        xl.DoubleCellValue(0.75),
        xl.DoubleCellValue(0.6),
      ]);
    }

    final raw = excel.save()!;
    final specs = [
      const ChartSpec.bar(sheetName: '课程目标条形图', title: '课程目标达成度', rowCount: 4),
      const ChartSpec.scatter(
          sheetName: '目标1散点趋势图', title: '学生个体课程目标1达成评价结果', rowCount: 5),
    ];
    final out = ExcelChartInjector.inject(Uint8List.fromList(raw), specs);

    final arch = ZipDecoder().decodeBytes(out);
    final names = arch.files.map((f) => f.name).toSet();

    final charts = names.where((n) => n.startsWith('xl/charts/chart')).toList();
    final drawingsWithContent = arch.files.where((f) =>
        f.name.startsWith('xl/drawings/drawing') &&
        f.name.endsWith('.xml') &&
        utf8.decode(f.content as List<int>).contains('graphicFrame'));
    expect(charts.length, greaterThanOrEqualTo(2), reason: '应有≥2个chart部件');
    expect(drawingsWithContent.length, greaterThanOrEqualTo(2),
        reason: '应有≥2个含图表锚点的drawing');

    final ct = utf8.decode(arch.files
        .firstWhere((f) => f.name == '[Content_Types].xml')
        .content as List<int>);
    expect(ct.contains('drawingml.chart+xml'), isTrue);

    final barChart = arch.files.firstWhere((f) =>
        charts.contains(f.name) &&
        utf8.decode(f.content as List<int>).contains('barChart'));
    final barXml = utf8.decode(barChart.content as List<int>);
    expect(barXml.contains("课程目标条形图'!\$A\$1:\$A\$4"), isTrue,
        reason: '柱状图类别引用A列');
    expect(barXml.contains("课程目标条形图'!\$B\$1:\$B\$4"), isTrue,
        reason: '柱状图数值引用B列');

    final scChart = arch.files.firstWhere((f) =>
        charts.contains(f.name) &&
        utf8.decode(f.content as List<int>).contains('scatterChart'));
    final scXml = utf8.decode(scChart.content as List<int>);
    expect(scXml.contains('<c:trendline>'), isTrue, reason: '散点图含线性趋势线');
    expect('<c:ser>'.allMatches(scXml).length, 3, reason: '散点图3个系列');

    final sheetXmls = arch.files.where((f) =>
        f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'));
    final withDrawing = sheetXmls.where(
        (f) => utf8.decode(f.content as List<int>).contains('<drawing '));
    expect(withDrawing.length, greaterThanOrEqualTo(2),
        reason: '≥2个worksheet挂载了drawing');
  });
}
