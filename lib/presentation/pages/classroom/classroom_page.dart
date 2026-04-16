import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../data/local/classroom_dao.dart';
import '../../../data/local/class_dao.dart';
import '../../../data/local/user_dao.dart';
import '../../../data/models/user_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/sync_service.dart';
import '../../../core/constants/role_guard.dart';
import '../../widgets/agent_entry_button.dart';

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  课堂管理页面 — 在线状态 / 课堂签到 / 课堂互动                              ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class ClassroomPage extends StatefulWidget {
  const ClassroomPage({super.key});

  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends State<ClassroomPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _classroomDao = ClassroomDao();
  final _classDao = ClassDao();
  final _syncService = SyncService();

  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _init();
  }

  Future<void> _init() async {
    await _loadClasses();
    // 自动将所有学生同步到默认班级（解决只显示少数人的问题）
    if (_selectedClassId != null) {
      await _classDao.syncAllStudentsToClass(_selectedClassId!);
    }
  }

  Future<void> _loadClasses() async {
    try {
      final classes = await _classDao.getActiveClasses();
      if (mounted) {
        setState(() {
          _classes = classes;
          if (classes.isNotEmpty && _selectedClassId == null) {
            _selectedClassId = classes.first['id'] as int;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = _authService.currentUser?.role ?? 'student';
    if (!RoleGuard.isTeacherOrAdmin(role)) {
      return _buildNoPermission(context);
    }

    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // ── 渐变页头（始终显示，不依赖班级加载状态）─────────────────
        _buildHeader(context, primary),
        // ── TabBar ────────────────────────────────────────────────
        Container(
          color: primary.withValues(alpha: 0.04),
          child: TabBar(
            controller: _tabController,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.wifi, size: 18), text: '在线状态'),
              Tab(icon: Icon(Icons.fact_check, size: 18), text: '课堂签到'),
              Tab(icon: Icon(Icons.forum, size: 18), text: '课堂互动'),
              Tab(icon: Icon(Icons.build_circle, size: 18), text: '课堂工具'),
            ],
          ),
        ),
        // ── TabBarView ────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OnlineStatusTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                syncService: _syncService,
              ),
              _CheckinManageTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                authService: _authService,
              ),
              _ClassroomInteractionTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                authService: _authService,
              ),
              _ClassroomToolsTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                authService: _authService,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Color primary) {
    final user = _authService.currentUser;
    final displayName = user?.realName ?? user?.userId ?? '老师';
    final className = _classes.isNotEmpty
        ? (_classes.firstWhere(
            (c) => c['id'] == _selectedClassId,
            orElse: () => _classes.first,
          )['name'] as String? ?? '')
        : '';

    // 直接构建渐变，避免 ThemeExtension 可能的延迟
    final headerGradient = LinearGradient(
      colors: [primary, primary.withValues(alpha: 0.7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: 12,
      ),
      decoration: BoxDecoration(gradient: headerGradient),
      child: Row(
        children: [
          // 图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cast_for_education,
                size: 24, color: Colors.white),
          ),
          const SizedBox(width: 12),
          // 文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('课堂管理',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  '$displayName${className.isNotEmpty ? ' · $className' : ''}',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          // 同步按钮
          const AgentEntryButton(agentId: 'tutor', color: Colors.white),
          ValueListenableBuilder<SyncStatus>(
            valueListenable: _syncService.status,
            builder: (_, syncStatus, __) => IconButton(
              icon: syncStatus == SyncStatus.downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync, color: Colors.white),
              tooltip: '同步学生数据',
              onPressed: syncStatus == SyncStatus.downloading
                  ? null
                  : () async {
                      final result =
                          await _syncService.downloadAllStudentData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.message)),
                        );
                      }
                    },
            ),
          ),
          // 班级选择
          if (_classes.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.class_, color: Colors.white),
              tooltip: '选择班级',
              onSelected: (id) => setState(() => _selectedClassId = id),
              itemBuilder: (_) => _classes
                  .map((c) => PopupMenuItem(
                        value: c['id'] as int,
                        child: Text(c['name'] as String? ?? ''),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildNoPermission(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('课堂管理')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('无权限访问',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8),
            Text('仅教师和管理员可访问课堂管理',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 0: 在线状态                                                           ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

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

class _CheckinManageTab extends StatefulWidget {
  final ClassroomDao classroomDao;
  final int? classId;
  final AuthService authService;

  const _CheckinManageTab({
    required this.classroomDao,
    this.classId,
    required this.authService,
  });

  @override
  State<_CheckinManageTab> createState() => _CheckinManageTabState();
}

class _CheckinManageTabState extends State<_CheckinManageTab> {
  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _records = [];
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _historySessions = [];
  bool _isLoading = true;
  String _filterStatus = 'all'; // all / present / absent / late

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant _CheckinManageTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classId != widget.classId) _loadData();
  }

  Future<void> _loadData() async {
    try {
      final active = await widget.classroomDao
          .getActiveSession(classId: widget.classId);
      List<Map<String, dynamic>> records = [];
      Map<String, int> stats = {};
      if (active != null) {
        records = await widget.classroomDao
            .getCheckinRecords(active['id'] as int);
        stats = await widget.classroomDao
            .getCheckinStats(active['id'] as int);
      }
      final history = await widget.classroomDao
          .getCheckinSessions(classId: widget.classId);
      if (mounted) {
        setState(() {
          _activeSession = active;
          _records = records;
          _stats = stats;
          _historySessions = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startCheckin() async {
    final titleCtrl = TextEditingController(
        text: '第${_historySessions.length + 1}周课堂签到');
    int lateMinutes = 10;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('发起签到', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '签到标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('迟到阈值: ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: lateMinutes.toDouble(),
                      min: 5,
                      max: 30,
                      divisions: 5,
                      label: '$lateMinutes 分钟',
                      onChanged: (v) =>
                          setDialogState(() => lateMinutes = v.round()),
                    ),
                  ),
                  Text('$lateMinutes分钟',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('开始签到')),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final userId = widget.authService.getCurrentUserId() ?? '';
      await widget.classroomDao.createCheckinSession(
        classId: widget.classId,
        title: titleCtrl.text.trim().isEmpty ? '课堂签到' : titleCtrl.text.trim(),
        createdBy: userId,
        lateMinutes: lateMinutes,
      );
      await _loadData();
    }
    titleCtrl.dispose();
  }

  Future<void> _endCheckin() async {
    if (_activeSession == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('结束签到'),
        content: const Text('确定要结束当前签到会话吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('结束')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.classroomDao
          .endCheckinSession(_activeSession!['id'] as int);
      await _loadData();
    }
  }

  Future<void> _markAll() async {
    if (_activeSession == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部签到'),
        content: const Text('确定将所有学生标记为已签到吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.classroomDao
          .markAllPresent(_activeSession!['id'] as int);
      await _loadData();
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> record) async {
    if (_activeSession == null) return;
    final current = record['status'] as String? ?? 'absent';
    final next = current == 'absent'
        ? 'present'
        : current == 'present'
            ? 'late'
            : 'absent';
    await widget.classroomDao.markCheckin(
      sessionId: _activeSession!['id'] as int,
      userId: record['user_id'] as String,
      status: next,
    );
    await _loadData();
  }

  List<Map<String, dynamic>> get _filteredRecords {
    if (_filterStatus == 'all') return _records;
    return _records.where((r) => r['status'] == _filterStatus).toList();
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
          // ── 当前签到会话 / 发起签到 ────────────────────────────
          if (_activeSession != null)
            _buildActiveSessionCard(primary)
          else
            _buildStartCheckinCard(primary),

          const SizedBox(height: 12),

          // ── 签到统计 ────────────────────────────────────────────
          if (_activeSession != null) ...[
            _buildCheckinStats(primary),
            const SizedBox(height: 12),

            // ── 筛选 ──────────────────────────────────────────────
            _buildFilterChips(),
            const SizedBox(height: 8),

            // ── 签到列表 ──────────────────────────────────────────
            if (_filteredRecords.isEmpty)
              _buildEmptyState('暂无匹配的签到记录')
            else
              ..._filteredRecords.map((r) => _buildRecordCard(r)),
          ],

          // ── 历史签到 ────────────────────────────────────────────
          if (_historySessions
              .where((s) => s['status'] == 'ended')
              .isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('历史签到记录'),
            const SizedBox(height: 8),
            ..._historySessions
                .where((s) => s['status'] == 'ended')
                .take(10)
                .map((s) => _buildHistoryCard(s)),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveSessionCard(Color primary) {
    final title = _activeSession!['title'] as String? ?? '课堂签到';
    final startedAt = _activeSession!['started_at'] as String? ?? '';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check, color: primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primary)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('进行中',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('开始时间: ${_formatTime(startedAt)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _markAll,
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('全部签到'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _endCheckin,
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('结束签到'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.red[400]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartCheckinCard(Color primary) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: _startCheckin,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_task, size: 28, color: primary),
              ),
              const SizedBox(height: 12),
              Text('发起签到',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primary)),
              const SizedBox(height: 4),
              const Text('点击开始新的课堂签到',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckinStats(Color primary) {
    final total = _stats['total'] ?? 0;
    final present = _stats['present'] ?? 0;
    final late_ = _stats['late'] ?? 0;
    final absent = _stats['absent'] ?? 0;
    final rate = total > 0 ? ((present + late_) / total * 100) : 0.0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniStat('已到', present, Colors.green),
                _miniStat('迟到', late_, Colors.orange),
                _miniStat('未到', absent, Colors.red),
                _miniStat('总计', total, Colors.blue),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? (present + late_) / total : 0,
                minHeight: 6,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                    rate >= 90 ? Colors.green : Colors.orange),
              ),
            ),
            const SizedBox(height: 4),
            Text('到课率: ${rate.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 6,
      children: [
        _filterChip('全部', 'all'),
        _filterChip('已签到', 'present'),
        _filterChip('迟到', 'late'),
        _filterChip('未签到', 'absent'),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filterStatus == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _filterStatus = value),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final status = record['status'] as String? ?? 'absent';
    final name = record['user_name'] as String? ?? record['user_id'] as String? ?? '?';
    final userId = record['user_id'] as String? ?? '';
    final checkedAt = record['checked_at'] as String?;

    final statusConfig = _getStatusConfig(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: _activeSession != null ? () => _toggleStatus(record) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                  color: statusConfig.color.withValues(alpha: 0.6),
                  width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(statusConfig.icon, color: statusConfig.color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(userId,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusConfig.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusConfig.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusConfig.color)),
                  ),
                  if (checkedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(_formatTime(checkedAt),
                        style:
                            const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> session) {
    final title = session['title'] as String? ?? '签到';
    final startedAt = session['started_at'] as String? ?? '';
    final sessionId = session['id'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: const Icon(Icons.history, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(_formatTime(startedAt),
            style: const TextStyle(fontSize: 11)),
        children: [
          FutureBuilder<Map<String, int>>(
            future: widget.classroomDao.getCheckinStats(sessionId),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              final s = snap.data!;
              final total = s['total'] ?? 0;
              final present = s['present'] ?? 0;
              final late_ = s['late'] ?? 0;
              final rate = total > 0
                  ? ((present + late_) / total * 100).toStringAsFixed(1)
                  : '0.0';
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('已到: $present', style: const TextStyle(fontSize: 12, color: Colors.green)),
                  Text('迟到: $late_', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                  Text('未到: ${s['absent'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                  Text('到课率: $rate%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildEmptyState(String text) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.fact_check_outlined, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status) {
      case 'present':
        return _StatusConfig('已签到', Icons.check_circle, Colors.green);
      case 'late':
        return _StatusConfig('迟到', Icons.access_time, Colors.orange);
      default:
        return _StatusConfig('未签到', Icons.cancel, Colors.red);
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

class _StatusConfig {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusConfig(this.label, this.icon, this.color);
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 2: 课堂互动                                                           ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class _ClassroomInteractionTab extends StatefulWidget {
  final ClassroomDao classroomDao;
  final int? classId;
  final AuthService authService;

  const _ClassroomInteractionTab({
    required this.classroomDao,
    this.classId,
    required this.authService,
  });

  @override
  State<_ClassroomInteractionTab> createState() =>
      _ClassroomInteractionTabState();
}

class _ClassroomInteractionTabState
    extends State<_ClassroomInteractionTab> {
  List<Map<String, dynamic>> _messages = [];
  Map<String, int> _msgStats = {};
  bool _isLoading = true;
  String? _filterType; // null = all
  final _inputCtrl = TextEditingController();
  String _messageType = 'announcement';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ClassroomInteractionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classId != widget.classId) _loadData();
  }

  Future<void> _loadData() async {
    try {
      final messages = await widget.classroomDao
          .getMessages(classId: widget.classId, messageType: _filterType);
      final stats = await widget.classroomDao
          .getMessageStats(classId: widget.classId);
      if (mounted) {
        setState(() {
          _messages = messages;
          _msgStats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final content = _inputCtrl.text.trim();
    if (content.isEmpty) return;

    final user = widget.authService.currentUser;
    if (user == null) return;

    await widget.classroomDao.sendMessage(
      classId: widget.classId,
      senderId: user.userId,
      senderName: user.realName ?? user.userId,
      senderRole: user.role,
      content: content,
      messageType: _messageType,
    );
    _inputCtrl.clear();
    await _loadData();
  }

  Future<void> _deleteMessage(int messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除这条消息吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.classroomDao.deleteMessage(messageId);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 消息统计 ──────────────────────────────────────
                Row(
                  children: [
                    _msgStatChip('公告', _msgStats['announcement'] ?? 0,
                        Icons.campaign, Colors.blue),
                    const SizedBox(width: 6),
                    _msgStatChip('提问', _msgStats['question'] ?? 0,
                        Icons.help_outline, Colors.green),
                    const SizedBox(width: 6),
                    _msgStatChip('回答', _msgStats['answer'] ?? 0,
                        Icons.question_answer, Colors.orange),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 筛选 ──────────────────────────────────────────
                Wrap(
                  spacing: 6,
                  children: [
                    FilterChip(
                      label: const Text('全部', style: TextStyle(fontSize: 12)),
                      selected: _filterType == null,
                      onSelected: (_) {
                        setState(() => _filterType = null);
                        _loadData();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    FilterChip(
                      label: const Text('公告', style: TextStyle(fontSize: 12)),
                      selected: _filterType == 'announcement',
                      onSelected: (_) {
                        setState(() => _filterType = 'announcement');
                        _loadData();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    FilterChip(
                      label: const Text('提问', style: TextStyle(fontSize: 12)),
                      selected: _filterType == 'question',
                      onSelected: (_) {
                        setState(() => _filterType = 'question');
                        _loadData();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    FilterChip(
                      label: const Text('回答', style: TextStyle(fontSize: 12)),
                      selected: _filterType == 'answer',
                      onSelected: (_) {
                        setState(() => _filterType = 'answer');
                        _loadData();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 消息列表 ──────────────────────────────────────
                if (_messages.isEmpty)
                  _buildEmptyState()
                else
                  ..._messages.map((m) => _buildMessageCard(m, primary)),
              ],
            ),
          ),
        ),

        // ── 底部输入栏 ────────────────────────────────────────────
        _buildInputBar(primary),
      ],
    );
  }

  Widget _msgStatChip(
      String label, int count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text('$label $count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(Map<String, dynamic> msg, Color primary) {
    final type = msg['message_type'] as String? ?? 'announcement';
    final senderName = msg['sender_name'] as String? ?? '未知';
    final senderRole = msg['sender_role'] as String? ?? 'student';
    final content = msg['content'] as String? ?? '';
    final createdAt = msg['created_at'] as String? ?? '';
    final msgId = msg['id'] as int;
    final senderId = msg['sender_id'] as String? ?? '';
    final currentUserId = widget.authService.getCurrentUserId() ?? '';
    final isOwn = senderId == currentUserId;
    final isAnswer = type == 'answer';

    final typeConfig = _getTypeConfig(type);
    final isTeacherMsg = senderRole == 'teacher' || senderRole == 'admin';

    return Padding(
      padding: EdgeInsets.only(left: isAnswer ? 24 : 0, bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(
                  color: typeConfig.color.withValues(alpha: 0.5),
                  width: 3),
            ),
          ),
          child: InkWell(
            onLongPress: isOwn ? () => _deleteMessage(msgId) : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(typeConfig.icon,
                          size: 16, color: typeConfig.color),
                      const SizedBox(width: 6),
                      Text(senderName,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isTeacherMsg ? Colors.blue : Colors.green)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isTeacherMsg ? '教师' : '同学',
                          style: TextStyle(
                              fontSize: 9,
                              color:
                                  isTeacherMsg ? Colors.blue : Colors.green),
                        ),
                      ),
                      const Spacer(),
                      Text(_formatTimeAgo(createdAt),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(content,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(Color primary) {
    final isTeacher = widget.authService.isTeacher ||
        widget.authService.isAdmin;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 消息类型选择
            PopupMenuButton<String>(
              initialValue: _messageType,
              onSelected: (v) => setState(() => _messageType = v),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getTypeConfig(_messageType).icon,
                        size: 14, color: primary),
                    const SizedBox(width: 4),
                    Text(
                      _getTypeConfig(_messageType).label,
                      style: TextStyle(fontSize: 12, color: primary),
                    ),
                    Icon(Icons.arrow_drop_down, size: 16, color: primary),
                  ],
                ),
              ),
              itemBuilder: (_) => [
                if (isTeacher)
                  const PopupMenuItem(
                      value: 'announcement', child: Text('公告')),
                const PopupMenuItem(value: 'question', child: Text('提问')),
                const PopupMenuItem(value: 'answer', child: Text('回答')),
              ],
            ),
            const SizedBox(width: 8),
            // 输入框
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            // 发送按钮
            IconButton(
              onPressed: _sendMessage,
              icon: Icon(Icons.send, color: primary),
              style: IconButton.styleFrom(
                backgroundColor: primary.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('暂无课堂消息',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('发布第一条公告或提问吧',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  _MsgTypeConfig _getTypeConfig(String type) {
    switch (type) {
      case 'announcement':
        return _MsgTypeConfig('公告', Icons.campaign, Colors.blue);
      case 'question':
        return _MsgTypeConfig('提问', Icons.help_outline, Colors.green);
      case 'answer':
        return _MsgTypeConfig('回答', Icons.question_answer, Colors.orange);
      default:
        return _MsgTypeConfig('消息', Icons.message, Colors.grey);
    }
  }

  String _formatTimeAgo(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}

class _MsgTypeConfig {
  final String label;
  final IconData icon;
  final Color color;
  const _MsgTypeConfig(this.label, this.icon, this.color);
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 3: 课堂工具 — 随机点名 / 快速投票 / 倒计时器                          ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class _ClassroomToolsTab extends StatefulWidget {
  final ClassroomDao classroomDao;
  final int? classId;
  final AuthService authService;

  const _ClassroomToolsTab({
    required this.classroomDao,
    this.classId,
    required this.authService,
  });

  @override
  State<_ClassroomToolsTab> createState() => _ClassroomToolsTabState();
}

class _ClassroomToolsTabState extends State<_ClassroomToolsTab> {
  final _userDao = UserDao();

  // ── 随机点名 ──
  List<UserModel> _students = [];
  String? _selectedStudent;
  bool _isRolling = false;
  Timer? _rollTimer;
  int _rollCount = 0;

  // ── 快速投票 ──
  final _pollQuestionCtrl = TextEditingController();
  List<String> _pollOptions = ['选项A', '选项B'];
  Map<String, int> _pollResults = {};
  bool _pollActive = false;
  String? _pollQuestion;

  // ── 倒计时 ──
  int _timerSeconds = 300; // 5分钟
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  bool _timerRunning = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    _countdownTimer?.cancel();
    _pollQuestionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      final students = await _userDao.getStudents();
      if (mounted) setState(() => _students = students);
    } catch (_) {}
  }

  // ── 随机点名逻辑 ──

  void _startRoll() {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有学生数据')),
      );
      return;
    }

    setState(() {
      _isRolling = true;
      _rollCount = 0;
      _selectedStudent = null;
    });

    final random = Random();
    _rollTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      _rollCount++;
      final idx = random.nextInt(_students.length);
      final s = _students[idx];
      setState(() => _selectedStudent = s.realName ?? s.userId);

      // 逐渐减速后停止
      if (_rollCount > 20 + random.nextInt(15)) {
        timer.cancel();
        setState(() => _isRolling = false);
      }
    });
  }

  // ── 投票逻辑 ──

  void _startPoll() {
    final question = _pollQuestionCtrl.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入投票问题')),
      );
      return;
    }

    setState(() {
      _pollQuestion = question;
      _pollActive = true;
      _pollResults = {for (var opt in _pollOptions) opt: 0};
    });
  }

  void _vote(String option) {
    setState(() {
      _pollResults[option] = (_pollResults[option] ?? 0) + 1;
    });
  }

  void _endPoll() {
    setState(() => _pollActive = false);
  }

  void _resetPoll() {
    setState(() {
      _pollActive = false;
      _pollQuestion = null;
      _pollResults.clear();
      _pollQuestionCtrl.clear();
      _pollOptions = ['选项A', '选项B'];
    });
  }

  // ── 倒计时逻辑 ──

  void _startCountdown() {
    setState(() {
      _remainingSeconds = _timerSeconds;
      _timerRunning = true;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        setState(() => _timerRunning = false);
        // 时间到提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏰ 时间到！'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  void _pauseCountdown() {
    _countdownTimer?.cancel();
    setState(() => _timerRunning = false);
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _timerRunning = false;
      _remainingSeconds = 0;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. 随机点名 ──
          _buildToolCard(
            title: '随机点名',
            icon: Icons.person_search,
            color: Colors.orange,
            isDark: isDark,
            child: Column(
              children: [
                // 显示区域
                Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    color: _isRolling
                        ? Colors.orange.withValues(alpha: 0.1)
                        : (isDark ? Colors.grey[850] : Colors.grey[50]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isRolling ? Colors.orange : Colors.grey.withValues(alpha: 0.2),
                      width: _isRolling ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 100),
                    child: Text(
                      _selectedStudent ?? '点击开始',
                      key: ValueKey(_selectedStudent),
                      style: TextStyle(
                        fontSize: _isRolling ? 28 : 24,
                        fontWeight: FontWeight.bold,
                        color: _selectedStudent != null && !_isRolling
                            ? Colors.orange[700]
                            : (isDark ? Colors.white60 : Colors.black54),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _isRolling ? null : _startRoll,
                      icon: Icon(_isRolling ? Icons.hourglass_top : Icons.shuffle, size: 18),
                      label: Text(_isRolling ? '选择中...' : '开始点名'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('共 ${_students.length} 名学生',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 2. 快速投票 ──
          _buildToolCard(
            title: '快速投票',
            icon: Icons.poll,
            color: Colors.blue,
            isDark: isDark,
            child: _pollActive ? _buildPollResults() : _buildPollSetup(),
          ),
          const SizedBox(height: 16),

          // ── 3. 倒计时器 ──
          _buildToolCard(
            title: '倒计时器',
            icon: Icons.timer,
            color: Colors.red,
            isDark: isDark,
            child: _buildCountdown(primary, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
    required Widget child,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 15, color: color)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  // ── 投票设置界面 ──

  Widget _buildPollSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _pollQuestionCtrl,
          decoration: InputDecoration(
            hintText: '输入投票问题...',
            hintStyle: const TextStyle(fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        ...List.generate(_pollOptions.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Text('${String.fromCharCode(65 + i)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: Colors.blue)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '选项${String.fromCharCode(65 + i)}',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  style: const TextStyle(fontSize: 12),
                  controller: TextEditingController(text: _pollOptions[i]),
                  onChanged: (v) => _pollOptions[i] = v,
                ),
              ),
              if (_pollOptions.length > 2)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _pollOptions.removeAt(i)),
                ),
            ],
          ),
        )),
        Row(
          children: [
            if (_pollOptions.length < 6)
              TextButton.icon(
                onPressed: () => setState(() =>
                    _pollOptions.add('选项${String.fromCharCode(65 + _pollOptions.length)}')),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加选项', style: TextStyle(fontSize: 12)),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _startPoll,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('开始投票', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  // ── 投票结果界面 ──

  Widget _buildPollResults() {
    final totalVotes = _pollResults.values.fold(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_pollQuestion ?? '', style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        ..._pollResults.entries.map((e) {
          final pct = totalVotes > 0 ? e.value / totalVotes : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: _pollActive ? () => _vote(e.key) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 6,
                              backgroundColor: Colors.grey.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation(
                                Colors.blue.withValues(alpha: 0.7)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${e.value}票 (${(pct * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: Colors.blue[700])),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('总票数：$totalVotes',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const Spacer(),
            if (_pollActive)
              FilledButton.tonal(
                onPressed: _endPoll,
                child: const Text('结束投票', style: TextStyle(fontSize: 12)),
              ),
            if (!_pollActive)
              OutlinedButton(
                onPressed: _resetPoll,
                child: const Text('新建投票', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }

  // ── 倒计时界面 ──

  Widget _buildCountdown(Color primary, bool isDark) {
    return Column(
      children: [
        // 时间设置
        if (!_timerRunning && _remainingSeconds == 0) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [1, 2, 3, 5, 10, 15, 20, 30].map((m) => ChoiceChip(
              label: Text('${m}分钟', style: const TextStyle(fontSize: 12)),
              selected: _timerSeconds == m * 60,
              onSelected: (v) => setState(() => _timerSeconds = m * 60),
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],

        // 倒计时显示
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: _timerRunning
                ? (_remainingSeconds <= 30
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.05))
                : (isDark ? Colors.grey[850] : Colors.grey[50]),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            _remainingSeconds > 0
                ? _formatTime(_remainingSeconds)
                : _formatTime(_timerSeconds),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: _timerRunning
                  ? (_remainingSeconds <= 30 ? Colors.red : primary)
                  : Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 控制按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_timerRunning && _remainingSeconds == 0)
              FilledButton.icon(
                onPressed: _startCountdown,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('开始'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            if (_timerRunning) ...[
              FilledButton.tonal(
                onPressed: _pauseCountdown,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause, size: 18),
                    SizedBox(width: 4),
                    Text('暂停'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _resetCountdown,
                child: const Text('重置'),
              ),
            ],
            if (!_timerRunning && _remainingSeconds > 0) ...[
              FilledButton.icon(
                onPressed: _startCountdown,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('继续'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _resetCountdown,
                child: const Text('重置'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
