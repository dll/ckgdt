/// 多智能体系统 — 数据模型
///
/// 参考 OpenMAIC（清华大学开放式多智能体互动课堂）架构理念：
/// Agent = 配置 + 人设 + 能力，Director 编排分发。

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
