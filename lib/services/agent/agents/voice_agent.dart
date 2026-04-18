import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../auth_service.dart';
import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🎙️ 语音智能体 — AI 驱动的自然语言导航 + 语音登录/退出
///
/// 登录/退出走本地快速通道（无需 AI）；
/// 其余所有交互由 AI 理解意图，返回结构化 JSON 指令。
class VoiceAgent extends BaseAgent {
  final AuthService _auth = AuthService();
  final AiService _aiService = AiService();

  // ── 支持的导航页面清单（供 AI prompt 引用） ──────────────────────────────
  static const _navPages = <String, String>{
    '首页': 'home',
    '知识图谱': 'graph',
    '章节测验': 'quiz',
    '视频教程': 'video',
    '学习中心': 'learning',
    '课堂管理': 'classroom',
    '实验任务': 'experiment',
    '考核管理': 'assessment',
    '作品展评': 'showcase',
    '达成度': 'achievement',
    '系统设置': 'settings',
    '管理面板': 'admin',
    'Git仓库': 'git',
    '通知中心': 'notification',
    '数据同步': 'sync',
    '三端互通': 'sync',
    '学习进度': 'progress',
    '错题本': 'wrong_answers',
    '我的收藏': 'favorites',
    '搜索': 'search',
    '实践': 'practice',
    '课件工坊': 'courseware',
  };

  /// 构建可用页面列表文本（嵌入 AI prompt）
  static String get _pageListForPrompt {
    final buf = StringBuffer();
    _navPages.forEach((label, keyword) {
      buf.writeln('- $label（keyword: $keyword）');
    });
    return buf.toString();
  }

  @override
  AgentConfig get config => AgentConfig(
        id: 'voice',
        name: '语音助手',
        emoji: '🎙️',
        description: '智能语音交互，自然语言导航、登录退出、多轮对话。',
        persona: '''你是"小知"，移动图谱教学系统的语音导航助手。
你的职责是理解用户的自然语言指令，执行导航、查询状态等操作。

## 核心能力
1. **页面导航**：理解用户想去哪个页面，即使表述不精确。
2. **多轮澄清**：意图模糊时主动追问，如"你想打开哪个页面？"
3. **上下文理解**：根据对话历史理解代词和省略，如上文提到测验，用户说"第三章的"即指第三章测验。
4. **状态感知**：知道用户当前是否已登录。

## 可导航页面
$_pageListForPrompt

## 输出格式
你必须返回 **严格 JSON**（不包含 markdown 代码块标记），格式如下：

导航意图：
{"intent":"navigate","keyword":"graph","label":"知识图谱","reply":"好的，正在打开知识图谱。"}

需要澄清：
{"intent":"clarify","reply":"你想打开哪个页面呢？比如知识图谱、章节测验、视频教程等。"}

闲聊/问候/帮助：
{"intent":"chat","reply":"你好！我是小知，可以帮你快速导航到任意页面。试试说'打开图谱'或'去测验'。"}

状态查询：
{"intent":"status","reply":"你想查询什么状态？"}

## 规则
- reply 字段必须简短（≤40字），适合语音朗读。
- keyword 必须是上述页面列表中的 keyword 值之一。
- 只返回 JSON，不要返回任何其他文字。
- 如果用户提到章节号（如"第三章"），在 JSON 中额外添加 "chapter": 3。''',
        priority: 9,
        requiresAi: true,
        keywords: [
          '登录', '退出', '打开', '去', '导航', '你好', '帮我',
          '跳转', '切换', '看看', '进入', '回到', '显示',
        ],
        capabilities: ['自然语言导航', '语音登录', '退出登录', '多轮对话', '上下文理解'],
        usageSteps: [
          '点击全局悬浮按钮"助手"或首页"多智能体"',
          '选择 🎙️ 语音助手（或直接语音输入）',
          '语音登录：说"登录 206004"（支持中文数字）',
          '自然语言导航：说"我想看知识图谱""帮我打开测验""去视频教程"等',
          '多轮对话：说"打开测验" → 系统追问 → 说"第三章"',
        ],
        classicCases: [
          const AgentCase(
            title: '语音登录',
            userInput: '登录 206004',
            agentReply: '登录成功！欢迎 刘老师。',
          ),
          const AgentCase(
            title: '自然语言导航',
            userInput: '我想看一下知识图谱',
            agentReply: '好的，正在打开知识图谱。',
          ),
          const AgentCase(
            title: '模糊导航',
            userInput: '帮我打开那个做题的页面',
            agentReply: '好的，正在打开章节测验。',
          ),
          const AgentCase(
            title: '上下文导航',
            userInput: '第三章的',
            agentReply: '好的，正在打开第三章的测验。',
          ),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['登录', '退出登录', '打开图谱', '打开测验', '去视频教程', '学习进度'];

  /// 中文数字转阿拉伯数字
  static String chineseToDigits(String text) {
    const map = {
      '零': '0', '〇': '0', '一': '1', '壹': '1', '二': '2', '贰': '2',
      '两': '2', '三': '3', '叁': '3', '四': '4', '肆': '4', '五': '5',
      '伍': '5', '六': '6', '陆': '6', '七': '7', '柒': '7', '八': '8',
      '捌': '8', '九': '9', '玖': '9',
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
    final normalized =
        userMessage.toLowerCase().replaceAll(RegExp(r'\s+'), '');

    // ══════════════════════════════════════════════════════════════════════
    // 快速通道：登录 / 退出（不经过 AI，保证离线也能用）
    // ══════════════════════════════════════════════════════════════════════

    // ── 退出登录 ──
    if (_isLogout(normalized)) {
      return _handleLogout();
    }

    // ── 登录 ──
    if (_isLogin(normalized)) {
      return _handleLogin(userMessage);
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
  // 内部方法
  // ═══════════════════════════════════════════════════════════════════════

  bool _isLogout(String normalized) {
    return (normalized.contains('退出') && normalized.contains('登录')) ||
        normalized.contains('注销') ||
        normalized.contains('登出');
  }

  bool _isLogin(String normalized) {
    return normalized.contains('登录') || normalized.contains('登陆');
  }

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
    final digits =
        chineseToDigits(rawMessage).replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isNotEmpty) {
      final password = digits.length >= 6
          ? digits.substring(digits.length - 6)
          : digits;
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

  /// 解析 AI 返回的 JSON 意图
  AgentMessage _parseAiResponse(AiChatResult result) {
    try {
      // 尝试从响应中提取 JSON
      final raw = result.content.trim();
      final jsonStr = _extractJson(raw);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final intent = json['intent'] as String? ?? 'chat';
      final reply = json['reply'] as String? ?? '我没听清，请再说一遍。';

      switch (intent) {
        case 'navigate':
          final keyword = json['keyword'] as String? ?? '';
          final label = json['label'] as String? ?? keyword;
          final chapter = json['chapter'];
          final params = <String, dynamic>{'keyword': keyword};
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
          );

        case 'clarify':
        case 'chat':
        case 'status':
        default:
          return buildReply(
            reply,
            modelProvider: result.provider,
            modelName: result.model,
          );
      }
    } catch (e) {
      // JSON 解析失败，直接返回 AI 原文
      debugPrint('VoiceAgent: JSON 解析失败: $e');
      return buildReply(
        result.content,
        modelProvider: result.provider,
        modelName: result.model,
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
