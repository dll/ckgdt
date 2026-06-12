import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// 给 excel 包(^4.0.6，不支持图表)导出的 xlsx 注入原生 OOXML 图表。
///
/// excel 包只写单元格；本类在 save() 后的 zip 里补齐：
///   xl/charts/chartK.xml          图表定义（引用 sheet 数据区）
///   xl/drawings/drawingM.xml      把图表锚定到工作表
///   xl/drawings/_rels/...rels     drawing→chart 关系
///   xl/worksheets/_rels/...rels   sheet→drawing 关系
///   worksheet.xml 内 <drawing>    挂载点
///   [Content_Types].xml 覆盖项     chart/drawing 内容类型
///
/// 支持：[ChartSpec.bar] 柱状图、[ChartSpec.scatter] 散点+线性趋势线+参考线。
class ExcelChartInjector {
  /// 在 [bytes]（excel.save() 结果）上按 [specs] 注入图表，返回新 xlsx 字节。
  /// 任一 sheet 名不存在则跳过该 spec（不报错）。
  static Uint8List inject(Uint8List bytes, List<ChartSpec> specs) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, List<int>>{};
    for (final f in archive.files) {
      files[f.name] = f.content as List<int>;
    }

    final workbook = _str(files['xl/workbook.xml']);
    final workbookRels = _str(files['xl/_rels/workbook.xml.rels']);
    if (workbook == null || workbookRels == null) return bytes;

    // sheet 名 -> r:id（兼容属性两种顺序）
    final nameToRid = <String, String>{};
    for (final m in RegExp(r'<sheet\b[^>]*?>').allMatches(workbook)) {
      final tag = m.group(0)!;
      final name = RegExp(r'name="([^"]*)"').firstMatch(tag)?.group(1);
      final rid = RegExp(r'r:id="([^"]*)"').firstMatch(tag)?.group(1);
      if (name != null && rid != null) nameToRid[_unescape(name)] = rid;
    }
    final ridToTarget = <String, String>{};
    for (final m in RegExp(r'<Relationship\b[^>]*?>').allMatches(workbookRels)) {
      final tag = m.group(0)!;
      final id = RegExp(r'Id="([^"]*)"').firstMatch(tag)?.group(1);
      final tgt = RegExp(r'Target="([^"]*)"').firstMatch(tag)?.group(1);
      if (id != null && tgt != null) ridToTarget[id] = tgt;
    }

    int maxDrawing = 0, maxChart = 0;
    for (final name in files.keys) {
      final dm = RegExp(r'xl/drawings/drawing(\d+)\.xml$').firstMatch(name);
      if (dm != null) maxDrawing = _max(maxDrawing, int.parse(dm.group(1)!));
      final cm = RegExp(r'xl/charts/chart(\d+)\.xml$').firstMatch(name);
      if (cm != null) maxChart = _max(maxChart, int.parse(cm.group(1)!));
    }

    var contentTypes = _str(files['[Content_Types].xml'])!;
    bool injectedAny = false;

    for (final spec in specs) {
      final rid = nameToRid[spec.sheetName];
      if (rid == null) continue;
      final target = ridToTarget[rid];
      if (target == null) continue;
      final sheetPath = 'xl/$target';
      final sheetXml = _str(files[sheetPath]);
      if (sheetXml == null) continue;

      final sheetFile = target.split('/').last;
      final drawingNo = ++maxDrawing;
      final chartNo = ++maxChart;

      files['xl/charts/chart$chartNo.xml'] = _bytes(spec.buildChartXml());
      files['xl/drawings/drawing$drawingNo.xml'] = _bytes(_drawingXml());
      files['xl/drawings/_rels/drawing$drawingNo.xml.rels'] = _bytes(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" '
        'Target="../charts/chart$chartNo.xml"/></Relationships>',
      );

      final sheetRelsPath = 'xl/worksheets/_rels/$sheetFile.rels';
      final drawRelId = _appendDrawingRel(
          files, sheetRelsPath, _str(files[sheetRelsPath]), drawingNo);

      if (!sheetXml.contains('<drawing ')) {
        files[sheetPath] = _bytes(sheetXml.replaceFirst(
            '</worksheet>', '<drawing r:id="$drawRelId"/></worksheet>'));
      }

      final addCt = StringBuffer();
      if (!contentTypes.contains('/xl/charts/chart$chartNo.xml')) {
        addCt.write('<Override PartName="/xl/charts/chart$chartNo.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>');
      }
      if (!contentTypes.contains('/xl/drawings/drawing$drawingNo.xml')) {
        addCt.write('<Override PartName="/xl/drawings/drawing$drawingNo.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>');
      }
      if (addCt.isNotEmpty) {
        contentTypes = contentTypes.replaceFirst('</Types>', '$addCt</Types>');
      }
      injectedAny = true;
    }

    if (!injectedAny) return bytes;
    files['[Content_Types].xml'] = _bytes(contentTypes);

