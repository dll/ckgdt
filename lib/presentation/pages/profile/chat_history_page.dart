import 'package:flutter/material.dart';
import '../../../data/local/ai_history_dao.dart';
import '../../../services/agent/agent_registry.dart';
import '../../widgets/markdown_bubble.dart';

/// 对话历史页面 — 查看和管理智能体对话记录
class ChatHistoryPage extends StatefulWidget {
  const ChatHistoryPage({super.key});

  @override
  State<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends State<ChatHistoryPage>
    with SingleTickerProviderStateMixin {
  final AiHistoryDao _dao = AiHistoryDao();
  late TabController _tabController;

  List<Map<String, dynamic>> _allSessions = [];
  List<Map<String, dynamic>> _starredSessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSessions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final all = await _dao.getSessions();
      final starred = await _dao.getStarredSessions();
      if (mounted) {
        setState(() {
          _allSessions = all;
          _starredSessions = starred;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getAgentName(String? agentId) {
    if (agentId == null || agentId.isEmpty) return '小知';
    final registry = AgentRegistry.instance;
    registry.initialize();
    final configs = registry.allConfigs;
    for (final cfg in configs) {
      if (cfg.id == agentId) return '${cfg.emoji} ${cfg.name}';
    }
    return '小知';
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
      if (diff.inDays < 1) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('对话历史'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '全部 (${_allSessions.length})'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 16),
                  const SizedBox(width: 4),
                  Text('收藏 (${_starredSessions.length})'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_allSessions.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'clear_all') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('清空全部对话'),
                      content: const Text('确定要清空所有对话历史吗？收藏的对话也会被删除。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _dao.clearAll();
                    _loadSessions();
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('清空全部', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSessionList(_allSessions, theme),
                _buildSessionList(_starredSessions, theme),
              ],
            ),
    );
  }

  Widget _buildSessionList(
      List<Map<String, dynamic>> sessions, ThemeData theme) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('暂无对话记录',
                style: TextStyle(fontSize: 16, color: Colors.grey[500])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final session = sessions[index];
          final sessionId = session['session_id'] as String;
          final agentId = session['agent_id'] as String?;
          final firstMsg = session['first_user_msg'] as String? ?? '(空对话)';
          final msgCount = (session['message_count'] as int?) ?? 0;
          final lastAt = session['last_at'] as String?;
          final isStarred =
              ((session['starred'] as int?) ?? 0) == 1;
          final title = session['title'] as String?;

          final displayTitle = title ?? (firstMsg.length > 40
              ? '${firstMsg.substring(0, 40)}...'
              : firstMsg);

          return Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openSession(sessionId, agentId),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayTitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isStarred)
                                const Icon(Icons.star,
                                    size: 16, color: Colors.amber),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                _getAgentName(agentId),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '$msgCount 条消息',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[500]),
                              ),
                              const Spacer(),
                              Text(
                                _formatTime(lastAt),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[400]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          size: 18, color: Colors.grey[400]),
                      onSelected: (value) async {
                        if (value == 'star') {
                          await _dao.toggleStar(sessionId);
                          _loadSessions();
                        } else if (value == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除对话'),
                              content: const Text('确定删除这条对话记录吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _dao.deleteSession(sessionId);
                            _loadSessions();
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'star',
                          child: Row(
                            children: [
                              Icon(
                                isStarred
                                    ? Icons.star_border
                                    : Icons.star,
                                size: 18,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Text(isStarred ? '取消收藏' : '收藏'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 打开单个会话详情（查看消息）
  void _openSession(String sessionId, String? agentId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChatDetailPage(
          sessionId: sessionId,
          agentName: _getAgentName(agentId),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 会话详情页 — 展示单个会话的所有消息
// ═══════════════════════════════════════════════════════════════════════════════

class _ChatDetailPage extends StatefulWidget {
  final String sessionId;
  final String agentName;

  const _ChatDetailPage({
    required this.sessionId,
    required this.agentName,
  });

  @override
  State<_ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<_ChatDetailPage> {
  final AiHistoryDao _dao = AiHistoryDao();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final msgs = await _dao.getSessionMessages(widget.sessionId);
    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agentName),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_border),
            onPressed: () async {
              await _dao.toggleStar(widget.sessionId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已切换收藏状态')),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const Center(child: Text('暂无消息'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final role = msg['role'] as String? ?? '';
                    final content = msg['content'] as String? ?? '';
                    final isUser = role == 'user';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.78,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? theme.colorScheme.primary
                                  : (isDark
                                      ? const Color(0xFF2A2A2A)
                                      : Colors.grey[100]!),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft:
                                    Radius.circular(isUser ? 16 : 4),
                                bottomRight:
                                    Radius.circular(isUser ? 4 : 16),
                              ),
                            ),
                            child: isUser
                                ? SelectableText(
                                    content,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                      height: 1.5,
                                    ),
                                  )
                                : MarkdownBubble(
                                    content: content,
                                    textColor: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    compact: true,
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
