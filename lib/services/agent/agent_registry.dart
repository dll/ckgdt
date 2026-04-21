import 'package:flutter/foundation.dart';
import 'agent_model.dart';
import 'base_agent.dart';
import '../../data/local/ai_history_dao.dart';
import 'agents/voice_agent.dart';
import 'agents/graph_agent.dart';
import 'agents/path_agent.dart';
import 'agents/learning_agent.dart';
import 'agents/quiz_agent.dart';
import 'agents/repo_agent.dart';
import 'agents/assessment_agent.dart';
import 'agents/lab_agent.dart';
import 'agents/works_agent.dart';
import 'agents/achievement_agent.dart';
import 'agents/courseware_agent.dart';
import 'agents/assistant_agent.dart';
import 'agents/tutor_agent.dart';
import 'agents/doc_converter_agent.dart';
import 'agents/mobile_expert_agent.dart';
import 'agents/ethics_agent.dart';
import 'agents/course_gen_agent.dart';
import 'agents/madkg_agent.dart';
import 'agents/lab_grading_agent.dart';
import 'agents/assessment_grading_agent.dart';
import 'agents/works_grading_agent.dart';
import 'agents/safety_agent.dart';
import 'agents/virtual_student_agent.dart';
import 'agents/virtual_teacher_agent.dart';

/// 智能体注册表 + Director 编排
///
/// 参考 OpenMAIC 的 Director-Agent 模式：
/// Director 根据用户消息选择最佳智能体，智能体处理后返回回复。
class AgentRegistry {
  static final AgentRegistry instance = AgentRegistry._();
  AgentRegistry._();

  final Map<String, BaseAgent> _agents = {};
  final AiHistoryDao _historyDao = AiHistoryDao();
  AgentSession _session = AgentSession();
  bool _initialized = false;

  // 回调
  void Function(AgentMessage)? onMessage;
  void Function(AgentAction)? onAction;
  void Function(String agentId)? onAgentSwitch;

  AgentSession get session => _session;
  bool get isInitialized => _initialized;

  /// 初始化：注册所有智能体
  void initialize() {
    if (_initialized) return;

    _register(VoiceAgent());
    _register(GraphAgent());
    _register(PathAgent());
    _register(LearningAgent());
    _register(QuizAgent());
    _register(RepoAgent());
    _register(AssessmentAgent());
    _register(LabAgent());
    _register(WorksAgent());
    _register(AchievementAgent());
    _register(CoursewareAgent());
    _register(TutorAgent());
    _register(DocConverterAgent());
    _register(MobileExpertAgent());
    _register(EthicsAgent());
    _register(CourseGenAgent());
    _register(MadkgAgent());
    // 批阅智能体（教师/管理员专用）
    _register(LabGradingAgent());
    _register(AssessmentGradingAgent());
    _register(WorksGradingAgent());
    // 安全监控智能体（管理员专用）
    _register(SafetyAgent());
    // 数字孪生智能体
    _register(VirtualStudentAgent());
    _register(VirtualTeacherAgent());
    _register(AssistantAgent()); // 兜底，最后注册

    _initialized = true;
    debugPrint('AgentRegistry: 已注册 ${_agents.length} 个智能体');
  }

  void _register(BaseAgent agent) {
    _agents[agent.config.id] = agent;
  }

  /// 获取所有智能体配置（供 UI 显示标签栏）
  List<AgentConfig> get allConfigs =>
      _agents.values.map((a) => a.config).toList();

  /// 获取指定角色可用的智能体配置
  ///
  /// [role] 用户角色：'student' / 'teacher' / 'admin'
  /// admin 可见所有智能体；其他角色按 allowedRoles 过滤。
  List<AgentConfig> configsForRole(String role) {
    return _agents.values
        .map((a) => a.config)
        .where((c) => c.isAllowedFor(role))
        .toList();
  }

  /// 获取指定智能体
  BaseAgent? getAgent(String id) => _agents[id];

  /// 获取当前活跃智能体
  BaseAgent? get activeAgent =>
      _session.activeAgentId != null ? _agents[_session.activeAgentId!] : null;

