part of '../works_page.dart';

class _RecordsTab extends StatefulWidget {
  final AuthService authService;
  const _RecordsTab({required this.authService});

  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  final _worksDao = WorksDao();
  String _dimension = 'latest';
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      await _worksDao.repairSubmissionState();
      final records = (await _worksDao.getWorks(sortBy: _dimension))
          .where((w) =>
              WorksDao.isSubmittedStatus(w['status'] as String?) ||
              WorksDao.hasVideoReference(w))
          .toList();
      if (mounted) {
        setState(() {
          _records = records;
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

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 维度切换 ─────────────────────────────────────
          Row(
            children: [
              _dimChip('最新发布', 'latest', Icons.schedule, primary),
              const SizedBox(width: 8),
              _dimChip('最多播放', 'most_viewed', Icons.visibility, primary),
              const SizedBox(width: 8),
              _dimChip('最热门', 'hottest', Icons.local_fire_department, primary),
            ],
          ),
          const SizedBox(height: 16),
          _sectionHeader(
            _dimension == 'latest'
                ? '按发布时间排序'
                : _dimension == 'most_viewed'
                    ? '按播放量排序'
                    : '按热度（点赞+评论）排序',
            icon: _dimension == 'latest'
                ? Icons.access_time
                : _dimension == 'most_viewed'
                    ? Icons.trending_up
                    : Icons.whatshot,
          ),
          if (_isLoading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ))
          else if (_records.isEmpty)
            _emptyHint('暂无作品记录', Icons.inbox)
          else
            ...List.generate(_records.length, (i) {
              return _buildRecordCard(context, _records[i], i + 1);
            }),
        ],
      ),
    );
  }

  Widget _dimChip(String label, String value, IconData icon, Color primary) {
    final selected = _dimension == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _dimension = value);
          _loadRecords();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:
                selected ? primary.withValues(alpha: 0.12) : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20, color: selected ? primary : Colors.grey[500]),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: selected ? primary : Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(
      BuildContext context, Map<String, dynamic> work, int rank) {
    final primary = Theme.of(context).colorScheme.primary;
    final viewCount = (work['view_count'] as int?) ?? 0;
    final likeCount = (work['like_count'] as int?) ?? 0;
    final commentCount = (work['comment_count'] as int?) ?? 0;
    final score = work['score'] as int?;
    final showReal = widget.authService.isTeacher || widget.authService.isAdmin;
    final studentName = _studentDisplayName(work, showReal);

    final rankColor = rank == 1
        ? Colors.amber[700]!
        : rank == 2
            ? Colors.grey[500]!
            : rank == 3
                ? Colors.brown[400]!
                : Colors.grey[400]!;

    final mainValue = _dimension == 'latest'
        ? _timeAgo(work['created_at'] as String?)
        : _dimension == 'most_viewed'
            ? '$viewCount次播放'
            : '${likeCount + commentCount}热度';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: rankColor, width: 3),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: rank <= 3
                  ? Icon(Icons.emoji_events, size: 24, color: rankColor)
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
                          fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (work['repo'] != null)
                        Text(work['repo'] as String,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Icon(Icons.visibility, size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text('$viewCount',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Icon(Icons.favorite, size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text('$likeCount',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Icon(Icons.comment, size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text('$commentCount',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(mainValue,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: primary)),
                if (score != null) ...[
                  const SizedBox(height: 2),
                  Text('$score分',
                      style: TextStyle(
                          fontSize: 11,
                          color: score >= 90
                              ? Colors.green
                              : score >= 80
                                  ? Colors.blue
                                  : Colors.orange)),
                ],
                if ((work['peer_count'] as int?) != null &&
                    (work['peer_count'] as int) > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                      '互评${(work['peer_avg'] as num?)?.toStringAsFixed(0) ?? '0'}分',
                      style:
                          TextStyle(fontSize: 10, color: Colors.orange[600])),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 2: 排行榜 (Leaderboard) — 多维度排行                                  ║
// ╚══════════════════════════════════════════════════════════════════════════════╝
