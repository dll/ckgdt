import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/local/ai_config_dao.dart';

class AiService {
  final AiConfigDao _configDao = AiConfigDao();

  // ── 核心：发送 chat completion 请求 ──────────────────────────────────────
  Future<String> chat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
  }) async {
    final config = await _configDao.getConfig();
    if (config.apiKey == null || config.apiKey!.isEmpty) {
      throw '抱歉，AI 服务暂时不可用。请在「设置  →  AI 配置」中配置 API Key。';
    }

    final allMessages = [
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    final url = '${config.effectiveBaseUrl}/chat/completions';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
            'User-Agent': 'knowledge-graph-app/1.0',
          },
          body: jsonEncode({
            'model': config.model,
            'messages': allMessages,
            'temperature': 0.7,
            'max_tokens': 2048,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw 'AI 请求失败 (${response.statusCode})，请检查网络连接和 API 配置。';
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    return json['choices'][0]['message']['content'] as String;
  }

  // ── 生成幻灯片内容 ──────────────────────────────────────────────────────
  /// 返回 List<Map>，每项含 title、bullets（List<String>）、notes
  Future<List<Map<String, dynamic>>> generateSlides(
    String topic, {
    String? chapter,
    int slideCount = 8,
  }) async {
    const system = '你是一位专业的移动应用开发课程讲师，擅长制作清晰、结构化的教学课件。'
        '请用中文回复，回复必须是合法的 JSON 数组。';
    final prompt = '''
请为"$topic"${chapter != null ? '（第 $chapter 章）' : ''}生成 $slideCount 张幻灯片的内容。
要求：
- 返回 JSON 数组，每项格式：{"title":"标题","bullets":["要点1","要点2","要点3"],"notes":"讲师备注"}
- 每张幻灯片 3-5 个要点，要点简洁（≤30字）
- 内容覆盖：背景介绍、核心概念、技术细节、代码示例说明、实践要点、总结
- 仅返回 JSON，不要包含其他文字
''';

    final raw = await chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: system,
    );

    // 提取 JSON 数组
    final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (match == null) return _fallbackSlides(topic, slideCount);
    try {
      final list = jsonDecode(match.group(0)!) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return _fallbackSlides(topic, slideCount);
    }
  }

  // ── 生成视频讲解脚本 ─────────────────────────────────────────────────────
  Future<String> generateScript(String topic, {String? chapter}) async {
    const system =
        '你是一位专业的移动应用开发课程讲师，负责录制教学视频。请用中文、口语化、清晰的语言生成视频讲解脚本。';
    final prompt = '''
请为"$topic"${chapter != null ? '（第 $chapter 章）' : ''}生成一份完整的教学视频讲解脚本。
要求：
- 总时长约 8-10 分钟（约 1500-2000 字）
- 分段落，每段有【时间点】标注（如【0:00】【1:30】）
- 语言口语化、适合 TTS 朗读
- 包含：开场白、核心内容讲解、代码讲解、总结
''';

    return chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: system,
    );
  }

  // ── 生成测验题目 ─────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> generateQuestions(
    String topic, {
    int count = 5,
    String? chapter,
  }) async {
    const system = '你是移动应用开发课程出题专家，擅长设计选择题。请用中文，只返回 JSON。';
    final prompt = '''
为"$topic"${chapter != null ? '（$chapter 章）' : ''}出 $count 道单选题。
返回 JSON 数组，格式：
[{"question":"题干","option_a":"A选项","option_b":"B选项","option_c":"C选项","option_d":"D选项","answer_index":0,"source":"$topic"}]
answer_index 为 0-3（对应 A-D），仅返回 JSON，不要其他文字。
''';

    final raw = await chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: system,
    );

    final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (match == null) return [];
    try {
      final list = jsonDecode(match.group(0)!) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── 生成学习路径 ─────────────────────────────────────────────────────────
  Future<String> generateLearningPath(String topic) async {
    const system =
        '你是移动应用开发课程设计专家，擅长制定学习路径。请用中文 Markdown 格式回复。';
    final prompt =
        '请为"$topic"生成一份详细的学习路径，包含：前置知识、核心步骤（带时间估计）、推荐资源、评估方式。';
    return chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: system,
    );
  }

  // ── 生成 PlantUML 代码 ──────────────────────────────────────────────────
  Future<String> generatePuml(String topic,
      {String diagramType = 'class'}) async {
    const system =
        '你是 UML 专家，擅长编写 PlantUML 代码。只返回 @startuml ... @enduml 代码块，不要其他内容。';
    final typeDesc = {
          'class': '类图',
          'sequence': '时序图',
          'activity': '活动图',
          'component': '组件图',
          'usecase': '用例图',
        }[diagramType] ??
        diagramType;
    final prompt =
        '请为"$topic"生成一个 $typeDesc（PlantUML 代码），要求：使用中文标签，包含完整的 @startuml 和 @enduml，风格专业简洁。';
    final raw = await chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: system,
    );
    // 提取 @startuml ... @enduml
    final match = RegExp(r'@startuml[\s\S]*?@enduml').firstMatch(raw);
    return match?.group(0) ?? raw;
  }

  // ── AI 辅助图谱推荐 ────────────────────────────────────────────────────────

  /// 根据当前图谱中已有的概念和关系，让 AI 推荐新的概念节点和关系边。
  /// 返回格式：{ "concepts": [...], "relations": [...] }
  Future<Map<String, dynamic>> recommendGraphElements({
    required List<Map<String, dynamic>> existingConcepts,
    required List<Map<String, dynamic>> existingRelations,
    String courseTopic = '移动应用开发',
  }) async {
    const system = '你是一位移动应用开发课程的知识图谱专家。'
        '根据现有的知识概念和关系，推荐补充的新概念节点和关系边，帮助完善知识图谱。'
        '只返回 JSON，不要其他文字。';

    // 构建现有概念摘要
    final conceptSummary = existingConcepts.map((c) {
      return '${c['concept_name']}(${c['concept_type'] ?? 'concept'}, '
          '第${c['chapter'] ?? '?'}章, ${c['importance'] ?? 'important'})';
    }).join('、');

    // 构建现有关系摘要
    String relationSummary = '暂无';
    if (existingRelations.isNotEmpty) {
      final conceptMap = <int, String>{};
      for (final c in existingConcepts) {
        conceptMap[c['id'] as int] = c['concept_name'] as String? ?? '?';
      }
      relationSummary = existingRelations.take(30).map((r) {
        final src = conceptMap[r['source_concept_id']] ?? '?';
        final tgt = conceptMap[r['target_concept_id']] ?? '?';
        return '$src -[${r['relation_type']}]-> $tgt';
      }).join('；');
    }

    final prompt = '''
课程主题：$courseTopic
已有概念（${existingConcepts.length}个）：$conceptSummary
已有关系（${existingRelations.length}条）：$relationSummary

请分析上述知识图谱，推荐 3~6 个新概念节点和 3~8 条新关系边来完善图谱。
要求：
1. 新概念不能与已有概念重名
2. 新关系可以连接已有概念，也可以连接新推荐的概念
3. 返回 JSON 格式如下：
{
  "concepts": [
    {"concept_name":"名称","concept_type":"concept|technology|tool|framework|language|platform|pattern","chapter":1,"importance":"core|important|supplementary","description":"简要描述","keywords":"关键词","confidence":0.85}
  ],
  "relations": [
    {"source":"源概念名","target":"目标概念名","relation_type":"prerequisite|related_to|part_of|compared_with|applied_in|builds_upon|alternative_to|extends","description":"关系描述","weight":1.0,"confidence":0.9}
  ]
}
4. confidence 表示 AI 对该推荐的置信度（0~1）
5. 仅返回 JSON，不要其他文字
''';

    final raw = await chat(
      [{'role': 'user', 'content': prompt}],
      systemPrompt: system,
    );

    // 提取 JSON 对象
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (match == null) {
      return {'concepts': <Map<String, dynamic>>[], 'relations': <Map<String, dynamic>>[]};
    }
    try {
      final parsed = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      return {
        'concepts': (parsed['concepts'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        'relations': (parsed['relations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      };
    } catch (_) {
      return {'concepts': <Map<String, dynamic>>[], 'relations': <Map<String, dynamic>>[]};
    }
  }

  // ── 检查连通性 ───────────────────────────────────────────────────────────
  Future<bool> testConnection() async {
    try {
      final result = await chat(
        [
          {'role': 'user', 'content': '你好，请回复"连接成功"三个字。'}
        ],
      ).timeout(const Duration(seconds: 15));
      return result.contains('成功') || result.length > 2;
    } catch (_) {
      return false;
    }
  }

  // ── 内部：生成备用幻灯片（AI 失败时） ───────────────────────────────────
  List<Map<String, dynamic>> _fallbackSlides(String topic, int count) {
    return List.generate(
      count,
      (i) => {
        'title': i == 0 ? '课程介绍：$topic' : '第 ${i + 1} 节',
        'bullets': ['内容待 AI 生成', '请检查 API Key 配置', '或手动编辑此幻灯片'],
        'notes': '',
      },
    );
  }
}
