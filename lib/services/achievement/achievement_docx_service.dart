import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';
import '../output_path_service.dart';
import 'achievement_template_assets.dart';

/// 课程达成评价报告 DOCX 生成器。
///
/// 输出结构高度对齐学校参考模板
/// （data/达成/计科22《移动应用开发》课程达成评价表格-课程目标达成评价报告.docx）：
/// - 表0 基本信息（课程/班级/教师/支撑毕业要求对应关系）
/// - 表1 课程目标达成考核与评价方式及成绩评定对照表（目标×平时/实验/期末满分比例）
/// - 表2 平时成绩评价标准
/// - 表3 实验成绩评价标准
/// - 表4 期末考核评价内容
/// - 表5 课程目标×评价环节 达成度计算（满分|平均分|达成度|环节权重→目标达成度→指标点达成度）
/// - 表6 达成结果分析与持续改进
class AchievementDocxService {
  static final AchievementDocxService instance = AchievementDocxService._();
  AchievementDocxService._();

  /// 生成 DOCX 文件并返回路径。
  ///
  /// [objectives]：4 个课程目标，每项 {objective(1-4), weight, indicator,
  ///   description, achievement, envs}。envs 是 3 个评价环节
  ///   [{name:'平时'|'实验'|'期末考试', full, avg, ach, weight}]。
  /// [classStats]：{studentCount, avgTotal, maxTotal, minTotal, stdDev}。
  /// [analysisText] / [improvementText]：达成分析与持续改进正文（可空，空则用默认模板）。
  Future<String> generateReport({
    required String batchName,
    required String courseName,
    required String className,
    required String semester,
    required String teacherName,
    required Map<String, dynamic> syllabus,
    required List<Map<String, dynamic>> objectives,
    required Map<String, dynamic> classStats,
    required List<Map<String, dynamic>> students,
    String? analysisText,
    String? qualitativeText,
    String? improvementText,
    double expectation = 0.6,
  }) async {
    final template = await _findTemplateForCourse(courseName);
    if (template != null) {
      try {
        return await _generateReportFromTemplate(
          template: template,
          courseName: courseName,
          className: className,
          semester: semester,
          teacherName: teacherName,
          syllabus: syllabus,
          objectives: objectives,
          classStats: classStats,
          students: students,
          analysisText: analysisText,
          qualitativeText: qualitativeText,
          improvementText: improvementText,
          expectation: expectation,
        );
      } catch (_) {
        // Fall through to the generated OOXML report if a user-supplied
        // template is malformed or no longer matches the expected tables.
      }
    }

    final archive = Archive();

    final documentXml = _buildDocumentXml(
      courseName: courseName,
      className: className,
      semester: semester,
      teacherName: teacherName,
      syllabus: syllabus,
      objectives: objectives,
      classStats: classStats,
      students: students,
      analysisText: analysisText,
      qualitativeText: qualitativeText,
      improvementText: improvementText,
      expectation: expectation,
    );

    archive.addFile(
        ArchiveFile.string('[Content_Types].xml', _buildContentTypes()));
    archive.addFile(ArchiveFile.string('_rels/.rels', _buildRels()));
    archive.addFile(ArchiveFile.string('word/document.xml', documentXml));
    archive.addFile(
        ArchiveFile.string('word/_rels/document.xml.rels', _buildDocRels()));

    final dir = await OutputPathService.getOutputDirectory();
    final safeName = '${courseName}_${className}_达成评价报告'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${dir.path}/$safeName.docx';

    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    await File(filePath).writeAsBytes(Uint8List.fromList(zipBytes));
    return filePath;
  }

