import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📱 移动专家智能体 — 各种移动应用技术栈
class MobileExpertAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'mobile_expert',
        name: '移动专家',
        emoji: '\u{1F4F1}',
        description: '解答各种移动应用开发技术栈问题。',
        persona: '你是移动应用开发技术专家，精通《移动应用开发》课程涉及的所有技术栈。'
            '你的专业领域：'
            '1) Android 原生开发：Java/Kotlin、Activity/Fragment、Jetpack Compose'
            '2) iOS 原生开发：Swift/SwiftUI、UIKit、Xcode'
            '3) Flutter 跨平台：Dart 语言、Widget 体系、状态管理、插件开发'
            '4) React Native：JavaScript/TypeScript、JSX、原生桥接'
            '5) 微信小程序：WXML/WXSS、小程序 API、云开发'
            '6) HarmonyOS：ArkTS、ArkUI、分布式能力'
            '7) 跨平台对比：性能、生态、适用场景分析'
            '回答时注重实践，给出代码示例和最佳实践。'
            '对比不同技术栈时客观公正，分析各自优劣。',
        priority: 6,
        keywords: [
          'Android', 'iOS', 'Flutter', 'Dart', 'React Native',
          '小程序', 'HarmonyOS', '鸿蒙', 'Kotlin', 'Swift',
          '跨平台', '原生', '移动开发', '技术栈', 'Compose',
          'SwiftUI', 'ArkTS', 'Widget', '状态管理',
        ],
        capabilities: ['技术解答', '代码示例', '技术对比', '最佳实践'],
        requiresAi: true,
        usageSteps: [
          '选择 📱 移动专家',
          '提出移动开发技术问题',
          '智能体给出专业解答和代码示例',
          '可请求不同技术栈的对比分析',
        ],
        classicCases: [
          AgentCase(title: '技术栈对比', userInput: 'Flutter 和 React Native 哪个更适合新项目？', agentReply: '## Flutter vs React Native 对比\n\n| 维度 | Flutter | React Native |\n|------|---------|---------------|\n| 语言 | Dart | JavaScript/TS |\n| 渲染 | 自绘引擎 | 原生组件桥接 |\n| 性能 | 接近原生 | 略低（JS桥接） |\n| 生态 | 快速增长 | 成熟丰富 |\n| 热重载 | ✅ 优秀 | ✅ 良好 |\n\n**建议**：新项目优先 Flutter（性能好、UI 一致性强）'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['Flutter vs RN', 'Android入门', '技术栈对比', 'HarmonyOS特点'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReply(result.content, modelProvider: result.provider, modelName: result.model);
  }
}
