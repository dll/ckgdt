import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📝 测验智能体 — 出题/批改/错题分析
class QuizAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'quiz',
        name: '测验教练',
        emoji: '📝',
        description: '出题练习、批改答案、分析错题。',
        persona: '你是测验教练，擅长出题和分析错题。'
            '出题时：给出题目、4个选项（A/B/C/D）、正确答案和解析。'
            '分析错题时：找出知识盲点，给出针对性复习建议。'
            '课程：《移动应用开发》。每次出 3-5 道选择题。',
        priority: 7,
        keywords: ['测验', '出题', '做题', '答题', '错题', '考试', '练习', '题目'],
        capabilities: ['出题', '批改', '错题分析', '章节推荐'],
        requiresAi: true,
      );

  @override
  List<String> get quickCommands =>
      ['出5道Flutter题', '分析我的错题', '第三章测验', '复习建议'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final reply = await safeAiChat(messages, aiService: _ai);
    return buildReply(reply);
  }
}
