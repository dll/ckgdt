
/// 教案质量门：对 AI 返回的教案做结构化校验与确定性增强。
///
/// 核心目标：防止 AI 输出过短、缺字段或模板化，导致下游 PDF/PPTX/MP4
/// 资源“看起来空泛、无法直接授课”。所有增强都是纯本地逻辑，不依赖
/// 二次 AI 调用，保证稳定可回测。
class LessonPlanQualityGate {
  /// 最低可接受质量分（0-100）
  static const int acceptableScore = 60;

  /// 单个教学环节 content 建议的最小字符数
  static const int minSectionContentLength = 250;

  /// 评估教案质量并返回 0-100 的分数
  static int score(Map<String, dynamic> plan) {
    var score = 0;
    final objectives = _asStringList(plan['objectives']);
    if (objectives.length >= 3) score += 15;

    final keyPoints = _asStringList(plan['keyPoints']);
    if (keyPoints.length >= 2) score += 10;

    final difficulties = _asStringList(plan['difficulties']);
    if (difficulties.length >= 2) score += 10;

    final sections = _asMapList(plan['sections']);
    if (sections.length >= 3) score += 15;

    var contentLen = 0;
    for (final s in sections) {
      contentLen += (s['content']?.toString() ?? '').length;
    }
    if (contentLen >= 1200) {
      score += 25;
    } else if (contentLen >= 600) {
      score += 15;
    } else if (contentLen >= 200) {
      score += 5;
    }

    final experiments = _asMapList(plan['experiments']);
    if (experiments.isNotEmpty) score += 10;

    final homework = plan['homework']?.toString() ?? '';
    if (homework.length >= 30) score += 10;

    final refs = _asStringList(plan['references']);
    if (refs.isNotEmpty) score += 5;

    return score;
  }

  /// 校验并增强教案，返回可直接用于生成资源的新 Map。
  static Map<String, dynamic> ensureTeachable(
    Map<String, dynamic> plan, {
    required String topic,
    String? chapter,
    required int classHours,
  }) {
    final result = Map<String, dynamic>.from(plan);
    final title = (result['title']?.toString() ?? topic).trim();
    final chapterText = (result['chapter']?.toString() ?? chapter ?? '').trim();
    result['title'] = title.isNotEmpty ? title : topic;
    result['chapter'] = chapterText;
    result['classHours'] = (result['classHours'] as int?) ?? classHours;

    // 教学目标（布鲁姆三层兜底）
    final objectives = _asStringList(result['objectives']);
    final defaultObjectives = [
      '学生能够解释$topic的基本概念与核心术语',
      '学生能够运用$topic的关键方法解决典型问题',
      '学生能够评价不同场景下$topic方案的适用性',
    ];
    while (objectives.length < 3) {
      objectives.add(defaultObjectives[objectives.length]);
    }
    result['objectives'] = objectives;

    // 教学重点
    final keyPoints = _asStringList(result['keyPoints']);
    final defaultKeyPoints = [
      '$topic的核心概念与工作原理',
      '$topic的典型应用场景与使用步骤',
    ];
    while (keyPoints.length < 2) {
      keyPoints.add(defaultKeyPoints[keyPoints.length]);
    }
    result['keyPoints'] = keyPoints;

    // 教学难点
    final difficulties = _asStringList(result['difficulties']);
    final defaultDifficulties = [
      '$topic中容易混淆的概念辨析',
      '$topic在实际问题中的综合应用',
    ];
    while (difficulties.length < 2) {
      difficulties.add(defaultDifficulties[difficulties.length]);
    }
    result['difficulties'] = difficulties;

    // 教学环节
    var sections = _asMapList(result['sections']);
    if (sections.isEmpty) {
      sections = _fallbackSections(topic, classHours);
    }
    _enrichSections(sections, topic, classHours);
    result['sections'] = sections;

    // 实验/实践
    var experiments = _asMapList(result['experiments']);
    if (experiments.isEmpty) {
      experiments = [
        {
          'name': '$topic实践练习',
          'objective': '通过动手操作加深对$topic的理解',
          'steps': [
            '明确任务要求与输入数据',
            '按照核心步骤完成$topic相关操作',
            '记录运行结果与遇到的问题',
            '总结关键发现与改进方向',
          ],
          'deliverables': '提交操作过程截图与简短总结报告',
        }
      ];
    }
    result['experiments'] = experiments;

    // UML 图表（仅对明显软件/编程类主题兜底）
    var umlDiagrams = _asMapList(result['umlDiagrams']);
    if (umlDiagrams.isEmpty && _looksLikeSoftwareTopic(topic)) {
      umlDiagrams = [
        {
          'type': 'class',
          'title': '$topic核心类图',
          'description': '描述$topic中主要实体/类的属性、方法及其关系',
        },
        {
          'type': 'sequence',
          'title': '$topic执行时序图',
          'description': '描述$topic典型流程中各组件的调用顺序',
        },
      ];
    }
    result['umlDiagrams'] = umlDiagrams;

    // 课后作业（三层）
    var homework = result['homework']?.toString() ?? '';
    if (homework.length < 30) {
      homework = _defaultHomework(topic);
    }
    result['homework'] = homework;

    // 参考资料
    final references = _asStringList(result['references']);
    if (references.isEmpty) {
      references.addAll([
        '教材相关章节',
        '$topic 官方文档或权威教程',
      ]);
    }
    result['references'] = references;

    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 内部辅助
  // ─────────────────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _fallbackSections(
      String topic, int hours) {
    final coreDuration = '${hours * 45 - 20}分钟';
    return [
      {
        'title': '课程导入与目标',
        'duration': '10分钟',
        'content': '通过生活化案例引出$topic的学习价值，明确本节课要解决的核心问题。',
        'activities': '教师展示案例并提问，学生思考并口头回应',
        'notes': '板书：$topic = 问题 + 方法 + 应用',
      },
      {
        'title': '核心概念讲解',
        'duration': coreDuration,
        'content': '系统讲解$topic的核心概念、工作原理与关键步骤。',
        'activities': '讲授+示例演示+即时提问',
        'notes': '配合板书或图示，强调关键步骤',
      },
      {
        'title': '总结与作业',
        'duration': '10分钟',
        'content': '回顾本节课重点，布置分层作业。',
        'activities': '师生共同总结，教师发布作业',
        'notes': '预留答疑时间',
      },
    ];
  }

