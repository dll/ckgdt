import 'package:flutter/material.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/homework_dao.dart';
import '../../../services/course_context_service.dart';

/// 退出成绩报告弹窗 — 显示学生/教师的成绩/教学报告
class LogoutReportDialog extends StatefulWidget {
  final String userId;
  final String userName;
  final String role;

  const LogoutReportDialog({
    super.key,
    required this.userId,
    required this.userName,
    required this.role,
  });

  /// 登出前调用此方法显示报告，返回 true 表示确认退出
  static Future<bool?> showBeforeLogout(
    BuildContext context, {
    required String userId,
    required String userName,
    required String role,
  }) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LogoutReportDialog(
        userId: userId,
        userName: userName,
        role: role,
      ),
    );
  }

  @override
  State<LogoutReportDialog> createState() => _LogoutReportDialogState();
}

class _LogoutReportDialogState extends State<LogoutReportDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _loading = true;
  Map<String, dynamic> _report = {};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _loadReport();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final ctx = CourseContextService();
      final courseId = await ctx.activeCourseId();

      if (widget.role == 'student') {
        // 学生端：成绩报告
        final quizResults = await db.rawQuery(
          "SELECT AVG(score * 100.0 / total_questions) as avg_score FROM quiz_results WHERE user_id = ? AND course_id = ?",
          [widget.userId, courseId],
        );
        final homeworkAvg = await HomeworkDao().getStudentHomeworkAverage(courseId, widget.userId);
        final labScores = await db.rawQuery(
          "SELECT AVG(score * 100.0 / max_score) as avg_score FROM lab_submissions WHERE user_id = ? AND score IS NOT NULL",
          [widget.userId],
        );
        final totalQuizzes = await db.rawQuery(
          "SELECT COUNT(*) as c FROM quiz_results WHERE user_id = ? AND course_id = ?",
          [widget.userId, courseId],
        );
        final totalHomework = await db.rawQuery(
          "SELECT COUNT(DISTINCT homework_id) as c FROM homework_submissions WHERE user_id = ?",
          [widget.userId],
        );

        final quizAvg = (quizResults.first['avg_score'] as num?)?.toDouble() ?? 0.0;
        final labAvg = (labScores.first['avg_score'] as num?)?.toDouble() ?? 0.0;

        // 综合成绩
        final overallScore = quizAvg * 0.3 + homeworkAvg * 0.3 + labAvg * 0.4;

        _report = {
          'quizAvg': quizAvg.toStringAsFixed(1),
          'homeworkAvg': homeworkAvg.toStringAsFixed(1),
          'labAvg': labAvg.toStringAsFixed(1),
          'overallScore': overallScore.toStringAsFixed(1),
          'totalQuizzes': (totalQuizzes.first['c'] as int?) ?? 0,
          'totalHomework': (totalHomework.first['c'] as int?) ?? 0,
          'level': _getLevel(overallScore),
          'levelColor': _getLevelColor(overallScore),
        };
      } else {
        // 教师端：教学报告
        final studentCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM users WHERE role = 'student' AND is_active = 1",
        );
        final quizAvg = await db.rawQuery(
          "SELECT AVG(score * 100.0 / total_questions) as avg_score FROM quiz_results WHERE course_id = ?",
          [courseId],
        );
        final pendingHomework = await db.rawQuery(
          "SELECT COUNT(*) as c FROM homework_submissions WHERE status = 'submitted'",
        );

        _report = {
          'studentCount': (studentCount.first['c'] as int?) ?? 0,
          'quizAvg': ((quizAvg.first['avg_score'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1),
          'pendingHomework': (pendingHomework.first['c'] as int?) ?? 0,
        };
      }
    } catch (e) {
      debugPrint('LogoutReport: load report error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
      _controller.forward();
    }
  }

  String _getLevel(double score) {
    if (score >= 85) return '优秀';
    if (score >= 70) return '良好';
    if (score >= 60) return '合格';
    return '需努力';
  }

  Color _getLevelColor(double score) {
    if (score >= 85) return Colors.green;
    if (score >= 70) return Colors.blue;
    if (score >= 60) return Colors.orange;
    return Colors.red;
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
              // 标题
              Icon(
                isStudent ? Icons.assessment : Icons.analytics,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                isStudent ? '学习报告' : '教学报告',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.userName,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),

              // 报告内容
              if (_loading)
                const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                isStudent ? _buildStudentReport(theme) : _buildTeacherReport(theme),

              const SizedBox(height: 20),

              // 按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('继续学习'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('确认退出'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentReport(ThemeData theme) {
    final overallScore = double.tryParse(_report['overallScore'] ?? '0') ?? 0;
    final level = _report['level'] ?? '需努力';
    final levelColor = _report['levelColor'] ?? Colors.red;

    return Column(
      children: [
        // 综合成绩
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                levelColor.withValues(alpha: 0.1),
                levelColor.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: levelColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                '$overallScore 分',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: levelColor,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  level,
                  style: TextStyle(
                    fontSize: 13,
                    color: levelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 各项成绩
        _buildScoreRow('测验平均分', _report['quizAvg'] ?? '0', Colors.blue),
        const SizedBox(height: 8),
        _buildScoreRow('作业平均分', _report['homeworkAvg'] ?? '0', Colors.green),
        const SizedBox(height: 8),
        _buildScoreRow('实验平均分', _report['labAvg'] ?? '0', Colors.orange),
        const SizedBox(height: 12),

        // 统计
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildMiniStat('完成测验', '${_report['totalQuizzes'] ?? 0} 次'),
            _buildMiniStat('提交作业', '${_report['totalHomework'] ?? 0} 次'),
          ],
        ),
      ],
    );
  }

  Widget _buildTeacherReport(ThemeData theme) {
    return Column(
      children: [
        _buildTeacherStatItem(
          Icons.people,
          '在册学生',
          '${_report['studentCount'] ?? 0} 人',
          Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildTeacherStatItem(
          Icons.quiz,
          '班级平均测验分',
          '${_report['quizAvg'] ?? '0'} 分',
          Colors.green,
        ),
        const SizedBox(height: 12),
        _buildTeacherStatItem(
          Icons.pending_actions,
          '待批作业',
          '${_report['pendingHomework'] ?? 0} 份',
          Colors.orange,
        ),
      ],
    );
  }

  Widget _buildScoreRow(String label, String score, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(
          '$score 分',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildTeacherStatItem(IconData icon, String label, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
