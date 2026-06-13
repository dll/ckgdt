import '../../ai_service.dart';
import '../../../data/local/achievement_dao.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🏆 达成智能体 — 达成度计算/报告
class AchievementAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
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
        tools: [
          AgentTool(
            name: 'list_achievement_batches',
            description: '获取所有达成度评价批次列表（含批次名、学生数），分析前先查可用批次及其 id',
            parameters: {},
            execute: (params) async {
              final batches = await AchievementDao().getAllBatches();
              if (batches.isEmpty) return '暂无达成度批次，请教师先在"达成"页创建批次并录入成绩';
              return batches
                  .map((b) => '- id=${b['id']} 《${b['name'] ?? b['batch_name'] ?? '未命名'}》'
                      '（${b['student_count'] ?? 0} 名学生，状态：${b['status'] ?? '进行中'}）')
                  .join('\n');
            },
          ),
          AgentTool(
            name: 'get_class_achievement',
            description: '获取指定批次的班级各课程目标平均达成度（CO1-CO4 + 总评）',
            parameters: {'batch_id': '批次 id（数字，来自 list_achievement_batches）'},
            execute: (params) async {
              final id = int.tryParse('${params['batch_id']}');
              if (id == null) return '请提供有效的批次 id（先用 list_achievement_batches 查询）';
              final avg = await AchievementDao().calculateClassAverage(id);
              if (avg.isEmpty) return '批次 #$id 暂无成绩数据';
              final buf = StringBuffer('批次 #$id 班级平均达成度：\n');
              avg.forEach((k, v) {
                buf.writeln('- $k：${(v).toStringAsFixed(3)}');
              });
              return buf.toString();
            },
          ),
          AgentTool(
            name: 'get_improvement_suggestions',
            description: '获取指定批次基于真实成绩计算的持续改进建议（按课程目标列出薄弱项 + 未达标学生数 + 改进措施）',
            parameters: {'batch_id': '批次 id（数字）'},
            execute: (params) async {
              final id = int.tryParse('${params['batch_id']}');
              if (id == null) return '请提供有效的批次 id';
              final list = await AchievementDao().generateImprovementSuggestions(id);
              if (list.isEmpty) return '批次 #$id 暂无成绩，无法生成改进建议';
              final buf = StringBuffer();
              for (final s in list) {
                final ach = (s['achievement'] as num?)?.toDouble() ?? 0;
                buf.writeln('### ${s['objectiveName']}（达成度 ${ach.toStringAsFixed(3)}，'
                    '${s['level'] ?? ''}）');
                if (s['lowStudentCount'] != null) {
                  buf.writeln('未达标学生：${s['lowStudentCount']}/${s['totalStudents'] ?? '?'} 名');
                }
                final actions = (s['actions'] as List?)?.cast<String>() ?? [];
                for (final a in actions.take(4)) {
                  buf.writeln('- $a');
                }
                buf.writeln();
              }
              return buf.toString();
            },
          ),
        ],
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
    // 动态加载课程目标，注入 AI prompt（支持任意课程）
    String objectivesContext = '';
    try {
      final batches = await AchievementDao().getBatches();
      if (batches.isNotEmpty) {
        final courseName = batches.first['course_name']?.toString() ?? '';
        if (courseName.isNotEmpty) {
          final objectives = await AchievementDao().getCourseObjectives(courseName);
          if (objectives.isNotEmpty) {
            final buf = StringBuffer('当前课程：$courseName\n课程目标：\n');
            for (final o in objectives) {
              final idx = o['idx'] ?? '?';
              final weight = o['weight'] ?? 0;
              final desc = o['description'] ?? '';
              final indicator = o['indicator'] ?? '';
              buf.writeln('- 目标$idx（权重$weight，指标点$indicator）：$desc');
            }
            objectivesContext = buf.toString();
          }
        }
      }
    } catch (e) {
      // 加载失败时使用通用 prompt，不阻塞对话
    }

    final messages = buildAiMessages(userMessage, session);
    if (objectivesContext.isNotEmpty) {
      // 在系统消息中注入课程目标上下文
      messages.insert(1, {
        'role': 'system',
        'content': objectivesContext,
      });
    }
    final result = await safeAiChatWithTools(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
