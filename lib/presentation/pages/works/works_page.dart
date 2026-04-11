import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/constants/app_theme.dart';
import '../../../data/local/works_dao.dart';
import '../../../services/auth_service.dart';

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  作品视角维度（多维过滤，复用考核页的 _GroupDimension 模式）                ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

/// 作品过滤维度定义
enum _WorkDimension {
  all('全部', '', Icons.apps, Colors.blueGrey),
  repo('仓库', 'repo', Icons.folder_copy, Colors.blue),
  classGroup('班组', 'class_group', Icons.class_, Colors.teal),
  project('项目', 'project', Icons.science, Colors.purple),
  role('角色', 'student_role', Icons.engineering, Colors.orange),
  techStack('技术栈', 'tech_stack', Icons.code, Colors.indigo);

  final String label;
  final String dbKey; // 对应 student_works 表中的列名
  final IconData icon;
  final Color color;
  const _WorkDimension(this.label, this.dbKey, this.icon, this.color);
}

/// 匿名展评：所有学生姓名统一显示为此值
const _kAnon = 'xxx';

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  作品展评页面 — 每位同学一个作品 / 多维过滤 / 互评互赞                     ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class WorksPage extends StatefulWidget {
  const WorksPage({super.key});

  @override
  State<WorksPage> createState() => _WorksPageState();
}

class _WorksPageState extends State<WorksPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _worksDao = WorksDao();
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _allStudents = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    // 1. 从 JSON 加载学生数据
    try {
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _allStudents =
          decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      // 2. 同步到数据库（每人一个作品，幂等）
      await _worksDao.syncStudentWorks(_allStudents);
    } catch (_) {}
    // 3. 加载统计概览
    await _loadOverview();
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _loadOverview() async {
    try {
      final ov = await _worksDao.getOverview();
      if (mounted) setState(() => _overview = ov);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradTheme = AppGradientTheme.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final isTeacher = _authService.isTeacher || _authService.isAdmin;

    return Column(
      children: [
        // ── 渐变页头 ───────────────────────────────────────
        Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: gradTheme.linearGradient),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.play_circle_filled,
                      color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('作品展评中心',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  _buildRoleBadge(isTeacher),
                ],
              ),
              const SizedBox(height: 12),
              if (_initialized) _buildHeaderStats(),
            ],
          ),
        ),
        // ── 圆角 TabBar ──────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: primary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(10),
            ),
            splashBorderRadius: BorderRadius.circular(10),
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: '作品展示'),
              Tab(text: '作品记录'),
              Tab(text: '排行榜'),
            ],
          ),
        ),
        // ── TabBarView ───────────────────────────────────
        Expanded(
          child: _initialized
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _GalleryTab(
                      authService: _authService,
                      allStudents: _allStudents,
                      onDataChanged: _loadOverview,
                    ),
                    _RecordsTab(authService: _authService),
                    _LeaderboardTab(authService: _authService),
                  ],
                )
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在加载作品数据...',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(bool isTeacher) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(
        isTeacher ? '教师端' : '学生端',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildHeaderStats() {
    final stats = [
      {
        'icon': Icons.videocam,
        'label': '作品',
        'value': '${_overview['total_works'] ?? 0}'
      },
      {
        'icon': Icons.visibility,
        'label': '播放',
        'value': '${_overview['total_views'] ?? 0}'
      },
      {
        'icon': Icons.favorite,
        'label': '点赞',
        'value': '${_overview['total_likes'] ?? 0}'
      },
      {
        'icon': Icons.comment,
        'label': '评论',
        'value': '${_overview['total_comments'] ?? 0}'
      },
    ];
    return Row(
      children: stats
          .map((s) => Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s['icon'] as IconData,
                        color: Colors.white.withValues(alpha: 0.8), size: 16),
                    const SizedBox(width: 4),
                    Text('${s['value']}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    const SizedBox(width: 2),
                    Text(s['label'] as String,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  公共 UI 辅助                                                              ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

Widget _sectionHeader(String title, {IconData? icon, Color? color}) {
  final c = color ?? Colors.blue;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        if (icon != null) ...[
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 6),
        ],
        Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

Widget _emptyHint(String message, IconData icon) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey[200]!),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(message,
            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      ],
    ),
  );
}

Widget _statChip(IconData icon, String value, String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ],
    ),
  );
}

String _timeAgo(String? isoTime) {
  if (isoTime == null || isoTime.isEmpty) return '';
  try {
    final dt = DateTime.parse(isoTime);
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}月前';
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  } catch (_) {
    return isoTime;
  }
}

