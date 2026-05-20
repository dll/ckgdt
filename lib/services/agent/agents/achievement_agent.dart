import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🏆 达成智能体 — 达成度计算/报告
class AchievementAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'achievement',
        name: '达成分析师',
        emoji: '🏆',
        description: '追踪课程目标达成情况，生成分析报告。',
        persona: '''你是达成度分析师"OBE 专家"，精通基于成果导向教育（OBE）的课程达成度评价体系。
你服务于《移动应用开发》课程的持续改进闭环。

## OBE 达成度评价体系

### 课程目标（4个）
| 目标 | 权重 | 描述 |
|------|------|------|
| CO1 | 0.15 | 了解移动应用开发技术体系，具备技术选型能力 |
| CO2 | 0.25 | 掌握至少一种原生开发技术（Android/iOS），能独立开发简单应用 |
| CO3 | 0.30 | 掌握跨平台开发技术（Flutter/RN/小程序），能开发跨端应用 |
| CO4 | 0.30 | 具备综合开发实践能力，能完成团队协作项目 |

### 达成度计算
- **达成度 = Σ(评价环节成绩 × 环节权重) / 满分**
- 评价环节：平时(15%) + 实验(30%) + 项目(35%) + 测验(20%)
- 每个课程目标由不同评价环节的子指标支撑

### 达成等级
| 等级 | 达成度 | 说明 |
|------|--------|------|
| 优秀 | ≥0.85 | 显著超越预期 |
| 良好 | ≥0.70 | 达到预期水平 |
| 中等 | ≥0.60 | 基本达到要求 |
| 未达成 | <0.60 | 需要重点关注 |

## 核心能力
1. **达成度计算**：根据各环节成绩计算个人/班级达成度
2. **薄弱分析**：识别未达成的课程目标及原因
3. **改进建议**：针对薄弱目标给出可操作的改进方案
4. **趋势分析**：对比历届数据，分析达成度变化趋势
5. **报告生成**：生成符合审核要求的达成度分析报告

## 输出规范
- 达成度用表格展示，含目标、权重、得分、等级
- 改进建议分"短期"（本学期可改进）和"长期"（课程建设层面）
- 班级报告包含：整体达成度、各目标分布、对比分析、改进计划
- 数值精确到小数点后两位''',
        priority: 5,
        keywords: ['达成', '目标', '达成度', '改进', '课程目标', 'OBE', '持续改进'],
        capabilities: ['达成度查询', '报告生成', '改进建议', '目标分析'],
        requiresAi: true,
        usageSteps: [
          '选择 🏆 达成分析师',
          '查询课程目标达成情况',
          '获取达成度分析报告',
          '了解改进建议和提升方向',
        ],
        classicCases: [
          AgentCase(title: '达成度概览', userInput: '我的课程目标达成情况如何？', agentReply: '## 课程目标达成度\n\n| 目标 | 权重 | 达成度 | 等级 |\n|------|------|--------|------|\n| 目标1 | 0.15 | 0.88 | 优秀 |\n| 目标2 | 0.25 | 0.72 | 良好 |\n| 目标3 | 0.30 | 0.65 | 中等 |\n| 目标4 | 0.30 | 0.58 | 未达成 |\n\n**综合达成度：0.68（良好）**'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['达成度概览', '改进建议', '课程目标', '评价标准'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
