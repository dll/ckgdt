part of '../works_page.dart';

class _WorksScoreTab extends StatefulWidget {
  final AuthService authService;

  const _WorksScoreTab({required this.authService});

  @override
  State<_WorksScoreTab> createState() => _WorksScoreTabState();
}

class _WorksScoreTabState extends State<_WorksScoreTab> {
  final _worksDao = WorksDao();
  List<Map<String, dynamic>> _works = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final userId = widget.authService.getCurrentUserId();
      final works = userId == null
          ? <Map<String, dynamic>>[]
          : await _worksDao.getWorks(userId: userId, sortBy: 'latest');
      if (!mounted) return;
      setState(() {
        _works = works;
        _loading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksScoreTab.loadData', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final primary = Theme.of(context).colorScheme.primary;
    final scored = _works.where((work) => _teacherScore(work) != null).toList();
    final teacherScores = scored
        .map((work) => _teacherScore(work)!)
        .where((score) => score > 0)
        .toList();
    final avg = teacherScores.isEmpty
        ? 0.0
        : teacherScores.reduce((a, b) => a + b) / teacherScores.length;
    final maxScore = teacherScores.isEmpty
        ? 0.0
        : teacherScores.reduce((a, b) => a > b ? a : b);
    final submitted = _works
        .where((work) =>
            WorksDao.isSubmittedStatus(work['status'] as String?) ||
            WorksDao.hasVideoReference(work))
        .length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppGradientTheme.of(context).linearGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '我的作品成绩',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已提交 $submitted · 教师已评 ${scored.length}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  teacherScores.isEmpty ? '未评' : avg.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _summaryTile(
                      '作品数', '${_works.length}', Icons.collections, primary)),
              const SizedBox(width: 10),
              Expanded(
                  child: _summaryTile(
                      '已提交', '$submitted', Icons.upload_file, primary)),
              const SizedBox(width: 10),
              Expanded(
                  child: _summaryTile(
                      '最高分',
                      teacherScores.isEmpty
                          ? '--'
                          : maxScore.toStringAsFixed(0),
                      Icons.emoji_events,
                      primary)),
            ],
          ),
          const SizedBox(height: 16),
          _sectionHeader('作品成绩明细', icon: Icons.list_alt, color: primary),
          if (_works.isEmpty)
            _emptyHint('暂无作品记录', Icons.workspace_premium_outlined)
          else
            ..._works.map((work) => _buildWorkScoreCard(work, primary)),
        ],
      ),
    );
  }

  Widget _summaryTile(
      String label, String value, IconData icon, Color primary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Icon(icon, color: primary, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildWorkScoreCard(Map<String, dynamic> work, Color primary) {
    final title = work['title'] as String? ?? '未命名作品';
    final status = work['status'] as String? ?? '待提交';
    final teacherScore = _teacherScore(work);
    final peerAvg = (work['peer_avg'] as num?)?.toDouble() ??
        (work['avg_score'] as num?)?.toDouble();
    final peerCount = (work['peer_count'] as num?)?.toInt() ?? 0;
    final views = (work['view_count'] as num?)?.toInt() ?? 0;
    final likes = (work['like_count'] as num?)?.toInt() ?? 0;
    final comments = (work['comment_count'] as num?)?.toInt() ?? 0;
    final scoreForColor = teacherScore ?? peerAvg ?? 0.0;
    final color = _scoreColor(scoreForColor);
    final ratio =
        scoreForColor <= 0 ? 0.0 : (scoreForColor / 100).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statChip(Icons.star, _scoreText(teacherScore), '师评',
                    teacherScore == null ? Colors.grey : color),
                const SizedBox(width: 8),
                _statChip(
                    Icons.group,
                    peerAvg == null ? '--' : peerAvg.toStringAsFixed(1),
                    '同评',
                    peerAvg == null ? Colors.grey : Colors.teal),
                const Spacer(),
                Text(
                  peerCount > 0 ? '$peerCount人互评' : '暂无互评',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _miniMetric(Icons.visibility, '$views', '播放'),
                _miniMetric(Icons.favorite, '$likes', '点赞'),
                _miniMetric(Icons.comment, '$comments', '评论'),
              ],
            ),
            if ((work['score_comment'] as String?)?.trim().isNotEmpty ==
                true) ...[
              const SizedBox(height: 10),
              Text(
                work['score_comment'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.grey[700], fontSize: 12, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      '已评分' => Colors.green,
      '已提交' => Colors.blue,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _miniMetric(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ],
      ),
    );
  }

  double? _teacherScore(Map<String, dynamic> work) {
    final score = (work['score'] as num?) ?? (work['teacher_score'] as num?);
    return score?.toDouble();
  }

  String _scoreText(double? score) =>
      score == null || score <= 0 ? '--' : score.toStringAsFixed(0);

  Color _scoreColor(double score) {
    if (score >= 90) return Colors.green;
    if (score >= 80) return Colors.blue;
    if (score >= 60) return Colors.orange;
    return score > 0 ? Colors.red : Colors.grey;
  }
}
