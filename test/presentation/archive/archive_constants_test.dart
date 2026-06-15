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

  test('final archive follows school bag 00-12 material list', () {
    for (final courseType in ['exam', 'assess']) {
      final docs = docsForPeriod(courseType, 'final');

      expect(
        docs.map((d) => d.key).toList(),
        [
          'final_archive_catalog',
          'final_syllabus',
          'final_syllabus_evaluation',
          'final_teaching_schedule',
          'final_lesson_plan',
          'final_syllabus_review',
          'final_assessment_review',
          'final_grade_book',
          'final_score_register',
          'final_assessment_description',
          'final_achievement_report',
          'final_textbook_guide',
          'final_sample_works',
        ],
      );
      expect(docs.map((d) => d.key).toSet(), hasLength(13));
      expect(docs.every((d) => d.canImport), isTrue);
      expect(docs.every((d) => d.needsGeneration), isTrue);
    }
  });

  test('closure archive tab does not duplicate all materials card', () {
    final examDocs = docsForPeriod('exam', 'archive');
    final assessDocs = docsForPeriod('assess', 'archive');

    expect(examDocs.map((d) => d.key), isNot(contains('all_materials')));
    expect(assessDocs.map((d) => d.key), isNot(contains('all_materials')));
    expect(examDocs.map((d) => d.key), contains('archive_form'));
    expect(assessDocs.map((d) => d.key), contains('archive_form'));
  });
}
