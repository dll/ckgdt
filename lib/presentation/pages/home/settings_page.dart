import 'package:flutter/material.dart';
import '../../../core/build_info.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/error_handler.dart';
import '../../../services/achievement_context.dart';
import '../../../main.dart';
import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import '../../widgets/screenshot_capture_page.dart';
import '../materials/ai_settings_page.dart';
import '../settings/voice_settings_page.dart';
import '../settings/ai_data_page.dart';
import '../feedback/feedback_manage_page.dart';
import '../feedback/feedback_dialog.dart';
import '../feedback/ai_help_dialog.dart';
import '../settings/course_manage_page.dart';
import '../../../data/local/course_dao.dart';
import '../profile/chat_history_page.dart';
import '../analytics/token_stats_page.dart';
import '../../widgets/back_button_bar.dart';
import '../settings/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ThemeMode _themeMode = ThemeMode.system;
  int _colorIndex = 0;
  bool _isPrintMode = false;
  bool _notificationsEnabled = true;
  bool _quickLoginEnabled = false;
  bool _feedbackEnabled = true;
  bool _teacherAiGradingEnabled = true;
  bool _showLoginProgress = true;
  bool _showLogoutReport = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final mode = await SettingsService.getThemeMode();
    final index = await SettingsService.getColorIndex();
    final printMode = await SettingsService.getPrintMode();
    final notifEnabled = await SettingsService.isNotificationEnabled();
    final quickLogin = await SettingsService.isQuickLoginEnabled();
    final feedbackEnabled = await SettingsService.isFeedbackEnabled();
    final teacherAiGradingEnabled =
        await SettingsService.isTeacherAiGradingEnabled();
    final showLoginProgress =
        await SettingsService.isLoginProgressDialogEnabled();
    final showLogoutReport =
        await SettingsService.isLogoutReportDialogEnabled();
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _colorIndex = index;
        _isPrintMode = printMode;
        _notificationsEnabled = notifEnabled;
        _quickLoginEnabled = quickLogin;
        _feedbackEnabled = feedbackEnabled;
        _teacherAiGradingEnabled = teacherAiGradingEnabled;
        _showLoginProgress = showLoginProgress;
        _showLogoutReport = showLogoutReport;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      appBar: BackButtonBar(
        title: '设置',
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '通用', icon: Icon(Icons.tune, size: 18)),
            Tab(text: 'AI 与语音', icon: Icon(Icons.smart_toy, size: 18)),
            Tab(text: '外观', icon: Icon(Icons.palette, size: 18)),
            Tab(text: '关于', icon: Icon(Icons.info_outline, size: 18)),
          ],
        ),
      ),
      body: Column(
        children: [
          // 用户信息卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppGradientTheme.of(context).verticalGradient,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  child: Text(
                    (user?.realName ?? user?.userId ?? 'U').substring(0, 1),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.realName ?? user?.userId ?? '用户',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        user?.role == 'admin'
                            ? '管理员'
                            : user?.role == 'teacher'
                                ? '教师'
                                : '学生',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tab 内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGeneralTab(authService),
                _buildAiTab(authService),
                _buildAppearanceTab(),
                _buildAboutTab(authService),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: 通用设置 ──────────────────────────────────────────────────────

  Widget _buildGeneralTab(AuthService authService) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSectionHeader('通知与弹窗'),
        _buildSwitchItem(
          icon: Icons.notifications,
          title: '通知设置',
          subtitle: '管理学习提醒',
          value: _notificationsEnabled,
          onChanged: (v) async {
            await SettingsService.setNotificationEnabled(v);
            setState(() => _notificationsEnabled = v);
          },
        ),
        _buildSwitchItem(
          icon: Icons.waving_hand,
          title: '登录欢迎弹窗',
          subtitle: _showLoginProgress
              ? '已开启：登录后显示学习进度'
              : '已关闭：登录后直接进入首页',
          value: _showLoginProgress,
          onChanged: (v) async {
            await SettingsService.setLoginProgressDialogEnabled(v);
            setState(() => _showLoginProgress = v);
          },
        ),
        _buildSwitchItem(
          icon: Icons.exit_to_app,
          title: '退出报告弹窗',
          subtitle: _showLogoutReport
              ? '已开启：退出前显示成绩报告'
              : '已关闭：退出时直接确认',
          value: _showLogoutReport,
          onChanged: (v) async {
            await SettingsService.setLogoutReportDialogEnabled(v);
            setState(() => _showLogoutReport = v);
          },
        ),
        const Divider(height: 24),
        _buildSectionHeader('课程与数据'),
        _buildNavItem(
          icon: Icons.school_outlined,
          title: '课程管理',
          subtitle: '查看、切换和生成课程',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CourseManagePage()),
          ),
        ),
        _buildNavItem(
          icon: Icons.storage,
          title: '清除缓存',
          subtitle: '释放存储空间',
          onTap: () => _showClearCacheDialog(context),
        ),
        _buildNavItem(
          icon: Icons.camera_alt,
          title: '后台截图',
          subtitle: '批量截取各功能页面封面图',
          onTap: () => _refreshAllScreenshots(context),
        ),
        if (authService.isAdmin) ...[
          const Divider(height: 24),
          _buildSectionHeader('管理员选项'),
          _buildSwitchItem(
            icon: Icons.flash_on,
            title: '快速登录',
            subtitle: '登录页显示测试用户快速登录按钮',
            value: _quickLoginEnabled,
            onChanged: (v) async {
              await SettingsService.setQuickLoginEnabled(v);
              setState(() => _quickLoginEnabled = v);
            },
          ),
          _buildSwitchItem(
            icon: Icons.feedback,
            title: '问题反馈按钮',
            subtitle: '所有用户页面显示浮动反馈按钮',
            value: _feedbackEnabled,
            onChanged: (v) async {
              await SettingsService.setFeedbackEnabled(v);
              setState(() => _feedbackEnabled = v);
              MyApp.refreshFeedback();
            },
          ),
        ],
      ],
    );
  }

  // ── Tab 2: AI 与语音 ─────────────────────────────────────────────────────

  Widget _buildAiTab(AuthService authService) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSectionHeader('AI 配置'),
        _buildNavItem(
          icon: Icons.smart_toy,
          title: 'AI 服务商配置',
          subtitle: '配置 AI 服务商、模型；可填写自己的 API Key',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiSettingsPage()),
          ),
        ),
        if (authService.isTeacher || authService.isAdmin)
          _buildSwitchItem(
            icon: Icons.fact_check_outlined,
            title: '教师 AI 批阅',
            subtitle: _teacherAiGradingEnabled
                ? '已开启：学生提交后后台生成 AI 批阅草稿'
                : '已关闭：教师可手动批阅或单独 AI 批阅',
            value: _teacherAiGradingEnabled,
            onChanged: (v) async {
              await SettingsService.setTeacherAiGradingEnabled(v);
              setState(() => _teacherAiGradingEnabled = v);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(v
                      ? '教师 AI 批阅已开启'
                      : '教师 AI 批阅已关闭'),
                ),
              );
            },
          ),
        const Divider(height: 24),
        _buildSectionHeader('对话与统计'),
        _buildNavItem(
          icon: Icons.chat_outlined,
          title: '对话历史',
          subtitle: '查看和管理智能体对话记录',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatHistoryPage()),
          ),
        ),
        _buildNavItem(
          icon: Icons.analytics,
          title: 'AI 数据管理',
          subtitle: '对话历史、使用统计、数据清理',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiDataPage()),
          ),
        ),
        _buildNavItem(
          icon: Icons.token,
          title: 'Token 用量统计',
          subtitle: '查看各模型/服务商的 Token 消耗趋势',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TokenStatsPage()),
          ),
        ),
        const Divider(height: 24),
        _buildSectionHeader('语音'),
        _buildNavItem(
          icon: Icons.mic,
          title: '讯飞语音设置',
          subtitle: '配置讯飞语音听写 AppID/APIKey/APISecret',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VoiceSettingsPage()),
          ),
        ),
      ],
    );
  }

  // ── Tab 3: 外观 ──────────────────────────────────────────────────────────

  Widget _buildAppearanceTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSectionHeader('主题色'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: List.generate(AppColors.presets.length, (i) {
              final preset = AppColors.presets[i];
              final selected = _colorIndex == i;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () async {
                    await SettingsService.setColorIndex(i);
                    setState(() => _colorIndex = i);
                    MyApp.refreshTheme();
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: preset.primary,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: preset.primary, width: 3)
                              : null,
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: preset.primary.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: selected
                            ? const Icon(Icons.check, color: Colors.white, size: 22)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        preset.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? preset.primary : Colors.grey,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('显示模式'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('跟随系统'),
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('浅色'),
                    icon: Icon(Icons.wb_sunny_outlined),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text('深色'),
                    icon: Icon(Icons.nightlight_round),
                  ),
                  ButtonSegment(
                    value: 3,
                    label: Text('打印'),
                    icon: Icon(Icons.print),
                  ),
                ],
                selected: {_isPrintMode ? 3 : _themeMode == ThemeMode.system ? 0 : _themeMode == ThemeMode.light ? 1 : 2},
                onSelectionChanged: (Set<int> selected) async {
                  final v = selected.first;
                  if (v == 3) {
                    await SettingsService.setPrintMode(true);
                    setState(() => _isPrintMode = true);
                  } else {
                    await SettingsService.setPrintMode(false);
                    final mode = v == 0 ? ThemeMode.system : v == 1 ? ThemeMode.light : ThemeMode.dark;
                    await SettingsService.setThemeMode(mode);
                    setState(() {
                      _isPrintMode = false;
                      _themeMode = mode;
                    });
                  }
                  MyApp.refreshTheme();
                },
              ),
              const SizedBox(height: 8),
              Builder(builder: (ctx) {
                if (_isPrintMode) {
                  return const Text(
                    '当前实际：打印（白底黑字）',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      letterSpacing: 0.8,
                    ),
                  );
                }
                final brightness = MediaQuery.platformBrightnessOf(ctx);
                final actual = _themeMode == ThemeMode.system
                    ? '当前实际：${brightness == Brightness.dark ? '深色（系统）' : '浅色（系统）'}'
                    : _themeMode == ThemeMode.light
                        ? '当前实际：浅色'
                        : '当前实际：深色';
                return Text(
                  actual,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.55),
                    letterSpacing: 0.8,
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('语言 / Language'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: FutureBuilder<Locale?>(
            future: SettingsService.getLocale(),
            builder: (ctx, snap) {
              final cur = snap.data?.languageCode ?? 'system';
              return SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'system',
                    label: Text('跟随系统'),
                    icon: Icon(Icons.language),
                  ),
                  ButtonSegment(value: 'zh', label: Text('中文')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {cur},
                onSelectionChanged: (s) async {
                  final v = s.first;
                  await SettingsService.setLocale(v == 'system' ? null : Locale(v));
                  if (mounted) {
                    MyApp.refreshTheme();
                    setState(() {});
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Tab 4: 关于 ──────────────────────────────────────────────────────────

  Widget _buildAboutTab(AuthService authService) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSectionHeader('应用信息'),
        _buildNavItem(
          icon: Icons.info,
          title: '关于应用',
          subtitle: '版本信息和使用条款',
          onTap: () => _showAboutDialog(context),
        ),
        _buildNavItem(
          icon: Icons.system_update,
          title: '检查更新',
          subtitle: 'v${BuildInfo.appVersion}  — 检查新版本',
          onTap: () => UpdateDialog.showCheckUpdate(context),
        ),
        const Divider(height: 24),
        _buildSectionHeader('帮助与反馈'),
        _buildNavItem(
          icon: Icons.support_agent,
          title: '系统帮助',
          subtitle: 'AI 助手解答使用问题',
          onTap: () => AiHelpDialog.show(context),
        ),
        _buildNavItem(
          icon: Icons.feedback_outlined,
          title: '问题反馈',
          subtitle: '提交问题或改进建议',
          onTap: () => FeedbackDialog.show(context),
        ),
        if (authService.isAdmin || authService.isTeacher)
          _buildNavItem(
            icon: Icons.admin_panel_settings,
            title: '反馈管理',
            subtitle: '查看和处理用户反馈',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FeedbackManagePage()),
            ),
          ),
      ],
    );
  }

  // ── 通用组件 ──────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: primary.withOpacity(0.1),
        child: Icon(icon, color: primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: primary.withOpacity(0.1),
        child: Icon(icon, color: primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除应用缓存吗？这不会影响您的学习数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('缓存已清除')),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) async {
    String courseName = '当前课程';
    try {
      final course = await CourseDao().getActiveCourse();
      if (course != null) courseName = course.name;
    } catch (e) {
      swallowDebug(e, tag: 'settings_page');
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.school, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(BuildInfo.displayFullName(AchievementContext.instance.courseName)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本：${BuildInfo.appVersion}'),
            const SizedBox(height: 8),
            Text(
              '${BuildInfo.displayFullName(AchievementContext.instance.courseName)}（${BuildInfo.appEnglishName}）。',
            ),
            const SizedBox(height: 8),
            Text('当前课程：$courseName。'),
            const SizedBox(height: 16),
            const Text('功能特点：', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('• 知识图谱可视化学习'),
            const Text('• 章节测验与错题复习'),
            const Text('• 学习进度追踪'),
            const Text('• AI 智能教学助手'),
            const Text('• 一键生课平台化'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshAllScreenshots(BuildContext context) async {
    final auth = AuthService();
    final isTeacher = auth.isTeacher;
    final isAdmin = auth.isAdmin;
    final isTeacherOrAdmin = isTeacher || isAdmin;

    final pages = <String, Widget>{};

    if (!isTeacherOrAdmin) {
      pages['学习进度'] = const _PlaceholderPage('学习进度');
      pages['错题本'] = const _PlaceholderPage('错题本');
      pages['我的收藏'] = const _PlaceholderPage('我的收藏');
    }

    if (isTeacherOrAdmin) {
      pages['成绩统计'] = const _PlaceholderPage('成绩统计');
      pages['班级管理'] = const _PlaceholderPage('班级管理');
    }

    int completed = 0;
    final total = pages.length;
    if (total == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可截图的页面')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在后台截取封面 ($completed/$total)...'),
            ],
          ),
        ),
      ),
    );

    for (final entry in pages.entries) {
      if (!context.mounted) break;
      try {
        await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => ScreenshotCapturePage(
              captureKey: entry.key,
              child: entry.value,
            ),
            transitionsBuilder: (_, __, ___, child) => child,
            opaque: false,
            barrierDismissible: false,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      } catch (e, st) {
        swallowDebug(e, tag: 'ScreenshotCapture', stack: st);
      }
      completed++;
    }

    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已截取 $completed 个页面封面')),
      );
      setState(() {});
    }
  }
}

/// 截图用占位页面
class _PlaceholderPage extends StatelessWidget {
  final String title;
  const _PlaceholderPage(this.title);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text(title)),
      );
}
