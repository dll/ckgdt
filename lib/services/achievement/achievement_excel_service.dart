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
    final rows = <Map<String, dynamic>>[];
    for (int i = hr + 1; i < table.rows.length; i++) {
      final row = table.rows[i];
      final sid = _cellStr(row, 0);
      if (!_isDataRow(sid)) continue;
      rows.add({
        'student_id': sid,
        'student_name': _cellStr(row, 1),
        'class_activity_score': _cell(row, 13), // 课堂表现最后得分
        'quiz_homework_score': _cell(row, 25), // 期间测验平均分
        'extra_learning_score': _cell(row, 36), // 大作业平均分
      });
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseExperimentSheet(xl.Sheet table) {
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
        'exp1_score': _cell(row, 2),
        'exp2_score': _cell(row, 3),
        'exp3_score': _cell(row, 5),
        'exp4_score': _cell(row, 6),
        'exp5_score': _cell(row, 8),
        'exp6_score': _cell(row, 9),
        'exp7_score': _cell(row, 11),
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
    final rows = byIdx.values.toList()
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
}
