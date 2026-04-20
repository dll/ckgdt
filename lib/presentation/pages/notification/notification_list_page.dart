import 'package:flutter/material.dart';
import '../../../data/local/notification_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import 'compose_notification_page.dart';

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
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = true;

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
      // 先检查自动提醒
      await _notificationService.checkAndCreateReminders();

      final notifications =
          await _notificationDao.getNotificationsForUser(userId);
      final unreadCount = await _notificationDao.getUnreadCount(userId);

      // 教师/管理员：为自己创建的通知附加阅读统计
      if (_authService.isAdmin || _authService.isTeacher) {
        for (int i = 0; i < notifications.length; i++) {
          final n = notifications[i];
          if (n['creator_id'] == userId) {
            final stats = await _notificationDao
                .getNotificationReadStats(n['id'] as int);
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
        ],
      ),
    );
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
                        color: isRead ? Colors.green : theme.colorScheme.outline,
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
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          // 「全部已读」按钮（有未读时显示）
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                '全部已读',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
        ],
      ),
      // 教师/管理员：悬浮按钮 → 发布通知
      floatingActionButton: isAdminOrTeacher
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
    final isRead = (notification['is_read'] as int?) == 1;
    final title = notification['title'] as String? ?? '';
    final content = notification['content'] as String? ?? '';
    final creatorName = notification['creator_name'] as String? ?? '系统';
    final createdAt = notification['created_at'] as String? ?? '';
    final notifType = notification['type'] as String? ?? 'manual';
    final readCount = notification['read_count'];
    final totalRecipients = notification['total_recipients'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isRead ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRead
            ? BorderSide.none
            : BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                width: 1,
              ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onNotificationTap(notification),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 未读蓝点 / 已读灰色图标
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: isRead
                    ? Icon(
                        _getTypeIcon(notifType),
                        size: 20,
                        color: theme.colorScheme.outline.withValues(alpha: 0.4),
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
                        fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
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
