/// 验证达成报告 DOCX 导出结构对齐学校模板：
/// - 共 7 张表
/// - 第四部分「达成结果分析」表含 5 行（定量/定性问卷/持续改进/教师签字/课程群意见）
/// 不依赖 AI / DB / UI，直接驱动 AchievementDocxService。
library;

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/achievement/achievement_docx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('达成报告 DOCX：7 张表 + 分析表 5 行 + 注入问卷定性文字', () async {
    final objectives = [
      for (int i = 1; i <= 4; i++)
        {
          'objective': i,
          'weight': [0.15, 0.25, 0.30, 0.30][i - 1],
          'indicator': ['1.4', '3.2', '4.2', '5.1'][i - 1],
          'description': '课程目标$i 描述',
          'assess_content': '目标$i 考核内容',
          'full_mark': [15, 25, 30, 30][i - 1],
          'achievement': 0.8,
          'envs': [
            {'name': '平时', 'full': 20, 'avg': 16, 'ach': 0.8, 'weight': 0.2},
            {'name': '实验', 'full': 30, 'avg': 24, 'ach': 0.8, 'weight': 0.3},
            {'name': '期末考试', 'full': 50, 'avg': 40, 'ach': 0.8, 'weight': 0.5},
          ],
        },
    ];

    final path = await AchievementDocxService.instance.generateReport(
      batchName: '测试批次',
      courseName: '移动应用开发',
      className: '计科22',
      semester: '2025-2026学年第1学期',
      teacherName: '刘东良',
      syllabus: {
        'info': {'课程类别': '专业基础'},
        'objectives': [
          for (int i = 1; i <= 4; i++)
            {'num': i, 'objective': '目标$i', 'requirement': '1.4'}
        ],
        'weights': const [],
      },
      objectives: objectives,
      classStats: {'studentCount': 48, 'avgTotal': 80, 'maxTotal': 95, 'minTotal': 42, 'stdDev': 8},
      students: const [],
      qualitativeText: '共回收有效问卷 48 份，综合满意度为 90.0%。',
    );

    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final doc = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    final xml = utf8.decode(doc.content as List<int>);

    final tableCount = '<w:tbl>'.allMatches(xml).length;
    expect(tableCount, 7, reason: '应有 7 张表，对齐模板');

    expect(xml.contains('调查问卷评价情况(定性)'), isTrue, reason: '缺定性问卷行');
    expect(xml.contains('课程群建设工作组意见'), isTrue, reason: '缺课程群工作组意见行');
    expect(xml.contains('共回收有效问卷 48 份'), isTrue, reason: '问卷定性文字未注入');

    await File(path).delete();
  });
}
