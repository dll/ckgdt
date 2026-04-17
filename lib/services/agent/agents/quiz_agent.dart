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
        usageSteps: [
          '选择 📝 测验教练',
          '指定章节或主题，如"第3章出5道题"',
          '智能体生成选择题并逐题展示',
          '答题后获得解析和错题分析',
        ],
        classicCases: [
          AgentCase(title: '按章节出题', userInput: '帮我出5道第3章 Flutter 的选择题', agentReply: '## 第3章 Flutter 测验\n\n**第1题** Flutter 中用于构建 UI 的基本单元是？\nA. Activity  B. Widget  C. View  D. Component\n\n**答案：B**\nFlutter 中一切皆 Widget，它是构建 UI 的基本单元。'),
          AgentCase(title: '错题分析', userInput: '分析我最近的错题', agentReply: '你最近的错题集中在：\n1. Widget 生命周期（错2次）\n2. 路由导航方式（错1次）\n\n建议复习 StatefulWidget 的 initState/dispose 生命周期。'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['出5道Flutter题', '分析我的错题', '第三章测验', '复习建议'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
