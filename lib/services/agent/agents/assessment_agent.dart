import 'dart:convert';

import '../../ai_service.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/assessment_dao.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📊 考核智能体 — 分组/答辩/成绩
class AssessmentAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'assessment',
        name: '考核助理',
        emoji: '📊',
        description: '查询分组信息、答辩安排和成绩统计。',
        persona: '''你是考核助理"考务官"，精通《移动应用开发》课程的全流程考核管理。

## 考核体系
本课程采用过程性考核 + 终结性考核相结合的评价方式：

### 成绩构成
| 环节 | 占比 | 说明 |
|------|------|------|
| 平时表现 | 15% | 出勤、课堂互动、作业提交 |
| 实验任务 | 30% | 6 次实验，按时提交+质量评分 |
| 项目大作业 | 35% | 分组开发+答辩，含贡献度评价 |
| 期末测验 | 20% | 章节综合测验 |

### 项目答辩评分维度
- 功能完整性（25分）：需求覆盖率、核心功能运行正常
- 技术深度（20分）：架构设计、设计模式、性能优化
- 跨框架整合（25分）：至少使用 2 种技术栈（如 Flutter + 小程序）
- 性能质量（15分）：启动速度、流畅度、内存占用、崩溃率
- 文档协作（15分）：README、API 文档、Git 提交规范、团队协作

### 分组规则
- 每组 3-5 人，自由组队
- 每人必须有明确的分工和可量化的贡献
- 贡献度评价：Git 提交量 + 代码行数 + 功能模块 + 组内互评

## 核心能力
1. **考核流程指导**：解释每个考核环节的要求和时间节点
2. **分组管理**：查询分组信息、成员列表、分工情况
3. **答辩准备**：指导 PPT 制作、演示要点、常见提问
4. **成绩分析**：统计各环节成绩、排名分布
5. **申诉处理**：解释成绩复核流程

## 输出规范
- 评分标准用表格展示，量化可操作
- 时间节点用日历格式标注
- 答辩建议分"必做"和"加分"两类
- 对学生和教师提供差异化服务''',
        priority: 5,
        keywords: ['考核', '分组', '答辩', '成绩', '评分', '项目', '立项', '贡献'],
        capabilities: ['分组查询', '答辩安排', '成绩统计', '考核指导'],
        requiresAi: true,
        tools: [
          AgentTool(
            name: 'list_assessment_groups',
            description: '获取项目考核分组列表（组名/组长/项目名/成员）',
            parameters: {},
            execute: (params) async {
              final groups = await AssessmentDao().getGroups();
              if (groups.isEmpty) return '当前暂无考核分组';
              return groups.map((g) {
                var members = '';
                final raw = g['member_names'] as String?;
                if (raw != null && raw.isNotEmpty) {
                  try {
                    members = (jsonDecode(raw) as List).join('、');
                  } catch (e) {
                    // member_names 非合法 JSON（旧数据/手填），按原文展示
                    swallow(e, tag: 'AssessmentAgent.memberNames');
                    members = raw;
                  }
                }
                return '- 《${g['name']}》组长：${g['leader'] ?? '未定'}'
                    '，项目：${g['project_name'] ?? '未定'}'
                    '${members.isNotEmpty ? '，成员：$members' : ''}';
              }).join('\n');
            },
          ),
          AgentTool(
            name: 'get_group_stats',
            description: '获取分组总体统计（组数/总人数/平均每组人数）',
            parameters: {},
            execute: (params) async {
              final s = await AssessmentDao().getGroupStats();
              final avg = (s['avg_members'] as num?)?.toStringAsFixed(1) ?? '0';
              return '共 ${s['group_count'] ?? 0} 组，'
                  '${s['total_members'] ?? 0} 人，平均每组 $avg 人';
            },
          ),
          AgentTool(
            name: 'get_score_overview',
            description: '获取项目考核成绩总览（已评分数/平均分/最高最低分）',
            parameters: {},
            execute: (params) async {
              final s = await AssessmentDao().getScoreOverview();
              final count = (s['count'] as int?) ?? 0;
              if (count == 0) return '暂无项目考核成绩';
              final avg = (s['avg_score'] as num?)?.toStringAsFixed(1) ?? '0';
              return '已评分 $count 项，平均分 $avg，'
                  '最高 ${s['max_score']}，最低 ${s['min_score']}';
            },
          ),
        ],
        usageSteps: [
          '选择 📊 考核助理',
          '询问分组、答辩或成绩相关问题',
          '智能体提供考核信息和评分标准',
          '可查询答辩安排和成绩统计',
        ],
        classicCases: [
          const AgentCase(title: '查询评分标准', userInput: '项目答辩的评分标准是什么？', agentReply: '## 项目答辩评分标准\n\n| 维度 | 分值 |\n|------|------|\n| 功能完整性 | 25分 |\n| 技术深度 | 20分 |\n| 跨框架整合 | 25分 |\n| 性能质量 | 15分 |\n| 文档协作 | 15分 |'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['考核流程', '答辩准备', '成绩构成', '分组规则'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithTools(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
