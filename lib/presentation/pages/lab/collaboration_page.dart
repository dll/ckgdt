import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../data/local/collaboration_dao.dart';
import '../../../services/auth_service.dart';

/// 协作讨论页面 — 讨论区 / 分工管理 / 互评中心（3 Tab）
class CollaborationPage extends StatefulWidget {
  final int? taskId;
  final int? groupId;
  const CollaborationPage({super.key, this.taskId, this.groupId});

  @override
  State<CollaborationPage> createState() => _CollaborationPageState();
}

class _CollaborationPageState extends State<CollaborationPage>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _collaborationDao = CollaborationDao();
  late TabController _tabController;

  bool _isLoading = true;
  bool _tablesReady = false;

  // ── 讨论区数据 ─────────────────────────────────────────────
  List<Map<String, dynamic>> _messages = [];
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  // ── 分工管理数据（从 JSON 动态加载） ──────────────────────────────
  List<Map<String, dynamic>> _taskDivisions = [];

  // ── 互评中心数据 ───────────────────────────────────────────
  List<Map<String, dynamic>> _peerReviews = [];

  // 可互评的提交列表（从 JSON 动态加载）
  List<Map<String, dynamic>> _submissions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    try {
      await _collaborationDao.ensureTables();
      _tablesReady = true;
    } catch (e) {
      debugPrint('CollaborationPage: 初始化表失败: $e');
    }
    // 从 JSON 加载真实学生数据填充分工和互评
    await _loadStudentDemoData();
    await _loadAllData();
  }

  /// 从 student_group_data.json 加载真实学生，填充分工管理和互评数据
  Future<void> _loadStudentDemoData() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final allStudents =
          decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      if (allStudents.isEmpty) return;

      // 找当前用户所在 repo 的同学，否则取第一个 repo
      final userId = _authService.getCurrentUserId();
      String? myRepo;
      if (userId != null) {
        final me = allStudents.firstWhere(
          (s) => s['userId'] == userId,
          orElse: () => <String, dynamic>{},
        );
        myRepo = me['repo'] as String?;
      }
      myRepo ??= allStudents.first['repo'] as String?;

      final repoMembers = allStudents
          .where((s) => s['repo'] == myRepo)
          .toList();
      if (repoMembers.isEmpty) return;

      // 分工角色列表
      const roles = [
        'UI 设计与实现',
        '后端接口开发',
        '数据库设计',
        '测试与文档',
        '前端开发',
        'API 接口设计',
      ];
      final divisions = <Map<String, dynamic>>[];
      for (int i = 0; i < repoMembers.length; i++) {
        final m = repoMembers[i];
        divisions.add({
          'member_name': m['name'] as String? ?? '',
          'member_id': m['userId'] as String? ?? '',
          'role': m['coreDuty'] as String? ?? roles[i % roles.length],
          'progress': (i == 0) ? 0.75 : (i == 1) ? 0.60 : (i == 2) ? 1.0 : 0.30 + (i % 5) * 0.1,
          'status': i == 2 ? '已完成' : '进行中',
        });
      }

      final subs = <Map<String, dynamic>>[];
      for (int i = 0; i < repoMembers.length; i++) {
        final m = repoMembers[i];
        subs.add({
          'submitter_id': m['userId'] as String? ?? '',
          'submitter_name': m['name'] as String? ?? '',
          'title': m['project'] as String? ?? '未命名项目',
          'submit_time': '2026-04-${(10 - i).toString().padLeft(2, '0')} 14:30',
          'description': m['features'] as String? ?? '移动应用开发项目',
        });
      }

      if (mounted) {
        setState(() {
          _taskDivisions = divisions;
          _submissions = subs;
        });
      }
    } catch (e) {
      debugPrint('CollaborationPage: 加载学生数据失败: $e');
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadMessages(),
        _loadPeerReviews(),
      ]);
    } catch (e) {
      debugPrint('CollaborationPage: 加载数据失败: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadMessages() async {
    if (!_tablesReady) return;
    try {
      final messages = await _collaborationDao.getMessages(
        taskId: widget.taskId,
        groupId: widget.groupId,
      );
      if (mounted) {
        setState(() => _messages = messages);
      }
    } catch (e) {
      debugPrint('CollaborationPage: 加载消息失败: $e');
    }
  }

  Future<void> _loadPeerReviews() async {
    if (!_tablesReady) return;
    try {
      final reviews = await _collaborationDao.getPeerReviews(
        taskId: widget.taskId,
      );
      if (mounted) {
        setState(() => _peerReviews = reviews);
      }
    } catch (e) {
      debugPrint('CollaborationPage: 加载互评失败: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('协作讨论'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.forum, size: 18), text: '讨论区'),
            Tab(icon: Icon(Icons.assignment_ind, size: 18), text: '分工管理'),
            Tab(icon: Icon(Icons.rate_review, size: 18), text: '互评中心'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDiscussionTab(),
                _buildTaskDivisionTab(),
                _buildPeerReviewTab(),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tab 1: 讨论区
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDiscussionTab() {
    final currentUserId = _authService.getCurrentUserId();

    return Column(
      children: [
        // 消息列表
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyState(
                  icon: Icons.forum_outlined,
                  title: '暂无讨论消息',
                  subtitle: '发送第一条消息开始讨论吧',
                )
              : RefreshIndicator(
                  onRefresh: _loadMessages,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMine = msg['sender_id'] == currentUserId;
                      return _buildMessageBubble(msg, isMine);
                    },
                  ),
                ),
        ),
        // 输入栏
        _buildMessageInputBar(),
      ],
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMine) {
    final primary = Theme.of(context).colorScheme.primary;
    final senderName = msg['sender_name'] ?? '未知';
    final message = msg['message'] ?? '';
    final createdAt = msg['created_at'] ?? '';
    final timeDisplay = _formatTime(createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            // 头像
            CircleAvatar(
              radius: 18,
              backgroundColor: primary.withValues(alpha: 0.15),
              child: Text(
                senderName.isNotEmpty ? senderName[0] : '?',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 气泡
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMine
                        ? primary.withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft:
                          isMine ? const Radius.circular(16) : Radius.zero,
                      bottomRight:
                          isMine ? Radius.zero : const Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    timeDisplay,
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 18,
              backgroundColor: primary,
              child: Text(
                senderName.isNotEmpty ? senderName[0] : '我',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInputBar() {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _sendMessage,
              icon: Icon(Icons.send_rounded, color: primary),
              style: IconButton.styleFrom(
                backgroundColor: primary.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先登录')),
        );
      }
      return;
    }

    try {
      await _collaborationDao.sendMessage(
        taskId: widget.taskId,
        groupId: widget.groupId,
        senderId: user.userId,
        senderName: user.realName ?? user.userId,
        message: text,
      );
      _messageController.clear();
      await _loadMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tab 2: 分工管理
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTaskDivisionTab() {
    final isTeacher = _authService.isTeacher || _authService.isAdmin;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 任务概览卡片
          _buildTaskOverviewCard(),
          const SizedBox(height: 16),
          // 标题
          Row(
            children: [
              Icon(Icons.people,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                '成员分工',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (isTeacher)
                TextButton.icon(
                  onPressed: _showEditDivisionDialog,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('编辑', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 成员卡片列表
          ..._taskDivisions.asMap().entries.map(
                (entry) => _buildMemberCard(entry.value, entry.key),
              ),
        ],
      ),
    );
  }

  Widget _buildTaskOverviewCard() {
    final primary = Theme.of(context).colorScheme.primary;
    final completedCount =
        _taskDivisions.where((d) => d['progress'] == 1.0).length;
    final totalProgress = _taskDivisions.isEmpty
        ? 0.0
        : _taskDivisions
                .map<double>((d) => (d['progress'] as double?) ?? 0.0)
                .reduce((a, b) => a + b) /
            _taskDivisions.length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              primary,
              primary.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group_work, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '团队任务概览',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$completedCount/${_taskDivisions.length} 完成',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 总体进度条
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: totalProgress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(totalProgress * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member, int index) {
    final primary = Theme.of(context).colorScheme.primary;
    final progress = (member['progress'] as double?) ?? 0.0;
    final isCompleted = progress >= 1.0;
    final memberName = member['member_name'] ?? '未知';
    final role = member['role'] ?? '未分配';
    final status = member['status'] ?? '未开始';

    final statusColors = {
      '已完成': Colors.green,
      '进行中': Colors.orange,
      '未开始': Colors.grey,
    };
    final statusColor = statusColors[status] ?? Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // 头像
            CircleAvatar(
              radius: 22,
              backgroundColor: isCompleted
                  ? Colors.green.withValues(alpha: 0.15)
                  : primary.withValues(alpha: 0.12),
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.green, size: 22)
                  : Text(
                      memberName.isNotEmpty ? memberName[0] : '?',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        memberName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  // 进度条
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                                isCompleted ? Colors.green : primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: isCompleted ? Colors.green : primary,
                          fontWeight: FontWeight.bold,
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

  void _showEditDivisionDialog() {
    final roles = [
      'UI 设计与实现',
      '后端接口开发',
      '数据库设计',
      '测试与文档',
      '前端开发',
      'API 接口设计',
    ];
    final controllers = <TextEditingController>[];
    final roleValues = <String>[];

    for (final div in _taskDivisions) {
      controllers.add(
        TextEditingController(text: div['role'] as String? ?? ''),
      );
      roleValues.add(div['role'] as String? ?? '');
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('编辑分工'),
              content: SizedBox(
                width: 360,
                child: _taskDivisions.isEmpty
                    ? const Text('暂无分工数据')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _taskDivisions.length,
                        itemBuilder: (_, i) {
                          final div = _taskDivisions[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    div['member_name'] as String? ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    value: roleValues[i].isNotEmpty &&
                                            roles.contains(roleValues[i])
                                        ? roleValues[i]
                                        : roles.first,
                                    items: roles
                                        .map((r) => DropdownMenuItem(
                                              value: r,
                                              child: Text(r,
                                                  style:
                                                      const TextStyle(
                                                          fontSize: 13)),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      setDialogState(() {
                                        roleValues[i] = val ?? roles.first;
                                      });
                                    },
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    for (int i = 0; i < _taskDivisions.length; i++) {
                      _taskDivisions[i]['role'] = roleValues[i];
                    }
                    setState(() {});
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('分工已更新')),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      for (final c in controllers) {
        c.dispose();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tab 3: 互评中心
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPeerReviewTab() {
    final currentUserId = _authService.getCurrentUserId();

    return RefreshIndicator(
      onRefresh: _loadPeerReviews,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 互评统计卡片
          _buildReviewStatsCard(),
          const SizedBox(height: 16),
          // 可互评的提交列表
          Row(
            children: [
              Icon(Icons.assignment,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                '待评作品',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._buildSubmissionsList(currentUserId),
          const SizedBox(height: 20),
          // 已有互评记录
          Row(
            children: [
              Icon(Icons.reviews,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                '互评记录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_peerReviews.length} 条',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_peerReviews.isEmpty)
            _buildEmptyCard(
              icon: Icons.rate_review_outlined,
              text: '暂无互评记录',
            )
          else
            ..._peerReviews.map((review) => _buildReviewCard(review)),
        ],
      ),
    );
  }

  Widget _buildReviewStatsCard() {
    final primary = Theme.of(context).colorScheme.primary;
    final totalReviews = _peerReviews.length;
    final avgScore = _peerReviews.isEmpty
        ? 0.0
        : _peerReviews
                .map<int>((r) => (r['score'] as int?) ?? 0)
                .reduce((a, b) => a + b) /
            _peerReviews.length;

    final currentUserId = _authService.getCurrentUserId();
    final myReviewCount = _peerReviews
        .where((r) => r['reviewer_id'] == currentUserId)
        .length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                Icons.rate_review,
                '$totalReviews',
                '总互评',
                primary,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            Expanded(
              child: _buildStatItem(
                Icons.star,
                avgScore.toStringAsFixed(1),
                '平均分',
                Colors.orange,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            Expanded(
              child: _buildStatItem(
                Icons.edit_note,
                '$myReviewCount',
                '我的评价',
                Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
      IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ],
    );
  }

  List<Widget> _buildSubmissionsList(String? currentUserId) {
    // 排除自己的提交
    final otherSubmissions = _submissions
        .where((s) => s['submitter_id'] != currentUserId)
        .toList();

    if (otherSubmissions.isEmpty) {
      return [
        _buildEmptyCard(
          icon: Icons.assignment_outlined,
          text: '暂无可评价的作品',
        ),
      ];
    }

    return otherSubmissions.map((submission) {
      final submitterName = submission['submitter_name'] ?? '未知';
      final title = submission['title'] ?? '';
      final submitTime = submission['submit_time'] ?? '';
      final submitterId = submission['submitter_id'] ?? '';

      // 检查是否已评过
      final hasReviewed = _peerReviews.any(
        (r) =>
            r['reviewer_id'] == currentUserId &&
            r['reviewee_id'] == submitterId,
      );

      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showPeerReviewDialog(submission),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // 头像
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                  child: Text(
                    submitterName.isNotEmpty ? submitterName[0] : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 提交信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$submitterName  $submitTime',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                // 评价状态
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasReviewed
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    hasReviewed ? '已评' : '待评',
                    style: TextStyle(
                      fontSize: 11,
                      color: hasReviewed ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final reviewerName = review['reviewer_name'] ?? '未知';
    final revieweeName = review['reviewee_name'] ?? '未知';
    final score = (review['score'] as int?) ?? 0;
    final comment = review['comment'] ?? '';
    final createdAt = review['created_at'] ?? '';

    Color scoreColor;
    if (score >= 80) {
      scoreColor = Colors.green;
    } else if (score >= 60) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  child: Text(
                    reviewerName.isNotEmpty ? reviewerName[0] : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                              text: reviewerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            TextSpan(
                              text: ' 评价了 ',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            TextSpan(
                              text: revieweeName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatTime(createdAt),
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                // 分数
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$score 分',
                    style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  comment,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 互评对话框 ─────────────────────────────────────────────

  void _showPeerReviewDialog(Map<String, dynamic> submission) {
    final submitterName = submission['submitter_name'] ?? '未知';
    final submitterId = submission['submitter_id'] ?? '';
    final title = submission['title'] ?? '';
    final description = submission['description'] ?? '';

    double scoreValue = 80;
    final commentController = TextEditingController();
    final currentUserId = _authService.getCurrentUserId();

    // 如果已有评价，预填
    final existing = _peerReviews.firstWhere(
      (r) =>
          r['reviewer_id'] == currentUserId &&
          r['reviewee_id'] == submitterId,
      orElse: () => <String, dynamic>{},
    );
    if (existing.isNotEmpty) {
      scoreValue = ((existing['score'] as int?) ?? 80).toDouble();
      commentController.text = existing['comment'] ?? '';
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.rate_review,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('互评打分',
                        style: TextStyle(fontSize: 17)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 被评人信息
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '提交者: $submitterName',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600]),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  height: 1.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 评分滑块
                      Row(
                        children: [
                          const Text(
                            '评分',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${scoreValue.toInt()} 分',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: _scoreColor(scoreValue.toInt()),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: scoreValue,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        activeColor: _scoreColor(scoreValue.toInt()),
                        label: '${scoreValue.toInt()}',
                        onChanged: (v) {
                          setDialogState(() => scoreValue = v);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[400])),
                          Text('50',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[400])),
                          Text('100',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[400])),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 评语输入
                      const Text(
                        '评语',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: commentController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: '请输入评价内容...',
                          hintStyle: TextStyle(
                              color: Colors.grey[400], fontSize: 13),
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(12),
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
                FilledButton(
                  onPressed: () {
                    _submitPeerReview(
                      submitterId: submitterId,
                      submitterName: submitterName,
                      score: scoreValue.toInt(),
                      comment: commentController.text.trim(),
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('提交评价'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitPeerReview({
    required String submitterId,
    required String submitterName,
    required int score,
    required String comment,
  }) async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      await _collaborationDao.addPeerReview(
        taskId: widget.taskId,
        reviewerId: user.userId,
        reviewerName: user.realName ?? user.userId,
        revieweeId: submitterId,
        revieweeName: submitterName,
        score: score,
        comment: comment,
      );
      await _loadPeerReviews();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已提交对 $submitterName 的评价 ($score 分)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交评价失败: $e')),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 公共 Widget
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCard({required IconData icon, required String text}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 40, color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text(
                text,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 工具方法 ───────────────────────────────────────────────

  Color _scoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _formatTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
      if (diff.inHours < 24) return '${diff.inHours} 小时前';
      if (diff.inDays < 7) return '${diff.inDays} 天前';

      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString.length > 16 ? isoString.substring(0, 16) : isoString;
    }
  }
}
