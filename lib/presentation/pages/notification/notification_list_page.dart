import 'package:flutter/material.dart';
import '../../widgets/back_button_bar.dart';
import '../../../data/local/notification_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/update_service.dart';
import 'compose_notification_page.dart';
import '../settings/update_dialog.dart';
import '../assessment/defense/defense_broadcast_page.dart';

/// 通知列表页面 — 展示用户的通知消息
///
/// 功能：
/// - 按时间倒序展示通知卡片（未读蓝点、标题、内容预览、发送者、相对时间）
/// - 点击 → 标记已读 + 显示详情对话框
/// - AppBar 支持「全部已读」操作
/// - 教师/管理员可查看阅读统计、发布新通知
/// - 下拉刷新
class NotificationListPage extends StatefulWidget {
  const NotificationListPage({super.key});

  @override
  State<NotificationListPage> createState() => _NotificationListPageState();
}

class _NotificationListPageState extends State<NotificationListPage> {
  final NotificationDao _notificationDao = NotificationDao();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = true;

  // 批量选择
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  /// 加载通知列表 + 未读计数
  Future<void> _loadNotifications() async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) return;

    try {
      // 修复历史遗留的孤儿收件人记录（同步导入等导致）
      await _notificationDao.cleanOrphanedRecipients();
      final notifications =
          await _notificationDao.getNotificationsForUser(userId);
      final unreadCount = await _notificationDao.getUnreadCount(userId);

      // 教师/管理员：为自己创建的通知附加阅读统计
      if (_authService.isAdmin || _authService.isTeacher) {
        for (int i = 0; i < notifications.length; i++) {
          final n = notifications[i];
          if (n['creator_id'] == userId) {
            final stats =
                await _notificationDao.getNotificationReadStats(n['id'] as int);
            // 创建可变副本并附加统计数据
            final mutable = Map<String, dynamic>.from(n);
            mutable['read_count'] = stats['read_count'];
            mutable['total_recipients'] = stats['total'];
            notifications[i] = mutable;
          }
        }
      }

      if (mounted) {
        setState(() {
          _notifications = notifications;
          _unreadCount = unreadCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 全部标记已读
  Future<void> _markAllAsRead() async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) return;

    await _notificationDao.markAllAsRead(userId);
    await _loadNotifications();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已全部标记为已读')),
      );
    }
  }

  /// 进入/退出选择模式
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear();
    });
  }

  /// 切换单条选中状态
  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      // 取消所有选中时自动退出选择模式
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  /// 全选 / 取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _notifications.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(
          _notifications.map((n) => n['id'] as int),
        );
      }
    });
  }

  /// 批量删除选中通知
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除选中的 ${_selectedIds.length} 条通知？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _notificationDao.deleteNotifications(_selectedIds.toList());
    _selectedIds.clear();
    _isSelectionMode = false;
    await _loadNotifications();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除选中通知')),
      );
    }
  }

  /// 清空所有通知
  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空通知'),
        content: const Text('确定删除所有通知？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _notificationDao.deleteAllNotifications();
    _selectedIds.clear();
    _isSelectionMode = false;
    await _loadNotifications();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空所有通知')),
      );
    }
  }

  /// 点击通知 → 标记已读 + 展示详情
  Future<void> _onNotificationTap(Map<String, dynamic> notification) async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) return;

    final notifId = notification['id'] as int;
    final isRead = (notification['is_read'] as int?) == 1;

    // 标记已读
    if (!isRead) {
      await _notificationDao.markAsRead(notifId, userId);
    }

    if (!mounted) return;

    // 显示详情对话框
    await _showNotificationDetail(notification);

    // 刷新列表
    await _loadNotifications();
  }

  /// 通知详情对话框
  Future<void> _showNotificationDetail(
      Map<String, dynamic> notification) async {
    final theme = Theme.of(context);
    final creatorName = notification['creator_name'] as String? ?? '系统';
    final createdAt = notification['created_at'] as String? ?? '';
    final title = notification['title'] as String? ?? '';
    final content = notification['content'] as String? ?? '';
    final notifType = notification['type'] as String? ?? 'manual';
    final relatedType = notification['related_entity_type'] as String? ?? '';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getTypeIcon(notifType),
              color: theme.colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 发送者 + 时间
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    creatorName,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // 通知正文
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // 教师/管理员：查看阅读统计
          if ((_authService.isAdmin || _authService.isTeacher) &&
              notification['creator_id'] == _authService.getCurrentUserId())
            TextButton.icon(
              icon: const Icon(Icons.analytics_outlined, size: 18),
              label: const Text('阅读统计'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _showReadStatus(notification['id'] as int);
              },
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          // 应用更新通知 — 显示"立即更新"和"忽略"
          if (relatedType == 'app_update')
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _onAppUpdateIgnore(notification);
              },
              child: const Text('忽略'),
            ),
          if (relatedType == 'app_update')
            FilledButton.icon(
              icon: const Icon(Icons.system_update, size: 18),
              label: const Text('立即更新'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _onAppUpdateTap();
              },
            ),
          // 按 related_entity_type 路由到对应 Tab
          if (relatedType.isNotEmpty && relatedType != 'app_update')
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('去查看'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _navigateToRelated(relatedType, notification);
              },
            ),
        ],
      ),
    );
  }

  /// 应用更新 — 忽略此版本
  Future<void> _onAppUpdateIgnore(Map<String, dynamic> notification) async {
    final relatedId = notification['related_entity_id'] as String? ?? '';
    if (relatedId.startsWith('app_update_v')) {
      final version = relatedId.substring('app_update_v'.length);
      await UpdateService().ignoreVersion(version);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已忽略此版本更新'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    await _loadNotifications();
  }

  /// 应用更新 — 立即更新
  void _onAppUpdateTap() {
    Navigator.of(context).maybePop();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await UpdateDialog.showCheckUpdate(context);
    });
  }

  /// 把通知里的 related_entity_type 翻译成提示，让用户自己跳对应 Tab
  void _navigateToRelated(String entityType,
      [Map<String, dynamic>? notification]) {
    // 答辩直播：直接跳转到答辩页面并传入 serverIp
    if (entityType == 'defense_live') {
      String? serverIp;
      final content = notification?['content'] as String? ?? '';
      // 从通知内容中提取 IP：教师机 IP: 192.168.x.x
      final ipMatch = RegExp(r'IP:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(content);
      if (ipMatch != null) {
        serverIp = ipMatch.group(1);
      }

      Navigator.of(context).maybePop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DefenseBroadcastPage(
              initialRole: 'defender',
              serverIp: serverIp,
            ),
          ),
        );
      });
      return;
    }

    final hint = {
      'lab_submission': '请到 实验 Tab 查看 AI 批阅 / 教师评分',
      'work_submission': '请到 作品 Tab 查看 AI 批阅 / 教师评分',
      'assessment_report': '请到 考核 Tab 查看 AI 批阅 / 教师评分',
      'feedback': '请到 反馈 Tab 查看',
      'contribution_score': '请到 考核 Tab 查看贡献评分',
    }[entityType];

    if (hint == null) return;
    Navigator.of(context).maybePop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hint), duration: const Duration(seconds: 3)),
      );
    });
  }

  /// 阅读统计弹窗（教师/管理员）
  Future<void> _showReadStatus(int notificationId) async {
    final statList =
        await _notificationDao.getNotificationReadStatus(notificationId);

    if (!mounted) return;

    final theme = Theme.of(context);
    final readCount = statList.where((s) => (s['is_read'] as int?) == 1).length;
    final total = statList.length;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('阅读统计 ($readCount/$total)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: statList.isEmpty
              ? const Center(child: Text('暂无收件人'))
              : ListView.separated(
                  itemCount: statList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final s = statList[index];
                    final isRead = (s['is_read'] as int?) == 1;
                    final name = s['real_name'] as String? ??
                        s['user_id'] as String? ??
                        '未知';
                    final readAt = s['read_at'] as String?;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isRead ? Icons.check_circle : Icons.circle_outlined,
                        color:
                            isRead ? Colors.green : theme.colorScheme.outline,
                        size: 20,
                      ),
                      title: Text(name, style: const TextStyle(fontSize: 14)),
                      trailing: isRead && readAt != null
                          ? Text(
                              _formatTime(readAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.outline,
                              ),
                            )
                          : Text(
                              '未读',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.error,
                              ),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 根据通知类型返回图标
  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'auto_reminder':
        return Icons.alarm;
      case 'manual':
        return Icons.campaign;
      case 'update':
        return Icons.system_update;
      default:
        return Icons.notifications;
    }
  }

  /// 格式化为相对时间（刚刚 / X分钟前 / X小时前 / X天前 / 日期）
  String _formatTime(String isoString) {
    try {
      final time = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(time);

      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${time.month}月${time.day}日';
    } catch (_) {
      return isoString;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI 构建
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdminOrTeacher = _authService.isAdmin || _authService.isTeacher;

    return Scaffold(
      appBar: BackButtonBar(
        title: _isSelectionMode ? '已选 ${_selectedIds.length} 项' : '通知',
        actions: _isSelectionMode
            ? [
                // 全选 / 取消全选
                IconButton(
                  icon: Icon(
                    _selectedIds.length == _notifications.length
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  tooltip: _selectedIds.length == _notifications.length
                      ? '取消全选'
                      : '全选',
                  onPressed: _toggleSelectAll,
                ),
                // 删除选中
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '删除选中',
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                ),
              ]
            : [
                if (_unreadCount > 0)
                  TextButton(
                    onPressed: _markAllAsRead,
                    child: Text(
                      '全部已读',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                if (_notifications.isNotEmpty)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'select') _toggleSelectionMode();
                      if (value == 'clear') _deleteAll();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'select',
                        child: ListTile(
                          leading: Icon(Icons.checklist),
                          title: Text('批量管理'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'clear',
                        child: ListTile(
                          leading: Icon(Icons.delete_sweep, color: Colors.red),
                          title:
                              Text('清空所有', style: TextStyle(color: Colors.red)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
              ],
      ),
      // 教师/管理员：悬浮按钮 → 发布通知（选择模式下隐藏）
      floatingActionButton: isAdminOrTeacher && !_isSelectionMode
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ComposeNotificationPage(),
                  ),
                );
                if (result == true) {
                  await _loadNotifications();
                }
              },
              child: const Icon(Icons.edit_notifications),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: _notifications.isEmpty
                  ? _buildEmptyState(theme)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _notifications.length,
                      itemBuilder: (_, index) =>
                          _buildNotificationCard(_notifications[index], theme),
                    ),
            ),
    );
  }

  /// 空状态视图
  Widget _buildEmptyState(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none,
                  size: 64,
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无通知',
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '新的通知将显示在这里',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.outline.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 通知卡片
  Widget _buildNotificationCard(
      Map<String, dynamic> notification, ThemeData theme) {
    final notifId = notification['id'] as int;
    final isRead = (notification['is_read'] as int?) == 1;
    final title = notification['title'] as String? ?? '';
    final content = notification['content'] as String? ?? '';
    final creatorName = notification['creator_name'] as String? ?? '系统';
    final createdAt = notification['created_at'] as String? ?? '';
    final notifType = notification['type'] as String? ?? 'manual';
    final readCount = notification['read_count'];
    final totalRecipients = notification['total_recipients'];
    final isSelected = _selectedIds.contains(notifId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isRead ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : isRead
                ? BorderSide.none
                : BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 1,
                  ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isSelectionMode
            ? () => _toggleSelection(notifId)
            : () => _onNotificationTap(notification),
        onLongPress: _isSelectionMode
            ? null
            : () {
                setState(() {
                  _isSelectionMode = true;
                  _selectedIds.add(notifId);
                });
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 选择模式：Checkbox；普通模式：未读蓝点/已读灰色图标
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(notifId),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: isRead
                      ? Icon(
                          _getTypeIcon(notifType),
                          size: 20,
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.4),
                        )
                      : Stack(
                          children: [
                            Icon(
                              _getTypeIcon(notifType),
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              // 通知内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isRead ? FontWeight.normal : FontWeight.w600,
                        color: isRead
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                            : theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 内容预览
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.outline,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // 底部信息行：发送者 + 时间 + 阅读统计
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 12, color: theme.colorScheme.outline),
                        const SizedBox(width: 2),
                        Text(
                          creatorName,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.access_time,
                            size: 12, color: theme.colorScheme.outline),
                        const SizedBox(width: 2),
                        Text(
                          _formatTime(createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        // 教师/管理员 — 自己发布的通知显示阅读统计
                        if (readCount != null && totalRecipients != null) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '已阅 $readCount / 共 $totalRecipients 人',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
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
        ),
      ),
    );
  }
}
