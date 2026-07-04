import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/error_handler.dart';
import 'ai_service.dart';
import 'course_context_service.dart';

/// 课程资源统一生成服务
/// 在用户输入课程名+章节后，生成完整的课程资源包（与 CKGDT 同等质量）
class CourseGenerationService {
  static final CourseGenerationService instance = CourseGenerationService._();
  CourseGenerationService._();

  final AiService _ai = AiService();

  /// 生成进度回调
  void Function(String step, double progress)? onProgress;

  CourseGenerationService({this.onProgress});

  /// 完整生成流程：输入课程信息 → 输出完整资源包
  Future<CourseGenerationResult> generateAll({
    required String courseName,
    required List<String> chapters,
    String? syllabusContent,
    Map<String, dynamic>? existingConfig,
  }) async {
    final courseId = CourseContextService.buildStableCourseId(courseName);
    final result =
        CourseGenerationResult(courseId: courseId, courseName: courseName);

    try {
      // 1. 基础配置
      _report('生成基础配置', 0.0);
      result.config =
          await _generateConfig(courseName, chapters, existingConfig);

      // 2. 章节配置
      _report('生成章节配置', 0.1);
      result.chapters =
          await _generateChapters(courseName, chapters, syllabusContent);

      // 3. 测验题目（每章 10 题）
      _report('生成测验题目', 0.2);
      result.quizzes =
          await _generateQuizzes(courseName, chapters, syllabusContent);

      // 4. 视频脚本（每章 1 个）
      _report('生成视频脚本', 0.4);
      result.videoScripts =
          await _generateVideoScripts(courseName, chapters, syllabusContent);

      // 5. 课件内容（每章 1 个）
      _report('生成课件内容', 0.5);
      result.courseware =
          await _generateCourseware(courseName, chapters, syllabusContent);

      // 6. 图谱定义（7 类）
      _report('生成图谱定义', 0.6);
      result.graphs = await _generateGraphDefinitions(courseName, chapters);

      // 7. 实验任务
      _report('生成实验任务', 0.7);
      result.labTasks =
          await _generateLabTasks(courseName, chapters, syllabusContent);

      // 8. 课后作业
      _report('生成课后作业', 0.78);
      result.homeworks = _generateHomeworks(courseName, chapters);

      // 9. 报告模板
      _report('生成报告模板', 0.8);
      result.reportTemplates =
          await _generateReportTemplates(courseName, chapters);

      // 10. 达成配置
      _report('生成达成配置', 0.9);
      result.achievementConfig =
          await _generateAchievementConfig(courseName, chapters);

      // 11. 考核配置
      _report('生成考核配置', 0.95);
      result.assessmentConfig =
          await _generateAssessmentConfig(courseName, chapters);

      _report('生成完成', 1.0);
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseGenerationService.generateAll', stack: st);
      result.error = e.toString();
    }

    return result;
  }

