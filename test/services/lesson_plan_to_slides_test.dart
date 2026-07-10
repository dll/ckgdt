import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/courseware_service.dart';

void main() {
  final service = CoursewareService();

  final richLessonPlan = {
    'title': '知识图谱构建',
    'chapter': '第三章 知识图谱技术',
    'classHours': 2,
    'objectives': [
      '学生能够解释知识图谱的三元组模型',
      '学生能够运用实体识别与关系抽取方法构建简单知识图谱',
    ],
    'keyPoints': ['三元组模型是知识图谱的核心抽象'],
    'difficulties': ['关系抽取中的歧义消解'],
    'sections': [
      {
        'title': '知识图谱概述',
        'duration': '15分钟',
        'content':
            '知识图谱是一种用图结构描述现实世界概念及其关系的语义网络。它最早由 Google 在 2012 年提出。\n'
            '一个知识图谱由实体、关系和属性组成。实体代表对象，关系描述联系，属性刻画特征。\n'
            '以"清华大学位于北京"为例，它可以表示为三元组（清华大学，位于，北京）。这种表示方式简洁且便于机器推理。\n'
            '常见误区：很多同学把知识图谱简单理解为数据库表。实际上，知识图谱强调语义关联。',
        'activities': '教师展示搜索知识卡片，学生举例身边三元组',
        'codeExample': '',
        'notes': '用学生熟悉的学校、城市做例子',
      },
      {
        'title': '知识抽取',
        'duration': '30分钟',
        'content':
            '知识抽取是从文本中自动识别实体、关系和事件的过程。它包括命名实体识别、关系抽取和属性抽取三个子任务。\n'
            '例如，对于句子"马云创办了阿里巴巴"，实体识别得到"马云"和"阿里巴巴"，关系抽取得到"创办"关系。\n'
            '课堂互动：请大家尝试从给定句子中抽取出实体和关系。',
        'activities': '讲授+板书示例+小组练习',
        'codeExample': '# Python 三元组示例\\ntriple = {"head": "马云", "relation": "创办", "tail": "阿里巴巴"}',
        'notes': '提醒学生注意关系方向性',
      },
    ],
    'experiments': [
      {
        'name': '从百科文本中抽取三元组',
        'objective': '掌握基于规则的关系抽取方法',
        'steps': ['选择文本', '识别人名', '抽取关系', '保存 JSON'],
        'deliverables': '提交 JSON 文件',
      }
    ],
    'umlDiagrams': [],
    'homework': '基础题：简述三元组模型。提高题：抽取 5 个三元组。',
    'references': ['《知识图谱》'],
  };

  test('splits long section content into multiple bullets and continuation slides',
      () {
    final slides = service.lessonPlanToSlides(richLessonPlan);

    // Should have overview, key-difficulty, section slides, code slides, experiment, homework
    expect(slides.length, greaterThan(6));

    // Find slides for "知识图谱概述"
    final overviewSlides = slides
        .where((s) => (s['title'] as String).startsWith('知识图谱概述'))
        .toList();
    expect(overviewSlides.length, greaterThanOrEqualTo(1));
    final firstOverview = overviewSlides.first;
    expect(firstOverview['subtitle'], contains('15分钟'));
    expect(firstOverview['bullets'], isA<List>());
    expect((firstOverview['bullets'] as List).length, lessThanOrEqualTo(6));
  });

  test('creates a dedicated code slide for codeExample', () {
    final slides = service.lessonPlanToSlides(richLessonPlan);
    final codeSlides = slides
        .where((s) => (s['title'] as String).contains('代码示例'))
        .toList();
    expect(codeSlides.length, greaterThanOrEqualTo(1));
    final codeSlide = codeSlides.first;
    expect(codeSlide['code'], isNotEmpty);
    expect(codeSlide['code'], contains('triple'));
  });
}
