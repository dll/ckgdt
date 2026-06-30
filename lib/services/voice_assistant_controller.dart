import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/init_logger.dart';
import 'agent/agent_model.dart';
import 'agent/agent_registry.dart';
import 'auth_service.dart';
import 'navigation_service.dart';
import 'tts_flutter_service.dart';
import 'voice_service.dart';

/// 语音指令路由器 — 四层渐进式路由匹配 + 常驻聆听循环。
///
/// ```
/// Layer 1 (0ms) — 精确指令：返回 / 退出 / 首页 / 注销
/// Layer 2 (0ms) — 关键词匹配：图谱 / 教学 / 评价 / 达成 / 归档 / 管理 / 实验 / 考核 / 作品 / 学习 / 课堂
/// Layer 3 (0ms) — 模式提取：子页面 / 内层 tab（"评价的实验" / "考核的成绩"）
/// Layer 4 (4-6s) — AI 大模型兜底：复杂意图（"帮我分析最近的成绩"）
/// ```
///
/// L1-L3 导航静默执行，不打断用户；L4 AI 助手通过 TTS 与用户对话。
class VoiceAssistantController {
  static final VoiceAssistantController instance = VoiceAssistantController._();
  VoiceAssistantController._();

  final _tts = TtsFlutterService.instance;
  final _nav = NavigationService.instance;
  final _registry = AgentRegistry.instance;
  final _auth = AuthService();
  final _voice = VoiceService();

  /// L4 AI 最后一句回复（供 UI 展示）
  final ValueNotifier<String> lastReply = ValueNotifier('');

  /// 当前是否在聆听（供 UI 绑定图标动画）
  final ValueNotifier<bool> isListening = ValueNotifier(false);

  /// 流式识别中的临时文本
  final ValueNotifier<String> partialText = ValueNotifier('');

  bool _loopActive = false;
  bool _restarting = false;

  // ═══════════════════════════════════════════════════════════════════════
  // 聆听循环（替代 dialog 生命周期）
  // ═══════════════════════════════════════════════════════════════════════

  /// 开启常驻聆听循环。调用方应在用户点击"语音"按钮时调用。
  Future<void> startLoop() async {
    if (_loopActive) return;
    _loopActive = true;

    _voice.onResult = (text) {
      partialText.value = text;
    };
    _voice.onComplete = (text) {
      unawaited(_handleComplete(text));
    };
    _voice.onError = (error) {
      InitLogger.error('voice', 'loop error: $error');
      unawaited(_voice.forceStop().then((_) => _restartLoop()));
    };
    _voice.onStateChanged = (listening) {
      isListening.value = listening;
    };

    final ok = await _voice.startListening();
    if (ok) {
      isListening.value = true;
      InitLogger.log('voice', 'loop started');
    } else {
      _loopActive = false;
      InitLogger.error('voice', 'loop start failed');
    }
  }

  /// 停止聆听循环。
  Future<void> stopLoop() async {
    _loopActive = false;
    _voice.onResult = null;
    _voice.onComplete = null;
    _voice.onError = null;
    _voice.onStateChanged = null;
    await _voice.forceStop();
    isListening.value = false;
    partialText.value = '';
    InitLogger.log('voice', 'loop stopped');
  }

