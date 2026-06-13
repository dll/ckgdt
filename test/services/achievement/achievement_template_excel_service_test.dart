library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/achievement/achievement_template_excel_service.dart';
import 'package:xml/xml.dart';

void main() {
  test('模板查找跳过只有三张成绩表的数据源文件', () async {
    final template =
        await AchievementTemplateExcelService.instance.findTemplateForCourse(
      '移动应用开发',
    );
    expect(template, isNotNull);
    expect(template!.path, isNot(contains('软件23《移动应用开发》课程达成评价表格86.xlsx')));
  });

  test('学校 Excel 模板填充：保留图表结构并替换关键数据单元格', () async {
    final template = File('data/达成/计科22《移动应用开发》课程达成评价表格48.xlsx');
    expect(await template.exists(), isTrue);
    final sourceBytes = await template.readAsBytes();

    final output = AchievementTemplateExcelService.instance.fillTemplate(
      sourceBytes,
      const AchievementExcelTemplatePayload(
        courseName: '移动应用开发',
        className: '计科22',
        semester: '2026-2027学年第1学期',
        objectiveWeights: [0.1, 0.2, 0.3, 0.4],
        objectiveAchievements: [0.8123, 0.7567, 0.7012, 0.9234],
        objectiveNames: ['课程目标1', '课程目标2', '课程目标3', '课程目标4'],
        indicators: ['1.4', '3.2', '4.2', '5.1'],
        scores: [
          {
            'student_id': 'S001',
            'student_name': '张三',
            'obj1_achievement': 0.82,
            'obj2_achievement': 0.76,
            'obj3_achievement': 0.70,
            'obj4_achievement': 0.92,
          },
        ],
        pingshi: [
          {
            'student_id': 'S001',
            'student_name': '张三',
            'class_activity_score': 88,
            'class_activity_achievement': 0.88,
            'quiz_homework_score': 77,
            'quiz_homework_achievement': 0.77,
            'extra_learning_score': 99,
            'extra_learning_achievement': 0.99,
            'total_score': 88.9,
          },
        ],
        experiment: [
          {
            'student_id': 'S001',
            'student_name': '张三',
            'exp1_score': 100,
            'exp2_score': 90,
            'exp3_score': 80,
            'exp4_score': 70,
            'exp5_score': 60,
            'exp6_score': 50,
            'exp7_score': 40,
            'obj1_achievement': 0.95,
            'obj2_achievement': 0.75,
            'obj3_achievement': 0.55,
            'obj4_achievement': 0.40,
            'total_score': 70,
          },
          {
            'student_id': 'S002',
            'student_name': '李四',
            'exp1_score': 80,
            'exp2_score': 70,
            'exp3_score': 60,
            'exp4_score': 50,
            'exp5_score': 90,
            'exp6_score': 83.3,
            'exp7_score': 0,
            'obj1_achievement': 0.75,
            'obj2_achievement': 0.55,
            'obj3_achievement': 0.90,
            'obj4_achievement': 0.833,
            'total_score': 72.2,
          },
        ],
        exam: [
          {
            'student_id': 'S001',
            'student_name': '张三',
            'project_score': 91,
            'group_score': 82,
            'individual_score': 73,
            'defense_score': 64,
            'obj1_achievement': 0.91,
            'obj2_achievement': 0.82,
            'obj3_achievement': 0.73,
            'obj4_achievement': 0.64,
            'total_score': 77.6,
          },
        ],
        pingshiAverage: {'obj1': 0.88, 'obj2': 0.77, 'obj3': 0, 'obj4': 0.99},
        experimentAverage: {
          'obj1': 0.95,
          'obj2': 0.75,
          'obj3': 0.55,
          'obj4': 0.40,
        },
        examAverage: {'obj1': 0.91, 'obj2': 0.82, 'obj3': 0.73, 'obj4': 0.64},
        weightedAchievement: 0.8012,
      ),
    );

    final originalNames = _archiveNames(sourceBytes);
    final outputNames = _archiveNames(output);
    expect(
        outputNames.containsAll(originalNames.where(
            (n) => n.startsWith('xl/charts/') || n.startsWith('xl/drawings/'))),
        isTrue);

    final pingshi = _sheetCells(output, '平时成绩');
    expect(pingshi['A1'], contains('2026-2027学年第1学期计科22《移动应用开发》'));
    expect(pingshi['A6'], 'S001');
    expect(pingshi['B6'], '张三');
    expect(pingshi['C6'], '88.0');
    expect(pingshi['N6'], '88.0');
    expect(pingshi['O6'], '0.88');
    expect(pingshi['P6'], '77.0');
    expect(pingshi['AB6'], '99.0');
    expect(pingshi['AM6'], '88.9');
    expect(pingshi['A7'], isEmpty, reason: '旧模板学生数据应被清空');

    final experiment = _sheetCells(output, '实验成绩');
    expect(experiment['A6'], 'S001');
    expect(experiment['C6'], '100.0');
    expect(experiment['E6'], '0.95');
    expect(experiment['L7'], '83.3', reason: '6实验数据导出到学校模板时，目标4得分不能显示为0');
    expect(experiment['N6'], '70.0');

    final individual = _sheetCells(output, '学生个体课程目标达成度');
    expect(individual['A7'], 'S001');
    expect(individual['F7'], '0.82');
    expect(individual['R7'], '0.92');

    final objective = _sheetCells(output, '课程目标点达成度');
    expect(objective['A6'], '目标1');
    expect(objective['B6'], '0.1');
    expect(objective['H6'], '0.8123');
    expect(objective['G20'], '0.8012');

    final scatter = _sheetCells(output, '目标1散点趋势图');
    expect(scatter['B1'], '1');
    expect(scatter['C1'], '0.82');
    expect(scatter['D1'], '0.8123');
  });
}

