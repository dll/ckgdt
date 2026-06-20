part of '../classroom_page.dart';

class _OnlineStatusTab extends StatefulWidget {
  final ClassroomDao classroomDao;
  final int? classId;
  final SyncService syncService;

  const _OnlineStatusTab({
    required this.classroomDao,
    this.classId,
    required this.syncService,
  });

  @override
  State<_OnlineStatusTab> createState() => _OnlineStatusTabState();
}

enum _SortMode { onlineFirst, nameAsc, lastActiveDesc }

class _OnlineStatusTabState extends State<_OnlineStatusTab> {
  List<Map<String, dynamic>> _students = [];
  Map<String, int> _stats = {'total': 0, 'online': 0, 'offline': 0};
  bool _isLoading = true;
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.onlineFirst;
  Timer? _refreshTimer;
  String? _lastSyncedTime;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadLastSyncTime();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadData());

    // 监听同步状态变化，完成后自动刷新
    widget.syncService.status.addListener(_onSyncStatusChanged);

    // 首次打开时自动触发一次同步
    _triggerSync();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    widget.syncService.status.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _OnlineStatusTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classId != widget.classId) _loadData();
  }

  // ── 同步集成 ──────────────────────────────────────────────────────────

  void _onSyncStatusChanged() {
    final s = widget.syncService.status.value;
    if (mounted) {
      setState(() => _isSyncing = (s == SyncStatus.downloading));
    }
    if (s == SyncStatus.idle) {
      _loadData();
      _loadLastSyncTime();
    }
  }

  Future<void> _loadLastSyncTime() async {
    final config = await widget.syncService.getConfig();
    if (mounted) {
      setState(() => _lastSyncedTime = config.lastDownload);
    }
  }

  Future<void> _triggerSync() async {
    await widget.syncService.downloadAllStudentData();
  }

  String _formatTimeAgo(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '从未同步';
    try {
      final dt = DateTime.parse(isoTime);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      return '${diff.inDays}天前';
    } catch (_) {
      return '未知';
    }
  }

  Future<void> _loadData() async {
    try {
      final students = await widget.classroomDao
          .getStudentsWithStatus(classId: widget.classId);
      final stats = await widget.classroomDao
          .getOnlineStats(classId: widget.classId);
      if (mounted) {
        setState(() {
          _students = students;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    var list = _students;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) {
        final name = (s['real_name'] as String? ?? '').toLowerCase();
        final id = (s['user_id'] as String? ?? '').toLowerCase();
        return name.contains(q) || id.contains(q);
      }).toList();
    }
    switch (_sortMode) {
      case _SortMode.onlineFirst:
        list.sort((a, b) {
          final aOnline = (a['is_online'] as int?) ?? 0;
          final bOnline = (b['is_online'] as int?) ?? 0;
          if (aOnline != bOnline) return bOnline - aOnline;
          return (a['real_name'] as String? ?? '')
              .compareTo(b['real_name'] as String? ?? '');
        });
      case _SortMode.nameAsc:
        list.sort((a, b) => (a['real_name'] as String? ?? '')
            .compareTo(b['real_name'] as String? ?? ''));
      case _SortMode.lastActiveDesc:
        list.sort((a, b) {
          final aTime = a['last_active'] as String? ?? '';
          final bTime = b['last_active'] as String? ?? '';
          return bTime.compareTo(aTime);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 统计卡片 ────────────────────────────────────────────
          Row(
            children: [
              _statCard('总人数', _stats['total'] ?? 0,
                  Icons.people, Colors.blue, primary),
              const SizedBox(width: 8),
              _statCard('在线', _stats['online'] ?? 0,
                  Icons.wifi, Colors.green, primary),
              const SizedBox(width: 8),
              _statCard('离线', _stats['offline'] ?? 0,
                  Icons.wifi_off, Colors.grey, primary),
            ],
          ),
          const SizedBox(height: 12),

          // ── 同步状态栏 ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isSyncing ? null : _triggerSync,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 16),
                  label: Text(_isSyncing ? '同步中...' : '同步学生数据',
                      style: const TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                Icon(Icons.access_time, size: 14,
                    color: Colors.grey.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  '上次同步: ${_formatTimeAgo(_lastSyncedTime)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 搜索 + 排序 ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索学生姓名或学号...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<_SortMode>(
                value: _sortMode,
                underline: const SizedBox(),
                icon: const Icon(Icons.sort, size: 20),
                items: const [
                  DropdownMenuItem(
                      value: _SortMode.onlineFirst,
                      child: Text('在线优先', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: _SortMode.nameAsc,
                      child: Text('按姓名', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: _SortMode.lastActiveDesc,
                      child: Text('最近活跃', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sortMode = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 学生列表 ────────────────────────────────────────────
          if (_filteredStudents.isEmpty)
            _buildEmptyState('暂无学生数据', Icons.people_outline)
          else
            ..._filteredStudents.map((s) => _buildDismissibleStudentCard(s, primary)),
        ],
      ),
    );
  }

  Widget _statCard(
      String label, int value, IconData icon, Color color, Color primary) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(label,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, Color primary) {
    final isOnline = (student['is_online'] as int?) == 1;
    final name = student['real_name'] as String? ?? student['user_id'] as String? ?? '?';
    final userId = student['user_id'] as String? ?? '';
    final lastActive = student['last_active'] as String?;
    final lastLogin = student['last_login'] as String?;
    final statusColor = isOnline ? Colors.green : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
                color: statusColor.withValues(alpha: 0.6), width: 3),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 在线状态圆点
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: isOnline
                    ? [BoxShadow(
                        color: Colors.green.withValues(alpha: 0.4),
                        blurRadius: 6)]
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // 头像
            CircleAvatar(
              radius: 18,
              backgroundColor: primary.withValues(alpha: 0.1),
              child: Text(
                name.isNotEmpty ? name.characters.first : '?',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: primary),
              ),
            ),
            const SizedBox(width: 10),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text(userId,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline
                        ? '在线 · ${_timeAgo(lastActive)}'
                        : '离线 · ${lastActive != null ? _timeAgo(lastActive) : "从未登录"}',
                    style: TextStyle(
                        fontSize: 11,
                        color: isOnline ? Colors.green[700] : Colors.grey),
                  ),
                ],
              ),
            ),
            // 最后登录
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isOnline ? '在线' : '离线',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor),
                  ),
                ),
                if (lastLogin != null) ...[
                  const SizedBox(height: 4),
                  Text('登录: ${_timeAgo(lastLogin)}',
                      style:
                          const TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 带滑动删除的学生卡片
  Widget _buildDismissibleStudentCard(Map<String, dynamic> student, Color primary) {
    final userId = student['user_id'] as String? ?? '';
    final name = student['real_name'] as String? ?? userId;

    return Dismissible(
      key: Key('student_$userId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 22),
            SizedBox(height: 2),
            Text('清除记录', style: TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认清除'),
            content: Text('确定要清除 $name 的在线记录吗？\n此操作不会删除学生账号。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('清除'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) async {
        await widget.classroomDao.clearLastActive(userId);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已清除 $name 的在线记录')),
          );
        }
      },
      child: _buildStudentCard(student, primary),
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  String _timeAgo(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '未知';
    try {
      final dt = DateTime.parse(isoTime);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '未知';
    }
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 1: 课堂签到                                                           ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

