part of '../works_page.dart';

class _LeaderboardTab extends StatefulWidget {
  final AuthService authService;
  const _LeaderboardTab({required this.authService});

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  final _worksDao = WorksDao();
  String _dimension = 'comprehensive';
  List<Map<String, dynamic>> _leaderboard = [];
  Map<String, dynamic> _overview = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final lb =
          await _worksDao.getLeaderboard(dimension: _dimension);
      final ov = await _worksDao.getOverview();
      if (mounted) {
        setState(() {
          _leaderboard = lb;
          _overview = ov;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final gradTheme = AppGradientTheme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final avgScore =
        (_overview['avg_score'] as num?)?.toDouble() ?? 0.0;
    final maxScore = _overview['max_score'] ?? 0;
    final totalWorks = _overview['total_works'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 维度切换 ────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _rankChip(
                    '综合', 'comprehensive', Icons.analytics, primary),
                _rankChip('成绩', 'score', Icons.star, primary),
                _rankChip(
                    '播放量', 'views', Icons.visibility, primary),
                _rankChip(
                    '点赞', 'likes', Icons.favorite, primary),
                _rankChip(
                    '评论', 'comments', Icons.comment, primary),
              ]
                  .map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: c))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),

          // ── 统计概览卡 ─────────────────────────────────
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: gradTheme.linearGradient,
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _overviewItem(
                    '作品总数', '$totalWorks', Icons.workspace_premium),
                Container(
                    width: 1,
                    height: 40,
                    color: Colors.white30),
                _overviewItem('平均分',
                    avgScore.toStringAsFixed(1), Icons.analytics),
                Container(
                    width: 1,
                    height: 40,
                    color: Colors.white30),
                _overviewItem(
                    '最高分', '$maxScore', Icons.emoji_events),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── 领奖台 ─────────────────────────────────────
          if (_leaderboard.length >= 3) ...[
            _buildPodium(context),
            const SizedBox(height: 20),
          ],

          // ── 完整排行 ───────────────────────────────────
          _sectionHeader('完整排行',
              icon: Icons.format_list_numbered),
          if (_leaderboard.isEmpty)
            _emptyHint('暂无排行数据', Icons.leaderboard)
          else
            ...List.generate(_leaderboard.length, (i) {
              final entry =
                  Map<String, dynamic>.from(_leaderboard[i]);
              entry['rank'] = i + 1;
              return _buildRankCard(context, entry);
            }),
        ],
      ),
    );
  }

  Widget _rankChip(
      String label, String value, IconData icon, Color primary) {
    final selected = _dimension == value;
    return FilterChip(
      avatar: Icon(icon,
          size: 14,
          color: selected ? primary : Colors.grey[500]),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        setState(() => _dimension = value);
        _loadData();
      },
      showCheckmark: false,
      selectedColor: primary.withValues(alpha: 0.15),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _overviewItem(
      String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11)),
      ],
    );
  }

  // ── 领奖台 ────────────────────────────────────────────

  Widget _buildPodium(BuildContext context) {
    if (_leaderboard.length < 3) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, box) {
        final cardWidth = (box.maxWidth - 24) / 3;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: cardWidth.clamp(0, 140),
              child: _podiumCard(
                  _leaderboard[1], 2, Colors.grey.shade400, 80),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: cardWidth.clamp(0, 140),
              child: _podiumCard(
                  _leaderboard[0], 1, Colors.amber, 100),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: cardWidth.clamp(0, 140),
              child: _podiumCard(
                  _leaderboard[2], 3, Colors.brown.shade300, 64),
            ),
          ],
        );
      },
    );
  }

  Widget _podiumCard(Map<String, dynamic> entry, int rank,
      Color color, double baseHeight) {
    final metricValue = _getMetricValue(entry);
    final showReal =
        widget.authService.isTeacher || widget.authService.isAdmin;
    final studentName = _studentDisplayName(entry, showReal);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1)
          const Icon(Icons.emoji_events,
              color: Colors.amber, size: 32),
        CircleAvatar(
          radius: rank == 1 ? 24 : 20,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            _avatarChar(entry, showReal),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: rank == 1 ? 16 : 14),
          ),
        ),
        const SizedBox(height: 4),
        Text(studentName,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis),
        Text(metricValue,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          height: baseHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.3),
                color.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8)),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          child: Text(
            entry['repo'] as String? ??
                entry['group_name'] as String? ??
                '',
            style: const TextStyle(fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _getMetricValue(Map<String, dynamic> entry) {
    return switch (_dimension) {
      'score' => '${entry['score'] ?? 0}分',
      'views' => '${entry['view_count'] ?? 0}次',
      'likes' => '${entry['like_count'] ?? 0}赞',
      'comments' => '${entry['comment_count'] ?? 0}评',
      _ => entry['composite_score'] != null
          ? '${(entry['composite_score'] as double).toStringAsFixed(1)}分'
          : '${entry['score'] ?? 0}分',
    };
  }

  // ── 排行卡片 ──────────────────────────────────────────

  Widget _buildRankCard(
      BuildContext context, Map<String, dynamic> entry) {
    final rank = entry['rank'] as int;
    final rankColor = rank == 1
        ? Colors.amber[700]!
        : rank == 2
            ? Colors.grey[500]!
            : rank == 3
                ? Colors.brown[400]!
                : Colors.grey[400]!;
    final metricValue = _getMetricValue(entry);
    final viewCount = (entry['view_count'] as int?) ?? 0;
    final likeCount = (entry['like_count'] as int?) ?? 0;
    final commentCount = (entry['comment_count'] as int?) ?? 0;
    final showReal =
        widget.authService.isTeacher || widget.authService.isAdmin;
    final studentName = _studentDisplayName(entry, showReal);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: rankColor, width: 3),
          ),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: rank <= 3
                  ? Icon(Icons.emoji_events,
                      size: 24, color: rankColor)
                  : Text('#$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: rankColor)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(studentName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        entry['repo'] as String? ??
                            entry['group_name'] as String? ??
                            '',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _miniStatGrey(
                          Icons.visibility, '$viewCount'),
                      const SizedBox(width: 10),
                      _miniStatGrey(
                          Icons.favorite, '$likeCount'),
                      const SizedBox(width: 10),
                      _miniStatGrey(
                          Icons.comment, '$commentCount'),
                    ],
                  ),
                ],
              ),
            ),
            Text(metricValue,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: rank <= 3
                        ? rankColor
                        : Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Widget _miniStatGrey(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[400]),
        const SizedBox(width: 2),
        Text(value,
            style: TextStyle(
                fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }
}
