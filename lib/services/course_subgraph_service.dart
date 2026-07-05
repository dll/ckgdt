import 'dart:convert';

/// Generates platform-ready subgraphs from a course syllabus.
///
/// The service is deterministic and works without AI, so every course can
/// still get editable graph scaffolds when the AI provider is unavailable.
class CourseSubgraphService {
  const CourseSubgraphService();

  CourseProfile inferProfile({
    required String courseName,
    required List<String> chapters,
    String? syllabusContent,
  }) {
    final text = '$courseName ${chapters.join(' ')} ${syllabusContent ?? ''}';
    final normalized = text.toLowerCase();

    if (_hasAny(normalized, const [
      '足球',
      '篮球',
      '排球',
      '田径',
      '体育',
      '专项',
      '训练',
      '体能',
      '战术',
      '动作',
      '比赛',
    ])) {
      return const CourseProfile(
        discipline: '体育',
        courseMode: '技能训练型',
        practiceLabel: '训练实践',
        graphCategories: ['课程图谱', '技能训练图谱', '战术规则图谱', '评价达成图谱'],
        evidenceTypes: ['训练记录', '动作视频', '技能测试', '比赛观察', '训练反思'],
        rubricDimensions: ['动作规范', '技能熟练度', '战术理解', '体能表现', '训练态度'],
      );
    }

    if (_hasAny(normalized, const [
      '文学',
      '鉴赏',
      '小说',
      '诗歌',
      '戏剧',
      '散文',
      '文本',
      '作家',
      '作品',
      '流派',
      '意象',
      '叙事',
    ])) {
      return const CourseProfile(
        discipline: '文学',
        courseMode: '赏析研读型',
        practiceLabel: '研读实践',
        graphCategories: ['课程图谱', '文本研读图谱', '主题流派图谱', '评价达成图谱'],
        evidenceTypes: ['文本批注', '读书报告', '课堂讨论', '赏析论文', '口头表达'],
        rubricDimensions: ['文本理解', '细读证据', '审美判断', '批评方法', '表达质量'],
      );
    }

    if (_hasAny(normalized, const [
      '艺术',
      '美术',
      '音乐',
      '设计',
      '舞蹈',
      '绘画',
      '创作',
      '展演',
      '作品集',
      '审美',
    ])) {
      return const CourseProfile(
        discipline: '艺术',
        courseMode: '创作展演型',
        practiceLabel: '创作实践',
        graphCategories: ['课程图谱', '创作技法图谱', '作品展评图谱', '评价达成图谱'],
        evidenceTypes: ['作品图片', '创作过程', '展演记录', '作品集', '互评反馈'],
        rubricDimensions: ['主题表达', '技法掌握', '创作过程', '审美完成度', '展示交流'],
      );
    }

    if (_hasAny(normalized, const [
      '案例',
      '管理',
      '经济',
      '金融',
      '法学',
      '法律',
      '营销',
      '会计',
      '决策',
      '商业',
    ])) {
      return const CourseProfile(
        discipline: '经管法',
        courseMode: '案例决策型',
        practiceLabel: '案例实践',
        graphCategories: ['课程图谱', '案例情境图谱', '决策论证图谱', '评价达成图谱'],
        evidenceTypes: ['案例分析', '决策方案', '辩论记录', '调研数据', '反思报告'],
        rubricDimensions: ['事实识别', '理论应用', '推理逻辑', '决策质量', '表达辩论'],
      );
    }

    if (_hasAny(normalized, const [
      '医学',
      '护理',
      '临床',
      '康复',
      '药学',
      '师范',
      '教学技能',
      '模拟',
      '操作规范',
    ])) {
      return const CourseProfile(
        discipline: '技能',
        courseMode: '技能模拟型',
        practiceLabel: '技能实践',
        graphCategories: ['课程图谱', '技能规范图谱', '情境模拟图谱', '评价达成图谱'],
        evidenceTypes: ['操作记录', '模拟视频', '技能清单', '反思报告', '教师观察'],
        rubricDimensions: ['操作规范', '情境判断', '安全伦理', '过程记录', '反思改进'],
      );
    }

    return const CourseProfile(
      discipline: '通用',
      courseMode: '理论实践型',
      practiceLabel: '实践任务',
      graphCategories: ['课程图谱', '实践活动图谱', '学习资源图谱', '评价达成图谱'],
      evidenceTypes: ['作业', '实践报告', '测验', '作品', '课堂表现'],
      rubricDimensions: ['知识理解', '实践应用', '问题分析', '表达呈现', '持续改进'],
    );
  }

