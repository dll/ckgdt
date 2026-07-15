import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
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
  final List<double> objectiveFullMarks;
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
  final List<Map<String, double>> envWeightsByObjective;
  final double weightedAchievement;
  final double expectation;

  const AchievementExcelTemplatePayload({
    required this.courseName,
    required this.className,
    required this.semester,
    required this.objectiveWeights,
    this.objectiveFullMarks = const [],
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
    this.envWeightsByObjective = const [],
    required this.weightedAchievement,
    this.expectation = 0.6,
  });
}

/// Coordinates for a concrete achievement workbook template.
///
/// Different courses can provide different profiles. The current default is
/// inferred from the school sample achievement table (e.g. the bundled
/// "课程达成评价表格48.xlsx"). The profile is course-agnostic and only
/// describes how the columns/sections are laid out.
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

  /// 仅在课程资源包目录（data/{courseId}/达成/）查找课程专属模板。
  /// 找不到时返回 null，由调用方走动态导出，绝不套用旧 bundled 模板。
  Future<File?> findTemplateForCourse(String courseName) async {
    final profile = AchievementExcelTemplateProfile.schoolMobile48();
    final roots = await AchievementTemplateAssets.courseOnlyRoots();
    final seen = <String>{};
    final allFiles = <File>[];
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
        allFiles.add(entity);
      }
    }
    // 使用课程资源包中的所有 xlsx 模板文件。
    // courseOnlyRoots() 已限定 data/{courseId}/达成/，无需按文件名二次过滤。
    final candidates = allFiles;
    final templates = <File>[];
    for (final file in candidates) {
      if (await _isSupportedTemplate(file, profile)) {
        templates.add(file);
      }
    }
    if (templates.isEmpty) return null;
    templates.sort((a, b) {
      final nameA = a.path.split(Platform.pathSeparator).last;
      final nameB = b.path.split(Platform.pathSeparator).last;
      // 1. 文件名为 XX-课程达成度评价图表.xlsx（无 模板/样例 后缀）优先
      final isSchool = RegExp(r'^\d+-课程达成度评价图表\.xlsx$');
      final aSchool = isSchool.hasMatch(nameA) ? 0 : 1;
      final bSchool = isSchool.hasMatch(nameB) ? 0 : 1;
      if (aSchool != bSchool) return aSchool.compareTo(bSchool);
      // 2. 模板 > 样例 > 其他
      int score(File f) {
        final n = f.path.split(Platform.pathSeparator).last;
        int s = 0;
        if (n.contains('模板') || f.path.contains('模板')) s += 2;
        if (n.contains('样例') || f.path.contains('样例')) s += 1;
        return s;
      }
      final sa = score(a), sb = score(b);
      if (sa != sb) return sb.compareTo(sa);
      // 3. 排除已生成的输出文件（含日期/版本号）
      final generated = RegExp(r'\d{4}-\d{2}-\d{2}|v控制版|v\d+\.\d+');
      final aGen = generated.hasMatch(a.path) ? 1 : 0;
      final bGen = generated.hasMatch(b.path) ? 1 : 0;
      if (aGen != bGen) return aGen.compareTo(bGen);
      return a.path.length.compareTo(b.path.length);
    });
    return templates.first;
  }

  /// 从模板 workbook 的实际 sheet 名中通过关键词匹配定位每类 sheet。
  /// 避免硬编码 sheet 名无法匹配不同课程模板（如"课程目标达成度" vs "课程目标点达成度"）。
  AchievementExcelTemplateProfile _resolveProfileForTemplate(
      Map<String, List<int>> files) {
    final sheets = _sheetPaths(files).keys.toSet();
    String? match(Iterable<String> keywords) {
      for (final sheet in sheets) {
        for (final kw in keywords) {
          if (sheet.contains(kw)) return sheet;
        }
      }
      return null;
    }
    String matchRequired(Iterable<String> keywords, String label) {
      return match(keywords) ??
          (throw ArgumentError('模板缺少$label相关的 sheet'));
    }
    final exam = matchRequired(['期末'], '期末成绩');
    final experiment = matchRequired(['实验'], '实验成绩');
    final pingshi = matchRequired(['平时'], '平时成绩');
    final individual = matchRequired(['个体', '学生'], '学生个体');
    final objective = matchRequired(['目标', '达成'], '课程目标达成度');
    final bar = match(['柱状', '条形', '柱形', '雷达', '图表']) ?? objective;
    final matchedScatter = <String>[];
    for (int i = 1; i <= 10; i++) {
      final found = match(['散点', '趋势', '目标$i']);
      if (found != null) matchedScatter.add(found);
    }
    return AchievementExcelTemplateProfile(
      examSheet: exam,
      experimentSheet: experiment,
      pingshiSheet: pingshi,
      individualSheet: individual,
      objectiveSheet: objective,
      barSheet: bar,
      scatterSheets: matchedScatter,
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
      // 尝试按学校 48 人模板 profile 匹配；失败时再按关键词匹配
      final sheets = _sheetPaths(files).keys.toSet();
      final requiredSheets = <String>{
        profile.examSheet,
        profile.experimentSheet,
        profile.pingshiSheet,
        profile.individualSheet,
        profile.objectiveSheet,
      };
      final matchesExact = sheets.containsAll(requiredSheets) &&
          _barSheetNames(profile).any((n) => sheets.contains(n)) &&
          List<bool>.generate(
            profile.scatterSheets.length,
            (i) => _scatterSheetNames(profile, i)
                .any((name) => sheets.contains(name)),
          ).every((p) => p);
      if (matchesExact) return true;
      // 关键词匹配兜底：只要包含期末/实验/平时/个体/目标等关键 sheet 即视为可用
      try {
        _resolveProfileForTemplate(files);
        return true;
      } catch (e) {
        swallow(e, tag: 'AchievementTemplateExcel._isSupportedTemplate.resolve');
        return false;
      }
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
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final files = <String, List<int>>{};
    for (final f in archive.files) {
      files[f.name] = f.content as List<int>;
    }
    final activeProfile =
        profile ?? _resolveProfileForTemplate(files);

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

    // 检测模板实际汇总行位置，避免硬编码 profilesummaryRow（如 54）与模板实际（如 91—92）不匹配
    // 而导致 resize 产生多余脏行。检测不到时回退到静态 profile 值。
    final sharedStrings = _parseSharedStrings(files);
    final actualPingshiSummaryRow =
        _detectSummaryStartRow(files, sheetPaths, activeProfile.pingshiSheet, sharedStrings)
            ?? activeProfile.pingshiSummaryRow;
    final actualExperimentSummaryRow =
        _detectSummaryStartRow(files, sheetPaths, activeProfile.experimentSheet, sharedStrings)
            ?? activeProfile.experimentSummaryRow;
    final actualExamSummaryRow =
        _detectSummaryStartRow(files, sheetPaths, activeProfile.examSheet, sharedStrings)
            ?? activeProfile.examSummaryRow;
    final actualIndividualSummaryRow =
        _detectSummaryStartRow(files, sheetPaths, activeProfile.individualSheet, sharedStrings)
            ?? (activeProfile.individualSummaryRow - 1);

    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.pingshiSheet],
      dataStartRow: activeProfile.componentDataStartRow,
      templateSummaryStartRow: actualPingshiSummaryRow,
      summaryRowCount: 2,
      targetDataRows: count,
      maxCol: 38,
    );
    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.experimentSheet],
      dataStartRow: activeProfile.componentDataStartRow,
      templateSummaryStartRow: actualExperimentSummaryRow,
      summaryRowCount: 2,
      targetDataRows: count,
      maxCol: 13,
    );
    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.examSheet],
      dataStartRow: activeProfile.componentDataStartRow,
      templateSummaryStartRow: actualExamSummaryRow,
      summaryRowCount: 2,
      targetDataRows: count,
      maxCol: 10,
    );
    _resizeSheetDataRegion(
      files,
      sheetPaths,
      [activeProfile.individualSheet],
      dataStartRow: activeProfile.individualDataStartRow,
      templateSummaryStartRow: actualIndividualSummaryRow,
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

  /// 当没有学校模板时，生成一份通用格式的模板 xlsx。
  /// 结构对齐学校归档模板，含平时/实验/期末/个体达成度/课程目标点达成度/图表数据页。
  Uint8List generateGenericTemplate({
    AchievementExcelTemplateProfile? profile,
    int objectiveCount = 4,
    int studentCount = 1,
  }) {
    final activeProfile = profile ?? _profileForObjectiveCount(objectiveCount);
    final excel = xl.Excel.createExcel();
    for (final n in excel.tables.keys.toList()) { excel.delete(n); }

    xl.CellIndex ic(int col, int row) =>
        xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
    xl.TextCellValue t(Object? v) => xl.TextCellValue(v?.toString() ?? '');

    void writeCell(xl.Sheet sheet, int row, int col, String text) {
      sheet.cell(ic(col, row)).value = t(text);
    }

    // ── 平时成绩 sheet ────────────────────────────────────────────
    final pingshi = excel[activeProfile.pingshiSheet];
    writeCell(pingshi, 0, 0, '课程目标达成度计算表（平时）');
    writeCell(pingshi, 1, 0, '班级：');
    writeCell(pingshi, 1, 1, '评价方式:平时');
    // 行 5（0-indexed 4）放表头用于 _fillPingshi 列检测
    writeCell(pingshi, 4, 0, '学号');
    writeCell(pingshi, 4, 1, '姓名');
    writeCell(pingshi, 4, 14, '课堂表现指标点达成度');
    writeCell(pingshi, 4, 26, '作业测验指标点达成度');
    writeCell(pingshi, 4, 37, '课外拓展指标点达成度');
    writeCell(pingshi, 4, 38, '得分');
    // 汇总行标记
    writeCell(pingshi, 5, 0, '班平均值');

    // ── 实验成绩 sheet ─────────────────────────────────────────────
    final experiment = excel[activeProfile.experimentSheet];
    writeCell(experiment, 0, 0, '课程目标达成度计算表（实验）');
    writeCell(experiment, 1, 0, '班级：');
    writeCell(experiment, 1, 1, '评价方式:实验');
    writeCell(experiment, 4, 0, '学号');
    writeCell(experiment, 4, 1, '姓名');
    writeCell(experiment, 4, 2, '实验1得分');
    writeCell(experiment, 4, 3, '实验2得分');
    writeCell(experiment, 4, 4, '指标点达成度');
    writeCell(experiment, 4, 5, '实验3得分');
    writeCell(experiment, 4, 6, '实验4得分');
    writeCell(experiment, 4, 7, '指标点达成度');
    writeCell(experiment, 4, 8, '实验5得分');
    writeCell(experiment, 4, 9, '实验6得分');
    writeCell(experiment, 4, 10, '指标点达成度');
    writeCell(experiment, 4, 12, '指标点达成度');
    writeCell(experiment, 4, 13, '得分');
    writeCell(experiment, 5, 0, '班平均值');

    // ── 期末成绩 sheet ─────────────────────────────────────────────
    final exam = excel[activeProfile.examSheet];
    writeCell(exam, 0, 0, '课程目标达成度计算表（期末考核）');
    writeCell(exam, 1, 0, '班级：');
    writeCell(exam, 1, 1, '评价方式:期末考核（大作业）');
    writeCell(exam, 4, 0, '学号');
    writeCell(exam, 4, 1, '姓名');
    writeCell(exam, 4, 2, '项目评分得分');
    writeCell(exam, 4, 3, '指标点达成度');
    writeCell(exam, 4, 4, '小组评分得分');
    writeCell(exam, 4, 5, '指标点达成度');
    writeCell(exam, 4, 6, '个人评分得分');
    writeCell(exam, 4, 7, '指标点达成度');
    writeCell(exam, 4, 8, '答辩评分得分');
    writeCell(exam, 4, 9, '指标点达成度');
    writeCell(exam, 4, 10, '得分');
    writeCell(exam, 5, 0, '班平均值');

    // ── 学生个体课程目标达成度 sheet ──────────────────────────────
    final individual = excel[activeProfile.individualSheet];
    writeCell(individual, 0, 0, '学生个体课程目标达成度计算表');
    writeCell(individual, 1, 0, '班级：');
    writeCell(individual, 4, 0, '学号');
    writeCell(individual, 4, 1, '姓名');
    for (int obj = 0; obj < objectiveCount; obj++) {
      final offset = 2 + obj * 4;
      writeCell(individual, 4, offset, '平时目标${obj + 1}达成度');
      writeCell(individual, 4, offset + 1, '实验目标${obj + 1}达成度');
      writeCell(individual, 4, offset + 2, '期末目标${obj + 1}达成度');
      writeCell(individual, 4, offset + 3, '目标${obj + 1}达成度');
    }
    writeCell(individual, 5, 0, '班平均值');

    // ── 课程目标点达成度 sheet ────────────────────────────────────
    for (int obj = 0; obj < objectiveCount; obj++) {
      for (int env = 0; env < 3; env++) {
        final row = 8 + obj * 3 + env;
        writeCell(excel[activeProfile.objectiveSheet], row, 0,
            env == 0 ? '目标${obj + 1}' : '');
      }
    }

    // ── 图表 sheet ─────────────────────────────────────────────────
    excel[activeProfile.barSheet];
    for (final name in activeProfile.scatterSheets) {
      excel[name];
    }

    final bytes = excel.encode();
    if (bytes == null) throw StateError('生成通用模板失败');
    return Uint8List.fromList(bytes);
  }

  /// 根据目标数量选择默认 profile。
  AchievementExcelTemplateProfile _profileForObjectiveCount(int count) {
    // 默认使用学校 profile；可根据需要扩展不同数量的版本
    return AchievementExcelTemplateProfile.schoolMobile48();
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
      final sheetPath = sheetPaths[profile.pingshiSheet];
      final sharedStrings = _parseSharedStrings(files);

      // 智能检测平时列结构：扫描 row 5 找达成度列和总评列
      // 保留中间原始分列不变
      final achCols = <int>[];
      int totalCol = 38;
      if (sheetPath != null) {
        for (int c = 2; c <= 42; c++) {
          final h = _readCellText(files, sheetPath, sharedStrings, 5, c);
          if (h == null) continue;
          final clean = h.replaceAll(RegExp(r'[\n\r]'), '').trim();
          if (clean.contains('指标点达成度') || clean == '达成度') {
            achCols.add(c);
          } else if (clean.contains('得分') || clean.contains('总评') ||
                     clean.contains('总分')) {
            totalCol = c;
          }
        }
      }
      // 回退：硬编码
      if (achCols.length < 3) {
        achCols
          ..clear()
          ..addAll([14, 26, 37]);
        totalCol = 38;
      }
      final mappedAchKeys = <int, String>{
        if (achCols.isNotEmpty) achCols[0]: 'class_activity_achievement',
        if (achCols.length > 1) achCols[1]: 'quiz_homework_achievement',
        if (achCols.length > 2) achCols[2]: 'extra_learning_achievement',
      };
      // obj index for pingshiAverage: 0 → obj1, 1 → obj2, 3 → obj4
      final pingshiObjIndexes = <int>[0, 1, 3];

      final start = profile.componentDataStartRow;
      final avgRow = profile.pingshiSummaryRow;
      final achRow = avgRow + 1;
      final rows = _rowsInScoreOrder(p.scores, p.pingshi);

      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final r = start + i;
        ws.text(r, 0, row['student_id']);
        ws.text(r, 1, row['student_name']);
        for (final entry in mappedAchKeys.entries) {
          ws.number(r, entry.key, _num(row, entry.value), 4);
        }
        ws.number(r, totalCol, _num(row, 'total_score'), 1);
      }
      ws.text(avgRow, 0, '班平均值');
      for (final entry in mappedAchKeys.entries) {
        ws.number(avgRow, entry.key, _avgF(rows, entry.value), 4);
      }
      ws.number(avgRow, totalCol, _avgF(rows, 'total_score'), 1);
      // 课程目标达成度
      ws.text(achRow, 0, '课程目标达成度');
      int achIdx = 0;
      for (final entry in mappedAchKeys.entries) {
        if (achIdx < pingshiObjIndexes.length) {
          ws.number(achRow, entry.key, _avg(p.pingshiAverage, pingshiObjIndexes[achIdx]), 4);
        }
        achIdx++;
      }
      ws.number(achRow, totalCol, _averageTotal(rows, 'total_score') / 100, 4);
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
      final sheetPath = sheetPaths[profile.experimentSheet];
      final sharedStrings = _parseSharedStrings(files);

      // 智能检测实验列结构：扫描 header row 5，按序识别得分列和达成度列
      // 每个实验目标块: N个得分列 + 1个达成度列，最后是总得分列
      final scoreCols = <int>[];
      final achCols = <int>[];
      int totalCol = 13;
      if (sheetPath != null) {
        for (int c = 2; c <= 16; c++) {
          final h = _readCellText(files, sheetPath, sharedStrings, 5, c);
          if (h == null) continue;
          final clean = h.replaceAll(RegExp(r'[\n\r]'), '');
          if (clean.contains('指标点达成度') || clean == '达成度') {
            achCols.add(c);
          } else if (clean.contains('得分')) {
            // 最后一个"得分"列是总得分
            totalCol = c;
          }
        }
      }
      // 以达成度列划分目标块：
      // achCols[0] 前的得分列 → obj1，achCols[1] 前的得分列 → obj2，依此类推
      // 但 OOXML 只能逐列扫描确定归属。简化：使用模板已知的每块 2/1 列结构
      // 实际写法：先收集得分列与达成度列的有序序列
      final colTypes = <String>[];
      final colIndices = <int>[];
      if (sheetPath != null) {
        for (int c = 2; c <= totalCol; c++) {
          final h = _readCellText(files, sheetPath, sharedStrings, 5, c);
          if (h == null) continue;
          final clean = h.replaceAll(RegExp(r'[\n\r]'), '').trim();
          if (clean.contains('指标点达成度') || clean == '达成度') {
            colTypes.add('ach');
            colIndices.add(c);
          } else if (clean.contains('得分')) {
            colTypes.add('score');
            colIndices.add(c);
          }
        }
      }
      // 如检测失败回退硬编码
      if (colTypes.length < 4) {
        scoreCols
          ..clear()
          ..addAll([2, 3, 5, 6, 8, 9, 11]);
        achCols
          ..clear()
          ..addAll([4, 7, 10, 12]);
        totalCol = 13;
      } else {
        scoreCols
          ..clear()
          ..addAll(colIndices.where((i) => colTypes[colIndices.indexOf(i)] == 'score'));
        achCols
          ..clear()
          ..addAll(colIndices.where((i) => colTypes[colIndices.indexOf(i)] == 'ach'));
      }
      // 将检测到的列号映射到数据字段
      // obj1：检测序列中的第 1、2 个得分列 → exp1_score, exp2_score
      // obj2：第 3、4 个得分列 → exp3_score, exp4_score
      // obj3：第 5、6 个得分列 → exp5_score, exp6_score
      // obj4：第 7 个得分列（如有）→ exp7_score
      final mappedScoreKeys = <int, String>{
        if (scoreCols.isNotEmpty) scoreCols[0]: 'exp1_score',
        if (scoreCols.length > 1) scoreCols[1]: 'exp2_score',
        if (scoreCols.length > 2) scoreCols[2]: 'exp3_score',
        if (scoreCols.length > 3) scoreCols[3]: 'exp4_score',
        if (scoreCols.length > 4) scoreCols[4]: 'exp5_score',
        if (scoreCols.length > 5) scoreCols[5]: 'exp6_score',
        if (scoreCols.length > 6) scoreCols[6]: 'exp7_score',
      };
      final mappedAchKeys = <int, String>{
        if (achCols.isNotEmpty) achCols[0]: 'obj1_achievement',
        if (achCols.length > 1) achCols[1]: 'obj2_achievement',
        if (achCols.length > 2) achCols[2]: 'obj3_achievement',
        if (achCols.length > 3) achCols[3]: 'obj4_achievement',
      };

      final start = profile.componentDataStartRow;
      final avgRow = profile.experimentSummaryRow;
      final achRow = avgRow + 1;
      final rows = _rowsInScoreOrder(p.scores, p.experiment);
      final maxCol = totalCol;
      _clearRows(ws, start, math.max(start, avgRow - 1), 0, maxCol);
      _clearRows(ws, avgRow, achRow, 0, maxCol);

      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final r = start + i;
        ws.text(r, 0, row['student_id']);
        ws.text(r, 1, row['student_name']);
        for (final entry in mappedScoreKeys.entries) {
          ws.number(r, entry.key, _num(row, entry.value), 1);
        }
        for (final entry in mappedAchKeys.entries) {
          ws.number(r, entry.key, _num(row, entry.value), 4);
        }
        ws.number(r, totalCol, _num(row, 'total_score'), 1);
      }
      // 班平均值
      ws.text(avgRow, 0, '班平均值');
      for (final entry in mappedScoreKeys.entries) {
        ws.number(avgRow, entry.key, _avgF(rows, entry.value), 1);
      }
      for (final entry in mappedAchKeys.entries) {
        ws.number(avgRow, entry.key, _avg(p.experimentAverage, 
            int.tryParse(entry.value.replaceAll(RegExp(r'\D'), ''))! - 1), 4);
      }
      ws.number(avgRow, totalCol, _avgF(rows, 'total_score'), 1);
      // 课程目标达成度
      ws.text(achRow, 0, '课程目标达成度');
      for (int i = 0; i < achCols.length; i++) {
        ws.number(achRow, achCols[i], _avg(p.experimentAverage, i), 4);
      }
      ws.number(achRow, totalCol, _averageTotal(rows, 'total_score') / 100, 4);
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
      final sheetPath = sheetPaths[profile.examSheet];
      final sharedStrings = _parseSharedStrings(files);
      // 智能检测列结构
      final colMap = <String, int>{};
      final achCols = <int>[];
      final scoreCols = <int>[];
      int totalCol = 10;
      if (sheetPath != null) {
        for (int c = 2; c <= 15; c++) {
          final h = _readCellText(files, sheetPath, sharedStrings, 5, c);
          if (h == null) continue;
          final clean = h.replaceAll(RegExp(r'[\n\r]'), '');
          if (clean.contains('得分') && clean.length < 10) totalCol = c;
          if (clean.contains('指标点达成度') || clean == '达成度') {
            achCols.add(c);
            scoreCols.add(c - 1);
          }
        }
      }
      for (int i = 0; i < achCols.length; i++) {
        colMap['obj${i + 1}_achievement'] = achCols[i];
        colMap['obj${i + 1}_score'] = scoreCols[i];
      }
      colMap['total_score'] = totalCol;
      // 满分列：写在每个 score 列所在的同一列、第 5 行
      for (int i = 0; i < p.objectiveWeights.length && i < scoreCols.length; i++) {
        ws.text(4, scoreCols[i], '满分${_fmtInt(_fullMarkFor(p, i))}');
      }

      final start = profile.componentDataStartRow;
      final avgRow = profile.examSummaryRow;
      final achRow = avgRow + 1;
      final rows = _rowsInScoreOrder(p.scores, p.exam);
      final maxCol = totalCol;
      _clearRows(ws, start, math.max(start, avgRow - 1), 0, maxCol);
      _clearRows(ws, avgRow, achRow, 0, maxCol);

      final scoreKeys = ['project_score', 'group_score', 'individual_score', 'defense_score'];
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final r = start + i;
        ws.text(r, 0, row['student_id']);
        ws.text(r, 1, row['student_name']);
        for (int obj = 0; obj < achCols.length; obj++) {
          final sCol = scoreCols[obj];
          if (sCol > 0 && sCol <= maxCol && obj < scoreKeys.length) {
            ws.number(r, sCol, _num(row, scoreKeys[obj]), 1);
          }
          final aCol = achCols[obj];
          if (aCol > 0 && aCol <= maxCol) {
            ws.number(r, aCol, _num(row, 'obj${obj + 1}_achievement'), 4);
          }
        }
        if (totalCol > 0 && totalCol <= maxCol) {
          ws.number(r, totalCol, _num(row, 'total_score'), 1);
        }
      }
      // 班平均值
      ws.text(avgRow, 0, '班平均值');
        for (int obj = 0; obj < achCols.length; obj++) {
          final sCol = scoreCols[obj];
          if (sCol > 0 && sCol <= maxCol && obj < scoreKeys.length) {
            ws.number(avgRow, sCol, _avgF(rows, scoreKeys[obj]), 1);
          }
          final aCol = achCols[obj];
          if (aCol > 0 && aCol <= maxCol) {
            ws.number(avgRow, aCol, _avg(p.examAverage, obj), 4);
          }
        }
      if (totalCol > 0 && totalCol <= maxCol) {
        ws.number(avgRow, totalCol, _avgF(rows, 'total_score'), 1);
      }
      // 课程目标达成度
      ws.text(achRow, 0, '课程目标达成度');
        for (int obj = 0; obj < achCols.length; obj++) {
          final aCol = achCols[obj];
          if (aCol > 0 && aCol <= maxCol) {
            ws.number(achRow, aCol, _avg(p.examAverage, obj), 4);
          }
        }
      if (totalCol > 0 && totalCol <= maxCol) {
        ws.number(achRow, totalCol, _averageTotal(rows, 'total_score') / 100, 4);
      }
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
      final objCount = p.objectiveWeights.length;
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
        for (int obj = 0; obj < objCount; obj++) {
          final offset = 2 + obj * 4;
          ws.number(r, offset, _pingshiObjective(pRow, obj), 4);
          ws.number(r, offset + 1, _num(eRow, 'obj${obj + 1}_achievement'), 4);
          ws.number(r, offset + 2, _num(xRow, 'obj${obj + 1}_achievement'), 4);
          ws.number(r, offset + 3, _num(s, 'obj${obj + 1}_achievement'), 4);
        }
      }
      ws.text(avgRow, 0, '班平均值');
      for (int obj = 0; obj < objCount; obj++) {
        final offset = 2 + obj * 4;
        ws.number(avgRow, offset, _avg(p.pingshiAverage, obj), 4);
        ws.number(avgRow, offset + 1, _avg(p.experimentAverage, obj), 4);
        ws.number(avgRow, offset + 2, _avg(p.examAverage, obj), 4);
        ws.number(avgRow, offset + 3, _achievement(p, obj), 4);
      }
      ws.text(indicatorRow, 0, '指标点达成度');
      for (int obj = 0; obj < objCount; obj++) {
        ws.number(indicatorRow, 2 + obj * 4, _achievement(p, obj), 4);
      }
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
      final objCount = p.objectiveWeights.length;
      for (int obj = 0; obj < objCount; obj++) {
        final envWeights = _envWeights(p, obj);
        final envFull = [
          for (final weight in envWeights)
            weight > 0 ? _objectiveFullMark(p, obj) : 0.0
        ];
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
      final objCount = p.objectiveWeights.length;
      for (int i = 0; i < objCount; i++) {
        final row = profile.barDataStartRow + i;
        ws.text(row, 1, _objectiveName(p, i));
        ws.number(row, 2, _achievement(p, i), 4);
      }
    });

    final objCount = p.objectiveWeights.length;
    for (int obj = 0; obj < math.min(objCount, profile.scatterSheets.length); obj++) {
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

  /// 解析共享字符串表，返回按索引排列的字符串列表。
  List<String> _parseSharedStrings(Map<String, List<int>> files) {
    final bytes = files['xl/sharedStrings.xml'];
    if (bytes == null) return const [];
    try {
      final doc = XmlDocument.parse(utf8.decode(bytes));
      return doc.findAllElements('si').map((si) {
        final t = si.findElements('t').firstOrNull;
        return t?.innerText ?? '';
      }).toList();
    } catch (e) {
      swallow(e, tag: 'AchievementTemplateExcel._parseSharedStrings');
      return const [];
    }
  }

  /// 在指定工作表中查找列 A 内容为「班平均值」的行号，用于确定汇总起始行。
  /// 找不到时返回 null，由调用方回退到静态 profile。
  int? _detectSummaryStartRow(
    Map<String, List<int>> files,
    Map<String, String> sheetPaths,
    String sheetName,
    List<String> sharedStrings,
  ) {
    final path = sheetPaths[sheetName];
    if (path == null) return null;
    final bytes = files[path];
    if (bytes == null) return null;
    try {
      final doc = XmlDocument.parse(utf8.decode(bytes));
      for (final row in doc.findAllElements('row')) {
        final rAttr = row.getAttribute('r');
        if (rAttr == null) continue;
        final rowNum = int.tryParse(rAttr);
        if (rowNum == null) continue;
        for (final cell in row.findElements('c')) {
          final ref = cell.getAttribute('r') ?? '';
          if (ref != 'A$rowNum') continue;
          final tAttr = cell.getAttribute('t');
          final v = cell.findElements('v').firstOrNull;
          if (tAttr != 's' || v == null) continue;
          final idx = int.tryParse(v.innerText.trim());
          if (idx == null || idx < 0 || idx >= sharedStrings.length) continue;
          if (sharedStrings[idx].contains('班平均值')) return rowNum;
        }
      }
    } catch (e) {
      swallow(e, tag: 'AchievementTemplateExcel._findClassAvgRow');
      return null;
    }
    return null;
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
          endRow: profile.barDataStartRow + p.objectiveWeights.length - 1,
        );
      }
    }

    final endRow = math.max(1, studentCount);
    for (var obj = 0; obj < profile.scatterSheets.length; obj++) {
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
    if (index >= 0 && index < p.objectiveFullMarks.length) {
      return p.objectiveFullMarks[index];
    }
    final weight = _weight(p, index);
    return weight > 0 ? weight * 100 : (index + 1) * 10.0;
  }

  static double _objectiveFullMark(
      AchievementExcelTemplatePayload p, int index) {
    return _fullMarkFor(p, index);
  }

  static List<double> _envWeights(
      AchievementExcelTemplatePayload p, int index) {
    if (index >= 0 && index < p.envWeightsByObjective.length) {
      final row = p.envWeightsByObjective[index];
      return [
        row['pingshi'] ?? 0,
        row['experiment'] ?? 0,
        row['exam'] ?? 0,
      ];
    }
    return const [0.2, 0.3, 0.5];
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

  /// 从工作表 XML 中读取指定单元格的文本值。
  /// [col] 是 0-indexed 列号，[row] 是 1-indexed 行号（与 Excel 一致）。
  String? _readCellText(Map<String, List<int>> files, String sheetPath,
      List<String> sharedStrings, int row, int col) {
    final bytes = files[sheetPath];
    if (bytes == null) return null;
    try {
      final doc = XmlDocument.parse(utf8.decode(bytes));
      final colRef = _WorksheetEditor._columnName(col);
      final cellRef = '$colRef$row';
      for (final cell in doc.findAllElements('c')) {
        final r = cell.getAttribute('r');
        if (r != cellRef) continue;
        final t = cell.getAttribute('t');
        final v = cell.findElements('v').firstOrNull;
        if (t == 's' && v != null) {
          final idx = int.tryParse(v.innerText.trim());
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            return sharedStrings[idx];
          }
        } else if (t == 'inlineStr') {
          final isEl = cell.findElements('is').firstOrNull;
          final t2 = isEl?.findElements('t').firstOrNull;
          return t2?.innerText;
        } else if (v != null) {
          return v.innerText.trim();
        }
        return null;
      }
    } catch (e) {
      swallow(e, tag: 'AchievementTemplateExcel._getCellText');
    }
    return null;
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
