import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../data/local/achievement_dao.dart';
import '../../../../services/course_context_service.dart';
import '../achievement_config.dart';

class AbComparisonTab extends StatefulWidget {
  final AchievementDao achievementDao;
  final ValueNotifier<int>? dataRevision;

  const AbComparisonTab({
    super.key,
    required this.achievementDao,
    this.dataRevision,
  });

  @override
  State<AbComparisonTab> createState() => _AbComparisonTabState();
}

class _AbComparisonTabState extends State<AbComparisonTab> {
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _scoresA = [];
  List<Map<String, dynamic>> _scoresB = [];
  int? _batchAId;
  int? _batchBId;
  bool _loading = true;
  final CourseContextService _courseContext = CourseContextService();
  AchievementConfig _config = AchievementConfig.defaults;
  List<double> _classAvgA = [0, 0, 0, 0];
  List<double> _classAvgB = [0, 0, 0, 0];

  @override
  void initState() {
    super.initState();
    _loadBatches();
    widget.dataRevision?.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    widget.dataRevision?.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      if (mounted) {
        setState(() {
          _batches = batches;
          _loading = false;
          if (_batches.isNotEmpty && _batchAId == null) {
            _batchAId = _batches.first['id'] as int;
            if (_batches.length > 1) {
              _batchBId = _batches[1]['id'] as int;
            }
          }
        });
        if (_batchAId != null && _batchBId != null) _loadScores();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadScores() async {
    if (_batchAId == null || _batchBId == null) return;
    setState(() => _loading = true);
    try {
      final scoresA = await widget.achievementDao.getScores(_batchAId!);
      final scoresB = await widget.achievementDao.getScores(_batchBId!);
      final courseName = await _courseContext.activeCourseName();
      final rows =
          await widget.achievementDao.getCourseObjectives(courseName);
      final cfg = rows.isNotEmpty
          ? AchievementConfig.fromObjectiveRows(rows)
          : AchievementConfig.defaults;

      _classAvgA = _calcBatchAvgs(scoresA);
      _classAvgB = _calcBatchAvgs(scoresB);

      if (mounted) {
        setState(() {
          _config = cfg;
          _scoresA = scoresA;
          _scoresB = scoresB;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<double> _calcBatchAvgs(List<Map<String, dynamic>> scores) {
    if (scores.isEmpty) return [0, 0, 0, 0];
    final sums = List<double>.filled(4, 0);
    for (final s in scores) {
      for (int i = 0; i < 4; i++) {
        sums[i] += (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
      }
    }
    final n = scores.length.toDouble();
    return [for (final v in sums) v / n];
  }

  List<int> get _activeObjectiveIndexes {
    final indexes = [
      for (var i = 0; i < 4; i++)
        if (_config.weights[i] > 0 || _config.fullMarks[i] > 0) i
    ];
    return indexes.isEmpty ? [0, 1, 2, 3] : indexes;
  }

  double _passRate(List<Map<String, dynamic>> scores) {
    if (scores.isEmpty) return 0;
    int passed = 0;
    for (final s in scores) {
      final t = (s['total_score'] as num?)?.toDouble() ?? 0;
      if (t >= 60) passed++;
    }
    return passed / scores.length;
  }

  double _totalAvg(List<Map<String, dynamic>> scores) {
    if (scores.isEmpty) return 0;
    double sum = 0;
    for (final s in scores) {
      sum += (s['total_score'] as num?)?.toDouble() ?? 0;
    }
    return sum / scores.length;
  }

  double _stdDev(List<Map<String, dynamic>> scores) {
    if (scores.isEmpty) return 0;
    final avg = _totalAvg(scores);
    double sumSq = 0;
    for (final s in scores) {
      final v = (s['total_score'] as num?)?.toDouble() ?? 0;
      sumSq += (v - avg) * (v - avg);
    }
    return sqrt(sumSq / scores.length);
  }

  double sqrt(double v) {
    if (v <= 0) return 0;
    double x = v;
    double y = 1;
    const e = 0.001;
    while (x - y > e) {
      x = (x + y) / 2;
      y = v / x;
    }
    return x;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _batches.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    if (_batches.length < 2) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows, size: 64, color: cs.error.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('至少需要两个批次才能进行 AB 对照',
                style: TextStyle(color: cs.error)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildBatchSelectors(primary),
        const SizedBox(height: 12),
        _buildComparisonMetrics(primary),
        const SizedBox(height: 12),
        _buildRadarChart(cs),
        const SizedBox(height: 12),
        _buildBarChart(primary),
        const SizedBox(height: 12),
        _buildScatterPlot(primary),
      ]),
    );
  }

  Widget _buildBatchSelectors(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _buildSingleSelector('批次 A', _batchAId, (v) {
                setState(() => _batchAId = v);
                _loadScores();
              }, primary),
            ),
            const SizedBox(width: 12),
            Icon(Icons.compare_arrows, color: primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSingleSelector('批次 B', _batchBId, (v) {
                setState(() => _batchBId = v);
                _loadScores();
              }, primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleSelector(
      String label, int? value, ValueChanged<int?> onChanged, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: primary)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              border: Border.all(color: primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: value,
              hint: const Text('选择批次', style: TextStyle(fontSize: 13)),
              items: _batches
                  .map((b) => DropdownMenuItem<int>(
                      value: b['id'] as int,
                      child: Text(b['batch_name']?.toString() ?? '未命名',
                          style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonMetrics(Color primary) {
    final passA = _passRate(_scoresA);
    final passB = _passRate(_scoresB);
    final avgA = _totalAvg(_scoresA);
    final avgB = _totalAvg(_scoresB);
    final stdA = _stdDev(_scoresA);
    final stdB = _stdDev(_scoresB);
    final countA = _scoresA.length;
    final countB = _scoresB.length;

    String deltaStr(double a, double b, {bool pct = false, int digs = 1}) {
      final diff = b - a;
      final sign = diff >= 0 ? '+' : '';
      if (pct) return '$sign${(diff * 100).toStringAsFixed(digs)}%';
      return '$sign${diff.toStringAsFixed(digs)}';
    }

    Color deltaColor(double a, double b, {bool higherBetter = true}) {
      if (a == b) return Colors.grey;
      return higherBetter == (b > a) ? Colors.green : Colors.red;
    }

    Widget metricCard(String label, String aVal, String bVal, String delta,
        Color dColor) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(delta,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: dColor)),
              const SizedBox(height: 2),
              Text('A:$aVal  B:$bVal',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('关键指标对比',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(height: 8),
            Row(
              children: [
                metricCard(
                    '人数',
                    '$countA',
                    '$countB',
                    deltaStr(countA.toDouble(), countB.toDouble()),
                    deltaColor(countA.toDouble(), countB.toDouble())),
                const SizedBox(width: 6),
                metricCard(
                    '平均分',
                    avgA.toStringAsFixed(1),
                    avgB.toStringAsFixed(1),
                    deltaStr(avgA, avgB),
                    deltaColor(avgA, avgB)),
                const SizedBox(width: 6),
                metricCard(
                    '通过率',
                    '${(passA * 100).toStringAsFixed(1)}%',
                    '${(passB * 100).toStringAsFixed(1)}%',
                    deltaStr(passA, passB, pct: true),
                    deltaColor(passA, passB)),
                const SizedBox(width: 6),
                metricCard(
                    '标准差',
                    stdA.toStringAsFixed(1),
                    stdB.toStringAsFixed(1),
                    deltaStr(stdA, stdB, digs: 2),
                    deltaColor(stdA, stdB, higherBetter: false)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarChart(ColorScheme cs) {
    final active = _activeObjectiveIndexes;
    if (active.length < 3 || _scoresA.isEmpty || _scoresB.isEmpty) {
      return const SizedBox.shrink();
    }
    final aVals = [for (final i in active) _classAvgA[i]];
    final bVals = [for (final i in active) _classAvgB[i]];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.radar, color: cs.primary, size: 20),
              const SizedBox(width: 6),
              Text('课程目标达成度雷达对照',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  tickCount: 5,
                  ticksTextStyle: const TextStyle(fontSize: 9, color: Colors.grey),
                  radarBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                  gridBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  tickBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                  titlePositionPercentageOffset: 0.15,
                  titleTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  getTitle: (index, angle) {
                    if (index < 0 || index >= active.length) {
                      return const RadarChartTitle(text: '');
                    }
                    final obj = active[index];
                    return RadarChartTitle(
                        text: '目标${obj + 1}\n${(_classAvgA[obj] * 100).toStringAsFixed(0)}%');
                  },
                  dataSets: [
                    RadarDataSet(
                      fillColor: Colors.blue.withValues(alpha: 0.15),
                      borderColor: Colors.blue,
                      borderWidth: 2,
                      entryRadius: 3,
                      dataEntries: [for (final v in aVals) RadarEntry(value: v.clamp(0.0, 1.0))],
                    ),
                    RadarDataSet(
                      fillColor: Colors.orange.withValues(alpha: 0.15),
                      borderColor: Colors.orange,
                      borderWidth: 2,
                      entryRadius: 3,
                      dataEntries: [for (final v in bVals) RadarEntry(value: v.clamp(0.0, 1.0))],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(Colors.blue, '批次 A'),
                const SizedBox(width: 20),
                _legendDot(Colors.orange, '批次 B'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildBarChart(Color primary) {
    final aCount = _scoresA.length;
    final bCount = _scoresB.length;
    if (aCount == 0 && bCount == 0) return const SizedBox.shrink();

    final passA = _passRate(_scoresA);
    final passB = _passRate(_scoresB);
    final avgA = _totalAvg(_scoresA);
    final avgB = _totalAvg(_scoresB);

    final activeLabels = ['人数', '平均分', '通过率'];
    final maxY = [
      [aCount.toDouble(), bCount.toDouble()],
      [avgA.clamp(0, 100), avgB.clamp(0, 100)],
      [passA, passB],
    ];

    final groupCount = activeLabels.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.bar_chart, color: primary, size: 20),
              const SizedBox(width: 6),
              Text('指标分组对比',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 1.0,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          rod.toY.toStringAsFixed(1),
                          TextStyle(color: rod.color, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= groupCount) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(activeLabels[idx], style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) => Text(
                          '${(value * 100).toInt()}%',
                          style: const TextStyle(fontSize: 9, color: Colors.grey),
                        ),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 0.2,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.15),
                      strokeWidth: 0.5,
                    ),
                  ),
                  barGroups: List.generate(groupCount, (i) {
                    final aVal = maxY[i][0];
                    final bVal = maxY[i][1];
                    final groupMax = [aVal, bVal].reduce((a, b) => a > b ? a : b);
                    final scale = groupMax > 0 ? 1.0 / groupMax : 1.0;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: aVal * scale,
                          color: Colors.blue,
                          width: 12,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                        BarChartRodData(
                          toY: bVal * scale,
                          color: Colors.orange,
                          width: 12,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(Colors.blue, '批次 A'),
                const SizedBox(width: 20),
                _legendDot(Colors.orange, '批次 B'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScatterPlot(Color primary) {
    if (_scoresA.isEmpty && _scoresB.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.scatter_plot, color: primary, size: 20),
              const SizedBox(width: 6),
              Text('学生成绩分布散点图',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: ScatterChart(
                ScatterChartData(
                  minX: 0,
                  maxX: ((_scoresA.length + _scoresB.length) - 1).clamp(1, 1).toDouble() + 1,
                  minY: 0,
                  maxY: 100,
                  scatterSpots: [
                    ..._scoresA.asMap().entries.map((e) => ScatterSpot(
                      e.key.toDouble(),
                      (e.value['total_score'] as num?)?.toDouble() ?? 0,
                      dotPainter: FlDotCirclePainter(
                        radius: 3.5,
                        color: Colors.blue.withValues(alpha: 0.6),
                      ),
                    )),
                    ..._scoresB.asMap().entries.map((e) => ScatterSpot(
                      (e.key + _scoresA.length).toDouble(),
                      (e.value['total_score'] as num?)?.toDouble() ?? 0,
                      dotPainter: FlDotCirclePainter(
                        radius: 3.5,
                        color: Colors.orange.withValues(alpha: 0.6),
                      ),
                    )),
                  ],
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 10,
                    getDrawingHorizontalLine: (v) {
                      if ((v - 60).abs() < 0.5) {
                        return const FlLine(color: Colors.red, strokeWidth: 1.5);
                      }
                      return FlLine(
                        color: Colors.grey.withValues(alpha: 0.15),
                        strokeWidth: 0.5,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: const TextStyle(fontSize: 9, color: Colors.grey),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx == 0) {
                            return Text('A组\n${_scoresA.length}人',
                                style: const TextStyle(fontSize: 9, color: Colors.grey));
                          }
                          if (idx == _scoresA.length) {
                            return Text('B组\n${_scoresB.length}人',
                                style: const TextStyle(fontSize: 9, color: Colors.grey));
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(Colors.blue.withValues(alpha: 0.6), '批次 A'),
                const SizedBox(width: 16),
                _legendDot(Colors.orange.withValues(alpha: 0.6), '批次 B'),
                const SizedBox(width: 16),
                Container(
                  width: 24, height: 2, color: Colors.red,
                ),
                const SizedBox(width: 4),
                const Text('及格线(60分)', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
