import '../../ai_service.dart';
import '../../auth_service.dart';
import '../../../data/local/lab_task_dao.dart';
import '../agent_model.dart';
import '../base_agent.dart';
import '../special_agent_tools.dart';

/// 🔬 实验智能体 — 实验任务/提交/截止
class LabAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'lab',
        name: '实验助手',
        emoji: '🔬',
        description: '跟踪实验任务进度、提交状态和截止提醒。',
        persona: '''你是实验助手"实验员"，负责 CKGDT 平台当前课程的实验任务管理和指导。

## 课程实验体系
本课程设置 {chapterCount} 次实验，对应 {courseName} 各章节，循序渐进。
共 {chapterCount} 次实验，对应 {courseName} 各章节。

## 实验要求规范
- **提交物**：源代码（Git 仓库链接）+ 实验报告（PDF/MD）+ 运行截图
- **截止时间**：实验发布后 2 周内提交
- **评分标准**：功能实现（40%）+ 代码质量（30%）+ 文档完整性（20%）+ 创新性（10%）
- **迟交政策**：每迟 1 天扣 10%，超过 5 天不接受提交

## 核心能力
1. **任务查询**：展示当前实验任务列表、截止日期、完成状态
2. **实验指导**：提供每个实验的步骤指引、环境配置帮助
3. **常见问题**：解答实验中遇到的环境配置、编译错误等问题
4. **报告模板**：提供标准实验报告模板和撰写建议
5. **提交检查**：验证提交物是否完整、格式是否正确

## 交互策略
- 学生询问时，先确认是哪个实验
- 给出步骤时附带预估时间
- 遇到错误时，先让学生描述错误信息，再给出解决方案
- 鼓励学生在实验基础上进行创新扩展（加分项）''',
        priority: 5,
        keywords: ['实验', '任务', '提交', '截止', '报告', '实验报告', 'lab'],
        capabilities: ['实验任务', '提交状态', '截止提醒', '实验指导'],
        requiresAi: true,
        tools: [
          AgentTool(
            name: 'list_lab_tasks',
            description: '获取已发布的实验任务列表（标题/章节/截止日期/难度/状态）',
            parameters: {},
            execute: (params) async {
              final tasks = await LabTaskDao().getTasks(status: 'active');
              if (tasks.isEmpty) return '当前暂无已发布的实验任务';
              return tasks
                  .map((t) => '- [${t['chapter'] ?? '?'}] 《${t['title']}》'
                      '（截止：${t['due_date'] ?? '未设'}，难度：${t['difficulty'] ?? '中等'}，'
                      '满分：${t['max_score'] ?? 100}）')
                  .join('\n');
            },
          ),
          AgentTool(
            name: 'get_my_lab_submissions',
            description: '获取当前登录学生的实验提交情况（已交哪些实验/得分/提交时间），用于回答"我交了哪些实验""我的成绩"',
            parameters: {},
            execute: (params) async {
              final userId = AuthService().currentUser?.userId;
              if (userId == null) return '未登录，无法获取提交记录';
              final subs = await LabTaskDao().getSubmissions(userId: userId);
              if (subs.isEmpty) return '该学生暂无实验提交记录';
              return subs.map((s) {
                final score = s['score'];
                final scoreStr =
                    score == null ? '待批阅' : '$score/${s['max_score'] ?? 100} 分';
                return '- 《${s['task_title'] ?? '实验#${s['task_id']}'}》'
                    '（提交于 ${s['submit_time'] ?? '?'}，$scoreStr）';
              }).join('\n');
            },
          ),
        ],
        usageSteps: [
          '选择 🔬 实验助手',
          '查询实验任务列表或截止日期',
          '了解实验要求和提交规范',
          '获取实验指导和常见问题解答',
        ],
        classicCases: [
          const AgentCase(
              title: '查看实验任务',
              userInput: '最近有哪些实验任务？',
              agentReply:
                  '## 当前实验任务\n\n1. **实验3：Flutter UI 开发** — 截止 4月20日\n   - 要求：实现一个包含列表和详情页的应用\n2. **实验4：状态管理** — 截止 5月5日\n   - 要求：使用 Provider 管理应用状态'),
        ],
      );

  @override
  List<String> get quickCommands => ['实验列表', '提交状态', '截止日期', '实验要求'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final tools = SpecialAgentTools.instance;
    if (tools.isLabTaskGenerationIntent(userMessage)) {
      try {
        final reply = await tools.generateLabTask(
          userRequest: userMessage,
        );
        return buildReply(
          reply,
          action: const AgentAction(
            type: 'navigate_sub_page',
            params: {'keyword': '实验管理'},
          ),
        );
      } catch (e) {
        return buildReply('实验任务生成失败：$e');
      }
    }

    final messages = buildAiMessages(userMessage, session);
    final result =
        await safeAiChatWithTools(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
