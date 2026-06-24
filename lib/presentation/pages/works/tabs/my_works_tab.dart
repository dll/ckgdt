// part of works_page.dart — 学生专属"我的作品"Tab
//
// 仅显示当前学生本人的作品 + 教师评分历史 + 同学互评。
// 教师/管理员视角不会看到这个 tab（works_page.dart 用 _isStudent 判断）。

part of '../works_page.dart';

class _MyWorksTab extends StatefulWidget {
  final AuthService authService;
  final VoidCallback? onDataChanged;

  const _MyWorksTab({
    required this.authService,
    this.onDataChanged,
  });

  @override
  State<_MyWorksTab> createState() => _MyWorksTabState();
}

class _MyWorksTabState extends State<_MyWorksTab> {
  final _worksDao = WorksDao();
  List<Map<String, dynamic>> _works = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = widget.authService.getCurrentUserId();
    if (uid == null) {
      setState(() {
        _loading = false;
        _works = [];
      });
      return;
    }
    final works = await _worksDao.getWorks(userId: uid, sortBy: 'latest');
    if (!mounted) return;
    setState(() {
      _works = works;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (_works.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_creation_outlined,
                  size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text('你还没有提交作品',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text(
                '请在"作品展示"中找到你的项目并上传演示视频',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(primary),
          const SizedBox(height: 16),
          _sectionHeader('我的作品 (${_works.length})',
              icon: Icons.collections, color: primary),
          ..._works.map((w) => _buildWorkCard(w, primary)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(Color primary) {
    final scoredCount = _works.where((w) {
      final s = (w['score'] as num?) ??
          (w['teacher_score'] as num?) ??
          (w['avg_score'] as num?) ??
          0;
      return s > 0;
    }).length;
    final scores = _works
        .map((w) => ((w['score'] as num?) ??
                (w['teacher_score'] as num?) ??
                (w['avg_score'] as num?) ??
                0)
            .toDouble())
        .where((s) => s > 0)
        .toList();
    final avg =
        scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;
    final maxScore =
        scores.isEmpty ? 0.0 : scores.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradientTheme.of(context).verticalGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_pin, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text('我的作品概览',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryStat('${_works.length}', '作品数'),
              _summaryStat('$scoredCount', '已评'),
              _summaryStat(avg.toStringAsFixed(1), '均分'),
              _summaryStat(maxScore.toInt().toString(), '最高'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildWorkCard(Map<String, dynamic> work, Color primary) {
    final title = work['title'] as String? ?? '未命名作品';
    final tech = work['tech_stack'] as String? ?? '';
    final desc = work['description'] as String? ?? '';
    final views = (work['view_count'] as num?)?.toInt() ?? 0;
    final likes = (work['like_count'] as num?)?.toInt() ?? 0;
    final teacherScore =
        ((work['score'] as num?) ?? (work['teacher_score'] as num?))?.toInt();
    final peerAvg = (work['avg_score'] as num?)?.toDouble();
    final status = work['status'] as String? ?? '草稿';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      // 学生本人作品在自己的 tab 内统一加蓝边框（视觉一致性）
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primary.withOpacity(0.4), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(work),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  _statusChip(status),
                ],
              ),
              if (tech.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tech,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(desc,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _statChip(Icons.visibility, '$views', '播放', Colors.grey),
                  const SizedBox(width: 8),
                  _statChip(Icons.favorite, '$likes', '赞', Colors.pink),
                  const Spacer(),
                  if (teacherScore != null && teacherScore > 0)
                    _statChip(Icons.star, '$teacherScore', '师评',
                        Colors.amber.shade700)
                  else if (peerAvg != null && peerAvg > 0)
                    _statChip(Icons.group, peerAvg.toStringAsFixed(1), '同评',
                        Colors.teal)
                  else
                    _statChip(Icons.hourglass_empty, '待评', '', Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status) {
      case '已评分':
        color = Colors.green;
        break;
      case '已提交':
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(status,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  void _openDetail(Map<String, dynamic> work) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkDetailSheet(
        work: work,
        worksDao: _worksDao,
        authService: widget.authService,
        onChanged: () {
          _load();
          widget.onDataChanged?.call();
        },
      ),
    );
  }
}
