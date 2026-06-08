import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/error_handler.dart';

/// 课程达成评价报告 DOCX 生成器
class AchievementDocxService {
  static final AchievementDocxService instance = AchievementDocxService._();
  AchievementDocxService._();

  /// 生成 DOCX 文件并返回路径
  Future<String> generateReport({
    required String batchName,
    required String courseName,
    required String className,
    required String semester,
    required String teacherName,
    required Map<String, dynamic> syllabus,
    required List<Map<String, dynamic>> objectives, // [{objective, weight, avgScore, achievement}]
    required Map<String, dynamic> classStats, // {studentCount, avgTotal, maxTotal, minTotal, stdDev}
    required List<Map<String, dynamic>> students, // [{id, name, obj1..4, total}]
  }) async {
    final archive = Archive();

    // 文档关系
    final rels = _buildRels();
    final contentTypes = _buildContentTypes();

    // 主文档
    final documentXml = _buildDocumentXml(
      batchName: batchName,
      courseName: courseName,
      className: className,
      semester: semester,
      teacherName: teacherName,
      syllabus: syllabus,
      objectives: objectives,
      classStats: classStats,
      students: students,
    );

    // 添加文件到 archive
    archive.addFile(ArchiveFile.string('[Content_Types].xml', contentTypes));
    archive.addFile(ArchiveFile.string('_rels/.rels', rels));
    archive.addFile(ArchiveFile.string('word/document.xml', documentXml));
    archive.addFile(ArchiveFile.string('word/_rels/document.xml.rels', _buildDocRels()));

    // 写入临时文件
    final dir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${dir.path}/achievement_reports');
    if (!await outputDir.exists()) await outputDir.create(recursive: true);

    final safeName = '${courseName}_${className}_达成评价报告'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${outputDir.path}/$safeName.docx';

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive) ?? [];
    await File(filePath).writeAsBytes(Uint8List.fromList(zipBytes));

