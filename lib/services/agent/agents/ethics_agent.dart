import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🏛️ 思政伦理智能体 — 思想政治、品德修养、法规伦理、安全教育
class EthicsAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'ethics',
        name: '思政伦理',
        emoji: '\u{1F3DB}\u{FE0F}',
        description: '思想政治教育、职业伦理、法规安全。',
        persona: '你是思政伦理导师，负责在《移动应用开发》课程中融入课程思政元素。'
            '你的职责：'
            '1) 思想政治：培养学生的爱国情怀、社会责任感，介绍中国科技自主创新成就'
            '（如鸿蒙系统、国产芯片、北斗导航等）'
            '2) 职业伦理：软件工程师的职业道德、代码质量责任、用户隐私保护'
            '3) 法律法规：《个人信息保护法》《数据安全法》《网络安全法》'
            '《计算机软件保护条例》等与移动开发相关的法规'
            '4) 安全教育：移动应用安全开发规范、数据加密、权限最小化原则'
            '5) 品德修养：团队协作精神、开源贡献意识、终身学习态度'
            '6) 伦理思考：AI 伦理、算法偏见、技术向善'
            '回答时结合移动开发实际案例，让思政教育自然融入专业学习。',
        priority: 5,
        keywords: [
          '思政', '伦理', '道德', '法规', '安全', '隐私',
          '法律', '责任', '爱国', '自主创新', '鸿蒙',
          '个人信息', '数据安全', '网络安全', '职业道德',
          '开源', 'AI伦理', '算法偏见', '品德', '修养',
        ],
        capabilities: ['思政教育', '法规解读', '伦理讨论', '安全规范'],
        requiresAi: true,
        usageSteps: [
          '选择 🏛️ 思政伦理',
          '提出思政、伦理、法规相关问题',
          '智能体结合移动开发实际案例解答',
          '了解相关法律法规和职业道德规范',
        ],
        classicCases: [
          AgentCase(title: '隐私保护法规', userInput: '移动应用开发需要遵守哪些隐私法规？', agentReply: '## 移动应用隐私法规\n\n**国内法规**：\n1. 《个人信息保护法》— 收集个人信息需明示同意\n2. 《数据安全法》— 数据分类分级保护\n3. 《网络安全法》— 实名制、数据本地化\n\n**开发实践**：\n- 权限最小化原则\n- 隐私政策弹窗\n- 数据加密存储\n- 用户数据可删除'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['移动开发法规', '隐私保护', '中国科技成就', 'AI伦理讨论'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
