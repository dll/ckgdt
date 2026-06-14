import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/class_dao.dart';
import '../../../data/local/notification_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/sync_service.dart';

class NotificationManagePage extends StatefulWidget {
  const NotificationManagePage({super.key});

  @override
  State<NotificationManagePage> createState() => _NotificationManagePageState();
}

class _NotificationManagePageState extends State<NotificationManagePage>
    with SingleTickerProviderStateMixin {
  final _dao = NotificationDao();
  final _auth = AuthService();
  final _classDao = ClassDao();

  late TabController _tabCtrl;

  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _targetType = 'all';
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isPublishing = false;

  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _isLoadingList = true;
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  Map<String, dynamic> _userStats = {};
  Map<String, dynamic> _globalStats = {};
  List<Map<String, dynamic>> _dailyStats = [];
  bool _isLoadingStats = true;

  String? _userId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _isTeacherOrAdmin ? 3 : 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        if (_tabCtrl.index == 0) { _loadNotifications(); }
        if (_tabCtrl.index == 2 || (_tabCtrl.index == 1 && !_isTeacherOrAdmin)) { _loadStats(); }
      }
    });
    _userId = _auth.getCurrentUserId();
    _loadNotifications();
    if (_isTeacherOrAdmin) _loadClasses();
  }

  bool get _isTeacherOrAdmin => _auth.isTeacher || _auth.isAdmin;

  @override
  void dispose() {
    _tabCtrl.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _dao.cleanOrphanedRecipients();
      final list = await _dao.getNotificationsForUser(uid);
      final unread = await _dao.getUnreadCount(uid);
      if (_isTeacherOrAdmin) {
        for (int i = 0; i < list.length; i++) {
          if (list[i]['creator_id'] == uid) {
            final s = await _dao.getNotificationReadStats(list[i]['id'] as int);
            final m = Map<String, dynamic>.from(list[i]);
            m['read_count'] = s['read_count'];
            m['total_recipients'] = s['total'];
            list[i] = m;
          }
        }
      }
      if (mounted) setState(() {
        _notifications = list;
        _unreadCount = unread;
        _isLoadingList = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingList = false);
    }
  }

  Future<void> _loadStats() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final us = await _dao.getUserStats(uid);
      final ds = await _dao.getDailyStats(uid);
      Map<String, dynamic> gs = {};
      if (_isTeacherOrAdmin) gs = await _dao.getGlobalStats();
      if (mounted) setState(() {
        _userStats = us;
        _globalStats = gs;
        _dailyStats = ds;
        _isLoadingStats = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _loadClasses() async {
    try {
      final list = await _classDao.getActiveClasses();
      if (mounted) setState(() => _classes = list);
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    final uid = _userId;
    if (uid == null) return;
    await _dao.markAllAsRead(uid);
    await _loadNotifications();
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    await _dao.deleteNotifications(_selectedIds.toList());
    _selectedIds.clear();
    _isSelectionMode = false;
    await _loadNotifications();
  }

  Future<void> _publishNotification() async {
    if (!_formKey.currentState!.validate()) return;
    if (_targetType == 'class' && _selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择目标班级')));
      return;
    }
    setState(() => _isPublishing = true);
    try {
      final notificationId = await _dao.createNotification(
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        creatorId: _userId,
        targetType: _targetType,
        targetId: _targetType == 'class' ? _selectedClassId.toString() : null,
        type: 'manual',
      );

      // 发布通知（Gitee 同步后续接入）
      if (notificationId != null && mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知已发布')));
        _titleCtrl.clear();
        _contentCtrl.clear();
        _tabCtrl.animateTo(0);
        _loadNotifications();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发布失败: $e')));
      }
    }
  }

  void _showDetail(Map<String, dynamic> n) async {
    await _dao.markAsRead(n['id'] as int, _userId!);
    _loadNotifications();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(_typeIcon(n['type'] as String? ?? 'manual'), size: 20, color: NoirTokens.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(n['title'] as String? ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
        content: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(n['content'] as String? ?? '', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.person_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(n['creator_name'] as String? ?? '系统', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              const Spacer(),
              Text(_formatTime(n['created_at'] as String? ?? ''), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ]),
            if (n['read_count'] != null && n['total_recipients'] != null) ...[
              const Divider(height: 20),
              Row(children: [
                Icon(Icons.visibility, size: 14, color: Colors.green),
                const SizedBox(width: 4),
                Text('${n['read_count']}/${n['total_recipients']} 已读',
                    style: TextStyle(fontSize: 12, color: Colors.green[700])),
              ]),
            ],
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知管理'),
        backgroundColor: NoirTokens.ink,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: NoirTokens.accent,
            unselectedLabelColor: NoirTokens.paper.withValues(alpha: 0.5),
            indicatorColor: NoirTokens.accent,
            tabs: [
              Tab(text: '通知列表 ($_unreadCount)'),
              if (_isTeacherOrAdmin) const Tab(text: '发送通知'),
              const Tab(text: '数据统计'),
            ],
          ),
        ),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _deleteSelected,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildNotificationList(),
          if (_isTeacherOrAdmin) _buildComposeForm(),
          _buildStats(),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    if (_isLoadingList) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 64, color: NoirTokens.paper.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text('暂无通知', style: TextStyle(color: NoirTokens.paper.withValues(alpha: 0.3), fontSize: 14)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(children: [
                Text('共 ${_notifications.length} 条',
                    style: TextStyle(fontSize: 12, color: NoirTokens.paper.withValues(alpha: 0.4))),
                const Spacer(),
                if (_unreadCount > 0)
                  GestureDetector(
                    onTap: _markAllAsRead,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: NoirTokens.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('全部已读 ($_unreadCount)',
                          style: TextStyle(fontSize: 11, color: NoirTokens.accent, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            );
          }
          final n = _notifications[i - 1];
          final id = n['id'] as int;
          final isUnread = n['is_read'] == 0;
          final selected = _selectedIds.contains(id);
          return _buildNotificationCard(n, id, isUnread, selected);
        },
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n, int id, bool isUnread, bool selected) {
    final title = n['title'] as String? ?? '';
    final content = n['content'] as String? ?? '';
    final type = n['type'] as String? ?? 'manual';
    final createdAt = n['created_at'] as String? ?? '';
    final sender = n['creator_name'] as String? ?? '系统';
    final rc = n['read_count'];
    final tr = n['total_recipients'];

    return GestureDetector(
      onLongPress: () {
        if (!_isSelectionMode) setState(() { _isSelectionMode = true; _selectedIds.add(id); });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: _isSelectionMode && selected
              ? NoirTokens.accent.withValues(alpha: 0.08)
              : isUnread
                  ? NoirTokens.accent.withValues(alpha: 0.03)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isUnread
              ? Border(left: BorderSide(color: NoirTokens.accent, width: 3))
              : null,
        ),
        child: ListTile(
          leading: _isSelectionMode
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelection(id),
                  activeColor: NoirTokens.accent,
                )
              : CircleAvatar(
                  radius: 18,
                  backgroundColor: NoirTokens.accent.withValues(alpha: 0.12),
                  child: Icon(_typeIcon(type), size: 18, color: NoirTokens.accent),
                ),
          title: Row(children: [
            Expanded(child: Text(title, style: TextStyle(
              fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14, color: NoirTokens.paper,
            ), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (isUnread)
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: NoirTokens.accent),
              ),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(content, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: NoirTokens.paper.withValues(alpha: 0.5))),
            const SizedBox(height: 4),
            Row(children: [
              Text(sender, style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.35))),
              const SizedBox(width: 8),
              Text(_formatTime(createdAt), style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.35))),
              if (rc != null && tr != null) ...[
                const Spacer(),
                Icon(Icons.visibility, size: 10, color: Colors.green.withValues(alpha: 0.5)),
                const SizedBox(width: 2),
                Text('$rc/$tr', style: TextStyle(fontSize: 10, color: Colors.green.withValues(alpha: 0.6))),
              ],
            ]),
          ]),
          onTap: _isSelectionMode
              ? () => _toggleSelection(id)
              : () => _showDetail(n),
        ),
      ),
    );
  }

  Widget _buildComposeForm() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: '通知标题',
              hintText: '请输入通知标题',
              prefixIcon: const Icon(Icons.title),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            maxLength: 100,
            validator: (v) => v == null || v.trim().isEmpty ? '请输入通知标题' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _contentCtrl,
            decoration: InputDecoration(
              labelText: '通知内容',
              hintText: '请输入通知内容...',
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 100),
                child: Icon(Icons.article_outlined),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            maxLines: 6,
            maxLength: 1000,
            validator: (v) => v == null || v.trim().isEmpty ? '请输入通知内容' : null,
          ),
          const SizedBox(height: 20),
          Text('发送范围', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              RadioListTile<String>(
                title: const Text('全部学生'),
                subtitle: const Text('发送给所有活跃学生'),
                value: 'all', groupValue: _targetType,
                onChanged: (v) { setState(() { _targetType = v!; _selectedClassId = null; }); },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              RadioListTile<String>(
                title: const Text('指定班级'),
                subtitle: const Text('仅发送给选定班级的学生'),
                value: 'class', groupValue: _targetType,
                onChanged: (v) { setState(() => _targetType = v!); },
              ),
            ]),
          ),
          if (_targetType == 'class') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedClassId,
              decoration: InputDecoration(
                labelText: '选择班级',
                prefixIcon: const Icon(Icons.class_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _classes.map((cls) => DropdownMenuItem<int>(
                value: cls['id'] as int,
                child: Text('${cls['name']} (${cls['student_count'] ?? 0}人)'),
              )).toList(),
              onChanged: (v) => setState(() => _selectedClassId = v),
              hint: const Text('请选择班级'),
              validator: (v) => _targetType == 'class' && v == null ? '请选择目标班级' : null,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isPublishing ? null : _publishNotification,
            icon: _isPublishing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(_isPublishing ? '发布中...' : '发布通知'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildStats() {
    if (_isLoadingStats) return const Center(child: CircularProgressIndicator());
    final us = _userStats;
    final total = us['total'] as int? ?? 0;
    final unread = us['unread'] as int? ?? 0;
    final readToday = us['read_today'] as int? ?? 0;
    final readRate = total > 0 ? ((total - unread) / total * 100).toStringAsFixed(1) : '0.0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 概览卡片
        Text('我的通知', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: NoirTokens.paper)),
        const SizedBox(height: 12),
        Row(children: [
          _statCard('已收通知', '$total', Icons.notifications, Colors.blue, 0),
          const SizedBox(width: 8),
          _statCard('未读', '$unread', Icons.mark_email_unread, Colors.orange, 1),
          const SizedBox(width: 8),
          _statCard('今日已读', '$readToday', Icons.today, Colors.green, 2),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _statCard('已读率', '$readRate%', Icons.visibility, Colors.purple, 3),
          if (_isTeacherOrAdmin) ...[
            const SizedBox(width: 8),
            _statCard('全部通知',
                '${_globalStats['total_notifications'] ?? 0}',
                Icons.analytics_outlined, NoirTokens.accent, 4),
          ],
        ]),
        const SizedBox(height: 24),

        // 近 7 天趋势
        Text('近 7 天趋势', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: NoirTokens.paper)),
        const SizedBox(height: 12),
        _buildDailyChart(),

        // 管理员额外全局统计
        if (_isTeacherOrAdmin && _globalStats.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('通知类型分布', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: NoirTokens.paper)),
          const SizedBox(height: 12),
          _buildTypeDistribution(),
        ],

        // 月度统计
        const SizedBox(height: 24),
        Text('月度统计', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: NoirTokens.paper)),
        const SizedBox(height: 12),
        _buildMonthlyStats(),

        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, int _) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: NoirTokens.paper.withValues(alpha: 0.6))),
          ]),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  Widget _buildDailyChart() {
    if (_dailyStats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: NoirTokens.inkDeep,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('暂无数据', style: TextStyle(color: NoirTokens.paper.withValues(alpha: 0.3))),
        ),
      );
    }
    final maxCount = _dailyStats.fold<int>(1, (m, d) => (d['count'] as int? ?? 0) > m ? (d['count'] as int) : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NoirTokens.inkDeep,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Row(children: [
          Text('日期', style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.4))),
          const Spacer(),
          Text('收到', style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.4))),
          const SizedBox(width: 24),
          Text('已读', style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.4))),
        ]),
        const SizedBox(height: 8),
        ..._dailyStats.map((d) {
          final day = d['day'] as String? ?? '';
          final count = d['count'] as int? ?? 0;
          final readCount = d['read_count'] as int? ?? 0;
          final shortDay = day.length >= 10 ? day.substring(5) : day;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 36, child: Text(shortDay, style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.5)))),
              const SizedBox(width: 8),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: maxCount > 0 ? count / maxCount : 0,
                  backgroundColor: Colors.blue.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(Colors.blue.withValues(alpha: 0.6)),
                  minHeight: 8,
                ),
              )),
              SizedBox(width: 24, child: Text('$count', style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.5)))),
              const SizedBox(width: 8),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: maxCount > 0 ? readCount / maxCount : 0,
                  backgroundColor: Colors.green.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(Colors.green.withValues(alpha: 0.6)),
                  minHeight: 8,
                ),
              )),
              SizedBox(width: 24, child: Text('$readCount', style: TextStyle(fontSize: 10, color: NoirTokens.paper.withValues(alpha: 0.5)))),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildTypeDistribution() {
    final dist = _globalStats['type_distribution'] as List<dynamic>? ?? [];
    if (dist.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NoirTokens.inkDeep,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: dist.map<Widget>((d) {
        final type = d['type'] as String? ?? 'manual';
        final count = d['count'] as int? ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(_typeIcon(type), size: 14, color: NoirTokens.accent),
            const SizedBox(width: 8),
            Text(_typeLabel(type), style: TextStyle(fontSize: 12, color: NoirTokens.paper)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: NoirTokens.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count', style: TextStyle(fontSize: 11, color: NoirTokens.accent, fontWeight: FontWeight.w600)),
            ),
          ]),
        );
      }).toList()),
    );
  }

  Widget _buildMonthlyStats() {
    final monthly = _userStats['monthly'] as List<dynamic>? ?? [];
    if (monthly.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: NoirTokens.inkDeep,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('暂无月度数据', style: TextStyle(color: NoirTokens.paper.withValues(alpha: 0.3))),
        ),
      );
    }
    final maxM = monthly.fold<int>(1, (m, d) => (d['count'] as int? ?? 0) > m ? (d['count'] as int) : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NoirTokens.inkDeep,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: monthly.map<Widget>((d) {
        final m = d['month'] as String? ?? '';
        final count = d['count'] as int? ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 32, child: Text('${m}月', style: TextStyle(fontSize: 11, color: NoirTokens.paper.withValues(alpha: 0.6)))),
            const SizedBox(width: 8),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: maxM > 0 ? count / maxM : 0,
                backgroundColor: NoirTokens.accent.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(NoirTokens.accent),
                minHeight: 10,
              ),
            )),
            const SizedBox(width: 8),
            SizedBox(width: 24, child: Text('$count', style: TextStyle(fontSize: 11, color: NoirTokens.paper.withValues(alpha: 0.6)))),
          ]),
        );
      }).toList()),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}月${dt.day}日';
    } catch (_) {
      return iso;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'grade': return Icons.grading;
      case 'submission': return Icons.upload_file;
      case 'ai_grading': return Icons.auto_awesome;
      case 'feedback': return Icons.feedback;
      case 'update': return Icons.system_update;
      case 'defense': return Icons.videocam;
      case 'auto_reminder': return Icons.notifications_active;
      default: return Icons.notifications;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'grade': return '成绩通知';
      case 'submission': return '提交通知';
      case 'ai_grading': return 'AI 批阅';
      case 'manual': return '手动通知';
      case 'feedback': return '反馈通知';
      case 'update': return '版本更新';
      case 'defense': return '答辩通知';
      case 'auto_reminder': return '自动提醒';
      default: return type;
    }
  }
}
