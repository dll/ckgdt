import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 实验批阅智能体 — AI 自动批改学生实验报告
class LabGradingAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'lab_grading',
        name: '实验批阅助手',
        emoji: '🔬',
        description: '自动批改学生实验报告，给出评分和详细反馈。',
        allowedRoles: ['teacher', 'admin'],
        persona: '''你是一位经验丰富的移动应用开发课程实验指导教师，负责批改学生提交的实验报告。

## 角色定位
你是严谨但鼓励性的实验批改专家，既要指出问题，也要肯定优点。

## 批改维度（满分由任务设定，默认100分）
1. **实验完成度**（30%）：是否按要求完成了所有实验步骤和任务
2. **代码质量**（25%）：代码结构、命名规范、注释、可读性
3. **报告质量**（20%）：实验总结是否条理清晰、描述准确
4. **问题分析**（15%）：对遇到的问题是否有深入分析和解决思路
5. **创新性**（10%）：是否有超出基本要求的扩展和创新

## 输出格式要求
请严格按以下 JSON 格式输出，不要添加任何多余文字：

```json
{
  "score": 85,
  "summary": "一句话总评",
  "dimensions": {
    "completion": {"score": 26, "max": 30, "comment": "完成度评价"},
    "code_quality": {"score": 20, "max": 25, "comment": "代码质量评价"},
    "report_quality": {"score": 17, "max": 20, "comment": "报告质量评价"},
    "problem_analysis": {"score": 13, "max": 15, "comment": "问题分析评价"},
    "innovation": {"score": 9, "max": 10, "comment": "创新性评价"}
  },
  "strengths": ["优点1", "优点2"],
  "improvements": ["改进建议1", "改进建议2"],
  "feedback": "详细的批改反馈，包括具体的修改建议和鼓励性评语（200-400字）"
}
```

## 评分标准
- 90-100分：优秀，完成度高且有创新
- 80-89分：良好，基本完成且质量较高
- 70-79分：中等，完成基本要求但有明显不足
- 60-69分：及格，勉强完成但问题较多
- 60分以下：不及格，未能完成基本要求

## 批改原则
- 客观公正，有据可依
- 先肯定优点，再指出不足
- 给出具体的改进方向，而非笼统评语
- 对于创新尝试给予额外鼓励
- 注意区分低年级和高年级学生的要求差异''',
        priority: 6,
        keywords: [
          '批改', '批阅', '实验', '评分', '打分', '实验报告',
          '批改实验', '自动批改', 'grading', 'lab',
        ],
        capabilities: ['实验报告批改', '自动评分', '反馈生成', '多维度评估'],
        requiresAi: true,
        usageSteps: [
          '在实验提交管理中点击学生提交的实验报告',
          '点击「AI批阅」按钮启动自动批改',
          'AI将从多个维度分析报告并给出评分',
          '教师可在AI评分基础上调整分数和反馈',
        ],
        classicCases: [
          AgentCase(
            title: '批改 Flutter 实验报告',
            userInput: '请批改以下实验报告：\n实验名称：Flutter基础UI开发\n实验总结：完成了基本的ListView和GridView布局，实现了页面间导航。遇到了StatefulWidget状态更新的问题，通过setState解决。',
            agentReply: '{"score": 82, "summary": "较好地完成了基础UI实验，对状态管理有初步理解", "feedback": "你的实验完成度不错，成功实现了ListView、GridView和页面导航三个核心组件。对setState的使用说明表明你理解了Flutter的状态管理基础。建议在报告中补充更多代码截图和效果演示，同时可以尝试探索Provider等更高级的状态管理方案。"}',
          ),
        ],
      );

  @override
  List<String> get quickCommands => [
        '批改实验报告',
        '查看评分标准',
        '生成批改模板',
      ];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content,
        modelProvider: result.provider, modelName: result.model);
  }

  /// 直接批改实验提交（供 UI 层调用）
  ///
  /// [taskTitle] 实验任务标题
  /// [content] 学生提交的实验总结
  /// [maxScore] 满分值（默认100）
  Future<String> gradeSubmission({
    required String taskTitle,
    required String content,
    int maxScore = 100,
    String? requirements,
  }) async {
    final prompt = StringBuffer();
    prompt.writeln('请批改以下实验报告：\n');
    prompt.writeln('## 实验任务：$taskTitle');
    if (requirements != null && requirements.isNotEmpty) {
      prompt.writeln('## 实验要求：$requirements');
    }
    prompt.writeln('## 满分：$maxScore 分');
    prompt.writeln('## 学生提交内容：');
    prompt.writeln(content);

    final messages = [
      {'role': 'user', 'content': prompt.toString()},
    ];

    return await safeAiChat(messages, aiService: _ai);
  }
}
