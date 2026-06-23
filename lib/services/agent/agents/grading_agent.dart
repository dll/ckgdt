import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../ai_service.dart';
import '../../auth_service.dart';
import '../../video_frame_extractor.dart';
import '../../../core/dev_paths.dart';
import '../../../data/local/ai_history_dao.dart';
import '../../../data/local/assessment_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/lab_task_dao.dart';
import '../../../data/local/works_dao.dart';
import '../agent_model.dart';
import '../base_agent.dart';
import '../orchestrator_agent.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

/// 批阅官 — 统一批阅智能体
///
/// 合并实验批阅、考核批阅、作品批阅三种能力于一身。
/// 用户只需说"批阅"即可自动匹配待批阅内容类型并调用对应工具链。
class GradingAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'grading',
        name: '批阅官',
        emoji: '📝',
        description: '自动批改实验报告、考核报告、学生作品，统一评分管理。',
        allowedRoles: ['teacher', 'admin'],
        persona: '''你是一位资深的课程全能批阅评审专家，负责批改学生提交的实验报告、考核报告和学生作品。

## 角色定位
你是严谨且鼓励性的批阅总官，能处理三种不同类型的批阅任务。每次开始前先确认批阅类型。

## 工作流程
1. **确定批阅类型**：询问用户需要批阅的是"实验报告"、"考核报告"还是"学生作品"
2. **获取待批阅列表**：调用对应工具获取未批阅的提交
3. **逐一批阅**：用 AI 分析内容，多维度评分
4. **保存结果**：调用对应保存工具写入数据库

---

### 类型一：实验报告批阅
**批改维度**（满分由任务设定，默认100分）
1. **实验完成度**（30%）：是否按要求完成了所有实验步骤和任务
2. **代码质量**（25%）：代码结构、命名规范、注释、可读性
3. **报告质量**（20%）：实验总结是否条理清晰、描述准确
4. **问题分析**（15%）：对遇到的问题是否有深入分析和解决思路
5. **创新性**（10%）：是否有超出基本要求的扩展和创新

### 类型二：考核报告批阅
**批改维度**（总分100分）
1. **功能完整性**（25分）：项目功能是否完整实现需求
2. **技术实现深度**（20分）：技术选型、架构设计、代码规范
3. **跨框架整合**（25分）：多端技术整合程度
4. **性能与质量**（15分）：代码质量、性能优化、用户体验
5. **文档与协作**（15分）：文档完整性、Git规范、团队分工

### 类型三：学生作品批阅 —— 两步评分法
**第一步：真实性校验（一票否决）**
- 视频画面展示的 App 是否与学生声称的项目一致？
- 不一致 → 判 0 分（relevance = "unrelated"）
- 部分匹配 → 总分 ≤ 60（relevance = "partial"）
- 一致 → 正常评分（relevance = "related"）

**第二步：五维度评分**
1. **功能完整性**（25分）：App 功能完整度、交互流畅度
2. **技术实现深度**（20分）：技术栈选型、架构设计
3. **跨框架整合**（20分）：多端技术整合
4. **性能与质量**（20分）：UI 美观度、响应速度
5. **文档与协作**（15分）：README、注释、演示视频

## 输出格式要求
根据不同批阅类型，输出对应的 JSON 格式：

**实验报告：**
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
  "feedback": "详细的批改反馈（200-400字）"
}
```

**考核报告：**
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
  "feedback": "详细的批改反馈（200-400字）"
}
```

**学生作品：**
```json
{
  "total_score": 85,
  "relevance": "related",
  "summary": "一句话总评",
  "scores": {
    "functionality": {"score": 22, "max": 25, "comment": "功能完整性评价"},
    "tech_depth": {"score": 16, "max": 20, "comment": "技术实现深度评价"},
    "integration": {"score": 17, "max": 20, "comment": "跨框架整合评价"},
    "quality": {"score": 17, "max": 20, "comment": "性能与质量评价"},
    "documentation": {"score": 13, "max": 15, "comment": "文档与协作评价"}
  },
  "strengths": ["优点1", "优点2"],
  "improvements": ["改进建议1", "改进建议2"],
  "feedback": "详细的批改反馈（200-400字）"
}
```

## 通用评分标准
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
- 注意区分低年级和高年级学生的要求差异
- 对跨平台技术整合给予重点关注
- 重视技术选型的合理性和代码质量''',
        priority: 6,
        keywords: [
          '批阅',
          '评分',
          '打分',
          '评语',
          '成绩',
          '作业',
          '实验报告',
          '考核',
          '作品',
          '提交',
          '审阅',
          '阅卷',
          '批改',
          '实验',
          '自动批改',
          '项目评审',
          '答辩',
          '作品评审',
          '视频作品',
          'grading',
          'lab',
          'assessment',
          'works',
        ],
        capabilities: [
          '实验批阅',
          '考核批阅',
          '作品批阅',
          '批量打评',
          '分数统计',
          '自动评分',
          '反馈生成',
          '多维度评估',
          '项目评审',
          '作品评审',
        ],
        requiresAi: true,
        useRag: false,
        tools: [
          // ── 实验批阅工具 ──
          AgentTool(
            name: 'get_submission_detail',
            description: '获取实验提交详情，参数：submissionId(int)',
            parameters: {'submissionId': '提交记录ID'},
            execute: (params) async {
              final db = await DatabaseHelper.instance.database;
              try {
                final id = params['submissionId'] as int;
                final list = await db.rawQuery('''
                  SELECT s.*, t.title as task_title, u.real_name as student_name
                  FROM lab_submissions s
                  LEFT JOIN lab_tasks t ON t.id = s.task_id
                  LEFT JOIN users u ON u.user_id = s.user_id
                  WHERE s.id = ?
                ''', [id]);
                if (list.isEmpty) return '未找到提交记录 (ID: $id)';
                final sub = list.first;
                final content = sub['content'] as String? ?? '';
                final contentPreview = content.length > 1000
                    ? '${content.substring(0, 1000)}…(后略)'
                    : (content.isEmpty ? '(空)' : content);
                return '提交详情：\n- 学生：${sub['student_name'] ?? sub['user_id']}\n- 实验任务：${sub['task_title'] ?? '-'}\n- 状态：${sub['status'] ?? '-'}\n- 提交时间：${sub['submit_time'] ?? '-'}\n- 当前分数：${sub['score'] ?? '未批阅'}\n- 当前评语：${sub['feedback'] ?? '-'}\n- 提交内容：$contentPreview';
              } catch (e) {
                return '查询提交详情失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'list_lab_tasks',
            description: '获取实验任务列表，参数：无',
            execute: (params) async {
              final dao = LabTaskDao();
              try {
                final tasks = await dao.getTasks();
                if (tasks.isEmpty) return '暂无实验任务';
                return tasks
                    .map((t) =>
                        '- [${t['id']}] ${t['title']} (${t['status'] ?? '未发布'})')
                    .join('\n');
              } catch (e) {
                return '查询实验任务失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'get_unmarked_submissions',
            description: '获取指定实验的待批阅提交列表，参数：taskId(int)',
            parameters: {'taskId': '实验任务ID'},
            execute: (params) async {
              final db = await DatabaseHelper.instance.database;
              try {
                final taskId = params['taskId'] as int;
                final list = await db.rawQuery('''
                  SELECT s.*, t.title as task_title, u.real_name as student_name
                  FROM lab_submissions s
                  LEFT JOIN lab_tasks t ON t.id = s.task_id
                  LEFT JOIN users u ON u.user_id = s.user_id
                  WHERE s.task_id = ? AND (s.score IS NULL OR s.score = 0)
                  ORDER BY s.submit_time DESC
                ''', [taskId]);
                if (list.isEmpty) return '该实验全部已批阅';
                return list.map((s) {
                  final c = s['content'] as String? ?? '';
                  final preview =
                      c.length > 200 ? '${c.substring(0, 200)}…' : c;
                  return '- 学生：${s['student_name'] ?? s['user_id']} (提交ID: ${s['id']})，提交时间：${s['submit_time'] ?? '-'}\n  内容预览：$preview';
                }).join('\n');
              } catch (e) {
                return '查询待批阅列表失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'save_score',
            description:
                '保存实验评分和评语，参数：submissionId(int), score(num), feedback(String)',
            parameters: {
              'submissionId': '提交记录ID',
              'score': '分数（0-100）',
              'feedback': '评语'
            },
            execute: (params) async {
              final dao = LabTaskDao();
              try {
                final id = params['submissionId'] as int;
                final score = (params['score'] as num).toInt();
                if (score < 0 || score > 100) {
                  return '评分失败：分数 $score 超出范围（0-100）';
                }
                final feedback = params['feedback'] as String? ?? '';
                await dao.gradeSubmission(id, score: score, feedback: feedback);
                return '评分成功：提交ID $id，分数 $score，评语 "$feedback"';
              } catch (e) {
                return '保存评分失败：$e';
              }
            },
          ),
          // ── 考核批阅工具 ──
          AgentTool(
            name: 'get_assessment_groups',
            description: '获取考核分组列表，参数：无',
            execute: (params) async {
              final dao = AssessmentDao();
              try {
                final groups = await dao.getGroups();
                if (groups.isEmpty) return '暂无考核分组';
                return groups.map((g) {
                  final members = g['member_names'] as String? ?? '';
                  final project = g['project_name'] as String? ?? '';
                  return '- [${g['id']}] ${g['name']} (项目：$project，成员：$members)';
                }).join('\n');
              } catch (e) {
                return '查询考核分组失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'get_project_scores',
            description: '获取指定分组的项目评分，参数：groupId(int)',
            parameters: {'groupId': '分组ID'},
            execute: (params) async {
              final db = await DatabaseHelper.instance.database;
              try {
                final groupId = params['groupId'] as int;
                final list = await db.rawQuery('''
                  SELECT s.*, p.name as project_name, g.name as group_name
                  FROM project_scores s
                  LEFT JOIN assessment_projects p ON s.project_id = p.id
                  LEFT JOIN assessment_groups g ON s.group_id = g.id
                  WHERE s.group_id = ?
                  ORDER BY s.total_score DESC
                ''', [groupId]);
                if (list.isEmpty) return '该分组暂无评分记录';
                return list.map((s) {
                  final total = s['total_score'] ?? '-';
                  final func = s['score_functionality'] ?? '-';
                  final tech = s['score_tech_depth'] ?? '-';
                  final integ = s['score_integration'] ?? '-';
                  final qual = s['score_quality'] ?? '-';
                  final doc = s['score_documentation'] ?? '-';
                  final comment = s['comment'] as String? ?? '';
                  return '- 项目：${s['project_name'] ?? '-'}，总分：$total（功能：$func，技术：$tech，整合：$integ，质量：$qual，文档：$doc）${comment.isNotEmpty ? '\n  评语：$comment' : ''}';
                }).join('\n');
              } catch (e) {
                return '查询项目评分失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'get_unmarked_projects',
            description: '查找尚未评分（无评分记录）的考核项目，参数：无',
            execute: (params) async {
              final db = await DatabaseHelper.instance.database;
              try {
                final list = await db.rawQuery('''
                  SELECT p.*, g.name as group_name
                  FROM assessment_projects p
                  LEFT JOIN assessment_groups g ON p.group_id = g.id
                  LEFT JOIN project_scores s ON s.project_id = p.id
                  WHERE s.id IS NULL
                  ORDER BY p.id ASC
                ''');
                if (list.isEmpty) return '所有项目均已评分';
                return list
                    .map((p) =>
                        '- [${p['id']}] ${p['name'] ?? '未命名'}（小组：${p['group_name'] ?? '-'}，状态：${p['status'] ?? '-'}）')
                    .join('\n');
              } catch (e) {
                return '查询待评分项目失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'save_project_score',
            description:
                '保存项目评分（各维度分数），参数：projectId(int), groupId(int), functionality(int), techDepth(int), integration(int), quality(int), documentation(int), scorerId(String), comment(String)',
            parameters: {
              'projectId': '项目ID',
              'groupId': '分组ID',
              'functionality': '功能完整性（0-25）',
              'techDepth': '技术实现深度（0-20）',
              'integration': '跨框架整合（0-25）',
              'quality': '性能与质量（0-15）',
              'documentation': '文档与协作（0-15）',
              'scorerId': '评分人ID',
              'comment': '评语',
            },
            execute: (params) async {
              final db = await DatabaseHelper.instance.database;
              try {
                final projectId = params['projectId'] as int;
                final groupId = params['groupId'] as int;
                final functionality = (params['functionality'] as num).toInt();
                final techDepth = (params['techDepth'] as num).toInt();
                final integration = (params['integration'] as num).toInt();
                final quality = (params['quality'] as num).toInt();
                final documentation = (params['documentation'] as num).toInt();
                // 范围校验
                if (functionality < 0 || functionality > 25) {
                  return '功能完整性（0-25）超出范围：$functionality';
                }
                if (techDepth < 0 || techDepth > 20) {
                  return '技术实现深度（0-20）超出范围：$techDepth';
                }
                if (integration < 0 || integration > 25) {
                  return '跨框架整合（0-25）超出范围：$integration';
                }
                if (quality < 0 || quality > 15) {
                  return '性能与质量（0-15）超出范围：$quality';
                }
                if (documentation < 0 || documentation > 15) {
                  return '文档与协作（0-15）超出范围：$documentation';
                }
                final scorerId = params['scorerId'] as String?;
                final comment = params['comment'] as String? ?? '';
                final total = functionality +
                    techDepth +
                    integration +
                    quality +
                    documentation;

                final existing = await db.query('project_scores',
                    where: 'project_id = ?', whereArgs: [projectId]);

                if (existing.isNotEmpty) {
                  await db.update(
                    'project_scores',
                    {
                      'score_functionality': functionality,
                      'score_tech_depth': techDepth,
                      'score_integration': integration,
                      'score_quality': quality,
                      'score_documentation': documentation,
                      'total_score': total,
                      'comment': comment,
                      'scorer_id': scorerId,
                      'scored_at': DateTime.now().toIso8601String(),
                    },
                    where: 'project_id = ?',
                    whereArgs: [projectId],
                  );
                  return '评分更新成功：项目ID $projectId，总分 $total';
                } else {
                  await db.insert('project_scores', {
                    'project_id': projectId,
                    'group_id': groupId,
                    'scorer_id': scorerId,
                    'score_functionality': functionality,
                    'score_tech_depth': techDepth,
                    'score_integration': integration,
                    'score_quality': quality,
                    'score_documentation': documentation,
                    'total_score': total,
                    'comment': comment,
                    'scored_at': DateTime.now().toIso8601String(),
                  });
                  return '评分保存成功：项目ID $projectId，总分 $total';
                }
              } catch (e) {
                return '保存项目评分失败：$e';
              }
            },
          ),
          // ── 作品批阅工具 ──
          AgentTool(
            name: 'get_work_detail',
            description: '获取作品详情，参数：workId(int)',
            parameters: {'workId': '作品ID'},
            execute: (params) async {
              final dao = WorksDao();
              try {
                final id = params['workId'] as int;
                final work = await dao.getWork(id);
                if (work == null) return '未找到作品 (ID: $id)';
                final desc = work['description'] as String? ?? '';
                final descDisplay = desc.length > 2000
                    ? '${desc.substring(0, 2000)}…(后略)'
                    : (desc.isEmpty ? '-' : desc);
                return '作品详情：\n- 标题：${work['title'] ?? '-'}\n- 学生：${work['student_name'] ?? work['user_id'] ?? '-'}\n- 技术栈：${work['tech_stack'] ?? '-'}\n- 状态：${work['status'] ?? '-'}\n- 描述：$descDisplay\n- 教师评分：${work['score'] ?? '未评分'}\n- 互评均分：${work['peer_avg'] ?? '-'}（${work['peer_count'] ?? 0}人）\n- 观看：${work['view_count'] ?? 0}，点赞：${work['like_count'] ?? 0}，评论：${work['comment_count'] ?? 0}';
              } catch (e) {
                return '查询作品详情失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'get_work_comments',
            description: '获取作品的评论列表，参数：workId(int)',
            parameters: {'workId': '作品ID'},
            execute: (params) async {
              final dao = WorksDao();
              try {
                final workId = params['workId'] as int;
                final comments = await dao.getComments(workId);
                if (comments.isEmpty) return '该作品暂无评论';
                return comments.map((c) {
                  final time = c['created_at'] as String? ?? '';
                  return '- ${c['user_name'] ?? c['user_id']}（$time）：${c['content']}';
                }).join('\n');
              } catch (e) {
                return '查询评论失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'get_pending_reviews',
            description: '获取待批阅（教师尚未评分）的作品列表，参数：无',
            execute: (params) async {
              final dao = WorksDao();
              try {
                final works = await dao.getWorks();
                final pending = works
                    .where((w) => w['score'] == null && w['status'] != '待提交')
                    .toList();
                if (pending.isEmpty) return '暂无待批阅的作品';
                return pending
                    .map((w) =>
                        '- [${w['id']}] ${w['title'] ?? '-'}（学生：${w['student_name'] ?? w['user_id'] ?? '-'}，状态：${w['status'] ?? '-'}）')
                    .join('\n');
              } catch (e) {
                return '查询待批阅作品失败：$e';
              }
            },
          ),
          AgentTool(
            name: 'save_work_score',
            description:
                '保存作品评分（五维度），参数：workId(int), scorerId(String), scorerName(String), functionality(int 0-25), techDepth(int 0-20), integration(int 0-20), quality(int 0-20), documentation(int 0-15), comment(String)',
            parameters: {
              'workId': '作品ID',
              'scorerId': '评分人ID',
              'scorerName': '评分人名称',
              'functionality': '功能完整性（0-25）',
              'techDepth': '技术实现深度（0-20）',
              'integration': '跨框架整合（0-20）',
              'quality': '性能与质量（0-20）',
              'documentation': '文档与协作（0-15）',
              'comment': '评语',
            },
            execute: (params) async {
              final dao = WorksDao();
              try {
                final workId = params['workId'] as int;
                final scorerId = params['scorerId'] as String?;
                final scorerName = params['scorerName'] as String?;
                final functionality = (params['functionality'] as num).toInt();
                final techDepth = (params['techDepth'] as num).toInt();
                final integration = (params['integration'] as num).toInt();
                final quality = (params['quality'] as num).toInt();
                final documentation = (params['documentation'] as num).toInt();
                // 范围校验
                if (functionality < 0 || functionality > 25) {
                  return '功能完整性（0-25）超出范围：$functionality';
                }
                if (techDepth < 0 || techDepth > 20) {
                  return '技术实现深度（0-20）超出范围：$techDepth';
                }
                if (integration < 0 || integration > 20) {
                  return '跨框架整合（0-20）超出范围：$integration';
                }
                if (quality < 0 || quality > 20) {
                  return '性能与质量（0-20）超出范围：$quality';
                }
                if (documentation < 0 || documentation > 15) {
                  return '文档与协作（0-15）超出范围：$documentation';
                }
                final comment = params['comment'] as String? ?? '';
                final total = functionality +
                    techDepth +
                    integration +
                    quality +
                    documentation;

                await dao.scoreWork(
                  workId: workId,
                  scorerId: scorerId,
                  scorerName: scorerName,
                  functionality: functionality,
                  techDepth: techDepth,
                  integration: integration,
                  quality: quality,
                  documentation: documentation,
                  comment: comment,
                );
                return '评分成功：作品ID $workId，总分 $total';
              } catch (e) {
                return '保存作品评分失败：$e';
              }
            },
          ),
        ],
        usageSteps: [
          '在实验提交管理/考核管理/作品展示页选择待批阅内容',
          '点击「AI批阅」按钮启动自动批改（或直接输入批阅指令）',
          'AI将根据内容类型自动匹配合适的评分维度和标准',
          '教师可在AI评分基础上调整分数和评语',
        ],
        classicCases: [
          const AgentCase(
            title: '批改 Flutter 实验报告',
            userInput:
                '请批改以下实验报告：\n实验名称：Flutter基础UI开发\n实验总结：完成了基本的ListView和GridView布局，实现了页面间导航。遇到了StatefulWidget状态更新的问题，通过setState解决。',
            agentReply:
                '{"score": 82, "summary": "较好地完成了基础UI实验，对状态管理有初步理解", "dimensions": {"completion": {"score": 26, "max": 30, "comment": "完成了ListView/GridView和导航"}, "code_quality": {"score": 20, "max": 25, "comment": "代码结构清晰"}, "report_quality": {"score": 17, "max": 20, "comment": "描述基本清晰"}, "problem_analysis": {"score": 12, "max": 15, "comment": "对setState有理解"}, "innovation": {"score": 7, "max": 10, "comment": "基本完成"}}, "feedback": "你的实验完成度不错，成功实现了ListView、GridView和页面导航三个核心组件。对setState的使用说明表明你理解了Flutter的状态管理基础。建议在报告中补充更多代码截图和效果演示，同时可以尝试探索Provider等更高级的状态管理方案。"}',
          ),
          const AgentCase(
            title: '批改移动应用考核报告',
            userInput:
                '请批改以下考核报告：\n报告类型：项目中期报告\n学生：张三\n内容：完成了Android端登录注册和首页功能，使用MVVM架构，接入了MySQL数据库。',
            agentReply:
                '{"total_score": 75, "summary": "完成了基础Android开发，但缺少跨平台整合和深度技术探索", "scores": {"functionality": {"score": 18, "max": 25, "comment": "实现了登录和首页核心功能"}, "tech_depth": {"score": 14, "max": 20, "comment": "MVVM架构选型合理"}, "integration": {"score": 12, "max": 25, "comment": "仅完成Android端，缺少跨平台"}, "quality": {"score": 10, "max": 15, "comment": "基本可用"}, "documentation": {"score": 11, "max": 15, "comment": "报告描述简略"}}, "feedback": "你已经完成了Android端的基础功能开发，MVVM架构选型合理。建议尽快启动Flutter或小程序端的开发，增强跨框架整合度。报告中应补充架构图、数据库设计和接口文档。"}',
          ),
          const AgentCase(
            title: '批改 Flutter 天气 App 学生作品',
            userInput:
                '请批改以下作品：\n标题：天气预报App\n技术栈：Flutter\n描述：使用Flutter开发的跨平台天气应用，集成高德天气API，支持城市搜索、7日预报、实时天气动画。',
            agentReply:
                '{"total_score": 86, "relevance": "related", "summary": "优秀的Flutter跨平台天气应用，功能完整且UI精美", "scores": {"functionality": {"score": 22, "max": 25, "comment": "核心功能完整，7日预报和动画是亮点"}, "tech_depth": {"score": 17, "max": 20, "comment": "Flutter架构合理，API集成规范"}, "integration": {"score": 17, "max": 20, "comment": "Flutter天然跨平台，但缺少原生端对比"}, "quality": {"score": 17, "max": 20, "comment": "天气动画提升了用户体验"}, "documentation": {"score": 13, "max": 15, "comment": "演示视频清晰完整"}}, "feedback": "这是一个完成度很高的Flutter天气应用。天气动画效果和7日预报功能是突出亮点。建议增加小程序或HarmonyOS版本的适配以提升跨框架整合评分。"}',
          ),
        ],
      );

  @override
  List<String> get quickCommands => [
        '批阅实验报告',
        '批阅考核报告',
        '批阅学生作品',
        '查看待批阅列表',
        '查看评分标准',
      ];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }

  @override
  double matchScore(String userMessage, AgentSession session) {
    double score = super.matchScore(userMessage, session);
    final text = userMessage.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    const broadKeywords = [
      '批改',
      '批阅',
      '评分',
      '打分',
      '评语',
      '审阅',
      '阅卷',
      '实验报告',
      '考核',
      '作品',
      '作业',
      '提交',
    ];
    for (final kw in broadKeywords) {
      if (text.contains(kw)) {
        score = (score + 0.1).clamp(0.0, 0.9);
      }
    }
    return score;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 1. 实验报告批阅
  // ═══════════════════════════════════════════════════════════════════════

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
    final guidance = await _loadGuidanceSnippet(const [
      'data/courseout/移动应用开发_模板/实验任务.md',
      'assets/graphs/06-学习图谱/实验学习指导图谱.md',
    ]);
    final prompt = StringBuffer();
    prompt.writeln('请批改以下实验报告：\n');
    prompt.writeln('## 实验任务：$taskTitle');
    if (guidance != null) {
      prompt.writeln('## 教师提供的实验指导/评分依据（节选）');
      prompt.writeln(guidance);
    }
    if (requirements != null && requirements.isNotEmpty) {
      prompt.writeln('## 实验要求：$requirements');
    }
    prompt.writeln('## 满分：$maxScore 分');
    prompt.writeln('## 学生提交内容：');
    prompt.writeln(content);
    prompt.writeln();
    prompt.writeln('## 硬规则（必须严格遵守）');
    prompt.writeln('1. 必须依据“实验任务、实验要求、学生提交正文”评分，不得凭课程印象打分');
    prompt.writeln('2. 若提交内容与任务要求无关或字数少于50字 → 分数必须低于60');
    prompt.writeln(
        '3. 若内容疑似 AI 生成（上下文过于统一、无个性化痕迹、格式过于标准）→ 在 JSON 中设置 "ai_flag": true 并扣 20 分');
    prompt.writeln('4. 输出必须引用任务要求或报告正文中的具体句子/事实作为评分依据，不可空泛');
    prompt.writeln('5. 分数允许任意整数（0-100），要求精确到个位评分，勿取整到离散值');
    prompt.writeln('6. feedback 必须面向学生，先肯定已完成内容，再说明不足，最后鼓励修改后再次提交');
    prompt.writeln('7. 若总分低于70分，必须满足：');
    prompt.writeln('   a) 在 "improvements" 中逐条列出具体不足（至少3条）');
    prompt.writeln('   b) 每条不足必须附带可操作的修复步骤（具体到：修改哪个代码文件、添加什么逻辑、调用什么API）');
    prompt.writeln('   c) "feedback" 字段必须包含至少200字的详细批改与修复指引');
    prompt.writeln();
    prompt.writeln('## 输出格式（只能输出 JSON，不要 Markdown 代码块）');
    prompt.writeln(
        '{"score":整数,"summary":"一句话总评","basis":["评分依据1","评分依据2"],"dimensions":{"completion":{"score":0,"max":30,"comment":"依据与扣分原因"},"code_quality":{"score":0,"max":25,"comment":"依据与扣分原因"},"report_quality":{"score":0,"max":20,"comment":"依据与扣分原因"},"problem_analysis":{"score":0,"max":15,"comment":"依据与扣分原因"},"innovation":{"score":0,"max":10,"comment":"依据与扣分原因"}},"strengths":["优点1","优点2"],"improvements":["不足及改进步骤1","不足及改进步骤2","不足及改进步骤3"],"feedback":"给学生看的完整反馈，说明为什么得这个分数，以及如何修改后再次提交","ai_flag":false}');

    final messages = [
      {'role': 'user', 'content': prompt.toString()},
    ];

    final result =
        await safeAiChatWithMeta(messages, aiService: _ai, temperature: 0.2);
    unawaited(AiHistoryDao().saveMessage(
      sessionId: 'direct_${DateTime.now().millisecondsSinceEpoch}',
      agentId: config.id,
      role: 'assistant',
      content: result.content,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      tokensUsed: result.totalTokens,
      provider: result.provider,
      model: result.model,
      userId: AuthService().currentUser?.userId,
    ));
    return result.content;
  }

  /// 加强版实验批阅：用 Orchestrator 串联 safety → grading → ethics。
  ///
  /// 返回值是主批阅结果（JSON 评分），ethics 步可在 [extraResult] 中获取。
  ///
  /// 触发场景：教师在 AI 批阅页打开"安全增强模式"开关，对疑似 AI 代写 / 涉敏内容
  /// 的提交做更严格审查。其它场景仍走 [gradeSubmission] 保持低成本。
  Future<
      ({
        String chainId,
        String gradingJson,
        String ethicsAdvice,
        String safetyNote
      })> gradeSubmissionWithOrchestrator({
    required String taskTitle,
    required String content,
    int maxScore = 100,
    String? requirements,
    AgentSession? session,
  }) async {
    final input = StringBuffer()
      ..writeln('请批改以下实验报告：')
      ..writeln('## 实验任务：$taskTitle');
    if (requirements != null && requirements.isNotEmpty) {
      input.writeln('## 实验要求：$requirements');
    }
    input
      ..writeln('## 满分：$maxScore 分')
      ..writeln('## 学生提交内容：')
      ..writeln(content);

    final orch = OrchestratorAgent();
    final session0 = session ?? AgentSession(activeAgentId: config.id);
    final result = await orch.runChain(
      userMessage: input.toString(),
      session: session0,
      agentChain: OrchestratorChains.labGrading,
    );

    const emptyOrchStep = OrchestratorStep(
        agentId: '', agentName: '', input: '', output: '', skipped: true);

    final safetyStep = result.steps.firstWhere(
      (s) => s.agentId == 'safety',
      orElse: () => emptyOrchStep,
    );
    final gradingStep = result.steps.firstWhere(
      (s) => s.agentId == 'lab_grading',
      orElse: () => emptyOrchStep,
    );
    final ethicsStep = result.steps.firstWhere(
      (s) => s.agentId == 'ethics',
      orElse: () => emptyOrchStep,
    );

    return (
      chainId: result.chainId,
      gradingJson: gradingStep.output ?? '',
      ethicsAdvice: ethicsStep.output ?? '',
      safetyNote: safetyStep.output ?? '',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. 考核报告批阅
  // ═══════════════════════════════════════════════════════════════════════

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
    final guidance = await _loadGuidanceSnippet([
      'data/考核/移动应用开发综合考核方案.md',
      _reportGuidePath(reportType),
      'data/考核/考核报告体系说明.md',
    ]);
    final prompt = StringBuffer();
    prompt.writeln('请批改以下考核报告：\n');
    prompt.writeln('## 报告类型：$reportType');
    if (guidance != null) {
      prompt.writeln('## 教师提供的考核指导/评分依据（节选）');
      prompt.writeln(guidance);
    }
    prompt.writeln('## 学生：$studentName');
    if (projectName != null) prompt.writeln('## 项目：$projectName');
    if (groupName != null) prompt.writeln('## 小组：$groupName');
    prompt.writeln('## 报告内容：');
    prompt.writeln(content);
    prompt.writeln();
    prompt.writeln('## 硬规则（必须严格遵守）');
    prompt.writeln('1. 必须依据“报告类型、项目/小组信息、报告正文、考核方案”评分，不得凭印象打分');
    prompt.writeln('2. 若报告内容与考核要求无关或字数少于80字 → 总分必须低于60');
    prompt.writeln(
        '3. 若内容疑似 AI 生成（上下文过于统一、无个性化痕迹、格式过于标准）→ 在 JSON 中设置 "ai_flag": true 并扣 20 分');
    prompt.writeln('4. 输出必须引用报告中的具体内容作为评分依据，不可空泛');
    prompt.writeln('5. 分数允许任意整数（0-100），要求精确到个位评分');
    prompt.writeln('6. feedback 必须面向学生，先肯定优点，再指出不足和修改路径，鼓励修改后再次提交');
    prompt.writeln('7. 若总分低于70分，必须满足：');
    prompt.writeln('   a) 在 "improvements" 中逐条列出具体不足（至少3条）');
    prompt.writeln('   b) 每条不足必须附带可操作的修复步骤（具体到：修改哪个文件、添加什么逻辑、参考什么接口）');
    prompt.writeln('   c) "feedback" 字段必须包含至少200字的详细批改与修复指引');
    prompt.writeln();
    prompt.writeln('## 输出格式（只能输出 JSON，不要 Markdown 代码块）');
    prompt.writeln(
        '{"total_score":整数,"summary":"一句话总评","basis":["评分依据1","评分依据2"],"scores":{"functionality":{"score":0,"max":25,"comment":"依据与扣分原因"},"tech_depth":{"score":0,"max":20,"comment":"依据与扣分原因"},"integration":{"score":0,"max":25,"comment":"依据与扣分原因"},"quality":{"score":0,"max":15,"comment":"依据与扣分原因"},"documentation":{"score":0,"max":15,"comment":"依据与扣分原因"}},"strengths":["优点1","优点2"],"improvements":["不足及改进步骤1","不足及改进步骤2","不足及改进步骤3"],"feedback":"给学生看的完整反馈，说明为什么得这个分数，以及如何修改后再次提交","ai_flag":false}');

    final messages = [
      {'role': 'user', 'content': prompt.toString()},
    ];

    final result =
        await safeAiChatWithMeta(messages, aiService: _ai, temperature: 0.2);
    unawaited(AiHistoryDao().saveMessage(
      sessionId: 'direct_${DateTime.now().millisecondsSinceEpoch}',
      agentId: config.id,
      role: 'assistant',
      content: result.content,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      tokensUsed: result.totalTokens,
      provider: result.provider,
      model: result.model,
      userId: AuthService().currentUser?.userId,
    ));
    return result.content;
  }

  /// 检查报告内容是否匹配小组技术栈和特色功能
  /// 返回 null = 通过，返回 String = 不通过原因
  Future<String?> checkReportTechStackAlignment({
    required String reportContent,
    required String groupTechStack,
    required String groupFeatures,
  }) async {
    if (groupTechStack.isEmpty && groupFeatures.isEmpty) return null;

    final prompt = StringBuffer();
    prompt.writeln('技术文档审核：检查报告是否覆盖小组技术栈和特色功能。\n');
    prompt.writeln('要求的技术栈：$groupTechStack');
    prompt.writeln('要求的特色功能：$groupFeatures\n');
    prompt.writeln('报告内容（前2000字）：');
    prompt.writeln(reportContent.length > 2000
        ? reportContent.substring(0, 2000)
        : reportContent);
    prompt.writeln('\n回答：若报告覆盖了技术栈和特色功能，只回复"PASS"。否则用中文说明缺少什么（50字内）。');

    try {
      final messages = [
        {'role': 'user', 'content': prompt.toString()}
      ];
      final result = await safeAiChatWithMeta(messages, aiService: _ai);
      unawaited(AiHistoryDao().saveMessage(
        sessionId: 'direct_${DateTime.now().millisecondsSinceEpoch}',
        agentId: config.id,
        role: 'assistant',
        content: result.content,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        tokensUsed: result.totalTokens,
        provider: result.provider,
        model: result.model,
      ));
      final clean = result.content.trim();
      if (_isAiUnavailableMessage(clean)) {
        return 'AI 服务暂时不可用，请检查网络连接和 AI 配置后重试';
      }
      if (clean.toUpperCase().startsWith('PASS') || clean.startsWith('通过')) {
        return null;
      }
      final reason = clean.length > 100 ? '${clean.substring(0, 100)}…' : clean;
      return reason;
    } catch (e, st) {
      stderr
          .writeln('[GradingAgent] checkReportTechStackAlignment 失败: $e\n$st');
      return 'AI 服务暂时不可用，请检查网络连接和 AI 配置后重试';
    }
  }

  bool _isAiUnavailableMessage(String text) {
    final lower = text.toLowerCase();
    return text.contains('AI 服务暂时不可用') ||
        text.contains('AI 请求失败') ||
        text.contains('API 配置') ||
        lower.contains('api key') ||
        lower.contains('400') ||
        lower.contains('401') ||
        lower.contains('429');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. 学生作品批阅
  // ═══════════════════════════════════════════════════════════════════════

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
    prompt.writeln();
    prompt.writeln('## 硬规则（必须严格遵守）');
    prompt.writeln('1. 必须依据作品描述、技术栈、演示视频/材料和考核标准评分，不得凭项目名称打分');
    prompt.writeln('2. 先做"真实性校验"：作品名称/描述/技术栈是否和实际内容一致？');
    prompt.writeln(
        '3. 明显对不上（描述的是A项目但实际是B/网上找的视频冒充/内容空洞无实质）→ total_score=0, relevance="unrelated", 所有维度score=0');
    prompt
        .writeln('4. 部分对不上（技术栈不符/功能未演示）→ total_score≤60, relevance="partial"');
    prompt.writeln('5. 若作品描述少于50字或内容空洞 → 分数必须低于60');
    prompt.writeln('6. 若疑似 AI 生成（无个性化痕迹、格式过于标准）→ 设置 "ai_flag": true 并扣 20 分');
    prompt.writeln('7. 必须引用评分维度（功能/技术/集成/质量/文档）作为评分依据');
    prompt.writeln('8. 分数允许任意整数（0-100）');
    prompt.writeln('9. feedback 必须面向学生，明确优点、不足、改进步骤，并鼓励修改后再次提交');
    prompt.writeln('10. 若总分低于70分，必须满足：');
    prompt.writeln('   a) 在 "improvements" 中逐条列出具体不足（至少3条）');
    prompt.writeln('   b) 每条不足必须附带可操作的修复步骤（具体到：修改哪个文件、添加什么布局/逻辑、优化什么性能点）');
    prompt.writeln('   c) "feedback" 字段必须包含至少200字的详细批改与修复指引');
    prompt.writeln();
    prompt.writeln('## 输出格式（只能输出 JSON，不要 Markdown 代码块）');
    prompt.writeln(
        '{"total_score":整数,"relevance":"related|partial|unrelated","summary":"一句话总评","basis":["评分依据1","评分依据2"],"scores":{"functionality":{"score":0,"max":25,"comment":"依据与扣分原因"},"tech_depth":{"score":0,"max":20,"comment":"依据与扣分原因"},"integration":{"score":0,"max":20,"comment":"依据与扣分原因"},"quality":{"score":0,"max":20,"comment":"依据与扣分原因"},"documentation":{"score":0,"max":15,"comment":"依据与扣分原因"}},"strengths":["优点1","优点2"],"improvements":["不足及改进步骤1","不足及改进步骤2","不足及改进步骤3"],"feedback":"给学生看的完整反馈，说明为什么得这个分数，以及如何修改后再次提交","ai_flag":false}');

    final messages = [
      {'role': 'user', 'content': prompt.toString()},
    ];

    final result =
        await safeAiChatWithMeta(messages, aiService: _ai, temperature: 0.2);
    unawaited(AiHistoryDao().saveMessage(
      sessionId: 'direct_${DateTime.now().millisecondsSinceEpoch}',
      agentId: config.id,
      role: 'assistant',
      content: result.content,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      tokensUsed: result.totalTokens,
      provider: result.provider,
      model: result.model,
      userId: AuthService().currentUser?.userId,
    ));
    return result.content;
  }

  /// 综合批阅降级路径：保留考核材料 + 视频信息 + 硬规则的 text-only 调用。
  ///
  /// 当 vision API 不可用时调用，不丢弃已加载的 [materialMd] 上下文，
  /// 并明确告知 AI 视频帧提取失败的事实（防幻觉）。
  Future<String> _gradeWorkWithContext({
    required String title,
    String? description,
    String? techStack,
    String? studentName,
    String? groupName,
    String? materialMd,
    bool hasFrames = false,
    int frameCount = 0,
  }) async {
    final buf = StringBuffer();
    buf.writeln('请按以下材料综合批阅学生作品（text-only 模式）：');
    buf.writeln();
    if (materialMd != null) {
      buf.writeln('## 考核标准（节选）');
      buf.writeln(materialMd);
      buf.writeln();
    }
    buf.writeln('## 学生作品信息');
    buf.writeln('- 名称：$title');
    if (studentName != null) buf.writeln('- 学生：$studentName');
    if (groupName != null) buf.writeln('- 小组：$groupName');
    if (techStack != null) buf.writeln('- 技术栈：$techStack');
    if (description != null && description.isNotEmpty) {
      buf.writeln('- 描述：');
      buf.writeln(description);
    }
    buf.writeln();
    buf.writeln('## 视频画面');
    if (hasFrames) {
      buf.writeln('（原有 $frameCount 张视频关键帧，但因视觉服务暂时不可用，无法分析画面）');
      buf.writeln('请结合文字材料评判，在反馈中注明"视频画面未成功分析"，不要虚构画面内容。');
    } else {
      buf.writeln('（无视频帧可用，请仅按文字材料评判，不要虚构画面内容）');
    }
    buf.writeln();
    buf.writeln('## 硬规则（必须严格遵守）');
    buf.writeln('1. 严格按 system prompt 的 5 维度 + JSON 输出格式，必须包含 relevance 字段');
    buf.writeln('2. 先做"真实性校验"：对比作品名称/描述/技术栈是否一致？');
    buf.writeln('3. 明显对不上 → total_score=0, relevance="unrelated"');
    buf.writeln('4. 若描述少于 50 字 → 总分必须低于 60');
    buf.writeln('5. 评语必须引用具体材料/描述作为依据，不可空泛');
    buf.writeln('6. 分数允许任意整数（0-100）');
    buf.writeln('7. feedback 必须面向学生，明确优点、不足、改进步骤，并鼓励修改后再次提交');
    buf.writeln('8. 若总分低于70分，必须满足：');
    buf.writeln('   a) improvements 至少3条具体不足');
    buf.writeln('   b) 每条附带可操作的修复步骤');
    buf.writeln('   c) feedback 至少200字详细批改与修复指引');
    buf.writeln();
    buf.writeln('## 输出格式（只能输出 JSON，不要 Markdown 代码块）');
    buf.writeln(
        '{"total_score":整数,"relevance":"related|partial|unrelated","summary":"一句话总评","basis":["评分依据1","评分依据2"],"scores":{"functionality":{"score":0,"max":25,"comment":"依据与扣分原因"},"tech_depth":{"score":0,"max":20,"comment":"依据与扣分原因"},"integration":{"score":0,"max":20,"comment":"依据与扣分原因"},"quality":{"score":0,"max":20,"comment":"依据与扣分原因"},"documentation":{"score":0,"max":15,"comment":"依据与扣分原因"}},"strengths":["优点1","优点2"],"improvements":["不足及改进步骤1","不足及改进步骤2","不足及改进步骤3"],"feedback":"给学生看的完整反馈，说明为什么得这个分数，以及如何修改后再次提交","ai_flag":false}');

    final result = await safeAiChatWithMeta(
      [
        {'role': 'user', 'content': buf.toString()}
      ],
      aiService: _ai,
      temperature: 0.3,
    );
    return result.content;
  }

  /// 综合批阅：考核材料 + 项目内容 + 视频帧。**这是真正读视频的版本**。
  ///
  /// 解决 "AI 没看视频" 的痼疾：
  /// 1. 加载 `data/考核/移动应用开发综合考核方案.md`（评价标准）
  /// 2. 用 ffmpeg 抽 [frameCount] 帧（默认 5）
  /// 3. 调 [AiService.chatWithVision]（zhipu:glm-4.6v）
  /// 4. 视频缺失/抽帧失败 → fallback 到 text-only，prompt 明确告知
  ///
  /// 返回 ({content, sourcesUsed}) — sourcesUsed 标识本次是否真用了视频。
  Future<
      ({
        String content,
        bool usedVideo,
        int frameCount,
        String? assessmentMaterial
      })> gradeWorkComprehensive({
    required String title,
    String? description,
    String? techStack,
    String? studentName,
    String? groupName,
    String? videoPath,
    String? videoUrl,
    int frameCount = 5,
  }) async {
    // 1. 加载考核材料（任意一份失败都 fallback 空）
    String? materialMd;
    try {
      materialMd = await rootBundle.loadString('data/考核/移动应用开发综合考核方案.md');
      // 太长截断（保留头尾）—— GLM-4V 上下文有限
      if (materialMd.length > 6000) {
        final head = materialMd.substring(0, 3500);
        final tail = materialMd.substring(materialMd.length - 2000);
        materialMd = '$head\n\n…（中段省略）…\n\n$tail';
      }
    } catch (e) {
      stderr.writeln('[GradingAgent] 考核材料加载失败：$e');
    }

    // 2. 抽视频帧（仅本地路径；远程 URL 暂不下载）
    var frames = <String>[];
    var resolvedVideoPath = videoPath;
    if (resolvedVideoPath == null && videoUrl != null && videoUrl.isNotEmpty) {
      if (videoUrl.startsWith('http')) {
        resolvedVideoPath = null;
      } else if (_looksAbsolutePath(videoUrl)) {
        resolvedVideoPath = videoUrl;
      } else {
        // 简单兜底：如果 videoUrl 看起来像本地相对路径，转成绝对路径试试
        resolvedVideoPath = '${DevPaths.projectRoot}/$videoUrl';
      }
    }
    if (resolvedVideoPath != null && File(resolvedVideoPath).existsSync()) {
      frames = await VideoFrameExtractor.extractKeyFrames(
        resolvedVideoPath,
        frameCount: frameCount,
      );
    }

    // 3. 拼综合 prompt（text 部分给视觉 / 文本路径都用）
    final buf = StringBuffer();
    buf.writeln('请按以下材料综合批阅学生作品：');
    buf.writeln();
    if (materialMd != null) {
      buf.writeln('## 考核标准（节选）');
      buf.writeln(materialMd);
      buf.writeln();
    }
    buf.writeln('## 学生作品信息');
    buf.writeln('- 名称：$title');
    if (studentName != null) buf.writeln('- 学生：$studentName');
    if (groupName != null) buf.writeln('- 小组：$groupName');
    if (techStack != null) buf.writeln('- 技术栈：$techStack');
    if (description != null && description.isNotEmpty) {
      buf.writeln('- 描述：');
      buf.writeln(description);
    }
    buf.writeln();
    if (frames.isNotEmpty) {
      buf.writeln('## 视频画面（${frames.length} 张关键帧 — 已附）');
      buf.writeln('请结合画面分析作品的实际运行效果、UI 美观度、功能展示流畅度。');
    } else {
      buf.writeln('## 视频画面');
      buf.writeln('（未提取到视频帧，请仅按文字材料评判，不要虚构画面内容）');
    }
    buf.writeln();
    buf.writeln('## 硬规则（必须严格遵守）');
    buf.writeln('1. 严格按 system prompt 的 5 维度 + JSON 输出格式，必须包含 relevance 字段');
    buf.writeln('2. 先做"真实性校验"：对比视频帧画面 vs 作品名称/描述/技术栈，是否一致？');
    buf.writeln(
        '3. 视频画面明显不是学生声称的项目（冒充/无关）→ total_score=0, relevance="unrelated"');
    buf.writeln('4. 若描述少于 50 字 → 总分必须低于 60');
    buf.writeln('5. 若画面与描述明显不符（如描述说有 AI 功能但画面只是空表单）→ 总分扣 15-25');
    buf.writeln('6. 评语必须引用具体内容（材料/描述/画面）作为依据，不可空泛');
    buf.writeln('7. 分数允许任意整数（0-100）');
    buf.writeln('8. feedback 必须面向学生，明确优点、不足、改进步骤，并鼓励修改后再次提交');
    buf.writeln('9. 若总分低于70分，必须满足：');
    buf.writeln('   a) 在 "improvements" 中逐条列出具体不足（至少3条）');
    buf.writeln('   b) 每条不足必须附带可操作的修复步骤（具体到：修改哪个文件、添加什么布局/逻辑、优化什么性能点）');
    buf.writeln('   c) "feedback" 字段必须包含至少200字的详细批改与修复指引');
    buf.writeln();
    buf.writeln('## 输出格式（只能输出 JSON，不要 Markdown 代码块）');
    buf.writeln(
        '{"total_score":整数,"relevance":"related|partial|unrelated","summary":"一句话总评","basis":["评分依据1","评分依据2"],"scores":{"functionality":{"score":0,"max":25,"comment":"依据与扣分原因"},"tech_depth":{"score":0,"max":20,"comment":"依据与扣分原因"},"integration":{"score":0,"max":20,"comment":"依据与扣分原因"},"quality":{"score":0,"max":20,"comment":"依据与扣分原因"},"documentation":{"score":0,"max":15,"comment":"依据与扣分原因"}},"strengths":["优点1","优点2"],"improvements":["不足及改进步骤1","不足及改进步骤2","不足及改进步骤3"],"feedback":"给学生看的完整反馈，说明为什么得这个分数，以及如何修改后再次提交","ai_flag":false}');

    // 4. 调用：有图走 vision，无图走 text
    final AiChatResult result;
    try {
      if (frames.isNotEmpty) {
        result = await _ai.chatWithVision(
          textPrompt: buf.toString(),
          imageBase64s: frames,
          systemPrompt: config.persona,
          temperature: 0.3,
        );
      } else {
        result = await _ai.chatWithVision(
          textPrompt: buf.toString(),
          imageBase64s: const [],
          systemPrompt: config.persona,
          temperature: 0.3,
        );
      }
    } catch (e) {
      // 视觉调用失败 → 降级到 text-only，但保留考核材料与硬规则上下文
      stderr.writeln('[GradingAgent] vision 失败 fallback to text: $e');
      final fallbackResult = await _gradeWorkWithContext(
        title: title,
        description: description,
        techStack: techStack,
        studentName: studentName,
        groupName: groupName,
        materialMd: materialMd,
        hasFrames: frames.isNotEmpty,
        frameCount: frames.length,
      );
      return (
        content: fallbackResult,
        usedVideo: false,
        frameCount: 0,
        assessmentMaterial: materialMd != null ? '已加载' : null,
      );
    }

    unawaited(AiHistoryDao().saveMessage(
      sessionId: 'comprehensive_${DateTime.now().millisecondsSinceEpoch}',
      agentId: config.id,
      role: 'assistant',
      content: result.content,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      tokensUsed: result.totalTokens,
      provider: result.provider,
      model: result.model,
      userId: AuthService().currentUser?.userId,
    ));

    return (
      content: result.content,
      usedVideo: frames.isNotEmpty,
      frameCount: frames.length,
      assessmentMaterial: materialMd != null ? '已加载' : null,
    );
  }

  bool _looksAbsolutePath(String path) {
    return path.startsWith('/') ||
        path.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  String _reportGuidePath(String reportType) {
    if (reportType.contains('第一周')) return 'data/考核/第一周报告-项目启动.md';
    if (reportType.contains('第二周')) return 'data/考核/第二周报告-核心开发.md';
    if (reportType.contains('第三周')) return 'data/考核/第三周报告-系统整合.md';
    if (reportType.contains('第四周')) return 'data/考核/第四周报告-测试交付.md';
    if (reportType.contains('答辩')) return 'data/考核/考核报告1-答辩报告.md';
    if (reportType.contains('个人')) return 'data/考核/考核报告2-个人报告.md';
    if (reportType.contains('小组')) return 'data/考核/考核报告3-小组报告.md';
    if (reportType.contains('项目')) return 'data/考核/考核报告4-项目报告.md';
    return 'data/考核/课程考核大作业.md';
  }

  Future<String?> _loadGuidanceSnippet(List<String> assetPaths,
      {int maxChars = 5000}) async {
    final buffer = StringBuffer();
    for (final path in assetPaths) {
      try {
        final text = await rootBundle.loadString(path);
        if (text.trim().isEmpty) continue;
        buffer
          ..writeln('### $path')
          ..writeln(text.trim())
          ..writeln();
      } catch (e) {
        swallowDebug(e, tag: 'grading_agent');
      }
      if (buffer.length >= maxChars) break;
    }
    if (buffer.isEmpty) return null;
    final text = buffer.toString();
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n…（后续评分依据已截断）';
  }
}
