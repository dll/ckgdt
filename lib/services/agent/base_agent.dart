import 'package:flutter/foundation.dart';
import 'agent_model.dart';
import '../ai_service.dart';

/// 智能体抽象基类
///
/// 所有智能体继承此类，实现 [handleMessage] 和 [matchScore]。
/// Director 通过 [matchScore] 选择最佳智能体处理用户消息。
abstract class BaseAgent {
  /// 智能体配置
  AgentConfig get config;

  /// 处理用户消息，返回智能体回复
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session);

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

  /// 构建智能体回复消息（含模型信息）
  AgentMessage buildReply(
    String content, {
    AgentAction? action,
    String? modelProvider,
    String? modelName,
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

  /// 安全调用 AI 服务（带错误处理），返回含模型元数据的结果
  Future<AiChatResult> safeAiChatWithMeta(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    required AiService aiService,
  }) async {
    try {
      return await aiService.chatWithMeta(messages,
          systemPrompt: systemPrompt ?? config.persona);
    } catch (e) {
      debugPrint('${config.name}: AI 调用失败: $e');
      return AiChatResult(
        content: '抱歉，AI 服务暂时不可用。请检查网络连接和 AI 配置。\n\n错误: $e',
        provider: '',
        model: '',
      );
    }
  }

  /// 安全调用 AI 服务（向后兼容，返回纯文本）
  Future<String> safeAiChat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    required dynamic aiService,
  }) async {
    try {
      return await aiService.chat(messages,
          systemPrompt: systemPrompt ?? config.persona);
    } catch (e) {
      debugPrint('${config.name}: AI 调用失败: $e');
      return '抱歉，AI 服务暂时不可用。请检查网络连接和 AI 配置。\n\n错误: $e';
    }
  }
}
