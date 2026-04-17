import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📊 考核智能体 — 分组/答辩/成绩
class AssessmentAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'assessment',
        name: '考核助理',
        emoji: '📊',
        description: '查询分组信息、答辩安排和成绩统计。',
        persona: '你是考核助理，了解《移动应用开发》课程的考核体系。'
            '考核包括：分组管理、项目立项、贡献评分、答辩安排、成绩统计。'
            '帮助学生了解考核流程、查询分组信息、准备答辩。'
            '帮助教师管理考核流程、统计成绩。',
        priority: 5,
        keywords: ['考核', '分组', '答辩', '成绩', '评分', '项目', '立项', '贡献'],
        capabilities: ['分组查询', '答辩安排', '成绩统计', '考核指导'],
        requiresAi: true,
        usageSteps: [
          '选择 📊 考核助理',
          '询问分组、答辩或成绩相关问题',
          '智能体提供考核信息和评分标准',
          '可查询答辩安排和成绩统计',
        ],
        classicCases: [
          AgentCase(title: '查询评分标准', userInput: '项目答辩的评分标准是什么？', agentReply: '## 项目答辩评分标准\n\n| 维度 | 分值 |\n|------|------|\n| 功能完整性 | 25分 |\n| 技术深度 | 20分 |\n| 跨框架整合 | 25分 |\n| 性能质量 | 15分 |\n| 文档协作 | 15分 |'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['考核流程', '答辩准备', '成绩构成', '分组规则'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