  /// 生成基础配置
  Future<Map<String, dynamic>> _generateConfig(
    String courseName,
    List<String> chapters,
    Map<String, dynamic>? existing,
  ) async {
    if (existing != null) return existing;

    final prompt = '''
为《$courseName》课程生成配置文件，返回 JSON：
{
  "course_name": "$courseName",
  "version": "1.0.0",
  "description": "课程简介（50字以内）",
  "total_weeks": 16,
  "weekly_hours": 2,
  "credits": 2,
  "category": "专业选修课",
  "objectives": [
    {"id": 1, "name": "目标1名称", "description": "目标1描述", "weight": 0.25},
    {"id": 2, "name": "目标2名称", "description": "目标2描述", "weight": 0.25},
    {"id": 3, "name": "目标3名称", "description": "目标3描述", "weight": 0.25},
    {"id": 4, "name": "目标4名称", "description": "目标4描述", "weight": 0.25}
  ]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    return _parseJson(response) ??
        {
          'course_name': courseName,
          'objectives': [],
        };
  }

  /// 生成章节配置
  Future<List<Map<String, dynamic>>> _generateChapters(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final prompt = '''
为《$courseName》课程的以下章节生成详细配置，返回 JSON 数组：
章节列表：${chapters.join('、')}

${syllabusContent != null ? '教学大纲摘要：\n$syllabusContent' : ''}

每个章节返回：
{
  "number": 1,
  "title": "章节标题",
  "description": "章节简介",
  "sub_chapters": ["子节1", "子节2", "子节3"],
  "key_points": ["重点1", "重点2"],
  "difficult_points": ["难点1", "难点2"],
  "objectives": ["本章教学目标"]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    final List? list = _parseJsonArray(response);
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 生成测验题目（每章 10 题）
  Future<List<Map<String, dynamic>>> _generateQuizzes(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final allQuestions = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节生成10道四选一测验题。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

返回 JSON 数组，每个元素：
{
  "question": "题目内容",
  "option_a": "选项A",
  "option_b": "选项B",
  "option_c": "选项C",
  "option_d": "选项D",
  "answer_index": 0,
  "chapter": "$chapter"
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final List? list = _parseJsonArray(response);
      if (list != null) {
        for (final q in list) {
          final question = Map<String, dynamic>.from(q as Map);
          question['chapter_number'] = i + 1;
          allQuestions.add(question);
        }
      }
      _report('生成测验题目', 0.2 + (i / chapters.length) * 0.15);
    }

    return allQuestions;
  }

  /// 生成视频脚本（每章 1 个）
  Future<List<Map<String, dynamic>>> _generateVideoScripts(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final scripts = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节生成一个5-8分钟的教学视频脚本。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

返回 JSON：
{
  "title": "$chapter",
  "duration_minutes": 6,
  "sections": [
    {
      "time": "00:00-01:00",
      "type": "intro",
      "content": "开场白和本节概述",
      "visual": "显示章节标题"
    },
    {
      "time": "01:00-03:00",
      "type": "content",
      "content": "核心知识点讲解",
      "visual": "展示关键概念图"
    },
    {
      "time": "03:00-05:00",
      "type": "example",
      "content": "实例演示",
      "visual": "操作演示"
    },
    {
      "time": "05:00-06:00",
      "type": "summary",
      "content": "本节总结",
      "visual": "显示要点回顾"
    }
  ],
  "script": "完整的旁白文本（包含所有section的content）"
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        data['chapter_number'] = i + 1;
        scripts.add(data);
      }
      _report('生成视频脚本', 0.4 + (i / chapters.length) * 0.1);
    }

    return scripts;
  }

  /// 生成课件内容（每章 1 个）
  Future<List<Map<String, dynamic>>> _generateCourseware(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final courseware = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节生成课件大纲（PPT 结构）。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

返回 JSON：
{
  "title": "$chapter",
  "slides": [
    {
      "slide_number": 1,
      "type": "title",
      "title": "章节标题",
      "subtitle": "课程名称"
    },
    {
      "slide_number": 2,
      "type": "content",
      "title": "本节目标",
      "bullets": ["目标1", "目标2"]
    },
    {
      "slide_number": 3,
      "type": "content",
      "title": "核心概念",
      "bullets": ["概念1：定义", "概念2：特点"],
      "notes": "详细讲解要点"
    },
    {
      "slide_number": 4,
      "type": "content",
      "title": "实例分析",
      "bullets": ["案例描述", "分析过程", "结论"],
      "notes": "配合案例讲解"
    },
    {
      "slide_number": 5,
      "type": "summary",
      "title": "本节小结",
      "bullets": ["要点1", "要点2", "要点3"]
    }
  ],
  "total_slides": 5
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        data['chapter_number'] = i + 1;
        courseware.add(data);
      }
      _report('生成课件内容', 0.5 + (i / chapters.length) * 0.1);
    }

    return courseware;
  }

