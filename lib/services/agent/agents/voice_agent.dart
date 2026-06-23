import 'dart:convert';

import '../../../core/constants/inner_tab_registry.dart';
import '../../../core/init_logger.dart';
import '../../../core/text_utils.dart';
import '../../auth_service.dart';
import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🎙️ 语音智能体 — AI 驱动的自然语言导航 + 语音登录/退出
///
/// 覆盖完整用户旅程：
/// - **登录/退出**：语音报学号登录、退出登录、退出系统
/// - **主菜单导航**：切换底部 Tab（首页/图谱/学习/实验/考核/作品…）
/// - **子页面操作**：打开二级页面（测验/视频/错题/设置/收藏…）
/// - **返回操作**：返回上一页、回到首页
/// - **系统操作**：退出系统/关闭应用
class VoiceAgent extends BaseAgent {
  final AuthService _auth = AuthService();
  final AiService _aiService = AiService();

  // ── 支持的导航页面清单（供 AI prompt 引用） ──────────────────────────────
  //
  // 教师 6 Tab：首页 图谱 教学 评价 达成 归档 [+管理]
  // 学生 6 Tab：首页 图谱 学习 实验 考核 作品
  static const _navPages = <String, String>{
    '首页': 'home',
    '知识图谱': 'graph',
    '教学中心': 'learning', // 教师：教学中心（教学+课堂聚合）
    '学习中心': 'learning', // 学生：学习中心
    '评价中心': 'assessment', // 教师：评价中心（实验+考核+作品聚合）
    '实验任务': 'experiment', // 学生：实验
    '考核管理': 'assessment', // 学生：考核
    '作品展评': 'showcase', // 学生：作品
    '达成度': 'achievement', // 教师：达成
    '归档': 'archive', // 教师：归档
    '管理面板': 'admin', // 管理员：管理
  };

  /// 子页面导航清单（供 AI prompt 引用）
  static const _subPages = <String, String>{
    '测验/做题': 'quiz',
    '错题本': 'wrong_answers',
    '视频教程': 'video',
    '课程资料/文档': 'document',
    '课件工坊': 'courseware',
    '学习进度/成绩': 'progress',
    '学习计划': 'plan',
    '薄弱诊断': 'weakness',
    '设置': 'settings',
    'AI设置': 'ai_settings',
    '语音设置': 'voice_settings',
    '搜索': 'search',
    '收藏': 'favorites',
    '数据同步': 'sync',
    '通知/消息': 'notification',
    'Git仓库': 'repo',
    '帮助/手册': 'handbook',
    '实践': 'practice',
    '个人中心': 'student_center',
    '教师工作台': 'teacher_workspace',
    'AI技能': 'ai_skill',
    '反馈': 'feedback',
    '成长曲线': 'growth_curve',
  };

  /// 内层 Tab 清单 — 单一来源见 [kInnerTabRegistry]
  /// （core/constants/inner_tab_registry.dart）。
  ///
  /// AI 用来识别"打开评价的作品页面"这种"父页面+内层"指令，输出
  /// {intent:"inner_tab", page:"assessment", tab:"项目"}。
  ///
  /// 历史上这里曾手抄一份 `_innerTabs`，与各页 `innerTabLabels()` 双向漂移
  /// （archive 整段缺失）。现统一从注册表读取，页面挂载时 mixin 做运行时校验。

  /// 构建可用页面列表文本（嵌入 AI prompt）
  static String get _pageListForPrompt {
    final buf = StringBuffer();
    _navPages.forEach((label, keyword) {
      buf.writeln('- $label（keyword: $keyword）');
    });
    return buf.toString();
  }

  /// 构建子页面列表文本（嵌入 AI prompt）
  static String get _subPageListForPrompt {
    final buf = StringBuffer();
    _subPages.forEach((label, keyword) {
      buf.writeln('- $label（keyword: $keyword）');
    });
    return buf.toString();
  }

