import 'package:flutter/material.dart';
import '../../../data/local/ai_history_dao.dart';
import '../../../services/auth_service.dart';

class RequestDetailTab extends StatefulWidget {
  const RequestDetailTab({super.key});

  @override
  State<RequestDetailTab> createState() => _RequestDetailTabState();
}

class _RequestDetailTabState extends State<RequestDetailTab> {
  final _dao = AiHistoryDao();
  final _role = AuthService().currentUser?.role ?? 'student';
  final _userId = AuthService().currentUser?.userId;

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _total = 0;

  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _role == 'student' ? _userId : null;
      final results = await Future.wait([
        _dao.getRequestLogs(limit: _pageSize, offset: 0, userId: uid),
        _dao.getRequestCount(userId: uid),
      ]);
      if (mounted) {
        setState(() {
          _logs = results[0] as List<Map<String, dynamic>>;
          _total = results[1] as int;
          _loading = false;
          _hasMore = _logs.length < _total;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败: $e';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final uid = _role == 'student' ? _userId : null;
      final more = await _dao.getRequestLogs(
        limit: _pageSize,
        offset: _logs.length,
        userId: uid,
      );
      if (mounted) {
        setState(() {
          _logs.addAll(more);
          _loadingMore = false;
          _hasMore = _logs.length < _total;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return tokens.toString();
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadFirst,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 12),
            const Text('暂无请求记录', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _logs.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _logs.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return _buildLogCard(_logs[index]);
          },
        ),
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final primary = Theme.of(context).colorScheme.primary;
    final time = log['created_at'] as String? ?? '';
    final model = log['model'] as String? ?? '未知';
    final provider = log['provider'] as String? ?? '未知';
    final prompt = (log['prompt_tokens'] as int?) ?? 0;
    final completion = (log['completion_tokens'] as int?) ?? 0;
    final total = (log['tokens_used'] as int?) ?? 0;
    final agentId = log['agent_id'] as String? ?? '';
    final sessionId = log['session_id'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy, size: 16, color: primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    model,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _formatTime(time),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _tokenChip('输入', prompt, Colors.blue),
                const SizedBox(width: 6),
                _tokenChip('输出', completion, Colors.green),
                const SizedBox(width: 6),
                _tokenChip('合计', total, Colors.deepPurple),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _providerColor(provider).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    provider,
                    style: TextStyle(fontSize: 10, color: _providerColor(provider)),
                  ),
                ),
              ],
            ),
            if (agentId.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.extension, size: 12, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(agentId, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  const SizedBox(width: 12),
                  Icon(Icons.fingerprint, size: 12, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sessionId.length > 16 ? '${sessionId.substring(0, 16)}…' : sessionId,
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
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

  Widget _tokenChip(String label, int tokens, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
          const SizedBox(width: 3),
          Text(_formatTokens(tokens), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Color _providerColor(String provider) {
    final p = provider.toLowerCase();
    if (p.contains('deepseek')) return Colors.indigo;
    if (p.contains('zhipu') || p.contains('glm')) return Colors.teal;
    if (p.contains('openai')) return Colors.green;
    return Colors.blueGrey;
  }
}
