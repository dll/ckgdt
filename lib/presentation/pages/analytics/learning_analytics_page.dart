import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/database_helper.dart';

/// 学情分析仪表板 — 教师专用
/// 提供班级整体学习数据分析、预警学生识别、章节掌握度分析
class LearningAnalyticsPage extends StatefulWidget {
  const LearningAnalyticsPage({super.key});

  @override
  State<LearningAnalyticsPage> createState() => _LearningAnalyticsPageState();
}

class _LearningAnalyticsPageState extends State<LearningAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // ── 班级概览数据 ────────────────────────────────────────────
  int _totalStudents = 0;
  int _activeStudents = 0; // 有学习记录的
  int _totalQuizAttempts = 0;
  double _classAvgScore = 0.0;

  // ── 成绩分布数据 ────────────────────────────────────────────
  Map<String, int> _scoreDistribution = {};

  // ── 章节掌握度 ──────────────────────────────────────────────
  List<Map<String, dynamic>> _chapterMastery = [];

  // ── 预警学生 ────────────────────────────────────────────────
  List<Map<String, dynamic>> _warningStudents = [];

  // ── 学习活跃度趋势 ──────────────────────────────────────────
  List<Map<String, dynamic>> _activityTrend = [];

  // ── 学生成绩排行 ────────────────────────────────────────────
  List<Map<String, dynamic>> _studentRanking = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      // ── 1. 班级概览 ──────────────────────────────────────
      final studentCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM users WHERE role='student'");
      _totalStudents = (studentCount.first['c'] as int?) ?? 0;

      // 有学习记录的学生数
      final activeCount = await db.rawQuery(
          'SELECT COUNT(DISTINCT user_id) as c FROM learning_records');
      _activeStudents = (activeCount.first['c'] as int?) ?? 0;

      // 测验统计
      final quizStats = await db.rawQuery('''
        SELECT COUNT(*) as total_attempts,
               AVG(score) as avg_score
        FROM quiz_results
      ''');
      _totalQuizAttempts = (quizStats.first['total_attempts'] as int?) ?? 0;
      _classAvgScore =
          (quizStats.first['avg_score'] as num?)?.toDouble() ?? 0.0;

      // ── 2. 成绩分布 ──────────────────────────────────────
      _scoreDistribution = await _computeScoreDistribution(db);

      // ── 3. 章节掌握度 ────────────────────────────────────
      _chapterMastery = await _computeChapterMastery(db);

      // ── 4. 预警学生 ──────────────────────────────────────
      _warningStudents = await _computeWarningStudents(db);

      // ── 5. 学习活跃度趋势 ────────────────────────────────
      _activityTrend = await _computeActivityTrend(db);

      // ── 6. 学生成绩排行 ──────────────────────────────────
      _studentRanking = await _computeStudentRanking(db);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('学情分析加载失败: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, int>> _computeScoreDistribution(dynamic db) async {
    final dist = <String, int>{
      '0-59': 0,
      '60-69': 0,
      '70-79': 0,
      '80-89': 0,
      '90-100': 0,
    };
    try {
      // 取每个学生的最新成绩
      final results = await db.rawQuery('''
        SELECT user_id, AVG(score) as avg_score
        FROM quiz_results
        GROUP BY user_id
      ''');
      for (final r in results) {
        final score = (r['avg_score'] as num?)?.toDouble() ?? 0;
        if (score >= 90) {
          dist['90-100'] = dist['90-100']! + 1;
        } else if (score >= 80) {
          dist['80-89'] = dist['80-89']! + 1;
        } else if (score >= 70) {
          dist['70-79'] = dist['70-79']! + 1;
        } else if (score >= 60) {
          dist['60-69'] = dist['60-69']! + 1;
        } else {
          dist['0-59'] = dist['0-59']! + 1;
        }
      }
    } catch (_) {}
    return dist;
  }

  Future<List<Map<String, dynamic>>> _computeChapterMastery(
      dynamic db) async {
    try {
      final chapters = await db.rawQuery('''
        SELECT chapter,
               COUNT(*) as attempt_count,
               AVG(CAST(num_correct AS REAL) / CASE WHEN num_total = 0 THEN 1 ELSE num_total END * 100) as mastery
        FROM quiz_results
        WHERE chapter IS NOT NULL AND chapter != ''
        GROUP BY chapter
        ORDER BY chapter
      ''');
      return chapters
          .map<Map<String, dynamic>>((r) => {
                'chapter': r['chapter'] ?? '未知',
                'mastery':
                    (r['mastery'] as num?)?.toDouble() ?? 0.0,
                'attempts': (r['attempt_count'] as int?) ?? 0,
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _computeWarningStudents(
      dynamic db) async {
    try {
      // 低分学生（平均分 < 60）或 无活跃记录学生
      final lowScoreStudents = await db.rawQuery('''
        SELECT u.user_id, u.real_name,
               COALESCE(q.avg_score, 0) as avg_score,
               COALESCE(q.quiz_count, 0) as quiz_count,
               COALESCE(l.learn_count, 0) as learn_count
        FROM users u
        LEFT JOIN (
          SELECT user_id, AVG(score) as avg_score, COUNT(*) as quiz_count
          FROM quiz_results
          GROUP BY user_id
        ) q ON u.user_id = q.user_id
        LEFT JOIN (
          SELECT user_id, COUNT(*) as learn_count
          FROM learning_records
          GROUP BY user_id
        ) l ON u.user_id = l.user_id
        WHERE u.role = 'student'
        AND (COALESCE(q.avg_score, 0) < 60 OR COALESCE(l.learn_count, 0) = 0)
        ORDER BY COALESCE(q.avg_score, 0) ASC
        LIMIT 20
      ''');

      return lowScoreStudents.map<Map<String, dynamic>>((r) {
        final avgScore = (r['avg_score'] as num?)?.toDouble() ?? 0.0;
        final learnCount = (r['learn_count'] as int?) ?? 0;
        final quizCount = (r['quiz_count'] as int?) ?? 0;

        String reason;
        String level;
        if (learnCount == 0 && quizCount == 0) {
          reason = '无任何学习记录';
          level = 'high';
        } else if (avgScore < 40) {
          reason = '平均成绩严重偏低 (${avgScore.toStringAsFixed(1)})';
          level = 'high';
        } else if (avgScore < 60) {
          reason = '平均成绩不及格 (${avgScore.toStringAsFixed(1)})';
          level = 'medium';
        } else {
          reason = '学习活跃度不足';
          level = 'low';
        }

        return {
          'user_id': r['user_id'],
          'real_name': r['real_name'] ?? r['user_id'],
          'avg_score': avgScore,
          'quiz_count': quizCount,
          'learn_count': learnCount,
          'reason': reason,
          'level': level,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _computeActivityTrend(
      dynamic db) async {
    try {
      // 按天统计最近14天的学习活跃度
      final records = await db.rawQuery('''
        SELECT DATE(completed_at) as day,
               COUNT(*) as record_count,
               COUNT(DISTINCT user_id) as active_users
        FROM learning_records
        WHERE completed_at IS NOT NULL
        GROUP BY DATE(completed_at)
        ORDER BY day DESC
        LIMIT 14
      ''');
      return records
          .map<Map<String, dynamic>>((r) => {
                'day': r['day'] ?? '',
                'records': (r['record_count'] as int?) ?? 0,
                'users': (r['active_users'] as int?) ?? 0,
              })
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _computeStudentRanking(
      dynamic db) async {
    try {
      return await db.rawQuery('''
        SELECT u.user_id, u.real_name,
               AVG(qr.score) as avg_score,
               COUNT(qr.id) as quiz_count,
               COALESCE(lr.learn_count, 0) as learn_count
        FROM users u
        JOIN quiz_results qr ON u.user_id = qr.user_id
        LEFT JOIN (
          SELECT user_id, COUNT(*) as learn_count
          FROM learning_records
          GROUP BY user_id
        ) lr ON u.user_id = lr.user_id
        WHERE u.role = 'student'
        GROUP BY u.user_id
        ORDER BY avg_score DESC
        LIMIT 30
      ''');
    } catch (_) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学情分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
            tooltip: '刷新数据',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard, size: 18), text: '总览'),
            Tab(icon: Icon(Icons.bar_chart, size: 18), text: '成绩分析'),
            Tab(icon: Icon(Icons.warning_amber, size: 18), text: '学情预警'),
            Tab(icon: Icon(Icons.leaderboard, size: 18), text: '学生排行'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildScoreAnalysisTab(),
                _buildWarningTab(),
                _buildRankingTab(),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab 1: 总览
  // ══════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    final primary = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 概览卡片
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.7)],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _overviewItem('学生总数', '$_totalStudents',
                          Icons.people, Colors.white),
                      _divider(),
                      _overviewItem('活跃学生', '$_activeStudents',
                          Icons.person_pin, Colors.white),
                      _divider(),
                      _overviewItem('测验次数', '$_totalQuizAttempts',
                          Icons.quiz, Colors.white),
                      _divider(),
                      _overviewItem(
                          '班均分',
                          _classAvgScore.toStringAsFixed(1),
                          Icons.trending_up,
                          Colors.white),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 活跃率
                  Row(
                    children: [
                      const Text('学生活跃率',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _totalStudents > 0
                                ? _activeStudents / _totalStudents
                                : 0,
                            minHeight: 8,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation(
                                Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _totalStudents > 0
                            ? '${(_activeStudents / _totalStudents * 100).toInt()}%'
                            : '0%',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 章节掌握度
          const Text('章节掌握度',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (_chapterMastery.isEmpty)
            _emptyCard('暂无章节测验数据')
          else
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: _chapterMastery
                      .map((c) => _masteryBar(
                            c['chapter'] as String,
                            (c['mastery'] as double).clamp(0, 100),
                            c['attempts'] as int,
                          ))
                      .toList(),
                ),
              ),
            ),
          const SizedBox(height: 20),

          // 学习活跃度趋势
          const Text('近期学习活跃度',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (_activityTrend.isEmpty)
            _emptyCard('暂无学习活动数据')
          else
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 200,
                  child: _buildActivityChart(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overviewItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                color: color.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 40, color: Colors.white30);

  Widget _masteryBar(String chapter, double mastery, int attempts) {
    final color = mastery >= 80
        ? Colors.green
        : mastery >= 60
            ? Colors.blue
            : mastery >= 40
                ? Colors.orange
                : Colors.red;
    // 截取章节名：如果太长，只显示前8字
    final shortName =
        chapter.length > 10 ? '${chapter.substring(0, 10)}…' : chapter;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(shortName,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: mastery / 100,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${mastery.toInt()}%',
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text('(${attempts}次)',
              style: TextStyle(fontSize: 10, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildActivityChart() {
    if (_activityTrend.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (int i = 0; i < _activityTrend.length; i++) {
      spots.add(FlSpot(
          i.toDouble(),
          (_activityTrend[i]['records'] as int).toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 5,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style:
                    TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (_activityTrend.length / 5)
                  .ceilToDouble()
                  .clamp(1, 10),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < _activityTrend.length) {
                  final day =
                      _activityTrend[idx]['day'] as String;
                  return Text(
                    day.length >= 5 ? day.substring(5) : day,
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey[500]),
                  );
                }
                return const Text('');
              },
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 3,
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 1,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab 2: 成绩分析
  // ══════════════════════════════════════════════════════════

  Widget _buildScoreAnalysisTab() {
    final primary = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 成绩分布柱状图
        const Text('成绩分布',
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 220,
              child: _buildDistributionChart(),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 成绩统计表
        const Text('统计指标',
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _statRow('班级平均分',
                    _classAvgScore.toStringAsFixed(1), primary),
                _statRow(
                    '参加测验人数',
                    '${_scoreDistribution.values.fold<int>(0, (a, b) => a + b)}',
                    Colors.blue),
                _statRow('优秀率 (≥90)',
                    '${_scoreDistribution['90-100'] ?? 0}人',
                    Colors.green),
                _statRow(
                    '不及格率 (<60)',
                    '${_scoreDistribution['0-59'] ?? 0}人',
                    Colors.red),
                const Divider(),
                _statRow(
                  '总测验次数',
                  '$_totalQuizAttempts',
                  Colors.orange,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 章节正确率对比
        const Text('章节正确率对比',
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (_chapterMastery.isEmpty)
          _emptyCard('暂无数据')
        else
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 220,
                child: _buildChapterBarChart(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDistributionChart() {
    final entries = _scoreDistribution.entries.toList();
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.blue,
      Colors.green
    ];

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (_scoreDistribution.values.fold<int>(0,
                    (a, b) => a > b ? a : b) +
                2)
            .toDouble(),
        barGroups: List.generate(entries.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: entries[i].value.toDouble(),
                color: colors[i],
                width: 28,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6)),
              ),
            ],
          );
        }),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < entries.length) {
                  return Text(entries[idx].key,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey[600]));
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style:
                    TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildChapterBarChart() {
    if (_chapterMastery.isEmpty) return const SizedBox.shrink();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barGroups: List.generate(_chapterMastery.length, (i) {
          final mastery = (_chapterMastery[i]['mastery'] as double)
              .clamp(0.0, 100.0);
          final color = mastery >= 80
              ? Colors.green
              : mastery >= 60
                  ? Colors.blue
                  : mastery >= 40
                      ? Colors.orange
                      : Colors.red;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: mastery,
                color: color,
                width: 20,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4)),
              ),
            ],
          );
        }),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < _chapterMastery.length) {
                  final name =
                      _chapterMastery[idx]['chapter'] as String;
                  final short =
                      name.length > 4 ? name.substring(0, 4) : name;
                  return Text(short,
                      style: TextStyle(
                          fontSize: 9, color: Colors.grey[600]));
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 20,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}%',
                style:
                    TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab 3: 学情预警
  // ══════════════════════════════════════════════════════════

  Widget _buildWarningTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 预警统计
        Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.red[700], size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '需关注学生: ${_warningStudents.length}人',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '以下学生平均分不及格或无学习记录，建议及时干预',
                        style: TextStyle(
                            fontSize: 12, color: Colors.red[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 预警学生列表
        if (_warningStudents.isEmpty)
          _emptyCard('目前没有需要预警的学生，非常好！')
        else
          ..._warningStudents.map((s) => _buildWarningCard(s)),
      ],
    );
  }

  Widget _buildWarningCard(Map<String, dynamic> student) {
    final level = student['level'] as String;
    final color = level == 'high'
        ? Colors.red
        : level == 'medium'
            ? Colors.orange
            : Colors.amber;
    final levelText = level == 'high'
        ? '严重'
        : level == 'medium'
            ? '中等'
            : '轻微';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
            level == 'high'
                ? Icons.error
                : level == 'medium'
                    ? Icons.warning
                    : Icons.info,
            color: color,
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Text(
              student['real_name'] as String,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(levelText,
                  style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(student['reason'] as String,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Row(
              children: [
                _miniStat(Icons.quiz, '${student['quiz_count']}次测验'),
                const SizedBox(width: 10),
                _miniStat(
                    Icons.menu_book, '${student['learn_count']}条记录'),
              ],
            ),
          ],
        ),
        trailing: Text(
          (student['avg_score'] as double).toStringAsFixed(0),
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[400]),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab 4: 学生排行
  // ══════════════════════════════════════════════════════════

  Widget _buildRankingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_studentRanking.isEmpty)
          _emptyCard('暂无学生成绩数据')
        else ...[
          // 前三名领奖台
          if (_studentRanking.length >= 3) ...[
            _buildPodium(),
            const SizedBox(height: 16),
          ],
          const Text('完整排行',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...List.generate(_studentRanking.length,
              (i) => _buildRankCard(i, _studentRanking[i])),
        ],
      ],
    );
  }

  Widget _buildPodium() {
    if (_studentRanking.length < 3) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _podiumItem(_studentRanking[1], 2, Colors.grey.shade400, 70),
        const SizedBox(width: 8),
        _podiumItem(_studentRanking[0], 1, Colors.amber, 90),
        const SizedBox(width: 8),
        _podiumItem(_studentRanking[2], 3, Colors.brown.shade300, 56),
      ],
    );
  }

  Widget _podiumItem(
      Map<String, dynamic> student, int rank, Color color, double h) {
    final name = (student['real_name'] as String?) ??
        (student['user_id'] as String? ?? '?');
    final score =
        (student['avg_score'] as num?)?.toDouble() ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1)
          const Icon(Icons.emoji_events, color: Colors.amber, size: 28),
        CircleAvatar(
          radius: rank == 1 ? 22 : 18,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('#$rank',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: rank == 1 ? 14 : 12)),
        ),
        const SizedBox(height: 4),
        Text(name,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600)),
        Text('${score.toStringAsFixed(1)}分',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Container(
          width: 70,
          height: h,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
      ],
    );
  }

  Widget _buildRankCard(int index, Map<String, dynamic> student) {
    final rank = index + 1;
    final name = (student['real_name'] as String?) ??
        (student['user_id'] as String? ?? '?');
    final avgScore =
        (student['avg_score'] as num?)?.toDouble() ?? 0;
    final quizCount = (student['quiz_count'] as int?) ?? 0;
    final learnCount = (student['learn_count'] as int?) ?? 0;

    final rankColor = rank == 1
        ? Colors.amber
        : rank == 2
            ? Colors.grey.shade400
            : rank == 3
                ? Colors.brown.shade300
                : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: rankColor.withValues(alpha: 0.15),
          child: Text('$rank',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: rankColor,
                  fontSize: 12)),
        ),
        title: Text(name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
            '测验${quizCount}次 · 学习记录${learnCount}条',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        trailing: Text(avgScore.toStringAsFixed(1),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: avgScore >= 90
                    ? Colors.green
                    : avgScore >= 80
                        ? Colors.blue
                        : avgScore >= 60
                            ? Colors.orange
                            : Colors.red)),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(message,
                  style: TextStyle(color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );
  }
}
