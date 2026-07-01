import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:knowledge_graph_app/data/models/archive_document_model.dart';
import 'package:knowledge_graph_app/services/archive_package_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArchiveNaming', () {
    test('fileBase concatenates with + separator', () {
      final n = ArchiveNaming(
        department: '软件学院',
        course: '移动应用开发',
        docLabel: '教学大纲',
        teacher: '刘东良',
        semester: '2025-2026-2',
      );
      expect(n.fileBase(), equals('软件学院+移动应用开发+教学大纲+刘东良+2025-2026-2'));
    });

    test('fileBase override docLabel', () {
      final n = ArchiveNaming(
        department: '软件学院',
        course: '移动应用开发',
        docLabel: '占位',
        teacher: '刘东良',
        semester: '2025-2026-2',
      );
      expect(n.fileBase(docLabel: '教学日历'),
          equals('软件学院+移动应用开发+教学日历+刘东良+2025-2026-2'));
    });

    test('zipBase excludes docLabel', () {
      final n = ArchiveNaming(
        department: '软件学院',
        course: '移动应用开发',
        docLabel: '教学大纲',
        teacher: '刘东良',
        semester: '2025-2026-2',
      );
      expect(n.zipBase, equals('软件学院+移动应用开发+刘东良+2025-2026-2'));
    });

    test('copyWith preserves untouched fields', () {
      final n = ArchiveNaming(
        department: '软件学院',
        course: '移动应用开发',
        docLabel: '教学大纲',
        teacher: '刘东良',
        semester: '2025-2026-2',
        warnings: ['w1'],
      );
      final c = n.copyWith(docLabel: '教学日历');
      expect(c.docLabel, '教学日历');
      expect(c.department, '软件学院');
      expect(c.semester, '2025-2026-2');
      expect(c.warnings, ['w1']);
    });
  });

  group('ArchivePackageService selected zip', () {
    test('adaptive final catalog preserves official Word original', () async {
      final oldRoot = ArchivePackageService.outputRoot;
      final temp =
          Directory.systemTemp.createTempSync('archive_adaptive_catalog_');
      try {
        ArchivePackageService.outputRoot = temp.path;
        final template = File(p.join(temp.path, 'old-catalog.docx'))
          ..writeAsBytesSync([1, 2, 3]);
        final doc = ArchiveDocument(
          title: '期末课程档案袋目录',
          documentType: 'final_archive_catalog',
          period: 'final',
          courseType: 'assess',
          content: '# 课程档案袋目录\n\n当前课程目录',
          filePath: template.path,
        );
        final naming = ArchiveNaming(
          department: '信息学院',
          course: '软件工程',
          docLabel: '课程档案袋目录',
          teacher: '刘东良',
          semester: '2025-2026-2',
        );

        final out = await ArchivePackageService.instance.archiveDocxOf(
          doc,
          docLabel: '课程档案袋目录',
          naming: naming,
        );

        expect(out, endsWith('.docx'));
        expect(File(out).readAsBytesSync(), equals([1, 2, 3]));
      } finally {
        ArchivePackageService.outputRoot = oldRoot;
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });

    test(
        'parsed beginning survey archives generated docx instead of source xlsx',
        () async {
      final oldRoot = ArchivePackageService.outputRoot;
      final temp = Directory.systemTemp.createTempSync('archive_survey_docx_');
      try {
        ArchivePackageService.outputRoot = temp.path;
        final source = File(p.join(temp.path, 'survey.xlsx'))
          ..writeAsBytesSync([1, 2, 3]);
        final doc = ArchiveDocument(
          title: '期初问卷',
          documentType: 'survey',
          period: 'beginning',
          courseType: 'assess',
          content: '# 课程目标支撑毕业要求达成度调查问卷\n\n## 一、达成度统计',
          filePath: source.path,
        );
        final naming = ArchiveNaming(
          department: '信息学院',
          course: '移动应用开发',
          docLabel: '问卷',
          teacher: '刘东良',
          semester: '2025-2026-2',
        );

        final out = await ArchivePackageService.instance.archiveDocxOf(
          doc,
          docLabel: '问卷',
          naming: naming,
        );

        expect(out, endsWith('.docx'));
        expect(File(out).readAsBytesSync(), isNot(equals([1, 2, 3])));
      } finally {
        ArchivePackageService.outputRoot = oldRoot;
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });

    test('zipSelectedFiles keeps selected original file types', () async {
      final oldRoot = ArchivePackageService.outputRoot;
      final temp = Directory.systemTemp.createTempSync('archive_zip_selected_');
      try {
        ArchivePackageService.outputRoot = temp.path;
        final naming = ArchiveNaming(
          department: '软件学院',
          course: '移动应用开发',
          docLabel: '成绩登记表',
          teacher: '刘东良',
          semester: '2025-2026-2',
        );
        final periodDir =
            Directory(p.join(temp.path, naming.semester, naming.course, '期末'))
              ..createSync(recursive: true);
        final xlsx = File(p.join(periodDir.path, '成绩登记表.xlsx'))
          ..writeAsBytesSync([1, 2, 3]);
        final pdf = File(p.join(periodDir.path, '考核说明.pdf'))
          ..writeAsBytesSync([4, 5, 6]);

        final zipPath = await ArchivePackageService.instance.zipSelectedFiles(
          naming: naming,
          filePaths: [xlsx.path, pdf.path],
        );

        final zip = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
        final names = zip.files.map((f) => f.name).toSet();
        expect(names, contains('期末/成绩登记表.xlsx'));
        expect(names, contains('期末/考核说明.pdf'));
      } finally {
        ArchivePackageService.outputRoot = oldRoot;
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });

    test('zipSelectedFiles skips duplicate file paths', () async {
      final oldRoot = ArchivePackageService.outputRoot;
      final temp = Directory.systemTemp.createTempSync('archive_zip_dedupe_');
      try {
        ArchivePackageService.outputRoot = temp.path;
        final naming = ArchiveNaming(
          department: '软件学院',
          course: '移动应用开发',
          docLabel: '结课材料',
          teacher: '刘东良',
          semester: '2025-2026-2',
        );
        final periodDir =
            Directory(p.join(temp.path, naming.semester, naming.course, '期末'))
              ..createSync(recursive: true);
        final pdf = File(p.join(periodDir.path, '样本.pdf'))
          ..writeAsBytesSync([1, 2, 3]);

        final zipPath = await ArchivePackageService.instance.zipSelectedFiles(
          naming: naming,
          filePaths: [pdf.path, pdf.path],
          prefix: '一键结课',
        );

        final zip = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
        expect(zip.files.where((f) => f.name.endsWith('样本.pdf')), hasLength(1));
      } finally {
        ArchivePackageService.outputRoot = oldRoot;
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });

    test('archives multiple originals with same doc label without overwrite',
        () async {
      final oldRoot = ArchivePackageService.outputRoot;
      final temp = Directory.systemTemp.createTempSync('archive_multi_final_');
      try {
        ArchivePackageService.outputRoot = temp.path;
        final sourceA = File(p.join(temp.path, '12-0-学生A大作业.pdf'))
          ..writeAsBytesSync([1, 2, 3]);
        final sourceB = File(p.join(temp.path, '12-1-学生B大作业.pdf'))
          ..writeAsBytesSync([4, 5, 6]);
        final naming = ArchiveNaming(
          department: '信息学院',
          course: '移动应用开发',
          docLabel: '课程考核大作业样本',
          teacher: '刘东良',
          semester: '2025-2026-2',
        );

        ArchiveDocument docFor(File file) => ArchiveDocument(
              title: '期末课程考核大作业样本 - ${p.basenameWithoutExtension(file.path)}',
              documentType: 'final_sample_works',
              period: 'final',
              courseType: 'assess',
              content: '# 课程考核大作业样本\n\n> 此资料以原始文件为准。',
              filePath: file.path,
            );

        final outA = await ArchivePackageService.instance.archiveDocxOf(
          docFor(sourceA),
          docLabel: '课程考核大作业样本',
          naming: naming,
        );
        final outB = await ArchivePackageService.instance.archiveDocxOf(
          docFor(sourceB),
          docLabel: '课程考核大作业样本',
          naming: naming,
        );

        expect(outA, isNot(outB));
        expect(File(outA).readAsBytesSync(), equals([1, 2, 3]));
        expect(File(outB).readAsBytesSync(), equals([4, 5, 6]));
      } finally {
        ArchivePackageService.outputRoot = oldRoot;
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });

    test('re-archiving the same original reuses the same output path',
        () async {
      final oldRoot = ArchivePackageService.outputRoot;
      final temp =
          Directory.systemTemp.createTempSync('archive_same_original_');
      try {
        ArchivePackageService.outputRoot = temp.path;
        final source = File(p.join(temp.path, '08-成绩登记表.xls'))
          ..writeAsBytesSync([1, 2, 3]);
        final naming = ArchiveNaming(
          department: '信息学院',
          course: '移动应用开发',
          docLabel: '成绩登记表',
          teacher: '刘东良',
          semester: '2025-2026-2',
        );
        final doc = ArchiveDocument(
          title: '期末成绩登记表',
          documentType: 'final_score_register',
          period: 'final',
          courseType: 'assess',
          content: '# 成绩登记表\n\n> 此资料以原始文件为准。',
          filePath: source.path,
        );

        final first = await ArchivePackageService.instance.archiveDocxOf(
          doc,
          docLabel: '成绩登记表',
          naming: naming,
        );
        final second = await ArchivePackageService.instance.archiveDocxOf(
          doc,
          docLabel: '成绩登记表',
          naming: naming,
        );

        expect(second, first);
        final periodDir = Directory(p.join(
          temp.path,
          naming.semester,
          naming.course,
          '期末',
        ));
        final files = periodDir
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path).toLowerCase() == '.xls')
            .toList();
        expect(files, hasLength(1));
      } finally {
        ArchivePackageService.outputRoot = oldRoot;
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });
  });
}
