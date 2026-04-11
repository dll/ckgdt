import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../main.dart';
import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import '../learning/video_page.dart';
import '../materials/ai_settings_page.dart';
import '../quiz/wrong_answers_page.dart';
import '../graph/favorites_page.dart';
import '../survey/survey_page.dart';

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
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _colorIndex = index;
        _notificationsEnabled = notifEnabled;
        _quickLoginEnabled = quickLogin;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // 用户信息
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradientTheme.of(context).verticalGradient,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text(
                    (user?.realName ?? user?.userId ?? 'U').substring(0, 1),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
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

          // 学习工具
          _buildSectionHeader(context, '学习工具'),
          _buildMenuItem(
            context,
            icon: Icons.error,
            title: '错题本',
            subtitle: '查看和复习错题',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WrongAnswersPage()),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.star,
            title: '我的收藏',
            subtitle: '查看收藏的知识点',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FavoritesPage()),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.poll,
            title: '问卷调查',
            subtitle: '学习习惯与课程满意度调查',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SurveyPage()),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.video_library,
            title: '视频教程',
            subtitle: '观看学习视频',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VideoListPage()),
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
            icon: Icons.storage,
            title: '清除缓存',
            subtitle: '释放存储空间',
            onTap: () => _showClearCacheDialog(context),
          ),
          _buildMenuItem(
            context,
            icon: Icons.smart_toy,
            title: 'AI 配置',
            subtitle: '配置 AI 服务商、API Key 和模型',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiSettingsPage()),
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
                      padding: const EdgeInsets.only(right: 20),
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
                                color:
                                    selected ? preset.primary : Colors.grey,
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
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode),
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
              ],
            ),
          ),

          const SizedBox(height: 8),

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
            icon: Icons.help,
            title: '帮助与反馈',
            subtitle: '获取帮助或提交建议',
            onTap: () => _showTip(context, '帮助与反馈功能开发中'),
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
      leading: CircleAvatar(
        backgroundColor: primary.withValues(alpha: 0.1),
        child: Icon(icon, color: primary),
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showTip(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.school, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Text('移动应用开发知识图谱'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本：1.0.0'),
            SizedBox(height: 8),
            Text('一款面向移动应用开发学习者的知识图谱与测验系统。'),
            SizedBox(height: 16),
            Text('功能特点：', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• 知识图谱可视化学习'),
            Text('• 章节测验与错题复习'),
            Text('• 学习进度追踪'),
            Text('• 视频教程播放'),
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
}
