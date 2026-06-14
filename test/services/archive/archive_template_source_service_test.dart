import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/archive_template_source_service.dart';
import 'package:knowledge_graph_app/services/archive/base_document_processor.dart';
import 'package:path/path.dart' as p;

void main() {
  late String? oldRoot;
  late Directory temp;
  late Directory templateDir;

  setUp(() {
    oldRoot = BaseDocumentProcessor.archiveDataRoot;
    temp = Directory.systemTemp.createTempSync('kg_beginning_templates_');
    BaseDocumentProcessor.archiveDataRoot = temp.path;
    templateDir = Directory(p.join(temp.path, '期初', '模板'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    BaseDocumentProcessor.archiveDataRoot = oldRoot;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('matches syllabus by semantic name without fixed number', () async {
    final source = File(p.join(templateDir.path, '移动应用开发课程教学大纲.md'))
      ..writeAsStringSync('# 移动应用开发教学大纲\n\n课程目标');

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'beginning',
      documentType: 'syllabus',
      label: '教学大纲',
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
    expect(doc.content, contains('课程目标'));
  });

  test('does not confuse syllabus with evaluation and review forms', () async {
    File(p.join(templateDir.path, '课程教学大纲合理性评价表.docx'))
        .writeAsBytesSync(const []);
    final source = File(p.join(templateDir.path, '课程教学大纲.md'))
      ..writeAsStringSync('# 正确的大纲');

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'beginning',
      documentType: 'syllabus',
      label: '教学大纲',
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
  });

  test('matches assessment plan pdf as original file', () async {
    final source = File(p.join(templateDir.path, '课程考查大作业方案.pdf'))
      ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'beginning',
      documentType: 'assessment_plan',
      label: '综合考核方案',
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
    expect(doc.content, contains('PDF 原件'));
  });

  test('prefers direct lesson plan markdown over lesson plan directory',
      () async {
    Directory(p.join(templateDir.path, '教案')).createSync();
    final source = File(p.join(templateDir.path, '理论教案.md'))
      ..writeAsStringSync('# 理论教案');

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'beginning',
      documentType: 'lesson_plan',
      label: '教学教案',
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
  });

  test('real beginning template directory resolves all configured materials',
      () async {
    final realRoot = Directory('data/归档').absolute;
    if (!realRoot.existsSync()) return;
    BaseDocumentProcessor.archiveDataRoot = realRoot.path;

    const docs = {
      'teaching_task': '教学任务单',
      'syllabus': '教学大纲',
      'syllabus_evaluation': '大纲合理性评价表',
      'syllabus_review': '大纲合理性审核表',
      'calendar': '教学日历',
      'course_schedule': '课程课表',
      'teaching_schedule': '教学进度表',
      'lesson_plan': '教学教案',
      'courseware': '教学课件',
      'roll_call': '学生点名册',
      'teacher_guide': '教师教学指导手册',
      'student_guide': '学生学习指导手册',
      'assessment_plan': '综合考核方案',
      'survey': '问卷',
    };

    for (final entry in docs.entries) {
      final doc = await ArchiveTemplateSourceService.parseBestSource(
        periodKey: 'beginning',
        documentType: entry.key,
        label: entry.value,
      );
      expect(doc, isNotNull, reason: '${entry.key} should resolve');
      expect(doc!.content.trim(), isNotEmpty);
    }
  });
}
