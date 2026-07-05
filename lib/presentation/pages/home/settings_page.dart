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
import '../learning/learning_plan_page.dart';
import '../quiz/quiz_page.dart';
import '../repo/git_repo_page.dart';
import '../repo/student_repo_page.dart';
import '../skill/ai_skill_page.dart';
import '../profile/virtual_twin_page.dart';
import '../practice/deep_practice_page.dart';
import '../practice/growth_curve_page.dart';
import '../sync/data_sync_page.dart';
import '../cross_platform/cross_platform_hub_page.dart';
import '../learning/progress_page.dart';
import '../quiz/wrong_answers_page.dart';
import '../graph/favorites_page.dart';
import '../survey/survey_page.dart';
import '../class_qa/class_qa_page.dart';
import '../analytics/learning_analytics_page.dart';
import '../admin/class_manage_page.dart';
import '../admin/teaching_manage_page.dart';
import '../admin/question_manage_page.dart';
import '../admin/survey_manage_page.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';
import '../admin/data_export_page.dart';
import '../admin/repo_analytics_page.dart';
import '../settings/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ThemeMode _themeMode = ThemeMode.system;
  int _colorIndex = 0;
  bool _notificationsEnabled = true;
  bool _quickLoginEnabled = false;
  bool _feedbackEnabled = true;
  bool _teacherAiGradingEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await SettingsService.getThemeMode();
    final index = await SettingsService.getColorIndex();
    final notifEnabled = await SettingsService.isNotificationEnabled();
    final quickLogin = await SettingsService.isQuickLoginEnabled();
    final feedbackEnabled = await SettingsService.isFeedbackEnabled();
    final teacherAiGradingEnabled =
        await SettingsService.isTeacherAiGradingEnabled();
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _colorIndex = index;
        _notificationsEnabled = notifEnabled;
        _quickLoginEnabled = quickLogin;
        _feedbackEnabled = feedbackEnabled;
        _teacherAiGradingEnabled = teacherAiGradingEnabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      appBar: const BackButtonBar(
        title: '设置',
      ),
      body: ListView(
        children: [
          // 用户信息
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

          const SizedBox(height: 16),

          // 系统设置
          _buildSectionHeader(context, '系统设置'),
          _buildMenuItem(
            context,
            icon: Icons.notifications,
            title: '通知设置',
            subtitle: '管理学习提醒',
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: (value) async {
                await SettingsService.setNotificationEnabled(value);
                setState(() => _notificationsEnabled = value);
              },
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.camera_alt,
            title: '后台截图',
            subtitle: '批量截取各功能页面封面图（后台静默运行）',
            onTap: () => _refreshAllScreenshots(context),
          ),
          _buildMenuItem(
            context,
            icon: Icons.storage,
            title: '清除缓存',
            subtitle: '释放存储空间',
            onTap: () => _showClearCacheDialog(context),
          ),
          _buildMenuItem(
            context,
            icon: Icons.smart_toy,
            title: 'AI 配置',
            subtitle: '配置 AI 服务商、模型；可填写自己的 API Key',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiSettingsPage()),
            ),
          ),
          if (authService.isTeacher || authService.isAdmin)
            _buildMenuItem(
              context,
              icon: Icons.fact_check_outlined,
              title: '教师 AI 批阅',
              subtitle: _teacherAiGradingEnabled
                  ? '已开启：学生提交后后台生成 AI 批阅草稿，教师复核后通知成绩'
                  : '已关闭：学生仍可正常提交，教师可手动批阅或单独 AI 批阅',
              trailing: Switch(
                value: _teacherAiGradingEnabled,
                onChanged: (value) async {
                  await SettingsService.setTeacherAiGradingEnabled(value);
                  setState(() => _teacherAiGradingEnabled = value);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value
                          ? '教师 AI 批阅已开启，学生提交后将后台生成草稿'
                          : '教师 AI 批阅已关闭，学生仍可正常提交'),
                    ),
                  );
                },
              ),
            ),
          _buildMenuItem(
            context,
            icon: Icons.chat_outlined,
            title: '对话历史',
            subtitle: '查看和管理智能体对话记录、收藏对话',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatHistoryPage()),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.analytics,
            title: 'AI 数据管理',
            subtitle: '对话历史、使用统计、数据清理',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiDataPage()),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.token,
            title: 'Token 用量统计',
            subtitle: '查看各模型/服务商的 Token 消耗趋势',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TokenStatsPage()),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.school_outlined,
            title: '课程管理',
            subtitle: '查看、切换和生成课程',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CourseManagePage()),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.mic,
            title: '讯飞语音设置',
            subtitle: '配置讯飞语音听写 AppID/APIKey/APISecret',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VoiceSettingsPage()),
            ),
          ),
          if (user?.isAdmin == true)
            _buildMenuItem(
              context,
              icon: Icons.flash_on,
              title: '快速登录',
              subtitle: '登录页显示测试用户快速登录按钮',
              trailing: Switch(
                value: _quickLoginEnabled,
                onChanged: (value) async {
                  await SettingsService.setQuickLoginEnabled(value);
                  setState(() => _quickLoginEnabled = value);
                },
              ),
            ),
          if (user?.isAdmin == true)
            _buildMenuItem(
              context,
              icon: Icons.feedback,
              title: '问题反馈按钮',
              subtitle: '所有用户页面显示浮动反馈按钮',
              trailing: Switch(
                value: _feedbackEnabled,
                onChanged: (value) async {
                  await SettingsService.setFeedbackEnabled(value);
                  setState(() => _feedbackEnabled = value);
                  MyApp.refreshFeedback();
                },
              ),
            ),

          const SizedBox(height: 16),

          // 外观设置
          _buildSectionHeader(context, '外观设置'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('主题色', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                Row(
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
                                    ? Border.all(
                                        color: preset.primary,
                                        width: 3,
                                      )
                                    : null,
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: preset.primary
                                              .withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                              child: selected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 22,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              preset.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected ? preset.primary : Colors.grey,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 显示模式 —— SegmentedButton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('显示模式', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.wb_sunny_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.nightlight_round),
                    ),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (Set<ThemeMode> selected) async {
                    final mode = selected.first;
                    await SettingsService.setThemeMode(mode);
                    setState(() => _themeMode = mode);
                    MyApp.refreshTheme();
                  },
                ),
                const SizedBox(height: 8),
                Builder(builder: (ctx) {
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
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                      letterSpacing: 0.8,
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 语言（i18n）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('语言 / Language', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                FutureBuilder<Locale?>(
                  future: SettingsService.getLocale(),
                  builder: (ctx, snap) {
                    final cur = snap.data?.languageCode ?? 'system';
                    return SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'system',
                          label: Text('跟随系统 / Auto'),
                          icon: Icon(Icons.language),
                        ),
                        ButtonSegment(
                          value: 'zh',
                          label: Text('中文'),
                        ),
                        ButtonSegment(
                          value: 'en',
                          label: Text('English'),
                        ),
                      ],
                      selected: {cur},
                      onSelectionChanged: (s) async {
                        final v = s.first;
                        await SettingsService.setLocale(
                            v == 'system' ? null : Locale(v));
                        if (mounted) {
                          MyApp.refreshTheme();
                          setState(() {});
                        }
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 关于
          _buildSectionHeader(context, '关于'),
          _buildMenuItem(
            context,
            icon: Icons.info,
            title: '关于应用',
            subtitle: '版本信息和使用条款',
            onTap: () => _showAboutDialog(context),
          ),
          _buildMenuItem(
            context,
            icon: Icons.system_update,
            title: '检查更新',
            subtitle: 'v${BuildInfo.appVersion}  — 检查 GitHub 新版本',
            onTap: () => UpdateDialog.showCheckUpdate(context),
          ),
          _buildMenuItem(
            context,
            icon: Icons.support_agent,
            title: '系统帮助',
            subtitle: 'AI 助手解答使用问题',
            onTap: () => AiHelpDialog.show(context),
          ),
          _buildMenuItem(
            context,
            icon: Icons.feedback_outlined,
            title: '问题反馈',
            subtitle: '提交问题或改进建议',
            onTap: () => FeedbackDialog.show(context),
          ),
          if (user?.isAdmin == true || user?.isTeacher == true)
            _buildMenuItem(
              context,
              icon: Icons.admin_panel_settings,
              title: '反馈管理',
              subtitle: '查看和处理用户反馈',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FeedbackManagePage()),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: primary.withValues(alpha: 0.1),
        child: Icon(icon, color: primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 11),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
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

    final pages = <String, Widget>{
      '学习路径': const LearningPlanPage(),
      '章节测验': const QuizPage(),
      'Git仓库': isTeacherOrAdmin ? const GitRepoPage() : const StudentRepoPage(),
      '技能工具': const SkillsHubPage(),
      '数字孪生': const VirtualTwinPage(),
      '深度实践': const DeepPracticePage(),
      '成长曲线': const GrowthCurvePage(),
      'Token统计': const TokenStatsPage(),
      '数据同步': const DataSyncPage(),
      '多端互通': const CrossPlatformHubPage(),
    };

    if (!isTeacherOrAdmin) {
      pages['学习进度'] = const ProgressPage();
      pages['错题本'] = const WrongAnswersPage();
      pages['我的收藏'] = const FavoritesPage();
      pages['问卷调查'] = const SurveyPage();
      pages['班级问答'] = const ClassQaPage();
    }

    if (isTeacherOrAdmin) {
      pages['成绩统计'] = const LearningAnalyticsPage();
      pages['班级管理'] = const ClassManagePage();
      pages['教学管理'] = const TeachingManagePage();
      pages['题库管理'] = const QuestionManagePage();
      pages['问卷管理'] = const SurveyManagePage();
      pages['反馈管理'] = const FeedbackManagePage();
      pages['课程管理'] = const CourseManagePage();
    }

    if (isAdmin) {
      pages['学生管理'] = const StudentManagePage();
      pages['数据导入'] = const DataImportPage();
      pages['数据导出'] = const DataExportPage();
      pages['仓库分析'] = const RepoAnalyticsPage();
    }

    int completed = 0;
    final total = pages.length;
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
