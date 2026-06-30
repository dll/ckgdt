import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'agent_model.dart';
import 'prompt_loader.dart';
import 'teaching_context_service.dart';
import '../ai_service.dart';
import '../rag_service.dart';
import '../course_context_service.dart';
import '../../data/local/agent_call_log_dao.dart';

/// 智能体抽象基类
///
/// 所有智能体继承此类，实现 [handleMessage] 和 [matchScore]。
/// Director 通过 [matchScore] 选择最佳智能体处理用户消息。
abstract class BaseAgent {
  /// 智能体配置
  AgentConfig get config;

  /// 处理用户消息，返回智能体回复
  Future<AgentMessage> handleMessage(String userMessage, AgentSession session);

  /// 优先从 `assets/agent_prompts/{config.id}.md` 加载 persona；
  /// 若 assets 中没有该文件则回退到代码中的 `config.persona`。
  ///
  /// 用 [PromptLoader] 内存缓存，二次调用零成本。
  Future<String> loadEffectivePersona() async {
    final fromAssets = await PromptLoader.load(config.id);
    final raw = fromAssets ?? config.persona;
    return promptWithCourse(raw);
  }

  /// 将 {key} 占位符替换为当前课程上下文的实际值。
  ///
  /// 支持的占位符：
  /// - `{courseName}` — 当前课程名称
  /// - `{chapterCount}` — 当前课程章节数
  /// - `{chapterName}` — 章节名称占位
  /// - `{topicName}` — 主题名称占位
  /// - 其它 `{key}` 可传入 [extraVars] 覆盖。
  Future<String> promptWithCourse(String text,
      {Map<String, String>? extraVars}) async {
    if (!text.contains('{')) return text;
    try {
      final ctx = CourseContextService();
      final course = await ctx.getActiveCourse();

      var result = text
          .replaceAll('{courseName}', course.name)
          .replaceAll('{chapterCount}', course.chapterCount.toString())
          .replaceAll('{chapterName}', 'X')
          .replaceAll('{topicName}', '课程主题');

      if (extraVars != null) {
        for (final e in extraVars.entries) {
          result = result.replaceAll('{${e.key}}', e.value);
        }
      }
      return result;
    } catch (_) {
      return text;
    }
  }

  /// 判断此智能体是否能处理该消息（0.0 ~ 1.0）
  /// Director 用此分数选择最佳智能体
  double matchScore(String userMessage, AgentSession session) {
    // 默认实现：关键词匹配
    double score = _keywordScore(userMessage);

    // 如果当前会话已激活此智能体，加分（上下文连续性）
    if (session.activeAgentId == config.id) {
      score += 0.3;
    }

    return score.clamp(0.0, 1.0);
  }

  /// 获取欢迎语
  String get greeting =>
      '你好！我是${config.emoji} ${config.name}。${config.description}';

  /// 获取快捷指令列表（显示为 chip）
  List<String> get quickCommands => [];

  // ═══════════════════════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════════════════════

  /// 关键词匹配得分
  double _keywordScore(String text) {
    if (config.keywords.isEmpty) return 0.0;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    int matched = 0;
    for (final kw in config.keywords) {
      if (normalized.contains(kw.toLowerCase())) matched++;
    }
    if (matched == 0) return 0.0;
    // 匹配 1 个关键词 = 0.4，2 个 = 0.6，3+ = 0.8
    return (0.2 + matched * 0.2).clamp(0.0, 0.8);
  }

