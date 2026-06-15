import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/presentation/pages/archive/archive_constants.dart';

void main() {
  test('midterm archive keeps formal 08/15/16 materials only', () {
    for (final courseType in ['exam', 'assess']) {
      final docs = docsForPeriod(courseType, 'midterm');

      expect(
        docs.map((d) => d.key).toList(),
        [
          'midterm_progress_check',
          'midterm_homework_review',
          'midterm_exam',
        ],
      );
      expect(
        docs.map((d) => d.label).toList(),
        [
          '课程进度执行检查',
          '作业与批阅次数统计',
          '期中考试',
        ],
      );
      expect(docs.map((d) => d.key).toSet(), hasLength(docs.length));
    }
  });
}
