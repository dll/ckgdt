import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import '../../core/error_handler.dart';
import '../data/local/workload_dao.dart';

/// 工作量 Excel 导入/导出服务。
///
/// - [exportTemplate] 生成空白申报模板（含表头与示例行），供教师填写后导入。
/// - [exportResult] 导出当前课程工作量结果（课程工作量 + 其他工作量）。
/// - [importExcel] 从 Excel 读取工作量申报，写入数据库（关联当前课程）。
class WorkloadExcelService {
  static const List<String> courseHeaders = [
    '教师工号',
    '姓名',
    '部门',
    '课程序号',
    '课程编号',
    '课程名称',
    '课程类别',
    '教学班',
    '上课形式',
    '课程性质',
    '学分',
    '学生人数',
    '课时数',
    '课程系数',
    '规模系数',
    '教师申报工作量',
    '工作量类型',
    '备注',
  ];

  static const List<String> otherHeaders = [
    '教师工号',
    '姓名',
    '部门',
    '工作量类型',
    '其他工作量类别',
    '超课时工作量项目名称',
    '教师申报工作量',
    '备注',
  ];

  /// 生成申报模板（含两张表：课程工作量 / 其他工作量）。
  Uint8List exportTemplate() {
    final excel = xl.Excel.createExcel();
    for (final n in excel.tables.keys.toList()) {
      excel.delete(n);
    }

    final courseSheet = excel['课程工作量'];
    courseSheet.appendRow(courseHeaders.map(xl.TextCellValue.new).toList());
    // 示例行
    courseSheet.appendRow([
      xl.TextCellValue('419116'),
      xl.TextCellValue('管理员'),
      xl.TextCellValue('计算机学院'),
      xl.TextCellValue('1'),
      xl.TextCellValue('CKGDT'),
      xl.TextCellValue('课程知识图谱与数字孪生'),
      xl.TextCellValue('专业基础课'),
      xl.TextCellValue('软件23'),
      xl.TextCellValue('合班'),
      xl.TextCellValue('理论'),
      const xl.DoubleCellValue(3.0),
      const xl.IntCellValue(5),
      const xl.IntCellValue(32),
      const xl.DoubleCellValue(1.0),
      const xl.DoubleCellValue(1.21),
      const xl.DoubleCellValue(38.72),
      xl.TextCellValue('理论工作量'),
      xl.TextCellValue(''),
    ]);

    final otherSheet = excel['其他工作量'];
    otherSheet.appendRow(otherHeaders.map(xl.TextCellValue.new).toList());
    otherSheet.appendRow([
      xl.TextCellValue('419116'),
      xl.TextCellValue('管理员'),
      xl.TextCellValue('计算机学院'),
      xl.TextCellValue('其他工作量'),
      xl.TextCellValue('监考工作量'),
      xl.TextCellValue('期末考试监考'),
      const xl.DoubleCellValue(4.0),
      xl.TextCellValue(''),
    ]);

    return Uint8List.fromList(excel.save()!);
  }

  /// 导出当前课程工作量结果。
  Uint8List exportResult(
    List<TeachingWorkload> course,
    List<TeachingWorkload> other,
  ) {
    final excel = xl.Excel.createExcel();
    for (final n in excel.tables.keys.toList()) {
      excel.delete(n);
    }

    final courseSheet = excel['课程工作量'];
    courseSheet.appendRow(courseHeaders.map(xl.TextCellValue.new).toList());
    for (final w in course) {
      courseSheet.appendRow([
        xl.TextCellValue(w.teacherId),
        xl.TextCellValue(w.teacherName),
        xl.TextCellValue(w.department ?? ''),
        xl.TextCellValue(w.courseSerial ?? ''),
        xl.TextCellValue(w.courseCode ?? ''),
        xl.TextCellValue(w.courseName),
        xl.TextCellValue(w.courseCategory ?? ''),
        xl.TextCellValue(w.classNames ?? ''),
        xl.TextCellValue(w.teachingForm ?? ''),
        xl.TextCellValue(w.courseNature ?? ''),
        xl.DoubleCellValue(w.credits ?? 0),
        xl.IntCellValue(w.studentCount ?? 0),
        xl.IntCellValue(w.classHours),
        xl.DoubleCellValue(w.courseCoefficient),
        xl.DoubleCellValue(w.scaleCoefficient),
        xl.DoubleCellValue(w.declaredWorkload),
        xl.TextCellValue(w.workloadType),
        xl.TextCellValue(w.remark ?? ''),
      ]);
    }

    final otherSheet = excel['其他工作量'];
    otherSheet.appendRow(otherHeaders.map(xl.TextCellValue.new).toList());
    for (final w in other) {
      otherSheet.appendRow([
        xl.TextCellValue(w.teacherId),
        xl.TextCellValue(w.teacherName),
        xl.TextCellValue(w.department ?? ''),
        xl.TextCellValue(w.workloadType),
        xl.TextCellValue(w.otherCategory ?? ''),
        xl.TextCellValue(w.extraHoursProject ?? ''),
        xl.DoubleCellValue(w.declaredWorkload),
        xl.TextCellValue(w.remark ?? ''),
      ]);
    }

    return Uint8List.fromList(excel.save()!);
  }

