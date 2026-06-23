import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../core/error_handler.dart';
import 'achievement_template_assets.dart';

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
      pingshiSummaryRow: 54,
      experimentSummaryRow: 54,
      examSummaryRow: 54,
      individualSummaryRow: 56,
      objectiveDataStartRow: 8,
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
      };
      final hasBaseSheets = sheets.containsAll(requiredSheets);
      final hasBarSheet =
          _barSheetNames(profile).any((name) => sheets.contains(name));
      final hasScatterSheets = List<bool>.generate(
        math.min(4, profile.scatterSheets.length),
        (i) =>
            _scatterSheetNames(profile, i).any((name) => sheets.contains(name)),
      ).every((present) => present);
      return hasBaseSheets && hasBarSheet && hasScatterSheets;
    } catch (e) {
      swallow(e, tag: 'AchievementTemplateExcelService._isSupportedTemplate');
      return false;
    }
  }

  Uint8List fillTemplate(
    Uint8List templateBytes,
    AchievementExcelTemplatePayload payload, {
    AchievementExcelTemplateProfile? profile,
    int? studentCount,
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

    // 动态汇总行：紧跟在最后一行学生数据之后
    final count = math.max(
      0,
      studentCount ??
          [
            payload.scores.length,
            payload.pingshi.length,
            payload.experiment.length,
            payload.exam.length,
          ].reduce(math.max),
    );
    final dynamicProfile = AchievementExcelTemplateProfile(
      examSheet: activeProfile.examSheet,
      experimentSheet: activeProfile.experimentSheet,
      pingshiSheet: activeProfile.pingshiSheet,
      individualSheet: activeProfile.individualSheet,
      objectiveSheet: activeProfile.objectiveSheet,
      barSheet: activeProfile.barSheet,
      scatterSheets: activeProfile.scatterSheets,
      componentDataStartRow: activeProfile.componentDataStartRow,
      individualDataStartRow: activeProfile.individualDataStartRow,
      scatterDataStartRow: activeProfile.scatterDataStartRow,
      pingshiSummaryRow: activeProfile.componentDataStartRow + count,
      experimentSummaryRow: activeProfile.componentDataStartRow + count,
      examSummaryRow: activeProfile.componentDataStartRow + count,
      individualSummaryRow: activeProfile.individualDataStartRow + count + 1,
      objectiveDataStartRow: activeProfile.objectiveDataStartRow,
      objectiveSummaryRow: activeProfile.objectiveSummaryRow,
      barDataStartRow: activeProfile.barDataStartRow,
    );

    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.pingshiSheet],
      dataStartRow: activeProfile.componentDataStartRow,
      templateSummaryStartRow: activeProfile.pingshiSummaryRow,
      summaryRowCount: 2,
      targetDataRows: count,
      maxCol: 38,
    );
    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.experimentSheet],
      dataStartRow: activeProfile.componentDataStartRow,
      templateSummaryStartRow: activeProfile.experimentSummaryRow,
      summaryRowCount: 2,
      targetDataRows: count,
      maxCol: 13,
    );
    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.examSheet],
      dataStartRow: activeProfile.componentDataStartRow,
      templateSummaryStartRow: activeProfile.examSummaryRow,
      summaryRowCount: 2,
      targetDataRows: count,
      maxCol: 10,
    );
    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.individualSheet],
      dataStartRow: activeProfile.individualDataStartRow,
      templateSummaryStartRow: activeProfile.individualSummaryRow - 1,
      summaryRowCount: 2,
      targetDataRows: count,
      maxCol: 17,
    );

    _fillPingshi(files, sheetPaths, dynamicProfile, payload);
    _fillExperiment(files, sheetPaths, dynamicProfile, payload);
    _fillExam(files, sheetPaths, dynamicProfile, payload);
    _fillIndividual(files, sheetPaths, dynamicProfile, payload);
    _fillObjective(files, sheetPaths, dynamicProfile, payload);
    _fillChartData(files, sheetPaths, dynamicProfile, payload);
    _updateTemplateCharts(files, sheetPaths, dynamicProfile, payload, count);

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
      final start = profile.componentDataStartRow;
      final avgRow = profile.pingshiSummaryRow; // 倒数第二行：班平均值
      final achRow = avgRow + 1; // 倒数第一行：课程目标达成度
      final rows = _rowsInScoreOrder(p.scores, p.pingshi);
      _clearRows(ws, start, math.max(start, avgRow - 1), 0, 38);
      _clearRows(ws, avgRow, achRow, 0, 38);
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final r = start + i;
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
      // 倒数第二行：班平均值（三项原始平均分 + 各达成度均值 + 总评均值）
      ws.text(avgRow, 0, '班平均值');
      ws.number(avgRow, 2, _avgF(rows, 'class_activity_score'), 1);
      ws.number(avgRow, 13, _avgF(rows, 'class_activity_score'), 1);
      ws.number(avgRow, 14, _avgF(rows, 'class_activity_achievement'), 4);
      ws.number(avgRow, 15, _avgF(rows, 'quiz_homework_score'), 1);
      ws.number(avgRow, 25, _avgF(rows, 'quiz_homework_score'), 1);
      ws.number(avgRow, 26, _avgF(rows, 'quiz_homework_achievement'), 4);
      ws.number(avgRow, 27, _avgF(rows, 'extra_learning_score'), 1);
      ws.number(avgRow, 36, _avgF(rows, 'extra_learning_score'), 1);
      ws.number(avgRow, 37, _avgF(rows, 'extra_learning_achievement'), 4);
      ws.number(avgRow, 38, _avgF(rows, 'total_score'), 1);
      // 倒数第一行：课程目标达成度（仅达成度列 O/AA/AL/AM = 14/26/37/38）
      ws.text(achRow, 0, '课程目标达成度');
      ws.number(achRow, 14, _avg(p.pingshiAverage, 0), 4);
      ws.number(achRow, 26, _avg(p.pingshiAverage, 1), 4);
      ws.number(achRow, 37, _avg(p.pingshiAverage, 3), 4);
      ws.number(achRow, 38, _averageTotal(rows, 'total_score') / 100, 4);
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
      final start = profile.componentDataStartRow;
      final avgRow = profile.experimentSummaryRow; // 倒数第二行：班平均值
      final achRow = avgRow + 1; // 倒数第一行：课程目标达成度
      final rows = _rowsInScoreOrder(p.scores, p.experiment);
      _clearRows(ws, start, math.max(start, avgRow - 1), 0, 13);
      _clearRows(ws, avgRow, achRow, 0, 13);
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final r = start + i;
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
        // 实验七已删除：L 列(11)留空，目标4 达成度仍取 obj4_achievement
        ws.clear(r, 11);
        ws.number(r, 12, _num(row, 'obj4_achievement'), 4);
        ws.number(r, 13, _num(row, 'total_score'), 1);
      }
      // 倒数第二行：班平均值（各列均值，实验七 L 列留空）
      ws.text(avgRow, 0, '班平均值');
      ws.number(avgRow, 2, _avgF(rows, 'exp1_score'), 1);
      ws.number(avgRow, 3, _avgF(rows, 'exp2_score'), 1);
      ws.number(avgRow, 4, _avgF(rows, 'obj1_achievement'), 4);
      ws.number(avgRow, 5, _avgF(rows, 'exp3_score'), 1);
      ws.number(avgRow, 6, _avgF(rows, 'exp4_score'), 1);
      ws.number(avgRow, 7, _avgF(rows, 'obj2_achievement'), 4);
      ws.number(avgRow, 8, _avgF(rows, 'exp5_score'), 1);
      ws.number(avgRow, 9, _avgF(rows, 'exp6_score'), 1);
      ws.number(avgRow, 10, _avgF(rows, 'obj3_achievement'), 4);
      ws.clear(avgRow, 11);
      ws.number(avgRow, 12, _avgF(rows, 'obj4_achievement'), 4);
      ws.number(avgRow, 13, _avgF(rows, 'total_score'), 1);
      // 倒数第一行：课程目标达成度（E/H/K/M/N = 4/7/10/12/13）
      ws.text(achRow, 0, '课程目标达成度');
      ws.number(achRow, 4, _avg(p.experimentAverage, 0), 4);
      ws.number(achRow, 7, _avg(p.experimentAverage, 1), 4);
      ws.number(achRow, 10, _avg(p.experimentAverage, 2), 4);
      ws.number(achRow, 12, _avg(p.experimentAverage, 3), 4);
      ws.number(achRow, 13, _averageTotal(rows, 'total_score') / 100, 4);
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
      final start = profile.componentDataStartRow;
      final avgRow = profile.examSummaryRow; // 倒数第二行：班平均值
      final achRow = avgRow + 1; // 倒数第一行：课程目标达成度
      final rows = _rowsInScoreOrder(p.scores, p.exam);
      _clearRows(ws, start, math.max(start, avgRow - 1), 0, 10);
      _clearRows(ws, avgRow, achRow, 0, 10);
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final r = start + i;
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
      // 倒数第二行：班平均值（各列均值）
      ws.text(avgRow, 0, '班平均值');
      ws.number(avgRow, 2, _avgF(rows, 'project_score'), 1);
      ws.number(avgRow, 3, _avgF(rows, 'obj1_achievement'), 4);
      ws.number(avgRow, 4, _avgF(rows, 'group_score'), 1);
      ws.number(avgRow, 5, _avgF(rows, 'obj2_achievement'), 4);
      ws.number(avgRow, 6, _avgF(rows, 'individual_score'), 1);
      ws.number(avgRow, 7, _avgF(rows, 'obj3_achievement'), 4);
      ws.number(avgRow, 8, _avgF(rows, 'defense_score'), 1);
      ws.number(avgRow, 9, _avgF(rows, 'obj4_achievement'), 4);
      ws.number(avgRow, 10, _avgF(rows, 'total_score'), 1);
      // 倒数第一行：课程目标达成度（D/F/H/J/K = 3/5/7/9/10）
      ws.text(achRow, 0, '课程目标达成度');
      ws.number(achRow, 3, _avg(p.examAverage, 0), 4);
      ws.number(achRow, 5, _avg(p.examAverage, 1), 4);
      ws.number(achRow, 7, _avg(p.examAverage, 2), 4);
      ws.number(achRow, 9, _avg(p.examAverage, 3), 4);
      ws.number(achRow, 10, _averageTotal(rows, 'total_score') / 100, 4);
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
      final avgRow = profile.individualSummaryRow - 1;
      final indicatorRow = profile.individualSummaryRow;
      _clearRows(ws, profile.individualDataStartRow,
          math.max(profile.individualDataStartRow, avgRow - 1), 0, 17);
      _clearRows(ws, avgRow, indicatorRow, 0, 17);
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
      ws.text(avgRow, 0, '班平均值');
      for (int obj = 0; obj < 4; obj++) {
        final offset = 2 + obj * 4;
        ws.number(avgRow, offset, _avg(p.pingshiAverage, obj), 4);
        ws.number(avgRow, offset + 1, _avg(p.experimentAverage, obj), 4);
        ws.number(avgRow, offset + 2, _avg(p.examAverage, obj), 4);
        ws.number(avgRow, offset + 3, _achievement(p, obj), 4);
      }
      ws.text(indicatorRow, 0, '指标点达成度');
      ws.number(indicatorRow, 2, _achievement(p, 0), 4);
      ws.number(indicatorRow, 6, _achievement(p, 1), 4);
      ws.number(indicatorRow, 10, _achievement(p, 2), 4);
      ws.number(indicatorRow, 14, _achievement(p, 3), 4);
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
            ws.numberPlain(row, 1, _weight(p, obj), 2);
            ws.numberPlain(row, 7, _achievement(p, obj), 4);
            ws.text(row, 8, _indicator(p, obj));
            ws.numberPlain(row, 9, _achievement(p, obj), 4);
          } else {
            ws.clear(row, 0);
            ws.clear(row, 1);
            ws.clear(row, 7);
            ws.clear(row, 8);
            ws.clear(row, 9);
          }
          ws.text(row, 2, envNames[env]);
          ws.numberPlain(row, 3, envFull[env], 0);
          ws.numberPlain(row, 4, envAch[env] * envFull[env], 2);
          ws.numberPlain(row, 5, envAch[env], 4);
          ws.numberPlain(row, 6, envWeights[env], 1);
        }
      }
      final row = profile.objectiveSummaryRow;
      ws.text(row, 0, '课程总体目标期望值');
      ws.numberPlain(row, 1, p.expectation, 1);
      ws.text(row, 2, '课程总体目标达成度(cc)');
      ws.numberPlain(row, 6, p.weightedAchievement, 4);
    });
  }

  void _fillChartData(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
  ) {
    _editFirstSheet(files, sheetPaths, _barSheetNames(profile), (ws) {
      for (int i = 0; i < 4; i++) {
        final row = profile.barDataStartRow + i;
        ws.text(row, 1, _objectiveName(p, i));
        ws.number(row, 2, _achievement(p, i), 4);
      }
    });

    for (int obj = 0; obj < math.min(4, profile.scatterSheets.length); obj++) {
      _editFirstSheet(files, sheetPaths, _scatterSheetNames(profile, obj),
          (ws) {
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

  void _resizeSheetDataRegion(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    Iterable<String> sheetNames, {
    required int dataStartRow,
    required int templateSummaryStartRow,
    required int summaryRowCount,
    required int targetDataRows,
    required int maxCol,
  }) {
    _editFirstSheet(files, sheetPaths, sheetNames, (ws) {
      ws.resizeDataRegion(
        dataStartRow: dataStartRow,
        templateSummaryStartRow: templateSummaryStartRow,
        summaryRowCount: summaryRowCount,
        targetDataRows: targetDataRows,
        maxCol: maxCol,
      );
    });
  }

  void _updateTemplateCharts(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    AchievementExcelTemplateProfile profile,
    AchievementExcelTemplatePayload p,
    int studentCount,
  ) {
    final barSheet =
        _firstExistingSheetName(sheetPaths, _barSheetNames(profile));
    if (barSheet != null) {
      final chartRefs = _chartRefsForSheet(files, sheetPaths[barSheet]!);
      for (final chart in chartRefs) {
        _updateBarChart(
          files,
          chart,
          sheetName: barSheet,
          startRow: profile.barDataStartRow,
          endRow: profile.barDataStartRow + 3,
        );
      }
    }

    final endRow = math.max(1, studentCount);
    for (var obj = 0; obj < math.min(4, profile.scatterSheets.length); obj++) {
      final sheetName =
          _firstExistingSheetName(sheetPaths, _scatterSheetNames(profile, obj));
      if (sheetName == null) continue;
      final chartRefs = _chartRefsForSheet(files, sheetPaths[sheetName]!);
      for (final chart in chartRefs) {
        _setDrawingAnchor(
          files,
          chart.drawingPath,
          fromCol: 7,
          fromRow: 1,
          toCol: 22,
          toRow: 27,
        );
        _updateScatterChart(
          files,
          chart,
          sheetName: sheetName,
          objectiveIndex: obj,
          endRow: endRow,
          average: _achievement(p, obj),
          expectation: p.expectation,
        );
      }
    }
  }

  void _updateBarChart(
    Map<String, List<int>> files,
    _ChartRef chart, {
    required String sheetName,
    required int startRow,
    required int endRow,
  }) {
    final raw = files[chart.chartPath];
    if (raw == null) return;
    final doc = XmlDocument.parse(utf8.decode(raw));
    if (doc.findAllElements('barChart', namespace: '*').isEmpty) return;
    final series = doc.findAllElements('ser', namespace: '*').toList();
    if (series.isNotEmpty) {
      _setSeriesName(series.first, '达成度');
      _setSeriesRefs(series.first, [
        _chartRef(sheetName, 'B', startRow, endRow),
        _chartRef(sheetName, 'C', startRow, endRow),
      ]);
      _ensureBarDataLabels(series.first);
    }
    files[chart.chartPath] = utf8.encode(doc.toXmlString());
  }

  void _updateScatterChart(
    Map<String, List<int>> files,
    _ChartRef chart, {
    required String sheetName,
    required int objectiveIndex,
    required int endRow,
    required double average,
    required double expectation,
  }) {
    final raw = files[chart.chartPath];
    if (raw == null) return;
    final doc = XmlDocument.parse(utf8.decode(raw));
    if (doc.findAllElements('scatterChart', namespace: '*').isEmpty) return;
    final series = doc.findAllElements('ser', namespace: '*').toList();
    if (series.length >= 3) {
      _setSeriesName(series[0], '${average.toStringAsFixed(2)}平均');
      _setSeriesRefs(series[0], [
        _chartRef(sheetName, 'B', 1, endRow),
        _chartRef(sheetName, 'D', 1, endRow),
      ]);
      _setSeriesName(series[1], '${expectation.toStringAsFixed(2)}期望');
      _setSeriesRefs(series[1], [
        _chartRef(sheetName, 'B', 1, endRow),
        _chartRef(sheetName, 'E', 1, endRow),
      ]);
      _setSeriesName(series[2], '个体达成度');
      _setSeriesRefs(series[2], [
        _chartRef(sheetName, 'B', 1, endRow),
        _chartRef(sheetName, 'C', 1, endRow),
      ]);
    }
    for (final ser in series) {
      ser.children.removeWhere(
          (node) => node is XmlElement && node.name.local == 'trendline');
    }
    _ensureBottomLegend(doc);
    files[chart.chartPath] = utf8.encode(doc.toXmlString());
  }

  List<_ChartRef> _chartRefsForSheet(
    Map<String, List<int>> files,
    String sheetPath,
  ) {
    final raw = files[sheetPath];
    if (raw == null) return const [];
    final sheet = XmlDocument.parse(utf8.decode(raw));
    final sheetRelsPath = _relsPathForPart(sheetPath);
    final sheetRels = _relationships(files, sheetRelsPath);
    final charts = <_ChartRef>[];
    for (final drawing in sheet.findAllElements('drawing')) {
      final rid = _relationshipId(drawing);
      final drawingTarget = rid == null ? null : sheetRels[rid];
      if (drawingTarget == null) continue;
      final drawingPath = _resolvePartPath(sheetPath, drawingTarget);
      final drawingRaw = files[drawingPath];
      if (drawingRaw == null) continue;
      final drawingDoc = XmlDocument.parse(utf8.decode(drawingRaw));
      final drawingRels = _relationships(files, _relsPathForPart(drawingPath));
      for (final chartEl
          in drawingDoc.findAllElements('chart', namespace: '*')) {
        final chartRid = _relationshipId(chartEl);
        final chartTarget = chartRid == null ? null : drawingRels[chartRid];
        if (chartTarget == null) continue;
        final chartPath = _resolvePartPath(drawingPath, chartTarget);
        if (files.containsKey(chartPath)) {
          charts.add(_ChartRef(drawingPath: drawingPath, chartPath: chartPath));
        }
      }
    }
    return charts;
  }

  Map<String, String> _relationships(
    Map<String, List<int>> files,
    String relsPath,
  ) {
    final raw = files[relsPath];
    if (raw == null) return const {};
    final doc = XmlDocument.parse(utf8.decode(raw));
    return {
      for (final rel in doc.findAllElements('Relationship'))
        if (rel.getAttribute('Id') != null &&
            rel.getAttribute('Target') != null)
          rel.getAttribute('Id')!: rel.getAttribute('Target')!,
    };
  }

  void _setDrawingAnchor(
    Map<String, List<int>> files,
    String drawingPath, {
    required int fromCol,
    required int fromRow,
    required int toCol,
    required int toRow,
  }) {
    final raw = files[drawingPath];
    if (raw == null) return;
    final doc = XmlDocument.parse(utf8.decode(raw));
    for (final anchor in doc.findAllElements('twoCellAnchor', namespace: '*')) {
      final from = _firstChild(anchor, 'from');
      final to = _firstChild(anchor, 'to');
      if (from == null || to == null) continue;
      _setChildText(from, 'col', fromCol.toString());
      _setChildText(from, 'row', fromRow.toString());
      _setChildText(to, 'col', toCol.toString());
      _setChildText(to, 'row', toRow.toString());
    }
    files[drawingPath] = utf8.encode(doc.toXmlString());
  }

  void _editFirstSheet(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    Iterable<String> sheetNames,
    void Function(_WorksheetEditor ws) edit,
  ) {
    final sheetName = _firstExistingSheetName(sheetPaths, sheetNames);
    if (sheetName == null) return;
    _editSheet(files, sheetPaths, sheetName, edit);
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

  static List<String> _barSheetNames(AchievementExcelTemplateProfile profile) {
    return [profile.barSheet, 'Sheet1'];
  }

  static List<String> _scatterSheetNames(
    AchievementExcelTemplateProfile profile,
    int index,
  ) {
    return [
      if (index >= 0 && index < profile.scatterSheets.length)
        profile.scatterSheets[index],
      'Sheet2(${index + 1})',
    ];
  }

  static String? _firstExistingSheetName(
    Map<String, String> sheetPaths,
    Iterable<String> names,
  ) {
    for (final name in names) {
      if (sheetPaths.containsKey(name)) return name;
    }
    return null;
  }

  static String? _relationshipId(XmlElement element) {
    for (final attribute in element.attributes) {
      final name = attribute.name;
      if (name.qualified == 'r:id' ||
          (name.prefix == 'r' && name.local == 'id') ||
          name.local == 'id') {
        return attribute.value;
      }
    }
    return null;
  }

  static String _chartRef(
    String sheetName,
    String col,
    int startRow,
    int endRow,
  ) {
    final safeName = sheetName.replaceAll("'", "''");
    return "'$safeName'!\$$col\$$startRow:\$$col\$$endRow";
  }

  static String _relsPathForPart(String partPath) {
    final slash = partPath.lastIndexOf('/');
    if (slash < 0) return '_rels/$partPath.rels';
    return '${partPath.substring(0, slash)}/_rels/${partPath.substring(slash + 1)}.rels';
  }

  static String _resolvePartPath(String basePart, String target) {
    var t = target.replaceAll('\\', '/');
    if (t.startsWith('/')) return t.substring(1);
    final slash = basePart.lastIndexOf('/');
    final baseDir = slash < 0 ? '' : basePart.substring(0, slash);
    final parts = <String>[];
    for (final part in '$baseDir/$t'.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  static void _setSeriesName(XmlElement series, String name) {
    var tx = _firstChild(series, 'tx');
    if (tx == null) {
      tx = _c('tx');
      series.children.insert(math.min(2, series.children.length), tx);
    }
    tx.children.clear();
    tx.children.add(_c('v', children: [XmlText(name)]));
  }

  static void _setSeriesRefs(XmlElement series, List<String> refs) {
    final formulas = series.findAllElements('f', namespace: '*').toList();
    for (var i = 0; i < math.min(refs.length, formulas.length); i++) {
      _setElementText(formulas[i], refs[i]);
    }
  }

  static void _ensureBarDataLabels(XmlElement series) {
    series.children.removeWhere(
        (node) => node is XmlElement && node.name.local == 'dLbls');
    final labels = _c('dLbls', children: [
      _c('numFmt', attributes: [
        XmlAttribute(XmlName('formatCode'), '0.00'),
        XmlAttribute(XmlName('sourceLinked'), '0'),
      ]),
      _c('dLblPos', attributes: [XmlAttribute(XmlName('val'), 'outEnd')]),
      _c('showLegendKey', attributes: [XmlAttribute(XmlName('val'), '0')]),
      _c('showVal', attributes: [XmlAttribute(XmlName('val'), '1')]),
      _c('showCatName', attributes: [XmlAttribute(XmlName('val'), '0')]),
      _c('showSerName', attributes: [XmlAttribute(XmlName('val'), '0')]),
      _c('showPercent', attributes: [XmlAttribute(XmlName('val'), '0')]),
      _c('showBubbleSize', attributes: [XmlAttribute(XmlName('val'), '0')]),
    ]);
    final cat = _firstChild(series, 'cat');
    final index =
        cat == null ? series.children.length : series.children.indexOf(cat);
    series.children.insert(index, labels);
  }

  static void _ensureBottomLegend(XmlDocument doc) {
    final charts = doc.findAllElements('chart', namespace: '*').toList();
    if (charts.isEmpty) return;
    final chart = charts.first;
    var legend = _firstChild(chart, 'legend');
    if (legend == null) {
      legend = _c('legend', children: [
        _c('legendPos', attributes: [XmlAttribute(XmlName('val'), 'b')]),
        _c('overlay', attributes: [XmlAttribute(XmlName('val'), '0')]),
      ]);
      final plotVisOnly = _firstChild(chart, 'plotVisOnly');
      final index = plotVisOnly == null
          ? chart.children.length
          : chart.children.indexOf(plotVisOnly);
      chart.children.insert(index, legend);
      return;
    }
    _upsertValChild(legend, 'legendPos', 'b');
    _upsertValChild(legend, 'overlay', '0');
  }

  static void _upsertValChild(XmlElement parent, String localName, String val) {
    var child = _firstChild(parent, localName);
    if (child == null) {
      child = _c(localName);
      parent.children.add(child);
    }
    child.setAttribute('val', val);
  }

  static XmlElement? _firstChild(XmlElement parent, String localName) {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == localName) return child;
    }
    return null;
  }

  static void _setChildText(
    XmlElement parent,
    String localName,
    String value,
  ) {
    final child = _firstChild(parent, localName);
    if (child == null) return;
    _setElementText(child, value);
  }

  static void _setElementText(XmlElement element, String value) {
    element.children.clear();
    element.children.add(XmlText(value));
  }

  static XmlElement _c(
    String localName, {
    List<XmlAttribute> attributes = const [],
    List<XmlNode> children = const [],
  }) {
    return XmlElement(XmlName(localName, 'c'), attributes, children);
  }

  static String _title(AchievementExcelTemplatePayload p, String suffix) {
    return '${p.semester}${p.className}《${p.courseName}》$suffix';
  }

  static List<Map<String, dynamic>> _rowsInScoreOrder(
    List<Map<String, dynamic>> scores,
    List<Map<String, dynamic>> rows,
  ) {
    if (scores.isEmpty) return rows;
    final byId = {for (final r in rows) '${r['student_id']}': r};
    final used = <String>{};
    final ordered = <Map<String, dynamic>>[];
    for (final score in scores) {
      final sid = '${score['student_id'] ?? score['user_id'] ?? ''}';
      if (sid.isEmpty) continue;
      used.add(sid);
      ordered.add(Map<String, dynamic>.from(byId[sid] ??
          {
            'student_id': sid,
            'student_name': score['student_name'] ?? score['real_name'] ?? '',
          }));
    }
    for (final row in rows) {
      final sid = '${row['student_id'] ?? ''}';
      if (sid.isNotEmpty && used.add(sid)) {
        ordered.add(Map<String, dynamic>.from(row));
      }
    }
    return ordered;
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

  /// 某字段在全班学生上的平均值（班平均值行用）。
  static double _avgF(List<Map<String, dynamic>> rows, String key) {
    if (rows.isEmpty) return 0;
    var sum = 0.0;
    for (final row in rows) {
      sum += _num(row, key);
    }
    return sum / rows.length;
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

  void resizeDataRegion({
    required int dataStartRow,
    required int templateSummaryStartRow,
    required int summaryRowCount,
    required int targetDataRows,
    required int maxCol,
  }) {
    final normalizedTargetRows = math.max(0, targetDataRows);
    final targetSummaryStartRow = dataStartRow + normalizedTargetRows;
    final delta = targetSummaryStartRow - templateSummaryStartRow;
    if (delta == 0) {
      _ensureDataRows(dataStartRow, normalizedTargetRows, maxCol);
      return;
    }

    final cloneSource =
        (_findRow(templateSummaryStartRow - 1) ?? _findRow(dataStartRow))
            ?.copy();
    if (delta < 0) {
      final deleteStart = targetSummaryStartRow;
      final deleteEnd = templateSummaryStartRow - 1;
      sheetData.children.removeWhere((node) {
        if (node is! XmlElement || node.name.local != 'row') return false;
        final row = int.tryParse(node.getAttribute('r') ?? '') ?? 0;
        return row >= deleteStart && row <= deleteEnd;
      });
      _shiftRows(templateSummaryStartRow, delta);
      _shiftMergeCells(templateSummaryStartRow, delta,
          deleteStart: deleteStart, deleteEnd: deleteEnd);
    } else {
      _shiftRows(templateSummaryStartRow, delta);
      _shiftMergeCells(templateSummaryStartRow, delta);
      if (cloneSource != null) {
        for (var row = templateSummaryStartRow;
            row < targetSummaryStartRow;
            row++) {
          final created = cloneSource.copy();
          _setRowNumber(created, row);
          _clearRowValues(created);
          _insertRowElement(created);
        }
      }
    }

    _ensureDataRows(dataStartRow, normalizedTargetRows, maxCol);
    _refreshDimension();
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
    _removeValueChildren(cell, keepFormula: false);
    cell.children.add(XmlElement(XmlName('v'), [], [XmlText(text)]));
    _updateDimension(row, col);
  }

  /// 写入静态数值并剥离单元格原有公式。
  /// 用于「课程目标点达成度」等汇总表：模板里这些格是跨表公式
  /// （如 ='平时成绩'!O54），学生人数变化后汇总行移位，公式指向空行会重算成
  /// 空白，覆盖我们写入的值。改写为静态值后所见即所得，不再依赖重算。
  void numberPlain(int row, int col, num value, int digits) {
    final cell = _cell(row, col);
    cell.removeAttribute('t');
    final rounded = double.parse(value.toDouble().toStringAsFixed(digits));
    final text = digits == 0 ? rounded.round().toString() : rounded.toString();
    _removeValueChildren(cell, keepFormula: false);
    cell.children.add(XmlElement(XmlName('v'), [], [XmlText(text)]));
    _updateDimension(row, col);
  }

  void clear(int row, int col) {
    final cell = _findCell(row, col);
    if (cell == null) return;
    cell.removeAttribute('t');
    _removeValueChildren(cell, keepFormula: false);
  }

  void _ensureDataRows(int startRow, int count, int maxCol) {
    if (count <= 0) return;
    final template =
        (_findRow(startRow) ?? _findRow(startRow + count - 1))?.copy();
    for (var i = 0; i < count; i++) {
      final rowNumber = startRow + i;
      if (_findRow(rowNumber) != null) continue;
      final row = template?.copy() ??
          XmlElement(
            XmlName('row'),
            [XmlAttribute(XmlName('r'), rowNumber.toString())],
            [],
          );
      _setRowNumber(row, rowNumber);
      _clearRowValues(row);
      for (var col = 0; col <= maxCol; col++) {
        if (_findCellInRow(row, col) != null) continue;
        final style = _styleForColumn(col, rowNumber);
        row.children.add(XmlElement(
          XmlName('c'),
          [
            XmlAttribute(XmlName('r'), _cellRef(rowNumber, col)),
            if (style != null) XmlAttribute(XmlName('s'), style),
          ],
          [],
        ));
      }
      _insertRowElement(row);
    }
  }

  XmlElement? _findRow(int row) {
    for (final rowEl in sheetData.findElements('row')) {
      final r = int.tryParse(rowEl.getAttribute('r') ?? '');
      if (r == row) return rowEl;
    }
    return null;
  }

  void _shiftRows(int fromRow, int delta) {
    final rows = sheetData.findElements('row').toList()
      ..sort((a, b) {
        final ar = int.tryParse(a.getAttribute('r') ?? '') ?? 0;
        final br = int.tryParse(b.getAttribute('r') ?? '') ?? 0;
        return delta > 0 ? br.compareTo(ar) : ar.compareTo(br);
      });
    for (final rowEl in rows) {
      final row = int.tryParse(rowEl.getAttribute('r') ?? '') ?? 0;
      if (row < fromRow) continue;
      _setRowNumber(rowEl, row + delta);
    }
  }

  void _setRowNumber(XmlElement rowEl, int row) {
    rowEl.setAttribute('r', row.toString());
    for (final cell in rowEl.findElements('c')) {
      final col = _columnIndex(cell.getAttribute('r') ?? '');
      if (col >= 0) cell.setAttribute('r', _cellRef(row, col));
    }
  }

  void _clearRowValues(XmlElement rowEl) {
    for (final cell in rowEl.findElements('c')) {
      cell.removeAttribute('t');
      _removeValueChildren(cell, keepFormula: false);
    }
  }

  void _insertRowElement(XmlElement rowEl) {
    final row = int.tryParse(rowEl.getAttribute('r') ?? '') ?? 0;
    final rows = sheetData.findElements('row').toList();
    for (final current in rows) {
      final currentRow = int.tryParse(current.getAttribute('r') ?? '') ?? 0;
      if (currentRow > row) {
        sheetData.children.insert(sheetData.children.indexOf(current), rowEl);
        return;
      }
    }
    sheetData.children.add(rowEl);
  }

  XmlElement? _findCellInRow(XmlElement rowEl, int col) {
    for (final cell in rowEl.findElements('c')) {
      if (_columnIndex(cell.getAttribute('r') ?? '') == col) return cell;
    }
    return null;
  }

  void _shiftMergeCells(
    int fromRow,
    int delta, {
    int? deleteStart,
    int? deleteEnd,
  }) {
    for (final mergeCell in document.findAllElements('mergeCell').toList()) {
      final ref = mergeCell.getAttribute('ref');
      final range = ref == null ? null : _CellRange.parse(ref);
      if (range == null) continue;
      if (deleteStart != null &&
          deleteEnd != null &&
          range.startRow >= deleteStart &&
          range.endRow <= deleteEnd) {
        mergeCell.parent?.children.remove(mergeCell);
        continue;
      }
      if (range.startRow >= fromRow) {
        mergeCell.setAttribute('ref', range.shiftRows(delta).toRef());
      }
    }
    final mergeCellsElements = document.findAllElements('mergeCells').toList();
    if (mergeCellsElements.isNotEmpty) {
      final mergeCells = mergeCellsElements.first;
      final count = mergeCells.findElements('mergeCell').length;
      mergeCells.setAttribute('count', count.toString());
    }
  }

  XmlElement _cell(int row, int col) {
    final existing = _findCell(row, col);
    if (existing != null) return existing;
    final rowEl = _row(row);
    final ref = _cellRef(row, col);
    final cell =
        XmlElement(XmlName('c'), [XmlAttribute(XmlName('r'), ref)], []);
    // 新建格继承同列上方已有格的样式，保证学号/姓名等列与模板数据行边框字体一致。
    final style = _styleForColumn(col, row);
    if (style != null) cell.setAttribute('s', style);
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

  /// 找同列、目标行上方最近一行已有格的样式索引（继承边框/字体）。
  String? _styleForColumn(int col, int belowRow) {
    String? best;
    var bestRow = -1;
    for (final rowEl in sheetData.findElements('row')) {
      final r = int.tryParse(rowEl.getAttribute('r') ?? '') ?? 0;
      if (r <= 0 || r >= belowRow) continue;
      for (final c in rowEl.findElements('c')) {
        if (_columnIndex(c.getAttribute('r') ?? '') == col) {
          final s = c.getAttribute('s');
          if (s != null && r > bestRow) {
            best = s;
            bestRow = r;
          }
        }
      }
    }
    return best;
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

  void _refreshDimension() {
    final dimensions = document.findAllElements('dimension');
    if (dimensions.isEmpty) return;
    var minRow = 1;
    var minCol = 0;
    var maxRow = 1;
    var maxCol = 0;
    var seen = false;
    for (final rowEl in sheetData.findElements('row')) {
      final row = int.tryParse(rowEl.getAttribute('r') ?? '') ?? 0;
      if (row <= 0) continue;
      if (!seen) {
        minRow = maxRow = row;
        seen = true;
      } else {
        minRow = math.min(minRow, row);
        maxRow = math.max(maxRow, row);
      }
      for (final cell in rowEl.findElements('c')) {
        final col = _columnIndex(cell.getAttribute('r') ?? '');
        if (col < 0) continue;
        minCol = seen ? math.min(minCol, col) : col;
        maxCol = math.max(maxCol, col);
      }
    }
    if (!seen) return;
    dimensions.first.setAttribute(
        'ref', '${_columnName(minCol)}$minRow:${_columnName(maxCol)}$maxRow');
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

class _ChartRef {
  const _ChartRef({
    required this.drawingPath,
    required this.chartPath,
  });

  final String drawingPath;
  final String chartPath;
}

class _CellRange {
  const _CellRange({
    required this.startCol,
    required this.startRow,
    required this.endCol,
    required this.endRow,
  });

  final int startCol;
  final int startRow;
  final int endCol;
  final int endRow;

  static _CellRange? parse(String ref) {
    final parts = ref.split(':');
    final first = _CellRef.parse(parts.first);
    final last = _CellRef.parse(parts.length > 1 ? parts.last : parts.first);
    if (first == null || last == null) return null;
    return _CellRange(
      startCol: first.col,
      startRow: first.row,
      endCol: last.col,
      endRow: last.row,
    );
  }

  _CellRange shiftRows(int delta) {
    return _CellRange(
      startCol: startCol,
      startRow: startRow + delta,
      endCol: endCol,
      endRow: endRow + delta,
    );
  }

  String toRef() {
    final start = '${_WorksheetEditor._columnName(startCol)}$startRow';
    final end = '${_WorksheetEditor._columnName(endCol)}$endRow';
    return start == end ? start : '$start:$end';
  }
}

class _CellRef {
  const _CellRef(this.col, this.row);

  final int col;
  final int row;

  static _CellRef? parse(String ref) {
    final colMatch = RegExp(r'^([A-Z]+)').firstMatch(ref);
    final rowMatch = RegExp(r'(\d+)').firstMatch(ref);
    if (colMatch == null || rowMatch == null) return null;
    var col = 0;
    for (final code in colMatch.group(1)!.codeUnits) {
      col = col * 26 + code - 64;
    }
    return _CellRef(col - 1, int.parse(rowMatch.group(1)!));
  }
}
