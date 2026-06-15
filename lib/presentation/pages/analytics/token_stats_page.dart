import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/ai_history_dao.dart';
import '../../../services/auth_service.dart';
import 'student_token_page.dart';
import 'class_token_page.dart';
import 'request_detail_tab.dart';
import '../../widgets/back_button_bar.dart';

class TokenStatsPage extends StatefulWidget {
  const TokenStatsPage({super.key});

  @override
  State<TokenStatsPage> createState() => _TokenStatsPageState();
}

class _TokenStatsPageState extends State<TokenStatsPage>
    with SingleTickerProviderStateMixin {
  final _dao = AiHistoryDao();
  final _role = AuthService().currentUser?.role ?? 'student';

  Map<String, int> _totals = {};
  List<Map<String, dynamic>> _dailyStats = [];
  List<Map<String, dynamic>> _modelStats = [];
  List<Map<String, dynamic>> _providerStats = [];
  bool _loading = true;
  String? _error;
  late final TabController _tabController;

  bool get _isStaff => _role == 'teacher' || _role == 'admin';
  int get _tabCount => _isStaff ? 4 : 2;

  List<Widget> get _tabs {
    final tabs = <Widget>[
      const Tab(text: '总览'),
      const Tab(text: '明细'),
    ];
    if (_isStaff) {
      tabs.addAll([const Tab(text: '学生'), const Tab(text: '班级')]);
    }
    return tabs;
  }

  List<Widget> get _tabViews {
    final views = <Widget>[
      _buildOverviewTab(),
      _buildDetailLogTab(),
    ];
    if (_isStaff) {
      views.addAll([const StudentTokenPage(), const ClassTokenPage()]);
    }
    return views;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = AuthService().currentUser?.userId;
      final results = await Future.wait([
        _dao.getTokenTotals(userId: _isStaff ? null : userId),
        _dao.getDailyTokenStats(days: 30),
        _dao.getModelTokenStats(),
        _dao.getProviderTokenStats(),
      ]);
      if (mounted) {
        setState(() {
          _totals = results[0] as Map<String, int>;
          _dailyStats = results[1] as List<Map<String, dynamic>>;
          _modelStats = results[2] as List<Map<String, dynamic>>;
          _providerStats = results[3] as List<Map<String, dynamic>>;
          _loading = false;
          _error = null;
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

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return tokens.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BackButtonBar(
        title: 'Token 用量统计',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
            Text(_error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return TabBarView(controller: _tabController, children: _tabViews);
  }

  Widget _buildOverviewTab() {
    final primary = Theme.of(context).colorScheme.primary;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCards(primary),
          const SizedBox(height: 20),
          _buildDailyChart(primary),
          const SizedBox(height: 20),
          _buildModelChart(primary),
          const SizedBox(height: 20),
          _buildProviderChart(primary),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDetailLogTab() {
    return const RequestDetailTab();
  }

  Widget _buildSummaryCards(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Token 总览', primary),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                  '总 Token',
                  _formatTokens(_totals['grandTotal'] ?? 0),
                  Icons.token,
                  Colors.deepPurple),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                  '输入 Token',
                  _formatTokens(_totals['promptTotal'] ?? 0),
                  Icons.input,
                  Colors.blue),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statCard(
                  '输出 Token',
                  _formatTokens(_totals['completionTotal'] ?? 0),
                  Icons.output,
                  Colors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard('活跃天数', '${_totals['activeDays'] ?? 0} 天',
                  Icons.calendar_today, Colors.orange),
            ),
          ],
        ),
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
                Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyChart(Color primary) {
    if (_dailyStats.isEmpty) {
      return _emptyCard('暂无每日 Token 数据');
    }

    int maxTokens = 0;
    for (final row in _dailyStats) {
      final t = (row['total_tokens'] as int?) ?? 0;
      if (t > maxTokens) maxTokens = t;
    }
    if (maxTokens == 0) maxTokens = 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('每日 Token 趋势（近30天）', primary),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
            child: SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        maxTokens > 0 ? (maxTokens / 4).ceilToDouble() : 50,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max && value == meta.min)
                            return const SizedBox.shrink();
                          return Text(
                            _formatTokens(value.toInt()),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[500]),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: (_dailyStats.length / 5)
                            .ceilToDouble()
                            .clamp(1, 100),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _dailyStats.length)
                            return const SizedBox.shrink();
                          final dateStr =
                              _dailyStats[idx]['date'] as String? ?? '';
                          final parts = dateStr.split('-');
                          final label = parts.length >= 3
                              ? '${parts[1]}/${parts[2]}'
                              : dateStr;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey[500])),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: (maxTokens * 1.15).ceilToDouble(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(_dailyStats.length, (i) {
                        return FlSpot(
                            i.toDouble(),
                            (_dailyStats[i]['total_tokens'] as int?)
                                    ?.toDouble() ??
                                0);
                      }),
                      isCurved: true,
                      color: primary,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: _dailyStats.length <= 15,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                                radius: 3, color: primary, strokeWidth: 0),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelChart(Color primary) {
    if (_modelStats.isEmpty) {
      return _emptyCard('暂无模型 Token 数据');
    }

    final stats = _modelStats.take(6).toList();
    int maxTokens = 0;
    for (final row in stats) {
      final t = (row['total_tokens'] as int?) ?? 0;
      if (t > maxTokens) maxTokens = t;
    }
    if (maxTokens == 0) maxTokens = 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('各模型 Token 用量', primary),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
            child: SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxTokens * 1.2).ceilToDouble(),
                  barGroups: List.generate(stats.length, (i) {
                    final t =
                        (stats[i]['total_tokens'] as int?)?.toDouble() ?? 0;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: t,
                          color: _barColor(i),
                          width: 28,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            _formatTokens(value.toInt()),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[500]),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= stats.length)
                            return const SizedBox.shrink();
                          final model = stats[idx]['model'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              model.length > 12
                                  ? '${model.substring(0, 12)}...'
                                  : model,
                              style: TextStyle(
                                  fontSize: 9, color: Colors.grey[600]),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey.withValues(alpha: 0.15),
                        strokeWidth: 1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderChart(Color primary) {
    if (_providerStats.isEmpty) {
      return _emptyCard('暂无服务商 Token 数据');
    }

    final colorList = [
      Colors.indigo,
      Colors.teal,
      Colors.deepOrange,
      Colors.purple,
      Colors.blueGrey
    ];
    final maxTokens = (_providerStats
        .map((r) => (r['total_tokens'] as int?) ?? 0)
        .reduce((a, b) => a > b ? a : b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('各服务商 Token 用量', primary),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (int i = 0; i < _providerStats.length; i++) ...[
                  _buildProviderRow(
                    _providerStats[i],
                    colorList[i % colorList.length],
                    maxTokens > 0 ? maxTokens : 1,
                  ),
                  if (i < _providerStats.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderRow(
      Map<String, dynamic> row, Color color, int maxTokens) {
    final provider = row['provider'] as String? ?? '未知';
    final total = (row['total_tokens'] as int?) ?? 0;
    final prompt = (row['prompt_tokens'] as int?) ?? 0;
    final completion = (row['completion_tokens'] as int?) ?? 0;
    final count = (row['request_count'] as int?) ?? 0;
    final ratio = maxTokens > 0 ? total / maxTokens : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(provider,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            ),
            Text(_formatTokens(total),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.input, size: 12, color: Colors.grey[400]),
            const SizedBox(width: 2),
            Text('输入 ${_formatTokens(prompt)}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            const SizedBox(width: 12),
            Icon(Icons.output, size: 12, color: Colors.grey[400]),
            const SizedBox(width: 2),
            Text('输出 ${_formatTokens(completion)}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            const Spacer(),
            Text('$count 次请求',
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ),
      ],
    );
  }

  Color _barColor(int index) {
    const colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo
    ];
    return colors[index % colors.length];
  }

  Widget _sectionTitle(String title, Color primary) {
    return Text(title,
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: primary));
  }

  Widget _emptyCard(String message) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.token,
                  size: 48, color: Colors.grey.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text(message, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
