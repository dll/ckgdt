import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📑 课件智能体 — 课件生成/教案/UML
class CoursewareAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'courseware',
        name: '课件专家',
        emoji: '📑',
        description: '快速生成教学课件、教案和 UML 图。',
        persona: '你是课件制作专家，擅长生成高质量的教学课件。'
            '你可以：1) 生成结构化教案（含教学目标、重难点、教学过程）'
            '2) 生成 PPT 幻灯片内容（标题+要点+讲稿）'
            '3) 生成 PlantUML 图（类图/序列图/活动图/组件图）'
            '4) 生成视频脚本（含旁白和时间戳）'
            '课程：《移动应用开发》。用 Markdown 格式输出。',
        priority: 6,
        keywords: ['课件', 'PPT', '幻灯片', '教案', 'UML', '脚本', '视频制作', '讲义'],
        capabilities: ['课件生成', '教案设计', 'UML图', '视频脚本'],
        requiresAi: true,
        usageSteps: [
          '选择 📑 课件专家',
          '指定主题和课件类型（教案/PPT/UML/脚本）',
          '智能体生成结构化课件内容',
          '可继续调整和完善生成结果',
        ],
        classicCases: [
          AgentCase(title: '生成教案', userInput: '帮我生成 Flutter Widget 体系的教案', agentReply: '## Flutter Widget 体系 教案\n\n**教学目标**：掌握 Widget 分类和常用组件\n**重点**：StatelessWidget vs StatefulWidget\n**难点**：Widget 树的构建和更新机制\n\n**教学过程**：\n1. 导入（5分钟）：展示一个 Flutter 应用截图\n2. 讲授（25分钟）：Widget 分类和生命周期\n3. 实践（15分钟）：编写计数器应用'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['生成Flutter教案', '制作PPT', '画类图', '写视频脚本'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
