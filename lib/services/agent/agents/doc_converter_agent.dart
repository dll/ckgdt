import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📄 文档转换智能体 — 导入导出多种格式（MD/PDF/PPT）
class DocConverterAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'doc_converter',
        name: '文档转换',
        emoji: '\u{1F4C4}',
        description: '导入导出多种文档格式，如 Markdown、PDF、PPT 等。',
        persona: '你是文档转换专家，擅长处理各种文档格式的转换和生成。'
            '你的能力：1) 将内容转换为 Markdown 格式（标题、列表、表格、代码块）'
            '2) 生成 PDF 文档结构（章节、段落、图表描述）'
            '3) 生成 PPT 幻灯片大纲（标题+要点+讲稿备注）'
            '4) 从用户描述中提取结构化内容'
            '5) 格式化和美化文档内容'
            '6) 生成文档模板（实验报告、项目文档、技术方案）'
            '当用户需要转换格式时，先确认源格式和目标格式，然后生成对应内容。'
            '输出使用 Markdown 格式，方便后续处理。',
        priority: 5,
        keywords: [
          '文档', '转换', '导入', '导出', 'Markdown', 'MD',
          'PDF', 'PPT', '格式', '模板', '报告模板',
          '实验报告', '项目文档', '技术方案', '文档生成',
        ],
        capabilities: ['格式转换', '文档生成', '模板创建', '内容结构化'],
        requiresAi: true,
        usageSteps: [
          '选择 📄 文档转换',
          '描述需要转换的内容和目标格式',
          '智能体生成结构化文档内容',
          '复制结果到对应工具中使用',
        ],
        classicCases: [
          AgentCase(title: '生成实验报告模板', userInput: '生成一份 Flutter UI 实验的报告模板', agentReply: '# 实验报告：Flutter UI 开发\n\n## 一、实验目的\n- 掌握 Flutter 常用 Widget 的使用\n- 理解 Widget 树的构建方式\n\n## 二、实验环境\n- Flutter SDK 3.x\n- Android Studio / VS Code\n\n## 三、实验步骤\n1. 创建 Flutter 项目\n2. 实现列表页面\n3. 实现详情页面\n\n## 四、实验结果\n（截图）\n\n## 五、总结与思考'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['生成实验报告模板', '转为Markdown', '生成PPT大纲', '文档模板'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
