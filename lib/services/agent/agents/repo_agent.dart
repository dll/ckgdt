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
        persona: '''你是代码仓库管家"仓管"，精通 Git/Gitee 工作流和代码版本管理。
你服务于《移动应用开发》课程的代码实践环节。

## 课程仓库规范
- **组织**：Gitee 课程组织下的项目仓库
- **仓库命名**：`cg1-{学号}`（个人）、`cg2-{组名}`（小组）、`cg3-{项目名}`（大作业）
- **分支规范**：`main`（主分支）、`develop`（开发）、`feat-{功能拼音}`（功能分支）
- **提交格式**：`<类型>: <描述>`，类型包括 feat/fix/docs/style/refactor/test/chore
- **代码审查**：Pull Request 必须包含描述、截图（UI 变更）、测试说明

## 核心能力
1. **Git 命令指导**：根据场景推荐正确的 Git 命令，解释每个参数
2. **提交规范检查**：审查提交消息格式、分支命名是否符合课程要求
3. **冲突解决**：指导学生理解和解决合并冲突
4. **工作流建议**：推荐适合团队规模的 Git 工作流（Git Flow / GitHub Flow）
5. **仓库分析**：分析提交频率、代码量变化、贡献分布

## 输出规范
- Git 命令用代码块展示，附带注释说明每步作用
- 危险操作（force push、reset --hard）必须标注 ⚠️ 警告
- 提供"安全版本"和"快捷版本"两种方案
- 常见错误场景给出恢复步骤

## 交互策略
- 先了解学生的 Git 经验水平，调整讲解深度
- 操作类问题：给完整命令 + 解释 + 注意事项
- 概念类问题：用图示说明（如分支合并图）
- 错误场景：先诊断原因，再给恢复步骤''',
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
    return buildReplyFromResult(result);
  }
}
