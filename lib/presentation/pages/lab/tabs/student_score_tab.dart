part of '../lab_tasks_page.dart';

class _StudentLabScoreTab extends StatefulWidget {
  final AuthService authService;
  final LabTaskDao labTaskDao;

  const _StudentLabScoreTab({
    required this.authService,
    required this.labTaskDao,
  });

  @override
  State<_StudentLabScoreTab> createState() => _StudentLabScoreTabState();
}

class _StudentLabScoreTabState extends State<_StudentLabScoreTab> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _details = [];
  bool _loading = true;
  int _passScore = SettingsService.defaultEvaluationPassScore;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final userId = widget.authService.getCurrentUserId();
      final passScore = await SettingsService.getEvaluationPassScore();
      if (userId == null) {
        if (!mounted) return;
        setState(() {
          _stats = {};
          _details = [];
          _passScore = passScore;
          _loading = false;
        });
        return;
      }

      try {
        await SyncService().downloadOwnData(userId);
      } catch (e, st) {
        swallowDebug(e, tag: 'StudentLabScoreTab.downloadOwnData', stack: st);
      }

      final stats = await widget.labTaskDao.getStudentLabStats(userId);
      final details = await widget.labTaskDao.getStudentLabScoreDetail(userId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _details = details;
        _passScore = passScore;
        _loading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'StudentLabScoreTab.loadData', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final primary = Theme.of(context).colorScheme.primary;
    final avg = (_stats['avg_score'] as num?)?.toDouble() ?? 0;
    final submitted = (_stats['submitted_tasks'] as num?)?.toInt() ?? 0;
    final total = (_stats['total_tasks'] as num?)?.toInt() ?? 0;
    final graded = (_stats['graded_count'] as num?)?.toInt() ?? 0;

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
                const Icon(Icons.science_outlined,
                    color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '我的实验成绩',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已提交 $submitted/$total · 已评分 $graded',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  avg > 0 ? avg.toStringAsFixed(1) : '未评',
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
                  child: _summaryTile('提交任务', '$submitted/$total',
                      Icons.assignment_turned_in, primary)),
              const SizedBox(width: 10),
              Expanded(
                  child:
                      _summaryTile('已评分', '$graded', Icons.grading, primary)),
              const SizedBox(width: 10),
              Expanded(
                  child: _summaryTile(
                      '达标线', '$_passScore', Icons.flag_outlined, primary)),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('实验成绩明细', Icons.list_alt, primary),
          if (_details.isEmpty)
            _emptyScoreHint()
          else
            ..._details.map((detail) => _detailCard(detail)),
        ],
      ),
    );
  }

  Widget _summaryTile(
      String label, String value, IconData icon, Color primary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withOpacity(0.10)),
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

  Widget _sectionTitle(String title, IconData icon, Color primary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _detailCard(Map<String, dynamic> detail) {
    final title = detail['task_title'] as String? ?? '实验任务';
    final chapter = detail['chapter'] as String? ?? '';
    final score = (detail['score'] as num?)?.toDouble();
    final maxScore = (detail['max_score'] as num?)?.toDouble() ?? 100;
    final status = detail['status'] as String? ?? '待批改';
    final feedback = detail['feedback'] as String? ?? '';
    final submitTime = detail['submit_time'] as String? ?? '';
    final color = score == null ? Colors.grey : _scoreColor(score, maxScore);
    final ratio = score == null || maxScore <= 0
        ? 0.0
        : (score / maxScore).clamp(0.0, 1.0).toDouble();

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      if (chapter.isNotEmpty || submitTime.isNotEmpty)
                        Text(
                          [
                            if (chapter.isNotEmpty) chapter,
                            if (submitTime.length >= 10)
                              '提交于 ${submitTime.substring(0, 10)}',
                          ].join(' · '),
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    score == null ? status : '${_fmt(score)}/${_fmt(maxScore)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: color.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            if (feedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                feedback,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyScoreHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('暂无实验成绩', style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Color _scoreColor(double score, double maxScore) {
    final ratio = maxScore > 0 ? score / maxScore : 0.0;
    if (ratio >= 0.9) return Colors.green;
    if (ratio >= 0.8) return Colors.blue;
    if (ratio >= 0.6) return Colors.orange;
    return Colors.red;
  }

  static String _fmt(num value) {
    final v = value.toDouble();
    if ((v - v.round()).abs() < 0.05) return v.round().toString();
    return v.toStringAsFixed(1);
  }
}