  static void _enrichSections(
    List<Map<String, dynamic>> sections,
    String topic,
    int hours,
  ) {
    final totalMinutes = hours * 45;

    // AI 返回的环节过少时补齐导入-核心-总结三段式结构
    if (sections.length == 1) {
      sections.add({
        'title': '核心概念讲解',
        'duration': '${totalMinutes - 20}分钟',
        'content': '',
      });
    }
    if (sections.length == 2) {
      sections.add({
        'title': '总结与作业',
        'duration': '10分钟',
        'content': '',
      });
    }

    var allocated = 0;

    for (var i = 0; i < sections.length; i++) {
      final s = Map<String, dynamic>.from(sections[i]);
      final title = (s['title']?.toString() ?? '环节${i + 1}').trim();
      s['title'] = title;

      var content = (s['content']?.toString() ?? '').trim();
      var activities = (s['activities']?.toString() ?? '').trim();
      var codeExample = (s['codeExample']?.toString() ?? '').trim();
      final notes = (s['notes']?.toString() ?? '').trim();

      // content 过短时做确定性扩展
      if (content.length < minSectionContentLength) {
        content = _expandSectionContent(title, content, topic, i, sections.length);
      }
      // 确保有真实案例（总结页除外）
      if (content.isNotEmpty &&
          !_containsCase(content) &&
          title != '总结与作业') {
        content +=
            '\n真实案例：以校园选课系统为例，$topic可以帮助学生快速发现课程之间的先修关系，避免选课冲突。';
      }
      // 确保有常见误区（总结页除外）
      if (content.isNotEmpty &&
          !_containsMisconception(content) &&
          title != '总结与作业') {
        content +=
            '\n常见误区与纠正：初学者常将$topic与简单列表混淆，实际上$topic强调实体之间的语义关联与可推理能力。';
      }
      // 确保有课堂互动问题（总结页除外）
      if (content.isNotEmpty &&
          !_containsInteraction(content) &&
          title != '总结与作业') {
        content +=
            '\n课堂互动问题：请结合自己的专业背景，举一个可以用$topic解决的实际问题，并说明需要哪些数据支撑。';
      }

      if (activities.isEmpty) {
        s['activities'] = i == sections.length - 1
            ? '师生共同总结，教师发布作业'
            : '讲授+示例演示+即时提问';
      }
      if (codeExample.isEmpty && _looksLikeCodeTopic(title, content)) {
        codeExample = _defaultCodeExample(topic);
      }
      if (codeExample.isNotEmpty) s['codeExample'] = codeExample;
      if (notes.isEmpty) {
        s['notes'] = i == 0
            ? '用案例吸引学生注意，建立学习兴趣'
            : '强调关键步骤，预留学生思考时间';
      }
      s['content'] = content;
      sections[i] = s;

      final durationMatch =
          RegExp(r'(\d+)\s*分钟').firstMatch(s['duration']?.toString() ?? '');
      if (durationMatch != null) {
        allocated += int.parse(durationMatch.group(1)!);
      }
    }

    // 如果时长明显不合理，按环节数均分
    if (allocated <= 0 || allocated > totalMinutes * 1.5) {
      final perSection = totalMinutes ~/ sections.length;
      for (var i = 0; i < sections.length; i++) {
        if (i < sections.length - 1) {
          sections[i]['duration'] = '$perSection分钟';
        } else {
          sections[i]['duration'] =
              '${totalMinutes - perSection * (sections.length - 1)}分钟';
        }
      }
    }
  }

