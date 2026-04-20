import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/local/feedback_dao.dart';

/// 管理员 — 问题反馈管理页面
class FeedbackManagePage extends StatefulWidget {
  const FeedbackManagePage({super.key});

  @override
  State<FeedbackManagePage> createState() => _FeedbackManagePageState();
}

class _FeedbackManagePageState extends State<FeedbackManagePage> {
  final _feedbackDao = FeedbackDao();
  List<Map<String, dynamic>> _feedbackList = [];
  Map<String, int> _stats = {'total': 0, 'pending': 0, 'resolved': 0};
  bool _isLoading = true;
  String _filter = 'all'; // all, pending, resolved

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _feedbackDao.getStats();
      final list = await _feedbackDao.getAllFeedback(
        status: _filter == 'all' ? null : _filter,
      );
      if (mounted) {
        setState(() {
          _stats = stats;
          _feedbackList = list;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('问题反馈管理'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          if (_feedbackList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空已处理',
              onPressed: _clearResolved,
            ),
        ],
      ),
      body: Column(
        children: [
          // 统计卡片
          _buildStatsBar(primary),

          // 筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'all',
                    label: Text('全部 (${_stats['total']})')),
                ButtonSegment(
                    value: 'pending',
                    label: Text('待处理 (${_stats['pending']})')),
                ButtonSegment(
                    value: 'resolved',
                    label: Text('已处理 (${_stats['resolved']})')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) {
                setState(() => _filter = s.first);
                _loadData();
              },
            ),
          ),

          // 列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _feedbackList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('暂无反馈',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _feedbackList.length,
                          itemBuilder: (context, index) {
                            return _buildFeedbackCard(
                                _feedbackList[index], primary);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(Color primary) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem('总反馈', _stats['total'] ?? 0, Icons.feedback),
          Container(width: 1, height: 30, color: Colors.white30),
          _statItem('待处理', _stats['pending'] ?? 0, Icons.pending_actions),
          Container(width: 1, height: 30, color: Colors.white30),
          _statItem('已处理', _stats['resolved'] ?? 0, Icons.check_circle),
        ],
      ),
    );
  }

  Widget _statItem(String label, int value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> fb, Color primary) {
    final isPending = fb['status'] == 'pending';
    final createdAt = fb['created_at'] as String? ?? '';
    final timeStr = createdAt.length >= 16 ? createdAt.substring(0, 16) : createdAt;
    final screenshots = (fb['screenshot_path'] as String?)?.split('|') ?? [];
    final roleStr = fb['user_role'] == 'admin'
        ? '管理员'
        : fb['user_role'] == 'teacher'
            ? '教师'
            : '学生';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isPending ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPending
            ? BorderSide(color: Colors.orange.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：用户 + 状态
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: primary.withValues(alpha: 0.1),
                  child: Text(
                    (fb['user_name'] as String? ?? 'U').substring(0, 1),
                    style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fb['user_name'] as String? ?? fb['user_id'] as String? ?? '未知',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '$roleStr  |  $timeStr',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                // 状态标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isPending ? '待处理' : '已处理',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPending ? Colors.orange : Colors.green,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 问题内容
            Text(
              fb['content'] as String? ?? '',
              style: const TextStyle(fontSize: 14),
            ),

            // 改进建议
            if (fb['suggestion'] != null &&
                (fb['suggestion'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 16, color: Colors.blue[400]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        fb['suggestion'] as String,
                        style: TextStyle(
                            fontSize: 13, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 截图预览
            if (screenshots.isNotEmpty &&
                screenshots.first.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: screenshots.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final path = screenshots[i];
                    return GestureDetector(
                      onTap: () => _showFullScreenImage(path),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(path),
                          width: 100,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 100,
                            height: 80,
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image, size: 24),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // 管理员回复
            if (fb['admin_reply'] != null &&
                (fb['admin_reply'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.reply,
                        size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '回复: ${fb['admin_reply']}',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isPending)
                  TextButton.icon(
                    onPressed: () => _showReplyDialog(fb),
                    icon: const Icon(Icons.reply, size: 16),
                    label: const Text('回复处理', style: TextStyle(fontSize: 12)),
                  ),
                TextButton.icon(
                  onPressed: () => _deleteFeedback(fb),
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: Colors.red[300]),
                  label: Text('删除',
                      style: TextStyle(fontSize: 12, color: Colors.red[300])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 回复并标记为已处理
  Future<void> _showReplyDialog(Map<String, dynamic> fb) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回复反馈'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '输入回复内容（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('标记已处理')),
        ],
      ),
    );

    if (result == true) {
      await _feedbackDao.updateStatus(
        fb['id'] as int,
        'resolved',
        reply: controller.text.trim().isNotEmpty ? controller.text.trim() : null,
      );
      _loadData();
    }
    controller.dispose();
  }

  /// 删除反馈
  Future<void> _deleteFeedback(Map<String, dynamic> fb) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除反馈'),
        content: const Text('确定要删除这条反馈吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      await _feedbackDao.deleteFeedback(fb['id'] as int);
      _loadData();
    }
  }

  /// 清空已处理的反馈
  Future<void> _clearResolved() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空已处理'),
        content: const Text('确定要删除所有"已处理"的反馈吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      final list = await _feedbackDao.getAllFeedback(status: 'resolved');
      for (final fb in list) {
        await _feedbackDao.deleteFeedback(fb['id'] as int);
      }
      _loadData();
    }
  }

  /// 全屏查看图片
  void _showFullScreenImage(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('截图'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(path),
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image,
                      size: 64, color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
