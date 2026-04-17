import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🤖 通用助手智能体 — 兜底问答/功能介绍/转接
class AssistantAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'assistant',
        name: '通用助手',
        emoji: '🤖',
        description: '通用问答、系统帮助、功能介绍。',
        persona: '你是"小知"，《移动应用开发》课程的 AI 助手。'
            '你是多智能体系统的总调度，当用户的问题不属于特定领域时由你回答。'
            '你了解系统中所有智能体的能力：'
            '🎙️语音助手（登录/导航）、🕸️图谱专家、🗺️路径规划师、📚学习伙伴、'
            '📝测验教练、📦仓库管家、📊考核助理、🔬实验助手、🎨作品展评官、'
            '🏆达成分析师、📑课件专家、👨‍🏫课堂助教、📄文档转换、📱移动专家、'
            '🏛️思政伦理、🎓课程生成。'
            '如果用户的问题更适合某个专家，建议他们切换。回答简洁友好。',
        priority: 1, // 最低优先级，作为兜底
        keywords: [], // 无特定关键词
        capabilities: ['通用问答', '功能介绍', '智能体推荐'],
        requiresAi: true,
        usageSteps: [
          '通过首页"多智能体"或全局悬浮按钮"助手"打开',
          '直接输入任何问题，系统自动匹配最佳智能体',
          '如需特定专家，点击智能体标签手动切换',
          '通用问题由我直接回答，专业问题推荐对应专家',
        ],
        classicCases: [
          AgentCase(title: '功能介绍', userInput: '有哪些智能体？', agentReply: '系统共有 17 个智能体：\n🎙️语音助手、🕸️图谱专家、🗺️路径规划师、📚学习伙伴、📝测验教练、📦仓库管家、📊考核助理、🔬实验助手、🎨作品展评官、🏆达成分析师、📑课件专家、👨‍🏫课堂助教、📄文档转换、📱移动专家、🏛️思政伦理、🎓课程生成、🤖通用助手\n\n直接提问即可，我会自动匹配最合适的专家！'),
          AgentCase(title: '智能转接', userInput: '帮我出几道测验题', agentReply: '（自动切换到 📝 测验教练）\n\n好的，我来帮你出题！请问你想要哪个章节的题目？'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['有哪些智能体', '系统功能介绍', '使用帮助', '课程简介'];

  @override
  double matchScore(String userMessage, AgentSession session) {
    // 兜底智能体：始终返回 0.2（低于其他智能体的关键词匹配）
    if (session.activeAgentId == config.id) return 0.4;
    return 0.2;
  }

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
