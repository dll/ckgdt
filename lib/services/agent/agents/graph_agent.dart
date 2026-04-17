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
        usageSteps: [
          '在对话面板中选择 🕸️ 图谱专家',
          '输入想要生成或查询的知识主题',
          '智能体返回概念节点和关系结构',
          '可继续追问扩展或细化图谱内容',
        ],
        classicCases: [
          AgentCase(title: '生成技术图谱', userInput: '帮我生成 Flutter 状态管理的知识图谱', agentReply: '## Flutter 状态管理知识图谱\n\n### 核心概念\n- setState（基础状态管理）\n- Provider（依赖注入）\n- Riverpod（改进版 Provider）\n- Bloc/Cubit（事件驱动）\n\n### 关系\n- setState → Provider（进阶替代）\n- Provider → Riverpod（演进）'),
          AgentCase(title: '扩展已有图谱', userInput: '在 Android 开发图谱中补充 Jetpack Compose 相关概念', agentReply: '为 Android 图谱补充以下概念：\n- Jetpack Compose（声明式 UI）\n- Composable 函数\n- State hoisting\n- remember/mutableStateOf'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['生成Flutter图谱', '分析概念关系', '扩展知识点', '图谱统计'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
