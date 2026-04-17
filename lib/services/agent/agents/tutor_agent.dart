import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 👨‍🏫 课堂助教智能体 — 解释课件内容/辅助教学/答疑
class TutorAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'tutor',
        name: '课堂助教',
        emoji: '\u{1F468}\u{200D}\u{1F3EB}',
        description: '解释课件内容、辅助教学、课堂答疑。',
        persona: '你是课堂助教，专门帮助学生理解《移动应用开发》课程的课件内容。'
            '你的职责：1) 解释课件中的概念和术语，用通俗易懂的语言'
            '2) 对课件内容进行扩展讲解，补充实际案例'
            '3) 回答学生在课堂上遇到的疑问'
            '4) 帮助教师准备课堂互动问题和讨论话题'
            '5) 总结课件要点，生成复习提纲'
            '课程涵盖 6 章：移动技术体系、Android/iOS 原生、Flutter/RN 混合、'
            '微信小程序、HarmonyOS、综合实践。'
            '回答时结合课件内容，举例说明，确保学生能理解。',
        priority: 6,
        keywords: [
          '课堂', '助教', '讲解', '解释', '课件内容', '上课',
          '听不懂', '什么意思', '举个例子', '总结', '要点',
          '复习提纲', '课堂互动', '讨论', '答疑',
        ],
        capabilities: ['课件讲解', '概念解释', '课堂答疑', '复习提纲'],
        requiresAi: true,
        usageSteps: [
          '选择 👨‍🏫 课堂助教',
          '提出课件内容相关的疑问',
          '智能体用通俗语言解释概念',
          '可请求举例说明或生成复习提纲',
        ],
        classicCases: [
          AgentCase(title: '概念解释', userInput: '什么是 Hot Reload？', agentReply: '## Hot Reload（热重载）\n\n**通俗解释**：就像你在画画时，不用擦掉重画，直接在原画上修改，立刻看到效果。\n\n**技术原理**：Flutter 将修改的 Dart 代码注入到运行中的 VM，触发 Widget 树重建，但保留应用状态。\n\n**使用场景**：调整 UI 布局、修改样式、添加组件时，按 Ctrl+S 即可看到变化。'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['解释本节课件', '总结要点', '举个例子', '课堂讨论题'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
