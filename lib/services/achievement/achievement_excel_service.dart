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
      if (studentId.contains('合计') || studentId.contains('平均') || studentId.contains('备注')) continue;

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
      final cells = table.rows[i].map((c) => c?.value?.toString() ?? '').toList();
      if (cells.isNotEmpty && cells[0].trim() == '学号') {
        headerRow = i;
        break;
      }
    }
    if (headerRow < 0) return results;

    final fm = AchievementConfig.defaults.fullMarks;
    const achCols = [5, 9, 13, 17];
    for (int i = headerRow + 1; i < table.rows.length; i++) {
      final cells = table.rows[i].map((c) => c?.value?.toString() ?? '').toList();
      if (cells.length < 18) continue;
      final sid = cells[0].trim();
      if (sid.isEmpty || sid.contains('合计') || sid.contains('平均') || sid.contains('备注')) continue;
      final name = cells.length > 1 ? cells[1].trim() : '';
      final ach = List<double>.generate(
          4, (k) => double.tryParse(cells[achCols[k]].trim())?.clamp(0.0, 1.0) ?? 0.0);
      results.add({
        'student_id': sid,
        'student_name': name,
        'obj1_score': ach[0] * fm[0],
        'obj2_score': ach[1] * fm[1],
        'obj3_score': ach[2] * fm[2],
        'obj4_score': ach[3] * fm[3],
        'total_score': ach[0] * fm[0] + ach[1] * fm[1] + ach[2] * fm[2] + ach[3] * fm[3],
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
  /// - 期末：学号0 姓名1 | 项目2 小组4 个人6 答辩8
  Map<String, List<Map<String, dynamic>>> parseComponentSheets(Uint8List bytes) {
    final excel = xl.Excel.decodeBytes(bytes);
    final out = <String, List<Map<String, dynamic>>>{
      'pingshi': [],
      'experiment': [],
      'exam': [],
    };
    if (excel.tables.isEmpty) return out;

    for (final key in excel.tables.keys) {
      final table = excel.tables[key]!;
      // 用 sheet 名识别类型（含「平时」「实验」「期末」）
      if (key.contains('平时')) {
        out['pingshi'] = _parsePingshiSheet(table);
      } else if (key.contains('实验')) {
        out['experiment'] = _parseExperimentSheet(table);
      } else if (key.contains('期末') || key.contains('考核')) {
        out['exam'] = _parseExamSheet(table);
      }
    }
    return out;
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
      'pingshi': ['class_activity_score', 'quiz_homework_score', 'extra_learning_score'],
      'experiment': ['exp1_score', 'exp2_score', 'exp3_score', 'exp4_score', 'exp5_score', 'exp6_score', 'exp7_score'],
      'exam': ['project_score', 'group_score', 'individual_score', 'defense_score'],
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
        final present = rows.map((r) => (r['student_id'] ?? '').toString()).toSet();
        final miss = rosterIds.difference(present).toList()..sort();
        if (miss.isNotEmpty) missing[env] = miss;
      }

      // 异常分值（0-100 之外）
      for (final r in rows) {
        final id = (r['student_id'] ?? '').toString();
        for (final f in scoreFields[env]!) {
          final v = (r[f] as num?)?.toDouble();
          if (v != null && (v < 0 || v > 100)) {
            outOfRange.add({'env': env, 'student_id': id, 'field': f, 'value': v});
          }
        }
      }
    }

    final ok = sheetsFound.isNotEmpty && outOfRange.isEmpty && duplicates.isEmpty;
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
    final simple = headerC2.contains('课堂');
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
        'group_score': _cell(row, 4),
        'individual_score': _cell(row, 6),
        'defense_score': _cell(row, 8),
      });
    }
    return rows;
  }


  Map<String, dynamic> _extractGrade(List<String> cells, String id, String name) {
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
        final doc = archive.files.firstWhere((f) => f.name == 'word/document.xml');
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
阅读以下《移动应用开发》课程教学大纲，提取每个课程目标的信息。
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
        [{'role': 'user', 'content': prompt}],
        systemPrompt: system,
      );
      final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
      if (match == null) return [];
      final list = (jsonDecode(match.group(0)!) as List).cast<Map<String, dynamic>>();
      // 规范化字段
      return list.map((o) {
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
          'experiment_standard': (o['experiment_standard'] ?? '').toString(),
        };
      }).where((o) => (o['idx'] as int) > 0).toList()
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
        final match = RegExp(r'\|\s*(\d)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|').firstMatch(line);
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
          r'\|\s*课程目标\s*(\d)\s*\|\s*([\d.]+)\s*\|.*?\|\s*(\d+)\s*.*?\|\s*(\d+)\s*.*?\|\s*(\d+)\s*.*?\|').firstMatch(line);
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
        final m = RegExp(r'\|\s*课程目标\s*(\d)[^|]*\|\s*([^|]+?)\s*\|')
            .firstMatch(line);
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
        inExpTable = true; continue;
      }
      if (inExpTable) {
        final m = RegExp(r'\|\s*(\d+)\s*\|.+?\|\s*(\d+(?:[-]\d+)?)\s*\|').firstMatch(line);
        if (m != null) {
          final expNum = int.tryParse(m.group(1)!) ?? 0;
          final targetStr = m.group(2)!;
          if (targetStr.contains('-')) {
            final range = targetStr.split('-');
            final start = int.tryParse(range[0]) ?? 0;
            final end = int.tryParse(range[1]) ?? start;
            for (int t = start; t <= end; t++) expMap.putIfAbsent(t, () => []).add('实验$expNum');
          } else {
            final t = int.tryParse(targetStr) ?? 0;
            if (t > 0) expMap.putIfAbsent(t, () => []).add('实验$expNum');
          }
        }
        if (line.trim().isEmpty && expMap.isNotEmpty) inExpTable = false;
      }
    }
    result['experimentMap'] = expMap.map((k, v) => MapEntry(k.toString(), v.join('、')));

    // 章节/教学安排表（|章节|...|对应课程目标|）
    final chMap = <int, List<String>>{};
    var inChTable = false;
    for (final line in lines) {
      if (line.contains('章节') && (line.contains('教学内容') || line.contains('对应课程目标'))) {
        inChTable = true; continue;
      }
      if (inChTable) {
        final m = RegExp(r'\|\s*(\d+)\s*\|.+?\|\s*目标\s*(\d+(?:[-]\d+)?)\s*\|').firstMatch(line);
        if (m != null) {
          final chNum = int.tryParse(m.group(1)!) ?? 0;
          final targetStr = m.group(2)!;
          if (targetStr.contains('-')) {
            final range = targetStr.split('-');
            final start = int.tryParse(range[0]) ?? 0;
            final end = int.tryParse(range[1]) ?? start;
            for (int t = start; t <= end; t++) chMap.putIfAbsent(t, () => []).add('第${chNum}章');
          } else {
            final t = int.tryParse(targetStr) ?? 0;
            if (t > 0) chMap.putIfAbsent(t, () => []).add('第${chNum}章');
          }
        }
        if (line.trim().isEmpty && chMap.isNotEmpty) inChTable = false;
      }
    }
    result['chapterMap'] = chMap.map((k, v) => MapEntry(k.toString(), v.join('、')));

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
      for (final tbl in doc.findAllElements('w:tbl')) {
        for (final tr in tbl.findAllElements('w:tr')) {
          final cells = <String>[];
          for (final tc in tr.findAllElements('w:tc')) {
            final text = tc
                .findAllElements('w:t')
                .map((t) => t.innerText)
                .join()
                .trim();
            cells.add(text);
          }
          if (cells.isEmpty) continue;
          // 权重对照表行：以「课程目标N」开头，第2列是权重小数
          final m = RegExp(r'课程目标\s*(\d)').firstMatch(cells[0]);
          if (m != null && cells.length >= 2) {
            final w = double.tryParse(cells[1].replaceAll(RegExp(r'[^\d.]'), ''));
            if (w != null && w > 0 && w <= 1) {
              weights.add({
                'objective': int.parse(m.group(1)!),
                'weight': w,
                'requirement': cells.length > 2 ? cells[2] : '',
                'pingshi_full': _extractFull(cells, 3),
                'experiment_full': _extractFull(cells, 4),
                'exam_full': _extractFull(cells, 5),
              });
            }
          }
        }
      }
      return {'objectives': objectives, 'weights': weights};
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementExcel.parseWord', stack: st);
      return {'error': 'Word 大纲解析失败: $e'};
    }
  }

  int _extractFull(List<String> cells, int i) {
    if (i >= cells.length) return 0;
    final m = RegExp(r'(\d+)').firstMatch(cells[i]);
    return m != null ? int.parse(m.group(1)!) : 0;
  }

  /// 把 parseSyllabus / parseWordSyllabus 的结果转成 course_objectives 行。
  /// 合并 objectives(描述/指标点) 与 weights(权重/各环节满分)。
  List<Map<String, dynamic>> syllabusToObjectiveRows(Map<String, dynamic> parsed) {
    final objectives = (parsed['objectives'] as List?) ?? const [];
    final weights = (parsed['weights'] as List?) ?? const [];
    final byIdx = <int, Map<String, dynamic>>{};

    for (final w in weights) {
      final idx = (w['objective'] as num).toInt();
      byIdx[idx] = {
        'idx': idx,
        'name': '课程目标$idx',
        'indicator': (w['requirement'] as String?)?.replaceAll(RegExp(r'[^\d.]'), '') ?? '',
        'weight': (w['weight'] as num?)?.toDouble() ?? 0,
        'full_mark': (w['exam_full'] as num?)?.toDouble() ??
            (w['pingshi_full'] as num?)?.toDouble() ?? 0,
        'pingshi_ratio': 0.20,
        'experiment_ratio': 0.30,
        'exam_ratio': 0.50,
      };
    }
    for (final o in objectives) {
      final idx = int.tryParse(o['num']?.toString() ?? '') ?? 0;
      if (idx == 0) continue;
      final row = byIdx.putIfAbsent(idx, () => {'idx': idx, 'name': '课程目标$idx'});
      row['description'] = o['objective'];
      if ((row['indicator'] as String?)?.isEmpty ?? true) {
        row['indicator'] = (o['requirement'] as String?)
                ?.replaceAll(RegExp(r'[^\d.]'), '') ??
            '';
      }
    }
    // 合并期末考核评价内容 → assess_content
    final assessContents = (parsed['assessContents'] as List?) ?? const [];
    for (final a in assessContents) {
      final idx = (a['objective'] as num?)?.toInt() ?? 0;
      if (idx == 0) continue;
      final row = byIdx.putIfAbsent(idx, () => {'idx': idx, 'name': '课程目标$idx'});
      row['assess_content'] = a['content'];
    }
    // 合并映射表字段（实验/章节→目标）
    void mergeMapToField(String mapKey, String field) {
      final m = (parsed[mapKey] as Map<String, dynamic>?) ?? {};
      for (final e in m.entries) {
        final idx = int.tryParse(e.key) ?? 0;
        if (idx == 0) continue;
        final row = byIdx.putIfAbsent(idx, () => {'idx': idx, 'name': '课程目标$idx'});
        row[field] = e.value.toString();
      }
    }
    mergeMapToField('experimentMap', 'experiments');
    mergeMapToField('chapterMap', 'chapters');
    final rows = byIdx.values
        .where((r) => ((r['idx'] as int?) ?? 0) >= 1 && ((r['idx'] as int?) ?? 0) <= 4)
        .toList()
      ..sort((a, b) => (a['idx'] as int).compareTo(b['idx'] as int));
    return rows;
  }

  /// 导入学生成绩到数据库
  Future<int> importToDatabase(int batchId, List<Map<String, dynamic>> grades) async {
    final db = await DatabaseHelper.instance.database;
    final fm = AchievementConfig.defaults.fullMarks;
    final now = DateTime.now().toIso8601String();
    int count = 0;

    // 单事务批量写入：避免每行一次 fsync/commit（N 行 → 1 次提交）
    await db.transaction((txn) async {
      for (final g in grades) {
        final studentId = g['student_id'] as String;
        if (studentId.isEmpty) continue;

        final obj1 = (g['obj1_score'] as double?) ?? 0;
        final obj2 = (g['obj2_score'] as double?) ?? 0;
        final obj3 = (g['obj3_score'] as double?) ?? 0;
        final obj4 = (g['obj4_score'] as double?) ?? 0;
        final total = (g['total_score'] as double?) ?? (obj1 + obj2 + obj3 + obj4);

        try {
          await txn.insert(
            'achievement_scores',
            {
              'batch_id': batchId,
              'student_id': studentId,
              'student_name': g['student_name'] ?? '',
              'obj1_score': obj1,
              'obj1_achievement': (obj1 / fm[0]).clamp(0.0, 1.0),
              'obj2_score': obj2,
              'obj2_achievement': (obj2 / fm[1]).clamp(0.0, 1.0),
              'obj3_score': obj3,
              'obj3_achievement': (obj3 / fm[2]).clamp(0.0, 1.0),
              'obj4_score': obj4,
              'obj4_achievement': (obj4 / fm[3]).clamp(0.0, 1.0),
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

  /// 生成成绩导入模板（.xlsx，3 个 sheet：平时成绩/实验成绩/期末成绩）。
  /// 列布局与 parseComponentSheets 的简洁模板分支严格对齐，表头标注每列支撑的
  /// 课程目标，体现大纲驱动的目标拆分。可选传入 [students] 预填学号/姓名名单。
  ///
  /// 目标拆分（以大纲为准）：
  /// - 平时：课堂表现→目标1，期间测验→目标2，课外学习→目标3+4
  /// - 实验：实验1,2→目标1，实验3,4→目标2，实验5→目标3，实验6→目标1-4
  /// - 期末：项目→目标1，小组→目标2，个人→目标3，答辩→目标4
  List<int> buildGradeTemplate({
    List<Map<String, dynamic>> students = const [],
    AchievementConfig? config,
  }) {
    final cfg = config ?? AchievementConfig.defaults;
    final excel = xl.Excel.createExcel();
    // 删除默认 Sheet1，最终输出 3 个 sheet
    for (final name in excel.tables.keys.toList()) {
      excel.delete(name);
    }

    String ind(int i) => i < cfg.indicators.length ? cfg.indicators[i] : '';

    // ── 平时：课堂表现(20→目标1) / 期间测验(30→目标2) / 课外学习(50→目标3,4) ──
    final ps = excel['平时成绩'];
    ps.appendRow([
      xl.TextCellValue('学号'),
      xl.TextCellValue('姓名'),
      xl.TextCellValue('课堂表现 满分20（目标1·${ind(0)}）'),
      xl.TextCellValue('期间测验 满分30（目标2·${ind(1)}）'),
      xl.TextCellValue('课外学习 满分50（目标3·${ind(2)}、目标4·${ind(3)}）'),
    ]);
    ps.appendRow([
      xl.TextCellValue(''),
      xl.TextCellValue('得分(百分制)'),
      xl.TextCellValue(''),
      xl.TextCellValue(''),
      xl.TextCellValue(''),
    ]);

    // ── 实验：6次实验 1,2→目标1 / 3,4→目标2 / 5→目标3 / 6→目标1-4 ──
    final es = excel['实验成绩'];
    es.appendRow([
      xl.TextCellValue('学号'),
      xl.TextCellValue('姓名'),
      xl.TextCellValue('实验1得分（目标1）'),
      xl.TextCellValue('实验2得分（目标1）'),
      xl.TextCellValue('实验3得分（目标2）'),
      xl.TextCellValue('实验4得分（目标2）'),
      xl.TextCellValue('实验5得分（目标3）'),
      xl.TextCellValue('实验6得分（目标1-4·综合）'),
    ]);

    // ── 期末成绩：项目(目标1)/小组(目标2)/个人(目标3)/答辩(目标4) ──
    final xs = excel['期末成绩'];
    xs.appendRow([
      xl.TextCellValue('学号'),
      xl.TextCellValue('姓名'),
      xl.TextCellValue('项目得分（目标1·满分100）'),
      xl.TextCellValue('小组得分（目标2·满分100）'),
      xl.TextCellValue('个人得分（目标3·满分100）'),
      xl.TextCellValue('答辩得分（目标4·满分100）'),
    ]);

    // 预填学生名单（学号/姓名），成绩列留空待教师填写
    for (final s in students) {
      final id = (s['student_id'] ?? s['user_id'] ?? '').toString();
      final name = (s['student_name'] ?? s['real_name'] ?? '').toString();
      if (id.isEmpty) continue;
      ps.appendRow([xl.TextCellValue(id), xl.TextCellValue(name)]);
      es.appendRow([xl.TextCellValue(id), xl.TextCellValue(name)]);
      xs.appendRow([xl.TextCellValue(id), xl.TextCellValue(name)]);
    }

    return excel.save() ?? <int>[];
  }
}