  List<Map<String, dynamic>> generateSubgraphs({
    required String courseName,
    required List<Map<String, dynamic>> chapters,
    String? syllabusContent,
    CourseProfile? profile,
  }) {
    final chapterTitles = chapters
        .map((chapter) => chapter['title']?.toString() ?? '')
        .where((title) => title.trim().isNotEmpty)
        .toList();
    final resolvedProfile = profile ??
        inferProfile(
          courseName: courseName,
          chapters: chapterTitles,
          syllabusContent: syllabusContent,
        );
    final normalizedChapters =
        chapterTitles.isEmpty ? ['课程导论', '核心内容', '综合实践'] : chapterTitles;

    final subgraphs = <Map<String, dynamic>>[];
    for (var i = 0; i < resolvedProfile.graphCategories.length; i++) {
      final category = resolvedProfile.graphCategories[i];
      subgraphs.add(_buildCategoryGraph(
        courseName: courseName,
        category: category,
        categoryIndex: i,
        chapters: normalizedChapters,
        profile: resolvedProfile,
      ));
    }
    return subgraphs;
  }

  PlatformReadinessResult evaluateReadiness({
    required List<Map<String, dynamic>> subgraphs,
    required CourseProfile profile,
  }) {
    final issues = <String>[];
    if (profile.graphCategories.length < 4) {
      issues.add('课程子图谱分类少于4类');
    }
    if (profile.evidenceTypes.isEmpty) {
      issues.add('缺少课程证据类型');
    }
    if (profile.rubricDimensions.isEmpty) {
      issues.add('缺少评价量规维度');
    }
    if (subgraphs.isEmpty) {
      issues.add('未生成子图谱');
    }
    for (final graph in subgraphs) {
      final nodes = graph['nodes'] as List? ?? const [];
      final edges = graph['edges'] as List? ?? const [];
      final category = graph['category']?.toString() ?? '未命名图谱';
      if (nodes.length < 3) issues.add('$category 节点不足');
      if (edges.isEmpty) issues.add('$category 缺少关系');
    }
    return PlatformReadinessResult(
      passed: issues.isEmpty,
      issues: issues,
      score: issues.isEmpty ? 100 : (100 - issues.length * 12).clamp(0, 100),
    );
  }

  String graphCategoriesJson(List<Map<String, dynamic>> subgraphs) {
    final categories = subgraphs.asMap().entries.map((entry) {
      return {
        'dir':
            '${(entry.key + 1).toString().padLeft(2, '0')}-${entry.value['category']}',
        'label': entry.value['category'],
        'color': entry.value['color'] ?? '#1677FF',
      };
    }).toList();
    return const JsonEncoder.withIndent('  ')
        .convert({'categories': categories});
  }

