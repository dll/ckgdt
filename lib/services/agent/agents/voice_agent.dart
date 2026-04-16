import '../../auth_service.dart';
import '../../voice_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🎙️ 语音智能体 — 语音登录/退出/导航/TTS
class VoiceAgent extends BaseAgent {
  final AuthService _auth = AuthService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'voice',
        name: '语音助手',
        emoji: '🎙️',
        description: '语音交互、登录退出、页面导航。',
        persona: '你是语音助手"小知"，负责帮用户进行语音登录、退出登录和页面导航。'
            '回复要简短（一句话），适合语音朗读。',
        priority: 9,
        keywords: ['登录', '退出', '打开', '去', '导航', '你好', '帮我', '跳转', '切换'],
        capabilities: ['语音登录', '退出登录', '页面导航', 'TTS语音回复'],
      );

  @override
  List<String> get quickCommands => ['登录', '退出登录', '打开图谱', '打开测验'];

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
    final normalized = userMessage.toLowerCase().replaceAll(RegExp(r'\s+'), '');

    // ── 退出登录 ──
    if (normalized.contains('退出') && normalized.contains('登录') ||
        normalized.contains('注销') || normalized.contains('登出')) {
      if (_auth.isLoggedIn) {
        await _auth.logout();
        return buildReply(
          '已退出登录，再见！',
          action: const AgentAction(type: 'navigate_login', description: '跳转到登录页'),
        );
      }
      return buildReply('你还没有登录哦。');
    }

    // ── 登录 ──
    if (normalized.contains('登录') || normalized.contains('登陆')) {
      final digits = chineseToDigits(userMessage).replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isNotEmpty) {
        final password = digits.length >= 6
            ? digits.substring(digits.length - 6)
            : digits;
        final ok = await _auth.login(digits, password);
        if (ok) {
          final name = _auth.currentUser?.realName ?? digits;
          return buildReply(
            '登录成功！欢迎 $name。',
            action: const AgentAction(type: 'navigate_home', description: '跳转到首页'),
          );
        }
        return buildReply('学号 $digits 登录失败，请检查后重试。');
      }
      return buildReply('请告诉我你的学号，比如"登录 206004"。');
    }

    // ── 页面导航 ──
    if (normalized.contains('打开') || normalized.contains('去') ||
        normalized.contains('跳转') || normalized.contains('切换') ||
        normalized.contains('导航')) {
      final nav = _resolveNavigation(normalized);
      if (nav != null) {
        return buildReply(
          '好的，正在打开${nav['label']}。',
          action: AgentAction(
            type: 'navigate_tab',
            params: {'keyword': nav['keyword']!},
            description: '导航到${nav['label']}',
          ),
        );
      }
    }

    // ── 你好/帮助 ──
    if (normalized.contains('你好') || normalized.contains('嗨') ||
        normalized.contains('hello') || normalized.contains('hi')) {
      final name = _auth.currentUser?.realName;
      return buildReply(
        name != null ? '你好 $name！有什么可以帮你的？' : '你好！有什么可以帮你的？',
      );
    }

    // ── 状态查询 ──
    if (normalized.contains('谁在') || normalized.contains('当前用户')) {
      if (_auth.isLoggedIn) {
        final u = _auth.currentUser!;
        return buildReply('当前登录用户：${u.realName ?? u.userId}（${u.role}）');
      }
      return buildReply('当前未登录。');
    }

    return buildReply('我可以帮你登录、退出或导航到指定页面。试试说"打开图谱"或"登录+学号"。');
  }

  Map<String, String>? _resolveNavigation(String text) {
    const navMap = {
      '图谱': '知识图谱', '知识图谱': '知识图谱',
      '测验': '章节测验', '考试': '章节测验', '答题': '章节测验',
      '学习': '学习中心', '教学': '学习中心',
      '课堂': '课堂管理', '实验': '实验任务',
      '考核': '考核管理', '作品': '作品展评',
      '达成': '达成度', '成就': '达成度',
      '设置': '系统设置', '管理': '管理面板',
      '首页': '首页', '主页': '首页',
      '仓库': 'Git仓库', '代码': 'Git仓库',
      '通知': '通知中心', '消息': '通知中心',
      '同步': '数据同步', '三端': '三端互通',
      '进度': '学习进度', '错题': '错题本',
      '收藏': '我的收藏', '搜索': '搜索',
    };
    for (final e in navMap.entries) {
      if (text.contains(e.key)) {
        return {'keyword': e.key, 'label': e.value};
      }
    }
    return null;
  }
}
