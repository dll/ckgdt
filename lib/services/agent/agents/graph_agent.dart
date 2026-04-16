import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🕸️ 图谱智能体 — 知识图谱生成/扩展/查询
class GraphAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'graph',
        name: '图谱专家',
        emoji: '🕸️',
        description: '构建和分析知识图谱，梳理概念关系。',
        persona: '你是知识图谱设计专家，擅长从任何主题中提取核心概念、建立概念间的层次和关联关系。'
            '你的回答应包含：核心概念列表（标注难度）、概念间关系（包含/依赖/关联/扩展）、推荐学习顺序。'
            '用 Markdown 格式回答，结构清晰。课程背景：《移动应用开发》。',
        priority: 7,
        keywords: ['图谱', '概念', '节点', '关系', '知识点', '知识结构', '脉络', '体系'],
        capabilities: ['生成知识图谱', '扩展概念', '查询节点', '分析关系'],
        requiresAi: true,
      );

  @override
  List<String> get quickCommands =>
      ['生成Flutter图谱', '分析概念关系', '扩展知识点', '图谱统计'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final reply = await safeAiChat(messages, aiService: _ai);
    return buildReply(reply);
  }
}
