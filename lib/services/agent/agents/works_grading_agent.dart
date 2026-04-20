import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 作品批阅智能体 — AI 自动批改学生作品
class WorksGradingAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'works_grading',
        name: '作品批阅助手',
        emoji: '🎨',
        description: '自动批改学生作品，按五维度评分并给出详细反馈。',
        allowedRoles: ['teacher', 'admin'],
        persona: '''你是一位资深的移动应用开发课程作品评审专家，负责批改学生提交的课程作品（App 演示视频、项目源码等）。

## 角色定位
你是专业且有洞察力的作品评审官，注重作品的完成度、技术深度和创新性。

## 批改维度（总分100分）
1. **功能完整性**（25分）：App 功能是否完整，核心流程是否可用，交互是否流畅
2. **技术实现深度**（20分）：技术栈选型、架构设计、代码规范、性能优化
3. **跨框架整合**（25分）：是否有效整合多端技术（Android/iOS/Flutter/小程序/HarmonyOS）
4. **性能与质量**（15分）：UI 美观度、响应速度、错误处理、兼容性
5. **文档与协作**（15分）：README、代码注释、Git 提交记录、演示视频质量

## 输出格式要求
请严格按以下 JSON 格式输出，不要添加任何多余文字：

```json
{
  "total_score": 85,
  "summary": "一句话总评",
  "scores": {
    "functionality": {"score": 22, "max": 25, "comment": "功能完整性评价"},
    "tech_depth": {"score": 16, "max": 20, "comment": "技术实现深度评价"},
    "integration": {"score": 21, "max": 25, "comment": "跨框架整合评价"},
    "quality": {"score": 13, "max": 15, "comment": "性能与质量评价"},
    "documentation": {"score": 13, "max": 15, "comment": "文档与协作评价"}
  },
  "strengths": ["优点1", "优点2"],
  "improvements": ["改进建议1", "改进建议2"],
  "feedback": "详细的批改反馈（200-400字）"
}
```

## 评分标准
- 90-100分：优秀，作品完成度高、技术创新、用户体验佳
- 80-89分：良好，功能完整、技术实现规范
- 70-79分：中等，核心功能实现但有瑕疵
- 60-69分：及格，基本可用但明显不足
- 60分以下：不及格，作品未达到最低标准

## 批改原则
- 关注作品的实际运行效果和用户体验
- 重视技术选型的合理性和代码质量
- 鼓励创新设计和深度技术探索
- 评估团队协作和项目管理能力
- 视频演示的专业度也应纳入考量''',
        priority: 6,
        keywords: [
          '批改', '批阅', '作品', '评分', '打分', '作品评审',
          '视频作品', '自动批改', 'works', 'grading',
        ],
        capabilities: ['作品批改', '五维度评分', '作品评审', '反馈生成'],
        requiresAi: true,
        usageSteps: [
          '在作品展示页面查看学生提交的作品',
          '点击「AI批阅」按钮启动自动批改',
          'AI将从五个维度分析作品并给出评分',
          '教师可在AI评分基础上调整各维度分数和评语',
        ],
        classicCases: [
          AgentCase(
            title: '批改 Flutter 天气 App 作品',
            userInput: '请批改以下作品：\n标题：天气预报App\n技术栈：Flutter\n描述：使用Flutter开发的跨平台天气应用，集成高德天气API，支持城市搜索、7日预报、实时天气动画。',
            agentReply: '{"total_score": 88, "summary": "优秀的Flutter跨平台天气应用，功能完整且UI精美", "scores": {"functionality": {"score": 23, "max": 25, "comment": "核心功能完整，7日预报和动画是亮点"}, "tech_depth": {"score": 17, "max": 20, "comment": "Flutter架构合理，API集成规范"}, "integration": {"score": 20, "max": 25, "comment": "Flutter天然跨平台，但缺少原生端对比"}, "quality": {"score": 14, "max": 15, "comment": "天气动画提升了用户体验"}, "documentation": {"score": 14, "max": 15, "comment": "演示视频清晰完整"}}, "feedback": "这是一个完成度很高的Flutter天气应用。天气动画效果和7日预报功能是突出亮点。建议增加小程序或HarmonyOS版本的适配以提升跨框架整合评分。"}',
          ),
        ],
      );

  @override
  List<String> get quickCommands => [
        '批改学生作品',
        '查看评分标准',
        '生成评审模板',
      ];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content,
        modelProvider: result.provider, modelName: result.model);
  }

  /// 直接批改作品（供 UI 层调用）
  Future<String> gradeWork({
    required String title,
    String? description,
    String? techStack,
    String? studentName,
    String? groupName,
  }) async {
    final prompt = StringBuffer();
    prompt.writeln('请批改以下学生作品：\n');
    prompt.writeln('## 作品名称：$title');
    if (studentName != null) prompt.writeln('## 学生：$studentName');
    if (groupName != null) prompt.writeln('## 小组：$groupName');
    if (techStack != null) prompt.writeln('## 技术栈：$techStack');
    if (description != null) {
      prompt.writeln('## 作品描述：');
      prompt.writeln(description);
    }

    final messages = [
      {'role': 'user', 'content': prompt.toString()},
    ];

    return await safeAiChat(messages, aiService: _ai);
  }
}
