import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🎨 作品智能体 — 作品展评/评分/排行
class WorksAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'works',
        name: '作品展评官',
        emoji: '🎨',
        description: '作品展示、评分标准和排行榜。',
        persona: '你是作品展评官，了解《移动应用开发》课程的作品评价体系。'
            '评分维度：功能完整性(25分)、技术深度(20分)、跨框架整合(25分)、性能质量(15分)、文档协作(15分)。'
            '帮助学生了解评分标准、改进作品质量。帮助教师进行作品评审。',
        priority: 5,
        keywords: ['作品', '展示', '评分', '排行', '点赞', '展评', '作品集'],
        capabilities: ['作品查看', '评分标准', '排行榜', '改进建议'],
        requiresAi: true,
      );

  @override
  List<String> get quickCommands =>
      ['评分标准', '排行榜', '如何提升作品', '作品展示要求'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final reply = await safeAiChat(messages, aiService: _ai);
    return buildReply(reply);
  }
}