    return filePath;
  }

  String _buildRels() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
  }

  String _buildContentTypes() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
  }

  String _buildDocRels() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';
  }

  String _buildDocumentXml({
    required String batchName,
    required String courseName,
    required String className,
    required String semester,
    required String teacherName,
    required Map<String, dynamic> syllabus,
    required List<Map<String, dynamic>> objectives,
    required Map<String, dynamic> classStats,
    required List<Map<String, dynamic>> students,
  }) {
    final b = StringBuffer();
    b.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    b.write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    b.write('<w:body>');

    // 标题
    _addTitle(b, '${courseName}课程达成评价报告');
    _addEmpty(b);

    // 一、基本信息
    _addHeading(b, '一、课程基本信息');
    final info = (syllabus['info'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        ) ??
        <String, String>{};
    _addTable(b, ['项目', '内容'], [
      ['课程名称', info['英文名称'] ?? courseName],
      ['课程代码', info['课程代码'] ?? ''],
      ['课程类别', info['课程类别'] ?? ''],
      ['学时/学分', '${info['总 学 时'] ?? ''} / ${info['总 学 分'] ?? ''}'],
      ['考核方式', info['考核方式'] ?? '考查'],
      ['开课学期', info['开课学期'] ?? semester],
      ['班级', className],
      ['授课教师', teacherName],
    ]);
    _addEmpty(b);

    // 二、课程目标与毕业要求
    _addHeading(b, '二、课程目标及其对毕业要求的支撑');
    final objList = syllabus['objectives'] as List? ?? [];
    final rows = <List<String>>[];
    for (final obj in objList) {
      rows.add(['课程目标${obj['num']}', obj['objective'] ?? '', obj['requirement'] ?? '']);
    }
    _addTable(b, ['序号', '课程目标', '支撑毕业要求'], rows);
    _addEmpty(b);

    // 三、考核权重
    _addHeading(b, '三、课程考核与评价方式');
    final weights = syllabus['weights'] as List? ?? [];
    final weightRows = <List<String>>[];
    for (final w in weights) {
      weightRows.add([
        '课程目标${w['objective']}',
        '${w['weight']}',
        '${w['pingshi_full']}',
        '${w['experiment_full']}',
        '${w['exam_full']}',
      ]);
    }
    _addTable(b, ['课程目标', '权重', '平时(20%)', '实验(30%)', '期末(50%)'], weightRows);
    _addEmpty(b);

    // 四、达成度计算结果
    _addHeading(b, '四、课程目标达成度计算');
    _addPara(b, '计算说明：学生个人课程目标达成度 = 各考核方式中该目标得分总和 / 该目标满分总和。');
    _addPara(b, '班级课程目标达成度 = 所有学生该目标达成度的算术平均值。');
    _addPara(b, '加权总达成度 = Σ(课程目标i达成度 × 权重i)。');
    _addEmpty(b);

    // 达成度汇总表
    final summaryRows = <List<String>>[];
    double totalWeighted = 0;
    for (final obj in objectives) {
      final ach = (obj['achievement'] as double?) ?? 0;
      final w = (obj['weight'] as double?) ?? 0;
      totalWeighted += ach * w;
      summaryRows.add([
        '课程目标${obj['objective']}',
        ach.toStringAsFixed(3),
        w.toStringAsFixed(2),
        (ach * 100).toStringAsFixed(1),
        _achievementLevel(ach),
      ]);
    }
    summaryRows.add(['加权总达成度', totalWeighted.toStringAsFixed(3), '1.00',
      (totalWeighted * 100).toStringAsFixed(1), _achievementLevel(totalWeighted)]);

    _addTable(b, ['课程目标', '达成度', '权重', '百分制', '评价等级'], summaryRows);
    _addEmpty(b);

    // 统计信息
    _addHeading(b, '五、成绩统计分析');
    _addTable(b, ['指标', '数值'], [
      ['学生人数', '${classStats['studentCount']}'],
      ['班级平均分', '${(classStats['avgTotal'] as double?)?.toStringAsFixed(1) ?? "0"}'],
      ['最高分', '${(classStats['maxTotal'] as double?)?.toStringAsFixed(1) ?? "0"}'],
      ['最低分', '${(classStats['minTotal'] as double?)?.toStringAsFixed(1) ?? "0"}'],
      ['标准差', '${(classStats['stdDev'] as double?)?.toStringAsFixed(2) ?? "0"}'],
    ]);
    _addEmpty(b);

    // 六、学生个体达成度
    _addHeading(b, '六、学生个体达成度明细');
    final stuHeader = ['学号', '姓名'];
    for (int i = 0; i < (objectives.length).clamp(0, 4); i++) {
      stuHeader.add('课程目标${i + 1}');
    }
    stuHeader.add('总分');
    stuHeader.add('评价等级');

    final stuRows = <List<String>>[];
    for (final s in students.take(50)) {
      final row = [
        '${s['student_id'] ?? ""}',
        '${s['student_name'] ?? ""}',
      ];
      for (int i = 1; i <= 4; i++) {
        row.add('${(s['obj${i}_score'] as double?)?.toStringAsFixed(1) ?? "0"}');
      }
      final total = (s['total_score'] as double?) ?? 0;
      row.add(total.toStringAsFixed(1));
      row.add(_achievementLevel(total / 100));
      stuRows.add(row);
    }
    _addTable(b, stuHeader, stuRows);
    _addEmpty(b);

    // 七、达成结果分析与改进措施
    _addHeading(b, '七、达成结果分析与改进措施');
    _addHeading(b, '（一）达成结果分析', level: 2);

    for (final obj in objectives) {
      final ach = (obj['achievement'] as double?) ?? 0;
      final level = _achievementLevel(ach);
      _addPara(b, '课程目标${obj['objective']}：达成度为${ach.toStringAsFixed(3)}（${level}）。'
          '${ach < 0.6 ? "该目标达成度偏低，需重点加强教学。" : ach > 0.8 ? "该目标达成情况优秀。" : "该目标达成情况良好，仍有提升空间。"}');
    }
    _addPara(b, '加权总达成度为${totalWeighted.toStringAsFixed(3)}，总体评价：${_achievementLevel(totalWeighted)}。');

    _addHeading(b, '（二）持续改进措施', level: 2);
    _addPara(b, '1. 针对达成度较低的课程目标，优化教学内容与方法，增加实践环节。');
    _addPara(b, '2. 加强学生学习过程监控，及时发现问题并进行针对性辅导。');
    _addPara(b, '3. 改进考核方式，确保评价体系能够全面反映学生能力达成情况。');
    _addPara(b, '4. 定期组织教学研讨，分享教学经验，持续提升教学质量。');
    _addEmpty(b);

    // 结尾
    _addEmpty(b);
    _addPara(b, '报告生成时间：${DateTime.now().toString().substring(0, 16)}');
    _addPara(b, '授课教师：$teacherName');

    b.write('</w:body></w:document>');
    return b.toString();
  }

  void _addTitle(StringBuffer b, String text) {
    _addPara(b, text, align: 'center', bold: true, size: 22);
  }

  void _addHeading(StringBuffer b, String text, {int level = 1}) {
    final size = level == 1 ? 28 : 24;
    _addPara(b, text, bold: true, size: size);
  }

  void _addPara(StringBuffer b, String text, {String align = 'left', bool bold = false, int size = 21}) {
    final escaped = _escape(text);
    final jc = align == 'center' ? '<w:jc w:val="center"/>' : '';
    b.write('<w:p><w:pPr>$jc</w:pPr><w:r><w:rPr>');
    if (bold) b.write('<w:b/><w:bCs/>');
    b.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/>');
    b.write('</w:rPr><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>');
  }

  void _addEmpty(StringBuffer b) {
    b.write('<w:p><w:r><w:t xml:space="preserve"> </w:t></w:r></w:p>');
  }

  void _addTable(StringBuffer b, List<String> headers, List<List<String>> rows) {
    b.write('<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/>');
    b.write('<w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('</w:tblBorders></w:tblPr>');

    // 表头行
    b.write('<w:tr><w:tblPrEx><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    b.write('</w:tblBorders></w:tblPrEx>');
    for (final h in headers) {
      b.write('<w:tc><w:tcPr><w:shd w:fill="4472C4" w:val="clear"/></w:tcPr>');
      b.write('<w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="20"/></w:rPr>');
      b.write('<w:t xml:space="preserve">${_escape(h)}</w:t></w:r></w:p></w:tc>');
    }
    b.write('</w:tr>');

    // 数据行
    for (int i = 0; i < rows.length; i++) {
      final fill = i % 2 == 0 ? 'F2F2F2' : 'FFFFFF';
      b.write('<w:tr>');
      for (final cell in rows[i]) {
        b.write('<w:tc><w:tcPr><w:shd w:fill="$fill" w:val="clear"/></w:tcPr>');
        b.write('<w:p><w:r><w:rPr><w:sz w:val="20"/></w:rPr>');
        b.write('<w:t xml:space="preserve">${_escape(cell)}</w:t></w:r></w:p></w:tc>');
      }
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
  }

  String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _achievementLevel(double val) {
    if (val >= 0.85) return '优秀';
    if (val >= 0.70) return '良好';
    if (val >= 0.60) return '中等';
    return '未达成';
  }
}
