import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:sqflite/sqflite.dart';
import 'package:xml/xml.dart';
import '../../core/error_handler.dart';
import '../../data/local/database_helper.dart';
import '../../presentation/pages/achievement/achievement_config.dart';
import '../ai_service.dart';

/// 从 Excel 文件解析学生成绩并导入数据库
class AchievementExcelService {
  static final AchievementExcelService instance = AchievementExcelService._();
  AchievementExcelService._();

  /// 解析 Excel 文件，返回学生成绩列表
  Future<List<Map<String, dynamic>>> parseGradeFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return parseGradeBytes(bytes);
  }

  /// 从字节数组解析 Excel。优先解析「学生个体课程目标达成度」聚合表
  /// （已按 平时0.2/实验0.3/期末0.5 算好每目标达成度），回退到首个 sheet。
  List<Map<String, dynamic>> parseGradeBytes(Uint8List bytes) {
    final excel = xl.Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];

    // 优先：聚合达成度表（列布局：学号|姓名|[平时|实验|期末|课程目标达成度]×4）
    for (final key in excel.tables.keys) {
      if (key.contains('个体') && key.contains('达成度')) {
        final agg = _parseAchievementSheet(excel.tables[key]!);
        if (agg.isNotEmpty) return agg;
      }
    }

    // 回退：首个 sheet 按 学号|姓名|目标N得分... 解析
    final table = excel.tables[excel.tables.keys.first]!;
    final results = <Map<String, dynamic>>[];
    int startRow = 0;
    for (int i = 0; i < table.rows.length && i < 5; i++) {
      final row = table.rows[i];
      final cells = row.map((c) => c?.value?.toString() ?? '').toList();
      if (cells.any((c) => c.contains('学号') || c.contains('姓名'))) {
        startRow = i;
        // 返回列映射信息
        break;
      }
    }

    // 解析数据行
    for (int i = startRow + 1; i < table.rows.length; i++) {
      final row = table.rows[i];
      final cells = row.map((c) => c?.value?.toString() ?? '').toList();

      if (cells.isEmpty || cells.length < 2) continue;
      if (cells[0].isEmpty) continue;

      final studentId = cells[0].trim();
      final studentName = cells.length > 1 ? cells[1].trim() : '';

      // 跳过空行和汇总行
      if (studentId.isEmpty) continue;
      if (studentId.contains('合计') ||
          studentId.contains('平均') ||
          studentId.contains('备注')) continue;

      results.add(_extractGrade(cells, studentId, studentName));
    }

    return results;
  }

  /// 解析「学生个体课程目标达成度」聚合表。
  /// 列布局：0=学号 1=姓名，之后每目标 4 列：平时|实验|期末|课程目标达成度。
  /// 取每目标第 4 列（已按 0.2/0.3/0.5 加权），共 4 目标 = 列 5,9,13,17。
  List<Map<String, dynamic>> _parseAchievementSheet(xl.Sheet table) {
    final results = <Map<String, dynamic>>[];
    int headerRow = -1;
    for (int i = 0; i < table.rows.length && i < 8; i++) {
      final cells =
          table.rows[i].map((c) => c?.value?.toString() ?? '').toList();
      if (cells.isNotEmpty && cells[0].trim() == '学号') {
        headerRow = i;
        break;
      }
    }
    if (headerRow < 0) return results;

    final fm = AchievementConfig.defaults.fullMarks;
    const achCols = [5, 9, 13, 17];
    for (int i = headerRow + 1; i < table.rows.length; i++) {
      final cells =
          table.rows[i].map((c) => c?.value?.toString() ?? '').toList();
      if (cells.length < 18) continue;
      final sid = cells[0].trim();
      if (sid.isEmpty ||
          sid.contains('合计') ||
          sid.contains('平均') ||
          sid.contains('备注')) continue;
      final name = cells.length > 1 ? cells[1].trim() : '';
      final ach = List<double>.generate(
          4,
          (k) =>
              double.tryParse(cells[achCols[k]].trim())?.clamp(0.0, 1.0) ??
              0.0);
      results.add({
        'student_id': sid,
        'student_name': name,
        'obj1_score': ach[0] * fm[0],
        'obj1_achievement': ach[0],
        'obj2_score': ach[1] * fm[1],
        'obj2_achievement': ach[1],
        'obj3_score': ach[2] * fm[2],
        'obj3_achievement': ach[2],
        'obj4_score': ach[3] * fm[3],
        'obj4_achievement': ach[3],
        'total_score':
            ach[0] * fm[0] + ach[1] * fm[1] + ach[2] * fm[2] + ach[3] * fm[3],
      });
    }
    return results;
  }

  /// 解析课程成绩模板的三张明细表（平时/实验/期末成绩），返回分项原始分。
  /// 对应模板：data/达成/计科22《移动应用开发》课程达成评价表格48.xlsx
  ///
  /// 返回 {pingshi: [...], experiment: [...], exam: [...]}，每项是
  /// 与 achievement_pingshi/experiment/exam_scores 表字段对齐的行列表。
  /// 列定位（0-indexed，数据从含学号的行之后开始）：
  /// - 平时：学号0 姓名1 | 课堂表现最后得分13 | 期间测验平均分25 | 大作业平均分36
  /// - 实验：学号0 姓名1 | exp1=2 exp2=3 exp3=5 exp4=6 exp5=8 exp6=9 exp7=11
  /// - 期末：学号0 姓名1 | 项目2 小组3 个人4 答辩5
  Map<String, List<Map<String, dynamic>>> parseComponentSheets(
      Uint8List bytes) {
    // Prefer direct OOXML parsing. It only reads worksheet cell values and
    // avoids the excel package style parser, which rejects some school-owned
    // templates with non-standard numFmtId values.
    final ooxml = _parseComponentSheetsFromOoxml(bytes);
    if (_hasComponentRows(ooxml)) return ooxml;

    final out = <String, List<Map<String, dynamic>>>{
      'pingshi': [],
      'experiment': [],
      'exam': [],
    };
    late final xl.Excel excel;
    try {
      excel = xl.Excel.decodeBytes(bytes);
    } catch (e, st) {
      // 部分学校模板包含非标准内置 numFmtId，excel 包会在样式解析阶段抛错。
      // 明细导入只依赖单元格文本/数值，回退到轻量 OOXML 解析可保留导入能力。
      swallowDebug(e,
          tag: 'AchievementExcel.parseComponentSheets.decode', stack: st);
      return _parseComponentSheetsFromOoxml(bytes);
    }
    if (excel.tables.isEmpty) return out;

    for (final key in excel.tables.keys) {
      final table = excel.tables[key]!;
      // 用 sheet 名识别类型。没有实验的课程可只提供平时/考核两张表；
      // “课程设计/项目/综合/答辩”等终结性评价归入 exam 桶。
      if (_isPingshiSheetName(key)) {
        out['pingshi'] = _parsePingshiSheet(table);
      } else if (_isExperimentSheetName(key)) {
        out['experiment'] = _parseExperimentSheet(table);
      } else if (_isExamSheetName(key)) {
        out['exam'] = _parseExamSheet(table);
      }
    }
    return out;
  }

  bool _hasComponentRows(Map<String, List<Map<String, dynamic>>> components) {
    return components.values.any((rows) => rows.isNotEmpty);
  }

  bool _isPingshiSheetName(String name) {
    return name.contains('平时') ||
        name.contains('过程') ||
        name.contains('课堂') ||
        name.contains('作业') ||
        name.contains('测验');
  }

  bool _isExperimentSheetName(String name) {
    return name.contains('实验') || name.contains('实训') || name.contains('实践');
  }

  bool _isExamSheetName(String name) {
    return name.contains('期末') ||
        name.contains('考核') ||
        name.contains('考试') ||
        name.contains('项目') ||
        name.contains('课程设计') ||
        name.contains('综合') ||
        name.contains('答辩');
  }

  Map<String, List<Map<String, dynamic>>> _parseComponentSheetsFromOoxml(
      Uint8List bytes) {
    final out = <String, List<Map<String, dynamic>>>{
      'pingshi': [],
      'experiment': [],
      'exam': [],
    };
    try {
      final sheets = _readXlsxRows(bytes);
      for (final entry in sheets.entries) {
        final key = entry.key;
        final rows = entry.value;
        if (_isPingshiSheetName(key)) {
          out['pingshi'] = _parsePingshiRows(rows);
        } else if (_isExperimentSheetName(key)) {
          out['experiment'] = _parseExperimentRows(rows);
        } else if (_isExamSheetName(key)) {
          out['exam'] = _parseExamRows(rows);
        }
      }
    } catch (e, st) {
      swallowDebug(e,
          tag: 'AchievementExcel.parseComponentSheets.ooxml', stack: st);
    }
    return out;
  }

  Map<String, List<List<String>>> _readXlsxRows(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    List<int> file(String name) =>
        archive.files.firstWhere((f) => f.name == name).content as List<int>;

    final sharedStrings = <String>[];
    if (archive.files.any((f) => f.name == 'xl/sharedStrings.xml')) {
      final ssDoc =
          XmlDocument.parse(utf8.decode(file('xl/sharedStrings.xml')));
      for (final si in ssDoc.findAllElements('si')) {
        sharedStrings
            .add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    final wb = XmlDocument.parse(utf8.decode(file('xl/workbook.xml')));
    final relDoc =
        XmlDocument.parse(utf8.decode(file('xl/_rels/workbook.xml.rels')));
    final relTargets = <String, String>{};
    for (final rel in relDoc.findAllElements('Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null) continue;
      relTargets[id] = target.startsWith('/') ? target.substring(1) : target;
    }

    final result = <String, List<List<String>>>{};
    for (final sheet in wb.findAllElements('sheet')) {
      final name = sheet.getAttribute('name') ?? '';
      final rid = sheet.getAttribute('r:id') ??
          sheet.getAttribute('id',
              namespace:
                  'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
      final target = rid == null ? null : relTargets[rid];
      if (name.isEmpty || target == null) continue;
      final sheetPath = target.startsWith('xl/') ? target : 'xl/$target';
      final doc = XmlDocument.parse(utf8.decode(file(sheetPath)));
      final rows = <List<String>>[];

      for (final rowEl in doc.findAllElements('row')) {
        final rowIndex = int.tryParse(rowEl.getAttribute('r') ?? '') ?? 0;
        if (rowIndex <= 0) continue;
        while (rows.length < rowIndex) {
          rows.add(<String>[]);
        }
        final row = rows[rowIndex - 1];
        for (final cell in rowEl.findElements('c')) {
          final col = _columnIndex(cell.getAttribute('r') ?? '');
          if (col < 0) continue;
          while (row.length <= col) {
            row.add('');
          }
          row[col] = _readXlsxCell(cell, sharedStrings);
        }
      }
      result[name] = rows;
    }
    return result;
  }

  String _readXlsxCell(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');
    var value = '';
    final vEls = cell.findElements('v');
    if (vEls.isNotEmpty) value = vEls.first.innerText;
    if (type == 's') {
      final idx = int.tryParse(value);
      return idx != null && idx >= 0 && idx < sharedStrings.length
          ? sharedStrings[idx]
          : value;
    }
    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((t) => t.innerText).join();
    }
    return value;
  }

  int _columnIndex(String cellRef) {
    final match = RegExp(r'^([A-Z]+)').firstMatch(cellRef);
    if (match == null) return -1;
    var index = 0;
    for (final code in match.group(1)!.codeUnits) {
      index = index * 26 + code - 64;
    }
    return index - 1;
  }

  /// 校验解析出的三环节成绩。返回结构化报告供导入前确认。
  /// [roster]：班级应有学生名单 [{student_id, student_name}]，用于查缺；可空。
  /// 报告字段：
  ///   sheetsFound: 识别到的环节(pingshi/experiment/exam)
  ///   counts: 各环节学生数
  ///   missing: 各环节缺失的学号(对比 roster)
  ///   outOfRange: 超出 0-100 的异常分值 [{env, student_id, field, value}]
  ///   duplicates: 各环节内重复学号
  ///   ok: 是否无阻断性问题(至少识别到一个环节且无结构错误)
  Map<String, dynamic> validateComponents(
    Map<String, List<Map<String, dynamic>>> components, {
    List<Map<String, dynamic>> roster = const [],
  }) {
    final sheetsFound = <String>[];
    final counts = <String, int>{};
    final missing = <String, List<String>>{};
    final duplicates = <String, List<String>>{};
    final outOfRange = <Map<String, dynamic>>[];

    final rosterIds = roster
        .map((r) => (r['student_id'] ?? r['user_id'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();

    const scoreFields = {
      'pingshi': [
        'class_activity_score',
        'quiz_homework_score',
        'extra_learning_score'
      ],
      'experiment': [
        'exp1_score',
        'exp2_score',
        'exp3_score',
        'exp4_score',
        'exp5_score',
        'exp6_score',
        'exp7_score'
      ],
      'exam': [
        'project_score',
        'group_score',
        'individual_score',
        'defense_score'
      ],
    };

    for (final env in ['pingshi', 'experiment', 'exam']) {
      final rows = components[env] ?? const [];
      if (rows.isEmpty) continue;
      sheetsFound.add(env);
      counts[env] = rows.length;

      // 重复学号
      final seen = <String>{};
      final dup = <String>[];
      for (final r in rows) {
        final id = (r['student_id'] ?? '').toString();
        if (id.isEmpty) continue;
        if (!seen.add(id)) dup.add(id);
      }
      if (dup.isNotEmpty) duplicates[env] = dup;

      // 缺失学号（仅当提供了 roster）
      if (rosterIds.isNotEmpty) {
        final present =
            rows.map((r) => (r['student_id'] ?? '').toString()).toSet();
        final miss = rosterIds.difference(present).toList()..sort();
        if (miss.isNotEmpty) missing[env] = miss;
      }

      // 异常分值（0-100 之外）
      for (final r in rows) {
        final id = (r['student_id'] ?? '').toString();
        for (final f in scoreFields[env]!) {
          final v = (r[f] as num?)?.toDouble();
          if (v != null && (v < 0 || v > 100)) {
            outOfRange
                .add({'env': env, 'student_id': id, 'field': f, 'value': v});
          }
        }
      }
    }

    final ok =
        sheetsFound.isNotEmpty && outOfRange.isEmpty && duplicates.isEmpty;
    return {
      'sheetsFound': sheetsFound,
      'counts': counts,
      'missing': missing,
      'duplicates': duplicates,
      'outOfRange': outOfRange,
      'ok': ok,
    };
  }

  /// 找到含「学号」的表头行索引；找不到返回 -1。
  int _findStudentHeaderRow(xl.Sheet table) {
    for (int i = 0; i < table.rows.length && i < 10; i++) {
      final c0 = table.rows[i].isNotEmpty
          ? (table.rows[i][0]?.value?.toString().trim() ?? '')
          : '';
      if (c0 == '学号') return i;
    }
    return -1;
  }

  bool _isDataRow(String sid) =>
      sid.isNotEmpty &&
      !sid.contains('合计') &&
      !sid.contains('平均') &&
      !sid.contains('备注') &&
      !sid.contains('学号');

  double _cell(List<xl.Data?> row, int i) {
    if (i >= row.length) return 0;
    return double.tryParse(row[i]?.value?.toString().trim() ?? '') ?? 0;
  }

  String _cellStr(List<xl.Data?> row, int i) {
    if (i >= row.length) return '';
    return row[i]?.value?.toString().trim() ?? '';
  }

  List<Map<String, dynamic>> _parsePingshiSheet(xl.Sheet table) {
    final hr = _findStudentHeaderRow(table);
    if (hr < 0) return [];
    // 布局识别：本系统模板把 课堂/测验/大作业 放在第 2/3/4 列；
    // 学校原始模板(表格48)是复杂多列，达成度子列在 13/25/36。
    final headerC2 = _cellStr(table.rows[hr], 2);
    final headerD = _cellStr(table.rows[hr], 3);
    final headerE = _cellStr(table.rows[hr], 4);
    final simple = headerC2.contains('课堂') &&
        headerD.contains('测验') &&
        (headerE.contains('课外') || headerE.contains('大作业'));
    final cActivity = simple ? 2 : 13;
    final cQuiz = simple ? 3 : 25;
    final cExtra = simple ? 4 : 36;
    final rows = <Map<String, dynamic>>[];
    for (int i = hr + 1; i < table.rows.length; i++) {
      final row = table.rows[i];
      final sid = _cellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      rows.add({
        'student_id': sid,
        'student_name': _cellStr(row, 1),
        'class_activity_score': _cell(row, cActivity),
        'quiz_homework_score': _cell(row, cQuiz),
        'extra_learning_score': _cell(row, cExtra),
      });
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseExperimentSheet(xl.Sheet table) {
    final hr = _findStudentHeaderRow(table);
    if (hr < 0) return [];
    // 布局识别：本系统模板 exp1-N 连续列；学校原始模板有达成度列间隔
    final headerC4 = _cellStr(table.rows[hr], 4);
    final simple = headerC4.contains('实验');
    List<int> cols;
    int nExp;
    if (simple) {
      // 6实验(大纲) vs 7实验(旧模板)：按第8列是否为实验名判断
      final hasExp7 = _cellStr(table.rows[hr], 8).contains('实验');
      nExp = hasExp7 ? 7 : 6;
      cols = [for (int c = 2; c < 2 + nExp; c++) c];
    } else {
      nExp = 7; // 学校原始模板固定7
      cols = [2, 3, 5, 6, 8, 9, 11];
    }
    final rows = <Map<String, dynamic>>[];
    for (int i = hr + 1; i < table.rows.length; i++) {
      final row = table.rows[i];
      final sid = _cellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      rows.add({
        'student_id': sid,
        'student_name': _cellStr(row, 1),
        for (int k = 0; k < nExp; k++) 'exp${k + 1}_score': _cell(row, cols[k]),
        for (int k = nExp; k < 7; k++) 'exp${k + 1}_score': 0.0, // 补齐exp7=0
      });
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseExamSheet(xl.Sheet table) {
    final hr = _findStudentHeaderRow(table);
    if (hr < 0) return [];
    final rows = <Map<String, dynamic>>[];
    for (int i = hr + 1; i < table.rows.length; i++) {
      final row = table.rows[i];
      final sid = _cellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      rows.add({
        'student_id': sid,
        'student_name': _cellStr(row, 1),
        'project_score': _cell(row, 2),
        'group_score': _cell(row, 3),
        'individual_score': _cell(row, 4),
        'defense_score': _cell(row, 5),
      });
    }
    return rows;
  }

  int _findStudentHeaderRowRows(List<List<String>> rows) {
    for (int i = 0; i < rows.length && i < 10; i++) {
      final c0 = _rowCellStr(rows[i], 0);
      if (c0 == '学号') return i;
    }
    return -1;
  }

  String _rowCellStr(List<String> row, int i) {
    if (i >= row.length) return '';
    return row[i].trim();
  }

  double _rowCell(List<String> row, int i) {
    if (i >= row.length) return 0;
    return double.tryParse(row[i].trim()) ?? 0;
  }

  List<Map<String, dynamic>> _parsePingshiRows(List<List<String>> tableRows) {
    final hr = _findStudentHeaderRowRows(tableRows);
    if (hr < 0) return [];
    final headerC2 = _rowCellStr(tableRows[hr], 2);
    final headerD = _rowCellStr(tableRows[hr], 3);
    final headerE = _rowCellStr(tableRows[hr], 4);
    final simple = headerC2.contains('课堂') &&
        headerD.contains('测验') &&
        (headerE.contains('课外') || headerE.contains('大作业'));
    final cActivity = simple ? 2 : 13;
    final cQuiz = simple ? 3 : 25;
    final cExtra = simple ? 4 : 36;
    final rows = <Map<String, dynamic>>[];
    for (int i = hr + 1; i < tableRows.length; i++) {
      final row = tableRows[i];
      final sid = _rowCellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      rows.add({
        'student_id': sid,
        'student_name': _rowCellStr(row, 1),
        'class_activity_score': _rowCell(row, cActivity),
        'quiz_homework_score': _rowCell(row, cQuiz),
        'extra_learning_score': _rowCell(row, cExtra),
      });
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseExperimentRows(
      List<List<String>> tableRows) {
    final hr = _findStudentHeaderRowRows(tableRows);
    if (hr < 0) return [];
    final headerC4 = _rowCellStr(tableRows[hr], 4);
    final simple = headerC4.contains('实验');
    List<int> cols;
    int nExp;
    if (simple) {
      final hasExp7 = _rowCellStr(tableRows[hr], 8).contains('实验');
      nExp = hasExp7 ? 7 : 6;
      cols = [for (int c = 2; c < 2 + nExp; c++) c];
    } else {
      nExp = 7;
      cols = [2, 3, 5, 6, 8, 9, 11];
    }

    final rows = <Map<String, dynamic>>[];
    for (int i = hr + 1; i < tableRows.length; i++) {
      final row = tableRows[i];
      final sid = _rowCellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      rows.add({
        'student_id': sid,
        'student_name': _rowCellStr(row, 1),
        for (int k = 0; k < nExp; k++)
          'exp${k + 1}_score': _rowCell(row, cols[k]),
        for (int k = nExp; k < 7; k++) 'exp${k + 1}_score': 0.0,
      });
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseExamRows(List<List<String>> tableRows) {
    final hr = _findStudentHeaderRowRows(tableRows);
    if (hr < 0) return [];
    final rows = <Map<String, dynamic>>[];
    for (int i = hr + 1; i < tableRows.length; i++) {
      final row = tableRows[i];
      final sid = _rowCellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      rows.add({
        'student_id': sid,
        'student_name': _rowCellStr(row, 1),
        'project_score': _rowCell(row, 2),
        'group_score': _rowCell(row, 3),
        'individual_score': _rowCell(row, 4),
        'defense_score': _rowCell(row, 5),
      });
    }
    return rows;
  }

  Map<String, dynamic> _extractGrade(
      List<String> cells, String id, String name) {
    // 列结构通常为：学号 | 姓名 | 课程目标1 | 课程目标2 | 课程目标3 | 课程目标4 | 总评 | ...
    final grade = <String, dynamic>{
      'student_id': id,
      'student_name': name,
    };

    // 解析数值列（从第3列开始尝试）
    final scores = <double>[];
    for (int i = 2; i < cells.length; i++) {
      final v = double.tryParse(cells[i]);
      if (v != null) scores.add(v);
    }

    // 如果有4个课程目标+总评
    if (scores.length >= 4) {
      grade['obj1_score'] = scores[0];
      grade['obj2_score'] = scores[1];
      grade['obj3_score'] = scores[2];
      grade['obj4_score'] = scores[3];
      if (scores.length >= 5) grade['total_score'] = scores[4];
    }

    return grade;
  }

  /// 解析由 [buildGradeTemplate] 生成的新动态模板。
  ///
  /// 新模板不再固定生成「平时/实验/期末」三张表，而是在「成绩录入」sheet
  /// 中按大纲对照表生成真实存在的考核项列。每个成绩单元格填写 0-100，
  /// 本方法按列头中的课程目标和比例直接合成 objN_achievement。
  List<Map<String, dynamic>> parseDynamicGradeTemplate(
    Uint8List bytes, {
    List<Map<String, dynamic>> objectiveRows = const [],
  }) {
    late final xl.Excel excel;
    try {
      excel = xl.Excel.decodeBytes(bytes);
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementExcel.parseDynamic.decode', stack: st);
      return const [];
    }
    final sheet = excel.tables['成绩录入'];
    if (sheet == null || sheet.rows.isEmpty) return const [];

    final items = _assessmentItemsFromRows(objectiveRows);
    final itemByObjectiveAndLabel = <String, _TemplateAssessmentItem>{
      for (final item in items) '${item.objective}|${item.label}': item
    };
    final fullMarks = _fullMarksFromRows(objectiveRows);

    var headerRow = -1;
    for (var r = 0; r < sheet.rows.length && r < 10; r++) {
      final cells =
          sheet.rows[r].map((c) => c?.value?.toString() ?? '').toList();
      if (cells.isNotEmpty && cells[0].trim() == '学号') {
        headerRow = r;
        break;
      }
    }
    if (headerRow < 0) return const [];

    final headers =
        sheet.rows[headerRow].map((c) => c?.value?.toString() ?? '').toList();
    final columns = <int, _TemplateAssessmentItem>{};
    for (var c = 2; c < headers.length; c++) {
      final parsed = _parseDynamicTemplateHeader(headers[c]);
      if (parsed == null) continue;
      final key = '${parsed.objective}|${parsed.label}';
      columns[c] = itemByObjectiveAndLabel[key] ?? parsed;
    }
    if (columns.isEmpty) return const [];

    final results = <Map<String, dynamic>>[];
    for (var r = headerRow + 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final sid = _cellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      final name = _cellStr(row, 1);
      final ach = List<double>.filled(4, 0);

      for (final entry in columns.entries) {
        final item = entry.value;
        if (item.objective < 1 || item.objective > 4) continue;
        final score = _cell(row, entry.key).clamp(0.0, 100.0).toDouble();
        ach[item.objective - 1] += score / 100.0 * item.ratio;
      }

      final grade = <String, dynamic>{
        'student_id': sid,
        'student_name': name,
      };
      var total = 0.0;
      for (var i = 0; i < 4; i++) {
        final full = fullMarks[i];
        final value = ach[i].clamp(0.0, 1.0);
        grade['obj${i + 1}_achievement'] = value;
        grade['obj${i + 1}_score'] = value * full;
        total += value * full;
      }
      grade['total_score'] = total;
      results.add(grade);
    }
    return results;
  }

  _TemplateAssessmentItem? _parseDynamicTemplateHeader(String header) {
    final text = _normalizeSyllabusText(header);
    final m = RegExp(r'^(.+?)-课程目标(\d+)-比例(\d+(?:\.\d+)?)%$').firstMatch(text);
    if (m == null) return null;
    final label = m.group(1)!.trim();
    final objective = int.tryParse(m.group(2)!) ?? 0;
    final ratio = (double.tryParse(m.group(3)!) ?? 0) / 100.0;
    if (objective <= 0 || ratio <= 0) return null;
    return _TemplateAssessmentItem(
      label: label,
      kind: _assessmentKind(label),
      objective: objective,
      ratio: ratio,
    );
  }

  /// 从文件解析教学大纲（支持 MD / Word(docx) / Excel）
  Future<Map<String, dynamic>> parseSyllabus(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return {'error': '文件不存在'};
    }

    final ext = filePath.split('.').last.toLowerCase();
    if (ext == 'md') {
      return _parseMarkdownSyllabus(await file.readAsString());
    } else if (ext == 'docx') {
      return parseWordSyllabus(await file.readAsBytes());
    } else if (ext == 'xlsx' || ext == 'xls') {
      return _parseExcelSyllabus(await file.readAsBytes());
    }

    return {'error': '不支持的文件格式: $ext'};
  }

  /// 从字节+扩展名解析大纲（FilePicker 在部分平台只给 bytes）。
  Map<String, dynamic> parseSyllabusBytes(Uint8List bytes, String ext) {
    final e = ext.toLowerCase();
    if (e == 'md') return _parseMarkdownSyllabus(utf8.decode(bytes));
    if (e == 'docx') return parseWordSyllabus(bytes);
    if (e == 'xlsx' || e == 'xls') return _parseExcelSyllabus(bytes);
    return {'error': '不支持的文件格式: $ext'};
  }

  /// 提取大纲原始纯文本（MD 直接 utf8；docx 抽 word/document.xml 的所有 w:t）。
  /// 供 AI 全面解析使用。
  String syllabusRawText(Uint8List bytes, String ext) {
    final e = ext.toLowerCase();
    if (e == 'md') return utf8.decode(bytes);
    if (e == 'docx') {
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        final doc =
            archive.files.firstWhere((f) => f.name == 'word/document.xml');
        final xmlStr = utf8.decode(doc.content as List<int>);
        final d = XmlDocument.parse(xmlStr);
        final buf = StringBuffer();
        for (final p in d.findAllElements('w:p')) {
          final line = p.findAllElements('w:t').map((t) => t.innerText).join();
          buf.writeln(line);
        }
        return buf.toString();
      } catch (e, st) {
        swallowDebug(e, tag: 'AchievementExcel.syllabusRawText', stack: st);
        return '';
      }
    }
    return '';
  }

  /// 用 AI 全面解析大纲原始文本，提取课程目标的完整信息：
  /// 描述、指标点、权重、满分、章节支撑、实验支撑、平时/实验/期末三类评价标准。
  /// 返回 4 个目标的行（与 course_objectives 字段对齐，含 standards JSON）。
  /// AI 不可用或解析失败时返回空列表，由调用方回退到正则解析。
  Future<List<Map<String, dynamic>>> aiExtractSyllabus(String rawText) async {
    if (rawText.trim().isEmpty) return [];
    const system = '你是高校课程达成度评价专家，精通工程教育认证。'
        '请仔细阅读课程教学大纲，提取 4 个课程目标的完整结构化信息，只返回 JSON，不要任何解释文字。';
    final prompt = '''
阅读以下课程教学大纲，提取每个课程目标的信息。
重点全面解析：
1. 课程目标的描述、支撑的毕业要求指标点(如 1.4)、权重(小数)、满分；
2. 哪些章节支撑该目标(章节号)；
3. 哪些实验项目支撑该目标(实验序号)；
4. 平时成绩评价标准、实验成绩评价标准、期末考核评价内容中该目标对应的考核要点。

返回 JSON 数组，4 个元素，格式：
[{
  "idx": 1,
  "name": "课程目标1",
  "indicator": "1.4",
  "weight": 0.15,
  "full_mark": 15,
  "description": "目标描述全文",
  "chapters": "第1章、第2章",
  "experiments": "实验1、实验2",
  "assess_content": "期末考核该目标的评价内容",
  "pingshi_standard": "平时成绩该目标的评价标准要点",
  "experiment_standard": "实验成绩该目标的评价标准要点"
}]
权重之和应为 1。仅返回 JSON 数组。

大纲全文：
$rawText
''';
    try {
      final raw = await AiService().chat(
        [
          {'role': 'user', 'content': prompt}
        ],
        systemPrompt: system,
      );
      final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
      if (match == null) return [];
      final list =
          (jsonDecode(match.group(0)!) as List).cast<Map<String, dynamic>>();
      // 规范化字段
      return list
          .map((o) {
            final idx = (o['idx'] as num?)?.toInt() ?? 0;
            return {
              'idx': idx,
              'name': (o['name'] as String?) ?? '课程目标$idx',
              'indicator': (o['indicator'] ?? '').toString(),
              'weight': (o['weight'] as num?)?.toDouble() ?? 0,
              'full_mark': (o['full_mark'] as num?)?.toDouble() ?? 0,
              'description': (o['description'] ?? '').toString(),
              'chapters': (o['chapters'] ?? '').toString(),
              'assess_content': (o['assess_content'] ?? '').toString(),
              'pingshi_ratio': 0.20,
              'experiment_ratio': 0.30,
              'exam_ratio': 0.50,
              // 额外信息打包进 standards（course_objectives 未必有这些列，调用方自取）
              'experiments': (o['experiments'] ?? '').toString(),
              'pingshi_standard': (o['pingshi_standard'] ?? '').toString(),
              'experiment_standard':
                  (o['experiment_standard'] ?? '').toString(),
            };
          })
          .where((o) => (o['idx'] as int) > 0)
          .toList()
        ..sort((a, b) => (a['idx'] as int).compareTo(b['idx'] as int));
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementExcel.aiExtractSyllabus', stack: st);
      return [];
    }
  }

  Map<String, dynamic> _parseMarkdownSyllabus(String content) {
    final result = <String, dynamic>{};
    final lines = content.split('\n');

    // 解析课程基本信息
    final infoMap = <String, String>{};
    for (final line in lines) {
      if (line.startsWith('**') && line.contains('：')) {
        final cleaned = line.replaceAll('**', '').replaceAll('*', '');
        final parts = cleaned.split('：');
        if (parts.length >= 2) {
          infoMap[parts[0].trim()] = parts.sublist(1).join('：').trim();
        }
      }
    }
    result['info'] = infoMap;

    // 解析课程目标
    final objectives = <Map<String, String>>[];
    var inObjTable = false;
    for (final line in lines) {
      if (line.contains('课程目标') && line.contains('支撑的毕业要求')) {
        inObjTable = true;
        continue;
      }
      if (inObjTable) {
        final match = RegExp(r'\|\s*(\d)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|')
            .firstMatch(line);
        if (match != null) {
          objectives.add({
            'num': match.group(1)!,
            'objective': match.group(2)!.trim(),
            'requirement': match.group(3)!.trim(),
          });
        }
        if (line.trim().isEmpty && objectives.isNotEmpty) {
          inObjTable = false;
        }
      }
    }
    result['objectives'] = objectives;

    // 解析考核权重表
    final weightItems = <Map<String, dynamic>>[];
    var inWeightTable = false;
    for (final line in lines) {
      if (line.contains('权重') && line.contains('毕业要求')) {
        inWeightTable = true;
        continue;
      }
      if (inWeightTable) {
        final match = RegExp(
                r'\|\s*课程目标\s*(\d)\s*\|\s*([\d.]+)\s*\|.*?\|\s*(\d+)\s*.*?\|\s*(\d+)\s*.*?\|\s*(\d+)\s*.*?\|')
            .firstMatch(line);
        if (match != null) {
          weightItems.add({
            'objective': int.parse(match.group(1)!),
            'weight': double.parse(match.group(2)!),
            'pingshi_full': int.parse(match.group(3)!),
            'experiment_full': int.parse(match.group(4)!),
            'exam_full': int.parse(match.group(5)!),
          });
        }
        if (line.trim().isEmpty && weightItems.isNotEmpty) {
          inWeightTable = false;
        }
      }
    }
    result['weights'] = weightItems;

    // 解析期末考核评价内容表（| 基本要求 | 评价内容 | 比例 |），供报告表4。
    final assessItems = <Map<String, dynamic>>[];
    var inAssessTable = false;
    for (final line in lines) {
      if (line.contains('基本要求') && line.contains('评价内容')) {
        inAssessTable = true;
        continue;
      }
      if (inAssessTable) {
        final m =
            RegExp(r'\|\s*课程目标\s*(\d)[^|]*\|\s*([^|]+?)\s*\|').firstMatch(line);
        if (m != null) {
          assessItems.add({
            'objective': int.parse(m.group(1)!),
            'content': m.group(2)!.trim(),
          });
        }
        if (line.trim().isEmpty && assessItems.isNotEmpty) {
          inAssessTable = false;
        }
      }
    }
    result['assessContents'] = assessItems;

    // 实验项目与学时分配表（|序号|...|对应课程目标|）
    final expMap = <int, List<String>>{};
    var inExpTable = false;
    for (final line in lines) {
      if (line.contains('实验项目') && line.contains('对应课程目标')) {
        inExpTable = true;
        continue;
      }
      if (inExpTable) {
        final m = RegExp(r'\|\s*(\d+)\s*\|.+?\|\s*(\d+(?:[-]\d+)?)\s*\|')
            .firstMatch(line);
        if (m != null) {
          final expNum = int.tryParse(m.group(1)!) ?? 0;
          final targetStr = m.group(2)!;
          if (targetStr.contains('-')) {
            final range = targetStr.split('-');
            final start = int.tryParse(range[0]) ?? 0;
            final end = int.tryParse(range[1]) ?? start;
            for (int t = start; t <= end; t++)
              expMap.putIfAbsent(t, () => []).add('实验$expNum');
          } else {
            final t = int.tryParse(targetStr) ?? 0;
            if (t > 0) expMap.putIfAbsent(t, () => []).add('实验$expNum');
          }
        }
        if (line.trim().isEmpty && expMap.isNotEmpty) inExpTable = false;
      }
    }
    result['experimentMap'] =
        expMap.map((k, v) => MapEntry(k.toString(), v.join('、')));

    // 章节/教学安排表（|章节|...|对应课程目标|）
    final chMap = <int, List<String>>{};
    var inChTable = false;
    for (final line in lines) {
      if (line.contains('章节') &&
          (line.contains('教学内容') || line.contains('对应课程目标'))) {
        inChTable = true;
        continue;
      }
      if (inChTable) {
        final m = RegExp(r'\|\s*(\d+)\s*\|.+?\|\s*目标\s*(\d+(?:[-]\d+)?)\s*\|')
            .firstMatch(line);
        if (m != null) {
          final chNum = int.tryParse(m.group(1)!) ?? 0;
          final targetStr = m.group(2)!;
          if (targetStr.contains('-')) {
            final range = targetStr.split('-');
            final start = int.tryParse(range[0]) ?? 0;
            final end = int.tryParse(range[1]) ?? start;
            for (int t = start; t <= end; t++)
              chMap.putIfAbsent(t, () => []).add('第${chNum}章');
          } else {
            final t = int.tryParse(targetStr) ?? 0;
            if (t > 0) chMap.putIfAbsent(t, () => []).add('第${chNum}章');
          }
        }
        if (line.trim().isEmpty && chMap.isNotEmpty) inChTable = false;
      }
    }
    result['chapterMap'] =
        chMap.map((k, v) => MapEntry(k.toString(), v.join('、')));

    return result;
  }

  Map<String, dynamic> _parseExcelSyllabus(Uint8List bytes) {
    // Excel 大纲较少见；优先支持 MD/Word。Excel 暂回退到通用提示。
    return {'note': 'Excel 大纲解析暂未支持，请用 Markdown 或 Word 格式大纲'};
  }

  /// 解析 Word(docx) 大纲：解压 word/document.xml，提取「课程目标达成考核与评价
  /// 方式及成绩评定对照表」——含 目标/权重/平时·实验·期末满分。
  Map<String, dynamic> parseWordSyllabus(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw StateError('非法 docx：缺 word/document.xml'),
      );
      final xmlStr = utf8.decode(docFile.content as List<int>);
      final doc = XmlDocument.parse(xmlStr);

      // docx 表格：w:tbl > w:tr > w:tc > w:p > w:r > w:t。逐行取单元格文本。
      final objectives = <Map<String, String>>[];
      final weights = <Map<String, dynamic>>[];
      final assessContents = <Map<String, dynamic>>[];
      final experimentMap = <int, List<String>>{};
      final chapterMap = <int, List<String>>{};
      final pingshiStandards = <int, String>{};
      final experimentStandards = <int, String>{};
      var rubricTableCount = 0;

      for (final tbl in doc.findAllElements('w:tbl')) {
        final tableRows = <List<String>>[];
        for (final tr in tbl.findAllElements('w:tr')) {
          final cells = <String>[];
          for (final tc in tr.findAllElements('w:tc')) {
            final text = _normalizeSyllabusText(
                tc.findAllElements('w:t').map((t) => t.innerText).join());
            cells.add(text);
          }
          if (cells.isEmpty) continue;
          tableRows.add(cells);
        }
        if (tableRows.isEmpty) continue;

        final headerText = tableRows.take(2).expand((r) => r).join('|');

        // 课程目标表：序号 | 课程目标 | 支撑的毕业要求。
        if (headerText.contains('课程目标') && headerText.contains('支撑的毕业要求')) {
          for (final cells in tableRows.skip(1)) {
            final idx = int.tryParse(cells.isNotEmpty ? cells[0] : '');
            if (idx == null || idx <= 0) continue;
            if (cells.length < 3 || cells[1].length <= 8) continue;
            final indicator = _extractIndicator(cells[2]);
            if (indicator == null) continue;
            objectives.add({
              'num': '$idx',
              'objective': cells[1],
              'requirement': cells[2],
            });
          }
          continue;
        }

        // 学校达成报告表：课程目标描述 | 毕业要求指标点 | 考核内容。
        if (headerText.contains('毕业要求指标点') && headerText.contains('考核内容')) {
          for (final cells in tableRows) {
            if (cells.length < 3 || cells[0].length <= 8) continue;
            final indicator = _extractIndicator(cells[1]);
            if (indicator == null) continue;
            final idx = objectives.length + 1;
            if (!objectives.any((o) => o['num'] == '$idx')) {
              objectives.add({
                'num': '$idx',
                'objective': cells[0],
                'requirement': cells[1],
              });
            }
            assessContents.add({
              'objective': idx,
              'content': cells[2],
            });
          }
          continue;
        }

        // 实验项目与课程目标映射表。
        if (headerText.contains('实验项目') && headerText.contains('对应课程目标')) {
          final targetCol = _findHeaderColumn(tableRows.first, '对应课程目标',
              fallback: tableRows.first.length - 1);
          for (final cells in tableRows.skip(1)) {
            if (cells.isEmpty) continue;
            final expNo = int.tryParse(cells[0]);
            if (expNo == null || expNo <= 0 || targetCol >= cells.length) {
              continue;
            }
            for (final target in _parseTargetRefs(cells[targetCol])) {
              experimentMap.putIfAbsent(target, () => []).add('实验$expNo');
            }
          }
          continue;
        }

        // 章节与课程目标映射表。
        if (headerText.contains('章节') && headerText.contains('对应课程目标')) {
          final targetCol = _findHeaderColumn(tableRows.first, '对应课程目标',
              fallback:
                  tableRows.first.length > 3 ? 3 : tableRows.first.length - 1);
          for (final cells in tableRows.skip(1)) {
            if (cells.isEmpty) continue;
            final chapterNo = int.tryParse(cells[0]);
            if (chapterNo == null ||
                chapterNo <= 0 ||
                targetCol >= cells.length) {
              continue;
            }
            for (final target in _parseTargetRefs(cells[targetCol])) {
              chapterMap.putIfAbsent(target, () => []).add('第$chapterNo章');
            }
          }
          continue;
        }

        // 课程目标达成考核与评价方式及成绩评定对照表。
        // 不再要求表头固定为「平时/实验/期末」三列。部分课程没有实验，
        // 或将终结性评价写成「课程设计/项目/综合考核」，这里按表头识别并
        // 归入内部三类桶：pingshi / experiment / exam。
        if (_looksLikeAssessmentMatrix(tableRows, headerText)) {
          for (var rowIndex = 0; rowIndex < tableRows.length; rowIndex++) {
            final cells = tableRows[rowIndex];
            final m = RegExp(r'课程目标\s*(\d)').firstMatch(cells[0]);
            if (m == null || cells.length < 3) continue;
            final idx = int.parse(m.group(1)!);

            // 两类模板：
            // 1) 课程目标1 | 0.15 | 支撑毕业要求1.4 | 15(20%) | 15(30%) | 15(50%)
            // 2) 课程目标1 | 支撑毕业要求2.2 | 20(20%) | 20(30%) | 20(50%)
            final explicitWeight =
                _parseWeightCell(cells.length > 1 ? cells[1] : '');
            final componentStart = explicitWeight != null ? 3 : 2;
            final items = <Map<String, dynamic>>[];
            final ratioByKind = <String, double>{
              'pingshi': 0,
              'experiment': 0,
              'exam': 0,
            };
            final fullByKind = <String, double>{};
            for (int i = componentStart; i < cells.length; i++) {
              final parsed = _parseFullAndRatio(cells[i]);
              if (parsed == null) continue;
              final label =
                  _assessmentLabelForCell(tableRows, rowIndex, i, items.length);
              final kind = _assessmentKind(label);
              final ratio = parsed.ratio ?? 0;
              ratioByKind[kind] = (ratioByKind[kind] ?? 0) + ratio;
              fullByKind[kind] = parsed.full;
              items.add({
                'label': label,
                'kind': kind,
                'full': parsed.full,
                'ratio': ratio,
              });
            }
            if (items.isEmpty) continue;
            final fullMark = (items.first['full'] as num).toDouble();
            final requirement = cells.length > 1
                ? cells.firstWhere((c) => _extractIndicator(c) != null,
                    orElse: () => '')
                : '';
            final weight = explicitWeight ?? (fullMark / 100.0);
            weights.add({
              'objective': idx,
              'weight': weight,
              'requirement': requirement,
              'full_mark': fullMark,
              'pingshi_full': fullByKind['pingshi'] ?? fullMark,
              'experiment_full': fullByKind['experiment'] ?? 0,
              'exam_full': fullByKind['exam'] ?? fullMark,
              'pingshi_ratio': ratioByKind['pingshi'] ?? 0,
              'experiment_ratio': ratioByKind['experiment'] ?? 0,
              'exam_ratio': ratioByKind['exam'] ?? 0,
              'assessment_items_json': jsonEncode(items),
            });
          }
          continue;
        }

        // 平时/实验评价标准表：观测点 | 评价标准 | 成绩比例。
        if (headerText.contains('观测点') && headerText.contains('评价标准')) {
          rubricTableCount++;
          final isExperimentRubric = rubricTableCount >= 2;
          for (final cells in tableRows) {
            if (cells.length < 2) continue;
            final idx = _extractObjectiveIndex(cells[0]);
            if (idx == null) continue;
            final standard = cells[1].trim();
            if (standard.isEmpty) continue;
            if (isExperimentRubric) {
              experimentStandards[idx] = standard;
            } else {
              pingshiStandards[idx] = standard;
            }
            final ratio = _parsePercent(cells.last);
            if (ratio != null && !weights.any((w) => w['objective'] == idx)) {
              weights.add({
                'objective': idx,
                'weight': ratio,
                'requirement': cells[0],
                'full_mark': ratio * 100,
                'pingshi_full': ratio * 100,
                'experiment_full': ratio * 100,
                'exam_full': ratio * 100,
              });
            }
          }
          continue;
        }

        // 期末/综合评价内容表：基本要求 | 评价内容 | 比例。
        if (headerText.contains('基本要求') &&
            headerText.contains('评价内容') &&
            headerText.contains('比例')) {
          for (final cells in tableRows.skip(1)) {
            if (cells.length < 2) continue;
            final idx = _extractObjectiveIndex(cells[0]);
            if (idx == null) continue;
            assessContents.add({
              'objective': idx,
              'content': cells[1],
            });
            final ratio = cells.length > 2 ? _parsePercent(cells[2]) : null;
            if (ratio != null && !weights.any((w) => w['objective'] == idx)) {
              weights.add({
                'objective': idx,
                'weight': ratio,
                'requirement': cells[0],
                'full_mark': ratio * 100,
                'pingshi_full': ratio * 100,
                'experiment_full': ratio * 100,
                'exam_full': ratio * 100,
              });
            }
          }
        }
      }

      for (final entry in pingshiStandards.entries) {
        assessContents.add({
          'objective': entry.key,
          'pingshi_standard': entry.value,
        });
      }
      for (final entry in experimentStandards.entries) {
        assessContents.add({
          'objective': entry.key,
          'experiment_standard': entry.value,
        });
      }

      return {
        'courseName': _extractCourseNameFromDocx(doc),
        'objectives': objectives,
        'weights': weights,
        'assessContents': assessContents,
        'experimentMap':
            experimentMap.map((k, v) => MapEntry(k.toString(), _joinUnique(v))),
        'chapterMap':
            chapterMap.map((k, v) => MapEntry(k.toString(), _joinUnique(v))),
      };
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementExcel.parseWord', stack: st);
      return {'error': 'Word 大纲解析失败: $e'};
    }
  }

  bool _looksLikeAssessmentMatrix(
      List<List<String>> tableRows, String headerText) {
    if (!headerText.contains('课程目标')) return false;
    final hasAssessmentKeyword = headerText.contains('成绩') ||
        headerText.contains('评价') ||
        headerText.contains('考核') ||
        headerText.contains('考试') ||
        headerText.contains('项目') ||
        headerText.contains('设计') ||
        headerText.contains('平时') ||
        headerText.contains('实验');
    if (!hasAssessmentKeyword) return false;

    var objectiveRowsWithScores = 0;
    for (final cells in tableRows) {
      if (cells.isEmpty) continue;
      if (RegExp(r'课程目标\s*\d').hasMatch(cells[0])) {
        final scoreCells = cells.where((c) => _parseFullAndRatio(c) != null);
        if (scoreCells.isNotEmpty) objectiveRowsWithScores++;
      }
    }
    return objectiveRowsWithScores > 0;
  }

  String _assessmentLabelForCell(List<List<String>> tableRows, int rowIndex,
      int colIndex, int componentOrdinal) {
    for (var r = rowIndex - 1; r >= 0; r--) {
      if (colIndex >= tableRows[r].length) continue;
      final text = _normalizeSyllabusText(tableRows[r][colIndex]);
      if (text.isEmpty) continue;
      if (_parseFullAndRatio(text) != null) continue;
      if (text.contains('课程目标') ||
          text.contains('毕业要求') ||
          text.contains('指标点') ||
          text == '权重') {
        continue;
      }
      return text;
    }
    const fallback = ['平时成绩', '考核成绩', '考核项3'];
    if (componentOrdinal >= 0 && componentOrdinal < fallback.length) {
      return fallback[componentOrdinal];
    }
    return '考核项${componentOrdinal + 1}';
  }

  String _assessmentKind(String label) {
    final text = _normalizeSyllabusText(label);
    if (text.contains('实验') || text.contains('实训') || text.contains('实践')) {
      return 'experiment';
    }
    if (text.contains('平时') ||
        text.contains('过程') ||
        text.contains('课堂') ||
        text.contains('作业') ||
        text.contains('测验') ||
        text.contains('考勤')) {
      return 'pingshi';
    }
    return 'exam';
  }

  String _normalizeSyllabusText(String text) {
    const replacements = {
      '０': '0',
      '１': '1',
      '２': '2',
      '３': '3',
      '４': '4',
      '５': '5',
      '６': '6',
      '７': '7',
      '８': '8',
      '９': '9',
      '（': '(',
      '）': ')',
      '％': '%',
      '，': ',',
      '；': ';',
      '：': ':',
      '－': '-',
      '—': '-',
      '～': '~',
    };
    var out = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    return out.trim();
  }

  String? _extractIndicator(String text) =>
      RegExp(r'\d+(?:\.\d+)+').firstMatch(text)?.group(0);

  int? _extractObjectiveIndex(String text) {
    final normalized = _normalizeSyllabusText(text);
    final m = RegExp(r'课程目标\s*(\d+)').firstMatch(normalized);
    if (m != null) return int.tryParse(m.group(1)!);
    return int.tryParse(normalized);
  }

  int _findHeaderColumn(List<String> header, String keyword,
      {required int fallback}) {
    for (var i = 0; i < header.length; i++) {
      if (header[i].contains(keyword)) return i;
    }
    return fallback.clamp(0, header.length - 1);
  }

  List<int> _parseTargetRefs(String text) {
    final normalized = _normalizeSyllabusText(text);
    final direct = RegExp(r'(?:课程)?目标\s*(\d+)')
        .allMatches(normalized)
        .map((m) => int.tryParse(m.group(1)!))
        .whereType<int>()
        .toList();
    if (direct.isNotEmpty) return _uniqueInts(direct);

    final targets = <int>[];
    for (final part in normalized.split(RegExp(r'[、,，;；/和及+\s]+'))) {
      if (part.isEmpty || part.contains('.')) continue;
      final range = RegExp(r'^(\d+)\s*[-~至]\s*(\d+)$').firstMatch(part);
      if (range != null) {
        final start = int.tryParse(range.group(1)!) ?? 0;
        final end = int.tryParse(range.group(2)!) ?? start;
        for (var i = start; i <= end; i++) {
          if (i > 0) targets.add(i);
        }
        continue;
      }
      final value = int.tryParse(part);
      if (value != null && value > 0) targets.add(value);
    }
    return _uniqueInts(targets);
  }

  List<int> _uniqueInts(Iterable<int> values) {
    final seen = <int>{};
    return [
      for (final v in values)
        if (seen.add(v)) v
    ];
  }

  String _joinUnique(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final v in values)
        if (v.trim().isNotEmpty && seen.add(v.trim())) v.trim()
    ].join('、');
  }

  double? _parseWeightCell(String text) {
    final trimmed = _normalizeSyllabusText(text);
    final value = double.tryParse(trimmed);
    if (value != null && value > 0 && value <= 1) return value;
    return null;
  }

  _FullAndRatio? _parseFullAndRatio(String text) {
    final normalized = _normalizeSyllabusText(text);
    final m = RegExp(
            r'^\s*(\d+(?:\.\d+)?)\s*(?:[(]\s*(\d+(?:\.\d+)?)\s*%\s*[)])?\s*$')
        .firstMatch(normalized);
    if (m == null) return null;
    final full = double.tryParse(m.group(1)!);
    if (full == null) return null;
    final ratioValue = m.group(2) != null ? double.tryParse(m.group(2)!) : null;
    return _FullAndRatio(full, ratioValue == null ? null : ratioValue / 100.0);
  }

  double? _parsePercent(String text) {
    final normalized = _normalizeSyllabusText(text);
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(normalized);
    if (m == null) return null;
    final value = double.tryParse(m.group(1)!);
    return value == null ? null : value / 100.0;
  }

  String? _extractCourseNameFromDocx(XmlDocument doc) {
    for (final p in doc.findAllElements('w:p')) {
      final text = _normalizeSyllabusText(
          p.findAllElements('w:t').map((t) => t.innerText).join());
      if (text.isEmpty) continue;
      final title = RegExp(r'《([^》]+)》\s*教学大纲').firstMatch(text);
      if (title != null) return title.group(1)!.trim();
      final named = RegExp(r'课程名称[:：]\s*([^,，;；\s]+)').firstMatch(text);
      if (named != null) return named.group(1)!.trim();
    }
    return null;
  }

  /// 把 parseSyllabus / parseWordSyllabus 的结果转成 course_objectives 行。
  /// 合并 objectives(描述/指标点) 与 weights(权重/各环节满分)。
  List<Map<String, dynamic>> syllabusToObjectiveRows(
      Map<String, dynamic> parsed) {
    final objectives = (parsed['objectives'] as List?) ?? const [];
    final weights = (parsed['weights'] as List?) ?? const [];
    final byIdx = <int, Map<String, dynamic>>{};

    for (final w in weights) {
      final idx = (w['objective'] as num).toInt();
      byIdx[idx] = {
        'idx': idx,
        'name': '课程目标$idx',
        'indicator':
            _extractIndicator((w['requirement'] as String?) ?? '') ?? '',
        'weight': (w['weight'] as num?)?.toDouble() ?? 0,
        'full_mark': (w['full_mark'] as num?)?.toDouble() ??
            (w['exam_full'] as num?)?.toDouble() ??
            (w['pingshi_full'] as num?)?.toDouble() ??
            0,
        'pingshi_ratio': (w['pingshi_ratio'] as num?)?.toDouble() ?? 0.20,
        'experiment_ratio': (w['experiment_ratio'] as num?)?.toDouble() ?? 0.30,
        'exam_ratio': (w['exam_ratio'] as num?)?.toDouble() ?? 0.50,
        'assessment_items_json': (w['assessment_items_json'] ?? '').toString(),
      };
    }
    for (final o in objectives) {
      final idx = int.tryParse(o['num']?.toString() ?? '') ?? 0;
      if (idx == 0) continue;
      final row =
          byIdx.putIfAbsent(idx, () => {'idx': idx, 'name': '课程目标$idx'});
      row['description'] = o['objective'];
      if ((row['indicator'] as String?)?.isEmpty ?? true) {
        row['indicator'] =
            _extractIndicator((o['requirement'] as String?) ?? '') ?? '';
      }
    }
    // 合并期末考核评价内容 → assess_content
    final assessContents = (parsed['assessContents'] as List?) ?? const [];
    for (final a in assessContents) {
      final idx = (a['objective'] as num?)?.toInt() ?? 0;
      if (idx == 0) continue;
      final row =
          byIdx.putIfAbsent(idx, () => {'idx': idx, 'name': '课程目标$idx'});
      if (a['content'] != null) row['assess_content'] = a['content'];
      if (a['pingshi_standard'] != null) {
        row['pingshi_standard'] = a['pingshi_standard'];
      }
      if (a['experiment_standard'] != null) {
        row['experiment_standard'] = a['experiment_standard'];
      }
    }
    // 合并映射表字段（实验/章节→目标）
    void mergeMapToField(String mapKey, String field) {
      final m = (parsed[mapKey] as Map<String, dynamic>?) ?? {};
      for (final e in m.entries) {
        final idx = int.tryParse(e.key) ?? 0;
        if (idx == 0) continue;
        final row =
            byIdx.putIfAbsent(idx, () => {'idx': idx, 'name': '课程目标$idx'});
        row[field] = e.value.toString();
      }
    }

    mergeMapToField('experimentMap', 'experiments');
    mergeMapToField('chapterMap', 'chapters');
    final rows = byIdx.values
        .where((r) =>
            ((r['idx'] as int?) ?? 0) >= 1 && ((r['idx'] as int?) ?? 0) <= 4)
        .toList()
      ..sort((a, b) => (a['idx'] as int).compareTo(b['idx'] as int));
    return rows;
  }

  /// 用确定性解析结果兜底，AI 结果只补充缺失字段，避免 AI 把权重/满分清空。
  List<Map<String, dynamic>> mergeSyllabusRows(
    List<Map<String, dynamic>> deterministicRows,
    List<Map<String, dynamic>> aiRows,
  ) {
    if (deterministicRows.isEmpty) return aiRows;
    final byIdx = <int, Map<String, dynamic>>{
      for (final row in deterministicRows)
        ((row['idx'] as num?)?.toInt() ?? 0): Map<String, dynamic>.from(row)
    }..remove(0);

    bool isEmptyValue(Object? value) {
      if (value == null) return true;
      if (value is num) return value == 0;
      return value.toString().trim().isEmpty;
    }

    const fillOnlyFields = [
      'description',
      'indicator',
      'chapters',
      'experiments',
      'assess_content',
      'pingshi_standard',
      'experiment_standard',
    ];
    for (final ai in aiRows) {
      final idx = (ai['idx'] as num?)?.toInt() ?? 0;
      if (idx == 0) continue;
      final row =
          byIdx.putIfAbsent(idx, () => {'idx': idx, 'name': '课程目标$idx'});
      for (final field in fillOnlyFields) {
        if (isEmptyValue(row[field]) && !isEmptyValue(ai[field])) {
          row[field] = ai[field];
        }
      }
      for (final field in ['weight', 'full_mark']) {
        if (isEmptyValue(row[field]) && !isEmptyValue(ai[field])) {
          row[field] = ai[field];
        }
      }
    }
    return byIdx.values.toList()
      ..sort((a, b) => (a['idx'] as int).compareTo(b['idx'] as int));
  }

  Future<List<double>> _resolveFullMarks(Database db, int batchId) async {
    final batch = await db.query('achievement_batches',
        columns: ['course_name'], where: 'id = ?', whereArgs: [batchId]);
    final courseName = batch.isNotEmpty
        ? (batch.first['course_name'] ?? '移动应用开发').toString()
        : '移动应用开发';
    final rows = await db.query('course_objectives',
        where: 'course_name = ?', whereArgs: [courseName], orderBy: 'idx ASC');
    if (rows.isNotEmpty) {
      final marks = List<double>.filled(4, 0);
      var hasMark = false;
      for (final r in rows) {
        final idx = (r['idx'] as num?)?.toInt() ?? 0;
        final mark = (r['full_mark'] as num?)?.toDouble() ?? 0;
        if (idx >= 1 && idx <= 4 && mark > 0) {
          marks[idx - 1] = mark;
          hasMark = true;
        }
      }
      if (hasMark) return marks;
    }
    return AchievementConfig.defaults.fullMarks;
  }

  /// 导入学生成绩到数据库
  Future<int> importToDatabase(
      int batchId, List<Map<String, dynamic>> grades) async {
    final db = await DatabaseHelper.instance.database;
    final fm = await _resolveFullMarks(db, batchId);
    final now = DateTime.now().toIso8601String();
    int count = 0;

    // 单事务批量写入：避免每行一次 fsync/commit（N 行 → 1 次提交）
    await db.transaction((txn) async {
      for (final g in grades) {
        final studentId = g['student_id'] as String;
        if (studentId.isEmpty) continue;

        final obj1 = (g['obj1_score'] as num?)?.toDouble() ?? 0;
        final obj2 = (g['obj2_score'] as num?)?.toDouble() ?? 0;
        final obj3 = (g['obj3_score'] as num?)?.toDouble() ?? 0;
        final obj4 = (g['obj4_score'] as num?)?.toDouble() ?? 0;
        final total = (g['total_score'] as num?)?.toDouble() ??
            (obj1 + obj2 + obj3 + obj4);
        double achOrScore(Object? achievement, double score, double fullMark) {
          final direct = (achievement as num?)?.toDouble();
          if (direct != null) return direct.clamp(0.0, 1.0);
          return fullMark > 0 ? (score / fullMark).clamp(0.0, 1.0) : 0.0;
        }

        final ach1 = (g['obj1_achievement'] as num?)?.toDouble() ??
            achOrScore(null, obj1, fm[0]);
        final ach2 = (g['obj2_achievement'] as num?)?.toDouble() ??
            achOrScore(null, obj2, fm[1]);
        final ach3 = (g['obj3_achievement'] as num?)?.toDouble() ??
            achOrScore(null, obj3, fm[2]);
        final ach4 = (g['obj4_achievement'] as num?)?.toDouble() ??
            achOrScore(null, obj4, fm[3]);

        try {
          await txn.insert(
            'achievement_scores',
            {
              'batch_id': batchId,
              'student_id': studentId,
              'student_name': g['student_name'] ?? '',
              'obj1_score': obj1,
              'obj1_achievement': ach1.clamp(0.0, 1.0),
              'obj2_score': obj2,
              'obj2_achievement': ach2.clamp(0.0, 1.0),
              'obj3_score': obj3,
              'obj3_achievement': ach3.clamp(0.0, 1.0),
              'obj4_score': obj4,
              'obj4_achievement': ach4.clamp(0.0, 1.0),
              'total_score': total,
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          count++;
        } catch (e, st) {
          swallowDebug(e, tag: 'ExcelImport.$studentId', stack: st);
        }
      }
    });

    return count;
  }

  /// 生成成绩导入模板。
  ///
  /// 新模板由大纲/对照表驱动：每个实际存在的考核项生成一列，缺失的项
  /// （例如英语课没有实验）不生成、不显示、不参与后续计算。旧三 sheet
  /// 模板解析仍保留在 [parseComponentSheets] 中用于兼容历史文件。
  List<int> buildGradeTemplate({
    List<Map<String, dynamic>> students = const [],
    AchievementConfig? config,
    List<Map<String, dynamic>> objectiveRows = const [],
  }) {
    final cfg = config ?? AchievementConfig.defaults;
    final objectiveItems = _assessmentItemsFromRows(objectiveRows);
    final activeItems = objectiveItems.isNotEmpty
        ? objectiveItems
        : _assessmentItemsFromConfig(cfg);
    final fullMarks = objectiveRows.isNotEmpty
        ? _fullMarksFromRows(objectiveRows)
        : cfg.fullMarks;

    final excel = xl.Excel.createExcel();
    // 删除默认 Sheet1，最终只输出动态模板 sheet。
    for (final name in excel.tables.keys.toList()) {
      excel.delete(name);
    }

    final sheet = excel['成绩录入'];
    sheet.appendRow([
      xl.TextCellValue('学号'),
      xl.TextCellValue('姓名'),
      for (final item in activeItems)
        xl.TextCellValue(
          '${item.label}-课程目标${item.objective}-比例${(item.ratio * 100).toStringAsFixed(0)}%',
        ),
    ]);

    // 预填学生名单（学号/姓名），成绩列留空待教师填写。每个成绩单元格填 0-100。
    for (final s in students) {
      final id = (s['student_id'] ?? s['user_id'] ?? '').toString();
      final name = (s['student_name'] ?? s['real_name'] ?? '').toString();
      if (id.isEmpty) continue;
      sheet.appendRow([xl.TextCellValue(id), xl.TextCellValue(name)]);
    }

    final matrix = excel['大纲对照表'];
    matrix.appendRow([
      xl.TextCellValue('课程目标'),
      xl.TextCellValue('指标点'),
      xl.TextCellValue('目标权重'),
      xl.TextCellValue('目标满分'),
      xl.TextCellValue('考核项'),
      xl.TextCellValue('考核项比例'),
    ]);
    for (var i = 0; i < 4; i++) {
      final objective = i + 1;
      final items = activeItems.where((item) => item.objective == objective);
      if (items.isEmpty && fullMarks[i] <= 0) continue;
      for (final item in items) {
        matrix.appendRow([
          xl.TextCellValue('课程目标$objective'),
          xl.TextCellValue(i < cfg.indicators.length ? cfg.indicators[i] : ''),
          xl.DoubleCellValue(i < cfg.weights.length ? cfg.weights[i] : 0),
          xl.DoubleCellValue(i < fullMarks.length ? fullMarks[i] : 0),
          xl.TextCellValue(item.label),
          xl.TextCellValue('${(item.ratio * 100).toStringAsFixed(0)}%'),
        ]);
      }
    }

    return excel.save() ?? <int>[];
  }

  List<double> _fullMarksFromRows(List<Map<String, dynamic>> rows) {
    final marks = List<double>.filled(4, 0);
    for (final row in rows) {
      final idx = (row['idx'] as num?)?.toInt() ?? 0;
      if (idx < 1 || idx > 4) continue;
      marks[idx - 1] = (row['full_mark'] as num?)?.toDouble() ?? 0;
    }
    return marks;
  }

  List<_TemplateAssessmentItem> _assessmentItemsFromRows(
      List<Map<String, dynamic>> rows) {
    final items = <_TemplateAssessmentItem>[];
    for (final row in rows) {
      final idx = (row['idx'] as num?)?.toInt() ?? 0;
      if (idx < 1 || idx > 4) continue;
      final rawJson = (row['assessment_items_json'] ?? '').toString();
      if (rawJson.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(rawJson) as List;
          for (final item in parsed) {
            final map = item as Map;
            final label = (map['label'] ?? '').toString().trim();
            final ratio = (map['ratio'] as num?)?.toDouble() ?? 0;
            if (label.isEmpty || ratio <= 0) continue;
            items.add(_TemplateAssessmentItem(
              label: label,
              kind: (map['kind'] ?? _assessmentKind(label)).toString(),
              objective: idx,
              ratio: ratio,
            ));
          }
          continue;
        } catch (e, st) {
          swallowDebug(e,
              tag: 'AchievementExcel.assessmentItemsFromRows', stack: st);
        }
      }

      final ratios = {
        '平时成绩': (row['pingshi_ratio'] as num?)?.toDouble() ?? 0,
        '实验成绩': (row['experiment_ratio'] as num?)?.toDouble() ?? 0,
        '考核成绩': (row['exam_ratio'] as num?)?.toDouble() ?? 0,
      };
      final sum = ratios.values.fold<double>(0, (a, b) => a + b);
      if (sum <= 0) continue;
      for (final entry in ratios.entries) {
        if (entry.value <= 0) continue;
        items.add(_TemplateAssessmentItem(
          label: entry.key,
          kind: _assessmentKind(entry.key),
          objective: idx,
          ratio: entry.value / sum,
        ));
      }
    }
    return items;
  }

  List<_TemplateAssessmentItem> _assessmentItemsFromConfig(
      AchievementConfig cfg) {
    final p = cfg.assessmentWeights['平时'] ?? 0.20;
    final e = cfg.assessmentWeights['实验'] ?? 0.30;
    final x = cfg.assessmentWeights['期末'] ?? 0.50;
    final items = <_TemplateAssessmentItem>[];
    for (var i = 0; i < 4; i++) {
      if (i < cfg.fullMarks.length && cfg.fullMarks[i] <= 0) continue;
      if (p > 0) {
        items.add(_TemplateAssessmentItem(
            label: '平时成绩', kind: 'pingshi', objective: i + 1, ratio: p));
      }
      if (e > 0) {
        items.add(_TemplateAssessmentItem(
            label: '实验成绩', kind: 'experiment', objective: i + 1, ratio: e));
      }
      if (x > 0) {
        items.add(_TemplateAssessmentItem(
            label: '考核成绩', kind: 'exam', objective: i + 1, ratio: x));
      }
    }
    return items;
  }
}

class _FullAndRatio {
  const _FullAndRatio(this.full, this.ratio);

  final double full;
  final double? ratio;
}

class _TemplateAssessmentItem {
  const _TemplateAssessmentItem({
    required this.label,
    required this.kind,
    required this.objective,
    required this.ratio,
  });

  final String label;
  final String kind;
  final int objective;
  final double ratio;
}
