import 'dart:convert';
import 'dart:math' as math;

import '../../core/error_handler.dart';
import '../../data/local/achievement_dao.dart';
import '../../data/local/knowledge_graph_dao.dart';
import '../../data/local/lab_task_dao.dart';
import '../../data/local/quiz_dao.dart';
import '../../data/models/question_model.dart';
import '../achievement/achievement_docx_service.dart';
import '../achievement/achievement_audit_context_service.dart';
import '../ai_service.dart';
import '../auth_service.dart';
import '../course_context_service.dart';
import '../courseware_service.dart';

/// 发布前专项能力：把智能体的自然语言请求落到本地业务闭环。
///
/// 这些方法不依赖前端页面状态，可被智能体、语音助手或按钮入口复用。
class SpecialAgentTools {
  SpecialAgentTools._();

  static final SpecialAgentTools instance = SpecialAgentTools._();

  final AiService _aiService = AiService();
  final CourseContextService _courseContext = CourseContextService();

  Future<String> generateKnowledgeGraph({
    required String userRequest,
    String? topic,
    int? chapter,
  }) async {
    final course = await _courseContext.getActiveCourse();
    final courseName = course.name;
    final chapters = await _courseContext.chapterTitles();
    final resolvedTopic = _cleanTopic(
      topic?.trim().isNotEmpty == true ? topic! : userRequest,
      removeWords: const [
        '请',
        '帮我',
        '生成',
        '创建',
        '构建',
        '知识图谱',
        '图谱',
        '概念图',
        '节点',
        '关系',
      ],
      fallback: courseName,
    );

    final prompt = '''
请为《$courseName》课程生成主题为“$resolvedTopic”的知识图谱。
${chapter != null ? '优先归入第$chapter章。' : ''}

当前课程章节：
${chapters.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

只输出合法 JSON 对象，不要 Markdown，不要解释。格式：
{
  "concepts": [
    {
      "name": "概念名称",
      "type": "concept|technology|tool|framework|language|platform|pattern",
      "chapter": 1,
      "description": "一句话说明",
      "keywords": "关键词1,关键词2",
      "importance": "core|important|optional"
    }
  ],
  "relations": [
    {
      "source": "概念A",
      "target": "概念B",
      "type": "prerequisite|related_to|part_of|compared_with|applied_in|builds_upon|alternative_to|extends",
      "label": "关系说明",
      "description": "关系依据"
    }
  ]
}

要求：
1. 概念 8-16 个，覆盖基础、核心和拓展概念。
2. 关系 10-24 条，必须有前置关系和应用关系。
3. 章节号必须是 1 到 ${chapters.length} 的整数。
4. 概念名称不要重复。
''';

    final result = await _aiService.chatWithMeta(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: '你是课程知识图谱建模专家，输出必须是可解析 JSON。',
      temperature: 0.2,
    );

    final parsed = _tryParseJsonMap(result.content);
    if (parsed == null) {
      return '图谱生成失败：AI 返回内容不是合法 JSON。请换一个更具体的主题后重试。';
    }

    final concepts = (parsed['concepts'] as List?) ?? const [];
    final relations = (parsed['relations'] as List?) ?? const [];
    if (concepts.isEmpty) {
      return '图谱生成失败：未提取到有效概念。';
    }

    final dao = KnowledgeGraphDao();
    final nameToId = <String, int>{};
    var createdConcepts = 0;

    for (final raw in concepts) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString().trim() ?? '';
      if (name.isEmpty || nameToId.containsKey(name)) continue;

      final existingId = await _findExactConceptId(dao, name);
      if (existingId != null) {
        nameToId[name] = existingId;
        continue;
      }

      final id = await dao.addConcept({
        'concept_name': name,
        'concept_type': _normalizeConceptType(raw['type']?.toString()),
        'chapter': chapter ?? _intInRange(raw['chapter'], 1, chapters.length),
        'description': raw['description']?.toString() ?? '',
        'keywords': raw['keywords']?.toString() ?? name,
        'importance': _normalizeImportance(raw['importance']?.toString()),
      });
      if (id > 0) {
        nameToId[name] = id;
        createdConcepts++;
      }
    }

