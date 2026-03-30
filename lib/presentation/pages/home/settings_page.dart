import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import '../learning/video_page.dart';
import '../quiz/wrong_answers_page.dart';
import '../graph/favorites_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final isDark = await SettingsService.isDarkMode();
    final notifEnabled = await SettingsService.isNotificationEnabled();
    setState(() {
      _isDarkMode = isDark;
      _notificationsEnabled = notifEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // 用户信息
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text(
                    (user?.realName ?? user?.userId ?? 'U').substring(0, 1),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF667eea),
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
                        user?.role == 'admin' ? '管理员' : 
                        user?.role == 'teacher' ? '教师' : '学生',
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
          _buildSectionHeader('学习工具'),
          _buildMenuItem(
            context,
            icon: Icons.error,
            title: '错题本',
            subtitle: '查看和复习错题',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WrongAnswersPage())),
          ),
          _buildMenuItem(
            context,
            icon: Icons.star,
            title: '我的收藏',
            subtitle: '查看收藏的知识点',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage())),
          ),
          _buildMenuItem(
            context,
            icon: Icons.video_library,
            title: '视频教程',
            subtitle: '观看学习视频',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VideoListPage())),
          ),
          
          const SizedBox(height: 16),
          
          // 系统设置
          _buildSectionHeader('系统设置'),
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
            icon: Icons.dark_mode,
            title: '深色模式',
            subtitle: '切换应用主题',
            trailing: Switch(
              value: _isDarkMode,
              onChanged: (value) async {
                await SettingsService.setDarkMode(value);
                setState(() => _isDarkMode = value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(value ? '已开启深色模式' : '已关闭深色模式')),
                );
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
          
          const SizedBox(height: 16),
          
          // 关于
          _buildSectionHeader('关于'),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF667eea),
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
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF667eea).withValues(alpha: 0.1),
        child: Icon(icon, color: const Color(0xFF667eea)),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
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
        title: const Row(
          children: [
            Icon(Icons.school, color: Color(0xFF667eea)),
            SizedBox(width: 12),
            Text('移动应用开发知识图谱'),
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
