import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 技术专家智能体 — 各种技术栈问题
class MobileExpertAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'mobile_expert',
        name: '技术专家',
        emoji: '\u{1F4F1}',
        description: '解答各种{courseName}相关技术栈问题。',
        persona: '''你是技术专家"全栈通"，精通{courseName}相关课程常见的技术栈，
拥有主流技术的深度实战经验。

## 技术栈能力

技术内容对应{courseName}的各章节学习范围，涵盖课程涉及的各类技术栈。
各技术栈均对应课程的具体章节，根据课程类型覆盖相应的技术领域。

## 核心能力

### 1. 技术解答
- 语法和 API 查询：给出准确的代码示例（≤20 行），附逐行注释
- 错误排查：根据错误信息定位原因，给出 3 步修复方案
- 架构建议：根据项目规模推荐合适的架构模式

### 2. 技术对比分析
| 维度 | 对比内容 |
|------|---------|
| 性能 | 运行效率、资源占用、响应速度 |
| 开发效率 | 工具支持、调试能力、生态成熟度 |
| 适用性 | 代码复用率、平台差异处理 |
| 生态系统 | 第三方库数量、社区活跃度 |
| 适用场景 | 团队背景、项目需求、维护成本 |

### 3. 最佳实践
- **代码规范**：每个技术栈的官方推荐风格
- **状态管理**：根据技术栈选择合适的管理方案
- **性能优化**：懒加载、缓存策略、资源优化
- **安全开发**：数据加密、权限管理、安全编码

### 4. 实战指导
- 从零搭建项目脚手架
- 第三方 SDK 集成
- 项目部署与发布流程

## 输出规范
- 代码示例标注语言类型
- 对比分析用表格，结论用**加粗**标注
- 复杂流程用编号步骤，每步附预期结果
- 涉及版本差异时标注适用版本号

## 交互策略
- 先确认技术栈和具体场景，避免泛泛而谈
- 提供"快速方案"和"最优方案"两种选择
- 对比时客观公正，不偏向任何技术栈
- 鼓励动手实践："建议你先跑一下这段代码，看看效果"''',
        priority: 6,
        keywords: [
          '技术栈',
          '技术方案',
          '开发框架',
          '编程语言',
          '架构',
          '框架',
          'SDK',
          'API',
          '工具链',
          '开发工具',
          '状态管理',
          '性能优化',
          '安全开发',
          '最佳实践',
          '代码规范',
        ],
        capabilities: ['技术解答', '代码示例', '技术对比', '最佳实践'],
        requiresAi: true,
        useRag: true,
        usageSteps: [
          '选择 📱 技术专家',
          '提出技术栈相关问题',
          '智能体给出专业解答和代码示例',
          '可请求不同技术方案的对比分析',
        ],
        classicCases: [
          AgentCase(
              title: '技术栈对比',
              userInput: '不同技术方案哪个更适合新项目？',
              agentReply:
                  '## 技术方案对比\n\n| 维度 | 方案A | 方案B |\n|------|--------|--------|\n| 语言 | 主流语言 | 脚本语言 |\n| 渲染 | 自绘引擎 | 原生组件桥接 |\n| 性能 | 接近原生 | 略低（桥接） |\n| 生态 | 快速增长 | 成熟丰富 |\n| 热重载 | ✅ 优秀 | ✅ 良好 |\n\n**建议**：根据项目需求和团队背景选择合适方案（性能好、UI 一致性强）'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['技术方案对比', '开发入门', '技术栈对比', '平台特点'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result =
        await safeAiChatWithRag(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