    var createdRelations = 0;
    for (final raw in relations) {
      if (raw is! Map) continue;
      final source = raw['source']?.toString().trim() ?? '';
      final target = raw['target']?.toString().trim() ?? '';
      final sourceId = nameToId[source];
      final targetId = nameToId[target];
      if (sourceId == null || targetId == null || sourceId == targetId) {
        continue;
      }
      final id = await dao.addRelation({
        'source_concept_id': sourceId,
        'target_concept_id': targetId,
        'relation_type': _normalizeRelationType(raw['type']?.toString()),
        'relation_label': raw['label']?.toString() ?? '',
        'description': raw['description']?.toString() ?? '',
        'ai_generated': 1,
        'confidence': 0.86,
      });
      if (id > 0) createdRelations++;
    }

    return '''
已生成“$resolvedTopic”知识图谱。

- 新增概念：$createdConcepts 个
- 可用概念：${nameToId.length} 个
- 新增关系：$createdRelations 条
- 当前课程：《$courseName》

请打开“图谱”页刷新查看；如需扩展，可继续说“在这个图谱中补充……”。''';
  }

  Future<String> generateAchievementReport({int? batchId}) async {
    final dao = AchievementDao();
    final batches = await dao.getAllBatches();
    if (batches.isEmpty) {
      return '暂无达成度批次，无法生成报告。请先在“达成”页导入大纲和成绩。';
    }

    final batch = _pickBatch(batches, batchId);
    if (batch == null) {
      return '未找到批次 #$batchId。请先查询达成度批次。';
    }
    final id = (batch['id'] as num).toInt();
    final scores = await dao.getScores(id);
    if (scores.isEmpty) {
      return '批次 #$id 暂无学生成绩，无法生成达成度报告。';
    }

    final courseName = (batch['course_name'] ?? '课程').toString();
    final className = (batch['class_name'] ?? '班级').toString();
    final semester =
        (batch['semester'] ?? DateTime.now().year.toString()).toString();
    final teacherName = AuthService().currentUser?.realName ?? '教师';

    final avg = await dao.recalculateAndSaveBatch(id);
    final weights = await dao.resolveObjectiveWeights(id);
    final fullMarks = await dao.resolveObjectiveFullMarks(id);
    final envWeights = await dao.resolveObjectiveAssessmentWeights(id);
    final combined = await dao.calculateCombinedAchievement(id);
    final objectivesRows = await dao.getCourseObjectives(courseName);
    final objectiveByIdx = <int, Map<String, dynamic>>{
      for (final row in objectivesRows)
        if (((row['idx'] as num?)?.toInt() ?? 0) > 0)
          (row['idx'] as num).toInt(): row
    };

    final activeIndexes = _activeObjectiveIndexes(weights, fullMarks);
    final pingshiAvg = combined['pingshi'] as Map<String, double>? ?? {};
    final experimentAvg = combined['experiment'] as Map<String, double>? ?? {};
    final examAvg = combined['exam'] as Map<String, double>? ?? {};

    final objectives = <Map<String, dynamic>>[];
    for (final i in activeIndexes) {
      final objectiveNo = i + 1;
      final objKey = 'obj$objectiveNo';
      final row = objectiveByIdx[objectiveNo] ?? const <String, dynamic>{};
      final env = i < envWeights.length
          ? envWeights[i]
          : const {'pingshi': 0.2, 'experiment': 0.3, 'exam': 0.5};
      final envs = <Map<String, dynamic>>[];

      void addEnv(String label, String key, Map<String, double> source) {
        final weight = env[key] ?? 0;
        if (weight <= 0) return;
        final ach = source[objKey] ?? avg['课程目标$objectiveNo'] ?? 0;
        final full = i < fullMarks.length ? fullMarks[i] : 0;
        envs.add({
          'name': label,
          'full': full,
          'avg': ach * full,
          'ach': ach,
          'weight': weight,
        });
      }

      addEnv('平时', 'pingshi', pingshiAvg);
      addEnv('实验', 'experiment', experimentAvg);
      addEnv('考核', 'exam', examAvg);

      objectives.add({
        'objective': objectiveNo,
        'weight': i < weights.length ? weights[i] : 0,
        'indicator': row['indicator']?.toString() ?? '',
        'description': _objectiveDescription(row, objectiveNo),
        'assess_content': row['assess_content']?.toString() ?? '',
        'full_mark': i < fullMarks.length ? fullMarks[i] : 0,
        'achievement': avg['课程目标$objectiveNo'] ?? 0,
        'avgScore': (avg['课程目标$objectiveNo'] ?? 0) * 100,
        'envs': envs,
      });
    }

    final survey = await dao.getSurveySatisfactionSummary();
    final qualitativeText = survey['hasSurveyData'] == true
        ? '共回收有效问卷 ${survey['totalResponses'] ?? 0} 份，综合满意度为 ${(((survey['overallSatisfaction'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%。问卷结果用于辅助解释定量达成度。'
        : null;
    final improvements = await dao.generateImprovementSuggestions(id);

    final path = await AchievementDocxService.instance.generateReport(
      batchName: (batch['batch_name'] ?? batch['name'] ?? '达成评价').toString(),
      courseName: courseName,
      className: className,
      semester: semester,
      teacherName: teacherName,
      syllabus: {
        'info': {
          '考核方式': '考查',
          '开课学期': semester,
        },
        'objectives': [
          for (final i in activeIndexes)
            {
              'num': i + 1,
              'objective':
                  _objectiveDescription(objectiveByIdx[i + 1] ?? {}, i + 1),
              'requirement':
                  objectiveByIdx[i + 1]?['indicator']?.toString() ?? '',
            }
        ],
        'weights': [
          for (final i in activeIndexes)
            {
              'objective': i + 1,
              'weight': i < weights.length ? weights[i] : 0,
              'pingshi_ratio':
                  i < envWeights.length ? envWeights[i]['pingshi'] ?? 0 : 0,
              'experiment_ratio':
                  i < envWeights.length ? envWeights[i]['experiment'] ?? 0 : 0,
              'exam_ratio':
                  i < envWeights.length ? envWeights[i]['exam'] ?? 0 : 0,
            }
        ],
      },
      objectives: objectives,
      classStats: {
        'studentCount': scores.length,
        'avgTotal': (avg['weighted'] ?? 0) * 100,
        'maxTotal': _maxOf(scores, 'total_score'),
        'minTotal': _minOf(scores, 'total_score'),
        'stdDev': _stdDevOf(scores, 'total_score'),
      },
      students: scores,
      qualitativeText: qualitativeText,
      improvementText: _formatImprovementText(improvements),
    );

    final audit = await AchievementAuditContextService.instance
        .buildAuditMarkdown(batchId: id, compact: true);

    return '''
达成度 Word 报告已生成。

- 批次：#${batch['id']} ${batch['batch_name'] ?? batch['name'] ?? ''}
- 课程：《$courseName》
- 班级：$className
- 学生数：${scores.length}
- 文件：$path

$audit

可在“达成 → 报告”页继续预览、导出 Excel 或重新生成。''';
  }

  Future<String> generateCourseware({
    required String userRequest,
    String? topic,
    bool forcePptx = false,
  }) async {
    final courseName = await _courseContext.activeCourseName();
    final resolvedTopic = _cleanTopic(
      topic?.trim().isNotEmpty == true ? topic! : userRequest,
      removeWords: const [
        '请',
        '帮我',
        '生成',
        '制作',
        '创建',
        '一份',
        '课件',
        'ppt',
        'pptx',
        'PPT',
        'PPTX',
        '教案',
        '幻灯片',
      ],
      fallback: courseName,
    );
    final chapter = _extractChapterText(userRequest);
    final wantPptx = forcePptx ||
        RegExp(r'(pptx|ppt|幻灯片)', caseSensitive: false).hasMatch(userRequest);

    final service = CoursewareService();
    final plan = await service.generateLessonPlan(
      topic: resolvedTopic,
      chapter: chapter,
      classHours: _extractClassHours(userRequest) ?? 2,
      additionalRequirements: '由智能体发布前专项能力生成，内容需适合课堂直接使用。',
    );
    final title = plan['title']?.toString().trim().isNotEmpty == true
        ? plan['title'].toString()
        : resolvedTopic;
    final markdown = service.generateMarkdown(plan);
    final mdPath = await service.exportMarkdownFile(
      markdown: markdown,
      title: title,
      chapter: chapter,
    );
    final pdfPath = await service.generateEnhancedPdf(lessonPlan: plan);

    String? pptxPath;
    String pptxNote = '';
    if (wantPptx) {
      final slides = service.lessonPlanToSlides(plan);
      pptxPath = await service.generatePptx(
        title: title,
        slides: slides,
        chapter: chapter,
      );
      if (pptxPath == null) {
        pptxNote = '\n- PPTX：生成失败或当前环境缺少 python-pptx，已保留 PDF/Markdown。';
      }
    }

    return '''
课件已生成。

- 主题：$resolvedTopic
- 课程：《$courseName》
${chapter == null ? '' : '- 章节：$chapter\n'}- Markdown：${mdPath ?? '未生成'}
- PDF：${pdfPath ?? '未生成'}
${pptxPath == null ? pptxNote : '- PPTX：$pptxPath'}

可在“课件工坊/教学资料”中继续编辑、预览和导出。''';
  }

  Future<String> generateQuizQuestions({
    required String userRequest,
    String? topic,
    int? count,
  }) async {
    final course = await _courseContext.getActiveCourse();
    final chapters = await _courseContext.chapterTitles();
    final resolvedTopic = _cleanTopic(
      topic?.trim().isNotEmpty == true ? topic! : userRequest,
      removeWords: const [
        '请',
        '帮我',
        '生成',
        '创建',
        '出',
        '道',
        '题',
        '选择题',
        '测验',
        '练习',
        '导入',
        '保存',
        '题库',
      ],
      fallback: course.name,
    );
    final questionCount = count ?? _extractCount(userRequest) ?? 5;
    final chapter = _extractChapterText(userRequest) ?? _guessChapter(chapters);

    final prompt = '''
请为《${course.name}》课程生成 "$resolvedTopic" 主题的 $questionCount 道四选一选择题。

当前课程章节：
${chapters.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

只输出合法 JSON 对象，不要 Markdown，不要解释。格式：
{
  "questions": [
    {
      "source": "第1章 章节名",
      "question": "题干",
      "options": ["A选项", "B选项", "C选项", "D选项"],
      "answer_index": 0,
      "explanation": "解析"
    }
  ]
}

要求：
1. 题干清晰，选项互斥，干扰项来自常见误解。
2. answer_index 使用 0-3。
3. source 优先使用 "$chapter"，否则使用最相关章节。
4. 覆盖记忆、理解、应用三个层次。
''';

    final result = await _aiService.chatWithMeta(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: '你是高校课程命题专家，输出必须是可解析 JSON。',
      temperature: 0.2,
    );

    final parsed = _tryParseJsonMap(result.content);
    final list = (parsed?['questions'] as List?) ?? const [];
    if (list.isEmpty) return '题目生成失败：AI 未返回有效题目。';

    final dao = QuizDao();
    var inserted = 0;
    for (final raw in list) {
      if (raw is! Map) continue;
      final options = (raw['options'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [];
      if (options.length < 4) continue;
      final text = raw['question']?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final source = raw['source']?.toString().trim().isNotEmpty == true
          ? raw['source'].toString().trim()
          : chapter;
      final id = await dao.addQuestion(QuestionModel(
        source: source,
        question: text,
        optionA: options[0],
        optionB: options[1],
        optionC: options[2],
        optionD: options[3],
        answerIndex: _intInRange(raw['answer_index'], 0, 3),
      ));
      if (id > 0) inserted++;
    }

    return '''
已为《${course.name}》生成并写入题库。

- 主题：$resolvedTopic
- 章节：$chapter
- 新增题目：$inserted 道

请到“题库管理”或“测验”页面刷新查看；如需继续扩展，可说“再生成进阶题/应用题”。''';
  }

  Future<String> generateLabTask({
    required String userRequest,
    String? topic,
  }) async {
    final course = await _courseContext.getActiveCourse();
    final chapters = await _courseContext.chapterTitles();
    final resolvedTopic = _cleanTopic(
      topic?.trim().isNotEmpty == true ? topic! : userRequest,
      removeWords: const [
        '请',
        '帮我',
        '生成',
        '创建',
        '设计',
        '发布',
        '实验',
        '任务',
      ],
      fallback: course.name,
    );
    final chapter = _extractChapterText(userRequest) ?? _guessChapter(chapters);

    final prompt = '''
请为《${course.name}》课程设计一个 "$resolvedTopic" 实验任务。

当前课程章节：
${chapters.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

只输出合法 JSON 对象，不要 Markdown，不要解释。格式：
{
  "title": "实验名称",
  "chapter": "$chapter",
  "description": "实验简介",
  "requirements": "实验要求，分条写",
  "deliverables": "提交物清单",
  "difficulty": "简单|中等|较难",
  "max_score": 100
}

要求：
1. 任务可课堂直接发布，目标、步骤、验收标准清晰。
2. 必须体现知识图谱驱动：说明关联知识点与前置概念。
3. 提交物至少包含实验报告、运行截图或结果说明。
''';

    final result = await _aiService.chatWithMeta(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: '你是高校课程实验设计专家，输出必须是可解析 JSON。',
      temperature: 0.2,
    );
    final parsed = _tryParseJsonMap(result.content);
    if (parsed == null) return '实验任务生成失败：AI 返回内容不是合法 JSON。';

    final title = parsed['title']?.toString().trim() ?? '';
    if (title.isEmpty) return '实验任务生成失败：缺少实验名称。';
    final id = await LabTaskDao().addTask(
      title: title,
      chapter: parsed['chapter']?.toString().trim().isNotEmpty == true
          ? parsed['chapter'].toString().trim()
          : chapter,
      description: parsed['description']?.toString() ?? '',
      requirements: parsed['requirements']?.toString() ?? '',
      deliverables: parsed['deliverables']?.toString() ?? '',
      difficulty: _normalizeDifficulty(parsed['difficulty']?.toString()),
      maxScore: _intInRange(parsed['max_score'], 1, 100),
      creatorId: AuthService().currentUser?.userId,
    );

    return '''
已发布实验任务。

- 课程：《${course.name}》
- 实验：$title
- 章节：${parsed['chapter'] ?? chapter}
- 任务 ID：$id

请到“实验管理/实验任务”页面刷新查看，并根据班级进度调整截止时间。''';
  }

  bool isGraphGenerationIntent(String text) =>
      text.contains('图谱') && RegExp(r'生成|创建|构建|补充|扩展').hasMatch(text);

  bool isAchievementReportIntent(String text) =>
      text.contains('达成') && text.contains('报告') && text.contains('生成');

  bool isCoursewareGenerationIntent(String text) =>
      RegExp(r'课件|PPT|ppt|幻灯片|教案').hasMatch(text) &&
      RegExp(r'生成|制作|创建').hasMatch(text);

  bool isQuizGenerationIntent(String text) =>
      RegExp(r'题|测验|练习').hasMatch(text) &&
      RegExp(r'生成|创建|出|导入|保存').hasMatch(text);

  bool isLabTaskGenerationIntent(String text) =>
      text.contains('实验') && RegExp(r'生成|创建|设计|发布').hasMatch(text);

  Map<String, dynamic>? _tryParseJsonMap(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'```json\s*', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(cleaned.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      swallow(e, tag: 'SpecialAgentTools._tryParseJsonMap');
      return null;
    }
  }

  Future<int?> _findExactConceptId(KnowledgeGraphDao dao, String name) async {
    final rows = await dao.searchConcepts(name);
    for (final row in rows) {
      if ((row['concept_name'] ?? '').toString().trim() == name) {
        return (row['id'] as num?)?.toInt();
      }
    }
    return null;
  }

  String _normalizeConceptType(String? value) {
    const allowed = {
      'concept',
      'technology',
      'tool',
      'framework',
      'language',
      'platform',
      'pattern',
    };
    final v = value?.trim() ?? '';
    return allowed.contains(v) ? v : 'concept';
  }

  String _normalizeImportance(String? value) {
    const allowed = {'core', 'important', 'optional'};
    final v = value?.trim() ?? '';
    return allowed.contains(v) ? v : 'important';
  }

  String _normalizeRelationType(String? value) {
    const allowed = {
      'prerequisite',
      'related_to',
      'part_of',
      'compared_with',
      'applied_in',
      'builds_upon',
      'alternative_to',
      'extends',
    };
    final v = value?.trim() ?? '';
    if (v == 'related') return 'related_to';
    return allowed.contains(v) ? v : 'related_to';
  }

  int _intInRange(Object? value, int min, int max) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) return min;
    return parsed.clamp(min, max).toInt();
  }

  Map<String, dynamic>? _pickBatch(
    List<Map<String, dynamic>> batches,
    int? batchId,
  ) {
    if (batchId != null) {
      for (final b in batches) {
        if ((b['id'] as num?)?.toInt() == batchId) return b;
      }
      return null;
    }
    for (final b in batches) {
      if (((b['student_count'] as num?)?.toInt() ?? 0) > 0) return b;
    }
    return batches.first;
  }

  List<int> _activeObjectiveIndexes(List<double> weights, List<double> marks) {
    final indexes = [
      for (var i = 0; i < 4; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < marks.length && marks[i] > 0))
          i,
    ];
    return indexes.isEmpty ? [0, 1, 2, 3] : indexes;
  }

  String _objectiveDescription(Map<String, dynamic> row, int index) {
    final desc = row['description']?.toString().trim() ?? '';
    if (desc.isNotEmpty) return desc;
    final name = row['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    return '课程目标$index';
  }

  double _maxOf(List<Map<String, dynamic>> rows, String key) {
    if (rows.isEmpty) return 0;
    return rows
        .map((r) => (r[key] as num?)?.toDouble() ?? 0)
        .reduce((a, b) => a > b ? a : b);
  }

  double _minOf(List<Map<String, dynamic>> rows, String key) {
    if (rows.isEmpty) return 0;
    return rows
        .map((r) => (r[key] as num?)?.toDouble() ?? 0)
        .reduce((a, b) => a < b ? a : b);
  }

  double _stdDevOf(List<Map<String, dynamic>> rows, String key) {
    if (rows.isEmpty) return 0;
    final values = rows.map((r) => (r[key] as num?)?.toDouble() ?? 0).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return variance <= 0 ? 0 : math.sqrt(variance);
  }

  String? _formatImprovementText(List<Map<String, dynamic>> suggestions) {
    if (suggestions.isEmpty) return null;
    final buf = StringBuffer();
    for (final s in suggestions.take(4)) {
      buf.writeln(
          '${s['objectiveName'] ?? '课程目标'}：达成度 ${((s['achievement'] as num?)?.toDouble() ?? 0).toStringAsFixed(3)}，${s['level'] ?? ''}。');
      final actions = (s['actions'] as List?) ?? const [];
      for (final action in actions.take(3)) {
        buf.writeln('• $action');
      }
    }
    return buf.toString().trim();
  }

  String _cleanTopic(
    String source, {
    required List<String> removeWords,
    required String fallback,
  }) {
    var text = source.trim();
    for (final word in removeWords) {
      text = text.replaceAll(word, '');
    }
    text = text
        .replaceAll(RegExp(r'[，。！？、:：；;“”"（）()【】\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? fallback : text;
  }

  String? _extractChapterText(String text) {
    final match = RegExp(r'第\s*([一二三四五六七八九十\d]+)\s*章').firstMatch(text);
    if (match == null) return null;
    return '第${match.group(1)}章';
  }

  int? _extractCount(String text) {
    final match = RegExp(r'(\d+)\s*(道|个|题)').firstMatch(text);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null) return null;
    return value.clamp(1, 20).toInt();
  }

  String _guessChapter(List<String> chapters) {
    return chapters.isNotEmpty ? chapters.first : '第1章';
  }

  String _normalizeDifficulty(String? value) {
    final v = value?.trim() ?? '';
    if (v.contains('简单') || v.toLowerCase() == 'easy') return '简单';
    if (v.contains('难') || v.toLowerCase() == 'hard') return '较难';
    return '中等';
  }

  int? _extractClassHours(String text) {
    final match = RegExp(r'(\d+)\s*(课时|学时)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
