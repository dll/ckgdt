import '../../ai_service.dart';
import '../../auth_service.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/wrong_answer_dao.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📝 测验智能体 — 出题/批改/错题分析
class QuizAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'quiz',
        name: '测验教练',
        emoji: '📝',
        description: '出题练习、批改答案、分析错题。',
        persona: '''你是测验教练"考官"，精通教育测量学和移动应用开发知识评估。
你服务于《移动应用开发》课程（6章：技术体系 → Android/iOS → Flutter/RN → 小程序 → HarmonyOS → 综合实践）。

## 核心能力
1. **命题出题**：根据章节、难度、知识点生成高质量选择题
2. **智能批改**：判断答案正误，给出详细解析
3. **错题分析**：从错题中提取知识盲区，生成诊断报告
4. **难度调控**：根据学生表现动态调整题目难度

## 命题规范
- 每道题包含：题干、4 个选项（A/B/C/D）、正确答案、详细解析
- 题干清晰无歧义，选项互斥且有区分度
- 干扰项（错误选项）应是常见误解，不能过于离谱
- 难度分三级：⭐基础（概念识记）、⭐⭐进阶（理解应用）、⭐⭐⭐综合（分析比较）
- 每次出 3-5 道题，覆盖不同知识点，避免重复考点

## 出题格式
```
**第N题** ⭐难度 [章节/知识点]
题干文字

A. 选项A
B. 选项B
C. 选项C
D. 选项D

**答案：X**
**解析**：详细解释为什么选 X，以及其他选项为什么不对。
```

## 错题分析格式
- 按知识点聚类错题，识别高频错误
- 区分错因：概念混淆 / 记忆不牢 / 理解偏差 / 粗心大意
- 给出针对性复习建议：需要重看哪一章哪个知识点
- 用统计图表展示正确率分布

## 交互策略
- 出题前确认：章节范围、题目数量、难度偏好
- 支持逐题出题模式（出一题答一题）和批量出题模式
- 答错后先给提示再给答案，引导学生思考
- 完成一组测验后给出总结评价

## Few-shot 示例

用户：帮我出3道第3章 Flutter 的题
助手：
**第1题** ⭐ [第3章/Widget基础]
Flutter 中，以下哪个 Widget 是可变状态的？

A. StatelessWidget
B. StatefulWidget
C. Container
D. Text

**答案：B**
**解析**：StatefulWidget 拥有 State 对象，可通过 setState() 触发 UI 重建。StatelessWidget 是不可变的。Container 和 Text 都继承自 StatelessWidget。''',
        priority: 7,
        keywords: ['测验', '出题', '做题', '答题', '错题', '考试', '练习', '题目'],
        capabilities: ['出题', '批改', '错题分析', '章节推荐'],
        requiresAi: true,
        useRag: true,
        tools: [
          AgentTool(
            name: 'get_my_wrong_answers',
            description: '获取当前登录学生的错题列表（题干/错误答案/正确答案/章节/错误次数），用于错题分析和复习建议',
            parameters: {},
            execute: (params) async {
              final userId = AuthService().currentUser?.userId;
              if (userId == null) return '未登录，无法获取错题';
              final rows = await WrongAnswerDao().getWrongAnswers(userId);
              if (rows.isEmpty) return '该学生暂无错题记录，表现不错！';
              final buf = StringBuffer('共 ${rows.length} 道错题：\n');
              for (final r in rows.take(20)) {
                final q = (r['question'] as String? ?? '').replaceAll('\n', ' ');
                final shortQ = q.length > 50 ? '${q.substring(0, 50)}…' : q;
                buf.writeln('- [第${r['chapter'] ?? '?'}章] $shortQ '
                    '(你答:${r['user_answer'] ?? '?'} / 正确:${r['correct_answer'] ?? '?'}'
                    ' / 错${r['times'] ?? 1}次)');
              }
              return buf.toString();
            },
          ),
          AgentTool(
            name: 'get_my_quiz_summary',
            description: '获取当前登录学生的测验总览统计（测验次数、累计正确率、平均分）',
            parameters: {},
            execute: (params) async {
              final userId = AuthService().currentUser?.userId;
              if (userId == null) return '未登录，无法获取测验统计';
              final s = await QuizDao().getQuizSummary(userId);
              if (s.isEmpty || (s['total_count'] as int? ?? 0) == 0) {
                return '该学生暂无测验记录';
              }
              final correct = (s['total_correct'] as num?)?.toInt() ?? 0;
              final total = (s['total_questions'] as num?)?.toInt() ?? 0;
              final rate = total > 0 ? (correct * 100 / total).toStringAsFixed(1) : '0';
              final avg = (s['avg_score'] as num?)?.toStringAsFixed(1) ?? '0';
              return '测验次数：${s['total_count']}，累计答对 $correct/$total（正确率 $rate%），平均分 $avg';
            },
          ),
          AgentTool(
            name: 'get_chapter_question_stats',
            description: '获取题库各章节题目数量分布，用于按章节出题前了解题库覆盖',
            parameters: {},
            execute: (params) async {
              final stats = await QuizDao().getChapterStats();
              if (stats.isEmpty) return '题库暂无题目';
              return stats
                  .map((s) => '- ${s['source']}：${s['count']} 题')
                  .join('\n');
            },
          ),
        ],
        usageSteps: [
          '选择 📝 测验教练',
          '指定章节或主题，如"第3章出5道题"',
          '智能体生成选择题并逐题展示',
          '答题后获得解析和错题分析',
        ],
        classicCases: [
          const AgentCase(title: '按章节出题', userInput: '帮我出5道第3章 Flutter 的选择题', agentReply: '## 第3章 Flutter 测验\n\n**第1题** Flutter 中用于构建 UI 的基本单元是？\nA. Activity  B. Widget  C. View  D. Component\n\n**答案：B**\nFlutter 中一切皆 Widget，它是构建 UI 的基本单元。'),
          const AgentCase(title: '错题分析', userInput: '分析我最近的错题', agentReply: '你最近的错题集中在：\n1. Widget 生命周期（错2次）\n2. 路由导航方式（错1次）\n\n建议复习 StatefulWidget 的 initState/dispose 生命周期。'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['出5道Flutter题', '分析我的错题', '第三章测验', '复习建议'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithTools(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