/// 截取角色名关键词：'HarmonyOS开发工程师' → 'HarmonyOS'
String _shortRole(String? role) {
  if (role == null || role.isEmpty) return '';
  final idx = role.indexOf('开发');
  if (idx > 0) return role.substring(0, idx);
  return role.length > 10 ? '${role.substring(0, 10)}…' : role;
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 0: 作品展示 (Gallery) — 多维度过滤 + 搜索 + 排序                       ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索姓名、项目、仓库、角色、技术栈...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showWorkDetail(context, work),
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
                            _kAnon,
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () => _showWorkDetail(context, work),
        child: Column(
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
                          _kAnon,
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

class _WorkDetailSheet extends StatefulWidget {
  final Map<String, dynamic> work;
  final Map<String, dynamic>? studentInfo;
  final AuthService authService;
  final WorksDao worksDao;
  final VoidCallback? onChanged;

  const _WorkDetailSheet({
    required this.work,
    this.studentInfo,
    required this.authService,
    required this.worksDao,
    this.onChanged,
  });

  @override
  State<_WorkDetailSheet> createState() => _WorkDetailSheetState();
}

class _WorkDetailSheetState extends State<_WorkDetailSheet> {
  late Map<String, dynamic> _work;
  List<Map<String, dynamic>> _comments = [];
  bool _isLiked = false;
  final _commentCtrl = TextEditingController();
  bool _loadingComments = true;

  @override
  void initState() {
    super.initState();
    _work = Map.from(widget.work);
    _loadInteractionData();
  }

  Future<void> _loadInteractionData() async {
    final userId = widget.authService.getCurrentUserId() ?? '';
    final workId = _work['id'] as int;
    try {
      final liked = await widget.worksDao.isLiked(workId, userId);
      final comments = await widget.worksDao.getComments(workId);
      final refreshed = await widget.worksDao.getWork(workId);
      if (mounted) {
        setState(() {
          _isLiked = liked;
          _comments = comments;
          if (refreshed != null) _work = refreshed;
          _loadingComments = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _toggleLike() async {
    final userId = widget.authService.getCurrentUserId() ?? '';
    final workId = _work['id'] as int;
    try {
      final liked = await widget.worksDao.toggleLike(workId, userId);
      final refreshed = await widget.worksDao.getWork(workId);
      if (mounted) {
        setState(() {
          _isLiked = liked;
          if (refreshed != null) _work = refreshed;
        });
      }
      widget.onChanged?.call();
    } catch (_) {}
  }

  Future<void> _submitComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;
    final user = widget.authService.currentUser;
    final userId = user?.userId ?? '';
    final role = user?.role ?? 'student';
    final name = user?.realName ?? userId;
    try {
      await widget.worksDao.addComment(
        workId: _work['id'] as int,
        userId: userId,
        userName: name,
        userRole: role,
        content: content,
      );
      _commentCtrl.clear();
      await _loadInteractionData();
      widget.onChanged?.call();
    } catch (_) {}
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final score = _work['score'] as int?;
    final tags = _work['tags'] != null
        ? (jsonDecode(_work['tags'] as String) as List)
        : [];
    final isTeacherOrAdmin =
        widget.authService.isTeacher || widget.authService.isAdmin;
    final viewCount = (_work['view_count'] as int?) ?? 0;
    final likeCount = (_work['like_count'] as int?) ?? 0;
    final commentCount = (_work['comment_count'] as int?) ?? 0;
    final si = widget.studentInfo; // 可能为 null

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(20),
        children: [
          // 拖拽手柄
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 视频区 ──────────────────────────────────────
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.12),
                  primary.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.videocam,
                    size: 64, color: primary.withValues(alpha: 0.2)),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 32),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '播放: ${_work['video_url'] ?? '视频文件未配置'}'),
                        ),
                      );
                    },
                  ),
                ),
                if (_work['video_duration'] != null)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_work['video_duration'] as String,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 学生信息 + 交互按钮 ─────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头像
              CircleAvatar(
                radius: 22,
                backgroundColor: primary.withValues(alpha: 0.15),
                child: Text(
                  'x',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kAnon,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (_work['student_role'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange
                                  .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Text(
                              _work['student_role'] as String,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange[700]),
                            ),
                          ),
                        if (_work['repo'] != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue
                                  .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Text(
                              _work['repo'] as String,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue[700]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 交互按钮行
          Row(
            children: [
              _statChip(Icons.visibility, '$viewCount', '播放',
                  Colors.grey[600]!),
              const SizedBox(width: 8),
              InkWell(
                onTap: _toggleLike,
                borderRadius: BorderRadius.circular(8),
                child: _statChip(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  '$likeCount',
                  '点赞',
                  _isLiked ? Colors.red : Colors.grey[600]!,
                ),
              ),
              const SizedBox(width: 8),
              _statChip(
                  Icons.comment, '$commentCount', '评论', Colors.blue),
              const Spacer(),
              if (isTeacherOrAdmin)
                ElevatedButton.icon(
                  onPressed: () => _showScoreDialog(context),
                  icon: const Icon(Icons.rate_review, size: 16),
                  label: Text(score != null ? '重新评分' : '评分'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const Divider(height: 28),

          // ── 项目信息 ────────────────────────────────────
          _sectionHeader('项目信息', icon: Icons.info_outline),
          _infoRow(Icons.science, '项目',
              _work['title'] as String? ?? '未命名'),
          _infoRow(Icons.code, '技术栈',
              _work['tech_stack'] as String? ?? '未指定'),
          if (_work['class_group'] != null)
            _infoRow(Icons.class_, '班组',
                _work['class_group'] as String),

          // 来自 JSON 的丰富信息
          if (si != null) ...[
            if (si['coreDuty'] != null &&
                (si['coreDuty'] as String).isNotEmpty)
              _infoRow(
                  Icons.work, '核心职责', si['coreDuty'] as String),
            if (si['features'] != null &&
                (si['features'] as String).isNotEmpty)
              _infoRow(Icons.auto_awesome, '特色功能',
                  si['features'] as String),
            if (si['remark'] != null &&
                (si['remark'] as String).isNotEmpty)
              _infoRow(Icons.note, '备注', si['remark'] as String),
          ],

          // 功能详情（长文本）
          if (_work['description'] != null &&
              (_work['description'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            _sectionHeader('功能详情', icon: Icons.description),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(_work['description'] as String,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      height: 1.6)),
            ),
          ],

          // 标签
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(t.toString(),
                            style: TextStyle(
                                fontSize: 11, color: primary)),
                      ))
                  .toList(),
            ),
          ],

          // ── 评分详情 ────────────────────────────────────
          if (score != null) ...[
            const SizedBox(height: 16),
            _sectionHeader('评分详情', icon: Icons.star),
            _buildScoreDetail(),
          ],

          // ── 评论区 ──────────────────────────────────────
          const SizedBox(height: 16),
          _sectionHeader('评论区 ($commentCount)', icon: Icons.forum),
          // 发表评论
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: InputDecoration(
                    hintText: '发表评论...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _submitComment,
                icon: Icon(Icons.send, color: primary),
                style: IconButton.styleFrom(
                  backgroundColor: primary.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingComments)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else if (_comments.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Text('暂无评论，快来抢沙发吧~',
                  style: TextStyle(
                      color: Colors.grey[400], fontSize: 13)),
            )
          else
            ..._comments.map((c) => _buildCommentItem(c)),
        ],
      ),
    );
  }

  Widget _buildScoreDetail() {
    final score = _work['score'] as int? ?? 0;
    final scoreColor = score >= 90
        ? Colors.green
        : score >= 80
            ? Colors.blue
            : Colors.orange;
    final dims = [
      {'name': '功能完整性', 'key': 'score_functionality', 'max': 25},
      {'name': '技术深度', 'key': 'score_tech_depth', 'max': 20},
      {'name': '跨框架整合', 'key': 'score_integration', 'max': 25},
      {'name': '性能质量', 'key': 'score_quality', 'max': 15},
      {'name': '文档协作', 'key': 'score_documentation', 'max': 15},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border:
            Border(left: BorderSide(color: scoreColor, width: 3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('$score',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: scoreColor)),
              Text(' / 100',
                  style:
                      TextStyle(fontSize: 16, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 10),
          ...dims.map((d) {
            final val =
                (_work[d['key'] as String] as int?) ?? 0;
            final maxVal = d['max'] as int;
            final ratio = val / maxVal;
            final barColor = ratio >= 0.9
                ? Colors.green
                : ratio >= 0.7
                    ? Colors.blue
                    : Colors.orange;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(d['name'] as String,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor:
                            AlwaysStoppedAnimation(barColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$val/$maxVal',
                      style: TextStyle(
                          fontSize: 11,
                          color: barColor,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
          if (_work['score_comment'] != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('教师评语',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(_work['score_comment'] as String,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[700])),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final role = comment['user_role'] as String? ?? 'student';
    final isTeacher = role == 'teacher' || role == 'admin';
    final roleColor = isTeacher ? Colors.blue : Colors.green;
    final roleLabel = isTeacher ? '教师' : '同学';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTeacher
            ? Colors.blue.withValues(alpha: 0.03)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
              color: roleColor.withValues(alpha: 0.4), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Text(
                  'x',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: roleColor),
                ),
              ),
              const SizedBox(width: 8),
              Text(_kAnon,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(roleLabel,
                    style: TextStyle(
                        fontSize: 9,
                        color: roleColor,
                        fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text(
                  _timeAgo(comment['created_at'] as String?),
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey[400])),
            ],
          ),
          const SizedBox(height: 8),
          Text(comment['content'] as String? ?? '',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[800],
                  height: 1.4)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(label,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── 评分对话框 ──────────────────────────────────────────

  void _showScoreDialog(BuildContext context) {
    double functionality =
        (_work['score_functionality'] as int?)?.toDouble() ?? 15;
    double techDepth =
        (_work['score_tech_depth'] as int?)?.toDouble() ?? 12;
    double integration =
        (_work['score_integration'] as int?)?.toDouble() ?? 15;
    double quality =
        (_work['score_quality'] as int?)?.toDouble() ?? 9;
    double documentation =
        (_work['score_documentation'] as int?)?.toDouble() ?? 9;
    final commentCtrl = TextEditingController(
        text: _work['score_comment'] as String? ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total = functionality.round() +
              techDepth.round() +
              integration.round() +
              quality.round() +
              documentation.round();
          final totalColor = total >= 90
              ? Colors.green
              : total >= 80
                  ? Colors.blue
                  : total >= 60
                      ? Colors.orange
                      : Colors.red;
          return AlertDialog(
            title: Text(
                '评分: $_kAnon',
                style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scoreSlider('功能完整性', functionality, 25,
                        (v) => setDialogState(() => functionality = v)),
                    _scoreSlider('技术实现深度', techDepth, 20,
                        (v) => setDialogState(() => techDepth = v)),
                    _scoreSlider('跨框架整合', integration, 25,
                        (v) => setDialogState(() => integration = v)),
                    _scoreSlider('性能与质量', quality, 15,
                        (v) => setDialogState(() => quality = v)),
                    _scoreSlider('文档与协作', documentation, 15,
                        (v) => setDialogState(() => documentation = v)),
                    const SizedBox(height: 8),
                    Text('总分: $total / 100',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: totalColor)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commentCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: '教师评语',
                        hintText: '请输入评语...',
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final user = widget.authService.currentUser;
                    await widget.worksDao.scoreWork(
                      workId: _work['id'] as int,
                      scorerId:
                          widget.authService.getCurrentUserId(),
                      scorerName: user?.realName ?? '教师',
                      functionality: functionality.round(),
                      techDepth: techDepth.round(),
                      integration: integration.round(),
                      quality: quality.round(),
                      documentation: documentation.round(),
                      comment:
                          commentCtrl.text.trim().isNotEmpty
                              ? commentCtrl.text.trim()
                              : null,
                    );
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('评分成功！'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      await _loadInteractionData();
                      widget.onChanged?.call();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('评分失败: $e')),
                      );
                    }
                  }
                },
                child: const Text('提交评分'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _scoreSlider(String name, double value, int max,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(name,
                      style: const TextStyle(fontSize: 13))),
              Text('${value.round()} / $max',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: max.toDouble(),
            divisions: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 1: 作品记录 (Records) — 多维度排序展示                                 ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

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
      final records = await _worksDao.getWorks(sortBy: _dimension);
      if (mounted) setState(() { _records = records; _isLoading = false; });
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
              _dimChip(
                  '最多播放', 'most_viewed', Icons.visibility, primary),
              const SizedBox(width: 8),
              _dimChip('最热门', 'hottest',
                  Icons.local_fire_department, primary),
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

  Widget _dimChip(
      String label, String value, IconData icon, Color primary) {
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
            color: selected
                ? primary.withValues(alpha: 0.12)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(
                    color: primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? primary : Colors.grey[500]),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: selected
                          ? primary
                          : Colors.grey[600])),
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
    final studentName = _kAnon;

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
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (work['repo'] != null)
                        Text(work['repo'] as String,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Icon(Icons.visibility,
                          size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text('$viewCount',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Icon(Icons.favorite,
                          size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text('$likeCount',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Icon(Icons.comment,
                          size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text('$commentCount',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500])),
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
    final studentName = _kAnon;
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
            'x',
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
    final studentName = _kAnon;

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
