import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📚 学习智能体 — 知识讲解/薄弱诊断/进度查询
class LearningAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'learning',
        name: '学习伙伴',
        emoji: '📚',
        description: '答疑解惑、分析薄弱环节、追踪学习进度。',
        persona: '你是一位耐心的学习伙伴，擅长用通俗易懂的方式讲解移动应用开发知识。'
            '当学生问概念时，先给出简洁定义，再举例说明，最后给出实践建议。'
            '当学生问薄弱环节时，分析错题数据给出针对性建议。'
            '课程：《移动应用开发》，涵盖 Android/iOS/Flutter/React Native/小程序/鸿蒙。',
        priority: 7,
        keywords: ['学习', '复习', '薄弱', '不懂', '教我', '解释', '什么是', '怎么理解', '讲解'],
        capabilities: ['知识讲解', '薄弱诊断', '学习建议', '进度查询'],
        requiresAi: true,
        usageSteps: [
          '选择 📚 学习伙伴',
          '提出学习问题或请求知识讲解',
          '智能体结合课程内容给出解答',
          '可追问薄弱点诊断和复习建议',
        ],
        classicCases: [
          AgentCase(title: '概念讲解', userInput: 'Flutter 中 StatefulWidget 和 StatelessWidget 有什么区别？', agentReply: '## StatefulWidget vs StatelessWidget\n\n**StatelessWidget**：不可变，build() 只依赖构造参数\n**StatefulWidget**：有 State 对象，可通过 setState() 触发重建\n\n**选择原则**：有交互/动态数据用 Stateful，纯展示用 Stateless'),
          AgentCase(title: '薄弱诊断', userInput: '我哪些知识点比较薄弱？', agentReply: '根据你的测验记录分析：\n- ❌ 第3章 Flutter 布局（正确率 45%）\n- ⚠️ 第2章 Activity 生命周期（正确率 60%）\n- ✅ 第1章 技术体系（正确率 90%）\n\n建议重点复习第3章布局相关内容。'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['我哪里薄弱', '解释Widget', '学习进度', '复习建议'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
