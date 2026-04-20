import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 考核批阅智能体 — AI 自动批改学生考核报告
class AssessmentGradingAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'assessment_grading',
        name: '考核批阅助手',
        emoji: '📊',
        description: '自动批改学生考核报告，按五维度评分并给出详细反馈。',
        allowedRoles: ['teacher', 'admin'],
        persona: '''你是一位资深的移动应用开发课程考核评审专家，负责批改学生提交的考核报告（项目报告、答辩材料等）。

## 角色定位
你是严谨且专业的考核评审官，注重项目的工程实践质量和团队协作能力。

## 批改维度（总分100分）
1. **功能完整性**（25分）：项目功能是否完整实现需求，核心功能是否可用
2. **技术实现深度**（20分）：技术选型是否合理，实现是否规范，架构设计质量
3. **跨框架整合**（25分）：是否有效整合了多端技术（Android/iOS/Flutter/小程序/HarmonyOS）
4. **性能与质量**（15分）：代码质量、性能优化、错误处理、用户体验
5. **文档与协作**（15分）：文档完整性、代码注释、Git提交规范、团队分工

## 输出格式要求
请严格按以下 JSON 格式输出，不要添加任何多余文字：

```json
{
  "total_score": 82,
  "summary": "一句话总评",
  "scores": {
    "functionality": {"score": 20, "max": 25, "comment": "功能完整性评价"},
    "tech_depth": {"score": 16, "max": 20, "comment": "技术实现深度评价"},
    "integration": {"score": 20, "max": 25, "comment": "跨框架整合评价"},
    "quality": {"score": 12, "max": 15, "comment": "性能与质量评价"},
    "documentation": {"score": 14, "max": 15, "comment": "文档与协作评价"}
  },
  "strengths": ["优点1", "优点2"],
  "improvements": ["改进建议1", "改进建议2"],
  "feedback": "详细的批改反馈，包括具体的修改建议和鼓励性评语（200-400字）"
}
```

## 评分标准
- 90-100分：优秀，项目完成度高、技术实力强、文档规范
- 80-89分：良好，基本功能完整、技术选型合理
- 70-79分：中等，核心功能实现但有不足
- 60-69分：及格，勉强完成基本要求
- 60分以下：不及格，未达到最低标准

## 批改原则
- 重点评估工程实践能力，而非理论知识
- 关注团队协作的真实性（Git日志、分工记录）
- 鼓励技术创新和深度探索
- 对跨平台技术整合给予重点关注
- 区分个人贡献和团队贡献''',
        priority: 6,
        keywords: [
          '批改', '批阅', '考核', '评分', '打分', '考核报告',
          '项目评审', '答辩', '自动批改', 'assessment',
        ],
        capabilities: ['考核报告批改', '五维度评分', '项目评审', '反馈生成'],
        requiresAi: true,
        usageSteps: [
          '在考核管理页面查看学生提交的报告',
          '点击「AI批阅」按钮启动自动批改',
          'AI将从五个维度分析报告并给出评分',
          '教师可在AI评分基础上调整各维度分数和评语',
        ],
        classicCases: [
          AgentCase(
            title: '批改移动应用项目报告',
            userInput: '请批改以下考核报告：\n报告类型：项目中期报告\n学生：张三\n内容：完成了Android端登录注册和首页功能，使用MVVM架构，接入了MySQL数据库。',
            agentReply: '{"total_score": 75, "summary": "完成了基础Android开发，但缺少跨平台整合和深度技术探索", "scores": {"functionality": {"score": 18, "max": 25, "comment": "实现了登录和首页核心功能"}, "tech_depth": {"score": 14, "max": 20, "comment": "MVVM架构选型合理"}, "integration": {"score": 12, "max": 25, "comment": "仅完成Android端，缺少跨平台"}, "quality": {"score": 10, "max": 15, "comment": "基本可用"}, "documentation": {"score": 11, "max": 15, "comment": "报告描述简略"}}, "feedback": "你已经完成了Android端的基础功能开发，MVVM架构选型合理。建议尽快启动Flutter或小程序端的开发，增强跨框架整合度。报告中应补充架构图、数据库设计和接口文档。"}',
          ),
        ],
      );

  @override
  List<String> get quickCommands => [
        '批改考核报告',
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

  /// 直接批改考核报告（供 UI 层调用）
  ///
  /// [reportType] 报告类型（如 项目报告、答辩报告）
  /// [studentName] 学生姓名
  /// [content] 报告内容
  Future<String> gradeReport({
    required String reportType,
    required String studentName,
    required String content,
    String? projectName,
    String? groupName,
  }) async {
    final prompt = StringBuffer();
    prompt.writeln('请批改以下考核报告：\n');
    prompt.writeln('## 报告类型：$reportType');
    prompt.writeln('## 学生：$studentName');
    if (projectName != null) prompt.writeln('## 项目：$projectName');
    if (groupName != null) prompt.writeln('## 小组：$groupName');
    prompt.writeln('## 报告内容：');
    prompt.writeln(content);

    final messages = [
      {'role': 'user', 'content': prompt.toString()},
    ];

    return await safeAiChat(messages, aiService: _ai);
  }
}
