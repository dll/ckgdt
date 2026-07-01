import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/models/archive_document_model.dart';
import 'package:knowledge_graph_app/services/achievement/achievement_audit_context_service.dart';

void main() {
  test('buildAuditMarkdownFromSnapshot reports ready archive workflow',
      () async {
    final temp = await Directory.systemTemp.createTemp('achievement_audit_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final original = File('${temp.path}/syllabus.docx');
    await original.writeAsBytes([1, 2, 3]);

    ArchiveDocument doc(String stage, String title, String type) =>
        ArchiveDocument(
          title: title,
          documentType: type,
          period: stage,
          courseType: 'exam',
          status: 'archived',
          filePath: original.path,
          reviewJson: '{"result":"pass"}',
          reviewedAt: '2026-07-01T00:00:00',
        );

    final snapshot = AchievementAuditSnapshot(
      courseName: '课程知识图谱与数字孪生',
      courseId: 'ckgdt',
      objectives: [
        {
          'idx': 1,
          'weight': 0.4,
          'full_mark': 40,
          'indicator': '1.1',
          'pingshi_ratio': 0.3,
          'experiment_ratio': 0.2,
          'exam_ratio': 0.5,
        },
        {
          'idx': 2,
          'weight': 0.6,
          'full_mark': 60,
          'indicator': '2.1',
          'pingshi_ratio': 0.2,
          'experiment_ratio': 0.3,
          'exam_ratio': 0.5,
        },
      ],
      batches: [
        {'id': 1, 'batch_name': 'CKGDT 达成评价'}
      ],
      selectedBatch: {'id': 1, 'batch_name': 'CKGDT 达成评价'},
      studentCount: 42,
      classAverage: const {'课程目标1': 0.82, 'weighted': 0.78},
      archiveDocuments: [
        doc('beginning', '教学大纲', 'syllabus'),
        doc('beginning', '教学进度表', 'teaching_schedule'),
        doc('beginning', '课程表', 'course_schedule'),
        doc('midterm', '期中教学检查材料', 'midterm_progress_check'),
        doc('final', '课程目标达成评价报告', 'final_achievement_report'),
        doc('final', '课程档案袋目录', 'final_archive_catalog'),
        doc('closure', '结课归档审批材料', 'archive_form'),
      ],
    );

    final markdown = AchievementAuditContextService()
        .buildAuditMarkdownFromSnapshot(snapshot);

    expect(markdown, contains('满足归档前置条件'));
    expect(markdown, contains('关键材料：7/7'));
    expect(markdown, contains('课程目标1：0.820'));
  });

  test('buildAuditMarkdownFromSnapshot reports blocking gaps', () {
    const snapshot = AchievementAuditSnapshot(
      courseName: '课程知识图谱与数字孪生',
      courseId: 'ckgdt',
      objectives: [
        {
          'idx': 1,
          'weight': 0.5,
          'full_mark': 0,
          'indicator': '',
        },
      ],
      batches: [
        {'id': 1, 'batch_name': 'CKGDT 达成评价'}
      ],
      selectedBatch: {'id': 1, 'batch_name': 'CKGDT 达成评价'},
      studentCount: 0,
      classAverage: {},
      archiveDocuments: [],
    );

    final markdown = AchievementAuditContextService()
        .buildAuditMarkdownFromSnapshot(snapshot);

    expect(markdown, contains('暂不满足一键归档条件'));
    expect(markdown, contains('课程目标1 未设置满分'));
    expect(markdown, contains('达成度批次没有学生成绩'));
    expect(markdown, contains('教学大纲缺失'));
  });
}