    final out = Archive();
    files.forEach((name, content) {
      out.addFile(ArchiveFile(name, content.length, content));
    });
    final encoded = ZipEncoder().encode(out);
    return Uint8List.fromList(encoded ?? bytes);
  }

  static String _drawingXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<xdr:twoCellAnchor>'
        '<xdr:from><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
        '<xdr:to><xdr:col>13</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>24</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
        '<xdr:graphicFrame macro="">'
        '<xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="Chart"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
        '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
        '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId1"/>'
        '</a:graphicData></a:graphic>'
        '</xdr:graphicFrame><xdr:clientData/>'
        '</xdr:twoCellAnchor></xdr:wsDr>';
  }

  static String _appendDrawingRel(Map<String, List<int>> files,
      String relsPath, String? existing, int drawingNo) {
    final target = '../drawings/drawing$drawingNo.xml';
    const type =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing';
    if (existing == null) {
      files[relsPath] = _bytes(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$type" Target="$target"/></Relationships>',
      );
      return 'rId1';
    }
    int maxId = 0;
    for (final m in RegExp(r'Id="rId(\d+)"').allMatches(existing)) {
      maxId = _max(maxId, int.parse(m.group(1)!));
    }
    final newId = 'rId${maxId + 1}';
    files[relsPath] = _bytes(existing.replaceFirst('</Relationships>',
        '<Relationship Id="$newId" Type="$type" Target="$target"/></Relationships>'));
    return newId;
  }

  static int _max(int a, int b) => a > b ? a : b;
  static String? _str(List<int>? b) => b == null ? null : utf8.decode(b);
  static List<int> _bytes(String s) => utf8.encode(s);
  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// 一张图表的规格：目标 sheet 名 + 类型 + 数据区行数。
class ChartSpec {
  final String sheetName;
  final String title;
  final ChartType type;
  final int rowCount;

  const ChartSpec.bar({
    required this.sheetName,
    required this.title,
    required this.rowCount,
  }) : type = ChartType.bar;

  const ChartSpec.scatter({
    required this.sheetName,
    required this.title,
    required this.rowCount,
  }) : type = ChartType.scatter;

  String _sheetRef(String col) {
    final esc = sheetName
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return "'$esc'!\$$col\$1:\$$col\$$rowCount";
  }

  String buildChartXml() =>
      type == ChartType.bar ? _barXml() : _scatterXml();

  String _head() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<c:chart>'
      '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>'
      '${title.replaceAll('&', '&amp;').replaceAll('<', '&lt;')}'
      '</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>'
      '<c:autoTitleDeleted val="0"/>';

  String _barXml() {
    return '${_head()}<c:plotArea><c:layout/>'
        '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/><c:varyColors val="1"/>'
        '<c:ser><c:idx val="0"/><c:order val="0"/>'
        '<c:tx><c:v>达成度</c:v></c:tx>'
        '<c:cat><c:strRef><c:f>${_sheetRef('A')}</c:f></c:strRef></c:cat>'
        '<c:val><c:numRef><c:f>${_sheetRef('B')}</c:f></c:numRef></c:val>'
        '</c:ser>'
        '<c:axId val="111111111"/><c:axId val="222222222"/>'
        '</c:barChart>'
        '<c:catAx><c:axId val="111111111"/><c:scaling><c:orientation val="minMax"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="b"/><c:crossAx val="222222222"/></c:catAx>'
        '<c:valAx><c:axId val="222222222"/><c:scaling><c:orientation val="minMax"/>'
        '<c:max val="1"/><c:min val="0"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="l"/><c:crossAx val="111111111"/></c:valAx>'
        '</c:plotArea><c:plotVisOnly val="1"/></c:chart></c:chartSpace>';
  }

  String _scatterXml() {
    return '${_head()}<c:plotArea><c:layout/>'
        '<c:scatterChart><c:scatterStyle val="lineMarker"/><c:varyColors val="0"/>'
        '<c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:v>个体达成度</c:v></c:tx>'
        '<c:spPr><a:ln w="19050"><a:noFill/></a:ln></c:spPr>'
        '<c:trendline><c:trendlineType val="linear"/><c:dispRSqr val="0"/><c:dispEq val="0"/></c:trendline>'
        '<c:xVal><c:numRef><c:f>${_sheetRef('A')}</c:f></c:numRef></c:xVal>'
        '<c:yVal><c:numRef><c:f>${_sheetRef('B')}</c:f></c:numRef></c:yVal>'
        '<c:smooth val="0"/></c:ser>'
        '<c:ser><c:idx val="1"/><c:order val="1"/><c:tx><c:v>班级平均</c:v></c:tx>'
        '<c:marker><c:symbol val="none"/></c:marker>'
        '<c:xVal><c:numRef><c:f>${_sheetRef('A')}</c:f></c:numRef></c:xVal>'
        '<c:yVal><c:numRef><c:f>${_sheetRef('C')}</c:f></c:numRef></c:yVal>'
        '<c:smooth val="0"/></c:ser>'
        '<c:ser><c:idx val="2"/><c:order val="2"/><c:tx><c:v>期望(0.6)</c:v></c:tx>'
        '<c:marker><c:symbol val="none"/></c:marker>'
        '<c:xVal><c:numRef><c:f>${_sheetRef('A')}</c:f></c:numRef></c:xVal>'
        '<c:yVal><c:numRef><c:f>${_sheetRef('D')}</c:f></c:numRef></c:yVal>'
        '<c:smooth val="0"/></c:ser>'
        '<c:axId val="333333333"/><c:axId val="444444444"/>'
        '</c:scatterChart>'
        '<c:valAx><c:axId val="333333333"/><c:scaling><c:orientation val="minMax"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="b"/><c:crossAx val="444444444"/></c:valAx>'
        '<c:valAx><c:axId val="444444444"/><c:scaling><c:orientation val="minMax"/>'
        '<c:max val="1"/><c:min val="0"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="l"/><c:crossAx val="333333333"/></c:valAx>'
        '</c:plotArea><c:plotVisOnly val="1"/></c:chart></c:chartSpace>';
  }
}

enum ChartType { bar, scatter }
