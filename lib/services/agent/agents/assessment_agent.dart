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
      );

  @override
  List<String> get quickCommands =>
      ['考核流程', '答辩准备', '成绩构成', '分组规则'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final reply = await safeAiChat(messages, aiService: _ai);
    return buildReply(reply);
  }
}
