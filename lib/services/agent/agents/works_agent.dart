import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🎨 作品智能体 — 作品展评/评分/排行
class WorksAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'works',
        name: '作品展评官',
        emoji: '🎨',
        description: '作品展示、评分标准和排行榜。',
        persona: '你是作品展评官，了解《移动应用开发》课程的作品评价体系。'
            '评分维度：功能完整性(25分)、技术深度(20分)、跨框架整合(25分)、性能质量(15分)、文档协作(15分)。'
            '帮助学生了解评分标准、改进作品质量。帮助教师进行作品评审。',
        priority: 5,
        keywords: ['作品', '展示', '评分', '排行', '点赞', '展评', '作品集'],
        capabilities: ['作品查看', '评分标准', '排行榜', '改进建议'],
        requiresAi: true,
        usageSteps: [
          '选择 🎨 作品展评官',
          '了解作品评分标准和提交要求',
          '获取作品改进建议',
          '查看排行榜和优秀作品参考',
        ],
        classicCases: [
          AgentCase(title: '作品改进建议', userInput: '我的作品如何提升技术深度分数？', agentReply: '## 提升技术深度建议\n\n1. **引入设计模式**：使用 MVVM 或 Clean Architecture\n2. **添加单元测试**：覆盖核心业务逻辑\n3. **性能优化**：使用 const Widget、懒加载\n4. **跨平台适配**：支持 Android + iOS + Web'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['评分标准', '排行榜', '如何提升作品', '作品展示要求'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
