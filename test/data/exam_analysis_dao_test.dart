import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/exam_analysis_dao.dart';

void main() {
  test('computeStatistics uses configured full marks instead of observed max',
      () {
    final stats = ExamAnalysisDao.computeStatistics(
      [
        [7, 8],
        [6, 7],
        [4, 6],
        [3, 5],
      ],
      fullMarks: [10, 10],
    );

    expect(stats['totalScore'], 20.0);
    expect(stats['max'], 15.0);
    expect(stats['avg'], 11.5);
    expect(stats['passCount'], 2);
    expect(stats['passRate'], 50.0);
    expect(stats['difficulty'], 0.575);

    final itemStats = stats['itemStats'] as List<dynamic>;
    expect(itemStats.first['fullMark'], 10.0);
    expect(itemStats.first['max'], 7.0);
    expect(itemStats.first['difficulty'], 0.5);
  });

  test('normalizeFullMarks pads and repairs invalid marks', () {
    expect(
      ExamAnalysisDao.normalizeFullMarks([15, 0], 4),
      [15.0, 10.0, 10.0, 10.0],
    );
  });
}
