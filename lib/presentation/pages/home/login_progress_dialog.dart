import 'package:flutter/material.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/course_context_service.dart';

/// 登录进度弹窗 — 显示学生/教师的学习/教学进度概览
class LoginProgressDialog extends StatefulWidget {
  final String userId;
  final String userName;
  final String role;

  const LoginProgressDialog({
    super.key,
    required this.userId,
    required this.userName,
    required this.role,
  });

  /// 登录成功后调用此方法显示弹窗
  static Future<void> showAfterLogin(
    BuildContext context, {
    required String userId,
    required String userName,
    required String role,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoginProgressDialog(
        userId: userId,
        userName: userName,
        role: role,
      ),
    );
  }

  @override
  State<LoginProgressDialog> createState() => _LoginProgressDialogState();
}

class _LoginProgressDialogState extends State<LoginProgressDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _loading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _loadStats();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final ctx = CourseContextService();
      final courseId = await ctx.activeCourseId();

      if (widget.role == 'student') {
        // 学生端：学习进度
        final quizCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM quiz_results WHERE user_id = ? AND course_id = ?",
          [widget.userId, courseId],
        );
        final homeworkCount = await db.rawQuery(
          "SELECT COUNT(DISTINCT homework_id) as c FROM homework_submissions WHERE user_id = ?",
          [widget.userId],
        );
        final labCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM lab_submissions WHERE user_id = ?",
          [widget.userId],
        );
        final wrongCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM wrong_answers WHERE user_id = ?",
          [widget.userId],
        );
        final nodeCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM concept_progress WHERE user_id = ? AND status = 'mastered'",
          [widget.userId],
        );

        _stats = {
          'quizCount': (quizCount.first['c'] as int?) ?? 0,
          'homeworkCount': (homeworkCount.first['c'] as int?) ?? 0,
          'labCount': (labCount.first['c'] as int?) ?? 0,
          'wrongCount': (wrongCount.first['c'] as int?) ?? 0,
          'masteredNodes': (nodeCount.first['c'] as int?) ?? 0,
        };
      } else {
        // 教师端：教学进度
        final studentCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM users WHERE role = 'student' AND is_active = 1",
        );
        final courseCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM courses WHERE is_active = 1",
        );
        final pendingSubmissions = await db.rawQuery(
          "SELECT COUNT(*) as c FROM homework_submissions WHERE status = 'submitted'",
        );

        _stats = {
          'studentCount': (studentCount.first['c'] as int?) ?? 0,
          'courseCount': (courseCount.first['c'] as int?) ?? 0,
          'pendingSubmissions': (pendingSubmissions.first['c'] as int?) ?? 0,
        };
      }
    } catch (e) {
      debugPrint('LoginProgress: load stats error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStudent = widget.role == 'student';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(24),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头像
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                ),
                child: Icon(
                  isStudent ? Icons.school : Icons.person,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '欢迎回来',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.userName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isStudent
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isStudent ? '学生' : '教师',
                  style: TextStyle(
                    fontSize: 12,
                    color: isStudent ? Colors.blue : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 进度统计
              if (_loading)
                const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                isStudent ? _buildStudentStats(theme) : _buildTeacherStats(theme),

              const SizedBox(height: 20),

              // 关闭按钮
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('进入学习'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentStats(ThemeData theme) {
    final items = [
      _StatItem(
        icon: Icons.quiz,
        label: '已完成测验',
        value: '${_stats['quizCount'] ?? 0} 次',
        color: Colors.blue,
      ),
      _StatItem(
        icon: Icons.assignment,
        label: '已提交作业',
        value: '${_stats['homeworkCount'] ?? 0} 次',
        color: Colors.green,
      ),
      _StatItem(
        icon: Icons.science,
        label: '已完成实验',
        value: '${_stats['labCount'] ?? 0} 次',
        color: Colors.orange,
      ),
      _StatItem(
        icon: Icons.check_circle,
        label: '已掌握节点',
        value: '${_stats['masteredNodes'] ?? 0} 个',
        color: Colors.purple,
      ),
    ];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items.take(2).map((item) => _buildStatCard(theme, item)).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items.skip(2).map((item) => _buildStatCard(theme, item)).toList(),
        ),
      ],
    );
  }

  Widget _buildTeacherStats(ThemeData theme) {
    final items = [
      _StatItem(
        icon: Icons.people,
        label: '在册学生',
        value: '${_stats['studentCount'] ?? 0} 人',
        color: Colors.blue,
      ),
      _StatItem(
        icon: Icons.menu_book,
        label: '开设课程',
        value: '${_stats['courseCount'] ?? 0} 门',
        color: Colors.green,
      ),
      _StatItem(
        icon: Icons.pending_actions,
        label: '待批作业',
        value: '${_stats['pendingSubmissions'] ?? 0} 份',
        color: Colors.orange,
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) => _buildStatCard(theme, item)).toList(),
    );
  }

  Widget _buildStatCard(ThemeData theme, _StatItem item) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: item.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(item.icon, size: 20, color: item.color),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: item.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
