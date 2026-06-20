import 'package:flutter/material.dart';
import '../../../core/constants/role_guard.dart';
import '../../../data/local/agent_call_log_dao.dart';
import '../../../services/auth_service.dart';
import '../../widgets/back_button_bar.dart';

/// AI 调用统计仪表板（教师 / 管理员）。
///
/// **数据源**：`agent_call_logs` 表，由 [BaseAgent.safeAiChatWithMeta]
/// 在 finally 中自动写入；无埋点开销。
///
/// **三块视图**：
/// 1. Agent 调用排行（COUNT/AVG_DURATION/SUM_CHARS）
/// 2. 最近调用链（chain_id 分组，看 Orchestrator 多步耗时）
/// 3. 最近原始日志（200 条 / 按 chain 跳转）
class AgentCallsDashboardPage extends StatefulWidget {
  const AgentCallsDashboardPage({super.key});

  @override
  State<AgentCallsDashboardPage> createState() =>
      _AgentCallsDashboardPageState();
}

class _AgentCallsDashboardPageState extends State<AgentCallsDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<Map<String, dynamic>> _agentRanking = [];
  List<Map<String, dynamic>> _recentChains = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ranking = await AgentCallLogDao.instance.aggregateByAgent();
    final chains = await AgentCallLogDao.instance.listRecentChains(limit: 30);
    if (!mounted) return;
    setState(() {
      _agentRanking = ranking;
      _recentChains = chains;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 角色守卫 — 学生侧无入口，但若手输路由仍可能进入；这里兜底拦截
    final role = AuthService().currentUser?.role ?? 'student';
    if (!RoleGuard.isTeacherOrAdmin(role)) {
      return Scaffold(
        appBar: BackButtonBar(title: 'AI 调用统计'),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('无权限访问', style: TextStyle(fontSize: 18, color: Colors.grey)),
              SizedBox(height: 8),
              Text('AI 调用统计仅教师 / 管理员可见',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: BackButtonBar(
        title: 'AI 调用统计',
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Agent 排行'),
            Tab(text: '调用链路'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildAgentRanking(),
                _buildChainList(),
              ],
            ),
    );
  }

  Widget _buildAgentRanking() {
    if (_agentRanking.isEmpty) {
      return const Center(
        child: Text('暂无 AI 调用记录\n（学生 / 教师与智能体对话后此处会显示统计）',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)),
      );
    }
    final totalCalls = _agentRanking.fold<int>(
        0, (s, r) => s + ((r['count'] as int?) ?? 0));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.bar_chart, size: 20),
                  const SizedBox(width: 8),
                  Text('总调用 $totalCalls 次',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('共 ${_agentRanking.length} 个 Agent',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._agentRanking.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            final count = (r['count'] as int?) ?? 0;
            final avgMs =
                ((r['avg_duration_ms'] as num?)?.toDouble() ?? 0).round();
            final pcChars =
                ((r['total_prompt_chars'] as num?)?.toInt()) ?? 0;
            final rcChars =
                ((r['total_response_chars'] as num?)?.toInt()) ?? 0;
            final percent = totalCalls > 0 ? count / totalCalls : 0.0;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _rankColor(i),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text(r['agent_name'] as String? ?? r['agent_id'] as String? ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percent,
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        '$count 次 · 平均 ${avgMs}ms · '
                        '消耗 ${(pcChars + rcChars) ~/ 1000}k 字符',
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
                isThreeLine: true,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChainList() {
    if (_recentChains.isEmpty) {
      return const Center(
        child: Text(
            '暂无 Orchestrator 调用链\n（教师在批阅页打开"增强批阅"后此处会显示）',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _recentChains.length,
        itemBuilder: (ctx, i) {
          final c = _recentChains[i];
          final chainId = c['chain_id'] as String? ?? '';
          final steps = (c['steps'] as int?) ?? 0;
          final totalMs =
              ((c['total_duration_ms'] as num?)?.toInt()) ?? 0;
          final agentChain = c['agent_chain'] as String? ?? '';
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.link, color: Colors.indigo),
              title: Text(agentChain.replaceAll(',', ' → '),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              subtitle: Text(
                  '$steps 步 · 总耗时 ${totalMs}ms · '
                  '${(c['started_at'] as String? ?? '').replaceFirst('T', ' ').substring(0, 19)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showChainDetail(chainId),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showChainDetail(String chainId) async {
    final logs = await AgentCallLogDao.instance.listByChain(chainId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.link),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('调用链详情 · $chainId',
                        style: const TextStyle(
                            fontSize: 14, fontFamily: 'monospace')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: logs.length,
                  itemBuilder: (c, i) {
                    final l = logs[i];
                    final step = (l['chain_step'] as int?) ?? i;
                    final dur = (l['duration_ms'] as int?) ?? 0;
                    final err = l['error'] as String?;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  child: Text('$step',
                                      style: const TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                    l['agent_name'] as String? ??
                                        l['agent_id'] as String? ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text('${dur}ms',
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Prompt: ${l['prompt_summary'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(
                                'Response: ${(l['response_summary'] as String?)?.substring(0, ((l['response_summary'] as String?)?.length ?? 0).clamp(0, 200)) ?? ''}',
                                style: const TextStyle(fontSize: 12)),
                            if (err != null && err.isNotEmpty)
                              Text('错误: $err',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.red)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _rankColor(int idx) {
    switch (idx) {
      case 0:
        return Colors.amber[700]!;
      case 1:
        return Colors.grey[500]!;
      case 2:
        return Colors.brown[300]!;
      default:
        return Colors.indigo[300]!;
    }
  }
}
