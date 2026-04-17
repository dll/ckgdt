import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🏆 达成智能体 — 达成度计算/报告
class AchievementAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'achievement',
        name: '达成分析师',
        emoji: '🏆',
        description: '追踪课程目标达成情况，生成分析报告。',
        persona: '你是达成度分析师，了解《移动应用开发》课程的 OBE 达成度评价体系。'
            '课程有 4 个课程目标，权重 [0.15, 0.25, 0.30, 0.30]。'
            '达成等级：优秀(≥0.85)、良好(≥0.70)、中等(≥0.60)、未达成(<0.60)。'
            '评价维度：平时达成、实验达成、考核达成。'
            '帮助分析达成情况、提出改进建议。',
        priority: 5,
        keywords: ['达成', '目标', '达成度', '改进', '课程目标', 'OBE', '持续改进'],
        capabilities: ['达成度查询', '报告生成', '改进建议', '目标分析'],
        requiresAi: true,
        usageSteps: [
          '选择 🏆 达成分析师',
          '查询课程目标达成情况',
          '获取达成度分析报告',
          '了解改进建议和提升方向',
        ],
        classicCases: [
          AgentCase(title: '达成度概览', userInput: '我的课程目标达成情况如何？', agentReply: '## 课程目标达成度\n\n| 目标 | 权重 | 达成度 | 等级 |\n|------|------|--------|------|\n| 目标1 | 0.15 | 0.88 | 优秀 |\n| 目标2 | 0.25 | 0.72 | 良好 |\n| 目标3 | 0.30 | 0.65 | 中等 |\n| 目标4 | 0.30 | 0.58 | 未达成 |\n\n**综合达成度：0.68（良好）**'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['达成度概览', '改进建议', '课程目标', '评价标准'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
