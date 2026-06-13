import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Data used to fill a school-owned achievement Excel template.
///
/// The filler clones the original xlsx package and only rewrites worksheet cell
/// values. Styles, merged cells, formulas, drawings and charts remain owned by
/// the template.
class AchievementExcelTemplatePayload {
  final String courseName;
  final String className;
  final String semester;
  final List<double> objectiveWeights;
  final List<double> objectiveAchievements;
  final List<String> objectiveNames;
  final List<String> indicators;
  final List<Map<String, dynamic>> scores;
  final List<Map<String, dynamic>> pingshi;
  final List<Map<String, dynamic>> experiment;
  final List<Map<String, dynamic>> exam;
  final Map<String, double> pingshiAverage;
  final Map<String, double> experimentAverage;
  final Map<String, double> examAverage;
  final double weightedAchievement;
  final double expectation;

  const AchievementExcelTemplatePayload({
    required this.courseName,
    required this.className,
    required this.semester,
    required this.objectiveWeights,
    required this.objectiveAchievements,
    required this.objectiveNames,
    required this.indicators,
    required this.scores,
    required this.pingshi,
    required this.experiment,
    required this.exam,
    required this.pingshiAverage,
    required this.experimentAverage,
    required this.examAverage,
    required this.weightedAchievement,
    this.expectation = 0.6,
  });
}

/// Coordinates for a concrete achievement workbook template.
///
/// Different courses can provide different profiles. The current default is
/// inferred from the school sample "计科22《移动应用开发》课程达成评价表格48.xlsx".
class AchievementExcelTemplateProfile {
  final String examSheet;
  final String experimentSheet;
  final String pingshiSheet;
  final String individualSheet;
  final String objectiveSheet;
  final String barSheet;
  final List<String> scatterSheets;

  final int componentDataStartRow;
  final int individualDataStartRow;
  final int scatterDataStartRow;
  final int pingshiSummaryRow;
  final int experimentSummaryRow;
  final int examSummaryRow;
  final int individualSummaryRow;
  final int objectiveDataStartRow;
  final int objectiveSummaryRow;
  final int barDataStartRow;

  const AchievementExcelTemplateProfile({
    required this.examSheet,
    required this.experimentSheet,
    required this.pingshiSheet,
    required this.individualSheet,
    required this.objectiveSheet,
    required this.barSheet,
    required this.scatterSheets,
    required this.componentDataStartRow,
    required this.individualDataStartRow,
    required this.scatterDataStartRow,
    required this.pingshiSummaryRow,
    required this.experimentSummaryRow,
    required this.examSummaryRow,
    required this.individualSummaryRow,
    required this.objectiveDataStartRow,
    required this.objectiveSummaryRow,
    required this.barDataStartRow,
  });

  factory AchievementExcelTemplateProfile.schoolMobile48() {
    return const AchievementExcelTemplateProfile(
      examSheet: '期末成绩',
      experimentSheet: '实验成绩',
      pingshiSheet: '平时成绩',
      individualSheet: '学生个体课程目标达成度',
      objectiveSheet: '课程目标点达成度',
      barSheet: '课程目标条形图',
      scatterSheets: [
        '目标1散点趋势图',
        '目标2散点趋势图',
        '目标3散点趋势图',
        '目标4散点趋势图',
      ],
      componentDataStartRow: 6,
      individualDataStartRow: 7,
      scatterDataStartRow: 1,
      pingshiSummaryRow: 55,
      experimentSummaryRow: 55,
      examSummaryRow: 55,
      individualSummaryRow: 56,
      objectiveDataStartRow: 6,
      objectiveSummaryRow: 20,
      barDataStartRow: 7,
    );
  }
}

class AchievementTemplateExcelService {
  static final AchievementTemplateExcelService instance =
      AchievementTemplateExcelService._();
  AchievementTemplateExcelService._();

