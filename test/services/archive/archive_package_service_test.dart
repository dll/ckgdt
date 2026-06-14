import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:knowledge_graph_app/services/archive_package_service.dart';

void main() {
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
  });
}
