import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/models/archive_document_model.dart';
import 'package:knowledge_graph_app/services/archive/archive_document_policy.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ArchiveDocumentPolicy', () {
    test('parsed survey and course schedule use structured content first', () {
      expect(
        ArchiveDocumentPolicy.shouldUseOriginalSource(
          'survey',
          content: '# 问卷\n\n## 达成度统计',
        ),
        isFalse,
      );
      expect(
        ArchiveDocumentPolicy.shouldUseOriginalSource(
          'course_schedule',
          content: '# 课程课表：移动应用开发',
        ),
        isFalse,
      );
    });

    test('original-reference fallback content still preserves source file', () {
      expect(
        ArchiveDocumentPolicy.shouldUseOriginalSource(
          'survey',
          content: '# 问卷\n\n> 此资料以原始文件为准。',
        ),
        isTrue,
      );
    });

    test('template parser keeps only non-structured original types', () {
      expect(
        ArchiveDocumentPolicy.shouldKeepOriginalTemplate(
          documentType: 'survey',
          extension: '.xlsx',
        ),
        isFalse,
      );
      expect(
        ArchiveDocumentPolicy.shouldKeepOriginalTemplate(
          documentType: 'syllabus_evaluation',
          extension: '.docx',
        ),
        isFalse,
      );
      expect(
        ArchiveDocumentPolicy.shouldKeepOriginalTemplate(
          documentType: 'assessment_plan',
          extension: '.pdf',
        ),
        isTrue,
      );
    });

    test(
        'sourceOriginalFile skips parsed spreadsheets but keeps fallback originals',
        () {
      final temp = Directory.systemTemp.createTempSync('archive_policy_');
      try {
        final xlsx = File(p.join(temp.path, 'survey.xlsx'))
          ..writeAsBytesSync([1, 2, 3]);
        final parsed = ArchiveDocument(
          title: '问卷',
          documentType: 'survey',
          period: 'beginning',
          courseType: 'assess',
          content: '# 问卷\n\n## 达成度统计',
          filePath: xlsx.path,
        );
        final fallback = parsed.copyWith(
          content: '# 问卷\n\n> 此资料以原始文件为准。',
        );

        expect(ArchiveDocumentPolicy.sourceOriginalFile(parsed), isNull);
        expect(ArchiveDocumentPolicy.sourceOriginalFile(fallback)?.path,
            xlsx.path);
      } finally {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });

    test('image originals are preserved and previewable as image PDFs', () {
      final temp = Directory.systemTemp.createTempSync('archive_policy_img_');
      try {
        final image = File(p.join(temp.path, 'cover.webp'))
          ..writeAsBytesSync([1, 2, 3]);
        final doc = ArchiveDocument(
          title: '教材封面',
          documentType: 'final_textbook_guide',
          period: 'final',
          courseType: 'assess',
          content: '# 教材封面\n\n> 此资料以原始文件为准。',
          filePath: image.path,
        );

        expect(ArchiveDocumentPolicy.sourceOriginalFile(doc)?.path, image.path);
        expect(ArchiveDocumentPolicy.canPreviewOriginalAsImage(image.path),
            isTrue);
        expect(
            ArchiveDocumentPolicy.canPreviewOriginalAsPdf(image.path), isFalse);
      } finally {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    });
  });
}
