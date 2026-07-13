import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/active_student_scope.dart';
import '../../../services/course_context_service.dart';
import '../../../services/course_terminology_service.dart';
import '../../../services/twin_service.dart';
import '../../../data/models/twin_profile_model.dart';

/// 登录进度弹窗 — 数字孪生3维画像 + 学习/教学进度概览
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
  late Animation<double> _fadeAnim;
  late Animation<double> _radarAnim;
  bool _loading = true;
  Map<String, dynamic> _stats = {};
  StudentTwinProfile? _studentProfile;
  CourseTerms? _terms;
  TeacherTwinProfile? _teacherProfile;

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
    _loadData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final ctx = CourseContextService();
      final courseId = await ctx.activeCourseId();
      final twinService = TwinService();
      _terms = await CourseTerminologyService().activeTerms();

      if (widget.role == 'student') {
        // 数字孪生画像
        _studentProfile = await twinService.buildStudentProfile(widget.userId);

        // 额外统计
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
        final masteredNodes = await db.rawQuery(
          "SELECT COUNT(*) as c FROM concept_progress WHERE user_id = ? AND status = 'mastered'",
          [widget.userId],
        );

        _stats = {
          'quizCount': (quizCount.first['c'] as int?) ?? 0,
          'homeworkCount': (homeworkCount.first['c'] as int?) ?? 0,
          'labCount': (labCount.first['c'] as int?) ?? 0,
          'masteredNodes': (masteredNodes.first['c'] as int?) ?? 0,
        };
      } else {
        // 教师数字孪生画像
        _teacherProfile = await twinService.buildTeacherProfile(widget.userId);

        final activeWhere = ActiveStudentScope.where();
        final studentCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM users u WHERE $activeWhere",
        );
        final courseCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM courses WHERE is_active = 1",
        );
        final pendingSubmissions = await db.rawQuery(
          "SELECT COUNT(*) as c FROM homework_submissions WHERE status = 'submitted'",
        );
        final quizAvg = await db.rawQuery(
          "SELECT AVG(score * 100.0 / total_questions) as avg_score FROM quiz_results WHERE course_id = ?",
          [courseId],
        );

        _stats = {
          'studentCount': (studentCount.first['c'] as int?) ?? 0,
          'courseCount': (courseCount.first['c'] as int?) ?? 0,
          'pendingSubmissions': (pendingSubmissions.first['c'] as int?) ?? 0,
          'quizAvg':
              ((quizAvg.first['avg_score'] as num?)?.toDouble() ?? 0.0)
                  .toStringAsFixed(1),
        };
      }
    } catch (e, st) {
      debugPrint('LoginProgress: load data error: $e\n$st');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStudent = widget.role == 'student';
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 12
            ? '上午好'
            : hour < 14
                ? '中午好'
                : hour < 18
                    ? '下午好'
                    : '晚上好';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 头部：头像 + 名字 + 角色 ──
              _buildHeader(theme, isStudent, greeting),
              const SizedBox(height: 16),

              // ── 数字孪生雷达 ──
              if (_loading)
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '正在加载学习画像',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '分析个人数据中，请稍候...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (isStudent && _studentProfile != null)
                _buildStudentRadar(_studentProfile!)
              else if (!isStudent && _teacherProfile != null)
                _buildTeacherRadar(_teacherProfile!)
              else
                const SizedBox(height: 160, child: Center(child: Text('加载中...'))),

              const SizedBox(height: 12),

              // ── 关键指标 ──
              if (!_loading)
                isStudent
                    ? _buildStudentMetrics(theme)
                    : _buildTeacherMetrics(theme),

              const SizedBox(height: 16),

              // ── 进入按钮 ──
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isStudent ? '进入学习' : '进入教学',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isStudent, String greeting) {
    final roleColor = isStudent ? Colors.blue : Colors.orange;
    final roleLabel = isStudent ? '学生' : '教师';
    final icon = isStudent ? Icons.school : Icons.person;

    return Column(
      children: [
        // 带光晕的头像
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                roleColor.withOpacity(0.3),
                roleColor.withOpacity(0.1),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: roleColor.withOpacity(0.3),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [roleColor, roleColor.withOpacity(0.7)],
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$greeting，',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 2),
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
            color: roleColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: roleColor.withOpacity(0.3)),
          ),
          child: Text(
            roleLabel,
            style: TextStyle(
              fontSize: 11,
              color: roleColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 学生端：5维雷达 + 详细指标
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudentRadar(StudentTwinProfile profile) {
    final radar = profile.radar;
    final keys = ['基础知识', '实践能力', '创新思维', '学习韧性', '学习速度'];
    final values = keys.map((k) => (radar[k] ?? 0) / 100).toList();

    return AnimatedBuilder(
      animation: _radarAnim,
      builder: (context, child) {
        return SizedBox(
          height: 160,
          child: RadarChart(
            RadarChartData(
              radarTouchData: RadarTouchData(enabled: false),
              radarBorderData: const BorderSide(color: Colors.transparent),
              gridBorderData: BorderSide(
                color: Colors.grey.withOpacity(0.15),
              ),
              titlePositionPercentageOffset: 0.12,
              titleTextStyle: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
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
                      .map((v) => RadarEntry(
                            value: v * _radarAnim.value,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentMetrics(ThemeData theme) {
    final profile = _studentProfile!;
    final level = profile.level;
    final levelColor = _getLevelColor(level);
    final pattern = profile.learningPattern;

    return Column(
      children: [
        // 等级 + 风险
        Row(
          children: [
            _buildMetricChip(
              icon: Icons.emoji_events,
              label: level,
              color: levelColor,
            ),
            const SizedBox(width: 6),
            _buildMetricChip(
              icon: _getRiskIcon(profile.riskLevel),
              label: _getRiskLabel(profile.riskLevel),
              color: _getRiskColor(profile.riskLevel),
            ),
            const SizedBox(width: 6),
            _buildMetricChip(
              icon: Icons.local_fire_department,
              label: '${profile.learningPattern.streakDays}天连学',
              color: profile.learningPattern.streakDays > 0
                  ? Colors.orange
                  : Colors.grey,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 4项核心指标
        Row(
          children: [
            _buildMetricCard(
              '测验均分',
              '${profile.quizAvg.toStringAsFixed(0)}分',
              Icons.quiz,
              Colors.blue,
            ),
            const SizedBox(width: 6),
            _buildMetricCard(
              '${_terms?.practiceLabel ?? '实验'}完成',
              '${profile.labCompletionRate.toStringAsFixed(0)}%',
              Icons.science,
              Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _buildMetricCard(
              '错题消化',
              '${profile.wrongDigestRate.toStringAsFixed(0)}%',
              Icons.check_circle,
              Colors.orange,
            ),
            const SizedBox(width: 6),
            _buildMetricCard(
              '概念覆盖',
              '${profile.conceptCoverage.toStringAsFixed(0)}%',
              Icons.hub,
              Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 学习风格
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.psychology, size: 16, color: Colors.blue.shade400),
              const SizedBox(width: 6),
              Text(
                '学习风格：${pattern.style}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const Spacer(),
              if (pattern.activeDaysLast7 > 0)
                Text(
                  '近7天活跃${pattern.activeDaysLast7}天',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 教师端：5维雷达 + 教学概览
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
          height: 160,
          child: RadarChart(
            RadarChartData(
              radarTouchData: RadarTouchData(enabled: false),
              radarBorderData: const BorderSide(color: Colors.transparent),
              gridBorderData: BorderSide(
                color: Colors.grey.withOpacity(0.15),
              ),
              titlePositionPercentageOffset: 0.12,
              titleTextStyle: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
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
                      .map((v) => RadarEntry(
                            value: v * _radarAnim.value,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeacherMetrics(ThemeData theme) {
    return Column(
      children: [
        Row(
          children: [
            _buildMetricCard(
              '在册学生',
              '${_stats['studentCount'] ?? 0}人',
              Icons.people,
              Colors.blue,
            ),
            const SizedBox(width: 6),
            _buildMetricCard(
              '开设课程',
              '${_stats['courseCount'] ?? 0}门',
              Icons.menu_book,
              Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _buildMetricCard(
              '班级均分',
              '${_stats['quizAvg'] ?? '0'}分',
              Icons.analytics,
              Colors.purple,
            ),
            const SizedBox(width: 6),
            _buildMetricCard(
              '待批作业',
              '${_stats['pendingSubmissions'] ?? 0}份',
              Icons.pending_actions,
              Colors.orange,
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 通用组件
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetricCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case '精通':
        return Colors.green;
      case '熟练':
        return Colors.blue;
      case '进阶':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getRiskLabel(String risk) {
    switch (risk) {
      case 'critical':
        return '需关注';
      case 'warning':
        return '注意';
      default:
        return '健康';
    }
  }

  Color _getRiskColor(String risk) {
    switch (risk) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  IconData _getRiskIcon(String risk) {
    switch (risk) {
      case 'critical':
        return Icons.warning;
      case 'warning':
        return Icons.info;
      default:
        return Icons.health_and_safety;
    }
  }
}
