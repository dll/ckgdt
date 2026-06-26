part of '../classroom_page.dart';

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
      color: primary.withOpacity(0.05),
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
                    color: Colors.green.withOpacity(0.15),
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
                  color: primary.withOpacity(0.1),
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
                  color: statusConfig.color.withOpacity(0.6),
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
                      color: statusConfig.color.withOpacity(0.12),
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
        return const _StatusConfig('已签到', Icons.check_circle, Colors.green);
      case 'late':
        return const _StatusConfig('迟到', Icons.access_time, Colors.orange);
      default:
        return const _StatusConfig('未签到', Icons.cancel, Colors.red);
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e, st) {
      swallowDebug(e, tag: 'checkin_manage_tab._formatTime', stack: st);
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

