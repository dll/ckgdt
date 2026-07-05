import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/course_subgraph_service.dart';

void main() {
  const service = CourseSubgraphService();

  test('infers literature course and generates reading subgraphs', () {
    final profile = service.inferProfile(
      courseName: '文学鉴赏',
      chapters: ['诗歌意象鉴赏', '小说叙事分析'],
      syllabusContent: '通过文本细读、作品赏析、流派比较和读书报告提升审美能力。',
    );

    expect(profile.discipline, '文学');
    expect(profile.practiceLabel, '研读实践');
    expect(profile.graphCategories, contains('文本研读图谱'));

    final subgraphs = service.generateSubgraphs(
      courseName: '文学鉴赏',
      chapters: [
        {'title': '诗歌意象鉴赏'},
        {'title': '小说叙事分析'},
      ],
      profile: profile,
    );
    final readiness =
        service.evaluateReadiness(subgraphs: subgraphs, profile: profile);

    expect(subgraphs.length, greaterThanOrEqualTo(4));
    expect(
      subgraphs.expand((g) => (g['nodes'] as List).map((n) => n['label'])),
      contains('文本细读'),
    );
    expect(readiness.passed, isTrue);
  });

  test('infers football course and generates training subgraphs', () {
    final profile = service.inferProfile(
      courseName: '足球专项',
      chapters: ['传接球技术', '局部进攻战术'],
      syllabusContent: '通过技术动作训练、体能训练、比赛观察和视频动作分析提升专项能力。',
    );

    expect(profile.discipline, '体育');
    expect(profile.practiceLabel, '训练实践');
    expect(profile.graphCategories, contains('技能训练图谱'));

    final subgraphs = service.generateSubgraphs(
      courseName: '足球专项',
      chapters: [
        {'title': '传接球技术'},
        {'title': '局部进攻战术'},
      ],
      profile: profile,
    );

    expect(
      subgraphs.expand((g) => (g['nodes'] as List).map((n) => n['label'])),
      contains('技术动作'),
    );
  });
}
