import '../../ai_service.dart';
import '../../../data/local/works_dao.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🎨 作品智能体 — 作品展评/评分/排行
class WorksAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'works',
        name: '作品展评官',
        emoji: '🎨',
        description: '作品展示、评分标准和排行榜。',
        persona: '''你是作品展评官"评审团"，负责 CKGDT 平台当前课程的学生作品评审和指导。

## 评分体系（满分 100 分）

### 五大评分维度
| 维度 | 分值 | 评价要点 |
|------|------|---------|
| 功能完整性 | 25分 | 需求覆盖率、核心功能可用、边界情况处理 |
| 技术深度 | 20分 | 架构设计、设计模式、性能优化、安全考虑 |
| 跨框架整合 | 25分 | 至少 2 种技术栈、统一体验、数据互通 |
| 性能质量 | 15分 | 启动速度 <3s、流畅度 60fps、无崩溃、内存合理 |
| 文档协作 | 15分 | README、API 文档、Git 规范、团队分工清晰 |

### 等级标准
- S 级（90-100）：技术创新突出，可作为教学示范
- A 级（80-89）：功能完整，技术扎实
- B 级（70-79）：基本完成，有明显改进空间
- C 级（60-69）：勉强达标，核心功能缺失或质量差
- D 级（<60）：未达标

## 核心能力
1. **作品评审**：根据五维度给出结构化评分和改进建议
2. **技术建议**：针对具体技术短板给出提升方案
3. **优秀案例**：展示历届优秀作品作为参考
4. **答辩指导**：帮助准备作品展示 PPT 和演示流程

## 改进建议原则
- 具体可操作：不说"提升性能"，说"使用 const Widget 减少重建"
- 优先级排序：先修核心功能，再优化体验
- 投入产出比：优先推荐低成本高收益的改进
- 正面引导：先肯定亮点，再提改进点''',
        priority: 5,
        keywords: ['作品', '展示', '评分', '排行', '点赞', '展评', '作品集'],
        capabilities: ['作品查看', '评分标准', '排行榜', '改进建议'],
        requiresAi: true,
        tools: [
          AgentTool(
            name: 'get_works_overview',
            description: '获取当前课程学生作品概览（作品数、已评分数、平均分、浏览点赞评论）',
            parameters: {},
            execute: (params) async {
              final o = await WorksDao().getOverview();
              return '作品总数：${o['total_works'] ?? 0}，'
                  '已评分：${o['scored_count'] ?? 0}，'
                  '平均分：${((o['avg_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}，'
                  '最高分：${o['max_score'] ?? 0}，'
                  '浏览：${o['total_views'] ?? 0}，'
                  '点赞：${o['total_likes'] ?? 0}，'
                  '评论：${o['total_comments'] ?? 0}';
            },
          ),
          AgentTool(
            name: 'get_works_leaderboard',
            description: '获取当前课程作品排行榜前 10 名',
            parameters: {
              'dimension':
                  'comprehensive|score|views|likes|comments，默认 comprehensive'
            },
            execute: (params) async {
              final dimension =
                  params['dimension']?.toString() ?? 'comprehensive';
              final rows =
                  await WorksDao().getLeaderboard(dimension: dimension);
              if (rows.isEmpty) return '当前课程暂无已提交作品排行榜数据。';
              return rows.take(10).map((w) {
                final name =
                    (w['title'] ?? w['work_name'] ?? '未命名作品').toString();
                final student =
                    (w['student_name'] ?? w['user_id'] ?? '').toString();
                final score = (w['score'] as num?)?.toDouble();
                final scoreText =
                    score == null ? '未评分' : '${score.toStringAsFixed(1)}分';
                return '- $name（$student，$scoreText，浏览 ${w['view_count'] ?? 0}，点赞 ${w['like_count'] ?? 0}）';
              }).join('\n');
            },
          ),
        ],
        usageSteps: [
          '选择 🎨 作品展评官',
          '了解作品评分标准和提交要求',
          '获取作品改进建议',
          '查看排行榜和优秀作品参考',
        ],
        classicCases: [
          const AgentCase(
              title: '作品改进建议',
              userInput: '我的作品如何提升技术深度分数？',
              agentReply:
                  '## 提升技术深度建议\n\n1. **引入设计模式**：使用 MVVM 或 Clean Architecture\n2. **添加单元测试**：覆盖核心业务逻辑\n3. **性能优化**：使用 const Widget、懒加载\n4. **跨平台适配**：支持 Android + iOS + Web'),
        ],
      );

  @override
  List<String> get quickCommands => ['评分标准', '排行榜', '如何提升作品', '作品展示要求'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result =
        await safeAiChatWithTools(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