  Future<void> _restartLoop() async {
    if (_restarting || !_loopActive) return;
    _restarting = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (!_loopActive) return;
      await _voice.forceStop();
      if (!_loopActive) return;
      final ok = await _voice.startListening();
      isListening.value = ok;
    } finally {
      _restarting = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 路由入口
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> routeSentence(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    InitLogger.log('voice',
        'routeSentence text="${text.length > 60 ? '${text.substring(0, 60)}...' : text}"');

    if (await _tryL1(text)) return;
    if (await _tryL2(text)) return;
    if (await _tryL3(text)) return;
    await _tryL4(text);
  }

  Future<void> _handleComplete(String text) async {
    final sentence = text.trim();
    partialText.value = '';
    await _voice.forceStop();
    if (!_loopActive) return;
    if (sentence.isEmpty) {
      await _restartLoop();
      return;
    }
    await routeSentence(sentence);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _restartLoop();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Layer 1: 精确指令 — 静默执行
  // ═══════════════════════════════════════════════════════════════════════

  Future<bool> _tryL1(String raw) async {
    final t = raw.replaceAll(RegExp(r'[。，！？、\s]'), '');

    if (t == '返回' ||
        t == '回去' ||
        t == '上一页' ||
        t == '后退' ||
        t.contains('返回上一页') ||
        t.contains('回到上一页')) {
      _nav.goBack();
      InitLogger.log('voice', 'L1 back');
      return true;
    }

    if (t.contains('回首页') || t.contains('回主页') || t == '首页' || t == '主页') {
      _nav.switchToTab(0);
      InitLogger.log('voice', 'L1 home');
      return true;
    }

    if (t.contains('退出系统') ||
        t.contains('退出程序') ||
        t.contains('关闭应用') ||
        t.contains('关闭系统') ||
        t.contains('关闭程序') ||
        t == '退出' ||
        t == '关闭') {
      _nav.exitApp();
      InitLogger.log('voice', 'L1 exit');
      return true;
    }

    if ((t.contains('退出') && t.contains('登录')) ||
        t.contains('注销') ||
        t.contains('登出')) {
      unawaited(_auth.logout());
      InitLogger.log('voice', 'L1 logout');
      return true;
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Layer 2: 关键词匹配 — 静默执行
  // ═══════════════════════════════════════════════════════════════════════

  static const _tabKeywords = <String, String>{
    '图谱': 'graph',
    '知识图谱': 'graph',
    '知识': 'graph',
    '案例': '案例',
    '案例中心': '案例',
    '案例管理': '案例',
    '优秀案例': '案例',
    '教学': 'learning',
    '教学中心': 'learning',
    '学习': 'learning',
    '学习中心': 'learning',
    '课堂': 'learning',
    '课堂管理': 'learning',
    '课程': 'learning',
    '上课': 'learning',
    '评价': 'assessment',
    '评价中心': 'assessment',
    '考核': 'assessment',
    '考核管理': 'assessment',
    '考试': 'assessment',
    '考察': 'assessment',
    '实验': 'experiment',
    '实验任务': 'experiment',
    '实验课': 'experiment',
    '作品': 'showcase',
    '作品展评': 'showcase',
    '展示': 'showcase',
    '作品展示': 'showcase',
    '我的作品': 'showcase',
    '达成': 'achievement',
    '达成度': 'achievement',
    '成绩达成': 'achievement',
    '成就': 'achievement',
    '成绩': 'achievement',
    '归档': 'archive',
    '存档': 'archive',
    '档案': 'archive',
    '管理': 'admin',
    '后台': 'admin',
    '管理面板': 'admin',
    '后台管理': 'admin',
    '设置': 'settings',
    '系统设置': 'settings',
    '配置': 'settings',
  };

  static const _subPageTargets = <String, _SubPage>{
    '测验': _SubPage('quiz', '测验'),
    '做题': _SubPage('quiz', '测验'),
    '错题': _SubPage('wrong_answers', '错题本'),
    '错题本': _SubPage('wrong_answers', '错题本'),
    '视频': _SubPage('video', '视频教程'),
    '教程': _SubPage('video', '视频教程'),
    '资料': _SubPage('document', '课程资料'),
    '文档': _SubPage('document', '课程资料'),
    '课件': _SubPage('courseware', '课件工坊'),
    '课件工坊': _SubPage('courseware', '课件工坊'),
    '进度': _SubPage('progress', '学习进度'),
    '统计': _SubPage('progress', '学习进度'),
    '计划': _SubPage('plan', '学习计划'),
    '学习计划': _SubPage('plan', '学习计划'),
    '薄弱': _SubPage('weakness', '薄弱诊断'),
    '诊断': _SubPage('weakness', '薄弱诊断'),
    '搜索': _SubPage('search', '搜索'),
    '查找': _SubPage('search', '搜索'),
    '收藏': _SubPage('favorites', '我的收藏'),
    '我的收藏': _SubPage('favorites', '我的收藏'),
    '同步': _SubPage('sync', '数据同步'),
    '数据同步': _SubPage('sync', '数据同步'),
    '通知': _SubPage('notification', '通知中心'),
    '消息': _SubPage('notification', '通知中心'),
    '仓库': _SubPage('repo', 'Git仓库'),
    '反馈': _SubPage('feedback', '反馈'),
    '帮助': _SubPage('handbook', '使用手册'),
    '手册': _SubPage('handbook', '使用手册'),
    '实践': _SubPage('practice', '深度实践'),
    '深度实践': _SubPage('practice', '深度实践'),
    '成长曲线': _SubPage('growth_curve', '成长曲线'),
    '个人中心': _SubPage('student_center', '个人中心'),
    '学生中心': _SubPage('student_center', '个人中心'),
    '教师工作台': _SubPage('teacher_workspace', '教师工作台'),
    '工作台': _SubPage('teacher_workspace', '教师工作台'),
    '聊天记录': _SubPage('chat_history', '聊天记录'),
    '对话记录': _SubPage('chat_history', '聊天记录'),
    'AI技能': _SubPage('ai_skill', 'AI技能'),
    '技能': _SubPage('ai_skill', 'AI技能'),
    '语音设置': _SubPage('voice_settings', '语音设置'),
    'AI设置': _SubPage('ai_settings', 'AI设置'),
    '三端': _SubPage('crossplatform', '跨平台'),
    '四端': _SubPage('crossplatform', '跨平台'),
    '跨平台': _SubPage('crossplatform', '跨平台'),
    '隐私': _SubPage('privacy', '隐私声明'),
    '用户协议': _SubPage('privacy', '隐私声明'),
    '我的数据': _SubPage('my_data', '我的数据'),
    '推荐视频': _SubPage('hot_videos', '推荐视频'),
    '推荐': _SubPage('hot_videos', '推荐视频'),
    'AI调用': _SubPage('agent_calls', 'AI调用统计'),
    '智能体统计': _SubPage('agent_calls', 'AI调用统计'),
  };

  Future<bool> _tryL2(String text) async {
    final t = text
        .replaceAll(RegExp(r'[。，！？、\s]'), '')
        .replaceAll('打开', '')
        .replaceAll('去到', '')
        .replaceAll('进入', '')
        .replaceAll('切换到', '')
        .replaceAll('切换', '')
        .replaceAll('显示', '')
        .replaceAll('我要', '')
        .replaceAll('我想', '')
        .replaceAll('帮我', '')
        .replaceAll('给我', '')
        .replaceAll('看一下', '')
        .replaceAll('看看', '')
        .replaceAll('看', '')
        .replaceAll('去', '');
    if (t.isEmpty) return false;
    if (t.contains('的')) return false;

    InitLogger.log('voice', 'L2 normalized="$t"');

    final sortedSubPages = _subPageTargets.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final e in sortedSubPages) {
      if (t == e.key || t.contains(e.key)) {
        final page = _nav.resolveSubPage(e.value.routeId);
        if (page != null) {
          _nav.pushPage(page);
          InitLogger.log('voice',
              'L2 subPage keyword=${e.key} routeId=${e.value.routeId}');
          return true;
        }
      }
    }

    final sortedTabs = _tabKeywords.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final e in sortedTabs) {
      if (t == e.key || t.contains(e.key)) {
        final ok = _nav.navigateByKeyword(e.value);
        if (ok) {
          InitLogger.log(
              'voice', 'L2 tab keyword=${e.key} englishKey=${e.value}');
          return true;
        }
        break;
      }
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Layer 3: 模式提取 — "X的Y" — 静默执行
  // ═══════════════════════════════════════════════════════════════════════

  static const _hubPages = <String, List<String>>{
    'teaching': ['教学', '学习', '课堂', '课程'],
    'evaluation': ['实验', '考核', '作品', '考试', '展示'],
  };

  Future<bool> _tryL3(String text) async {
    final t = text
        .replaceAll(RegExp(r'[。，！？、\s]'), '')
        .replaceAll('打开', '')
        .replaceAll('去到', '')
        .replaceAll('进入', '')
        .replaceAll('切换到', '')
        .replaceAll('切换', '')
        .replaceAll('显示', '')
        .replaceAll('我要', '')
        .replaceAll('我想', '')
        .replaceAll('帮我', '')
        .replaceAll('给我', '')
        .replaceAll('看一下', '')
        .replaceAll('看看', '')
        .replaceAll('看', '')
        .replaceAll('去', '');
    if (t.isEmpty || !t.contains('的')) return false;

    InitLogger.log('voice', 'L3 trying="$t"');

    final parts = t.split('的').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return false;

    final first = parts.first;
    final last = parts.last;

    String? parentEnglishKey;
    for (final e in _tabKeywords.entries) {
      if (first.contains(e.key) || e.key.contains(first)) {
        parentEnglishKey = e.value;
        break;
      }
    }
    if (parentEnglishKey == null) return false;

    // hub 子 tab？
    String? hubPageKey;
    for (final hub in _hubPages.entries) {
      for (final label in hub.value) {
        if (last.contains(label) || label.contains(last)) {
          if (_isHubOfTab(hub.key, parentEnglishKey)) {
            hubPageKey = hub.key;
            break;
          }
        }
      }
      if (hubPageKey != null) break;
    }

    if (hubPageKey != null) {
      final tabOk = _nav.navigateByKeyword(parentEnglishKey);
      if (tabOk) {
        _nav.requestInnerTab(hubPageKey, last);
        InitLogger.log('voice',
            'L3 hubPageKey=$hubPageKey parentKey=$parentEnglishKey tab=$last');
        return true;
      }
      return false;
    }

    // 子页面？
    final subRoute = _nav.matchSubPage(last);
    if (subRoute != null) {
      final page = _nav.resolveSubPage(subRoute);
      if (page != null && _nav.navigateByKeyword(parentEnglishKey)) {
        _nav.pushPage(page);
        InitLogger.log(
            'voice', 'L3 parent+subPage parent=$parentEnglishKey sub=$last');
        return true;
      }
    }

    // 页面内层 tab
    final innerPageKey = _pageKeyForKeyword(last);
    if (innerPageKey.isNotEmpty) {
      final tabOk = _nav.navigateByKeyword(parentEnglishKey);
      if (tabOk) {
        _nav.requestInnerTab(innerPageKey, last);
        InitLogger.log('voice', 'L3 pageInnerTab page=$innerPageKey tab=$last');
        return true;
      }
    }

    return false;
  }

  bool _isHubOfTab(String hubPageKey, String tabEnglishKey) {
    switch (tabEnglishKey) {
      case 'learning':
        return hubPageKey == 'teaching';
      case 'assessment':
        return hubPageKey == 'evaluation';
      default:
        return false;
    }
  }

  String _pageKeyForKeyword(String kw) {
    switch (kw) {
      case '考核':
      case '考核管理':
      case '考试':
        return 'assessment';
      case '实验':
      case '实验任务':
      case '实验课':
        return 'lab';
      case '作品':
      case '作品展评':
      case '展示':
        return 'works';
      case '课堂':
      case '课堂管理':
        return 'classroom';
      case '教学':
      case '学习':
      case '学习中心':
        return 'learning';
      case '达成':
      case '达成度':
        return 'achievement';
      case '归档':
      case '存档':
        return 'archive';
      default:
        return '';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Layer 4: AI 大模型兜底 — TTS 交互
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _tryL4(String text) async {
    InitLogger.log('voice', 'L4 AI fallback text="$text"');
    lastReply.value = '思考中…';

    final prevOnAction = _registry.onAction;
    _registry.onAction = _executeAction;

    if (_registry.activeAgent?.config.id != 'voice') {
      _registry.switchTo('voice');
    }

    try {
      final reply = await _registry.dispatch(text);
      final speakText = reply.content.trim();
      InitLogger.log('voice',
          'L4 done replyLen=${speakText.length} hasAction=${reply.action != null}');
      lastReply.value = speakText;
      if (speakText.isNotEmpty) {
        await _say(speakText);
      }
    } catch (e, st) {
      InitLogger.error('voice', 'L4 error: $e', st);
      lastReply.value = '刚刚没听明白，请再说一遍';
      await _say(lastReply.value);
    } finally {
      _registry.onAction = prevOnAction;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 公共方法
  // ═══════════════════════════════════════════════════════════════════════

  void speakNoPermission({required String page, required String tab}) {
    _say('$tab是教师专属功能，无法打开');
  }

  void speak(String text) => _say(text);

  // ═══════════════════════════════════════════════════════════════════════
  // AI action 执行
  // ═══════════════════════════════════════════════════════════════════════

  void _executeAction(AgentAction action) {
    InitLogger.log('voice',
        'L4 executeAction type=${action.type} params=${action.params}');
    switch (action.type) {
      case 'navigate_tab':
        final keyword = action.params['keyword'] as String?;
        final label = action.params['label'] as String?;
        var ok = keyword != null ? _nav.navigateByKeyword(keyword) : false;
        if (!ok && label != null && label != keyword) {
          ok = _nav.navigateByKeyword(label);
        }
        InitLogger.log('voice', 'L4 navigate_tab keyword=$keyword ok=$ok');
        break;
      case 'navigate_home':
        _nav.switchToTab(0);
        break;
      case 'navigate_sub_page':
        final kw = action.params['keyword'] as String?;
        if (kw != null) {
          final page = _nav.resolveSubPage(kw);
          if (page != null) _nav.pushPage(page);
        }
        break;
      case 'inner_tab':
        final page = action.params['page'] as String?;
        final tab = action.params['tab'] as String?;
        if (page == null || tab == null) break;
        _nav.requestInnerTab(page, tab);
        final parentLabel =
            NavigationService.pageKeyToTabLabel(page, isTeacher: _isTeacher());
        if (parentLabel != null) _nav.navigateByKeyword(parentLabel);
        break;
      case 'go_back':
        _nav.goBack();
        break;
      case 'pop_to_root':
        _nav.popToRoot();
        _nav.switchToTab(0);
        break;
      case 'exit_app':
        _nav.exitApp();
        break;
      case 'navigate_login':
        unawaited(_auth.logout());
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  bool _isTeacher() => _auth.isTeacher || _auth.isAdmin;

  Future<void> _say(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('VoiceAssistantController: tts error: $e');
    }
  }
}

class _SubPage {
  final String routeId;
  final String label;
  const _SubPage(this.routeId, this.label);
}