  static String _expandSectionContent(
    String title,
    String existing,
    String topic,
    int index,
    int total,
  ) {
    if (existing.isEmpty) {
      if (index == 0) {
        return '首先，通过贴近学生生活或专业背景的实际案例引出$topic的学习价值。'
            '让学生意识到$topic并非抽象理论，而是解决真实问题的有效工具。'
            '本环节明确本节课的核心目标与预期产出，并与已学知识建立衔接。';
      }
      if (index == total - 1) {
        return '最后，带领学生一起回顾本节课的核心知识点，梳理$topic的关键概念、方法与典型应用场景。'
            '在此基础上布置分层作业，基础题巩固概念，提高题训练综合应用，拓展题引导学生进行延伸探究。';
      }
      return '本环节系统讲解$topic的核心概念、关键原理与操作步骤。'
          '通过具体示例帮助学生理解抽象知识，并引导学生关注容易出错的关键细节。';
    }

    if (index == 0) {
      return '$existing\n为什么要学习$topic？因为它能够帮助我们用结构化的方式描述复杂世界中的实体与关系，'
          '从而支持搜索、推荐、问答等智能应用。本环节将通过一个真实案例让学生直观感受$topic的用处。';
    }
    if (index == total - 1) {
      return '$existing\n在总结环节，我们将用一张思维导图回顾$topic的核心要点，并通过课堂提问检验学生的掌握情况。'
          '课后请完成分层作业，巩固本节所学内容。';
    }
    return '$existing\n为加深理解，本环节将给出一个贴近实际的$topic应用案例，并剖析其关键实现思路。'
        '同时指出初学者最容易犯的几种错误，并通过一道课堂互动问题检验理解。';
  }

  static bool _containsCase(String text) =>
      text.contains('案例') ||
      text.contains('例如') ||
      text.contains('比如') ||
      text.contains('以');

  static bool _containsMisconception(String text) =>
      text.contains('误区') ||
      text.contains('注意') ||
      text.contains('混淆') ||
      text.contains('易错');

  static bool _containsInteraction(String text) =>
      text.contains('?') ||
      text.contains('？') ||
      text.contains('互动') ||
      text.contains('思考') ||
      text.contains('讨论');

  static bool _looksLikeCodeTopic(String? title, String? content) {
    final combined = '${title ?? ''} ${content ?? ''}';
    const codeKeywords = [
      '代码', '编程', '算法', '函数', '类', '实现', 'Python', 'Java', 'Dart',
      '程序', '接口', '变量', '循环', '调试', '运行', '示例', '语法'
    ];
    return codeKeywords.any((k) => combined.contains(k));
  }

  static bool _looksLikeSoftwareTopic(String topic) {
    const keywords = [
      '软件', '程序', '系统', '代码', '算法', '类', '接口', '架构', '工程',
      '开发', '设计模式', '数据库', '网络', 'Web', '前端', '后端', '移动'
    ];
    return keywords.any((k) => topic.contains(k));
  }

  static String _defaultCodeExample(String topic) {
    if (topic.contains('Python') || topic.contains('python')) {
      return '# 最小可运行示例\n'
          'def greet(name):\n'
          '    return f"Hello, {name}!"\n'
          '\n'
          'print(greet("World"))';
    }
    return 'public class Demo {\n'
        '  public static void main(String[] args) {\n'
        '    System.out.println("Hello, $topic");\n'
        '  }\n'
        '}';
  }

  static String _defaultHomework(String topic) {
    return '基础题：简述$topic的核心概念与典型应用场景。\n'
        '提高题：完成一个$topic的典型案例分析，说明其关键步骤与注意事项。\n'
        '拓展题：查阅资料，比较$topic与一种相关技术的异同，并给出适用场景建议。';
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }
}
