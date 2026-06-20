import 'package:flutter/material.dart';
import '../../../data/local/teacher_application_dao.dart';
import '../../../data/local/notification_dao.dart';
import '../../../services/auth_service.dart';

import '../../widgets/back_button_bar.dart';

/// 教师申请审核页面 — 管理员查看、审核教师申请
class TeacherApplicationManagePage extends StatefulWidget {
  const TeacherApplicationManagePage({super.key});

  @override
  State<TeacherApplicationManagePage> createState() =>
      _TeacherApplicationManagePageState();
}

class _TeacherApplicationManagePageState
    extends State<TeacherApplicationManagePage>
    with SingleTickerProviderStateMixin {
  final _dao = TeacherApplicationDao();
  late final TabController _tabController;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _reviewed = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final all = await _dao.getAllApplications();
      _pending = all.where((a) => a['status'] == 'pending').toList();
      _reviewed =
          all.where((a) => a['status'] != 'pending').toList();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BackButtonBar(
        title: '教师申请审核',
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '待审核 (${_pending.length})'),
            Tab(text: '已处理 (${_reviewed.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_pending, isPending: true),
                _buildList(_reviewed, isPending: false),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list,
      {required bool isPending}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isPending ? Icons.inbox : Icons.done_all,
                size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              isPending ? '暂无待审核的申请' : '暂无已处理的申请',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final app = list[index];
          return _buildApplicationCard(app, isPending: isPending);
        },
      ),
    );
  }

  Widget _buildApplicationCard(Map<String, dynamic> app,
      {required bool isPending}) {
    final status = app['status'] as String;
    final applicantName =
        app['applicant_name'] as String? ?? app['applicant_id'] as String;
    final workId = app['work_id'] as String? ?? '';
    final school = app['school'] as String? ?? '';
    final reason = app['reason'] as String? ?? '';
    final createdAt = app['created_at'] as String? ?? '';
    final reviewComment = app['review_comment'] as String? ?? '';
    final reviewedAt = app['reviewed_at'] as String? ?? '';

    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        statusLabel = '待审核';
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusLabel = '已通过';
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusLabel = '已拒绝';
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusLabel = status;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：姓名 + 状态
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(Icons.person, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(applicantName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('账号：${app['applicant_id']}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(statusIcon, size: 16, color: statusColor),
                  label: Text(statusLabel,
                      style: TextStyle(color: statusColor, fontSize: 12)),
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 详细信息
            _infoRow(Icons.badge, '教师工号', workId),
            if (school.isNotEmpty) _infoRow(Icons.school, '学校', school),
            if (reason.isNotEmpty) _infoRow(Icons.note, '申请说明', reason),
            _infoRow(Icons.schedule, '申请时间', _formatTime(createdAt)),
            if (!isPending && reviewedAt.isNotEmpty)
              _infoRow(Icons.rate_review, '审核时间', _formatTime(reviewedAt)),
            if (!isPending && reviewComment.isNotEmpty)
              _infoRow(Icons.comment, '审核意见', reviewComment),

            // 操作按钮
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(app),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('拒绝'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _approve(app),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('通过'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 8),
          Text('$label：',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  // ─── 审核操作 ────────────────────────────────────────────────────────

  Future<void> _approve(Map<String, dynamic> app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认通过'),
        content: Text(
            '确认通过 ${app['applicant_name'] ?? app['applicant_id']} 的教师申请？\n通过后该用户将获得教师权限。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认通过')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final reviewer = AuthService().currentUser?.userId ?? '';
      await _dao.reviewApplication(
        applicationId: app['id'] as int,
        reviewerId: reviewer,
        approved: true,
      );

      // 通知申请人
      try {
        final notifDao = NotificationDao();
        await notifDao.createNotification(
          title: '教师申请已通过',
          content: '您的教师申请已通过审核，请重新登录以启用教师功能。',
          type: 'teacher_application',
          creatorId: reviewer,
          targetType: 'individual',
          targetId: app['applicant_id'] as String,
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('已通过'), backgroundColor: Colors.green),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showRejectDialog(Map<String, dynamic> app) async {
    final commentCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('拒绝申请'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('拒绝 ${app['applicant_name'] ?? app['applicant_id']} 的教师申请'),
            const SizedBox(height: 12),
            TextField(
              controller: commentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '拒绝原因（选填）',
                hintText: '请简要说明拒绝原因',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('确认拒绝')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final reviewer = AuthService().currentUser?.userId ?? '';
      await _dao.reviewApplication(
        applicationId: app['id'] as int,
        reviewerId: reviewer,
        approved: false,
        comment: commentCtrl.text.trim().isNotEmpty
            ? commentCtrl.text.trim()
            : null,
      );

      // 通知申请人
      try {
        final notifDao = NotificationDao();
        final reason = commentCtrl.text.trim().isNotEmpty
            ? '原因：${commentCtrl.text.trim()}'
            : '';
        await notifDao.createNotification(
          title: '教师申请未通过',
          content: '很遗憾，您的教师申请未通过审核。$reason',
          type: 'teacher_application',
          creatorId: reviewer,
          targetType: 'individual',
          targetId: app['applicant_id'] as String,
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已拒绝'), backgroundColor: Colors.orange),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
    commentCtrl.dispose();
  }
}