  Future<File?> _findTemplateForCourse(String courseName) async {
    final roots = await AchievementTemplateAssets.templateRoots();
    final seen = <String>{};
    final candidates = <File>[];
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!seen.add(path)) continue;
        final name = path.split(Platform.pathSeparator).last;
        if (name.startsWith('~\$')) continue;
        if (!name.toLowerCase().endsWith('.docx')) continue;
        if (!name.contains('达成')) continue;
        if (courseName.isNotEmpty && !name.contains(courseName)) continue;
        candidates.add(entity);
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final an = a.path.contains('评价报告') ? 0 : 1;
      final bn = b.path.contains('评价报告') ? 0 : 1;
      if (an != bn) return an.compareTo(bn);
      return a.path.length.compareTo(b.path.length);
    });
    return candidates.first;
  }

  Future<String> _generateReportFromTemplate({
    required File template,
    required String courseName,
    required String className,
    required String semester,
    required String teacherName,
    required Map<String, dynamic> syllabus,
    required List<Map<String, dynamic>> objectives,
    required Map<String, dynamic> classStats,
    required List<Map<String, dynamic>> students,
    String? analysisText,
    String? qualitativeText,
    String? improvementText,
    required double expectation,
  }) async {
    final archive = ZipDecoder().decodeBytes(await template.readAsBytes());
    final files = <String, List<int>>{};
    for (final f in archive.files) {
      files[f.name] = f.content as List<int>;
    }

    final documentBytes = files['word/document.xml'];
    if (documentBytes == null) throw StateError('模板缺 word/document.xml');
    final doc = XmlDocument.parse(utf8.decode(documentBytes));
    final tables = _descendants(doc, 'tbl');
    if (tables.length < 7) throw StateError('达成报告模板表格数不足');

    _fillDocxTitle(doc, '$semester《$courseName》课程目标达成评价报告');
    _fillDocxBasicInfo(tables[0], courseName, className, semester, teacherName,
        syllabus, objectives, classStats, students);
    _fillDocxAssessmentTable(tables[1], objectives);
    _fillDocxStandardTable(tables[2], objectives);
    _fillDocxStandardTable(tables[3], objectives);
    _fillDocxExamContentTable(tables[4], objectives);
    _fillDocxAchievementMatrix(tables[5], objectives, expectation);
    _fillDocxAnalysisTable(
      tables[6],
      objectives,
      classStats,
      analysisText,
      qualitativeText,
      improvementText,
      teacherName,
    );

    files['word/document.xml'] = utf8.encode(doc.toXmlString());
    final out = Archive();
    files.forEach((name, content) {
      out.addFile(ArchiveFile(name, content.length, content));
    });

    final dir = await OutputPathService.getOutputDirectory();
    final safeName = '${courseName}_${className}_达成评价报告'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${dir.path}/$safeName.docx';
    final zipBytes = ZipEncoder().encode(out) ?? <int>[];
    await File(filePath).writeAsBytes(Uint8List.fromList(zipBytes));
    return filePath;
  }

  void _fillDocxTitle(XmlDocument doc, String title) {
    for (final p in _descendants(doc, 'p')) {
      if (!_elementText(p).contains('课程目标达成评价报告')) continue;
      _setParagraphText(p, title);
      return;
    }
  }

  void _fillDocxBasicInfo(
    XmlElement table,
    String courseName,
    String className,
    String semester,
    String teacherName,
    Map<String, dynamic> syllabus,
    List<Map<String, dynamic>> objectives,
    Map<String, dynamic> classStats,
    List<Map<String, dynamic>> students,
  ) {
    final info = (syllabus['info'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ??
        <String, String>{};
    final studentCount =
        (classStats['studentCount'] ?? students.length).toString();
    _setCell(table, 1, 1, courseName);
    _setCell(table, 1, 3, info['课程类别'] ?? '专业基础');
    _setCell(table, 1, 5, info['总 学 时'] ?? info['课程学时'] ?? '48');
    _setCell(table, 1, 7, info['总 学 分'] ?? info['学分'] ?? '2.5');
    _setCell(table, 2, 1, className);
    _setCell(table, 2, 3, studentCount);
    _setCell(table, 2, 5, teacherName);
    _setCell(table, 3, 1, teacherName);
    _setCell(table, 3, 3, info['考核类型'] ?? '考查');
    _setCell(table, 3, 5, info['考核方式'] ?? '大作业');
    _setCell(table, 4, 1, teacherName);
    _setCell(table, 5, 1, '定量评价+定性评价');
    _setCell(table, 6, 1, '课程教学大纲、课程过程性考核合理性审核表、教学过程性评价数据以及考试成绩');

    for (int i = 0; i < objectives.length && i < 4; i++) {
      final row = 9 + i;
      final obj = objectives[i];
      _setCell(table, row, 0, (obj['description'] ?? '').toString());
      _setCell(table, row, 1, _requirementText(obj));
      _setCell(
        table,
        row,
        2,
        (obj['assess_content'] ?? obj['description'] ?? '').toString(),
      );
    }
  }

  void _fillDocxAssessmentTable(
      XmlElement table, List<Map<String, dynamic>> objectives) {
    for (int i = 0; i < objectives.length && i < 4; i++) {
      final row = 2 + i;
      final obj = objectives[i];
      final idx = (obj['objective'] as num?)?.toInt() ?? i + 1;
      final weight = (obj['weight'] as num?)?.toDouble() ?? 0;
      final full = _objFullMark(obj).toInt();
      _setCell(table, row, 0, '课程目标$idx');
      _setCell(table, row, 1, weight.toStringAsFixed(1));
      _setCell(table, row, 2, '支撑毕业要求${(obj['indicator'] ?? '')}');
      _setCell(table, row, 3, _envRatioCell(obj, '平时', full.toDouble()));
      final experimentCell = _envRatioCell(obj, '实验', full.toDouble());
      _setCell(table, row, 4, experimentCell == '—' ? '' : experimentCell);
      _setCell(table, row, 5, _envRatioCell(obj, '考核', full.toDouble()));
    }
    _setCell(table, 6, 0, '合计（占总评成绩比例）');
    _setCell(table, 6, 1, _hasEnv(objectives, '平时') ? '100' : '');
    _setCell(table, 6, 2, _hasEnv(objectives, '实验') ? '100' : '');
    _setCell(table, 6, 3, _hasEnv(objectives, '考核') ? '100' : '');
  }

  void _fillDocxStandardTable(
      XmlElement table, List<Map<String, dynamic>> objectives) {
    for (int i = 0; i < objectives.length && i < 4; i++) {
      final row = 2 + i;
      final obj = objectives[i];
      final idx = (obj['objective'] as num?)?.toInt() ?? i + 1;
      final indicator = (obj['indicator'] ?? '').toString();
      _setCell(table, row, 0, '课程目标$idx（支撑毕业要求$indicator）');
      _setCell(table, row, 1, (obj['description'] ?? '').toString());
      _setCell(table, row, 6, _objFullMark(obj).toInt().toString());
    }
  }

  void _fillDocxExamContentTable(
      XmlElement table, List<Map<String, dynamic>> objectives) {
    for (int i = 0; i < objectives.length && i < 4; i++) {
      final row = 1 + i;
      final obj = objectives[i];
      final idx = (obj['objective'] as num?)?.toInt() ?? i + 1;
      final indicator = (obj['indicator'] ?? '').toString();
      _setCell(table, row, 0, '课程目标$idx（支撑毕业要求$indicator）');
      _setCell(
        table,
        row,
        1,
        (obj['assess_content'] ?? obj['description'] ?? '').toString(),
      );
      _setCell(table, row, 2, _objFullMark(obj).toInt().toString());
    }
  }

  void _fillDocxAchievementMatrix(
    XmlElement table,
    List<Map<String, dynamic>> objectives,
    double expectation,
  ) {
    for (int i = 0; i < objectives.length && i < 4; i++) {
      final obj = objectives[i];
      final idx = (obj['objective'] as num?)?.toInt() ?? i + 1;
      final weight = (obj['weight'] as num?)?.toDouble() ?? 0;
      final indicator = (obj['indicator'] ?? '').toString();
      final objAch = (obj['achievement'] as num?)?.toDouble() ?? 0;
      final envs = (obj['envs'] as List?) ?? _defaultEnvs(objAch);
      for (int j = 0; j < 3; j++) {
        final row = 5 + i * 3 + j;
        final env = j < envs.length ? envs[j] as Map : const {};
        if (j == 0) {
          _setCell(table, row, 0, '目标$idx');
          _setCell(table, row, 1, weight.toStringAsFixed(1));
          _setCell(table, row, 7, objAch.toStringAsFixed(2));
          _setCell(table, row, 8, indicator);
          _setCell(table, row, 9, objAch.toStringAsFixed(2));
        } else {
          _setCell(table, row, 0, '');
          _setCell(table, row, 1, '');
          _setCell(table, row, 7, '');
          _setCell(table, row, 8, '');
          _setCell(table, row, 9, '');
        }
        _setCell(table, row, 2, (env['name'] ?? '').toString());
        _setCell(table, row, 3,
            ((env['full'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
        _setCell(table, row, 4,
            ((env['avg'] as num?)?.toDouble() ?? 0).toStringAsFixed(2));
        _setCell(table, row, 5,
            ((env['ach'] as num?)?.toDouble() ?? 0).toStringAsFixed(2));
        _setCell(table, row, 6,
            ((env['weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1));
      }
    }
    _setCell(table, 17, 0, '课程总体目标期望值');
    _setCell(table, 17, 1, expectation.toStringAsFixed(1));
    _setCell(table, 17, 2, '课程总体目标达成度(cc)');
  }

  void _fillDocxAnalysisTable(
    XmlElement table,
    List<Map<String, dynamic>> objectives,
    Map<String, dynamic> classStats,
    String? analysisText,
    String? qualitativeText,
    String? improvementText,
    String teacherName,
  ) {
    final quantitative = (analysisText?.trim().isNotEmpty ?? false)
        ? analysisText!
        : _defaultAnalysis(objectives, classStats);
    final qualitative = (qualitativeText?.trim().isNotEmpty ?? false)
        ? qualitativeText!
        : '本课程通过问卷调查获取学生对课程目标达成情况的自我评价。问卷结果与定量评价结果基本一致，表明学生自我评价与实际能力达成情况基本相符。';
    final improvement = (improvementText?.trim().isNotEmpty ?? false)
        ? improvementText!
        : _defaultImprovement(objectives);
    _setCell(table, 1, 0, '课程目标达成情况(定量)');
    _setCell(table, 1, 1, quantitative);
    _setCell(table, 2, 0, '调查问卷评价情况(定性)');
    _setCell(table, 2, 1, qualitative);
    _setCell(table, 3, 0, '达成情况分析及持续改进');
    _setCell(table, 3, 1, improvement);
    _setCell(table, 4, 0, '任课教师签字');
    _setCell(table, 4, 1,
        '$teacherName　　日期：${DateTime.now().toString().substring(0, 10)}');
    _setCell(table, 5, 0, '课程群建设工作组意见');
    _setCell(table, 5, 1, '课程群建设工作组组长签字：　　　　日期：　 年　 月　 日');
  }

  String _requirementText(Map<String, dynamic> obj) {
    final indicator = (obj['indicator'] ?? '').toString();
    if (indicator.isEmpty) return '';
    return indicator.contains('毕业要求') ? indicator : '支撑毕业要求$indicator';
  }

  void _setCell(XmlElement table, int rowIndex, int cellIndex, String text) {
    final rows = _children(table, 'tr');
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    final cells = _children(rows[rowIndex], 'tc');
    if (cellIndex < 0 || cellIndex >= cells.length) return;
    _setCellText(cells[cellIndex], text);
  }

  void _setCellText(XmlElement cell, String text) {
    cell.children.removeWhere(
        (node) => node is! XmlElement || node.name.local != 'tcPr');
    final lines = text.split('\n');
    for (final line in lines.isEmpty ? const [''] : lines) {
      cell.children.add(XmlElement(XmlName('w:p'), [], [
        XmlElement(XmlName('w:r'), [], [
          XmlElement(
            XmlName('w:t'),
            [XmlAttribute(XmlName('xml:space'), 'preserve')],
            [XmlText(line)],
          )
        ])
      ]));
    }
  }

  void _setParagraphText(XmlElement paragraph, String text) {
    paragraph.children
        .removeWhere((node) => node is! XmlElement || node.name.local != 'pPr');
    paragraph.children.add(XmlElement(XmlName('w:r'), [], [
      XmlElement(
        XmlName('w:t'),
        [XmlAttribute(XmlName('xml:space'), 'preserve')],
        [XmlText(text)],
      )
    ]));
  }

  String _elementText(XmlElement element) {
    return _descendants(element, 't').map((t) => t.innerText).join();
  }

  List<XmlElement> _descendants(XmlNode node, String localName) {
    return node.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == localName)
        .toList();
  }

  List<XmlElement> _children(XmlElement element, String localName) {
    return element.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == localName)
        .toList();
  }

  String _buildRels() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  String _buildContentTypes() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

  String _buildDocRels() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';

  String _buildDocumentXml({
    required String courseName,
    required String className,
    required String semester,
    required String teacherName,
    required Map<String, dynamic> syllabus,
    required List<Map<String, dynamic>> objectives,
    required Map<String, dynamic> classStats,
    required List<Map<String, dynamic>> students,
    String? analysisText,
    String? qualitativeText,
    String? improvementText,
    required double expectation,
  }) {
    final b = StringBuffer();
    b.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    b.write(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    b.write('<w:body>');

    final info = (syllabus['info'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ??
        <String, String>{};
    final studentCount =
        (classStats['studentCount'] ?? students.length).toString();

    _title(b, '$semester《$courseName》课程目标达成评价报告');
    _empty(b);

    _buildBasicInfoTable(b, courseName, className, semester, teacherName,
        studentCount, info, objectives);
    _empty(b);

    _heading(b, '课程目标达成考核与评价方式及成绩评定对照表');
    _buildAssessmentRefTable(b, objectives);
    _empty(b);

    _heading(b, '二、课程考核标准');
    var standardIndex = 1;
    if (_hasEnv(objectives, '平时')) {
      _para(b, '$standardIndex 平时成绩评价标准', bold: true);
      _buildStandardTable(b, _objectivesForEnv(objectives, '平时'));
      _para(b, '注：该表格中比例为平时考核成绩比例。');
      standardIndex++;
    }
    if (_hasEnv(objectives, '实验')) {
      _para(b, '$standardIndex 实验成绩评价标准', bold: true);
      _buildStandardTable(b, _objectivesForEnv(objectives, '实验'));
      _para(b, '注：该表格中比例为实验考核成绩比例。');
      standardIndex++;
    }
    if (_hasEnv(objectives, '考核')) {
      _para(b, '$standardIndex 考核评价内容', bold: true);
      _buildExamContentTable(b, _objectivesForEnv(objectives, '考核'));
    }
    _empty(b);

    _heading(b, '三、课程目标和支撑毕业要求指标点达成情况计算（定量评价）');
    _buildAchievementMatrixTable(b, objectives, expectation);
    _empty(b);

    _heading(b, '四、达成结果分析与持续改进');
    _buildAnalysisTable(b, objectives, classStats, analysisText,
        qualitativeText, improvementText, teacherName);

    b.write('</w:body></w:document>');
    return b.toString();
  }

  // ── 表0：基本信息 ───────────────────────────────────────────────
  void _buildBasicInfoTable(
    StringBuffer b,
    String courseName,
    String className,
    String semester,
    String teacherName,
    String studentCount,
    Map<String, String> info,
    List<Map<String, dynamic>> objectives,
  ) {
    b.write(_tblStart(9000));
    _mergedHeaderRow(b, '一、基本信息', 9);
    _kvRow(b, [
      '课程名称',
      courseName,
      '课程类别',
      info['课程类别'] ?? '专业基础',
      '课程学时',
      info['总 学 时'] ?? '48',
      '学分',
      info['总 学 分'] ?? '2.5'
    ]);
    _kvRow(b, [
      '专业班级',
      className,
      '学生人数',
      studentCount,
      '任课教师',
      teacherName,
      '职称',
      info['职称'] ?? ''
    ]);
    _kvRow(b, [
      '考核类型',
      info['考核方式'] ?? '考查',
      '考核方式',
      '大作业',
      '评价方法',
      '定量评价+定性评价',
      '',
      ''
    ]);
    _mergedHeaderRow(b, '课程支撑毕业要求与课程目标及课程内容的对应关系', 9);
    b.write('<w:tr>');
    _tc(b, '支撑的毕业要求', span: 2, bold: true, fill: 'D9E2F3');
    _tc(b, '课程目标', span: 3, bold: true, fill: 'D9E2F3');
    _tc(b, '考核内容', span: 4, bold: true, fill: 'D9E2F3');
    b.write('</w:tr>');
    for (final o in objectives) {
      final desc = (o['description'] ?? '').toString();
      final indicator = (o['indicator'] ?? '').toString();
      final assess = (o['assess_content'] ?? '').toString();
      b.write('<w:tr>');
      _tc(b, desc, span: 2);
      _tc(b, '支撑毕业要求$indicator', span: 3);
      _tc(b, assess.isNotEmpty ? assess : '课程目标相关考核内容', span: 4);
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
  }

  // ── 表1：考核与评价方式对照表 ───────────────────────────────────
  void _buildAssessmentRefTable(
      StringBuffer b, List<Map<String, dynamic>> objectives) {
    final envLabels = [
      for (final label in ['平时', '实验', '考核'])
        if (_hasEnv(objectives, label)) label
    ];
    b.write(_tblStart(9000));
    b.write('<w:tr>');
    _tc(b, '课程目标', bold: true, fill: 'D9E2F3');
    _tc(b, '权重', bold: true, fill: 'D9E2F3');
    _tc(b, '毕业要求', bold: true, fill: 'D9E2F3');
    for (final label in envLabels) {
      _tc(b, '$label 支撑课程目标的满分（比例%）', bold: true, fill: 'D9E2F3');
    }
    b.write('</w:tr>');
    for (final o in objectives) {
      final idx = (o['objective'] as num?)?.toInt() ?? 0;
      final w = (o['weight'] as num?)?.toDouble() ?? 0;
      final indicator = (o['indicator'] ?? '').toString();
      final fullMark = _objFullMark(o);
      b.write('<w:tr>');
      _tc(b, '课程目标$idx');
      _tc(b, w.toStringAsFixed(2));
      _tc(b, '支撑毕业要求$indicator');
      for (final label in envLabels) {
        _tc(b, _envRatioCell(o, label, fullMark));
      }
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
  }

  String _envRatioCell(
      Map<String, dynamic> objective, String label, double fallbackFullMark) {
    final envs = (objective['envs'] as List?) ?? const [];
    for (final env in envs) {
      final map = env as Map;
      final name = (map['name'] ?? '').toString();
      if (!name.contains(label)) continue;
      final weight = (map['weight'] as num?)?.toDouble() ?? 0;
      if (weight <= 0) return '—';
      final full = (map['full'] as num?)?.toDouble() ?? fallbackFullMark;
      return '${full.toInt()}（${(weight * 100).toStringAsFixed(0)}%）';
    }
    return '—';
  }

  bool _usesEnv(Map<String, dynamic> objective, String label) {
    final envs = (objective['envs'] as List?) ?? const [];
    for (final env in envs) {
      final map = env as Map;
      final name = (map['name'] ?? '').toString();
      final weight = (map['weight'] as num?)?.toDouble() ?? 0;
      if (name.contains(label) && weight > 0) return true;
    }
    return false;
  }

  bool _hasEnv(List<Map<String, dynamic>> objectives, String label) =>
      objectives.any((objective) => _usesEnv(objective, label));

  List<Map<String, dynamic>> _objectivesForEnv(
    List<Map<String, dynamic>> objectives,
    String label,
  ) =>
      objectives.where((objective) => _usesEnv(objective, label)).toList();

  // ── 表2/3：平时/实验评价标准 ────────────────────────────────────
  void _buildStandardTable(
      StringBuffer b, List<Map<String, dynamic>> objectives) {
    b.write(_tblStart(9000));
    b.write('<w:tr>');
    for (final h in [
      '课程目标',
      '观测点',
      '优秀 90-100',
      '良好 70-89',
      '合格 60-69',
      '不合格 0-59',
      '成绩比例（%）'
    ]) {
      _tc(b, h, bold: true, fill: 'D9E2F3');
    }
    b.write('</w:tr>');
    for (final o in objectives) {
      final idx = (o['objective'] as num?)?.toInt() ?? 0;
      final indicator = (o['indicator'] ?? '').toString();
      final fullMark = _objFullMark(o);
      b.write('<w:tr>');
      _tc(b, '课程目标$idx（支撑毕业要求$indicator）');
      _tc(b, (o['description'] ?? '').toString());
      _tc(b, '能够熟练掌握并独立完成相关任务。');
      _tc(b, '能够较好掌握并完成相关任务。');
      _tc(b, '能够基本掌握并完成相关任务。');
      _tc(b, '未能掌握，无法完成相关任务。');
      _tc(b, fullMark.toInt().toString());
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
  }

  // ── 表4：期末考核评价内容 ───────────────────────────────────────
  void _buildExamContentTable(
      StringBuffer b, List<Map<String, dynamic>> objectives) {
    b.write(_tblStart(9000));
    b.write('<w:tr>');
    for (final h in ['基本要求', '评价内容', '比例']) {
      _tc(b, h, bold: true, fill: 'D9E2F3');
    }
    b.write('</w:tr>');
    for (final o in objectives) {
      final idx = (o['objective'] as num?)?.toInt() ?? 0;
      final indicator = (o['indicator'] ?? '').toString();
      final fullMark = _objFullMark(o);
      b.write('<w:tr>');
      _tc(b, '课程目标$idx（支撑毕业要求$indicator）');
      _tc(b, (o['assess_content'] ?? o['description'] ?? '').toString());
      _tc(b, fullMark.toInt().toString());
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
  }

  // ── 表5：课程目标×评价环节 达成度计算（核心，含单元格纵向合并）──
  void _buildAchievementMatrixTable(StringBuffer b,
      List<Map<String, dynamic>> objectives, double expectation) {
    b.write(_tblStart(9500));
    b.write('<w:tr>');
    for (final h in [
      '课程目标i',
      '权重',
      '评价环节j',
      '满分',
      '平均分',
      '达成度',
      '权重',
      '课程目标达成度',
      '指标点',
      '指标点达成度'
    ]) {
      _tc(b, h, bold: true, fill: 'D9E2F3');
    }
    b.write('</w:tr>');

    double totalWeighted = 0;
    for (final o in objectives) {
      final idx = (o['objective'] as num?)?.toInt() ?? 0;
      final w = (o['weight'] as num?)?.toDouble() ?? 0;
      final indicator = (o['indicator'] ?? '').toString();
      final objAch = (o['achievement'] as num?)?.toDouble() ?? 0;
      totalWeighted += objAch * w;
      final envs = (o['envs'] as List?) ?? _defaultEnvs(objAch);
      final n = envs.length;
      for (int j = 0; j < n; j++) {
        final e = envs[j] as Map;
        final full = (e['full'] as num?)?.toDouble() ?? 0;
        final avg = (e['avg'] as num?)?.toDouble() ?? 0;
        final ach = (e['ach'] as num?)?.toDouble() ?? 0;
        final ew = (e['weight'] as num?)?.toDouble() ?? 0;
        b.write('<w:tr>');
        if (j == 0) {
          _tc(b, '目标$idx', vMerge: 'restart');
          _tc(b, w.toStringAsFixed(2), vMerge: 'restart');
        } else {
          _tcMergeCont(b);
          _tcMergeCont(b);
        }
        _tc(b, (e['name'] ?? '').toString());
        _tc(b, full.toStringAsFixed(0));
        _tc(b, avg.toStringAsFixed(2));
        _tc(b, ach.toStringAsFixed(2));
        _tc(b, ew.toStringAsFixed(1));
        if (j == 0) {
          _tc(b, objAch.toStringAsFixed(2), vMerge: 'restart');
          _tc(b, indicator, vMerge: 'restart');
          _tc(b, objAch.toStringAsFixed(2), vMerge: 'restart');
        } else {
          _tcMergeCont(b);
          _tcMergeCont(b);
          _tcMergeCont(b);
        }
        b.write('</w:tr>');
      }
    }
    b.write('<w:tr>');
    _tc(b, '课程总体目标期望值', bold: true);
    _tc(b, expectation.toStringAsFixed(1), span: 5, bold: true);
    _tc(b, '课程总体目标达成度(cc)', bold: true);
    _tc(b, totalWeighted.toStringAsFixed(2), span: 3, bold: true);
    b.write('</w:tr>');
    b.write('</w:tbl>');
  }

  // ── 表6：达成结果分析与持续改进 ─────────────────────────────────
  void _buildAnalysisTable(
    StringBuffer b,
    List<Map<String, dynamic>> objectives,
    Map<String, dynamic> classStats,
    String? analysisText,
    String? qualitativeText,
    String? improvementText,
    String teacherName,
  ) {
    b.write(_tblStart(9000));
    _mergedHeaderRow(b, '四、达成结果分析', 2);

    final analysis = (analysisText?.trim().isNotEmpty ?? false)
        ? analysisText!
        : _defaultAnalysis(objectives, classStats);
    b.write('<w:tr>');
    _tc(b, '课程目标达成情况(定量)', bold: true, fill: 'F2F2F2');
    _tc(b, analysis);
    b.write('</w:tr>');

    final qualitative = (qualitativeText?.trim().isNotEmpty ?? false)
        ? qualitativeText!
        : '本课程采用调查问卷开展定性评价，问卷结果与定量评价结果基本一致，'
            '表明学生自我评价与实际能力达成情况基本相符。';
    b.write('<w:tr>');
    _tc(b, '调查问卷评价情况(定性)', bold: true, fill: 'F2F2F2');
    _tc(b, qualitative);
    b.write('</w:tr>');

    final improvement = (improvementText?.trim().isNotEmpty ?? false)
        ? improvementText!
        : _defaultImprovement(objectives);
    b.write('<w:tr>');
    _tc(b, '达成情况分析及持续改进', bold: true, fill: 'F2F2F2');
    _tc(b, improvement);
    b.write('</w:tr>');

    b.write('<w:tr>');
    _tc(b, '任课教师签字', bold: true, fill: 'F2F2F2');
    _tc(b, '$teacherName　　日期：${DateTime.now().toString().substring(0, 10)}');
    b.write('</w:tr>');

    b.write('<w:tr>');
    _tc(b, '课程群建设工作组意见', bold: true, fill: 'F2F2F2');
    _tc(b, '课程群建设工作组组长签字：　　　　日期：　 年　 月　 日');
    b.write('</w:tr>');
    b.write('</w:tbl>');
  }

  // ───────────────────────── 默认正文 ─────────────────────────

  String _defaultAnalysis(
      List<Map<String, dynamic>> objectives, Map<String, dynamic> classStats) {
    final sb = StringBuffer('1. 定量评价情况分析\n');
    for (final o in objectives) {
      final idx = (o['objective'] as num?)?.toInt() ?? 0;
      final ach = (o['achievement'] as num?)?.toDouble() ?? 0;
      final lvl = _achievementLevel(ach);
      sb.write('课程目标$idx 达成度为 ${ach.toStringAsFixed(3)}（$lvl）。'
          '${ach < 0.6 ? '该目标达成度偏低，需重点加强。' : ach >= 0.85 ? '该目标达成情况优秀。' : '该目标达成情况良好，仍有提升空间。'}\n');
    }
    final cnt = classStats['studentCount'] ?? 0;
    sb.write('参与评价学生 $cnt 人。');
    return sb.toString();
  }

  String _defaultImprovement(List<Map<String, dynamic>> objectives) {
    final weak = objectives
        .where((o) => ((o['achievement'] as num?)?.toDouble() ?? 0) < 0.7)
        .map((o) => '课程目标${(o['objective'] as num?)?.toInt()}')
        .toList();
    final sb = StringBuffer('2. 持续改进措施\n');
    if (weak.isNotEmpty) {
      sb.write('针对达成度偏低的${weak.join('、')}，下一轮教学将增加相关课时与实践环节，'
          '增设阶段性测验并对低分学生进行针对性辅导。\n');
    }
    sb.write('① 优化教学内容与方法，强化实践环节；'
        '② 加强学习过程监控，及时发现并解决问题；'
        '③ 改进考核方式，确保评价全面反映学生能力；'
        '④ 定期开展教学研讨，持续提升教学质量。');
    return sb.toString();
  }

  /// 无分环节数据时，按环节权重回填（达成度同目标达成度）。
  List<Map<String, dynamic>> _defaultEnvs(double objAch) => [
        {
          'name': '平时',
          'full': 20,
          'avg': objAch * 20,
          'ach': objAch,
          'weight': 0.2
        },
        {
          'name': '实验',
          'full': 30,
          'avg': objAch * 30,
          'ach': objAch,
          'weight': 0.3
        },
        {
          'name': '考核',
          'full': 50,
          'avg': objAch * 50,
          'ach': objAch,
          'weight': 0.5
        },
      ];

  double _objFullMark(Map<String, dynamic> o) =>
      (o['full_mark'] as num?)?.toDouble() ??
      (o['fullMark'] as num?)?.toDouble() ??
      ((o['weight'] as num?)?.toDouble() ?? 0) * 100;

  // ───────────────────────── OOXML 基元 ─────────────────────────

  void _title(StringBuffer b, String text) =>
      _para(b, text, align: 'center', bold: true, size: 30);

  void _heading(StringBuffer b, String text) =>
      _para(b, text, bold: true, size: 24);

  void _para(StringBuffer b, String text,
      {String align = 'left', bool bold = false, int size = 21}) {
    final jc = align == 'center' ? '<w:jc w:val="center"/>' : '';
    final parts = text.split('\n');
    for (int i = 0; i < parts.length; i++) {
      b.write('<w:p><w:pPr>$jc</w:pPr><w:r><w:rPr>');
      if (bold) b.write('<w:b/><w:bCs/>');
      b.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>');
      b.write(
          '<w:t xml:space="preserve">${_escape(parts[i])}</w:t></w:r></w:p>');
    }
  }

  void _empty(StringBuffer b) =>
      b.write('<w:p><w:r><w:t xml:space="preserve"> </w:t></w:r></w:p>');

  String _tblStart(int width) {
    const borders = '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '</w:tblBorders>';
    return '<w:tbl><w:tblPr><w:tblW w:w="$width" w:type="dxa"/>$borders</w:tblPr>';
  }

  void _mergedHeaderRow(StringBuffer b, String text, int cols) {
    b.write('<w:tr>');
    _tc(b, text, span: cols, bold: true, fill: 'D9E2F3');
    b.write('</w:tr>');
  }

  void _kvRow(StringBuffer b, List<String> cells) {
    b.write('<w:tr>');
    for (int i = 0; i < cells.length; i++) {
      final isLabel = i.isEven;
      _tc(b, cells[i], bold: isLabel, fill: isLabel ? 'F2F2F2' : null);
    }
    if (cells.length < 9) _tc(b, '');
    b.write('</w:tr>');
  }

  /// 表格单元格。[span] 横向合并列数；[vMerge]='restart' 开始纵向合并。
  void _tc(StringBuffer b, String text,
      {int span = 1, bool bold = false, String? fill, String? vMerge}) {
    b.write('<w:tc><w:tcPr>');
    b.write('<w:tcW w:w="0" w:type="auto"/>');
    if (span > 1) b.write('<w:gridSpan w:val="$span"/>');
    if (vMerge != null) b.write('<w:vMerge w:val="$vMerge"/>');
    if (fill != null) b.write('<w:shd w:fill="$fill" w:val="clear"/>');
    b.write('<w:vAlign w:val="center"/></w:tcPr>');
    b.write('<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr>');
    if (bold) b.write('<w:b/>');
    b.write('<w:sz w:val="18"/></w:rPr>');
    b.write(
        '<w:t xml:space="preserve">${_escape(text)}</w:t></w:r></w:p></w:tc>');
  }

  /// 纵向合并的延续单元格（空内容，继承上方）。
  void _tcMergeCont(StringBuffer b) {
    b.write('<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>'
        '<w:vMerge w:val="continue"/><w:vAlign w:val="center"/></w:tcPr>'
        '<w:p/></w:tc>');
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