  /// 构建内层 Tab 清单文本（嵌入 AI prompt）
  static String get _innerTabListForPrompt {
    final buf = StringBuffer();
    kInnerTabRegistry.forEach((page, tabs) {
      final label = kInnerTabPageLabels[page] ?? page;
      buf.writeln('- $label (page=$page) 的内层 Tab: ${tabs.join(" / ")}');
    });
    return buf.toString();
  }

  @override
  AgentConfig get config => AgentConfig(
        id: 'voice',
        name: '语音助手',
        emoji: '🎙️',
        description: '智能语音交互，自然语言导航、登录退出、多轮对话。',
        persona: '''你是"小知"，CKGDT 课程知识图谱与数字孪生平台的语音导航助手。
你的职责是理解用户的自然语言指令，执行导航、返回、退出等操作，并在用户提问时直接回答。

## 核心能力
1. **页面导航**：理解用户想去哪个页面，即使表述不精确。
2. **子页面操作**：理解用户想进入哪个子功能页面。
3. **内层 Tab 切换**：理解"打开评价的作品页面"这种"父页面+内层 Tab"指令。
4. **返回操作**：用户说"返回""回去""上一页"时执行返回。
5. **退出操作**：退出系统/退出登录。
6. **多轮澄清**：意图模糊时主动追问，如"你想打开哪个页面？"
7. **自由问答**：用户问问题时直接给出简短答案（≤60字适合朗读）。

## 底部 Tab 结构（角色不同 label 不同，keyword 相同）
- **教师/管理员**：首页 | 图谱 | 教学 | 评价 | 达成 | 归档 [+管理]
- **学生**：首页 | 图谱 | 学习 | 实验 | 考核 | 作品
- 教师的"教学"=学生的"学习" → keyword: learning
- 教师的"评价"聚合了学生的"实验+考核+作品" → keyword: assessment
- 用户说"课堂"/"课程"也映射到 keyword: learning
- 用户说"实验"/"考核"/"作品"时，如果是教师角色也填 keyword: assessment

## 可导航主页面（底部Tab）
$_pageListForPrompt

## 可导航子页面（二级页面）
$_subPageListForPrompt

## 可切换的内层 Tab（顶层页面内部的 TabController）
$_innerTabListForPrompt

## 输出格式
你必须返回 **严格 JSON**（不包含 markdown 代码块标记），格式如下：

主页面导航：
{"intent":"navigate","keyword":"learning","label":"教学","reply":"好的，正在打开教学。"}

子页面导航：
{"intent":"sub_page","keyword":"wrong_answers","label":"错题本","reply":"好的，正在打开错题本。"}

内层 Tab 切换（必须同时给 page 和 tab）：
{"intent":"inner_tab","page":"assessment","tab":"项目","reply":"好的，切换到考核的项目。"}

返回上一页：
{"intent":"back","reply":"好的，正在返回上一页。"}

回到首页：
{"intent":"navigate","keyword":"home","label":"首页","reply":"好的，回到首页。"}

退出系统：
{"intent":"exit_app","reply":"好的，正在退出系统。"}

退出登录：
{"intent":"logout","reply":"好的，正在退出登录。"}

需要澄清（仅当用户意图完全无法判断时才用，不要对明确的页面名称追问）：
{"intent":"clarify","reply":"你想打开哪个页面呢？"}

闲聊/问候/问答：
{"intent":"chat","reply":"<对用户问题的简短回答，或问候>"}

## 规则
- reply 必须简短（≤60 字），适合语音朗读，**不要包含 markdown 标记**。
- keyword 必须是上述"可导航主页面"清单里的 keyword 值之一。
- **重要**：用户说"打开教学""打开课堂""打开学习""打开课程"→ keyword: learning
- **重要**：用户说"打开评价""打开考核""打开实验""打开作品"→ keyword: assessment（教师的评价中心聚合这些）
- inner_tab 的 page 必须是 assessment/works/achievement/classroom/lab/learning 之一。
- 用户说"打开评价的作品页"→ inner_tab: page=assessment, tab=项目。
- 只返回 JSON，不要返回任何其他文字。
- 如果用户问知识类问题，用 chat 意图作答。
- "返回""回去""上一页""后退" → intent: back
- "退出系统""关闭应用""退出程序""关闭系统" → intent: exit_app
- "退出登录""注销""登出" → intent: logout''',
        priority: 9,
        requiresAi: true,
        keywords: [
          '登录',
          '退出',
          '打开',
          '去',
          '导航',
          '你好',
          '帮我',
          '跳转',
          '切换',
          '看看',
          '进入',
          '回到',
          '显示',
          '返回',
          '回去',
          '上一页',
          '后退',
          '关闭',
        ],
        capabilities: [
          '自然语言导航',
          '子页面操作',
          '返回导航',
          '语音登录',
          '退出登录',
          '退出系统',
          '多轮对话'
        ],
        usageSteps: [
          '点击全局悬浮按钮"助手"或首页"多智能体"',
          '选择 🎙️ 语音助手（或直接语音输入）',
          '语音登录：说"登录 206004"（支持中文数字）',
          '主菜单导航：说"打开图谱""去学习中心""切换到考核"',
          '子页面操作：说"打开错题本""去设置""看视频"',
          '返回操作：说"返回""回去""上一页""回到首页"',
          '退出系统：说"退出系统""关闭应用"',
          '退出登录：说"退出登录""注销"',
        ],
        classicCases: [
          const AgentCase(
            title: '语音登录',
            userInput: '登录 206004',
            agentReply: '登录成功！欢迎 刘老师。',
          ),
          const AgentCase(
            title: '主菜单导航',
            userInput: '我想看一下知识图谱',
            agentReply: '好的，正在打开知识图谱。',
          ),
          const AgentCase(
            title: '子页面操作',
            userInput: '帮我打开错题本',
            agentReply: '好的，正在打开错题本。',
          ),
          const AgentCase(
            title: '返回上一页',
            userInput: '返回',
            agentReply: '好的，正在返回上一页。',
          ),
          const AgentCase(
            title: '退出系统',
            userInput: '退出系统',
            agentReply: '好的，正在退出系统，再见！',
          ),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['登录', '退出登录', '打开图谱', '打开测验', '打开错题本', '返回', '退出系统'];

  /// 中文数字转阿拉伯数字
  static String chineseToDigits(String text) {
    const map = {
      '零': '0',
      '〇': '0',
      '一': '1',
      '壹': '1',
      '二': '2',
      '贰': '2',
      '两': '2',
      '三': '3',
      '叁': '3',
      '四': '4',
      '肆': '4',
      '五': '5',
      '伍': '5',
      '六': '6',
      '陆': '6',
      '七': '7',
      '柒': '7',
      '八': '8',
      '捌': '8',
      '九': '9',
      '玖': '9',
    };
    var result = text;
    for (final e in map.entries) {
      result = result.replaceAll(e.key, e.value);
    }
    return result;
  }

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final normalized = userMessage.toLowerCase().replaceAll(RegExp(r'\s+'), '');

    // ══════════════════════════════════════════════════════════════════════
    // 快速通道（不经过 AI，保证离线也能用）
    // ══════════════════════════════════════════════════════════════════════

    // ── 退出登录 ──
    if (_isLogout(normalized)) {
      return _handleLogout();
    }

    // ── 登录 ──
    if (_isLogin(normalized)) {
      return _handleLogin(userMessage);
    }

    // ── 返回上一页 ──
    if (_isBack(normalized)) {
      return _handleBack(normalized);
    }

    // ── 退出系统 ──
    if (_isExitApp(normalized)) {
      return _handleExitApp();
    }

    // ══════════════════════════════════════════════════════════════════════
    // AI 通道：自然语言理解（导航、问候、状态查询、多轮对话）
    // ══════════════════════════════════════════════════════════════════════

    // 构建含历史上下文的消息列表
    final messages = buildAiMessages(userMessage, session);

    // 注入当前登录状态到 system prompt
    final loginCtx = _auth.isLoggedIn
        ? '当前已登录用户：${_auth.currentUser?.realName ?? _auth.currentUser?.userId}（${_auth.currentUser?.role}）'
        : '当前未登录。';

    final systemPrompt = '${config.persona}\n\n## 当前状态\n$loginCtx';

    final result = await safeAiChatWithMeta(
      messages,
      systemPrompt: systemPrompt,
      aiService: _aiService,
    );

    // 解析 AI 返回的 JSON
    return _parseAiResponse(result);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 快速通道匹配
  // ═══════════════════════════════════════════════════════════════════════

  bool _isLogout(String normalized) {
    return (normalized.contains('退出') && normalized.contains('登录')) ||
        normalized.contains('注销') ||
        normalized.contains('登出');
  }

  bool _isLogin(String normalized) {
    return normalized.contains('登录') || normalized.contains('登陆');
  }

  bool _isBack(String normalized) {
    return normalized == '返回' ||
        normalized == '回去' ||
        normalized == '上一页' ||
        normalized == '后退' ||
        normalized.contains('返回上一页') ||
        normalized.contains('回到上一页');
  }

  bool _isExitApp(String normalized) {
    return (normalized.contains('退出') && normalized.contains('系统')) ||
        (normalized.contains('退出') && normalized.contains('程序')) ||
        (normalized.contains('关闭') && normalized.contains('应用')) ||
        (normalized.contains('关闭') && normalized.contains('系统')) ||
        (normalized.contains('关闭') && normalized.contains('程序'));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 快速通道处理
  // ═══════════════════════════════════════════════════════════════════════

  Future<AgentMessage> _handleLogout() async {
    if (_auth.isLoggedIn) {
      await _auth.logout();
      return buildReply(
        '已退出登录，再见！',
        action: const AgentAction(
          type: 'navigate_login',
          description: '跳转到登录页',
        ),
      );
    }
    return buildReply('你还没有登录哦。');
  }

  Future<AgentMessage> _handleLogin(String rawMessage) async {
    final digits = extractDigits(chineseToDigits(rawMessage));
    if (digits.isNotEmpty) {
      final password =
          digits.length >= 6 ? digits.substring(digits.length - 6) : digits;
      final ok = await _auth.login(digits, password);
      if (ok) {
        final name = _auth.currentUser?.realName ?? digits;
        return buildReply(
          '登录成功！欢迎 $name。',
          action: const AgentAction(
            type: 'navigate_home',
            description: '跳转到首页',
          ),
        );
      }
      return buildReply('学号 $digits 登录失败，请检查后重试。');
    }
    return buildReply('请告诉我你的学号，比如"登录 206004"。');
  }

  AgentMessage _handleBack(String normalized) {
    // "回到首页" 是特殊的返回操作
    if (normalized.contains('首页') || normalized.contains('主页')) {
      return buildReply(
        '好的，回到首页。',
        action: const AgentAction(
          type: 'pop_to_root',
          description: '返回到首页',
        ),
      );
    }

    return buildReply(
      '好的，正在返回上一页。',
      action: const AgentAction(
        type: 'go_back',
        description: '返回上一页',
      ),
    );
  }

  AgentMessage _handleExitApp() {
    return buildReply(
      '好的，正在退出系统，再见！',
      action: const AgentAction(
        type: 'exit_app',
        description: '退出应用程序',
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AI 响应解析
  // ═══════════════════════════════════════════════════════════════════════

  /// 解析 AI 返回的 JSON 意图
  AgentMessage _parseAiResponse(AiChatResult result) {
    try {
      // 尝试从响应中提取 JSON
      final raw = result.content.trim();
      InitLogger.log('voice',
          '_parseAiResponse rawLen=${raw.length} raw="${raw.length > 200 ? '${raw.substring(0, 200)}...' : raw}"');
      final jsonStr = _extractJson(raw);
      InitLogger.log('voice',
          '_parseAiResponse jsonStrLen=${jsonStr.length} jsonStr="${jsonStr.length > 200 ? '${jsonStr.substring(0, 200)}...' : jsonStr}"');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final intent = json['intent'] as String? ?? 'chat';
      final reply = json['reply'] as String? ?? '我没听清，请再说一遍。';
      InitLogger.log('voice',
          '_parseAiResponse intent=$intent keyword=${json['keyword']} label=${json['label']} page=${json['page']} tab=${json['tab']}');

      switch (intent) {
        case 'navigate':
          final keyword = json['keyword'] as String? ?? '';
          final label = json['label'] as String? ?? keyword;
          final chapter = json['chapter'];
          final params = <String, dynamic>{'keyword': keyword, 'label': label};
          if (chapter != null) params['chapter'] = chapter;
          return buildReply(
            reply,
            action: AgentAction(
              type: 'navigate_tab',
              params: params,
              description: '导航到$label',
            ),
            modelProvider: result.provider,
            modelName: result.model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.totalTokens,
          );

        case 'sub_page':
          final keyword = json['keyword'] as String? ?? '';
          final label = json['label'] as String? ?? keyword;
          return buildReply(
            reply,
            action: AgentAction(
              type: 'navigate_sub_page',
              params: {'keyword': keyword},
              description: '打开子页面$label',
            ),
            modelProvider: result.provider,
            modelName: result.model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.totalTokens,
          );

        case 'inner_tab':
          final page = json['page'] as String? ?? '';
          final tab = json['tab'] as String? ?? '';
          return buildReply(
            reply,
            action: AgentAction(
              type: 'inner_tab',
              params: {'page': page, 'tab': tab},
              description: '切到 $page 的 $tab',
            ),
            modelProvider: result.provider,
            modelName: result.model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.totalTokens,
          );

        case 'back':
          return buildReply(
            reply,
            action: const AgentAction(
              type: 'go_back',
              description: '返回上一页',
            ),
            modelProvider: result.provider,
            modelName: result.model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.totalTokens,
          );

        case 'exit_app':
          return buildReply(
            reply,
            action: const AgentAction(
              type: 'exit_app',
              description: '退出应用程序',
            ),
            modelProvider: result.provider,
            modelName: result.model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.totalTokens,
          );

        case 'logout':
          return buildReply(
            reply,
            action: const AgentAction(
              type: 'navigate_login',
              description: '退出登录',
            ),
            modelProvider: result.provider,
            modelName: result.model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.totalTokens,
          );

        case 'clarify':
        case 'chat':
        case 'status':
        default:
          return buildReply(
            reply,
            modelProvider: result.provider,
            modelName: result.model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.totalTokens,
          );
      }
    } catch (e, st) {
      // JSON 解析失败，直接返回 AI 原文
      InitLogger.error(
          'voice',
          'VoiceAgent JSON 解析失败 raw="${result.content.length > 100 ? '${result.content.substring(0, 100)}...' : result.content}" error=$e',
          st);
      return buildReply(
        result.content,
        modelProvider: result.provider,
        modelName: result.model,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTokens: result.totalTokens,
      );
    }
  }

  /// 从 AI 回复中提取 JSON（处理可能被 markdown 包裹的情况）
  String _extractJson(String text) {
    // 尝试去除 markdown 代码块
    final codeBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final match = codeBlock.firstMatch(text);
    if (match != null) return match.group(1)!.trim();

    // 尝试提取 {...}
    final braces = RegExp(r'\{[\s\S]*\}');
    final braceMatch = braces.firstMatch(text);
    if (braceMatch != null) return braceMatch.group(0)!;

    // 原文返回
    return text;
  }
}
