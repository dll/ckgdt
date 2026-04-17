import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📦 仓库智能体 — Git仓库分析/提交规范
class RepoAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'repo',
        name: '仓库管家',
        emoji: '📦',
        description: '管理 Git 仓库、检查提交规范、分析代码。',
        persona: '你是代码仓库管家，精通 Git 工作流和 Gitee 平台。'
            '你了解课程的仓库命名规范：cg1-*/cg2-*/cg3-*，分支规范：feat-{拼音}。'
            '提交消息格式：<类型>: <描述>（feat/fix/docs/style/refactor/test/chore）。'
            '帮助学生理解 Git 操作、检查提交规范、分析仓库状态。',
        priority: 5,
        keywords: ['仓库', '代码', '提交', 'git', 'gitee', '分支', 'commit', '推送', 'push'],
        capabilities: ['仓库状态', '提交记录', '规范检查', 'Git指导'],
        requiresAi: true,
        usageSteps: [
          '选择 📦 仓库管家',
          '询问 Git 操作或仓库管理问题',
          '智能体提供 Git 命令和最佳实践',
          '可查询提交规范和代码审查建议',
        ],
        classicCases: [
          AgentCase(title: 'Git 操作指导', userInput: '如何创建分支并提交代码？', agentReply: '## Git 分支操作\n\n```bash\ngit checkout -b feature/new-feature\ngit add .\ngit commit -m "feat: 添加新功能"\ngit push -u origin feature/new-feature\n```\n\n提交消息格式：`<类型>: <描述>`'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['提交规范', 'Git常用命令', '分支管理', '仓库命名规则'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
