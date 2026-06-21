import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/achievement/achievement_template_excel_service.dart';
import 'package:knowledge_graph_app/services/achievement/excel_chart_injector.dart';
import 'package:knowledge_graph_app/services/achievement/achievement_docx_service.dart';

/// 提取 xlsx 内某 worksheet 的某单元格内容（数值或 inlineStr 文本）。
/// 正确处理自闭合空单元格 `<c r="L6"/>`（返回 null）。
String? _cell(String xml, String ref) {
  final open = RegExp('<c r="$ref"([^>]*)>').firstMatch(xml);
  if (open == null) return null;
  if (open.group(1)!.trimRight().endsWith('/')) return null; // 自闭合 → 空
  final close = xml.indexOf('</c>', open.end);
  if (close < 0) return null;
  final inner = xml.substring(open.end, close);
  final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner);
  if (v != null) return v.group(1);
  final t = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).firstMatch(inner);
  return t?.group(1);
}

double? _num(String xml, String ref) {
  final s = _cell(xml, ref);
  return s == null ? null : double.tryParse(s);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('达成度模板：两行汇总落正确列 + 实验七留空 + 注入5图', () async {
    final tpl = File(
        'assets/achievement_templates/mobile_achievement_template_48.xlsx');
    expect(tpl.existsSync(), isTrue, reason: '内置模板缺失');

    Map<String, dynamic> ps(String id, String name) => {
          'student_id': id,
          'student_name': name,
          'class_activity_score': 80.0,
          'class_activity_achievement': 0.8,
          'quiz_homework_score': 90.0,
          'quiz_homework_achievement': 0.9,
          'extra_learning_score': 70.0,
          'extra_learning_achievement': 0.7,
          'total_score': 80.0,
        };
    Map<String, dynamic> es(String id, String name) => {
          'student_id': id,
          'student_name': name,
          'exp1_score': 80.0,
          'exp2_score': 80.0,
          'exp3_score': 90.0,
          'exp4_score': 90.0,
          'exp5_score': 70.0,
          'exp6_score': 70.0,
          'exp7_score': 0.0,
          'obj1_achievement': 0.8,
          'obj2_achievement': 0.9,
          'obj3_achievement': 0.7,
          'obj4_achievement': 0.7,
          'total_score': 80.0,
        };
    Map<String, dynamic> xs(String id, String name) => {
          'student_id': id,
          'student_name': name,
          'project_score': 80.0,
          'group_score': 90.0,
          'individual_score': 70.0,
          'defense_score': 70.0,
          'obj1_achievement': 0.8,
          'obj2_achievement': 0.9,
          'obj3_achievement': 0.7,
          'obj4_achievement': 0.7,
          'total_score': 80.0,
        };
    final ids = [
      ['001', '甲'],
      ['002', '乙'],
      ['003', '丙'],
    ];

    final payload = AchievementExcelTemplatePayload(
      courseName: '移动应用开发',
      className: '计科22',
      semester: '2025-2026',
      objectiveWeights: const [0.15, 0.25, 0.3, 0.3],
      objectiveAchievements: const [0.8, 0.9, 0.7, 0.7],
      objectiveNames: const ['目标1', '目标2', '目标3', '目标4'],
      indicators: const ['1.1', '2.1', '3.1', '4.1'],
      scores: [
        for (final e in ids)
          {
            'student_id': e[0],
            'student_name': e[1],
            'obj1_achievement': 0.8,
            'obj2_achievement': 0.9,
            'obj3_achievement': 0.7,
            'obj4_achievement': 0.7,
          }
      ],
      pingshi: [for (final e in ids) ps(e[0], e[1])],
      experiment: [for (final e in ids) es(e[0], e[1])],
      exam: [for (final e in ids) xs(e[0], e[1])],
      pingshiAverage: const {'obj1': 0.8, 'obj2': 0.9, 'obj3': 0.0, 'obj4': 0.7},
      experimentAverage: const {
        'obj1': 0.8,
        'obj2': 0.9,
        'obj3': 0.7,
        'obj4': 0.7
      },
      examAverage: const {'obj1': 0.8, 'obj2': 0.9, 'obj3': 0.7, 'obj4': 0.7},
      weightedAchievement: 0.785,
    );

    final filled = AchievementTemplateExcelService.instance.fillTemplate(
      Uint8List.fromList(tpl.readAsBytesSync()),
      payload,
      studentCount: 3,
    );

    final specs = <ChartSpec>[
      const ChartSpec.barRange(
          sheetName: '课程目标条形图', title: '课程目标达成度', startRow: 7, endRow: 10),
      for (int i = 0; i < 4; i++)
        ChartSpec.scatterRange(
            sheetName: '目标${i + 1}散点趋势图',
            title: '目标${i + 1}',
            startRow: 1,
            endRow: 3),
    ];
    final out = ExcelChartInjector.inject(filled, specs);

    final archive = ZipDecoder().decodeBytes(out);
    final files = <String, String>{};
    int chartCount = 0;
    for (final f in archive.files) {
      if (f.name.startsWith('xl/charts/chart') && f.name.endsWith('.xml')) {
        chartCount++;
      }
      if (f.name.endsWith('.xml')) {
        files[f.name] = utf8.decode(f.content as List<int>);
      }
    }

    // start=6, count=3 → 班平均值=第9行，课程目标达成度=第10行
    final pingshi = files['xl/worksheets/sheet3.xml']!;
    expect(_cell(pingshi, 'A9'), '班平均值');
    expect(_cell(pingshi, 'A10'), '课程目标达成度');
    // 平时达成度列：O/AA/AL/AM = 14/26/37/38
    expect(_num(pingshi, 'O10'), closeTo(0.8, 1e-6));
    expect(_num(pingshi, 'AA10'), closeTo(0.9, 1e-6));
    expect(_num(pingshi, 'AL10'), closeTo(0.7, 1e-6));

    final experiment = files['xl/worksheets/sheet2.xml']!;
    expect(_cell(experiment, 'A9'), '班平均值');
    expect(_cell(experiment, 'A10'), '课程目标达成度');
    // 实验达成度列：E/H/K/M/N = 4/7/10/12/13
    expect(_num(experiment, 'E10'), closeTo(0.8, 1e-6));
    expect(_num(experiment, 'H10'), closeTo(0.9, 1e-6));
    expect(_num(experiment, 'K10'), closeTo(0.7, 1e-6));
    expect(_num(experiment, 'M10'), closeTo(0.7, 1e-6));
    // 实验七 = L 列(col11)：数据行与班平均行均留空
    expect(_cell(experiment, 'L6'), isNull);
    expect(_cell(experiment, 'L9'), isNull);

    final exam = files['xl/worksheets/sheet1.xml']!;
    expect(_cell(exam, 'A9'), '班平均值');
    expect(_cell(exam, 'A10'), '课程目标达成度');
    // 期末达成度列：D/F/H/J/K = 3/5/7/9/10
    expect(_num(exam, 'D10'), closeTo(0.8, 1e-6));
    expect(_num(exam, 'F10'), closeTo(0.9, 1e-6));
    expect(_num(exam, 'H10'), closeTo(0.7, 1e-6));
    expect(_num(exam, 'J10'), closeTo(0.7, 1e-6));

    // 注入了 5 张新图（模板原图被剥离引用，仍可能残留为孤儿，故用 ≥5）
    expect(chartCount, greaterThanOrEqualTo(5));
  });

  test('达成度 Word：5图嵌入正文 + content-types/rels 合并', () async {
    // 假课程名 → 不匹配任何模板文件 → 走生成（OOXML）路径
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A // PNG 魔数（结构测试用，内容不校验）
    ]);
    final objectives = [
      for (int i = 1; i <= 4; i++)
        {
          'objective': i,
          'weight': 0.25,
          'indicator': '$i.1',
          'description': '课程目标$i 描述',
          'assess_content': '考核内容$i',
          'achievement': 0.78,
          'envs': [
            {'name': '平时', 'full': 20.0, 'avg': 16.0, 'ach': 0.8, 'weight': 0.2},
            {'name': '实验', 'full': 30.0, 'avg': 24.0, 'ach': 0.8, 'weight': 0.3},
            {
              'name': '期末考试',
              'full': 50.0,
              'avg': 38.0,
              'ach': 0.76,
              'weight': 0.5
            },
          ],
        }
    ];

    final path = await AchievementDocxService.instance.generateReport(
      batchName: '自动化测试批次',
      courseName: 'ZZ自动化测试课程',
      className: '测试班',
      semester: '2025-2026',
      teacherName: '测试教师',
      syllabus: const {
        'info': {'课程类别': '专业基础', '总 学 时': '48', '总 学 分': '2.5'}
      },
      objectives: objectives,
      classStats: const {
        'studentCount': 3,
        'avgTotal': 78.0,
        'maxTotal': 90.0,
        'minTotal': 60.0,
        'stdDev': 8.0,
      },
      students: const [
        {'student_id': '001', 'student_name': '甲', 'total_score': 80.0},
        {'student_id': '002', 'student_name': '乙', 'total_score': 78.0},
        {'student_id': '003', 'student_name': '丙', 'total_score': 76.0},
      ],
      barChartPng: png,
      scatterChartPngs: [png, png, png, png],
    );

    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'docx 未生成');
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final names = archive.files.map((f) => f.name).toSet();
    String text(String n) =>
        utf8.decode(archive.files.firstWhere((f) => f.name == n).content
            as List<int>);

    // 5 张图片落盘
    for (var i = 1; i <= 5; i++) {
      expect(names.contains('word/media/image$i.png'), isTrue,
          reason: '缺 image$i.png');
    }

    // 正文确实引用了 rImg1..rImg5（之前的 bug：图片在包里但正文没引用）
    final doc = text('word/document.xml');
    expect(doc.contains('五、课程目标达成度可视化图表'), isTrue);
    for (var i = 1; i <= 5; i++) {
      expect(doc.contains('r:embed="rImg$i"'), isTrue,
          reason: '正文缺 rImg$i 引用');
    }

    // rels 合并：rImg1..5 关系齐全
    final rels = text('word/_rels/document.xml.rels');
    for (var i = 1; i <= 5; i++) {
      expect(rels.contains('Id="rImg$i"'), isTrue, reason: 'rels 缺 rImg$i');
    }

    // content-types 合并：png 扩展名 + 仍保留 document.xml override
    final ct = text('[Content_Types].xml');
    expect(ct.contains('Extension="png"'), isTrue);
    expect(ct.contains('/word/document.xml'), isTrue);
  });
}

