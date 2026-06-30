import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/error_handler.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/twin_service.dart';
import '../../../services/agent/agent_registry.dart';
import '../../../data/models/twin_profile_model.dart';
import '../../widgets/agent_chat_overlay.dart';
import '../../widgets/markdown_bubble.dart';

import '../../../core/constants/app_theme.dart';

/// 数字孪生仪表盘 — 教育教学数字镜像
///
/// 高保真、实时动态映射师生教学全过程。
/// 贯穿 教·学·练·评·研 五维，支撑精准教学与持续优化。
class VirtualTwinPage extends StatefulWidget {
  const VirtualTwinPage({super.key});

  @override
  State<VirtualTwinPage> createState() => _VirtualTwinPageState();
}

class _VirtualTwinPageState extends State<VirtualTwinPage>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  final _twinService = TwinService();

  bool get _isTeacher => _authService.isTeacher || _authService.isAdmin;
  // 数字孪生智能体为双模（学生/教师自动识别），注册 id 为 'digital_twin'。
  // 历史上这里误用了未注册的 'virtual_student'/'virtual_teacher'，导致 AI
  // 解读与深度对话静默失效（getAgent 返回 null）。
  static const String _agentId = 'digital_twin';

  StudentTwinProfile? _studentProfile;
  TeacherTwinProfile? _teacherProfile;
  bool _profileLoading = true;

  // AI 解读
  String _aiReply = '';
  bool _aiLoading = false;
  bool _aiExpanded = false;

  // 快捷交互
  String _quickReply = '';
  bool _quickLoading = false;
  String _quickTopic = '';

  late AnimationController _headerAnimCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _headerFade;

  List<String> _chapterNames = [];
  Color primary = const Color(0xFF1677FF);

  @override
  void initState() {
    super.initState();
    _headerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _loadChapterNames();
    _headerFade = CurvedAnimation(
      parent: _headerAnimCtrl,
      curve: Curves.easeInOut,
    );
    _loadProfile();
  }

  @override
  void dispose() {
    _headerAnimCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChapterNames() async {
    try {
      final ctx = CourseContextService();
      final titles = await ctx.shortChapterTitles();
      if (titles.isNotEmpty && mounted) {
        setState(() => _chapterNames = titles);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'VirtualTwinPage.loadChapterNames', stack: st);
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _profileLoading = true);
    try {
      final userId = _authService.currentUser?.userId ?? '';
      if (_isTeacher) {
        _teacherProfile = await _twinService.buildTeacherProfile(userId);
      } else {
        _studentProfile = await _twinService.buildStudentProfile(userId);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'VirtualTwinPage.loadProfile', stack: st);
    }
    if (mounted) {
      setState(() => _profileLoading = false);
      _headerAnimCtrl.forward();
    }
  }

  Future<void> _loadAiInsight() async {
    if (_aiLoading) return;
    setState(() {
      _aiLoading = true;
      _aiExpanded = true;
    });
    try {
      final registry = AgentRegistry.instance;
      if (!registry.isInitialized) registry.initialize();
      final agent = registry.getAgent(_agentId);
      if (agent != null) {
        final result = await agent.handleMessage(
          _isTeacher ? '教学仪表盘' : '查看我的状态',
          registry.session,
        );
        _aiReply = result.content;
      }
    } catch (e) {
      _aiReply = '加载失败：$e';
    }
    if (mounted) setState(() => _aiLoading = false);
  }

  Future<void> _quickChat(String topic, String prompt) async {
    if (_quickLoading) return;
    setState(() {
      _quickLoading = true;
      _quickTopic = topic;
      _quickReply = '';
    });
    try {
      final registry = AgentRegistry.instance;
      if (!registry.isInitialized) registry.initialize();
      final agent = registry.getAgent(_agentId);
      if (agent != null) {
        final result = await agent.handleMessage(prompt, registry.session);
        _quickReply = result.content;
      }
    } catch (e) {
      _quickReply = '请求失败：$e';
    }
    if (mounted) setState(() => _quickLoading = false);
  }

  // ── 问候语生成 ──
  String _getGreeting() {
    final hour = DateTime.now().hour;
    final name = _authService.currentUser?.realName ?? '';
    final prefix = name.isNotEmpty ? '$name，' : '';
    if (hour < 6) return '$prefix夜深了，注意休息';
    if (hour < 9) return '$prefix早上好！新的一天，加油';
    if (hour < 12) return '$prefix上午好！学习效率最佳时段';
    if (hour < 14) return '$prefix中午好！适当休息';
    if (hour < 18) return '$prefix下午好！继续保持';
    if (hour < 21) return '$prefix晚上好！';
    return '$prefix夜间学习注意用眼';
  }

  IconData _getTimeIcon() {
    final h = DateTime.now().hour;
    if (h < 6 || h >= 21) return Icons.nights_stay;
    if (h < 12) return Icons.wb_sunny;
    if (h < 14) return Icons.lunch_dining;
    return Icons.wb_twilight;
  }

  // ── 等级与晋级 ──
  Map<String, dynamic> _getLevelInfo() {
    if (_isTeacher) {
      return {
        'level': '教学导师',
        'icon': Icons.school,
        'color': Colors.deepPurple,
        'progress': 1.0,
        'next': '',
      };
    }
    final level = _studentProfile?.level ?? '入门';
    const levels = ['入门', '进阶', '熟练', '精通'];
    final idx = levels.indexOf(level).clamp(0, 3);
    final nextLevel = idx < 3 ? levels[idx + 1] : '';

    final p = _studentProfile ?? StudentTwinProfile.empty();
    final score =
        (p.quizAvg * 0.3 + p.labCompletionRate * 0.4 + p.conceptCoverage * 0.3)
            .clamp(0.0, 100.0);
    final thresholds = [0.0, 40.0, 60.0, 80.0, 100.0];
    final rangeStart = thresholds[idx];
    final rangeEnd = thresholds[idx + 1];
    final progress =
        ((score - rangeStart) / (rangeEnd - rangeStart)).clamp(0.0, 1.0);

    final colors = [Colors.grey, Colors.blue, Colors.green, Colors.amber];
    final icons = [
      Icons.emoji_events_outlined,
      Icons.trending_up,
      Icons.star_half,
      Icons.star,
    ];

    return {
      'level': level,
      'icon': icons[idx],
      'color': colors[idx],
      'progress': progress,
      'next': nextLevel,
      'score': score,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isTeacher ? '美德精灵 · 数字孪生' : '美德精灵 · 数字孪生'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新数据',
            onPressed: _loadProfile,
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: '深度对话',
            onPressed: () => AgentChatOverlay.show(context, agentId: _agentId),
          ),
        ],
      ),
      body: _profileLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ── 问候卡片 + 趋势摘要 ──
                    _buildGreetingCard(isDark),
                    const SizedBox(height: 12),

                    // ── Hero Header + 等级进度 ──
                    FadeTransition(
                      opacity: _headerFade,
                      child: _buildHeader(context, isDark),
                    ),
                    const SizedBox(height: 16),

                    // ── 指标卡片 ──
                    _buildStatCards(),
                    const SizedBox(height: 16),

                    // ── 数字生命体：身体隐喻 + 图谱健康 ──
                    _buildLifeTwinSection(isDark),
                    const SizedBox(height: 16),

                    // ── 风险/预警卡片 ──
                    _buildRiskSection(isDark),

                    // ── 快捷交互 ──
                    _buildQuickActions(isDark),
                    if (_quickReply.isNotEmpty || _quickLoading) ...[
                      const SizedBox(height: 12),
                      _buildQuickReplyCard(isDark),
                    ],
                    const SizedBox(height: 16),

                    // ── 章节掌握度 / 班级分布 ──
                    if (!_isTeacher)
                      _buildChapterMastery(isDark)
                    else
                      _buildClassDistribution(isDark),
                    const SizedBox(height: 16),

                    // ── 雷达图 ──
                    _buildRadarSection(isDark),
                    const SizedBox(height: 16),

                    // ── 学习热力图 / 教师参与度 ──
                    if (!_isTeacher) ...[
                      _buildHeatmap(isDark),
                      const SizedBox(height: 16),
                    ],

                    // ── 里程碑 / 教师预警列表 ──
                    if (!_isTeacher)
                      _buildMilestones(isDark)
                    else ...[
                      if (_teacherProfile?.alerts.isNotEmpty ?? false) ...[
                        _buildAlertsList(isDark),
                        const SizedBox(height: 16),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // ── 成长曲线 ──
                    if (!_isTeacher) ...[
                      _buildGrowthCurve(isDark),
                      const SizedBox(height: 16),
                    ],

                    // ── 教师薄弱节点 ──
                    if (_isTeacher &&
                        (_teacherProfile?.weakSpots.isNotEmpty ?? false)) ...[
                      _buildWeakSpots(),
                      const SizedBox(height: 16),
                    ],

                    // ── AI 深度解读 ──
                    _buildAiSection(isDark),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 问候卡片（含趋势摘要）
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGreetingCard(bool isDark) {
    final trend = _isTeacher ? _teacherProfile?.trend : _studentProfile?.trend;
    final pattern = _studentProfile?.learningPattern;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isDark
                ? [Colors.deepPurple.shade900, Colors.indigo.shade900]
                : [const Color(0xFFe8eaf6), const Color(0xFFede7f6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getTimeIcon(),
                    size: 20,
                    color:
                        isDark ? Colors.amber.shade200 : Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getGreeting(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 进度摘要
            Text(
              _getProgressSummary(),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            // 趋势变化
            if (trend != null && trend.summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up,
                        size: 14,
                        color: isDark ? Colors.greenAccent : Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      '趋势：${trend.summary}',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            isDark ? Colors.greenAccent : Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 学生学习模式标签
            if (!_isTeacher && pattern != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  _miniTag('${pattern.style}学习者', Icons.psychology, isDark),
                  if (pattern.streakDays > 0)
                    _miniTag('连续${pattern.streakDays}天',
                        Icons.local_fire_department, isDark),
                  if (pattern.activeDaysLast7 > 0)
                    _miniTag('周活${pattern.activeDaysLast7}天',
                        Icons.calendar_today, isDark),
                ],
              ),
            ],
            // 晋级提醒
            if (!_isTeacher) ...[
              const SizedBox(height: 8),
              _buildLevelHint(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniTag(String text, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: primary),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white70 : primary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _getProgressSummary() {
    if (_isTeacher) {
      final p = _teacherProfile ?? TeacherTwinProfile.empty();
      final parts = <String>[];
      if (p.pendingGrading > 0) parts.add('${p.pendingGrading}份待批阅');
      parts.add('均分${p.classAvg.toStringAsFixed(1)}');
      if (p.classEngagement > 0)
        parts.add('参与度${p.classEngagement.toStringAsFixed(0)}%');
      if (p.deadlineWarnings > 0) parts.add('${p.deadlineWarnings}个截止预警');
      return parts.join(' · ');
    }
    final p = _studentProfile ?? StudentTwinProfile.empty();
    final items = <String>[];
    if (p.quizAvg > 0) items.add('测验${p.quizAvg.toStringAsFixed(0)}分');
    if (p.labCompletionRate > 0) {
      items.add('实验${p.labCompletionRate.toStringAsFixed(0)}%');
    }
    if (p.conceptCoverage > 0) {
      items.add('覆盖${p.conceptCoverage.toStringAsFixed(0)}%');
    }
    if (p.studyMinutesTotal > 0) {
      items.add('累计${(p.studyMinutesTotal / 60).toStringAsFixed(1)}h');
    }
    return items.isEmpty ? '开始学习以解锁您的数字画像' : items.join(' · ');
  }

  Widget _buildLevelHint() {
    final info = _getLevelInfo();
    final next = info['next'] as String;
    if (next.isEmpty) {
      return Text(
        '已达最高等级「精通」',
        style: TextStyle(
            fontSize: 11,
            color: Colors.amber.shade700,
            fontWeight: FontWeight.w500),
      );
    }
    final progress = (info['progress'] as double);
    final pct = (progress * 100).toInt();
    return Row(
      children: [
        Icon(Icons.trending_up, size: 14, color: (info['color'] as Color)),
        const SizedBox(width: 4),
        Text(
          '距离「$next」还差 ${100 - pct}%',
          style: TextStyle(
              fontSize: 11,
              color: (info['color'] as Color),
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation(info['color'] as Color),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Hero Header
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, bool isDark) {
    final info = _getLevelInfo();
    final level = info['level'] as String;
    final levelColor = info['color'] as Color;
    final levelIcon = info['icon'] as IconData;
    final progress = info['progress'] as double;
    final riskLevel = _studentProfile?.riskLevel ?? 'healthy';

    // 风险状态指示色
    Color pulseColor = Colors.greenAccent;
    String statusText = '状态良好';
    if (_isTeacher) {
      final alerts = _teacherProfile?.alerts ?? [];
      if (alerts.length >= 5) {
        pulseColor = Colors.redAccent;
        statusText = '${alerts.length}个学生需关注';
      } else if (alerts.isNotEmpty) {
        pulseColor = Colors.orangeAccent;
        statusText = '${alerts.length}个轻微预警';
      } else {
        statusText = '班级状态良好';
      }
    } else {
      if (riskLevel == 'critical') {
        pulseColor = Colors.redAccent;
        statusText = '学习状态需关注';
      } else if (riskLevel == 'warning') {
        pulseColor = Colors.orangeAccent;
        statusText = '学习节奏可优化';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppGradientTheme.of(context).linearGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 头像 + 状态脉搏
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4), width: 2),
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  child: Text(
                    _isTeacher ? '🧑‍🏫' : '🧑‍🎓',
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              // 状态指示灯
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: pulseColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: pulseColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 姓名
          Text(
            _authService.currentUser?.realName ??
                _authService.currentUser?.userId ??
                '',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          // 状态文字
          Text(statusText,
              style: TextStyle(
                  fontSize: 11,
                  color: pulseColor,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          // 等级徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(levelIcon, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(level,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // 等级进度条
          if (!_isTeacher) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 指标卡片（增强版 — 含趋势箭头）
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatCards() {
    if (_isTeacher) {
      final p = _teacherProfile ?? TeacherTwinProfile.empty();
      return Row(
        children: [
          _statCard('班级人数', '${p.classSize}', Icons.people, Colors.blue),
          _statCard('班级均分', p.classAvg.toStringAsFixed(1), Icons.bar_chart,
              Colors.green,
              delta: p.trend?.quizAvgDelta),
          _statCard('待批阅', '${p.pendingGrading}', Icons.assignment_late,
              p.pendingGrading > 0 ? Colors.red : Colors.green),
          _statCard('参与度', '${p.classEngagement.toStringAsFixed(0)}%',
              Icons.group_work, Colors.orange),
        ],
      );
    }

    final p = _studentProfile ?? StudentTwinProfile.empty();
    return Row(
      children: [
        _statCard(
            '测验均分',
            p.quizAvg.toStringAsFixed(1),
            Icons.quiz,
            p.quizAvg >= 80
                ? Colors.green
                : (p.quizAvg >= 60 ? Colors.blue : Colors.red),
            delta: p.trend?.quizAvgDelta),
        _statCard('实验完成', '${p.labCompletionRate.toStringAsFixed(0)}%',
            Icons.science, Colors.green,
            delta: p.trend?.labRateDelta),
        _statCard('错题消化', '${p.wrongDigestRate.toStringAsFixed(0)}%',
            Icons.auto_fix_high, Colors.orange),
        _statCard('节点覆盖', '${p.conceptCoverage.toStringAsFixed(0)}%',
            Icons.account_tree, Colors.purple,
            delta: p.trend?.conceptCovDelta),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color,
      {double? delta}) {
    return Expanded(
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              // 趋势箭头
              if (delta != null && delta.abs() > 0.5)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      delta > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 10,
                      color: delta > 0 ? Colors.green : Colors.red,
                    ),
                    Text(
                      delta.abs().toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 9,
                        color: delta > 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 数字生命体：课程图谱 × 人体隐喻
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLifeTwinSection(bool isDark) {
    final organs = _buildLifeOrgans();
    final lifeScore = _lifeScore(organs);
    final lifeColor = _healthColor(lifeScore);
    final graphLabel = _isTeacher ? '课程图谱' : '我的图谱';
    final roleSubtitle = _isTeacher
        ? '把班级学习状态映射为课程生命体，快速发现教学器官的健康变化'
        : '把知识节点、学习连接和实践行为映射为个人课程生命体';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: lifeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.monitor_heart, color: lifeColor, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isTeacher ? '班级数字生命体' : '个人数字生命体',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        roleSubtitle,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => AgentChatOverlay.show(
                    context,
                    agentId: _agentId,
                    initialContext: _isTeacher
                        ? '请用适合语音朗读的方式，基于我的教师数字孪生画像，做一次班级课程生命体体检：先说生命指数，再说最健康的器官、最需要修复的器官和下一步教学动作。'
                        : '请用适合语音朗读的方式，基于我的学生数字孪生画像，做一次个人课程生命体体检：先说生命指数，再说最健康的器官、最需要修复的器官和今天学习动作。',
                  ),
                  icon: const Icon(Icons.mic, size: 16),
                  label: const Text('语音体检'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _vitalPill('生命指数', '${lifeScore.toStringAsFixed(0)}%',
                    Icons.favorite, lifeColor, isDark),
                _vitalPill(
                    graphLabel, _graphVitalText(), Icons.hub, primary, isDark),
                _vitalPill('健康状态', _healthText(lifeScore),
                    Icons.health_and_safety, lifeColor, isDark),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final body = _buildTwinBody(organs, isDark);
                final legend = _buildOrganLegend(organs, isDark);
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 260, child: body),
                      const SizedBox(width: 16),
                      Expanded(child: legend),
                    ],
                  );
                }
                return Column(
                  children: [
                    body,
                    const SizedBox(height: 12),
                    legend,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTwinBody(List<_TwinOrgan> organs, bool isDark) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        return Container(
          height: 260,
          decoration: BoxDecoration(
            color:
                isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
            ),
          ),
          child: CustomPaint(
            painter: _TwinBodyPainter(
              organs: organs,
              pulse: _pulseCtrl.value,
              isDark: isDark,
              primary: primary,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '节点是器官，连接是神经，数据变化形成健康体征',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrganLegend(List<_TwinOrgan> organs, bool isDark) {
    return Column(
      children: organs.map((organ) => _organRow(organ, isDark)).toList(),
    );
  }

  Widget _organRow(_TwinOrgan organ, bool isDark) {
    final color = _healthColor(organ.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(organ.icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        organ.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          organ.metaphor,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (organ.value / 100).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    organ.detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${organ.value.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _healthText(organ.value),
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _vitalPill(
      String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$label：$value',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<_TwinOrgan> _buildLifeOrgans() {
    if (_isTeacher) {
      final p = _teacherProfile ?? TeacherTwinProfile.empty();
      final nodeScore = _average(p.nodeCoverage.values);
      final riskControl =
          (100 - p.alerts.length * 8 - p.weakSpots.length * 6).clamp(0, 100);
      final feedback = (p.gradingTimeliness - p.pendingGrading * 1.5)
          .clamp(0, 100)
          .toDouble();
      return [
        _TwinOrgan(
          name: '大脑',
          metaphor: '课程图谱',
          detail: p.nodeCoverage.isEmpty
              ? '等待节点达成数据'
              : '图谱节点达成均值 ${nodeScore.toStringAsFixed(0)}%',
          value: nodeScore,
          icon: Icons.psychology,
        ),
        _TwinOrgan(
          name: '神经',
          metaphor: '师生连接',
          detail: '班级均分 ${p.classAvg.toStringAsFixed(1)}',
          value: p.classAvg.clamp(0, 100).toDouble(),
          icon: Icons.hub,
        ),
        _TwinOrgan(
          name: '心脏',
          metaphor: '班级活力',
          detail: '近7天参与度 ${p.classEngagement.toStringAsFixed(0)}%',
          value: p.classEngagement.clamp(0, 100).toDouble(),
          icon: Icons.favorite,
        ),
        _TwinOrgan(
          name: '双手',
          metaphor: '反馈批阅',
          detail:
              '待批 ${p.pendingGrading} 份，及时率 ${p.gradingTimeliness.toStringAsFixed(0)}%',
          value: feedback,
          icon: Icons.rate_review,
        ),
        _TwinOrgan(
          name: '骨骼',
          metaphor: '教学进度',
          detail: '大纲执行 ${p.teachingProgress.toStringAsFixed(0)}%',
          value: p.teachingProgress.clamp(0, 100).toDouble(),
          icon: Icons.account_tree,
        ),
        _TwinOrgan(
          name: '免疫',
          metaphor: '风险处置',
          detail: '${p.alerts.length} 个学生预警，${p.weakSpots.length} 个薄弱节点',
          value: riskControl.toDouble(),
          icon: Icons.health_and_safety,
        ),
      ];
    }

    final p = _studentProfile ?? StudentTwinProfile.empty();
    final chapterAvg = _average(p.chapterMastery.values);
    final activePulse =
        (p.learningPattern.activeDaysLast7 / 7 * 100).clamp(0, 100).toDouble();
    final connection = (chapterAvg * 0.45 +
            p.conceptCoverage * 0.35 +
            p.wrongDigestRate * 0.20)
        .clamp(0, 100)
        .toDouble();
    return [
      _TwinOrgan(
        name: '大脑',
        metaphor: '知识节点',
        detail: '概念覆盖 ${p.conceptCoverage.toStringAsFixed(0)}%',
        value: p.conceptCoverage.clamp(0, 100).toDouble(),
        icon: Icons.psychology,
      ),
      _TwinOrgan(
        name: '神经',
        metaphor: '图谱连接',
        detail: '章节掌握、覆盖与错题修复综合映射',
        value: connection,
        icon: Icons.hub,
      ),
      _TwinOrgan(
        name: '心脏',
        metaphor: '学习脉搏',
        detail: '近7天活跃 ${p.learningPattern.activeDaysLast7} 天',
        value: activePulse,
        icon: Icons.favorite,
      ),
      _TwinOrgan(
        name: '双手',
        metaphor: '实验实践',
        detail: '实验完成 ${p.labCompletionRate.toStringAsFixed(0)}%',
        value: p.labCompletionRate.clamp(0, 100).toDouble(),
        icon: Icons.science,
      ),
      _TwinOrgan(
        name: '骨骼',
        metaphor: '课程骨架',
        detail: p.chapterMastery.isEmpty
            ? '等待章节测验数据'
            : '章节掌握均值 ${chapterAvg.toStringAsFixed(0)}%',
        value: chapterAvg,
        icon: Icons.account_tree,
      ),
      _TwinOrgan(
        name: '免疫',
        metaphor: '错题修复',
        detail: '错题消化 ${p.wrongDigestRate.toStringAsFixed(0)}%',
        value: p.wrongDigestRate.clamp(0, 100).toDouble(),
        icon: Icons.auto_fix_high,
      ),
    ];
  }

  double _lifeScore(List<_TwinOrgan> organs) {
    if (organs.isEmpty) return 0;
    return organs.fold(0.0, (sum, organ) => sum + organ.value) / organs.length;
  }

  double _average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.fold(0.0, (sum, value) => sum + value) / list.length;
  }

  String _graphVitalText() {
    if (_isTeacher) {
      final p = _teacherProfile ?? TeacherTwinProfile.empty();
      return p.nodeCoverage.isEmpty ? '待采集' : '${p.nodeCoverage.length} 节点';
    }
    final p = _studentProfile ?? StudentTwinProfile.empty();
    return '覆盖 ${p.conceptCoverage.toStringAsFixed(0)}%';
  }

  String _healthText(double value) {
    if (value >= 85) return '强健';
    if (value >= 70) return '健康';
    if (value >= 45) return '待增强';
    if (value > 0) return '需修复';
    return '待唤醒';
  }

  Color _healthColor(double value) {
    if (value >= 85) return Colors.green;
    if (value >= 70) return Colors.teal;
    if (value >= 45) return Colors.orange;
    if (value > 0) return Colors.deepOrange;
    return Colors.grey;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 风险/预警区
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRiskSection(bool isDark) {
    if (!_isTeacher) {
      // 学生风险
      final risk = _studentProfile?.riskLevel ?? 'healthy';
      final reasons = _studentProfile?.riskReasons ?? [];
      if (risk == 'healthy' || reasons.isEmpty) return const SizedBox.shrink();

      final color = risk == 'critical' ? Colors.red : Colors.orange;
      final icon =
          risk == 'critical' ? Icons.error_outline : Icons.warning_amber;
      final title = risk == 'critical' ? '学习预警' : '学习提醒';

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          elevation: 1,
          color: color.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 6),
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ],
                ),
                const SizedBox(height: 6),
                ...reasons.map((r) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 5, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(r,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      );
    }

    // 教师端：显示截止预警 + 待批提醒
    final p = _teacherProfile ?? TeacherTwinProfile.empty();
    if (p.deadlineWarnings == 0 && p.pendingGrading == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 1,
        color: Colors.orange.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.notification_important,
                      size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text('教学提醒',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700)),
                ],
              ),
              const SizedBox(height: 6),
              if (p.deadlineWarnings > 0)
                _alertRow(
                    '${p.deadlineWarnings} 个实验任务即将截止（3天内）', Colors.red, isDark),
              if (p.pendingGrading > 0)
                _alertRow('${p.pendingGrading} 份报告待批阅', Colors.orange, isDark),
              if (p.gradingTimeliness < 70 && p.gradingTimeliness > 0)
                _alertRow(
                    '批阅及时率 ${p.gradingTimeliness.toStringAsFixed(0)}%，建议加快',
                    Colors.orange,
                    isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertRow(String text, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(Icons.circle, size: 5, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 快捷交互
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickActions(bool isDark) {
    final actions = _isTeacher
        ? [
            const _QuickAction('进度汇报', Icons.assessment, Colors.blue,
                '请汇报全班学习进度，包括成绩分布、薄弱环节和需要关注的学生'),
            const _QuickAction(
                '教学建议', Icons.lightbulb, Colors.amber, '根据当前班级数据，给出教学改进建议'),
            const _QuickAction('批阅提醒', Icons.notifications_active, Colors.red,
                '列出需要批阅的内容和优先级建议'),
            const _QuickAction('班级诊断', Icons.analytics, Colors.green,
                '分析班级整体表现趋势和优劣势，给出精准教学建议'),
          ]
        : [
            const _QuickAction(
                '今日计划', Icons.today, Colors.blue, '根据我的学习进度和薄弱环节，帮我制定今天的学习计划'),
            const _QuickAction('进度汇报', Icons.assessment, Colors.green,
                '汇报我的整体学习进度，包括各章节掌握度和趋势变化'),
            const _QuickAction('薄弱诊断', Icons.warning_amber, Colors.orange,
                '智能诊断我的薄弱知识点，给出针对性提升路径'),
            const _QuickAction('成长激励', Icons.favorite, Colors.pink,
                '根据我的进步情况和里程碑成就，给我继续学习的动力'),
          ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions
          .map((a) => ActionChip(
                avatar: Icon(a.icon, size: 16, color: a.color),
                label: Text(a.label, style: const TextStyle(fontSize: 12)),
                onPressed:
                    _quickLoading ? null : () => _quickChat(a.label, a.prompt),
                backgroundColor: a.color.withValues(alpha: 0.08),
                side: BorderSide(color: a.color.withValues(alpha: 0.2)),
              ))
          .toList(),
    );
  }

  Widget _buildQuickReplyCard(bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.indigo.shade900 : Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy,
                    size: 16,
                    color: isDark
                        ? Colors.indigo.shade200
                        : Colors.indigo.shade600),
                const SizedBox(width: 6),
                Text(
                  _quickTopic,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Colors.indigo.shade200
                        : Colors.indigo.shade700,
                  ),
                ),
                const Spacer(),
                if (!_quickLoading)
                  InkWell(
                    onTap: () => setState(() {
                      _quickReply = '';
                      _quickTopic = '';
                    }),
                    child: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_quickLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              MarkdownBubble(content: _quickReply, compact: true),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 章节掌握度（学生端）— 教学过程映射
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChapterMastery(bool isDark) {
    final mastery = _studentProfile?.chapterMastery ?? {};
    final resolved = _chapterNames.isNotEmpty
        ? _chapterNames
        : CourseContextService.defaultCourseChapters;
    final rowCount =
        mastery.length > resolved.length ? mastery.length : resolved.length;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book, size: 18, color: primary),
                const SizedBox(width: 6),
                Text('章节掌握度 · 知识骨架',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(rowCount, (i) {
              final ch = i + 1;
              final score = mastery[ch] ?? 0;
              final color = score >= 80
                  ? Colors.green
                  : score >= 60
                      ? Colors.blue
                      : score >= 40
                          ? Colors.orange
                          : Colors.red;
              final health = score >= 80
                  ? '健康'
                  : score >= 60
                      ? '良好'
                      : score >= 40
                          ? '需加强'
                          : score > 0
                              ? '薄弱'
                              : '未测验';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                          ch <= resolved.length ? resolved[ch - 1] : '第${ch}章',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.white60 : Colors.grey[600])),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (score / 100).clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor:
                              isDark ? Colors.white12 : Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Text(
                        score > 0 ? score.toStringAsFixed(0) : '-',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: color),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 40,
                      child: Text(health,
                          style: TextStyle(fontSize: 9, color: color),
                          textAlign: TextAlign.center),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              '章节是课程骨架，知识节点和学习记录会同步影响数字生命体健康状态',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 班级分布（教师端）— 心脏层
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildClassDistribution(bool isDark) {
    final dist = _teacherProfile?.classDistribution ?? {};
    final excellent = dist['excellent'] ?? 0;
    final good = dist['good'] ?? 0;
    final average = dist['average'] ?? 0;
    final atRisk = dist['atRisk'] ?? 0;
    final total = excellent + good + average + atRisk;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups, size: 18, color: primary),
                const SizedBox(width: 6),
                Text('班级分布 · 育人心脏',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
            const SizedBox(height: 12),
            if (total > 0) ...[
              // 分布条
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 20,
                  child: Row(
                    children: [
                      if (excellent > 0)
                        Flexible(
                          flex: excellent,
                          child: Container(color: Colors.green),
                        ),
                      if (good > 0)
                        Flexible(
                          flex: good,
                          child: Container(color: Colors.blue),
                        ),
                      if (average > 0)
                        Flexible(
                          flex: average,
                          child: Container(color: Colors.orange),
                        ),
                      if (atRisk > 0)
                        Flexible(
                          flex: atRisk,
                          child: Container(color: Colors.red),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _distItem('优秀≥85', excellent, Colors.green, total),
                  _distItem('良好≥70', good, Colors.blue, total),
                  _distItem('及格≥60', average, Colors.orange, total),
                  _distItem('预警<60', atRisk, Colors.red, total),
                ],
              ),
            ] else
              Text('暂无测验成绩数据',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _distItem(String label, int count, Color color, int total) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 2),
        Text('$count人',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        Text('$pct%', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 学习热力图（学生端）— 30天活跃度
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeatmap(bool isDark) {
    final activity = _studentProfile?.dailyActivity ?? [];
    if (activity.isEmpty) return const SizedBox.shrink();

    final maxVal =
        activity.fold(0.0, (m, v) => v > m ? v : m).clamp(1.0, double.infinity);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.grid_on, size: 18, color: primary),
                const SizedBox(width: 6),
                Text('学习热力图 · 近30天',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: Row(
                children: List.generate(
                  activity.length.clamp(0, 30),
                  (i) {
                    final val = activity[i];
                    final intensity = (val / maxVal).clamp(0.0, 1.0);
                    final color = val == 0
                        ? (isDark ? Colors.white10 : Colors.grey.shade200)
                        : Color.lerp(
                            Colors.green.shade100,
                            Colors.green.shade800,
                            intensity,
                          )!;
                    return Expanded(
                      child: Tooltip(
                        message: '${30 - i}天前：${val.toStringAsFixed(0)}分钟',
                        child: Container(
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('30天前',
                    style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                Row(
                  children: [
                    Text('少 ',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    ...List.generate(
                      4,
                      (i) => Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            Colors.green.shade100,
                            Colors.green.shade800,
                            i / 3,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(' 多',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                  ],
                ),
                Text('今天',
                    style: TextStyle(fontSize: 9, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 里程碑成就（学生端）
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMilestones(bool isDark) {
    final milestones = _studentProfile?.milestones ?? [];
    if (milestones.isEmpty) return const SizedBox.shrink();

    final achieved = milestones.where((m) => m.achieved).toList();
    final pending = milestones.where((m) => !m.achieved).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events,
                    size: 18, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                Text('里程碑成就',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
                const Spacer(),
                Text(
                  '${achieved.length}/${milestones.length}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade700,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...achieved.map((m) => _milestoneChip(m, true, isDark)),
                ...pending.map((m) => _milestoneChip(m, false, isDark)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _milestoneChip(Milestone m, bool achieved, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: achieved
            ? Colors.amber.withValues(alpha: 0.12)
            : (isDark ? Colors.white10 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: achieved
              ? Colors.amber.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(m.icon, style: TextStyle(fontSize: achieved ? 14 : 12)),
          const SizedBox(width: 4),
          Text(
            m.title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: achieved ? FontWeight.w600 : FontWeight.normal,
              color: achieved
                  ? (isDark ? Colors.amber.shade200 : Colors.amber.shade800)
                  : Colors.grey,
              decoration: achieved ? null : TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 学生预警列表（教师端）
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAlertsList(bool isDark) {
    final alerts = _teacherProfile?.alerts ?? [];
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: Colors.red.shade600),
                const SizedBox(width: 6),
                Text('学生预警 · 需关注',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
                const Spacer(),
                Text('${alerts.length}人',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ...alerts.take(8).map((a) {
              final typeIcon = a.alertType == 'inactive'
                  ? Icons.access_time
                  : a.alertType == 'low_score'
                      ? Icons.trending_down
                      : Icons.assignment_late;
              final typeColor = a.alertType == 'inactive'
                  ? Colors.orange
                  : a.alertType == 'low_score'
                      ? Colors.red
                      : Colors.deepOrange;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: typeColor.withValues(alpha: 0.1),
                  child: Icon(typeIcon, size: 14, color: typeColor),
                ),
                title: Text(a.realName.isNotEmpty ? a.realName : a.userId,
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(a.message,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 雷达图
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRadarSection(bool isDark) {
    Map<String, double> radar;
    if (_isTeacher) {
      final p = _teacherProfile ?? TeacherTwinProfile.empty();
      radar = {
        '知识传递': p.classAvg.clamp(0, 100),
        '实践转化': (p.nodeCoverage.length / 50 * 100).clamp(0, 100),
        '参与激发': p.classEngagement.clamp(0, 100),
        '批阅质量': p.gradingTimeliness.clamp(0, 100),
        '薄弱管控': p.weakSpots.isEmpty
            ? 100
            : ((1 - p.weakSpots.length / 10) * 100).clamp(0, 100),
      };
    } else {
      radar = (_studentProfile?.radar ?? {});
      if (radar.isEmpty) {
        radar = {
          '基础知识': 0,
          '实践能力': 0,
          '创新思维': 0,
          '学习韧性': 0,
          '学习速度': 0,
        };
      }
    }

    final labels = radar.keys.toList();
    final values = radar.values.toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar, size: 18, color: primary),
                const SizedBox(width: 6),
                Text(_isTeacher ? '教学效能雷达' : '能力雷达',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  dataSets: [
                    RadarDataSet(
                      dataEntries: values
                          .map((v) => RadarEntry(value: v.clamp(0, 100)))
                          .toList(),
                      fillColor: primary.withValues(alpha: 0.2),
                      borderColor: primary,
                      borderWidth: 2,
                    ),
                  ],
                  getTitle: (index, angle) => RadarChartTitle(
                    text: labels[index % labels.length],
                    angle: 0,
                  ),
                  titleTextStyle: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black54),
                  tickCount: 4,
                  ticksTextStyle: const TextStyle(fontSize: 0),
                  tickBorderData: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  gridBorderData: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  radarBorderData: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 成长曲线
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGrowthCurve(bool isDark) {
    final weekly = _studentProfile?.weeklyMinutes ?? [];
    if (weekly.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.show_chart, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Text('暂无学习时长数据，开始学习以解锁成长曲线',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, size: 18, color: primary),
                const SizedBox(width: 6),
                Text('成长曲线 · 近8周学习时长',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: isDark ? Colors.white10 : Colors.black12,
                      strokeWidth: 1,
                    ),
                    drawVerticalLine: false,
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => Text(
                          'W${value.toInt() + 1}',
                          style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: weekly
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      color: primary,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: primary.withValues(alpha: 0.1),
                      ),
                      dotData: const FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 薄弱节点（教师端）
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWeakSpots() {
    final spots = _teacherProfile?.weakSpots ?? [];
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber,
                    size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                const Text('薄弱节点 Top 5',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ...spots.map((s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: s.avgScore >= 60
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                    child: Text(
                      s.avgScore.toStringAsFixed(0),
                      style: TextStyle(
                          fontSize: 11,
                          color: s.avgScore >= 60 ? Colors.orange : Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title:
                      Text(s.nodeTitle, style: const TextStyle(fontSize: 13)),
                )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI 深度解读
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAiSection(bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.psychology, color: primary),
            title: const Text('AI 智能诊断',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle:
                const Text('基于全量数据的深度分析与个性化建议', style: TextStyle(fontSize: 11)),
            trailing: Icon(_aiExpanded
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down),
            onTap: () {
              if (!_aiExpanded && _aiReply.isEmpty) {
                _loadAiInsight();
              } else {
                setState(() => _aiExpanded = !_aiExpanded);
              }
            },
          ),
          if (_aiExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _aiLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _aiReply.isEmpty
                      ? Text('点击展开获取 AI 智能诊断',
                          style: TextStyle(color: Colors.grey[500]))
                      : MarkdownBubble(content: _aiReply, compact: true),
            ),
        ],
      ),
    );
  }
}

/// 快捷交互按钮模型
class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final String prompt;
  const _QuickAction(this.label, this.icon, this.color, this.prompt);
}

class _TwinOrgan {
  final String name;
  final String metaphor;
  final String detail;
  final double value;
  final IconData icon;

  const _TwinOrgan({
    required this.name,
    required this.metaphor,
    required this.detail,
    required this.value,
    required this.icon,
  });
}

class _TwinBodyPainter extends CustomPainter {
  final List<_TwinOrgan> organs;
  final double pulse;
  final bool isDark;
  final Color primary;

  const _TwinBodyPainter({
    required this.organs,
    required this.pulse,
    required this.isDark,
    required this.primary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final nervePaint = Paint()
      ..color = primary.withValues(alpha: 0.22 + pulse * 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height * 0.46);

    final head = Offset(size.width * 0.5, size.height * 0.17);
    final chest = Offset(size.width * 0.5, size.height * 0.34);
    final leftHand = Offset(size.width * 0.28, size.height * 0.43);
    final rightHand = Offset(size.width * 0.72, size.height * 0.43);
    final pelvis = Offset(size.width * 0.5, size.height * 0.66);
    final leftFoot = Offset(size.width * 0.36, size.height * 0.84);
    final rightFoot = Offset(size.width * 0.64, size.height * 0.84);

    canvas
      ..drawCircle(head, size.width * 0.085, bodyPaint)
      ..drawLine(
          Offset(size.width * 0.5, size.height * 0.25), pelvis, bodyPaint)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: size.width * 0.26,
            height: size.height * 0.34,
          ),
          const Radius.circular(26),
        ),
        bodyPaint,
      )
      ..drawLine(chest, leftHand, bodyPaint)
      ..drawLine(chest, rightHand, bodyPaint)
      ..drawLine(pelvis, leftFoot, bodyPaint)
      ..drawLine(pelvis, rightFoot, bodyPaint);

    final organPositions = [
      head,
      Offset(size.width * 0.5, size.height * 0.27),
      Offset(size.width * 0.5, size.height * 0.39),
      leftHand,
      Offset(size.width * 0.5, size.height * 0.61),
      Offset(size.width * 0.5, size.height * 0.51),
    ];

    for (var i = 0; i < organPositions.length; i++) {
      final from = i == 0 ? chest : organPositions[i];
      final to = i == 0 ? organPositions[i] : chest;
      canvas.drawLine(from, to, nervePaint);
    }

    _drawGraphHalo(canvas, size, head, nervePaint);

    for (var i = 0; i < organPositions.length && i < organs.length; i++) {
      _drawOrgan(canvas, organPositions[i], organs[i], i);
    }
  }

  void _drawGraphHalo(Canvas canvas, Size size, Offset anchor, Paint paint) {
    final nodes = [
      anchor + Offset(-size.width * 0.17, size.height * 0.02),
      anchor + Offset(size.width * 0.17, size.height * 0.02),
      anchor + Offset(-size.width * 0.11, -size.height * 0.10),
      anchor + Offset(size.width * 0.11, -size.height * 0.10),
      anchor + Offset(0, -size.height * 0.14),
    ];
    for (var i = 0; i < nodes.length; i++) {
      canvas.drawLine(anchor, nodes[i], paint);
      canvas.drawCircle(
        nodes[i],
        3.5 + pulse * 1.5,
        Paint()
          ..color = primary.withValues(alpha: 0.28 + pulse * 0.18)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawOrgan(Canvas canvas, Offset center, _TwinOrgan organ, int index) {
    final color = _organColor(organ.value);
    final radius = 11.0 + organ.value.clamp(0, 100) / 100 * 7 + pulse * 2;
    final fill = Paint()
      ..color = color.withValues(alpha: 0.20 + pulse * 0.10)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas
      ..drawCircle(center, radius + 5, fill)
      ..drawCircle(center, radius, stroke)
      ..drawArc(
        Rect.fromCircle(center: center, radius: radius + 3),
        -1.57,
        6.28 * (organ.value / 100).clamp(0.0, 1.0),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );

    final textPainter = TextPainter(
      text: TextSpan(
        text: organ.name,
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 42);
    textPainter.paint(
      canvas,
      center.translate(-textPainter.width / 2, radius + 8),
    );
  }

  Color _organColor(double value) {
    if (value >= 85) return Colors.green;
    if (value >= 70) return Colors.teal;
    if (value >= 45) return Colors.orange;
    if (value > 0) return Colors.deepOrange;
    return Colors.grey;
  }

  @override
  bool shouldRepaint(covariant _TwinBodyPainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.organs != organs ||
        oldDelegate.isDark != isDark ||
        oldDelegate.primary != primary;
  }
}