  /// 生成图谱定义（7 类）
  Future<List<Map<String, dynamic>>> _generateGraphDefinitions(
    String courseName,
    List<String> chapters,
  ) async {
    final graphs = <Map<String, dynamic>>[];
    final categories = ['课程', '技术栈', '实验', '项目', '教学', '学习', '思政'];

    for (var i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final prompt = '''
为《$courseName》课程生成"${cat}图谱"的节点和边定义。

章节列表：${chapters.join('、')}

返回 JSON：
{
  "category": "$cat",
  "nodes": [
    {"id": "n1", "label": "节点名称", "type": "concept", "level": 0},
    {"id": "n2", "label": "子节点", "type": "sub_concept", "level": 1, "parent_id": "n1"}
  ],
  "edges": [
    {"from": "n1", "to": "n2", "type": "contains", "label": "包含"}
  ]
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        graphs.add(data);
      }
      _report('生成图谱定义', 0.6 + (i / categories.length) * 0.1);
    }

    return graphs;
  }

  /// 生成实验任务
  Future<List<Map<String, dynamic>>> _generateLabTasks(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final tasks = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节设计一个实验任务。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

返回 JSON：
{
  "title": "${chapter}实验",
  "description": "实验目的和背景",
  "objectives": ["实验目标1", "实验目标2"],
  "requirements": ["要求1", "要求2", "要求3"],
  "deliverables": ["交付物1", "交付物2"],
  "duration_hours": 4,
  "difficulty": "medium"
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        data['chapter_number'] = i + 1;
        tasks.add(data);
      }
    }

    return tasks;
  }

  List<Map<String, dynamic>> _generateHomeworks(
    String courseName,
    List<String> chapters,
  ) {
    return List.generate(chapters.length, (index) {
      final chapterNumber = index + 1;
      final chapter = chapters[index];
      final objectiveId = (index % 4) + 1;
      final objectiveMapping = [
        {'objective_id': objectiveId, 'contribution': 1.0}
      ];
      return {
        'chapter': '第$chapterNumber章',
        'chapter_number': chapterNumber,
        'chapter_title': chapter,
        'course_objective': '目标$objectiveId',
        'description': '围绕《$courseName》"$chapter"章节完成知识理解、实践应用与反思提升。',
        'items': [
          {
            'type_code': 'basic',
            'type': '基础题',
            'question': '梳理"$chapter"的核心概念、关键关系和易混点，形成结构化说明。',
            'reference_answer': '能够覆盖本章核心概念，说明概念之间的先后、包含、依赖或支撑关系。',
            'max_score': 30,
            'objective_mapping': objectiveMapping,
          },
          {
            'type_code': 'practice',
            'type': '实践题',
            'question': '结合课程平台或真实教学场景，设计一个"$chapter"相关的应用任务，并说明操作步骤和预期结果。',
            'reference_answer': '任务目标清晰，步骤可执行，能体现章节知识在教学、学习、实验或评价中的应用。',
            'max_score': 40,
            'objective_mapping': objectiveMapping,
          },
          {
            'type_code': 'reflection',
            'type': '思考题',
            'question': '分析"$chapter"在课程知识图谱与数字化教学中的价值，提出一个可改进点。',
            'reference_answer': '能够联系课程图谱、学习数据或教学评价，提出具体、可验证的改进建议。',
            'max_score': 30,
            'objective_mapping': objectiveMapping,
          },
        ],
      };
    });
  }

  /// 生成报告模板
  Future<List<Map<String, dynamic>>> _generateReportTemplates(
    String courseName,
    List<String> chapters,
  ) async {
    final prompt = '''
为《$courseName》课程生成报告模板配置，返回 JSON 数组：

[
  {"name": "实验报告模板", "type": "lab_report", "sections": ["实验目的", "实验环境", "实验步骤", "实验结果", "问题与解决"]},
  {"name": "项目报告模板", "type": "project_report", "sections": ["项目背景", "需求分析", "设计方案", "实现过程", "测试结果", "总结"]},
  {"name": "学习心得模板", "type": "reflection", "sections": ["学习内容", "收获与体会", "问题与建议"]},
  {"name": "周报告模板", "type": "weekly_report", "sections": ["本周学习", "完成任务", "遇到问题", "下周计划"]},
  {"name": "课程考核报告模板", "type": "final_report", "sections": ["课程概述", "知识掌握", "技能提升", "作品展示", "自我评价"]}
]
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    final List? list = _parseJsonArray(response);
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 生成达成配置
  Future<Map<String, dynamic>> _generateAchievementConfig(
    String courseName,
    List<String> chapters,
  ) async {
    final prompt = '''
为《$courseName》课程生成成绩达成度计算配置，返回 JSON：

{
  "objectives": [
    {"id": 1, "name": "目标1", "weight": 0.25},
    {"id": 2, "name": "目标2", "weight": 0.25},
    {"id": 3, "name": "目标3", "weight": 0.25},
    {"id": 4, "name": "目标4", "weight": 0.25}
  ],
  "components": [
    {"name": "平时成绩", "weight": 0.3, "objective_weights": [0.2, 0.3, 0.3, 0.2]},
    {"name": "实验成绩", "weight": 0.3, "objective_weights": [0.2, 0.2, 0.4, 0.2]},
    {"name": "期末考试", "weight": 0.4, "objective_weights": [0.25, 0.25, 0.25, 0.25]}
  ]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    return _parseJson(response) ?? {};
  }

  /// 生成考核配置
  Future<Map<String, dynamic>> _generateAssessmentConfig(
    String courseName,
    List<String> chapters,
  ) async {
    final prompt = '''
为《$courseName》课程生成考核配置，返回 JSON：

{
  "groups": [
    {
      "name": "平时成绩",
      "weight": 0.3,
      "items": [
        {"name": "课堂表现", "weight": 0.15},
        {"name": "作业完成", "weight": 0.15}
      ]
    },
    {
      "name": "实验成绩",
      "weight": 0.3,
      "items": [
        {"name": "实验完成度", "weight": 0.2},
        {"name": "实验报告质量", "weight": 0.1}
      ]
    },
    {
      "name": "项目考核",
      "weight": 0.2,
      "items": [
        {"name": "项目完成度", "weight": 0.1},
        {"name": "项目答辩", "weight": 0.1}
      ]
    },
    {
      "name": "期末考试",
      "weight": 0.2,
      "items": [
        {"name": "理论考试", "weight": 0.2}
      ]
    }
  ]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    return _parseJson(response) ?? {};
  }

  // ── 辅助方法 ──────────────────────────────────────────────────────────────

  void _report(String step, double progress) {
    onProgress?.call(step, progress);
    debugPrint(
        '=== CourseGeneration: $step (${(progress * 100).toStringAsFixed(0)}%)');
  }

  dynamic _parseJson(String? text) {
    if (text == null || text.isEmpty) return null;
    // 提取 JSON 块
    final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(text);
    if (jsonMatch != null) {
      try {
        return jsonDecode(jsonMatch.group(1)!);
      } catch (_) {}
    }
    // 直接尝试解析
    try {
      return jsonDecode(text);
    } catch (_) {}
    return null;
  }

  List<dynamic>? _parseJsonArray(String? text) {
    final result = _parseJson(text);
    if (result is List) return result;
    return null;
  }
}

/// 课程生成结果
class CourseGenerationResult {
  final String courseId;
  final String courseName;

  Map<String, dynamic> config = {};
  List<Map<String, dynamic>> chapters = [];
  List<Map<String, dynamic>> quizzes = [];
  List<Map<String, dynamic>> videoScripts = [];
  List<Map<String, dynamic>> courseware = [];
  List<Map<String, dynamic>> graphs = [];
  List<Map<String, dynamic>> labTasks = [];
  List<Map<String, dynamic>> homeworks = [];
  List<Map<String, dynamic>> reportTemplates = [];
  Map<String, dynamic> achievementConfig = {};
  Map<String, dynamic> assessmentConfig = {};
  String? error;

  CourseGenerationResult({
    required this.courseId,
    required this.courseName,
  });

  bool get isSuccess => error == null;

  /// 转换为可序列化的 Map（用于存储/上传）
  Map<String, dynamic> toMap() => {
        'course_id': courseId,
        'course_name': courseName,
        'config': config,
        'chapters': chapters,
        'quizzes': quizzes,
        'video_scripts': videoScripts,
        'courseware': courseware,
        'graphs': graphs,
        'lab_tasks': labTasks,
        'homeworks': homeworks,
        'report_templates': reportTemplates,
        'achievement_config': achievementConfig,
        'assessment_config': assessmentConfig,
        'generated_at': DateTime.now().toIso8601String(),
      };
}
