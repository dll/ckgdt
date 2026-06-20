import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/local/ai_history_dao.dart';
import '../../../services/agent/agent_registry.dart';

/// AI 数据管理页面
///
/// 功能：使用统计、对话历史浏览、数据清理、导出
class AiDataPage extends StatefulWidget {
  const AiDataPage({super.key});

  @override
  State<AiDataPage> createState() => _AiDataPageState();
}

class _AiDataPageState extends State<AiDataPage> {
  final _historyDao = AiHistoryDao();
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String _filterType = 'all'; // all, agent, skill

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final stats = await _historyDao.getStats();
      List<Map<String, dynamic>> sessions;
      if (_filterType == 'agent') {
        sessions = await _historyDao.getSessions(agentId: '');
        // 获取所有有 agent_id 的会话
        sessions = await _historyDao.getSessions();
        sessions = sessions.where((s) {
          final aid = s['agent_id'] as String?;
          return aid != null && aid.isNotEmpty;
        }).toList();
      } else if (_filterType == 'skill') {
        sessions = await _historyDao.getSessions();
        sessions = sessions.where((s) {
          final sid = s['skill_id'] as String?;
          return sid != null && sid.isNotEmpty;
        }).toList();
      } else {
        sessions = await _historyDao.getSessions();
      }
      if (mounted) {
        setState(() {
          _stats = stats;
          _sessions = sessions;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AiDataPage: 加载数据失败: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 数据管理'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatsSection(primary),
                  const SizedBox(height: 20),
                  _buildHistorySection(primary),
                  const SizedBox(height: 20),
                  _buildCleanupSection(primary),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 使用统计
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatsSection(Color primary) {
    final totalSessions = _stats['totalSessions'] ?? 0;
    final totalMessages = _stats['totalMessages'] ?? 0;
    final weekSessions = _stats['weekSessions'] ?? 0;
    final topAgentId = _stats['topAgentId'] as String?;
    final topAgentCount = _stats['topAgentCount'] ?? 0;

    // 获取最活跃智能体名称
    String topAgentName = '暂无';
    if (topAgentId != null && topAgentId.isNotEmpty) {
      AgentRegistry.instance.initialize();
      final agent = AgentRegistry.instance.getAgent(topAgentId);
      if (agent != null) {
        topAgentName = '${agent.config.emoji} ${agent.config.name} ($topAgentCount次)';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('📊 使用统计', primary),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statCard('总对话数', '$totalSessions', Icons.chat, Colors.blue)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('总消息数', '$totalMessages', Icons.message, Colors.green)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statCard('本周使用', '$weekSessions 次', Icons.calendar_today, Colors.orange)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('最活跃', topAgentName, Icons.star, Colors.purple)),
          ],
        ),
        // 智能体使用排行
        if ((_stats['agentStats'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          _buildAgentRanking(primary),
        ],
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentRanking(Color primary) {
    final agentStats = _stats['agentStats'] as List<Map<String, dynamic>>? ?? [];
    if (agentStats.isEmpty) return const SizedBox.shrink();

    AgentRegistry.instance.initialize();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('智能体使用排行', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(height: 10),
            ...agentStats.take(5).map((stat) {
              final agentId = stat['agent_id'] as String? ?? '';
              final count = (stat['cnt'] as int?) ?? 0;
              final agent = AgentRegistry.instance.getAgent(agentId);
              final name = agent != null ? '${agent.config.emoji} ${agent.config.name}' : agentId;
              final maxCount = (agentStats.first['cnt'] as int?) ?? 1;
              final ratio = maxCount > 0 ? count / maxCount : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        Text('$count 次', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: primary.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(primary),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 对话历史
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHistorySection(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('📋 对话历史', primary)),
            // 筛选
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('全部', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'agent', label: Text('智能体', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'skill', label: Text('技能', style: TextStyle(fontSize: 11))),
              ],
              selected: {_filterType},
              onSelectionChanged: (selected) {
                setState(() => _filterType = selected.first);
                _loadData();
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_sessions.isEmpty)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 8),
                    const Text('暂无对话记录', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          )
        else
          ...(_sessions.take(20).map((session) => _buildSessionCard(session, primary))),
        if (_sessions.length > 20)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Text(
                '仅显示最近 20 条，共 ${_sessions.length} 条',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, Color primary) {
    final sessionId = session['session_id'] as String? ?? '';
    final agentId = session['agent_id'] as String? ?? '';
    final skillId = session['skill_id'] as String? ?? '';
    final msgCount = (session['message_count'] as int?) ?? 0;
    final lastAt = session['last_at'] as String? ?? '';
    final firstMsg = session['first_user_msg'] as String? ?? '(无消息)';

    // 获取智能体/技能名称
    String label;
    IconData icon;
    Color color;
    if (agentId.isNotEmpty) {
      AgentRegistry.instance.initialize();
      final agent = AgentRegistry.instance.getAgent(agentId);
      label = agent != null ? '${agent.config.emoji} ${agent.config.name}' : agentId;
      icon = Icons.smart_toy;
      color = Colors.indigo;
    } else if (skillId.isNotEmpty) {
      label = '🛠️ 技能: $skillId';
      icon = Icons.auto_awesome;
      color = Colors.teal;
    } else {
      label = '💬 对话';
      icon = Icons.chat;
      color = Colors.grey;
    }

    final dateStr = lastAt.length >= 16 ? lastAt.substring(0, 16).replaceAll('T', ' ') : lastAt;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, size: 18, color: color),
        ),
        title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              firstMsg.length > 50 ? '${firstMsg.substring(0, 50)}...' : firstMsg,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '$dateStr · $msgCount 条消息',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          onPressed: () => _deleteSession(sessionId),
          tooltip: '删除会话',
        ),
        onTap: () => _showSessionDetail(sessionId, label),
      ),
    );
  }

  Future<void> _showSessionDetail(String sessionId, String label) async {
    final messages = await _historyDao.getSessionMessages(sessionId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  Text('${messages.length} 条消息', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (ctx, index) {
                  final msg = messages[index];
                  final role = msg['role'] as String? ?? '';
                  final content = msg['content'] as String? ?? '';
                  final createdAt = msg['created_at'] as String? ?? '';
                  final isUser = role == 'user';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            Text(
                              isUser ? '用户' : (role == 'system' ? '系统' : '助手'),
                              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              createdAt.length >= 19 ? createdAt.substring(11, 19) : '',
                              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(ctx).size.width * 0.75,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            content,
                            style: const TextStyle(fontSize: 13, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('确定要删除这个会话的所有消息吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyDao.deleteSession(sessionId);
      await _loadData();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 数据清理
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCleanupSection(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🗑️ 数据清理', primary),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.red),
                title: const Text('清除全部对话历史', style: TextStyle(fontSize: 14)),
                subtitle: Text('删除所有 AI 对话记录', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _clearAllHistory,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.date_range, color: Colors.orange),
                title: const Text('清除 7 天前的历史', style: TextStyle(fontSize: 14)),
                subtitle: Text('保留最近一周的记录', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _clearOldHistory,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.file_download, color: Colors.blue),
                title: const Text('导出历史记录 (JSON)', style: TextStyle(fontSize: 14)),
                subtitle: Text('导出所有对话数据', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _exportHistory,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部历史'),
        content: const Text('确定要清除所有 AI 对话历史记录吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除全部', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final count = await _historyDao.clearAll();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 $count 条记录')),
        );
      }
    }
  }

  Future<void> _clearOldHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除旧记录'),
        content: const Text('确定要清除 7 天前的对话历史吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final before = DateTime.now().subtract(const Duration(days: 7));
      final count = await _historyDao.clearHistory(before: before);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 $count 条旧记录')),
        );
      }
    }
  }

  Future<void> _exportHistory() async {
    try {
      final data = await _historyDao.exportHistory();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      // 保存到文件
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/ai_exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('${exportDir.path}/ai_history_$timestamp.json');
      await file.writeAsString(jsonStr, flush: true);

      // 同时复制到剪贴板
      if (jsonStr.length < 100000) {
        await Clipboard.setData(ClipboardData(text: jsonStr));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出 ${data.length} 条记录到: ${file.path}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () {
                try {
                  if (Platform.isWindows) {
                    Process.run('explorer', [exportDir.path]);
                  } else if (Platform.isMacOS) {
                    Process.run('open', [exportDir.path]);
                  }
                } catch (_) {}
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 辅助
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _sectionTitle(String title, Color primary) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: primary,
      ),
    );
  }
}
