import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🎓 课程生成智能体 — 综合各智能体能力，快速生成其它课程
class CourseGenAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'course_gen',
        name: '课程生成',
        emoji: '\u{1F393}',
        description: '依据现有课程模板，快速生成其它课程内容。',
        persona: '你是课程生成专家，能够依据《移动应用开发》课程的完整体系，'
            '快速、高质量地生成其它课程的教学内容。'
            '你了解完整的课程建设要素：'
            '1) 课程大纲：章节结构、教学目标、学时分配'
            '2) 知识图谱：概念节点、关系边、层级结构'
            '3) 教学课件：PPT 大纲、讲稿、教案'
            '4) 测验题库：选择题、判断题、简答题，按章节和难度分级'
            '5) 实验任务：实验目标、步骤、评分标准、截止时间'
            '6) 学习路径：前置知识、推荐顺序、预计学时'
            '7) 达成度评价：课程目标、权重、评价维度'
            '8) 作品评价：评分维度和标准'
            '生成流程：用户指定课程名称和基本信息 → 生成课程大纲 → '
            '逐步生成各模块内容。输出使用 Markdown 格式，结构清晰。',
        priority: 5,
        keywords: [
          '课程生成', '生成课程', '新课程', '课程模板', '课程大纲',
          '课程建设', '教学大纲', '培养方案', '课程设计',
          '其它课程', '其他课程', '创建课程',
        ],
        capabilities: ['课程大纲', '题库生成', '图谱生成', '实验设计'],
        requiresAi: true,
        usageSteps: [
          '选择 🎓 课程生成',
          '指定新课程名称和基本信息',
          '智能体生成课程大纲和教学内容',
          '逐步完善各模块（题库、实验、图谱等）',
        ],
        classicCases: [
          AgentCase(title: '生成新课程', userInput: '帮我生成一门《Web 前端开发》课程大纲', agentReply: '## 《Web 前端开发》课程大纲\n\n**学时**：48学时（理论32 + 实验16）\n\n| 章节 | 主题 | 学时 |\n|------|------|------|\n| 第1章 | Web 技术体系全景 | 4 |\n| 第2章 | HTML5 + CSS3 基础 | 8 |\n| 第3章 | JavaScript 核心 | 8 |\n| 第4章 | Vue.js 框架开发 | 8 |\n| 第5章 | React 框架开发 | 8 |\n| 第6章 | 综合项目实践 | 12 |'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['生成新课程', '课程大纲模板', '题库生成', '实验任务设计'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
