import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../data/local/database_helper.dart';
import '../../../core/constants/app_theme.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';

class TeacherWorkspacePage extends StatefulWidget {
  const TeacherWorkspacePage({super.key});

  @override
  State<TeacherWorkspacePage> createState() => _TeacherWorkspacePageState();
}

class _TeacherWorkspacePageState extends State<TeacherWorkspacePage> {
  final _authService = AuthService();

  bool _isLoading = true;

  // 教学概览数据
  int _studentCount = 0;
  int _graphCount = 0;
  int _questionCount = 0;
  int _resourceCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      final studentResult = await db.rawQuery(
        "SELECT COUNT(*) as count FROM users WHERE role='student'",
      );
      final graphResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM graphs',
      );
      final questionResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM questions',
      );
      final resourceResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM resource_files',
      );

      setState(() {
        _studentCount = (studentResult.first['count'] as int?) ?? 0;
        _graphCount = (graphResult.first['count'] as int?) ?? 0;
        _questionCount = (questionResult.first['count'] as int?) ?? 0;
        _resourceCount = (resourceResult.first['count'] as int?) ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final gradient = AppGradientTheme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('教师工作台'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 欢迎头部 ──────────────────────────────────────────────
              _buildWelcomeHeader(user, gradient),
              const SizedBox(height: 24),

              // ── 教学概览 ──────────────────────────────────────────────
              const Text(
                '教学概览',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildOverviewStats(),
              const SizedBox(height: 24),

              // ── 快捷工具 ──────────────────────────────────────────────
              const Text(
                '快捷工具',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildToolGrid(),
              const SizedBox(height: 24),

              // ── 最近动态 ──────────────────────────────────────────────
              const Text(
                '最近动态',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildRecentActivities(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 欢迎头部
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWelcomeHeader(dynamic user, AppGradientTheme gradient) {
    final displayName = user?.realName ?? user?.userId ?? '老师';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: gradient.linearGradient,
        ),
        child: Row(
          children: [
            // 头像
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.school, size: 36, color: Colors.white),
            ),
            const SizedBox(width: 16),
            // 文字信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '欢迎回来，$displayName！',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '教师工作台',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '工号：${user?.userId ?? ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 教学概览 — 4 个统计卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOverviewStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            '学生人数',
            '$_studentCount',
            Icons.people,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '图谱数量',
            '$_graphCount',
            Icons.account_tree,
            Colors.teal,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '题库数量',
            '$_questionCount',
            Icons.quiz,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '资源数量',
            '$_resourceCount',
            Icons.folder,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 快捷工具 — 6 个工具卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildToolGrid() {
    final tools = [
      _ToolItem(
        icon: Icons.people,
        label: '学生管理',
        color: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StudentManagePage()),
        ),
      ),
      _ToolItem(
        icon: Icons.quiz,
        label: '题库管理',
        color: Colors.orange,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('题库管理功能开发中')),
          );
        },
      ),
      _ToolItem(
        icon: Icons.folder_open,
        label: '资源管理',
        color: Colors.purple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DataImportPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.assessment,
        label: '成绩统计',
        color: Colors.green,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('成绩统计功能开发中')),
          );
        },
      ),
      _ToolItem(
        icon: Icons.account_tree,
        label: '图谱编辑',
        color: Colors.teal,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('图谱编辑功能开发中')),
          );
        },
      ),
      _ToolItem(
        icon: Icons.download,
        label: '数据导出',
        color: Colors.indigo,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DataImportPage()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        final tool = tools[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: tool.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tool.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    tool.icon,
                    color: tool.color,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tool.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: tool.color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 最近动态 — 模拟数据列表
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRecentActivities() {
    final activities = [
      _ActivityItem(
        icon: Icons.person_add,
        title: '新学生注册',
        subtitle: '共 $_studentCount 名学生已加入课程',
        time: '系统统计',
        color: Colors.blue,
      ),
      _ActivityItem(
        icon: Icons.quiz,
        title: '题库已就绪',
        subtitle: '共 $_questionCount 道题目覆盖 6 个章节',
        time: '系统统计',
        color: Colors.orange,
      ),
      _ActivityItem(
        icon: Icons.account_tree,
        title: '知识图谱',
        subtitle: '已创建 $_graphCount 个知识图谱',
        time: '系统统计',
        color: Colors.teal,
      ),
      _ActivityItem(
        icon: Icons.folder,
        title: '课程资源',
        subtitle: '已上传 $_resourceCount 个课程资源文件',
        time: '系统统计',
        color: Colors.purple,
      ),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final activity = activities[index];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: activity.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                activity.icon,
                color: activity.color,
                size: 22,
              ),
            ),
            title: Text(
              activity.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              activity.subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: Text(
              activity.time,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 辅助数据类
// ─────────────────────────────────────────────────────────────────────────────

class _ToolItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _ActivityItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color color;

  const _ActivityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
  });
}
