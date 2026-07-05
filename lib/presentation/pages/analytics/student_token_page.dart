import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/ai_history_dao.dart';
import '../../../data/local/class_dao.dart';
import '../../../services/auth_service.dart';
import '../../../core/error_handler.dart';

class StudentTokenPage extends StatefulWidget {
  const StudentTokenPage({super.key});

  @override
  State<StudentTokenPage> createState() => _StudentTokenPageState();
}

class _StudentTokenPageState extends State<StudentTokenPage> {
  final _dao = AiHistoryDao();
  final _classDao = ClassDao();

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _classes = [];
  String? _selectedClassId;
  bool _loading = true;
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _classDao.getActiveClasses(),
        _dao.getTokenTotalsByUser(classId: _selectedClassId),
      ]);
      if (mounted) {
        setState(() {
          _classes = results[0];
          _students = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('StudentTokenPage: 加载数据失败: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return tokens.toString();
  }

  String _displayName(Map<String, dynamic> row) {
    final name = row['real_name'] as String? ?? '';
    if (name.isNotEmpty) return name;
    return row['user_id'] as String? ?? '未知';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final role = AuthService().currentUser?.role ?? 'student';

    if (role == 'student') {
      return _buildSelfView(primary);
    }

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildClassFilter(primary),
                const SizedBox(height: 12),
                _buildSummaryBar(primary),
                const SizedBox(height: 12),
                ...List.generate(_students.length, (i) => _buildStudentCard(i, primary)),
                if (_students.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: Text('暂无学生 Token 数据', style: TextStyle(color: Colors.grey))),
                  ),
              ],
            ),
          );
  }

  Widget _buildSelfView(Color primary) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dao.getDailyTokenStatsByUser(
        AuthService().currentUser?.userId ?? '',
        days: 30,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final stats = snapshot.data!;
        int totalTokens = 0;
        for (final row in stats) {
          totalTokens += (row['total_tokens'] as int?) ?? 0;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('我的 Token 用量', primary),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.token, size: 48, color: Colors.deepPurple),
                    const SizedBox(height: 12),
                    Text(_formatTokens(totalTokens),
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primary)),
                    const SizedBox(height: 4),
                    const Text('近30天总 Token 消耗', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildDailyMiniChart(stats, primary),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDailyMiniChart(List<Map<String, dynamic>> stats, Color primary) {
    int maxTokens = 1;
    for (final row in stats) {
      final t = (row['total_tokens'] as int?) ?? 0;
      if (t > maxTokens) maxTokens = t;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('每日趋势', primary),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) => Text(
                          _formatTokens(value.toInt()),
                          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: (stats.length / 5).ceilToDouble().clamp(1, 100),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= stats.length) return const SizedBox.shrink();
                          final parts = (stats[idx]['date'] as String? ?? '').split('-');
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(parts.length >= 3 ? '${parts[1]}/${parts[2]}' : '',
                                style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: (maxTokens * 1.15).ceilToDouble(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(stats.length, (i) =>
                          FlSpot(i.toDouble(), (stats[i]['total_tokens'] as int?)?.toDouble() ?? 0)),
                      isCurved: true,
                      color: primary,
                      barWidth: 2.5,
                      belowBarData: BarAreaData(show: true, color: primary.withOpacity(0.1)),
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

  Widget _buildClassFilter(Color primary) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: DropdownButton<String?>(
          value: _selectedClassId,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          hint: const Text('全部班级'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('全部班级')),
            ..._classes.map((c) => DropdownMenuItem<String?>(
                  value: c['id'].toString(),
                  child: Text(c['name'] as String? ?? ''),
                )),
          ],
          onChanged: (v) {
            setState(() => _selectedClassId = v);
            _loadData();
          },
        ),
      ),
    );
  }

  Widget _buildSummaryBar(Color primary) {
    int totalStudents = _students.length;
    int totalTokens = 0;
    for (final s in _students) {
      totalTokens += (s['total_tokens'] as int?) ?? 0;
    }
    return Row(
      children: [
        Text('$totalStudents 名学生', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const Spacer(),
        Text('合计 ${_formatTokens(totalTokens)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
      ],
    );
  }

  Widget _buildStudentCard(int index, Color primary) {
    final row = _students[index];
    final total = (row['total_tokens'] as int?) ?? 0;
    final prompt = (row['prompt_tokens'] as int?) ?? 0;
    final completion = (row['completion_tokens'] as int?) ?? 0;
    final count = (row['request_count'] as int?) ?? 0;
    final days = (row['active_days'] as int?) ?? 0;
    final lastActive = row['last_active'] as String? ?? '';
    final isExpanded = _expandedIndex == index;

    final maxTokens = _students.isNotEmpty
        ? (_students.map((s) => (s['total_tokens'] as int?) ?? 0).reduce((a, b) => a > b ? a : b))
        : 1;
    final ratio = maxTokens > 0 ? total / maxTokens : 0.0;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _expandedIndex = isExpanded ? null : index),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _avatarColor(index),
                    child: Text(
                      _displayName(row).isNotEmpty ? _displayName(row)[0] : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_displayName(row),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(row['user_id'] as String? ?? '',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_formatTokens(total),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
                      Text('$count 次 · $days 天',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: primary.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation(primary),
                  minHeight: 4,
                ),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 12),
                _buildDetailRow('输入 Token', _formatTokens(prompt), Icons.input, Colors.blue),
                _buildDetailRow('输出 Token', _formatTokens(completion), Icons.output, Colors.green),
                _buildDetailRow('活跃天数', '$days 天', Icons.calendar_today, Colors.orange),
                if (lastActive.isNotEmpty)
                  _buildDetailRow('最近活跃', _formatDateTime(lastActive), Icons.access_time, Colors.grey),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e, st) {
      swallowDebug(e, tag: 'StudentTokenPage._formatDateTime', stack: st);
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  Color _avatarColor(int index) {
    const colors = [Colors.deepPurple, Colors.blue, Colors.teal, Colors.orange, Colors.pink, Colors.indigo];
    return colors[index % colors.length];
  }

  Widget _sectionTitle(String title, Color primary) {
    return Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary));
  }
}
