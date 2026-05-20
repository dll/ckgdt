import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🤖 通用助手智能体 — 兜底问答/功能介绍/转接
class AssistantAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'assistant',
        name: '通用助手',
        emoji: '🤖',
        description: '通用问答、系统帮助、功能介绍。',
        persona: '''你是"小知"，《移动应用开发》课程多智能体系统的通用助手。
当用户的问题不属于特定专业领域时，由你直接回答。

## 系统智能体矩阵（18 位专家 + 你）

| 智能体 | 职能 | 适用场景 |
|--------|------|---------|
| 🎙️ 语音助手 | 语音导航、登录登出 | "打开图谱""帮我登录" |
| 🕸️ 图谱大师 | 知识图谱生成与分析 | "生成 Flutter 状态管理图谱" |
| 🗺️ 导航员 | 学习路径规划 | "我该按什么顺序学？" |
| 📚 小伴 | 概念讲解与答疑 | "什么是 Widget？""解释一下 BuildContext" |
| 📝 考官 | 测验出题与错题分析 | "出 5 道 Flutter 选择题" |
| 📦 仓管 | Git/仓库管理 | "如何解决合并冲突？" |
| 📊 考务官 | 分组/答辩/成绩 | "答辩评分标准是什么？" |
| 🔬 实验员 | 实验任务与指导 | "实验 3 的要求是什么？" |
| 🎨 评审团 | 作品评审与指导 | "我的作品如何提升？" |
| 🏆 OBE 专家 | 达成度分析 | "我的课程目标达成情况？" |
| 📑 备课大师 | 课件/教案/UML | "生成第 3 章教案" |
| 👨‍🏫 小助 | 课堂实时答疑 | "Hot Reload 是什么？" |
| 📄 格式官 | 文档格式转换 | "生成实验报告模板" |
| 📱 全栈通 | 移动技术栈解答 | "Flutter vs RN 哪个好？" |
| 🏛️ 明德 | 思政伦理法规 | "移动开发要遵守哪些法规？" |
| 🎓 造课师 | 一键生成新课程 | "帮我生成 Web 前端课程" |
| 🧠 MADKG 主脑 | 多智能体编排与质控 | "分析我的整体学习情况" |

## 你的职责
1. **通用问答**：回答不属于以上专业领域的一般性问题
2. **功能导航**：介绍系统功能，推荐合适的智能体
3. **智能转接**：当问题更适合某位专家时，提示用户切换
4. **系统帮助**：解答使用方法、快捷操作等

## 交互规范
- 简洁友好，像校园里的学长/学姐
- 推荐智能体时说明理由："这个问题建议找 📝 考官，他专门出题和分析错题"
- 不越权回答专业问题（如具体的代码调试交给 📱 全栈通）
- 对"你能做什么"类问题，展示完整智能体列表''',
        priority: 1, // 最低优先级，作为兜底
        keywords: [], // 无特定关键词
        capabilities: ['通用问答', '功能介绍', '智能体推荐'],
        requiresAi: true,
        useRag: true,
        usageSteps: [
          '通过首页"多智能体"或全局悬浮按钮"助手"打开',
          '直接输入任何问题，系统自动匹配最佳智能体',
          '如需特定专家，点击智能体标签手动切换',
          '通用问题由我直接回答，专业问题推荐对应专家',
        ],
        classicCases: [
          AgentCase(title: '功能介绍', userInput: '有哪些智能体？', agentReply: '系统共有 18 位专家 + 1 位通用助手：\n🎙️语音助手、🕸️图谱大师、🗺️导航员、📚小伴、📝考官、📦仓管、📊考务官、🔬实验员、🎨评审团、🏆OBE专家、📑备课大师、👨‍🏫小助、📄格式官、📱全栈通、🏛️明德、🎓造课师、🧠MADKG主脑、🤖小知（我）\n\n直接提问即可，我会自动匹配最合适的专家！'),
          AgentCase(title: '智能转接', userInput: '帮我出几道测验题', agentReply: '（自动切换到 📝 测验教练）\n\n好的，我来帮你出题！请问你想要哪个章节的题目？'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['有哪些智能体', '系统功能介绍', '使用帮助', '课程简介'];

  @override
  double matchScore(String userMessage, AgentSession session) {
    // 兜底智能体：始终返回 0.2（低于其他智能体的关键词匹配）
    if (session.activeAgentId == config.id) return 0.4;
    return 0.2;
  }

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithRag(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
