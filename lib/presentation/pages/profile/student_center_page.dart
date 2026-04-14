import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../core/constants/app_theme.dart';
import '../quiz/wrong_answers_page.dart';
import '../graph/favorites_page.dart';
import '../learning/learning_plan_page.dart';
import '../learning/progress_page.dart';
import '../learning/weakness_diagnosis_page.dart';
import '../learning/student_lab_page.dart';
import '../lab/productization_guide_page.dart';

class StudentCenterPage extends StatefulWidget {
  const StudentCenterPage({super.key});

  @override
  State<StudentCenterPage> createState() => _StudentCenterPageState();
}

class _StudentCenterPageState extends State<StudentCenterPage> {
  final _authService = AuthService();
  final _quizDao = QuizDao();
  final _learningRecordDao = LearningRecordDao();

  bool _isLoading = true;

  // 学习概览数据
  int _learnedNodes = 0;
  int _quizCount = 0;
  double _avgScore = 0.0;
  int _learningDays = 0;

  // 成长轨迹数据
  List<Map<String, dynamic>> _recentRecords = [];

  // 成就数据
  int _achievementLevel = 0; // 0-4 对应 5 个等级

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final userId = user.userId;

        // 加载学习统计
        final learningStats = await _learningRecordDao.getStatistics(userId);
        final quizSummary = await _quizDao.getQuizSummary(userId);

        // 加载成长轨迹（最近学习记录）
        final records = await _learningRecordDao.getRecords(userId);

        // 计算学习天数（从学习记录中提取不同日期的数量）
        final daySet = <String>{};
        for (final record in records) {
          final completedAt = record['completed_at'] as String?;
          if (completedAt != null && completedAt.length >= 10) {
            daySet.add(completedAt.substring(0, 10));
          }
        }

        // 计算成就等级（基于平均分）
        final avgScore = (quizSummary['avg_score'] ?? 0).toDouble();
        int level = 0;
        if (avgScore >= 80) {
          level = 4;
        } else if (avgScore >= 60) {
          level = 3;
        } else if (avgScore >= 40) {
          level = 2;
        } else if (avgScore >= 20) {
          level = 1;
        }

        setState(() {
          _learnedNodes = (learningStats['unique_nodes'] as int?) ?? 0;
          _quizCount = (quizSummary['total_count'] as int?) ?? 0;
          _avgScore = avgScore;
          _learningDays = daySet.length;
          _recentRecords = records.take(10).toList();
          _achievementLevel = level;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
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
        title: const Text('我的学习中心'),
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
              const SizedBox(height: 16),

              // ── 学习概览 ──────────────────────────────────────────────
              const Text(
                '学习概览',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildOverviewStats(),
              const SizedBox(height: 16),

              // ── 成长轨迹 ──────────────────────────────────────────────
              const Text(
                '成长轨迹',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildGrowthTimeline(),
              const SizedBox(height: 16),

              // ── 学习成就 ──────────────────────────────────────────────
              const Text(
                '学习成就',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildAchievementBadges(),
              const SizedBox(height: 16),

              // ── 快捷入口 ──────────────────────────────────────────────
              const Text(
                '快捷入口',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildQuickActions(),
              const SizedBox(height: 16),
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
    final roleName = user?.role == 'admin'
        ? '管理员'
        : user?.role == 'teacher'
            ? '教师'
            : '学生';
    final displayName = user?.realName ?? user?.userId ?? '同学';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: gradient.linearGradient,
        ),
        child: Row(
          children: [
            // 头像
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 12),
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
                    child: Text(
                      roleName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '学号：${user?.userId ?? ''}',
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
  // 学习概览 — 4 个统计卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOverviewStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            '已学节点',
            '$_learnedNodes',
            Icons.account_tree,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '测验次数',
            '$_quizCount',
            Icons.quiz,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '平均分',
            _avgScore.toStringAsFixed(1),
            Icons.trending_up,
            Colors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '学习天数',
            '$_learningDays',
            Icons.calendar_today,
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
  // 成长轨迹 — 时间线列表
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGrowthTimeline() {
    if (_recentRecords.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.timeline, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  '暂无学习记录',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 4),
                Text(
                  '开始学习知识图谱，记录成长轨迹吧！',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(_recentRecords.length, (index) {
            final record = _recentRecords[index];
            final nodeTitle = record['node_title'] as String? ?? '未知节点';
            final completedAt = record['completed_at'] as String? ?? '';
            final dateStr = completedAt.length >= 10
                ? completedAt.substring(0, 10)
                : completedAt;
            final timeStr = completedAt.length >= 16
                ? completedAt.substring(11, 16)
                : '';
            final isLast = index == _recentRecords.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 时间线指示器
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: index == 0
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey[400],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: index == 0
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.3)
                                  : Colors.grey[300]!,
                              width: 2,
                            ),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.grey[300],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 内容
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '学习了「$nodeTitle」',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$dateStr $timeStr',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 学习成就 — 5 个徽章
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAchievementBadges() {
    final badges = [
      _BadgeData('初学者', Icons.emoji_events, Colors.brown[300]!, '0-20分'),
      _BadgeData('进阶者', Icons.star, Colors.blue, '20-40分'),
      _BadgeData('探索者', Icons.explore, Colors.teal, '40-60分'),
      _BadgeData('精通者', Icons.workspace_premium, Colors.orange, '60-80分'),
      _BadgeData('专家级', Icons.military_tech, Colors.amber[700]!, '80分以上'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: badges.length,
      itemBuilder: (context, index) {
        final badge = badges[index];
        final isUnlocked = index <= _achievementLevel && _quizCount > 0;

        return Card(
          elevation: isUnlocked ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isUnlocked
                  ? badge.color.withValues(alpha: 0.5)
                  : Colors.grey[300]!,
              width: isUnlocked ? 2 : 1,
            ),
          ),
          color: isUnlocked ? null : Colors.grey[100],
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  badge.icon,
                  size: 28,
                  color: isUnlocked ? badge.color : Colors.grey[400],
                ),
                const SizedBox(height: 4),
                Text(
                  badge.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        isUnlocked ? FontWeight.bold : FontWeight.normal,
                    color: isUnlocked ? badge.color : Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  badge.desc,
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 快捷入口
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(
        icon: Icons.error_outline,
        label: '错题本',
        color: Colors.red,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WrongAnswersPage()),
        ),
      ),
      _QuickAction(
        icon: Icons.star_outline,
        label: '我的收藏',
        color: Colors.amber[700]!,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FavoritesPage()),
        ),
      ),
      _QuickAction(
        icon: Icons.route,
        label: '学习计划',
        color: Colors.indigo,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LearningPlanPage()),
        ),
      ),
      _QuickAction(
        icon: Icons.trending_up,
        label: '测验记录',
        color: Colors.green,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProgressPage()),
        ),
      ),
      _QuickAction(
        icon: Icons.psychology,
        label: '薄弱诊断',
        color: Colors.deepPurple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WeaknessDiagnosisPage()),
        ),
      ),
      _QuickAction(
        icon: Icons.science,
        label: '我的实验',
        color: Colors.brown,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StudentLabPage()),
        ),
      ),
      _QuickAction(
        icon: Icons.checklist,
        label: '产品化',
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductizationGuidePage()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.85,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: action.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: action.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      action.icon,
                      color: action.color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    action.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: action.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 辅助数据类
// ─────────────────────────────────────────────────────────────────────────────

class _BadgeData {
  final String name;
  final IconData icon;
  final Color color;
  final String desc;

  const _BadgeData(this.name, this.icon, this.color, this.desc);
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}
