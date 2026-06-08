import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
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

  /// 从字节数组解析 Excel
  List<Map<String, dynamic>> parseGradeBytes(Uint8List bytes) {
    final excel = xl.Excel.decodeBytes(bytes);
    final results = <Map<String, dynamic>>[];

    // 读取第一个 sheet（通常是总评成绩表）
    if (excel.tables.isEmpty) return results;
    final sheet = excel.tables.keys.first;
    final table = excel.tables[sheet]!;

    // 跳过表头行，从第2行开始读取学生数据
    int startRow = 0;
    for (int i = 0; i < table.rows.length && i < 5; i++) {
      final row = table.rows[i];
      final cells = row.map((c) => c?.value?.toString() ?? '').toList();
      // 查找包含"学号"或"姓名"的表头行
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

  Map<String, dynamic> _extractGrade(List<String> cells, String id, String name) {
    // 尝试智能解析列结构
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

  /// 从 Excel 解析教学大纲（支持 MD 文件和 Excel 文件）
  Future<Map<String, dynamic>> parseSyllabus(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return {'error': '文件不存在'};
    }

    final ext = filePath.split('.').last.toLowerCase();
    if (ext == 'md') {
      return _parseMarkdownSyllabus(await file.readAsString());
    } else if (ext == 'xlsx' || ext == 'xls') {
      return _parseExcelSyllabus(await file.readAsBytes());
    }

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
    return {'note': 'Excel 大纲解析待完善'};
  }

  /// 导入学生成绩到数据库
  Future<int> importToDatabase(int batchId, List<Map<String, dynamic>> grades) async {
    final db = await DatabaseHelper.instance.database;
    int count = 0;

    for (final g in grades) {
      final studentId = g['student_id'] as String;
      if (studentId.isEmpty) continue;

      // 计算达成度 (满分100)
      final obj1 = (g['obj1_score'] as double?) ?? 0;
      final obj2 = (g['obj2_score'] as double?) ?? 0;
      final obj3 = (g['obj3_score'] as double?) ?? 0;
      final obj4 = (g['obj4_score'] as double?) ?? 0;
      final total = (g['total_score'] as double?) ?? (obj1 + obj2 + obj3 + obj4);

      // 满分读自单一来源 config（与大纲 15/25/30/30 一致），不再硬编码 100
      final fm = AchievementConfig.defaults.fullMarks;

      try {
        await db.insert(
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
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        count++;
      } catch (e, st) {
        swallowDebug(e, tag: 'ExcelImport.$studentId', stack: st);
      }
    }

    return count;
  }
}
