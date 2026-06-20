part of '../works_page.dart';

class _GalleryTab extends StatefulWidget {
  final AuthService authService;
  final List<Map<String, dynamic>> allStudents;
  final VoidCallback? onDataChanged;
  const _GalleryTab({
    required this.authService,
    required this.allStudents,
    this.onDataChanged,
  });

  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> {
  final _worksDao = WorksDao();
  final _searchCtrl = TextEditingController();
  String _sortBy = 'latest';
  _WorkDimension _currentDim = _WorkDimension.all;
  List<Map<String, dynamic>> _works = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorks();
  }

  Future<void> _loadWorks() async {
    setState(() => _isLoading = true);
    try {
      final works = await _worksDao.getWorks(sortBy: _sortBy);
      if (mounted) setState(() { _works = works; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredWorks {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _works;
    return _works
        .where((w) =>
            (w['title'] as String? ?? '').toLowerCase().contains(q) ||
            (w['student_name'] as String? ?? '').toLowerCase().contains(q) ||
            (w['repo'] as String? ?? '').toLowerCase().contains(q) ||
            (w['student_role'] as String? ?? '').toLowerCase().contains(q) ||
            (w['tech_stack'] as String? ?? '').toLowerCase().contains(q) ||
            (w['project'] as String? ?? '').toLowerCase().contains(q) ||
            (w['group_name'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  /// 按当前维度对作品分组
  Map<String, List<Map<String, dynamic>>> _groupedWorks(
      List<Map<String, dynamic>> works) {
    if (_currentDim == _WorkDimension.all) return {};
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final w in works) {
      final key = (w[_currentDim.dbKey] as String?)?.trim() ?? '未分配';
      grouped.putIfAbsent(key, () => []).add(w);
    }
    return Map.fromEntries(
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredWorks;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // ── 搜索栏 ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索姓名、项目、仓库、角色、技术栈...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // ── 维度过滤 Chips ─────────────────────────────────
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _WorkDimension.values
                .map((dim) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(dim.icon,
                            size: 14,
                            color: _currentDim == dim
                                ? dim.color
                                : Colors.grey[500]),
                        label: Text(dim.label,
                            style: const TextStyle(fontSize: 12)),
                        selected: _currentDim == dim,
                        onSelected: (_) {
                          setState(() => _currentDim = dim);
                        },
                        showCheckmark: false,
                        selectedColor: dim.color.withValues(alpha: 0.15),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ))
                .toList(),
          ),
        ),
        // ── 排序 Chips（仅全部视角下显示） ────────────────
        if (_currentDim == _WorkDimension.all) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _sortChip('最新', 'latest', Icons.schedule, primary),
                _sortChip(
                    '最多播放', 'most_viewed', Icons.visibility, primary),
                _sortChip(
                    '最多点赞', 'most_liked', Icons.favorite, primary),
                _sortChip(
                    '最热', 'hottest', Icons.local_fire_department, primary),
              ]
                  .map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8), child: c))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 4),
        // ── 统计行 ────────────────────────────────────────
        if (!_isLoading && _currentDim != _WorkDimension.all)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildDimStats(filtered),
          ),
        // ── 内容区 ────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child:
                          _emptyHint('没有找到匹配的作品', Icons.search_off))
                  : _currentDim == _WorkDimension.all
                      ? _buildFlatView(context, filtered)
                      : _buildGroupedView(context, filtered),
        ),
      ],
    );
  }

  Widget _buildDimStats(List<Map<String, dynamic>> works) {
    final grouped = _groupedWorks(works);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(_currentDim.icon,
              size: 14, color: _currentDim.color),
          const SizedBox(width: 6),
          Text(
            '${_currentDim.label}视角 · ${grouped.length}组 · ${works.length}人',
            style: TextStyle(
                fontSize: 12,
                color: _currentDim.color,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(
      String label, String value, IconData icon, Color primary) {
    final selected = _sortBy == value;
    return FilterChip(
      avatar: Icon(icon,
          size: 14, color: selected ? primary : Colors.grey[500]),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) {
        setState(() => _sortBy = value);
        _loadWorks();
      },
      showCheckmark: false,
      selectedColor: primary.withValues(alpha: 0.15),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ── 全部视角：平铺网格/列表 ─────────────────────────────

  Widget _buildFlatView(
      BuildContext context, List<Map<String, dynamic>> works) {
    return RefreshIndicator(
      onRefresh: _loadWorks,
      child: LayoutBuilder(
        builder: (ctx, box) {
          final cols =
              box.maxWidth > 900 ? 3 : box.maxWidth > 600 ? 2 : 1;
          if (cols == 1) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: works.length,
              itemBuilder: (_, i) =>
                  _buildVideoCard(context, works[i]),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.15,
            ),
            itemCount: works.length,
            itemBuilder: (_, i) =>
                _buildVideoCard(context, works[i]),
          );
        },
      ),
    );
  }

  // ── 维度视角：分组展示 ──────────────────────────────────

  Widget _buildGroupedView(
      BuildContext context, List<Map<String, dynamic>> works) {
    final grouped = _groupedWorks(works);
    final sortedKeys = grouped.keys.toList();

    return RefreshIndicator(
      onRefresh: _loadWorks,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (int gi = 0; gi < sortedKeys.length; gi++) ...[
            if (gi > 0) const SizedBox(height: 14),
            _buildGroupHeader(
                sortedKeys[gi], grouped[sortedKeys[gi]]!.length),
            ...grouped[sortedKeys[gi]]!
                .map((w) => _buildCompactCard(context, w)),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String groupName, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _currentDim.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(color: _currentDim.color, width: 3)),
      ),
      child: Row(
        children: [
          Icon(_currentDim.icon,
              size: 16, color: _currentDim.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(groupName,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _currentDim.color)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _currentDim.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count人',
                style: TextStyle(
                    fontSize: 11,
                    color: _currentDim.color,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── 紧凑型作品卡片（分组视图使用） ──────────────────────

  Widget _buildCompactCard(
      BuildContext context, Map<String, dynamic> work) {
    final primary = Theme.of(context).colorScheme.primary;
    final score = work['score'] as int?;
    final viewCount = (work['view_count'] as int?) ?? 0;
    final likeCount = (work['like_count'] as int?) ?? 0;
    final commentCount = (work['comment_count'] as int?) ?? 0;
    final duration = work['video_duration'] as String? ?? '';
    final isTeacherOrAdmin =
        widget.authService.isTeacher || widget.authService.isAdmin;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showWorkDetail(context, work),
        onLongPress: isTeacherOrAdmin
            ? () => _confirmDeleteWork(context, work)
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 播放按钮
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.play_circle_fill,
                        color: primary.withValues(alpha: 0.6), size: 26),
                    if (duration.isNotEmpty)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(duration,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 7,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _studentDisplayName(work, isTeacherOrAdmin),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (work['student_role'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color:
                                  Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _shortRole(
                                  work['student_role'] as String?),
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.orange[700]),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _miniStat(Icons.visibility, '$viewCount',
                            Colors.grey[500]!),
                        const SizedBox(width: 10),
                        _miniStat(Icons.favorite, '$likeCount',
                            Colors.red[300]!),
                        const SizedBox(width: 10),
                        _miniStat(Icons.comment, '$commentCount',
                            Colors.blue[300]!),
                        const Spacer(),
                        if (score != null)
                          Text('${score}分',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: score >= 80
                                      ? Colors.green
                                      : Colors.orange)),
                        if ((work['peer_count'] as int?) != null &&
                            (work['peer_count'] as int) > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                              '互评${(work['peer_avg'] as num?)?.toStringAsFixed(0) ?? '0'}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange[600])),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 完整视频作品卡片（全部视图使用） ────────────────────

  Widget _buildVideoCard(
      BuildContext context, Map<String, dynamic> work) {
    final primary = Theme.of(context).colorScheme.primary;
    final status = work['status'] as String? ?? '待提交';
    final score = work['score'] as int?;
    final viewCount = (work['view_count'] as int?) ?? 0;
    final likeCount = (work['like_count'] as int?) ?? 0;
    final commentCount = (work['comment_count'] as int?) ?? 0;
    final duration = work['video_duration'] as String? ?? '';
    final isTeacherOrAdmin =
        widget.authService.isTeacher || widget.authService.isAdmin;
    final needsScore =
        isTeacherOrAdmin && status == '已提交' && score == null;
    // 学生身份时本人作品视觉强调（边框 + 角标），引导学生在全班 grid 里
    // 一眼找到自己。
    final currentUid = widget.authService.getCurrentUserId();
    final isMine = !isTeacherOrAdmin &&
        currentUid != null &&
        (work['user_id'] as String?) == currentUid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isMine
            ? BorderSide(color: primary, width: 2.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      elevation: isMine ? 4 : 2,
      child: InkWell(
        onTap: () => _showWorkDetail(context, work),
        onLongPress: (widget.authService.isTeacher || widget.authService.isAdmin)
            ? () => _confirmDeleteWork(context, work)
            : null,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 缩略图区 ──────────────────────────────────
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          primary.withValues(alpha: 0.15),
                          primary.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.play_circle_outline,
                          size: 52,
                          color: primary.withValues(alpha: 0.3)),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 28),
                    ),
                  ),
                  if (duration.isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(duration,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  if (needsScore)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('待评分',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (score != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: score >= 90
                              ? Colors.green
                              : score >= 80
                                  ? Colors.blue
                                  : Colors.orange,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$score分',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if ((work['peer_count'] as int?) != null &&
                      (work['peer_count'] as int) > 0)
                    Positioned(
                      left: 8,
                      top: score != null ? 32 : 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange[700],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                            '互评${(work['peer_avg'] as num?)?.toStringAsFixed(0) ?? '0'}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (score == null && !needsScore && status == '待提交')
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('待提交',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
            // ── 信息区 ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 学生姓名 + 角色
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _studentDisplayName(work, isTeacherOrAdmin),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (work['student_role'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _shortRole(
                                work['student_role'] as String?),
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // 项目名称
                  Text(
                    work['title'] as String? ?? '',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // 交互数据行
                  Row(
                    children: [
                      _miniStat(Icons.visibility, '$viewCount',
                          Colors.grey[600]!),
                      const SizedBox(width: 14),
                      _miniStat(Icons.favorite, '$likeCount',
                          Colors.red[300]!),
                      const SizedBox(width: 14),
                      _miniStat(Icons.comment, '$commentCount',
                          Colors.blue[300]!),
                      const Spacer(),
                      if (work['tech_stack'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (work['tech_stack'] as String).length > 12
                                ? '${(work['tech_stack'] as String).substring(0, 12)}…'
                                : work['tech_stack'] as String,
                            style: TextStyle(
                                fontSize: 9, color: primary),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
            ),
            // 学生本人作品角标
            if (isMine)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '我的',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(value,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ── 作品删除（管理员/教师长按）──────────────────────────

  Future<void> _confirmDeleteWork(
      BuildContext ctx, Map<String, dynamic> work) async {
    final workId = work['id'] as int;
    final title = work['title'] as String? ?? '未命名作品';
    final userName = work['student_name'] ?? work['user_id'] ?? '';

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('删除作品'),
        content: Text('确定要删除「$userName」的作品「$title」吗？\n\n此操作将同时删除评分、评论、点赞记录，不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _worksDao.deleteWork(workId);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
              content: Text('已删除'), backgroundColor: Colors.green),
        );
        _loadWorks();
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
              content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── 作品详情 BottomSheet ─────────────────────────────────

  void _showWorkDetail(BuildContext ctx, Map<String, dynamic> work) {
    final workId = work['id'] as int;
    final userId = widget.authService.getCurrentUserId() ?? '';

    // 从 JSON 查找该学生的丰富信息
    final workUserId = work['user_id'] as String?;
    Map<String, dynamic>? studentInfo;
    if (workUserId != null && widget.allStudents.isNotEmpty) {
      try {
        studentInfo = widget.allStudents
            .firstWhere((s) => s['userId'] == workUserId);
      } catch (_) {
        studentInfo = null;
      }
    }

    // 记录播放
    _worksDao.recordView(workId, userId);

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WorkDetailSheet(
        work: work,
        studentInfo: studentInfo,
        authService: widget.authService,
        worksDao: _worksDao,
        onChanged: () {
          _loadWorks();
          widget.onDataChanged?.call();
        },
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  作品详情 BottomSheet                                                       ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