Set<String> _archiveNames(Uint8List bytes) {
  return ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toSet();
}

Map<String, String> _sheetCells(Uint8List bytes, String sheetName) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = {
    for (final f in archive.files) f.name: f.content as List<int>,
  };
  String text(String name) => utf8.decode(files[name]!);

  final sharedStrings = <String>[];
  if (files.containsKey('xl/sharedStrings.xml')) {
    final ss = XmlDocument.parse(text('xl/sharedStrings.xml'));
    for (final si in ss.findAllElements('si')) {
      sharedStrings.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final workbook = XmlDocument.parse(text('xl/workbook.xml'));
  final rels = XmlDocument.parse(text('xl/_rels/workbook.xml.rels'));
  final targets = <String, String>{};
  for (final rel in rels.findAllElements('Relationship')) {
    final id = rel.getAttribute('Id');
    final target = rel.getAttribute('Target');
    if (id != null && target != null) {
      targets[id] = target.startsWith('xl/') ? target : 'xl/$target';
    }
  }
  String? path;
  for (final sheet in workbook.findAllElements('sheet')) {
    if (sheet.getAttribute('name') != sheetName) continue;
    final rid = sheet.getAttribute('r:id') ??
        sheet.getAttribute('id',
            namespace:
                'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
    path = rid == null ? null : targets[rid];
    break;
  }
  expect(path, isNotNull, reason: 'sheet not found: $sheetName');

  final doc = XmlDocument.parse(text(path!));
  final out = <String, String>{};
  for (final cell in doc.findAllElements('c')) {
    final ref = cell.getAttribute('r');
    if (ref == null) continue;
    out[ref] = _cellText(cell, sharedStrings);
  }
  return out;
}

String _cellText(XmlElement cell, List<String> sharedStrings) {
  final inline = cell.findElements('is').expand((e) => e.findAllElements('t'));
  if (inline.isNotEmpty) return inline.map((t) => t.innerText).join();
  final value = cell.findElements('v').firstOrNull?.innerText ?? '';
  if (cell.getAttribute('t') == 's') {
    final index = int.tryParse(value);
    if (index != null && index >= 0 && index < sharedStrings.length) {
      return sharedStrings[index];
    }
  }
  return value;
}
