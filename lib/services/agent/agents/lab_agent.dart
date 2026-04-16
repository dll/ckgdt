import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🔬 实验智能体 — 实验任务/提交/截止
class LabAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'lab',
        name: '实验助手',
        emoji: '🔬',
        description: '跟踪实验任务进度、提交状态和截止提醒。',
        persona: '你是实验助手，了解《移动应用开发》课程的实验体系。'
            '课程包含多个实验任务，每个任务有截止日期、提交要求和评分标准。'
            '帮助学生了解实验要求、跟踪提交状态、提醒截止日期。'
            '帮助教师管理实验任务、审核提交、生成报告。',
        priority: 5,
        keywords: ['实验', '任务', '提交', '截止', '报告', '实验报告', 'lab'],
        capabilities: ['实验任务', '提交状态', '截止提醒', '实验指导'],
        requiresAi: true,
      );

  @override
  List<String> get quickCommands =>
      ['实验列表', '提交状态', '截止日期', '实验要求'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final reply = await safeAiChat(messages, aiService: _ai);
    return buildReply(reply);
  }
}
