import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/active_student_scope.dart';
import '../../../data/local/homework_dao.dart';
import '../../../services/course_context_service.dart';
import '../../../services/course_terminology_service.dart';
import '../../../services/twin_service.dart';
import '../../../data/models/twin_profile_model.dart';

/// 退出报告弹窗 — 数字孪生3维画像 + 成绩/教学总结
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
  late Animation<double> _fadeAnim;
  late Animation<double> _radarAnim;
  bool _loading = true;
  Map<String, dynamic> _report = {};
  StudentTwinProfile? _studentProfile;
  TeacherTwinProfile? _teacherProfile;
  CourseTerms? _terms;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _radarAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    // 立即启动动画，让加载指示器可见
    _controller.forward();
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
      final twinService = TwinService();
      _terms = await CourseTerminologyService().activeTerms();

      if (widget.role == 'student') {
        // 数字孪生画像
        _studentProfile = await twinService.buildStudentProfile(widget.userId);

        // 成绩数据
        final quizResults = await db.rawQuery(
          "SELECT AVG(score * 100.0 / total_questions) as avg_score FROM quiz_results WHERE user_id = ? AND course_id = ?",
          [widget.userId, courseId],
        );
        final homeworkAvg =
            await HomeworkDao().getStudentHomeworkAverage(courseId, widget.userId);
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
        final totalLabs = await db.rawQuery(
          "SELECT COUNT(*) as c FROM lab_submissions WHERE user_id = ?",
          [widget.userId],
        );

        final quizAvg = (quizResults.first['avg_score'] as num?)?.toDouble() ?? 0.0;
        final labAvg = (labScores.first['avg_score'] as num?)?.toDouble() ?? 0.0;
        final overallScore = quizAvg * 0.3 + homeworkAvg * 0.3 + labAvg * 0.4;

        _report = {
          'quizAvg': quizAvg.toStringAsFixed(1),
          'homeworkAvg': homeworkAvg.toStringAsFixed(1),
          'labAvg': labAvg.toStringAsFixed(1),
          'overallScore': overallScore.toStringAsFixed(1),
          'totalQuizzes': (totalQuizzes.first['c'] as int?) ?? 0,
          'totalHomework': (totalHomework.first['c'] as int?) ?? 0,
          'totalLabs': (totalLabs.first['c'] as int?) ?? 0,
          'level': _getLevel(overallScore),
          'levelColor': _getLevelColor(overallScore),
        };
      } else {
        // 教师数字孪生画像
        _teacherProfile = await twinService.buildTeacherProfile(widget.userId);

        final activeWhere = ActiveStudentScope.where();
        final studentCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM users u WHERE $activeWhere",
        );
        final quizAvg = await db.rawQuery(
          "SELECT AVG(score * 100.0 / total_questions) as avg_score FROM quiz_results WHERE course_id = ?",
          [courseId],
        );
        final pendingHomework = await db.rawQuery(
          "SELECT COUNT(*) as c FROM homework_submissions WHERE status = 'submitted'",
        );
        final totalCourses = await db.rawQuery(
          "SELECT COUNT(*) as c FROM courses WHERE is_active = 1",
        );

        _report = {
          'studentCount': (studentCount.first['c'] as int?) ?? 0,
          'quizAvg':
              ((quizAvg.first['avg_score'] as num?)?.toDouble() ?? 0.0)
                  .toStringAsFixed(1),
          'pendingHomework': (pendingHomework.first['c'] as int?) ?? 0,
          'totalCourses': (totalCourses.first['c'] as int?) ?? 0,
        };
      }
    } catch (e, st) {
      debugPrint('LogoutReport: load report error: $e\n$st');
    }

    if (mounted) {
      setState(() => _loading = false);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(28),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 标题 ──
                _buildHeader(theme, isStudent),
                const SizedBox(height: 20),

                // ── 数字孪生雷达 ──
                if (_loading)
                  SizedBox(
                    height: 220,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '正在生成学习报告',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '分析学习数据中，请稍候...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '成绩统计 · 知识画像 · 能力雷达',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (isStudent && _studentProfile != null)
                  _buildStudentRadar(_studentProfile!)
                else if (!isStudent && _teacherProfile != null)
                  _buildTeacherRadar(_teacherProfile!),

                const SizedBox(height: 20),

                // ── 详细报告 ──
                if (!_loading)
                  isStudent
                      ? _buildStudentReport(theme)
                      : _buildTeacherReport(theme),

                const SizedBox(height: 24),

                // ── 按钮 ──
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('继续学习'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isStudent) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withOpacity(0.6),
              ],
            ),
          ),
          child: Icon(
            isStudent ? Icons.assessment : Icons.analytics,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isStudent ? '学习报告' : '教学报告',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          widget.userName,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 学生端
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudentRadar(StudentTwinProfile profile) {
    final radar = profile.radar;
    final keys = ['基础知识', '实践能力', '创新思维', '学习韧性', '学习速度'];
    final values = keys.map((k) => (radar[k] ?? 0) / 100).toList();

    return AnimatedBuilder(
      animation: _radarAnim,
      builder: (context, child) {
        return SizedBox(
          height: 180,
          child: RadarChart(
            RadarChartData(
              radarTouchData: RadarTouchData(enabled: false),
              radarBorderData: const BorderSide(color: Colors.transparent),
              gridBorderData: BorderSide(
                color: Colors.grey.withOpacity(0.15),
              ),
              titlePositionPercentageOffset: 0.12,
              titleTextStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              radarShape: RadarShape.polygon,
              getTitle: (index, angle) => RadarChartTitle(
                text: keys[index],
                angle: 0,
              ),
              dataSets: [
                RadarDataSet(
                  fillColor: Colors.blue.withOpacity(0.15),
                  borderColor: Colors.blue,
                  borderWidth: 2,
                  entryRadius: 4,
                  dataEntries: values
                      .map((v) => RadarEntry(value: v * _radarAnim.value))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentReport(ThemeData theme) {
    final overallScore = double.tryParse(_report['overallScore'] ?? '0') ?? 0;
    final level = _report['level'] ?? '需努力';
    final levelColor = _report['levelColor'] as Color? ?? Colors.red;

    return Column(
      children: [
        // 综合成绩大卡片
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                levelColor.withOpacity(0.12),
                levelColor.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: levelColor.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text(
                '$overallScore',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: levelColor,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: levelColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
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

        // 各项成绩进度条
        _buildScoreProgressBar('测验平均分', _report['quizAvg'] ?? '0', 0.3, Colors.blue),
        const SizedBox(height: 10),
        _buildScoreProgressBar('作业平均分', _report['homeworkAvg'] ?? '0', 0.3, Colors.green),
        const SizedBox(height: 10),
        _buildScoreProgressBar('${_terms?.practiceLabel ?? '实验'}平均分', _report['labAvg'] ?? '0', 0.4, Colors.orange),
        const SizedBox(height: 16),

        // 统计数据
        Row(
          children: [
            _buildMiniStat(Icons.quiz, '测验', '${_report['totalQuizzes'] ?? 0}次'),
            _buildMiniStat(Icons.assignment, '作业', '${_report['totalHomework'] ?? 0}次'),
            _buildMiniStat(Icons.science, _terms?.practiceLabel ?? '实验', '${_report['totalLabs'] ?? 0}次'),
          ],
        ),
      ],
    );
  }

  Widget _buildScoreProgressBar(String label, String score, double weight, Color color) {
    final scoreVal = double.tryParse(score) ?? 0;
    final weightPct = (weight * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
            Text(
              '$score 分',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '权重$weightPct%',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: scoreVal / 100,
            minHeight: 6,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 教师端
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTeacherRadar(TeacherTwinProfile profile) {
    final keys = ['教学进度', '班级均分', '学生参与', '批阅及时', '节点覆盖'];
    final nodeAvg = profile.nodeCoverage.isEmpty
        ? 0.0
        : profile.nodeCoverage.values.reduce((a, b) => a + b) / profile.nodeCoverage.length;
    final values = [
      profile.teachingProgress.clamp(0, 100),
      profile.classAvg.clamp(0, 100),
      profile.classEngagement.clamp(0, 100),
      profile.gradingTimeliness.clamp(0, 100),
      nodeAvg.clamp(0, 100),
    ];

    return AnimatedBuilder(
      animation: _radarAnim,
      builder: (context, child) {
        return SizedBox(
          height: 180,
          child: RadarChart(
            RadarChartData(
              radarTouchData: RadarTouchData(enabled: false),
              radarBorderData: const BorderSide(color: Colors.transparent),
              gridBorderData: BorderSide(
                color: Colors.grey.withOpacity(0.15),
              ),
              titlePositionPercentageOffset: 0.12,
              titleTextStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              radarShape: RadarShape.polygon,
              getTitle: (index, angle) => RadarChartTitle(
                text: keys[index],
                angle: 0,
              ),
              dataSets: [
                RadarDataSet(
                  fillColor: Colors.orange.withOpacity(0.15),
                  borderColor: Colors.orange,
                  borderWidth: 2,
                  entryRadius: 4,
                  dataEntries: values
                      .map((v) => RadarEntry(value: v * _radarAnim.value))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeacherReport(ThemeData theme) {
    return Column(
      children: [
        // 3项核心数据
        Row(
          children: [
            _buildTeacherMetricCard(
              '在册学生',
              '${_report['studentCount'] ?? 0}',
              '人',
              Icons.people,
              Colors.blue,
            ),
            const SizedBox(width: 10),
            _buildTeacherMetricCard(
              '班级均分',
              '${_report['quizAvg'] ?? '0'}',
              '分',
              Icons.analytics,
              Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildTeacherMetricCard(
              '待批作业',
              '${_report['pendingHomework'] ?? 0}',
              '份',
              Icons.pending_actions,
              Colors.orange,
            ),
            const SizedBox(width: 10),
            _buildTeacherMetricCard(
              '开设课程',
              '${_report['totalCourses'] ?? 0}',
              '门',
              Icons.menu_book,
              Colors.purple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTeacherMetricCard(
    String label, String value, String unit, IconData icon, Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
