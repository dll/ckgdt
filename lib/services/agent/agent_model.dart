/// 多智能体系统 — 数据模型
///
/// 参考 OpenMAIC（清华大学开放式多智能体互动课堂）架构理念：
/// Agent = 配置 + 人设 + 能力，Director 编排分发。
library;

/// 智能体工具 — 允许智能体调用本地能力（数据库查询、文件操作等）
///
/// AI 在回复中输出 `{"tool": "name", "params": {...}}` 格式的 JSON，
/// 由 [BaseAgent] 解析并执行对应的 [execute] 函数，
/// 将结果注入上下文后继续对话。
class AgentTool {
  final String name;
  final String description;
  final Map<String, String> parameters; // 参数名 → 说明
  final Future<String> Function(Map<String, dynamic> params) execute;

  const AgentTool({
    required this.name,
    required this.description,
    this.parameters = const {},
    required this.execute,
  });

  /// 生成工具声明文本（嵌入 Prompt）
  String toPromptDeclaration() {
    final buf = StringBuffer('- **$name**: $description');
    if (parameters.isNotEmpty) {
      buf.write('\n  参数: ');
      buf.write(parameters.entries
          .map((e) => '`${e.key}` (${e.value})')
          .join(', '));
    }
    return buf.toString();
  }
}

/// 经典案例
class AgentCase {
  final String title;      // 案例标题
  final String userInput;  // 用户输入示例
  final String agentReply; // 智能体回复示例（摘要）

  const AgentCase({
    required this.title,
    required this.userInput,
    required this.agentReply,
  });
}

/// 智能体配置
class AgentConfig {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final String persona; // 系统提示词（人设）
  final int priority; // 1-10，Director 选择优先级
  final List<String> keywords; // 触发关键词
  final List<String> capabilities; // 能力标签
  final bool requiresAi; // 是否需要 AI API
  final bool useRag; // 是否启用 RAG（检索增强生成）
  final List<AgentTool> tools; // 可调用的工具列表
  final List<String> usageSteps; // 使用步骤
  final List<AgentCase> classicCases; // 经典案例

  /// 允许使用此智能体的用户角色列表
  ///
  /// 空列表 = 所有角色可用（默认）。
  /// 例如 `['teacher', 'admin']` 表示仅教师和管理员可见。
  final List<String> allowedRoles;

  const AgentConfig({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.persona,
    this.priority = 5,
    this.keywords = const [],
    this.capabilities = const [],
    this.requiresAi = false,
    this.useRag = false,
    this.tools = const [],
    this.usageSteps = const [],
    this.classicCases = const [],
    this.allowedRoles = const [],
  });

  /// 检查给定角色是否可以使用此智能体
  bool isAllowedFor(String role) {
    if (allowedRoles.isEmpty) return true; // 空 = 不限制
    return allowedRoles.contains(role);
  }
}

/// 消息角色
enum MessageRole { user, agent, system }

/// 智能体消息
class AgentMessage {
  final String id;
  final String agentId;
  final String agentName;
  final String agentEmoji;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final AgentAction? action;
  final bool isLoading;

  /// AI 服务商名称（如 "DeepSeek"、"智谱清言 GLM"）
  final String? modelProvider;

  /// AI 模型名称（如 "deepseek-chat"、"glm-4-flash"）
  final String? modelName;

  /// 输入 Token 数
  final int promptTokens;

  /// 输出 Token 数
  final int completionTokens;

  /// 总 Token 数
  final int totalTokens;

  AgentMessage({
    String? id,
    required this.agentId,
    this.agentName = '',
    this.agentEmoji = '',
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.action,
    this.isLoading = false,
    this.modelProvider,
    this.modelName,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
        timestamp = timestamp ?? DateTime.now();

  AgentMessage copyWith({String? content, bool? isLoading, AgentAction? action}) {
    return AgentMessage(
      id: id,
      agentId: agentId,
      agentName: agentName,
      agentEmoji: agentEmoji,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      action: action ?? this.action,
      isLoading: isLoading ?? this.isLoading,
      modelProvider: modelProvider,
      modelName: modelName,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }
}

/// 智能体动作（导航、登录等副作用）
class AgentAction {
  final String type; // navigate, login, logout, generate, query, open_page
  final Map<String, dynamic> params;
  final String? description;

  const AgentAction({
    required this.type,
    this.params = const {},
    this.description,
  });
}

/// 会话状态
class AgentSession {
  final String id;
  final List<AgentMessage> messages;
  String? activeAgentId;
  final DateTime createdAt;

  AgentSession({
    String? id,
    List<AgentMessage>? messages,
    this.activeAgentId,
    DateTime? createdAt,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
        messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// 获取最近 N 条消息（用于构建 AI 上下文）
  List<AgentMessage> recentMessages([int count = 10]) {
    if (messages.length <= count) return List.from(messages);
    return messages.sublist(messages.length - count);
  }

  /// 获取最近的用户消息文本（用于上下文判断）
  String? get lastUserMessage {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) return messages[i].content;
    }
    return null;
  }
}
