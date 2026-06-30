import '../../../data/local/case_dao.dart';
import '../../../core/utils/path_utils.dart';
import '../../ai_service.dart';
import '../../project_detector.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 教学案例演示智能体 — 组织案例启动、讲解和课堂演示脚本。
class CaseDemoAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'case_demo',
        name: '教学案例演示',
        emoji: '🧩',
        description: '整理教学案例的应用类型、启动方式、查看步骤和演示讲解词。',
        persona: '''你是“教学案例演示”智能体，负责把课程里的案例项目组织成清晰、可课堂执行的演示方案。

## 工作目标
- 帮教师说明案例是什么类型的应用：Windows EXE、APK、bat/cmd 启动包、Web 服务、Flutter/Java/Node 项目等。
- 给出启动应用的方法：点击平台按钮、执行脚本、安装 APK、打开浏览器地址等。
- 给出查看应用的步骤：从启动到进入首页，再到关键功能页。
- 组织“启动后的截图”讲解：说明截图应展示首页、核心功能、数据结果或移动端效果。
- 提炼应用特色内容：强调教学价值、技术栈、业务流程、可观察点和课堂提问点。

## 回复风格
- 面向课堂演示，直接给可照着讲的步骤。
- 不编造不存在的路径或截图；如果资料缺失，明确提示需要补充。
- 优先使用平台已登记的案例数据。
- 对不同应用形态给不同启动建议。

## 输出结构
1. 案例概览
2. 应用类型
3. 启动方法
4. 查看步骤
5. 截图讲解建议
6. 应用特色与课堂讲解词''',
        priority: 6,
        keywords: [
          '教学案例',
          '案例演示',
          '演示案例',
          '启动案例',
          '案例启动',
          '截图讲解',
          '应用特色',
          'exe',
          'apk',
          'bat',
        ],
        capabilities: ['案例概览', '启动步骤', '截图讲解', '演示讲稿'],
        requiresAi: true,
        tools: [
          AgentTool(
            name: 'list_teaching_cases',
            description: '列出当前课程已登记的教学案例及自动识别出的运行信息',
            parameters: {},
            execute: (params) async {
              final cases = await CaseDao().getCases();
              if (cases.isEmpty) return '当前课程还没有登记教学案例。';
              return cases.map(_caseSummary).join('\n\n');
            },
          ),
        ],
        usageSteps: [
          '选择 🧩 教学案例演示',
          '询问“有哪些案例可以演示”',
          '指定某个案例生成启动步骤和讲解词',
          '根据建议补充截图和特色说明',
        ],
        classicCases: [
          const AgentCase(
            title: '生成案例演示脚本',
            userInput: '帮我把教学案例整理成课堂演示流程',
            agentReply: '我会先读取当前课程案例列表，然后按“应用类型、启动方法、查看步骤、截图讲解、应用特色”生成演示脚本。',
          ),
        ],
      );

  @override
  List<String> get quickCommands => [
        '当前有哪些教学案例？',
        '生成案例演示流程',
        '帮我写截图讲解词',
        '如何演示 APK 案例？',
      ];

  @override
  double matchScore(String userMessage, AgentSession session) {
    final text = userMessage.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    var score = super.matchScore(userMessage, session);
    if (text.contains('案例') &&
        (text.contains('演示') ||
            text.contains('启动') ||
            text.contains('截图') ||
            text.contains('特色') ||
            text.contains('查看步骤'))) {
      score += 0.35;
    }
    return score.clamp(0.0, 1.0);
  }

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result =
        await safeAiChatWithTools(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}

String _caseSummary(Map<String, dynamic> c) {
  final name = (c['name'] ?? '').toString();
  final path = PathUtils.normalize(c['project_path']?.toString() ?? '');
  final isApk = path.toLowerCase().endsWith('.apk');
  ProjectInfo? info;
  if (path.isNotEmpty && PathUtils.pathExists(path)) {
    info = ProjectDetector.getProjectInfo(path);
  }
  final type = (c['demo_app_type'] ?? '').toString().trim().isNotEmpty
      ? c['demo_app_type'].toString().trim()
      : isApk
          ? 'Android APK 应用'
          : info?.label ?? (c['project_type'] ?? '教学演示应用').toString();
  final launch = (c['launch_method'] ?? '').toString().trim().isNotEmpty
      ? c['launch_method'].toString().trim()
      : info?.runCommand != null
          ? ([info!.runCommand!, ...info.runArgs]).join(' ')
          : isApk
              ? '通过 ADB 安装并启动 APK'
              : '由平台自动识别启动方式';
  final steps = (c['view_steps'] ?? '').toString().trim();
  final feature =
      (c['feature_intro'] ?? c['description'] ?? '').toString().trim();
  final screenshot =
      PathUtils.normalize(c['screenshot_path']?.toString() ?? '');

  return [
    '- 案例：$name',
    '  类型：$type',
    '  路径：${path.isEmpty ? '未填写' : path}',
    '  启动：$launch',
    if (info?.url != null) '  访问地址：${info!.url}',
    '  查看步骤：${steps.isEmpty ? '未维护，可根据应用类型生成' : steps.replaceAll(RegExp(r'[\r\n]+'), ' / ')}',
    '  截图：${screenshot.isEmpty ? '未维护' : screenshot}',
    '  特色：${feature.isEmpty ? '未维护，可结合应用功能提炼' : feature}',
  ].join('\n');
}
