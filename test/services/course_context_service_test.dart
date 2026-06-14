import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/course_context_service.dart';

void main() {
  group('CourseContextService', () {
    test('buildStableCourseId keeps ascii names readable', () {
      expect(
        CourseContextService.buildStableCourseId('Software Engineering 2026'),
        'software_engineering_2026',
      );
    });

    test('buildStableCourseId creates stable ids for Chinese course names', () {
      final id1 = CourseContextService.buildStableCourseId('软件工程');
      final id2 = CourseContextService.buildStableCourseId('软件工程');

      expect(id1, startsWith('course_'));
      expect(id1, id2);
    });

    test('formatChapterTitle normalizes generated course chapters', () {
      expect(
        CourseContextService.formatChapterTitle('需求分析与建模', 2),
        '第2章 需求分析与建模',
      );
      expect(
        CourseContextService.formatChapterTitle('3. 软件设计', 3),
        '第3章 软件设计',
      );
    });
  });
}
