import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🗺️ 路径智能体 — 学习路径规划
class PathAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'path',
        name: '路径规划师',
        emoji: '🗺️',
        description: '根据你的水平和目标，量身定制学习路径。',
        persona: '你是学习规划专家，擅长根据学习目标和当前水平设计个性化学习路径。'
            '你的回答应包含：阶段划分、每阶段目标和时长、前置知识、推荐资源。'
            '用 Markdown 格式回答。课程背景：《移动应用开发》，涵盖 Android/iOS/Flutter/小程序/鸿蒙。',
        priority: 6,
        keywords: ['路径', '计划', '怎么学', '从哪开始', '推荐', '学习计划', '规划', '路线'],
        capabilities: ['规划学习路径', '推荐学习顺序', '评估学习进度'],
        requiresAi: true,
      );

  @override
  List<String> get quickCommands =>
      ['零基础学Flutter', '制定学习计划', '推荐学习顺序', '评估我的进度'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final reply = await safeAiChat(messages, aiService: _ai);
    return buildReply(reply);
  }
}
