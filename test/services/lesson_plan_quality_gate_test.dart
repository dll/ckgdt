import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/lesson_plan_quality_gate.dart';

void main() {
  test('fills missing fields in a thin plan', () {
    final thin = {
      'title': '',
      'sections': [
        {
          'title': '导入',
          'content': '今天学习知识图谱。',
        }
      ],
    };

    final enriched = LessonPlanQualityGate.ensureTeachable(
      thin,
      topic: '知识图谱',
      chapter: '第三章',
      classHours: 2,
    );

    expect(enriched['title'], '知识图谱');
    expect(enriched['chapter'], '第三章');
    expect((enriched['objectives'] as List).length, greaterThanOrEqualTo(3));
    expect((enriched['keyPoints'] as List).length, greaterThanOrEqualTo(2));
    expect((enriched['difficulties'] as List).length, greaterThanOrEqualTo(2));
    expect((enriched['sections'] as List).length, greaterThanOrEqualTo(3));
    expect((enriched['experiments'] as List).isNotEmpty, isTrue);
    expect((enriched['homework'] as String).length, greaterThan(30));
    expect((enriched['references'] as List).isNotEmpty, isTrue);
  });

  test('does not overwrite existing rich content', () {
    final rich = {
      'title': '知识图谱',
      'objectives': ['目标1', '目标2', '目标3'],
      'keyPoints': ['重点1'],
      'difficulties': ['难点1'],
      'sections': [
        {
          'title': '导入',
          'content': '这是一段很长的教学内容。' * 20,
          'activities': '讨论',
          'notes': '备注',
        }
      ],
      'experiments': [
        {'name': '实验1', 'objective': '目标', 'steps': ['步骤1'], 'deliverables': '报告'}
      ],
      'homework': '基础题：简述核心概念；提高题：完成案例分析；拓展题：比较相关技术。',
      'references': ['教材'],
    };

    final enriched = LessonPlanQualityGate.ensureTeachable(
      rich,
      topic: '知识图谱',
      chapter: '第三章',
      classHours: 2,
    );

    expect(enriched['objectives'], ['目标1', '目标2', '目标3']);
    expect((enriched['keyPoints'] as List).length, 2);
    expect((enriched['difficulties'] as List).length, 2);
    // 环节过少时会补齐为导入-核心-总结三段式
    expect((enriched['sections'] as List).length, 3);
    expect(enriched['homework'], '基础题：简述核心概念；提高题：完成案例分析；拓展题：比较相关技术。');
  });

  test('score reflects completeness', () {
    final thin = {'sections': []};
    final rich = {
      'objectives': ['a', 'b', 'c'],
      'keyPoints': ['a', 'b'],
      'difficulties': ['a', 'b'],
      'sections': [
        {'content': 'x' * 500},
        {'content': 'y' * 500},
        {'content': 'z' * 500},
      ],
      'experiments': [{}],
      'homework': '基础题、提高题、拓展题',
      'references': ['教材'],
    };

    expect(LessonPlanQualityGate.score(thin), lessThan(30));
    expect(LessonPlanQualityGate.score(rich), greaterThanOrEqualTo(60));
  });
}