  /// 从 Excel 字节读取工作量记录。
  /// [courseId] 关联当前课程；[defaultTeacherId]/[defaultTeacherName] 兜底。
  List<TeachingWorkload> importExcel(
    Uint8List bytes, {
    required String courseId,
    required String defaultTeacherId,
    required String defaultTeacherName,
    required String semester,
  }) {
    final excel = xl.Excel.decodeBytes(bytes);
    final List<TeachingWorkload> result = [];

    // 课程工作量表
    if (excel.tables.containsKey('课程工作量')) {
      final sheet = excel['课程工作量'];
      final rows = sheet.rows;
      for (var i = 1; i < rows.length; i++) {
        final r = rows[i];
        if (r.isEmpty) continue;
        final name = _cellStr(r, 5);
        if (name.isEmpty) continue;
        final w = TeachingWorkload(
          teacherId: _cellStr(r, 0).isNotEmpty ? _cellStr(r, 0) : defaultTeacherId,
          teacherName: _cellStr(r, 1).isNotEmpty ? _cellStr(r, 1) : defaultTeacherName,
          department: _cellStr(r, 2),
          courseSerial: _cellStr(r, 3),
          courseCode: _cellStr(r, 4),
          courseName: name,
          courseCategory: _cellStr(r, 6),
          classNames: _cellStr(r, 7),
          teachingForm: _cellStr(r, 8),
          courseNature: _cellStr(r, 9),
          credits: _cellDouble(r, 10),
          studentCount: _cellInt(r, 11),
          classHours: _cellInt(r, 12),
          courseCoefficient: _cellDouble(r, 13) ?? 1.0,
          scaleCoefficient: _cellDouble(r, 14) ?? 1.0,
          declaredWorkload: _cellDouble(r, 15) ?? 0,
          workloadType: _cellStr(r, 16).isNotEmpty ? _cellStr(r, 16) : '理论工作量',
          status: 'submitted',
          semester: semester,
          courseId: courseId,
          remark: _cellStr(r, 17),
        );
        result.add(w);
      }
    }

    // 其他工作量表
    if (excel.tables.containsKey('其他工作量')) {
      final sheet = excel['其他工作量'];
      final rows = sheet.rows;
      for (var i = 1; i < rows.length; i++) {
        final r = rows[i];
        if (r.isEmpty) continue;
        final category = _cellStr(r, 4);
        if (category.isEmpty) continue;
        final w = TeachingWorkload(
          teacherId: _cellStr(r, 0).isNotEmpty ? _cellStr(r, 0) : defaultTeacherId,
          teacherName: _cellStr(r, 1).isNotEmpty ? _cellStr(r, 1) : defaultTeacherName,
          department: _cellStr(r, 2),
          courseName: '',
          workloadType: _cellStr(r, 3).isNotEmpty ? _cellStr(r, 3) : '其他工作量',
          otherCategory: category,
          extraHoursProject: _cellStr(r, 5),
          declaredWorkload: _cellDouble(r, 6) ?? 0,
          status: 'submitted',
          semester: semester,
          courseId: courseId,
          remark: _cellStr(r, 7),
        );
        result.add(w);
      }
    }

    return result;
  }

  String _cellStr(List<xl.Data?> row, int idx) {
    if (idx >= row.length) return '';
    final v = row[idx];
    if (v == null) return '';
    return v.value.toString().trim();
  }

  double? _cellDouble(List<xl.Data?> row, int idx) {
    final s = _cellStr(row, idx);
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  int _cellInt(List<xl.Data?> row, int idx) {
    final s = _cellStr(row, idx);
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? 0;
  }
}
