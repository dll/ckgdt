part of '../classroom_page.dart';

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