  Map<String, dynamic> _buildCategoryGraph({
    required String courseName,
    required String category,
    required int categoryIndex,
    required List<String> chapters,
    required CourseProfile profile,
  }) {
    final slug = _slug(category);
    final rootId = '${slug}_root';
    final nodes = <Map<String, dynamic>>[
      {
        'id': rootId,
        'label': '$courseName$category',
        'type': 'root',
        'level': 0,
        'content':
            '${profile.discipline} · ${profile.courseMode} · ${profile.practiceLabel}',
      },
    ];
    final edges = <Map<String, dynamic>>[];

    if (category.contains('课程')) {
      for (var i = 0; i < chapters.length; i++) {
        final chapterId = '${slug}_chapter_${i + 1}';
        nodes.add({
          'id': chapterId,
          'label': chapters[i],
          'type': 'chapter',
          'level': 1,
          'parent_id': rootId,
          'content': '章节节点，可继续编辑知识点、活动和评价关系。',
        });
        edges.add({
          'from': rootId,
          'to': chapterId,
          'type': 'contains',
          'label': '包含',
        });
      }
    } else if (category.contains('评价') || category.contains('达成')) {
      for (var i = 0; i < profile.rubricDimensions.length; i++) {
        final nodeId = '${slug}_rubric_${i + 1}';
        nodes.add({
          'id': nodeId,
          'label': profile.rubricDimensions[i],
          'type': 'rubric',
          'level': 1,
          'parent_id': rootId,
          'content': '评价维度，可映射到课程目标、作业、实践任务和达成评价。',
        });
        edges.add({
          'from': rootId,
          'to': nodeId,
          'type': 'assesses',
          'label': '评价',
        });
      }
    } else if (category.contains('资源')) {
      for (var i = 0; i < profile.evidenceTypes.length; i++) {
        final nodeId = '${slug}_evidence_${i + 1}';
        nodes.add({
          'id': nodeId,
          'label': profile.evidenceTypes[i],
          'type': 'evidence',
          'level': 1,
          'parent_id': rootId,
          'content': '课程证据类型，用于数字孪生画像、达成评价和归档。',
        });
        edges.add({
          'from': rootId,
          'to': nodeId,
          'type': 'collects',
          'label': '采集',
        });
      }
    } else {
      final activities = _activityNodes(profile);
      for (var i = 0; i < activities.length; i++) {
        final nodeId = '${slug}_activity_${i + 1}';
        nodes.add({
          'id': nodeId,
          'label': activities[i],
          'type': 'activity',
          'level': 1,
          'parent_id': rootId,
          'content': '根据课程大纲生成的活动节点，可编辑为具体任务。',
        });
        edges.add({
          'from': rootId,
          'to': nodeId,
          'type': 'guides',
          'label': '组织',
        });
      }
    }

    return {
      'category': category,
      'slug': slug,
      'color': _colors[categoryIndex % _colors.length],
      'course_profile': profile.toMap(),
      'nodes': nodes,
      'edges': edges,
    };
  }

  List<String> _activityNodes(CourseProfile profile) {
    switch (profile.discipline) {
      case '文学':
        return const ['文本细读', '意象分析', '主题辨析', '课堂讨论', '赏析写作'];
      case '体育':
        return const ['技术动作', '体能训练', '战术配合', '比赛观察', '训练反思'];
      case '艺术':
        return const ['技法练习', '创作构思', '过程记录', '作品展评', '审美反思'];
      case '经管法':
        return const ['案例事实', '理论框架', '方案决策', '论证表达', '复盘改进'];
      case '技能':
        return const ['操作规范', '情境模拟', '过程观察', '安全伦理', '反思改进'];
      default:
        return const ['核心概念', '实践活动', '学习资源', '成果证据', '改进建议'];
    }
  }

  bool _hasAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }

  String _slug(String value) {
    final codeUnits = value.codeUnits.map((c) => c.toRadixString(16)).join();
    return 'sg_${codeUnits.length > 20 ? codeUnits.substring(0, 20) : codeUnits}';
  }

  static const _colors = [
    '#E53935',
    '#1E88E5',
    '#43A047',
    '#FB8C00',
    '#8E24AA',
    '#00897B',
  ];
}

class CourseProfile {
  final String discipline;
  final String courseMode;
  final String practiceLabel;
  final List<String> graphCategories;
  final List<String> evidenceTypes;
  final List<String> rubricDimensions;

  const CourseProfile({
    required this.discipline,
    required this.courseMode,
    required this.practiceLabel,
    required this.graphCategories,
    required this.evidenceTypes,
    required this.rubricDimensions,
  });

  Map<String, dynamic> toMap() => {
        'discipline': discipline,
        'course_mode': courseMode,
        'practice_label': practiceLabel,
        'graph_categories': graphCategories,
        'evidence_types': evidenceTypes,
        'rubric_dimensions': rubricDimensions,
      };
}

class PlatformReadinessResult {
  final bool passed;
  final List<String> issues;
  final int score;

  const PlatformReadinessResult({
    required this.passed,
    required this.issues,
    required this.score,
  });
}
