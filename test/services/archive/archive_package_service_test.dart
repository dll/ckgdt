import 'package:flutter_test/flutter_test.dart';
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
      expect(n.fileBase(),
          equals('软件学院+移动应用开发+教学大纲+刘东良+2025-2026-2'));
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
}
