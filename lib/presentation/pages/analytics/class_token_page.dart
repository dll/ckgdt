import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/ai_history_dao.dart';

class ClassTokenPage extends StatefulWidget {
  const ClassTokenPage({super.key});

  @override
  State<ClassTokenPage> createState() => _ClassTokenPageState();
}

class _ClassTokenPageState extends State<ClassTokenPage> {
  final _dao = AiHistoryDao();

  List<Map<String, dynamic>> _classStats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final stats = await _dao.getTokenTotalsByClass();
      if (mounted) {
        setState(() {
          _classStats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ClassTokenPage: load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _classStats.isEmpty
          ? ListView(children: const [
              Padding(padding: EdgeInsets.all(48),
                  child: Center(child: Text('暂无班级 Token 数据', style: TextStyle(color: Colors.grey)))),
            ])
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummaryBar(primary),
                const SizedBox(height: 16),
                _buildClassChart(primary),
                const SizedBox(height: 20),
                _sectionTitle('班级明细', primary),
                const SizedBox(height: 12),
                ...List.generate(_classStats.length, (i) => _buildClassCard(i, primary)),
              ],
            ),
    );
  }

  Widget _buildSummaryBar(Color primary) {
    int totalStudents = 0, totalTokens = 0;
    for (final row in _classStats) {
      totalStudents += (row['student_count'] as int?) ?? 0;
      totalTokens += (row['total_tokens'] as int?) ?? 0;
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _sumItem('${_classStats.length} 个', '班级', Colors.deepPurple),
            _sumItem('$totalStudents 人', '涉及学生', Colors.blue),
            _sumItem(_fmt(totalTokens), '总 Token', primary),
          ],
        ),
      ),
    );
  }

  Widget _sumItem(String value, String label, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }

  Widget _buildClassChart(Color primary) {
    final stats = _classStats.take(8).toList();
    int maxTokens = 1;
    for (final row in stats) {
      final t = (row['total_tokens'] as int?) ?? 0;
      if (t > maxTokens) maxTokens = t;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('班级 Token 对比（Top 8）', primary),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
            child: SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxTokens * 1.2).ceilToDouble(),
                  barGroups: List.generate(stats.length, (i) {
                    final t = (stats[i]['total_tokens'] as int?)?.toDouble() ?? 0;
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(toY: t, color: _barColor(i), width: 28,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                    ]);
                  }),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 42,
                      getTitlesWidget: (v, _) => Text(_fmt(v.toInt()),
                          style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    )),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 60,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= stats.length) return const SizedBox.shrink();
                        final name = stats[idx]['class_name'] as String? ?? '';
                        return Padding(padding: const EdgeInsets.only(top: 6),
                            child: Text(name.length > 10 ? '${name.substring(0, 10)}...' : name,
                                style: TextStyle(fontSize: 9, color: Colors.grey[600])));
                      },
                    )),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withValues(alpha: 0.15), strokeWidth: 1)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassCard(int index, Color primary) {
    final row = _classStats[index];
    final total = (row['total_tokens'] as int?) ?? 0;
    final prompt = (row['prompt_tokens'] as int?) ?? 0;
    final completion = (row['completion_tokens'] as int?) ?? 0;
    final count = (row['request_count'] as int?) ?? 0;
    final studentCount = (row['student_count'] as int?) ?? 0;
    final name = row['class_name'] as String? ?? '未知班级';
    final maxTokens = _classStats.isNotEmpty
        ? (_classStats.map((s) => (s['total_tokens'] as int?) ?? 0).reduce((a, b) => a > b ? a : b))
        : 1;
    final ratio = maxTokens > 0 ? total / maxTokens : 0.0;
    final avg = studentCount > 0 ? (total ~/ studentCount) : 0;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.school, size: 20, color: _barColor(index)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('$studentCount 名学生', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_fmt(total), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
                Text('人均 ${_fmt(avg)}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ]),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: ratio, minHeight: 6,
                  backgroundColor: primary.withValues(alpha: 0.08), valueColor: AlwaysStoppedAnimation(primary)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _mini('输入', _fmt(prompt), Colors.blue),
              const SizedBox(width: 16),
              _mini('输出', _fmt(completion), Colors.green),
              const SizedBox(width: 16),
              _mini('请求', '$count 次', Colors.orange),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _mini(String label, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Color _barColor(int i) {
    const c = [Colors.deepPurple, Colors.blue, Colors.teal, Colors.orange, Colors.pink, Colors.indigo];
    return c[i % c.length];
  }

  Widget _sectionTitle(String title, Color primary) {
    return Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary));
  }
}
