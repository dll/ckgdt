part of '../assessment_page.dart';

class _ScoreTab extends StatefulWidget {
  final AuthService authService;
  const _ScoreTab({required this.authService});

  @override
  State<_ScoreTab> createState() => _ScoreTabState();
}

class _ScoreTabState extends State<_ScoreTab> {
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _ranking = [];
  Map<String, dynamic> _overview = {};
  Map<String, dynamic>? _myScore; // 学生个人成绩
  bool _loading = true;

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final ranking = await _dao.getScoreRanking();
      final overview = await _dao.getScoreOverview();

      // 学生：查找自己的成绩
      if (_isStudent) {
        final userId = widget.authService.getCurrentUserId();
        if (userId != null) {
          for (final r in ranking) {
            // 通过成员信息匹配
            final memberIds = r['member_ids'];
            if (memberIds != null && memberIds.toString().contains(userId)) {
              _myScore = r;
              break;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _ranking = ranking;
          _overview = overview;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    final avgScore =
        (_overview['avg_score'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final maxScore = '${(_overview['max_score'] ?? 0)}';
    final passRate = (_overview['pass_rate'] as String?) ?? '0%';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 学生模式：显示个人成绩摘要
          if (_isStudent) ...[
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [primary, primary.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.school,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 20),
                        const SizedBox(width: 8),
                        const Text('我的考核成绩',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_myScore != null) ...[
                      Text(
                        '${(_myScore!['total_score'] as num?)?.toInt() ?? 0}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            height: 1.1),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_myScore!['group_name'] ?? ''} · ${_myScore!['project_name'] ?? ''}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ] else
                      Column(
                        children: [
                          Icon(Icons.pending_outlined,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 36),
                          const SizedBox(height: 8),
                          const Text('暂无成绩',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (_myScore != null) ...[
              const SizedBox(height: 16),
              _buildDimensionDetailForScore(_myScore!),
            ],
          ],

          // 教师/管理员模式：显示统计概览和排行榜
          if (!_isStudent) ...[
            // 统计概览
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [primary, primary.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _overviewItem('平均分', avgScore, Icons.analytics),
                    Container(width: 1, height: 44, color: Colors.white24),
                    _overviewItem('最高分', maxScore, Icons.emoji_events),
                    Container(width: 1, height: 44, color: Colors.white24),
                    _overviewItem('及格率', passRate, Icons.check_circle),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 排行榜
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: Colors.indigo.withValues(alpha: 0.5), width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.leaderboard, size: 17, color: Colors.indigo[400]),
                  const SizedBox(width: 8),
                  Text('成绩排行 (${_ranking.length})',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800])),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (_ranking.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.leaderboard_outlined,
                            size: 48, color: Colors.grey[300]),
                      ),
                      const SizedBox(height: 12),
                      Text('暂无成绩数据', style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                ),
              )
            else
              ..._ranking.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final s = entry.value;
                return _buildScoreCard(context, {
                  'group': s['group_name'] ?? '未知小组',
                  'project': s['project_name'] ?? '未指定项目',
                  'score': (s['total_score'] as num?)?.toInt() ?? 0,
                  'rank': rank,
                  'comment': s['comment'],
                  'functionality': s['score_functionality'],
                  'tech_depth': s['score_tech_depth'],
                  'integration': s['score_integration'],
                  'quality': s['score_quality'],
                  'documentation': s['score_documentation'],
                });
              }),

            const SizedBox(height: 16),

            // 成绩明细说明
            if (_ranking.isNotEmpty) _buildDimensionDetail(),
          ],
        ],
      ),
    );
  }

  Widget _buildDimensionDetail() {
    // Use the top-ranked entry for the dimension detail display
    final top = _ranking.first;
    final functionality = (top['score_functionality'] as num?)?.toInt() ?? 0;
    final techDepth = (top['score_tech_depth'] as num?)?.toInt() ?? 0;
    final integration = (top['score_integration'] as num?)?.toInt() ?? 0;
    final quality = (top['score_quality'] as num?)?.toInt() ?? 0;
    final documentation = (top['score_documentation'] as num?)?.toInt() ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.indigo.withValues(alpha: 0.04),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bar_chart, size: 16, color: Colors.indigo[400]),
                ),
                const SizedBox(width: 8),
                Text('评分维度明细（${top['group_name'] ?? '第一名'}）',
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 14),
            _dimensionBar('功能完整性', functionality, 25, Colors.blue),
            _dimensionBar('技术实现深度', techDepth, 20, Colors.green),
            _dimensionBar('跨框架整合', integration, 25, Colors.purple),
            _dimensionBar('性能与质量', quality, 15, Colors.orange),
            _dimensionBar('文档与协作', documentation, 15, Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _overviewItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75), fontSize: 11)),
      ],
    );
  }

  Widget _buildScoreCard(BuildContext context, Map<String, dynamic> score) {
    final rank = score['rank'] as int;
    final totalScore = score['score'] as int;
    final rankColor = rank == 1
        ? Colors.amber[700]!
        : rank == 2
            ? Colors.grey.shade500
            : rank == 3
                ? Colors.brown.shade400
                : Colors.grey;
    final rankIcon = rank <= 3 ? Icons.emoji_events : null;

    final scoreColor = totalScore >= 90
        ? Colors.green
        : totalScore >= 80
            ? Colors.blue
            : totalScore >= 60
                ? Colors.orange
                : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: rank <= 3 ? 3 : 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: rank <= 3
              ? LinearGradient(
                  colors: [
                    rankColor.withValues(alpha: 0.06),
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: rank <= 3
                    ? Border.all(color: rankColor.withValues(alpha: 0.3))
                    : null,
              ),
              child: Center(
                child: rankIcon != null
                    ? Icon(rankIcon, color: rankColor, size: 22)
                    : Text('#$rank',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                            fontSize: 14)),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(score['group'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(score['project'] as String,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            // Score
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$totalScore',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scoreColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dimensionBar(String name, int score, int max, Color color) {
    final ratio = max > 0 ? score / max : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('$score/$max',
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  /// 学生个人成绩维度详情
  Widget _buildDimensionDetailForScore(Map<String, dynamic> score) {
    final functionality = (score['score_functionality'] as num?)?.toInt() ?? 0;
    final techDepth = (score['score_tech_depth'] as num?)?.toInt() ?? 0;
    final integration = (score['score_integration'] as num?)?.toInt() ?? 0;
    final quality = (score['score_quality'] as num?)?.toInt() ?? 0;
    final documentation = (score['score_documentation'] as num?)?.toInt() ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.indigo.withValues(alpha: 0.04),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bar_chart, size: 16, color: Colors.indigo[400]),
                ),
                const SizedBox(width: 8),
                const Text('评分维度明细',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 14),
            _dimensionBar('功能完整性', functionality, 25, Colors.blue),
            _dimensionBar('技术实现深度', techDepth, 20, Colors.green),
            _dimensionBar('跨框架整合', integration, 25, Colors.purple),
            _dimensionBar('性能与质量', quality, 15, Colors.orange),
            _dimensionBar('文档与协作', documentation, 15, Colors.teal),
          ],
        ),
      ),
    );
  }
}