  /// 构建智能体回复消息（含模型信息 + Token 用量）
  AgentMessage buildReply(
    String content, {
    AgentAction? action,
    String? modelProvider,
    String? modelName,
    int promptTokens = 0,
    int completionTokens = 0,
    int totalTokens = 0,
  }) {
    return AgentMessage(
      agentId: config.id,
      agentName: config.name,
      agentEmoji: config.emoji,
      role: MessageRole.agent,
      content: content,
      action: action,
      modelProvider: modelProvider,
      modelName: modelName,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  /// 从 AiChatResult 构建回复消息（自动提取 Token 用量）
  AgentMessage buildReplyFromResult(AiChatResult result,
      {AgentAction? action}) {
    return buildReply(
      result.content,
      action: action,
      modelProvider: result.provider,
      modelName: result.model,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      totalTokens: result.totalTokens,
    );
  }

  /// 构建加载中消息
  AgentMessage buildLoading() {
    return AgentMessage(
      agentId: config.id,
      agentName: config.name,
      agentEmoji: config.emoji,
      role: MessageRole.agent,
      content: '正在思考...',
      isLoading: true,
    );
  }

  /// 构建 AI 对话的消息列表（含系统提示词 + 历史消息）
  List<Map<String, String>> buildAiMessages(
      String userMessage, AgentSession session) {
    final messages = <Map<String, String>>[];

    // 添加历史消息（最近 8 条）
    for (final msg in session.recentMessages(8)) {
      if (msg.isLoading) continue;
      messages.add({
        'role': msg.role == MessageRole.user ? 'user' : 'assistant',
        'content': msg.content,
      });
    }

    // 添加当前用户消息
    messages.add({'role': 'user', 'content': userMessage});

    return messages;
  }

  /// 安全调用 AI 服务（带错误处理），返回含模型元数据的结果。
  ///
  /// 自动写入 [AgentCallLogDao] 审计日志（异常静默不影响主链路）。
  ///
  /// **chainId / chainStep**：当被 [OrchestratorAgent] 调用时通过 zone 注入；
  /// 直接调用本方法时传 null 即可。日志里以此关联整条 Agent 链。
  Future<AiChatResult> safeAiChatWithMeta(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    required AiService aiService,
    double? temperature,
  }) async {
    final stopwatch = Stopwatch()..start();
    final basePrompt = systemPrompt ?? await loadEffectivePersona();
    final lastUserMsg =
        messages.isNotEmpty ? (messages.last['content'] ?? '') : '';
    final teachingContext =
        await AgentTeachingContextService.instance.buildPromptContext(
      userMessage: lastUserMsg,
    );
    final effectivePrompt = teachingContext.trim().isEmpty
        ? basePrompt
        : '$basePrompt\n\n$teachingContext';
    final promptChars = effectivePrompt.length + lastUserMsg.length;
    AiChatResult? result;
    String? error;

    try {
      result = await aiService.chatWithMeta(messages,
          systemPrompt: effectivePrompt, temperature: temperature);
      return result;
    } catch (e) {
      error = e.toString();
      debugPrint('${config.name}: AI 调用失败: $e');
      return AiChatResult(
        content: '抱歉，AI 服务暂时不可用。请检查网络连接和 AI 配置。\n\n错误: $e',
        provider: '',
        model: '',
      );
    } finally {
      stopwatch.stop();
      // 异步写日志，不 await — 不阻塞主调用链
      AgentCallLogDao.instance.insert(
        agentId: config.id,
        agentName: config.name,
        chainId: Zone.current[#agentChainId] as String?,
        chainStep: Zone.current[#agentChainStep] as int?,
        promptSummary: lastUserMsg.length > 200
            ? '${lastUserMsg.substring(0, 200)}…'
            : lastUserMsg,
        responseSummary: result?.content,
        durationMs: stopwatch.elapsedMilliseconds,
        promptChars: promptChars,
        responseChars: result?.content.length,
        provider: result?.provider,
        model: result?.model,
        error: error,
      );
    }
  }

  /// 安全调用 AI 服务（向后兼容，返回纯文本）
  Future<String> safeAiChat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    required AiService aiService,
  }) async {
    try {
      return await aiService.chat(messages,
          systemPrompt: systemPrompt ?? await loadEffectivePersona());
    } catch (e) {
      debugPrint('${config.name}: AI 调用失败: $e');
      return '抱歉，AI 服务暂时不可用。请检查网络连接和 AI 配置。\n\n错误: $e';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RAG 增强
  // ═══════════════════════════════════════════════════════════════════════

  final RagService _ragService = RagService();

  /// 构建 RAG 增强的系统提示词
  ///
  /// 如果 [config.useRag] 为 true，先检索相关课程知识，
  /// 将结果拼接到 persona 末尾作为参考资料。
  /// 构造带 RAG 上下文的系统提示词
  ///
  /// 检索优先级：
  /// 1. 向量索引（rag_embeddings 表非空）→ retrieveContextVector（语义检索）
  /// 2. 索引为空 / 失败 → retrieveContext（TF-IDF + 关键字回退）
  ///
  /// 拼接结果到 persona 末尾作为参考资料。
  Future<String> buildRagPrompt(String userMessage) async {
    final persona = await loadEffectivePersona();
    if (!config.useRag) return persona;

    try {
      // 优先向量检索（语义匹配，对长文档/同义词更准）
      var context = await _ragService.retrieveContextVector(
        userMessage,
        topK: 6,
      );

      // 向量索引为空 / 检索失败 → 回退到 TF-IDF
      if (context.isEmpty) {
        context = await _ragService.retrieveContext(
          userMessage,
          maxConcepts: 6,
          includeRelations: true,
          includeResources: true,
        );
      }

      if (context.isEmpty) return persona;

      return '$persona\n\n$context\n\n'
          '请基于以上课程知识库的参考资料回答用户问题，'
          '引用具体概念或资料时标注来源。'
          '如果参考资料与问题无关，可忽略。';
    } catch (e) {
      debugPrint('${config.name}: RAG 检索失败: $e');
      return persona;
    }
  }

  /// RAG 增强版 AI 调用（自动检索上下文）
  Future<AiChatResult> safeAiChatWithRag(
    String userMessage,
    List<Map<String, String>> messages, {
    required AiService aiService,
  }) async {
    final prompt = await buildRagPrompt(userMessage);
    return safeAiChatWithMeta(messages,
        systemPrompt: prompt, aiService: aiService);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 工具调用
  // ═══════════════════════════════════════════════════════════════════════

  /// 生成工具声明文本，嵌入系统提示词
  String buildToolsPromptSection() {
    if (config.tools.isEmpty) return '';

    final buf = StringBuffer('\n\n## 可用工具\n\n');
    buf.writeln('你可以调用以下工具获取实时数据。'
        '需要调用工具时，在回复中**单独一行**输出 JSON：');
    buf.writeln('```');
    buf.writeln('{"tool": "工具名", "params": {"参数名": "值"}}');
    buf.writeln('```');
    buf.writeln();
    for (final tool in config.tools) {
      buf.writeln(tool.toPromptDeclaration());
    }
    buf.writeln();
    buf.writeln('工具执行结果会自动注入上下文，你再据此给出最终回答。');
    buf.writeln('如果不需要工具，直接回答用户即可。');
    return buf.toString();
  }

  /// 解析 AI 回复中的工具调用指令
  ///
  /// 返回 `null` 表示回复中没有工具调用。
  Map<String, dynamic>? parseToolCall(String aiReply) {
    // 匹配 JSON 块：{"tool": "...", "params": {...}}
    for (final candidate in _jsonObjectCandidates(aiReply)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is! Map<String, dynamic>) continue;
        final toolName = decoded['tool']?.toString();
        if (toolName == null || toolName.isEmpty) continue;
        final rawParams = decoded['params'];
        final params = rawParams is Map<String, dynamic>
            ? rawParams
            : rawParams is Map
                ? rawParams.map((k, v) => MapEntry(k.toString(), v))
                : <String, dynamic>{};
        return {'tool': toolName, 'params': params};
      } catch (e) {
        debugPrint('${config.name}: 工具调用候选解析失败: $e');
      }
    }
    return null;
  }

  List<String> _jsonObjectCandidates(String text) {
    final candidates = <String>[];
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).allMatches(text);
    for (final match in fenced) {
      final content = match.group(1)?.trim();
      if (content != null && content.startsWith('{')) {
        candidates.add(content);
      }
    }

    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 123) continue; // {
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var j = i; j < text.length; j++) {
        final ch = text[j];
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch == '\\') {
          escaped = true;
          continue;
        }
        if (ch == '"') {
          inString = !inString;
          continue;
        }
        if (inString) continue;
        if (ch == '{') depth++;
        if (ch == '}') depth--;
        if (depth == 0) {
          candidates.add(text.substring(i, j + 1));
          break;
        }
      }
    }
    return candidates;
  }

  /// 执行工具调用并返回结果
  Future<String?> executeToolCall(Map<String, dynamic> toolCall) async {
    final toolName = toolCall['tool'] as String;
    final params = toolCall['params'] as Map<String, dynamic>? ?? {};

    final tool = config.tools.where((t) => t.name == toolName).firstOrNull;
    if (tool == null) {
      return '⚠️ 未知工具: $toolName';
    }

    try {
      return await tool.execute(params);
    } catch (e) {
      debugPrint('${config.name}: 工具执行失败 ($toolName): $e');
      return '⚠️ 工具执行出错: $e';
    }
  }

  /// 带工具调用循环的 AI 对话（最多执行 1 轮工具调用）
  ///
  /// 流程：
  /// 1. 发送用户消息 → 获取 AI 回复
  /// 2. 如果回复中包含工具调用 → 执行工具 → 将结果注入上下文 → 再次调用 AI
  /// 3. 返回最终回复
  Future<AiChatResult> safeAiChatWithTools(
    String userMessage,
    List<Map<String, String>> messages, {
    required AiService aiService,
  }) async {
    // 准备系统提示词（RAG + 工具声明）
    String prompt = config.useRag
        ? await buildRagPrompt(userMessage)
        : await loadEffectivePersona();

    if (config.tools.isNotEmpty) {
      prompt += buildToolsPromptSection();
    }

    // 第一轮调用
    final firstResult = await safeAiChatWithMeta(
      messages,
      systemPrompt: prompt,
      aiService: aiService,
    );

    // 检查是否有工具调用
    if (config.tools.isEmpty) return firstResult;

    final toolCall = parseToolCall(firstResult.content);
    if (toolCall == null) return firstResult;

    // 执行工具
    final toolResult = await executeToolCall(toolCall);
    if (toolResult == null) return firstResult;

    // 构建第二轮消息：注入工具结果
    final followUp = List<Map<String, String>>.from(messages);
    followUp.add({
      'role': 'assistant',
      'content': firstResult.content,
    });
    followUp.add({
      'role': 'user',
      'content': '工具 "${toolCall['tool']}" 的执行结果：\n$toolResult\n\n'
          '请根据以上工具返回的数据，给出完整的回答。',
    });

    // 第二轮调用（不再包含工具声明，防止无限循环）
    return safeAiChatWithMeta(
      followUp,
      systemPrompt: await loadEffectivePersona(),
      aiService: aiService,
    );
  }
}
