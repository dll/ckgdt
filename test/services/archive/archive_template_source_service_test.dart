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

  test('extracts beginning official docx template as editable content',
      () async {
    final source = File(p.join(templateDir.path, '课程教学大纲合理性评价表.docx'))
      ..writeAsBytesSync(const [0x50, 0x4b, 0x03, 0x04]);

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'beginning',
      documentType: 'syllabus_evaluation',
      label: '大纲合理性评价表',
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
    expect(doc.content, isNot(contains('此资料以原始文件为准')));
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
    const expectedPrefixes = {
      'teaching_task': '01-',
      'syllabus': '02-',
      'syllabus_evaluation': '03-',
      'syllabus_review': '04-',
      'calendar': '06-',
      'course_schedule': '07-',
      'teaching_schedule': '08-',
      'lesson_plan': '09-',
      'courseware': '10-',
      'roll_call': '11-',
      'teacher_guide': '12-',
      'student_guide': '13-',
      'assessment_plan': '14-',
      'survey': '15-',
    };

    for (final entry in docs.entries) {
      final doc = await ArchiveTemplateSourceService.parseBestSource(
        periodKey: 'beginning',
        documentType: entry.key,
        label: entry.value,
      );
      expect(doc, isNotNull, reason: '${entry.key} should resolve');
      expect(doc!.content.trim(), isNotEmpty);
      expect(
          p.basename(doc.sourcePath), startsWith(expectedPrefixes[entry.key]!),
          reason: '${entry.key} should match numbered beginning template');
      if (entry.key == 'course_schedule') {
        expect(doc.content, contains('课程课表：移动应用开发'));
        expect(doc.content, isNot(contains('此资料以原始文件为准')));
      }
      if (entry.key == 'survey') {
        expect(doc.content, contains('达成度统计'));
        expect(doc.content, isNot(contains('此资料以原始文件为准')));
      }
      if (entry.key == 'assessment_plan') {
        expect(doc.content, contains('PDF 原件'));
      }
    }
  });

  test(
      'real beginning direct imports support schedule docx guides md and plan pdf',
      () async {
    final files = {
      'teaching_schedule': (
        '教学进度表',
        File('data/归档/期初/模板/08-软件23+《移动应用开发》教学进度表+刘东良.docx'),
        '教学进度'
      ),
      'teacher_guide': (
        '教师教学指导手册',
        File('data/归档/期初/模板/12-移动应用开发教师教学指导手册+new.md'),
        '移动应用开发教师教学指导手册'
      ),
      'student_guide': (
        '学生学习指导手册',
        File('data/归档/期初/模板/13-移动应用开发学生学习指导手册+new.md'),
        '移动应用开发学生学习指导手册'
      ),
      'assessment_plan': (
        '综合考核方案',
        File('data/归档/期初/模板/14-课程考查大作业方案.pdf'),
        'PDF 原件'
      ),
      'survey': (
        '问卷',
        File('data/归档/期初/模板/15-课程目标支撑毕业要求达成度调查问卷.xlsx'),
        '达成度统计'
      ),
    };

    for (final entry in files.entries) {
      final (label, file, expected) = entry.value;
      if (!file.existsSync()) continue;
      final doc = await ArchiveTemplateSourceService.parseFile(
        file: file,
        documentType: entry.key,
        label: label,
      );
      expect(doc, isNotNull, reason: '${entry.key} should import');
      expect(doc!.sourcePath, file.path);
      expect(doc.content, contains(expected));
    }
  });

  test('real midterm template directory resolves progress homework and exam',
      () async {
    final realRoot = Directory('data/归档').absolute;
    if (!realRoot.existsSync()) return;
    BaseDocumentProcessor.archiveDataRoot = realRoot.path;

    const docs = {
      'midterm_progress_check': '课程进度执行检查',
      'midterm_homework_review': '作业与批阅次数统计',
      'midterm_exam': '期中考试',
    };

    for (final entry in docs.entries) {
      final doc = await ArchiveTemplateSourceService.parseBestSource(
        periodKey: 'midterm',
        documentType: entry.key,
        label: entry.value,
      );
      expect(doc, isNotNull, reason: '${entry.key} should resolve');
      expect(doc!.content.trim(), isNotEmpty);
    }
  });

  test('midterm progress template matches arbitrary numbering', () async {
    final midtermDir = Directory(p.join(temp.path, '期中', '模板'))
      ..createSync(recursive: true);
    final source = File(p.join(midtermDir.path, '22-软件工程课程进度.md'))
      ..writeAsStringSync('# 教学进度表\n\n周次：第1-8周\n\n计划学时：32学时');

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'midterm',
      documentType: 'midterm_progress_check',
      label: '课程进度执行检查',
      now: DateTime(2026, 6, 15),
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
    expect(doc.content, contains('课程进度执行检查表'));
    expect(doc.content, contains('2026-06-15'));
  });

  test('uses midterm official docx template as editable structure', () async {
    final midtermDir = Directory(p.join(temp.path, '期中', '模板'))
      ..createSync(recursive: true);
    final source = File(p.join(midtermDir.path, '08-软件工程课程进度检查.docx'))
      ..writeAsBytesSync(const [0x50, 0x4b, 0x03, 0x04]);

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'midterm',
      documentType: 'midterm_progress_check',
      label: '课程进度执行检查',
      now: DateTime(2026, 6, 15),
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
    expect(doc.content, contains('课程进度执行检查'));
    expect(doc.content, isNot(contains('此资料以原始文件为准')));
  });

  test('midterm homework review warns when source is actually progress table',
      () async {
    final midtermDir = Directory(p.join(temp.path, '期中', '模板'))
      ..createSync(recursive: true);
    final source = File(p.join(midtermDir.path, '15-作业次数和批阅次数.md'))
      ..writeAsStringSync('# 教学进度表\n\n周次\n\n教学内容摘要\n\n第1周 移动应用开发技术体系');

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'midterm',
      documentType: 'midterm_homework_review',
      label: '作业与批阅次数统计',
      now: DateTime(2026, 6, 15),
    );

    expect(doc, isNotNull);
    expect(doc!.sourcePath, source.path);
    expect(doc.content, contains('作业与批阅次数统计表'));
    expect(doc.content, contains('源文件疑似为教学进度表'));
  });

  test('real final template directory resolves school archive bag materials',
      () async {
    final realRoot = Directory('data/归档').absolute;
    if (!realRoot.existsSync()) return;
    BaseDocumentProcessor.archiveDataRoot = realRoot.path;

    const docs = {
      'final_archive_catalog': '课程档案袋目录',
      'final_assessment_review': '课程期末考核命题审核表',
      'final_grade_book': '记分册',
      'final_score_register': '成绩登记表',
      'final_achievement_report': '课程达成评价材料',
      'final_textbook_guide': '教材与实验指导书',
      'final_sample_works': '课程考核大作业样本',
    };

    for (final entry in docs.entries) {
      final doc = await ArchiveTemplateSourceService.parseBestSource(
        periodKey: 'final',
        documentType: entry.key,
        label: entry.value,
      );
      expect(doc, isNotNull, reason: '${entry.key} should resolve');
      expect(doc!.content.trim(), isNotEmpty);
    }
  });

  test('final archive catalog docx template is extracted for regeneration',
      () async {
    final realRoot = Directory('data/归档').absolute;
    if (!realRoot.existsSync()) return;
    BaseDocumentProcessor.archiveDataRoot = realRoot.path;

    final doc = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: 'final',
      documentType: 'final_archive_catalog',
      label: '课程档案袋目录',
    );

    expect(doc, isNotNull);
    expect(doc!.sourceName, contains('课程档案袋目录'));
    expect(doc.content, isNot(contains('此资料以原始文件为准')));
    expect(doc.content, contains('课程档案袋目录'));
  });
}
