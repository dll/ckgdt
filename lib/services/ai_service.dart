import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/local/ai_config_dao.dart';
import '../data/local/ai_history_dao.dart';
import '../data/models/ai_config_model.dart';
import '../core/error_handler.dart';
import 'auth_service.dart';

/// AI 对话结果（含模型元数据 + Token 用量）
class AiChatResult {
  /// AI 回复内容
  final String content;

  /// 服务商显示名称（如 "DeepSeek"、"智谱清言 GLM"）
  final String provider;

  /// 实际使用的模型名称（如 "deepseek-chat"、"glm-4-flash"）
  final String model;

  /// 输入 Token 数
  final int promptTokens;

  /// 输出 Token 数
  final int completionTokens;

  /// 总 Token 数
  final int totalTokens;

  const AiChatResult({
    required this.content,
    required this.provider,
    required this.model,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  @override
  String toString() => content;
}

class AiService {
  static const String defaultCourseName = '课程';

  final AiConfigDao _configDao = AiConfigDao();

  // ── 核心：发送 chat completion 请求（返回含模型信息的结果）─────────────────
  Future<AiChatResult> chatWithMeta(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    AiConfigModel? configOverride,
    double? temperature,
  }) async {
    final config = configOverride ?? await _configDao.getConfig();
    final effectiveKey = config.effectiveApiKey;
    final isLocal = config.provider == 'ollama' || config.provider == 'vllm';
    if (!isLocal && (effectiveKey == null || effectiveKey.isEmpty)) {
      throw '抱歉，AI 服务暂时不可用。请在「设置  →  AI 配置」中配置 API Key。';
    }

    final allMessages = [
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    final url = '${config.effectiveBaseUrl}/chat/completions';
    final maxTokens = configOverride != null
        ? (config.maxTokens < 4096 ? 4096 : config.maxTokens)
        : config.maxTokens;
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            // 本地服务（ollama/vllm）允许任意 Bearer，包括 dummy。给个占位让 header 合法
            'Authorization': 'Bearer ${effectiveKey ?? 'local-no-key'}',
            'User-Agent': 'knowledge-graph-app/1.0',
          },
          body: jsonEncode({
            'model': config.model,
            'messages': allMessages,
            'temperature': temperature ?? config.temperature,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(
            Duration(seconds: config.timeout < 120 ? 120 : config.timeout));

    if (response.statusCode != 200) {
      throw 'AI 请求失败 (${response.statusCode})，请检查网络连接和 API 配置。';
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final content = json['choices'][0]['message']['content'] as String;
    // API 响应中的 model 字段（可能与请求的略有不同）
    final actualModel = json['model'] as String? ?? config.model;

    // 解析 Token 用量（所有 OpenAI 兼容 API 都返回 usage）
    final usage = json['usage'] as Map<String, dynamic>?;
    final promptTokens = (usage?['prompt_tokens'] as int?) ?? 0;
    final completionTokens = (usage?['completion_tokens'] as int?) ?? 0;
    final totalTokens = (usage?['total_tokens'] as int?) ?? 0;

    return AiChatResult(
      content: content,
      provider: config.providerLabel,
      model: actualModel,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  // ── 向后兼容：返回纯文本内容（自动保存 Token 历史）─────────────────────
  Future<String> chat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    AiConfigModel? configOverride,
    double? temperature,
  }) async {
    final result = await chatWithMeta(messages,
        systemPrompt: systemPrompt,
        configOverride: configOverride,
        temperature: temperature);
    _autoSaveTokenHistory(result);
    return result.content;
  }

  // ── 多模态：文本 + 图片 base64 列表 → AI 回复（含视觉理解）─────────────
  /// 用 GLM-4V (zhipu:glm-4.6v) 等视觉模型分析图片 + 文本。
  ///
  /// 输入：
  /// - [textPrompt]：文字描述/问题
  /// - [imageBase64s]：图片 base64 列表（每张作为 data:image/jpeg;base64,...）
  /// - [systemPrompt]：可选系统提示
  ///
  /// 默认强制用 `zhipu:glm-4.6v`（已注册 + 内置 free key），即使用户当前
  /// 主配置是 deepseek 等纯文本模型也不影响。
  ///
  /// **空图列表**会 fallback 到普通 [chatWithMeta]（仅文本），并在 prompt
  /// 里显式标 "未读到图片" — 这是给 UI 不要崩、视频缺失场景兜底用。
  Future<AiChatResult> chatWithVision({
    required String textPrompt,
    required List<String> imageBase64s,
    String? systemPrompt,
    double? temperature,
  }) async {
    if (imageBase64s.isEmpty) {
      // 退化为纯文本调用，但 prompt 加注解防 LLM 幻觉评论 "我看到的视频"
      return chatWithMeta(
        [
          {
            'role': 'user',
            'content': '$textPrompt\n\n[注：未提供视频帧 / 图片，仅按上述文字材料评判。]'
          }
        ],
        systemPrompt: systemPrompt,
        temperature: temperature,
      );
    }

    // 强制走 zhipu glm-4.6v（vision capable + 已注册）
    final visionConfig = AiConfigModel(
      provider: 'zhipu',
      model: 'glm-4.6v',
      // apiKey 留空 → effectiveApiKey 命中内置 zhipu:glm-4.6v free key
      apiKey: null,
      maxTokens: 4096,
      temperature: temperature ?? 0.3,
      timeout: 120,
    );
    final effectiveKey = visionConfig.effectiveApiKey;
    if (effectiveKey == null || effectiveKey.isEmpty) {
      throw '视觉模型 zhipu:glm-4.6v 内置 Key 缺失，请在 AI 配置里手填。';
    }

    final url = '${visionConfig.effectiveBaseUrl}/chat/completions';

    // OpenAI vision 兼容格式：content 是数组 [{type:text}, {type:image_url}, ...]
    final visionContent = <Map<String, dynamic>>[
      {'type': 'text', 'text': textPrompt},
    ];
    for (final b64 in imageBase64s) {
      visionContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$b64'},
      });
    }

    final allMessages = <Map<String, dynamic>>[
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': visionContent},
    ];

    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $effectiveKey',
            'User-Agent': 'knowledge-graph-app/1.0',
          },
          body: jsonEncode({
            'model': visionConfig.model,
            'messages': allMessages,
            'temperature': visionConfig.temperature,
            'max_tokens': visionConfig.maxTokens,
          }),
        )
        .timeout(Duration(seconds: visionConfig.timeout));

    if (response.statusCode != 200) {
      throw '视觉 AI 请求失败 (${response.statusCode}): ${response.body}';
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final content = json['choices'][0]['message']['content'] as String;
    final actualModel = json['model'] as String? ?? visionConfig.model;
    final usage = json['usage'] as Map<String, dynamic>?;
    return AiChatResult(
      content: content,
      provider: visionConfig.providerLabel,
      model: actualModel,
      promptTokens: (usage?['prompt_tokens'] as int?) ?? 0,
      completionTokens: (usage?['completion_tokens'] as int?) ?? 0,
      totalTokens: (usage?['total_tokens'] as int?) ?? 0,
    );
  }

  /// 自动保存 Token 历史（静默失败，不阻塞主流程）
  void _autoSaveTokenHistory(AiChatResult result) {
    try {
      final userId = AuthService().currentUser?.userId;
      AiHistoryDao()
          .saveMessage(
        sessionId: 'auto_${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: result.content.length > 200
            ? '${result.content.substring(0, 200)}...'
            : result.content,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        tokensUsed: result.totalTokens,
        provider: result.provider,
        model: result.model,
        userId: userId,
      )
          .catchError((e) {
        debugPrint('Token history save failed: $e');
        return 0;
      });
    } catch (e) {
      debugPrint('Token history save failed: $e');
    }
  }

  // ── 查询账户余额 ─────────────────────────────────────────────────────────
  /// 返回 {'available': '12.34', 'currency': 'CNY'} 或 null（不支持/失败）
  /// 目前支持 DeepSeek（/user/balance）
  Future<Map<String, String>?> queryBalance(
      {AiConfigModel? configOverride}) async {
    final config = configOverride ?? await _configDao.getConfig();
    final effectiveKey = config.effectiveApiKey;
    if (effectiveKey == null || effectiveKey.isEmpty) return null;

    final baseUrl = config.effectiveBaseUrl;

    // DeepSeek: GET /user/balance
    if (config.provider == 'deepseek' || baseUrl.contains('deepseek')) {
      try {
        final resp = await http.get(
          Uri.parse('$baseUrl/user/balance'),
          headers: {
            'Authorization': 'Bearer $effectiveKey',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          // DeepSeek 返回 {"balance_infos": [{"currency":"CNY","total_balance":"...","granted_balance":"...","topped_up_balance":"..."}]}
          final infos = json['balance_infos'] as List?;
          if (infos != null && infos.isNotEmpty) {
            final info = infos[0] as Map<String, dynamic>;
            return {
              'available': info['total_balance']?.toString() ?? '0',
              'currency': info['currency']?.toString() ?? 'CNY',
            };
          }
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'AiService.queryBalance', stack: st);
      }
    }

    return null;
  }

  // ── 生成幻灯片内容 ──────────────────────────────────────────────────────
  /// 返回 List<Map>，每项含 title、bullets（List<String>）、notes
  Future<List<Map<String, dynamic>>> generateSlides(
    String topic, {
    String? chapter,
    int slideCount = 8,
    String courseName = defaultCourseName,
  }) async {
    final system = '你是一位专业的《$courseName》课程讲师，擅长制作清晰、结构化的教学课件。'
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
    } catch (e) {
      // AI 输出非合法 JSON 数组属预期，回退兜底幻灯片
      swallow(e, tag: 'AiService.parseSlides');
      return _fallbackSlides(topic, slideCount);
    }
  }

  // ── 生成视频讲解脚本 ─────────────────────────────────────────────────────
  Future<String> generateScript(
    String topic, {
    String? chapter,
    String courseName = defaultCourseName,
  }) async {
    final system = '你是一位专业的《$courseName》课程讲师，负责录制教学视频。请用中文、口语化、清晰的语言生成视频讲解脚本。';
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
    String courseName = defaultCourseName,
  }) async {
    final system = '你是《$courseName》课程出题专家，擅长设计选择题。请用中文，只返回 JSON。';
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
    } catch (e) {
      // AI 输出非合法 JSON 数组属预期，回退空列表
      swallow(e, tag: 'AiService.parseJsonList');
      return [];
    }
  }

  // ── 生成学习路径 ─────────────────────────────────────────────────────────
  Future<String> generateLearningPath(
    String topic, {
    String courseName = defaultCourseName,
  }) async {
    final system = '你是《$courseName》课程设计专家，擅长制定学习路径。请用中文 Markdown 格式回复。';
    final prompt = '请为"$topic"生成一份详细的学习路径，包含：前置知识、核心步骤（带时间估计）、推荐资源、评估方式。';
    return chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: system,
    );
  }

  // ── 生成 PlantUML 代码 ──────────────────────────────────────────────────
  Future<String> generatePuml(String topic,
      {String diagramType = 'class', AiConfigModel? configOverride}) async {
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
      configOverride: configOverride,
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
    String courseTopic = defaultCourseName,
  }) async {
    final system = '你是一位《$courseTopic》课程的知识图谱专家。'
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
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: system,
    );

    // 提取 JSON 对象
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (match == null) {
      return {
        'concepts': <Map<String, dynamic>>[],
        'relations': <Map<String, dynamic>>[]
      };
    }
    try {
      final parsed = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      return {
        'concepts':
            (parsed['concepts'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        'relations':
            (parsed['relations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      };
    } catch (e) {
      // AI 输出非合法 JSON 属预期，回退空结构
      swallow(e, tag: 'AiService.parseConceptGraph');
      return {
        'concepts': <Map<String, dynamic>>[],
        'relations': <Map<String, dynamic>>[]
      };
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
    } catch (e, st) {
      swallowDebug(e, tag: 'AiService.testConnection', stack: st);
      return false;
    }
  }

  /// 获取当前配置的服务商和模型标签（用于非 AI 调用场景的显示）
  Future<AiChatResult> getModelInfo() async {
    final config = await _configDao.getConfig();
    return AiChatResult(
      content: '',
      provider: config.providerLabel,
      model: config.model,
    );
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