  /// Finds a course-specific template under data/达成.
  ///
  /// This keeps the export path template-driven: another course can add its own
  /// xlsx whose filename contains the course name and "达成", without changing
  /// the calculation code.
  Future<File?> findTemplateForCourse(String courseName) async {
    final profile = AchievementExcelTemplateProfile.schoolMobile48();
    final roots = <Directory>[
      Directory('data/达成'),
      Directory('${Directory.current.path}/data/达成'),
    ];
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
        if (!name.toLowerCase().endsWith('.xlsx')) continue;
        if (!name.contains('达成')) continue;
        if (courseName.isNotEmpty && !name.contains(courseName)) continue;
        candidates.add(entity);
      }
    }
    final templates = <File>[];
    for (final file in candidates) {
      if (await _isSupportedTemplate(file, profile)) {
        templates.add(file);
      }
    }
    if (templates.isEmpty) return null;
    templates.sort((a, b) {
      final an = a.path.contains('表格') ? 0 : 1;
      final bn = b.path.contains('表格') ? 0 : 1;
      if (an != bn) return an.compareTo(bn);
      return a.path.length.compareTo(b.path.length);
    });
    return templates.first;
  }

  Future<bool> _isSupportedTemplate(
    File file,
    AchievementExcelTemplateProfile profile,
  ) async {
    try {
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final files = <String, List<int>>{};
      for (final f in archive.files) {
        files[f.name] = f.content as List<int>;
      }
      final sheets = _sheetPaths(files).keys.toSet();
      final requiredSheets = <String>{
        profile.examSheet,
        profile.experimentSheet,
        profile.pingshiSheet,
        profile.individualSheet,
        profile.objectiveSheet,
        profile.barSheet,
        ...profile.scatterSheets,
      };
      return sheets.containsAll(requiredSheets);
    } catch (_) {
      return false;
    }
  }

  Uint8List fillTemplate(
    Uint8List templateBytes,
    AchievementExcelTemplatePayload payload, {
    AchievementExcelTemplateProfile? profile,
  }) {
    final activeProfile =
        profile ?? AchievementExcelTemplateProfile.schoolMobile48();
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final files = <String, List<int>>{};
    for (final f in archive.files) {
      files[f.name] = f.content as List<int>;
    }

    final sheetPaths = _sheetPaths(files);
    if (sheetPaths.isEmpty) return templateBytes;

    _fillPingshi(files, sheetPaths, activeProfile, payload);
    _fillExperiment(files, sheetPaths, activeProfile, payload);
    _fillExam(files, sheetPaths, activeProfile, payload);
    _fillIndividual(files, sheetPaths, activeProfile, payload);
    _fillObjective(files, sheetPaths, activeProfile, payload);
    _fillChartData(files, sheetPaths, activeProfile, payload);

    files.remove('xl/calcChain.xml');
    final out = Archive();
    files.forEach((name, content) {
      out.addFile(ArchiveFile(name, content.length, content));
    });
    final encoded = ZipEncoder().encode(out);
    return Uint8List.fromList(encoded ?? templateBytes);
  }

  void _fillPingshi(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
  ) {
    _editSheet(files, sheetPaths, profile.pingshiSheet, (ws) {
      ws.text(1, 0, _title(p, '课程目标达成度计算表（平时）'));
      ws.text(2, 0, '班级：${p.className}');
      ws.text(2, 1, '评价方式:平时');
      _clearRows(ws, profile.componentDataStartRow,
          profile.pingshiSummaryRow - 1, 0, 38);
      for (int i = 0; i < p.pingshi.length; i++) {
        final row = p.pingshi[i];
        final r = profile.componentDataStartRow + i;
        final classActivity = _num(row, 'class_activity_score');
        final quizHomework = _num(row, 'quiz_homework_score');
        final extraLearning = _num(row, 'extra_learning_score');
        ws.text(r, 0, row['student_id']);
        ws.text(r, 1, row['student_name']);
        ws.number(r, 2, classActivity, 1);
        ws.number(r, 13, classActivity, 1);
        ws.number(r, 14, _num(row, 'class_activity_achievement'), 4);
        ws.number(r, 15, quizHomework, 1);
        ws.number(r, 25, quizHomework, 1);
        ws.number(r, 26, _num(row, 'quiz_homework_achievement'), 4);
        ws.number(r, 27, extraLearning, 1);
        ws.number(r, 36, extraLearning, 1);
        ws.number(r, 37, _num(row, 'extra_learning_achievement'), 4);
        ws.number(r, 38, _num(row, 'total_score'), 1);
      }
      final row = profile.pingshiSummaryRow;
      ws.text(row, 0, '课程目标达成度');
      ws.number(row, 1, _avg(p.pingshiAverage, 0), 4);
      ws.number(row, 15, _avg(p.pingshiAverage, 1), 4);
      ws.number(row, 27, _avg(p.pingshiAverage, 3), 4);
      ws.number(row, 38, _averageTotal(p.pingshi, 'total_score') / 100, 4);
    });
  }

  void _fillExperiment(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
  ) {
    _editSheet(files, sheetPaths, profile.experimentSheet, (ws) {
      ws.text(1, 0, _title(p, '课程目标达成度计算表（实验）'));
      ws.text(2, 0, '班级：${p.className}');
      ws.text(2, 1, '评价方式:实验');
      _clearRows(ws, profile.componentDataStartRow,
          profile.experimentSummaryRow - 1, 0, 13);
      for (int i = 0; i < p.experiment.length; i++) {
        final row = p.experiment[i];
        final r = profile.componentDataStartRow + i;
        ws.text(r, 0, row['student_id']);
        ws.text(r, 1, row['student_name']);
        ws.number(r, 2, _num(row, 'exp1_score'), 1);
        ws.number(r, 3, _num(row, 'exp2_score'), 1);
        ws.number(r, 4, _num(row, 'obj1_achievement'), 4);
        ws.number(r, 5, _num(row, 'exp3_score'), 1);
        ws.number(r, 6, _num(row, 'exp4_score'), 1);
        ws.number(r, 7, _num(row, 'obj2_achievement'), 4);
        ws.number(r, 8, _num(row, 'exp5_score'), 1);
        ws.number(r, 9, _num(row, 'exp6_score'), 1);
        ws.number(r, 10, _num(row, 'obj3_achievement'), 4);
        ws.number(r, 11, _experimentTarget4Score(row), 1);
        ws.number(r, 12, _num(row, 'obj4_achievement'), 4);
        ws.number(r, 13, _num(row, 'total_score'), 1);
      }
      final row = profile.experimentSummaryRow;
      ws.text(row, 0, '课程目标达成度');
      ws.number(row, 1, _avg(p.experimentAverage, 0), 4);
      ws.number(row, 5, _avg(p.experimentAverage, 1), 4);
      ws.number(row, 8, _avg(p.experimentAverage, 2), 4);
      ws.number(row, 11, _avg(p.experimentAverage, 3), 4);
      ws.number(row, 13, _averageTotal(p.experiment, 'total_score') / 100, 4);
    });
  }

  void _fillExam(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
  ) {
    _editSheet(files, sheetPaths, profile.examSheet, (ws) {
      ws.text(1, 0, _title(p, '课程目标达成度计算表（期末考核）'));
      ws.text(2, 0, '班级：${p.className}');
      ws.text(2, 1, '评价方式:期末考核（大作业）');
      for (int i = 0; i < math.min(4, p.objectiveWeights.length); i++) {
        ws.text(4, 1 + i * 2, '满分${_fmtInt(_fullMarkFor(p, i))}');
      }
      _clearRows(
          ws, profile.componentDataStartRow, profile.examSummaryRow - 1, 0, 10);
      for (int i = 0; i < p.exam.length; i++) {
        final row = p.exam[i];
        final r = profile.componentDataStartRow + i;
        ws.text(r, 0, row['student_id']);
        ws.text(r, 1, row['student_name']);
        ws.number(r, 2, _num(row, 'project_score'), 1);
        ws.number(r, 3, _num(row, 'obj1_achievement'), 4);
        ws.number(r, 4, _num(row, 'group_score'), 1);
        ws.number(r, 5, _num(row, 'obj2_achievement'), 4);
        ws.number(r, 6, _num(row, 'individual_score'), 1);
        ws.number(r, 7, _num(row, 'obj3_achievement'), 4);
        ws.number(r, 8, _num(row, 'defense_score'), 1);
        ws.number(r, 9, _num(row, 'obj4_achievement'), 4);
        ws.number(r, 10, _num(row, 'total_score'), 1);
      }
      final row = profile.examSummaryRow;
      ws.text(row, 0, '课程目标达成度');
      ws.number(row, 1, _avg(p.examAverage, 0), 4);
      ws.number(row, 4, _avg(p.examAverage, 1), 4);
      ws.number(row, 6, _avg(p.examAverage, 2), 4);
      ws.number(row, 8, _avg(p.examAverage, 3), 4);
      ws.number(row, 10, _averageTotal(p.exam, 'total_score') / 100, 4);
    });
  }

  void _fillIndividual(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
  ) {
    _editSheet(files, sheetPaths, profile.individualSheet, (ws) {
      ws.text(
          1, 0, '${p.semester}${p.className}《${p.courseName}》学生个体课程目标达成度计算表');
      ws.text(2, 0, '班级：${p.className}');
      _clearRows(ws, profile.individualDataStartRow,
          profile.individualSummaryRow - 1, 0, 17);
      final pById = {for (final r in p.pingshi) '${r['student_id']}': r};
      final eById = {for (final r in p.experiment) '${r['student_id']}': r};
      final xById = {for (final r in p.exam) '${r['student_id']}': r};
      for (int i = 0; i < p.scores.length; i++) {
        final s = p.scores[i];
        final sid = '${s['student_id'] ?? ''}';
        final pRow = pById[sid], eRow = eById[sid], xRow = xById[sid];
        final r = profile.individualDataStartRow + i;
        ws.text(r, 0, sid);
        ws.text(r, 1, s['student_name']);
        for (int obj = 0; obj < 4; obj++) {
          final offset = 2 + obj * 4;
          ws.number(r, offset, _pingshiObjective(pRow, obj), 4);
          ws.number(r, offset + 1, _num(eRow, 'obj${obj + 1}_achievement'), 4);
          ws.number(r, offset + 2, _num(xRow, 'obj${obj + 1}_achievement'), 4);
          ws.number(r, offset + 3, _num(s, 'obj${obj + 1}_achievement'), 4);
        }
      }
      final row = profile.individualSummaryRow;
      ws.text(row, 0, '指标点达成度');
      ws.number(row, 1, _achievement(p, 0), 4);
      ws.number(row, 3, _achievement(p, 1), 4);
      ws.number(row, 7, _achievement(p, 2), 4);
      ws.number(row, 11, _achievement(p, 3), 4);
    });
  }

  void _fillObjective(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
  ) {
    _editSheet(files, sheetPaths, profile.objectiveSheet, (ws) {
      ws.text(2, 0, '${p.semester}${p.className}《${p.courseName}》课程目标达成度计算表');
      const envNames = ['平时', '实验', '期末考试'];
      const envWeights = [0.2, 0.3, 0.5];
      const envFull = [20.0, 30.0, 50.0];
      for (int obj = 0; obj < 4; obj++) {
        final envAch = [
          _avg(p.pingshiAverage, obj),
          _avg(p.experimentAverage, obj),
          _avg(p.examAverage, obj),
        ];
        for (int env = 0; env < 3; env++) {
          final row = profile.objectiveDataStartRow + obj * 3 + env;
          if (env == 0) {
            ws.text(row, 0, '目标${obj + 1}');
            ws.number(row, 1, _weight(p, obj), 2);
            ws.number(row, 7, _achievement(p, obj), 4);
            ws.text(row, 8, _indicator(p, obj));
            ws.number(row, 9, _achievement(p, obj), 4);
          } else {
            ws.clear(row, 0);
            ws.clear(row, 1);
            ws.clear(row, 7);
            ws.clear(row, 8);
            ws.clear(row, 9);
          }
          ws.text(row, 2, envNames[env]);
          ws.number(row, 3, envFull[env], 0);
          ws.number(row, 4, envAch[env] * envFull[env], 2);
          ws.number(row, 5, envAch[env], 4);
          ws.number(row, 6, envWeights[env], 1);
        }
      }
      final row = profile.objectiveSummaryRow;
      ws.text(row, 0, '课程总体目标期望值');
      ws.number(row, 1, p.expectation, 1);
      ws.text(row, 2, '课程总体目标达成度(cc)');
      ws.number(row, 6, p.weightedAchievement, 4);
    });
  }

  void _fillChartData(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
  ) {
    _editSheet(files, sheetPaths, profile.barSheet, (ws) {
      for (int i = 0; i < 4; i++) {
        final row = profile.barDataStartRow + i;
        ws.text(row, 1, _objectiveName(p, i));
        ws.number(row, 2, _achievement(p, i), 4);
      }
    });

    for (int obj = 0; obj < math.min(4, profile.scatterSheets.length); obj++) {
      _editSheet(files, sheetPaths, profile.scatterSheets[obj], (ws) {
        _clearRows(ws, profile.scatterDataStartRow,
            profile.scatterDataStartRow + 199, 1, 4);
        for (int i = 0; i < p.scores.length; i++) {
          final row = profile.scatterDataStartRow + i;
          ws.number(row, 1, i + 1, 0);
          ws.number(row, 2, _num(p.scores[i], 'obj${obj + 1}_achievement'), 4);
          ws.number(row, 3, _achievement(p, obj), 4);
          ws.number(row, 4, p.expectation, 1);
        }
      });
    }
  }

  void _editSheet(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    String sheetName,
    void Function(_WorksheetEditor ws) edit,
  ) {
    final path = sheetPaths[sheetName];
    final raw = path == null ? null : files[path];
    if (path == null || raw == null) return;
    final document = XmlDocument.parse(utf8.decode(raw));
    edit(_WorksheetEditor(document));
    files[path] = utf8.encode(document.toXmlString());
  }

  Map<String, String> _sheetPaths(Map<String, List<int>> files) {
    final workbookXml = files['xl/workbook.xml'];
    final relsXml = files['xl/_rels/workbook.xml.rels'];
    if (workbookXml == null || relsXml == null) return const {};
    final workbook = XmlDocument.parse(utf8.decode(workbookXml));
    final rels = XmlDocument.parse(utf8.decode(relsXml));
    final relTargets = <String, String>{};
    for (final rel in rels.findAllElements('Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null) continue;
      relTargets[id] = _normalizeSheetPath(target);
    }
    final out = <String, String>{};
    for (final sheet in workbook.findAllElements('sheet')) {
      final name = sheet.getAttribute('name');
      final rid = sheet.getAttribute('r:id') ??
          sheet.getAttribute('id',
              namespace:
                  'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
      final target = rid == null ? null : relTargets[rid];
      if (name != null && target != null) out[name] = target;
    }
    return out;
  }

  String _normalizeSheetPath(String target) {
    var t = target.replaceAll('\\', '/');
    if (t.startsWith('/')) t = t.substring(1);
    if (!t.startsWith('xl/')) t = 'xl/$t';
    return t.replaceAll('/../', '/');
  }

  static String _title(AchievementExcelTemplatePayload p, String suffix) {
    return '${p.semester}${p.className}《${p.courseName}》$suffix';
  }

  static double _num(Map<String, dynamic>? row, String key) {
    return (row?[key] as num?)?.toDouble() ?? 0;
  }

  static double _avg(Map<String, double> avg, int objective) {
    return avg['obj${objective + 1}'] ?? 0;
  }

  static double _achievement(AchievementExcelTemplatePayload p, int index) {
    if (index < 0 || index >= p.objectiveAchievements.length) return 0;
    return p.objectiveAchievements[index];
  }

  static double _weight(AchievementExcelTemplatePayload p, int index) {
    if (index < 0 || index >= p.objectiveWeights.length) return 0;
    return p.objectiveWeights[index];
  }

  static String _indicator(AchievementExcelTemplatePayload p, int index) {
    if (index < 0 || index >= p.indicators.length) return '';
    return p.indicators[index];
  }

  static String _objectiveName(AchievementExcelTemplatePayload p, int index) {
    if (index < 0 || index >= p.objectiveNames.length) {
      return '课程目标${index + 1}';
    }
    return p.objectiveNames[index];
  }

  static double _fullMarkFor(AchievementExcelTemplatePayload p, int index) {
    final weight = _weight(p, index);
    return weight > 0 ? weight * 100 : [10, 20, 30, 40][index].toDouble();
  }

  static String _fmtInt(num value) => value.round().toString();

  static double _pingshiObjective(Map<String, dynamic>? row, int objective) {
    if (objective == 0) return _num(row, 'class_activity_achievement');
    if (objective == 1) return _num(row, 'quiz_homework_achievement');
    if (objective == 2) return 0;
    return _num(row, 'extra_learning_achievement');
  }

  static double _experimentTarget4Score(Map<String, dynamic>? row) {
    final exp7 = _num(row, 'exp7_score');
    if (exp7 > 0) return exp7;
    final obj4 = _num(row, 'obj4_achievement');
    return obj4 > 0 ? obj4 * 100 : 0;
  }

  static double _averageTotal(List<Map<String, dynamic>> rows, String key) {
    if (rows.isEmpty) return 0;
    var sum = 0.0;
    for (final row in rows) {
      sum += _num(row, key);
    }
    return sum / rows.length;
  }

  static void _clearRows(
    _WorksheetEditor ws,
    int startRow,
    int endRow,
    int startCol,
    int endCol,
  ) {
    if (endRow < startRow) return;
    for (int row = startRow; row <= endRow; row++) {
      for (int col = startCol; col <= endCol; col++) {
        ws.clear(row, col);
      }
    }
  }
}

class _WorksheetEditor {
  final XmlDocument document;
  late final XmlElement sheetData;

  _WorksheetEditor(this.document) {
    sheetData = document.findAllElements('sheetData').first;
  }

  void text(int row, int col, Object? value) {
    final text = value?.toString() ?? '';
    final cell = _cell(row, col);
    cell.removeAttribute('t');
    cell.setAttribute('t', 'inlineStr');
    _removeValueChildren(cell, keepFormula: false);
    cell.children.add(XmlElement(XmlName('is'), [], [
      XmlElement(XmlName('t'), [], [XmlText(text)])
    ]));
    _updateDimension(row, col);
  }

  void number(int row, int col, num value, int digits) {
    final cell = _cell(row, col);
    cell.removeAttribute('t');
    final rounded = double.parse(value.toDouble().toStringAsFixed(digits));
    final text = digits == 0 ? rounded.round().toString() : rounded.toString();
    _removeValueChildren(cell, keepFormula: true);
    cell.children.add(XmlElement(XmlName('v'), [], [XmlText(text)]));
    _updateDimension(row, col);
  }

  void clear(int row, int col) {
    final cell = _findCell(row, col);
    if (cell == null) return;
    cell.removeAttribute('t');
    _removeValueChildren(cell, keepFormula: false);
  }

  XmlElement _cell(int row, int col) {
    final existing = _findCell(row, col);
    if (existing != null) return existing;
    final rowEl = _row(row);
    final ref = _cellRef(row, col);
    final cell =
        XmlElement(XmlName('c'), [XmlAttribute(XmlName('r'), ref)], []);
    final cells = rowEl.findElements('c').toList();
    var inserted = false;
    for (final current in cells) {
      if (_columnIndex(current.getAttribute('r') ?? '') > col) {
        final index = rowEl.children.indexOf(current);
        rowEl.children.insert(index, cell);
        inserted = true;
        break;
      }
    }
    if (!inserted) rowEl.children.add(cell);
    return cell;
  }

  XmlElement _row(int row) {
    for (final rowEl in sheetData.findElements('row')) {
      final r = int.tryParse(rowEl.getAttribute('r') ?? '');
      if (r == row) return rowEl;
    }
    final created = XmlElement(
      XmlName('row'),
      [XmlAttribute(XmlName('r'), row.toString())],
      [],
    );
    final rows = sheetData.findElements('row').toList();
    var inserted = false;
    for (final current in rows) {
      final r = int.tryParse(current.getAttribute('r') ?? '') ?? 0;
      if (r > row) {
        final index = sheetData.children.indexOf(current);
        sheetData.children.insert(index, created);
        inserted = true;
        break;
      }
    }
    if (!inserted) sheetData.children.add(created);
    return created;
  }

  XmlElement? _findCell(int row, int col) {
    final ref = _cellRef(row, col);
    for (final rowEl in sheetData.findElements('row')) {
      if (rowEl.getAttribute('r') != row.toString()) continue;
      for (final cell in rowEl.findElements('c')) {
        if (cell.getAttribute('r') == ref) return cell;
      }
    }
    return null;
  }

  void _removeValueChildren(XmlElement cell, {required bool keepFormula}) {
    cell.children.removeWhere((node) {
      if (node is! XmlElement) return false;
      final name = node.name.local;
      if (keepFormula && name == 'f') return false;
      return name == 'v' || name == 'is' || name == 'f';
    });
  }

  void _updateDimension(int row, int col) {
    final dimensions = document.findAllElements('dimension');
    if (dimensions.isEmpty) return;
    final dimension = dimensions.first;
    final ref = dimension.getAttribute('ref') ?? 'A1:A1';
    final parts = ref.split(':');
    final first = parts.first;
    final last = parts.length > 1 ? parts.last : parts.first;
    final maxRow = math.max(_rowIndex(last), row);
    final maxCol = math.max(_columnIndex(last), col);
    dimension.setAttribute('ref', '$first:${_columnName(maxCol)}$maxRow');
  }

  static String _cellRef(int row, int col) => '${_columnName(col)}$row';

  static int _rowIndex(String ref) {
    final m = RegExp(r'(\d+)').firstMatch(ref);
    return m == null ? 1 : int.parse(m.group(1)!);
  }

  static int _columnIndex(String ref) {
    final m = RegExp(r'^([A-Z]+)').firstMatch(ref);
    if (m == null) return -1;
    var n = 0;
    for (final code in m.group(1)!.codeUnits) {
      n = n * 26 + code - 64;
    }
    return n - 1;
  }

  static String _columnName(int index) {
    var n = index + 1;
    final chars = <String>[];
    while (n > 0) {
      n--;
      chars.insert(0, String.fromCharCode(65 + n % 26));
      n ~/= 26;
    }
    return chars.join();
  }
}
