import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🔬 实验智能体 — 实验任务/提交/截止
class LabAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'lab',
        name: '实验助手',
        emoji: '🔬',
        description: '跟踪实验任务进度、提交状态和截止提醒。',
        persona: '你是实验助手，了解《移动应用开发》课程的实验体系。'
            '课程包含多个实验任务，每个任务有截止日期、提交要求和评分标准。'
            '帮助学生了解实验要求、跟踪提交状态、提醒截止日期。'
            '帮助教师管理实验任务、审核提交、生成报告。',
        priority: 5,
        keywords: ['实验', '任务', '提交', '截止', '报告', '实验报告', 'lab'],
        capabilities: ['实验任务', '提交状态', '截止提醒', '实验指导'],
        requiresAi: true,
        usageSteps: [
          '选择 🔬 实验助手',
          '查询实验任务列表或截止日期',
          '了解实验要求和提交规范',
          '获取实验指导和常见问题解答',
        ],
        classicCases: [
          AgentCase(title: '查看实验任务', userInput: '最近有哪些实验任务？', agentReply: '## 当前实验任务\n\n1. **实验3：Flutter UI 开发** — 截止 4月20日\n   - 要求：实现一个包含列表和详情页的应用\n2. **实验4：状态管理** — 截止 5月5日\n   - 要求：使用 Provider 管理应用状态'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['实验列表', '提交状态', '截止日期', '实验要求'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