  // ═══════════════════════════════════════════════════════════════════════
  // Director 编排
  // ═══════════════════════════════════════════════════════════════════════

  /// 根据用户消息选择最佳智能体并处理
  Future<AgentMessage> dispatch(String userMessage) async {
    if (!_initialized) initialize();

    // 添加用户消息到会话
    final userMsg = AgentMessage(
      agentId: 'user',
      role: MessageRole.user,
      content: userMessage,
    );
    _session.messages.add(userMsg);
    onMessage?.call(userMsg);

    // Director 选择最佳智能体
    final agent = _selectAgent(userMessage);
    final previousAgentId = _session.activeAgentId;
    _session.activeAgentId = agent.config.id;

    // 如果切换了智能体，通知 UI
    if (previousAgentId != agent.config.id) {
      onAgentSwitch?.call(agent.config.id);
    }

    // 保存用户消息到历史
    _saveToHistory(agent.config.id, 'user', userMessage);

    // 智能体处理消息
    try {
      final reply = await agent.handleMessage(userMessage, _session);
      _session.messages.add(reply);
      onMessage?.call(reply);

      // 保存智能体回复到历史
      _saveToHistory(agent.config.id, 'assistant', reply.content);

      // 如果有动作，通知 UI 执行
      if (reply.action != null) {
        onAction?.call(reply.action!);
      }

      return reply;
    } catch (e) {
      debugPrint('AgentRegistry: 智能体处理错误: $e');
      final errorReply = agent.buildReply('抱歉，处理出错了：$e');
      _session.messages.add(errorReply);
      onMessage?.call(errorReply);
      return errorReply;
    }
  }

  /// Director 选择逻辑
  BaseAgent _selectAgent(String userMessage) {
    // 1) 如果当前有活跃智能体且匹配度 > 0.5，继续用它
    if (_session.activeAgentId != null) {
      final active = _agents[_session.activeAgentId!];
      if (active != null) {
        final score = active.matchScore(userMessage, _session);
        if (score > 0.5) return active;
      }
    }

    // 2) 遍历所有智能体，取 matchScore 最高的
    BaseAgent? best;
    double bestScore = 0;
    for (final agent in _agents.values) {
      final score = agent.matchScore(userMessage, _session);
      if (score > bestScore) {
        bestScore = score;
        best = agent;
      }
    }

    // 3) 如果最高分 < 0.3，用 AssistantAgent 兜底
    if (bestScore < 0.3) {
      return _agents['assistant'] ?? _agents.values.last;
    }

    return best ?? _agents['assistant'] ?? _agents.values.last;
  }

  /// 手动切换到指定智能体
  void switchTo(String agentId) {
    final agent = _agents[agentId];
    if (agent == null) return;

    _session.activeAgentId = agentId;
    onAgentSwitch?.call(agentId);

    // 添加系统消息
    final sysMsg = AgentMessage(
      agentId: agentId,
      agentName: agent.config.name,
      agentEmoji: agent.config.emoji,
      role: MessageRole.system,
      content: agent.greeting,
    );
    _session.messages.add(sysMsg);
    onMessage?.call(sysMsg);
  }

  /// 重置会话
  void resetSession() {
    _session = AgentSession();
  }

  /// 获取欢迎消息
  AgentMessage getWelcomeMessage() {
    return AgentMessage(
      agentId: 'assistant',
      agentName: '小知',
      agentEmoji: '🤖',
      role: MessageRole.system,
      content: '你好！我是小知，你的 AI 学习助手。\n\n'
          '你可以直接告诉我你需要什么，我会自动找到合适的专家来帮你。\n'
          '比如："帮我出几道测验题"、"打开知识图谱"、"我哪里比较薄弱"...\n\n'
          '也可以点击下方的智能体标签，直接和特定专家对话。',
    );
  }

  /// 异步保存消息到历史（静默失败）
  void _saveToHistory(String agentId, String role, String content) {
    _historyDao.saveMessage(
      sessionId: _session.id,
      agentId: agentId,
      role: role,
      content: content,
    ).catchError((e) {
      debugPrint('AgentRegistry: 保存历史失败: $e');
      return 0;
    });
  }
}
