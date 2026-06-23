import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI submission gate regression', () {
    final submitFiles = [
      File('lib/presentation/pages/learning/student_lab_page.dart'),
      File('lib/presentation/pages/lab/tabs/task_list_tab.dart'),
      File('lib/presentation/pages/assessment/tabs/report_tab.dart'),
      File('lib/presentation/pages/works/tabs/work_detail_sheet.dart'),
    ];

    test('student submissions are not blocked by AI score or availability', () {
      for (final file in submitFiles) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('getEvaluationPassScore')),
          reason: '${file.path} must not gate submission by score threshold',
        );
        expect(
          source,
          isNot(contains('_showAiDraftBlockedDialog')),
          reason: '${file.path} must not show the old AI blocking dialog',
        );
        expect(
          source,
          isNot(contains('_confirmDirectSubmitWithoutTeacherAi')),
          reason: '${file.path} must not add pre-submit AI confirmation gates',
        );
        expect(
          source,
          isNot(contains('提交失败：AI 服务暂时不可用')),
          reason: '${file.path} must not fail student submission on AI outage',
        );
      }
    });

    test('student submissions trigger background AI grading when enabled', () {
      for (final file in submitFiles) {
        final source = file.readAsStringSync();
        expect(source, contains('returnDraft: false'), reason: file.path);
        expect(source, contains('notifyStudent: true'), reason: file.path);
      }
    });

    test('teacher evaluation hub no longer exposes submission pass score setup',
        () {
      final source =
          File('lib/presentation/pages/home/evaluation_hub_page.dart')
              .readAsStringSync();
      expect(source, isNot(contains('评价达标分数线')));
      expect(source, isNot(contains('setEvaluationPassScore')));
    });
  });
}
