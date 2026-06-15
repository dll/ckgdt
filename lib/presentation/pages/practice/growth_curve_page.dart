import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../services/auth_service.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/learning_record_dao.dart';

import '../../widgets/back_button_bar.dart';

/// 能力增长曲线 — 灵感来自"天天向上"项目
/// 用数学模型展示不同学习模式的长期效果差异
class GrowthCurvePage extends StatefulWidget {
  const GrowthCurvePage({super.key});

  @override
  State<GrowthCurvePage> createState() => _GrowthCurvePageState();
}

class _GrowthCurvePageState extends State<GrowthCurvePage>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  final _quizDao = QuizDao();
  final _learningRecordDao = LearningRecordDao();

  late TabController _tabController;

  // 学习模式参数
  final _modes = <_LearningMode>[
    _LearningMode('冲刺模式', '每周5学2休，增长率2.4%',
        studyDays: 5, restDays: 2, rate: 0.024, color: Colors.purple),
    _LearningMode('标准模式', '每周5学2休，增长率1%',
        studyDays: 5, restDays: 2, rate: 0.01, color: Colors.blue),
    _LearningMode('内卷模式', '每天学习不休息，增长率1%',
        studyDays: 7, restDays: 0, rate: 0.01, color: Colors.red),
    _LearningMode('佛系模式', '每周2学5休，增长率1%',
        studyDays: 2, restDays: 5, rate: 0.01, color: Colors.green),
    _LearningMode('课程模式', '每周2学5休，增长率0.5%',
        studyDays: 2, restDays: 5, rate: 0.005, color: Colors.orange),
  ];

  Set<int> _activeModes = {0, 1, 3}; // 默认显示的模式
  int _totalDays = 120; // 学期天数
  bool _showLog = false; // 对数坐标

  // 学生实际数据
  List<FlSpot> _actualData = [];
  bool _hasActualData = false;

  // 自定义模式
  double _customRate = 0.01;
  int _customStudyDays = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadActualData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadActualData() async {
    final userId = _authService.currentUser?.userId;
    if (userId == null) return;

    try {
      // 获取学习记录，按日期统计
      final records = await _learningRecordDao.getRecords(userId);
      await _quizDao.getQuizResults(userId);

      // 统计每天的学习积累
      final dayMap = <int, double>{}; // 天数偏移→累计能力值
      if (records.isNotEmpty) {
        // 找到最早的学习日期
        DateTime? earliest;
        for (final r in records) {
          final dateStr = r['completed_at']?.toString();
          if (dateStr != null) {
            try {
              final d = DateTime.parse(dateStr);
              if (earliest == null || d.isBefore(earliest)) earliest = d;
            } catch (_) {}
          }
        }

        if (earliest != null) {
          double ability = 1.0;
          final today = DateTime.now();
          final totalDays = today.difference(earliest).inDays + 1;

          for (int d = 0; d < totalDays && d <= _totalDays; d++) {
            final date = earliest.add(Duration(days: d));
            // 计算当天的学习活动数
            int activities = 0;
            for (final r in records) {
              final dateStr = r['completed_at']?.toString();
              if (dateStr != null) {
                try {
                  final rd = DateTime.parse(dateStr);
                  if (rd.year == date.year &&
                      rd.month == date.month &&
                      rd.day == date.day) {
                    activities++;
                  }
                } catch (_) {}
              }
            }
            // 有学习活动则能力增长
            if (activities > 0) {
              ability *= (1 + 0.005 * min(activities, 5));
            } else {
              ability *= 0.999; // 不学习微弱衰减
            }
            dayMap[d] = ability;
          }
        }
      }

      if (dayMap.isNotEmpty) {
        final spots = dayMap.entries
            .map((e) => FlSpot(e.key.toDouble(), e.value))
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));

        if (mounted) {
          setState(() {
            _actualData = spots;
            _hasActualData = true;
          });
        }
      }
    } catch (_) {}
  }

  /// 计算某模式在第 day 天的能力值
  double _calcAbility(_LearningMode mode, int day) {
    double ability = 1.0;
    final cycleDays = mode.studyDays + mode.restDays;
    for (int d = 0; d < day; d++) {
      if (cycleDays == 0 || d % cycleDays < mode.studyDays) {
        ability *= (1 + mode.rate);
      } else {
        ability *= (1 - mode.rate / 3); // 休息日微弱衰减
      }
    }
    return ability;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: BackButtonBar(
        title: '能力增长曲线',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.show_chart, size: 18), text: '增长对比'),
            Tab(icon: Icon(Icons.tune, size: 18), text: '自定义模拟'),
            Tab(icon: Icon(Icons.person, size: 18), text: '我的成长'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildComparisonTab(isDark),
          _buildCustomTab(isDark),
          _buildPersonalTab(isDark),
        ],
      ),
    );
  }

  // ── Tab 1：增长对比 ──────────────────────────────────────────────

  Widget _buildComparisonTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 说明卡片
          Card(
            color: isDark
                ? Colors.indigo.withValues(alpha: 0.2)
                : Colors.indigo[50],
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_graph,
                          color: Colors.indigo[400], size: 20),
                      const SizedBox(width: 6),
                      const Text('天天向上：坚持的力量',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '假设初始能力值为 1，每天学习能力提升 r%，不学习衰减 r/3%。\n'
                    '120 天后（一学期），不同学习模式的差距令人惊讶！',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: isDark ? Colors.white60 : Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 模式选择
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(_modes.length, (i) {
              final mode = _modes[i];
              final isActive = _activeModes.contains(i);
              return FilterChip(
                label: Text(mode.name,
                    style: TextStyle(
                        fontSize: 11,
                        color: isActive ? Colors.white : mode.color)),
                selected: isActive,
                selectedColor: mode.color,
                checkmarkColor: Colors.white,
                onSelected: (v) => setState(() {
                  if (v)
                    _activeModes.add(i);
                  else
                    _activeModes.remove(i);
                }),
              );
            }),
          ),
          const SizedBox(height: 8),

          // 天数滑块
          Row(
            children: [
              Text('周期：$_totalDays天', style: const TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _totalDays.toDouble(),
                  min: 30,
                  max: 365,
                  divisions: 67,
                  label: '$_totalDays天',
                  onChanged: (v) => setState(() => _totalDays = v.round()),
                ),
              ),
              // 对数切换
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Log', style: TextStyle(fontSize: 11)),
                  Switch(
                    value: _showLog,
                    onChanged: (v) => setState(() => _showLog = v),
                  ),
                ],
              ),
            ],
          ),

          // 图表
          SizedBox(
            height: 280,
            child: _buildChart(),
          ),
          const SizedBox(height: 12),

          // 终值对比表
          _buildResultTable(),

          const SizedBox(height: 16),

          // 启发文字
          Card(
            color: isDark
                ? Colors.amber.withValues(alpha: 0.15)
                : Colors.amber[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.amber[700], size: 18),
                      const SizedBox(width: 6),
                      Text('学习启示',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.amber[800])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• 坚持每天学习比偶尔突击效果好得多\n'
                    '• 适度休息（5+2模式）比"内卷"更高效\n'
                    '• 哪怕每天只提升 0.5%，120天后能力值也能翻倍\n'
                    '• 关键不是学多久，而是能坚持多久',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final lines = <LineChartBarData>[];

    for (final idx in _activeModes) {
      final mode = _modes[idx];
      final spots = <FlSpot>[];
      final step = max(1, _totalDays ~/ 60);
      for (int d = 0; d <= _totalDays; d += step) {
        double val = _calcAbility(mode, d);
        if (_showLog && val > 0) val = log(val) / ln10 + 1;
        spots.add(FlSpot(d.toDouble(), val));
      }

      lines.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: mode.color,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: mode.color.withValues(alpha: 0.05),
        ),
      ));
    }

    // 添加实际数据线
    if (_hasActualData && _actualData.isNotEmpty) {
      final actualSpots = _showLog
          ? _actualData
              .map((s) => FlSpot(s.x, s.y > 0 ? log(s.y) / ln10 + 1 : 1))
              .toList()
          : _actualData;

      lines.add(LineChartBarData(
        spots: actualSpots,
        isCurved: true,
        color: Colors.amber,
        barWidth: 3,
        dotData: const FlDotData(show: true),
        dashArray: [5, 3],
      ));
    }

    if (lines.isEmpty) {
      return const Center(child: Text('请选择至少一个学习模式'));
    }

    return LineChart(
      LineChartData(
        lineBarsData: lines,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: _showLog ? 0.5 : null,
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: max(1, _totalDays / 6),
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child:
                    Text('${v.toInt()}天', style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text(
                v >= 10 ? '${v.toInt()}' : v.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3))),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final color = s.bar.color ?? Colors.blue;
              return LineTooltipItem(
                '第${s.x.toInt()}天\n能力: ${s.y.toStringAsFixed(2)}',
                TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.bold),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildResultTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏁 终值对比（初始能力=1.0）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ..._modes
                .asMap()
                .entries
                .where((e) => _activeModes.contains(e.key))
                .map((e) {
              final mode = e.value;
              final finalVal = _calcAbility(mode, _totalDays);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: mode.color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(mode.name,
                            style: const TextStyle(fontSize: 12))),
                    Text('${finalVal.toStringAsFixed(2)}×',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: mode.color)),
                    const SizedBox(width: 8),
                    Text('(+${((finalVal - 1) * 100).toStringAsFixed(0)}%)',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              );
            }),
            if (_hasActualData && _actualData.isNotEmpty) ...[
              const Divider(),
              Row(
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: Colors.amber, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('我的实际', style: TextStyle(fontSize: 12))),
                  Text('${_actualData.last.y.toStringAsFixed(2)}×',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.amber)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Tab 2：自定义模拟 ──────────────────────────────────────────

  Widget _buildCustomTab(bool isDark) {
    final customMode = _LearningMode(
      '自定义',
      '自定义模式',
      studyDays: _customStudyDays,
      restDays: 7 - _customStudyDays,
      rate: _customRate,
      color: Colors.teal,
    );

    final standardMode = _modes[1]; // 标准模式作为对比
    final customVal = _calcAbility(customMode, _totalDays);
    final standardVal = _calcAbility(standardMode, _totalDays);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚙️ 自定义学习参数',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 16),

                  // 每周学习天数
                  Row(
                    children: [
                      const SizedBox(
                          width: 80,
                          child: Text('学习天数：', style: TextStyle(fontSize: 13))),
                      Expanded(
                        child: Slider(
                          value: _customStudyDays.toDouble(),
                          min: 1,
                          max: 7,
                          divisions: 6,
                          label: '$_customStudyDays天/周',
                          onChanged: (v) =>
                              setState(() => _customStudyDays = v.round()),
                        ),
                      ),
                      SizedBox(
                          width: 50,
                          child: Text('$_customStudyDays天/周',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold))),
                    ],
                  ),

                  // 每日增长率
                  Row(
                    children: [
                      const SizedBox(
                          width: 80,
                          child: Text('增长率：', style: TextStyle(fontSize: 13))),
                      Expanded(
                        child: Slider(
                          value: _customRate * 100,
                          min: 0.1,
                          max: 5.0,
                          divisions: 49,
                          label: '${(_customRate * 100).toStringAsFixed(1)}%',
                          onChanged: (v) =>
                              setState(() => _customRate = v / 100),
                        ),
                      ),
                      SizedBox(
                          width: 50,
                          child: Text(
                              '${(_customRate * 100).toStringAsFixed(1)}%/天',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold))),
                    ],
                  ),

                  // 模拟天数
                  Row(
                    children: [
                      const SizedBox(
                          width: 80,
                          child: Text('模拟天数：', style: TextStyle(fontSize: 13))),
                      Expanded(
                        child: Slider(
                          value: _totalDays.toDouble(),
                          min: 30,
                          max: 365,
                          divisions: 67,
                          label: '$_totalDays天',
                          onChanged: (v) =>
                              setState(() => _totalDays = v.round()),
                        ),
                      ),
                      SizedBox(
                          width: 50,
                          child: Text('$_totalDays天',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 对比图表
          SizedBox(
            height: 250,
            child: _buildCustomChart(customMode, standardMode),
          ),
          const SizedBox(height: 12),

          // 结果对比
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _buildResultCard(
                              '你的模式', customVal, Colors.teal, isDark)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildResultCard(
                              '标准模式', standardVal, Colors.blue, isDark)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: customVal >= standardVal
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      customVal >= standardVal
                          ? '🎉 你的模式比标准模式强 ${((customVal / standardVal - 1) * 100).toStringAsFixed(0)}%'
                          : '⚠️ 你的模式比标准模式弱 ${((1 - customVal / standardVal) * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: customVal >= standardVal
                              ? Colors.green[700]
                              : Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomChart(_LearningMode custom, _LearningMode standard) {
    final step = max(1, _totalDays ~/ 60);
    final customSpots = <FlSpot>[];
    final standardSpots = <FlSpot>[];

    for (int d = 0; d <= _totalDays; d += step) {
      customSpots.add(FlSpot(d.toDouble(), _calcAbility(custom, d)));
      standardSpots.add(FlSpot(d.toDouble(), _calcAbility(standard, d)));
    }

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: customSpots,
          isCurved: true,
          color: Colors.teal,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: Colors.teal.withValues(alpha: 0.1)),
        ),
        LineChartBarData(
          spots: standardSpots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          dashArray: [5, 3],
        ),
      ],
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          interval: max(1, _totalDays / 6),
          getTitlesWidget: (v, _) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${v.toInt()}天', style: const TextStyle(fontSize: 10)),
          ),
        )),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (v, _) =>
              Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
        )),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3))),
    ));
  }

  Widget _buildResultCard(String title, double val, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 4),
          Text('${val.toStringAsFixed(2)}×',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text('+${((val - 1) * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // ── Tab 3：我的成长 ──────────────────────────────────────────────

  Widget _buildPersonalTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 成长概况卡片
          _buildGrowthSummary(isDark),
          const SizedBox(height: 16),

          // 我的成长曲线
          if (_hasActualData) ...[
            const Text('📈 我的学习轨迹',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            SizedBox(height: 220, child: _buildPersonalChart()),
            const SizedBox(height: 16),
          ],

          // 学习建议
          _buildSuggestions(isDark),

          const SizedBox(height: 16),

          // 成就徽章
          _buildBadges(isDark),
        ],
      ),
    );
  }

  Widget _buildGrowthSummary(bool isDark) {
    final totalDays = _hasActualData && _actualData.isNotEmpty
        ? _actualData.last.x.toInt()
        : 0;
    final abilityMultiplier =
        _hasActualData && _actualData.isNotEmpty ? _actualData.last.y : 1.0;

    // 判断最接近的学习模式
    String bestMatch = '未知';
    if (totalDays > 0) {
      double minDiff = double.infinity;
      for (final mode in _modes) {
        final diff = (_calcAbility(mode, totalDays) - abilityMultiplier).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestMatch = mode.name;
        }
      }
    }

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.indigo, Colors.indigo.withValues(alpha: 0.7)],
          ),
        ),
        child: Column(
          children: [
            const Text('我的学习概况',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem('学习天数', '$totalDays'),
                _summaryItem(
                    '能力倍率', '${abilityMultiplier.toStringAsFixed(2)}×'),
                _summaryItem('学习模式', bestMatch),
              ],
            ),
            if (!_hasActualData) ...[
              const SizedBox(height: 12),
              const Text('开始学习后，这里将显示你的成长数据',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildPersonalChart() {
    if (_actualData.isEmpty) {
      return const Center(child: Text('暂无学习数据'));
    }

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: _actualData,
          isCurved: true,
          color: Colors.amber,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: Colors.amber.withValues(alpha: 0.15)),
        ),
        // 对比标准线
        LineChartBarData(
          spots: List.generate(
            max(1,
                (_actualData.last.x / max(1, _actualData.last.x ~/ 30)).ceil()),
            (i) {
              final d = (i * max(1, _actualData.last.x ~/ 30)).toDouble();
              return FlSpot(d, _calcAbility(_modes[1], d.toInt()));
            },
          ),
          isCurved: true,
          color: Colors.blue.withValues(alpha: 0.4),
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          dashArray: [4, 4],
        ),
      ],
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          getTitlesWidget: (v, _) =>
              Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
        )),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (v, _) =>
              Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
        )),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3))),
    ));
  }

  Widget _buildSuggestions(bool isDark) {
    final suggestions = <Map<String, dynamic>>[];

    if (!_hasActualData || _actualData.isEmpty) {
      suggestions.add({
        'icon': Icons.play_arrow,
        'color': Colors.blue,
        'text': '开始你的第一次学习吧！浏览知识图谱或做章节测验都算学习活动。'
      });
    } else {
      final days = _actualData.last.x.toInt();
      final val = _actualData.last.y;

      if (days < 7) {
        suggestions.add({
          'icon': Icons.emoji_events,
          'color': Colors.amber,
          'text': '学习刚起步，坚持7天形成习惯！'
        });
      } else if (days < 30) {
        suggestions.add({
          'icon': Icons.trending_up,
          'color': Colors.green,
          'text': '已坚持${days}天，继续保持！30天后效果将非常明显。'
        });
      } else {
        suggestions.add({
          'icon': Icons.stars,
          'color': Colors.purple,
          'text':
              '太棒了！已坚持${days}天，能力提升了${((val - 1) * 100).toStringAsFixed(0)}%！'
        });
      }

      final standardVal = _calcAbility(_modes[1], days);
      if (val > standardVal) {
        suggestions.add({
          'icon': Icons.rocket_launch,
          'color': Colors.deepPurple,
          'text': '你的成长速度超过标准模式！继续保持这个节奏！'
        });
      } else {
        suggestions.add({
          'icon': Icons.tips_and_updates,
          'color': Colors.orange,
          'text': '试试每天多学一点，哪怕 10 分钟也能显著提升成长曲线。'
        });
      }
    }

    suggestions.add({
      'icon': Icons.book,
      'color': Colors.teal,
      'text': '推荐：每天完成一个深度实践节，测验做错的题记入错题本复习。'
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💡 学习建议',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...suggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(s['icon'] as IconData,
                          size: 18, color: s['color'] as Color),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(s['text'] as String,
                              style:
                                  const TextStyle(fontSize: 12, height: 1.5))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildBadges(bool isDark) {
    final days = _hasActualData && _actualData.isNotEmpty
        ? _actualData.last.x.toInt()
        : 0;

    final badges = <Map<String, dynamic>>[
      {
        'icon': Icons.looks_one,
        'name': '初学者',
        'desc': '完成首次学习',
        'unlocked': days >= 1
      },
      {
        'icon': Icons.calendar_today,
        'name': '坚持一周',
        'desc': '连续学习7天',
        'unlocked': days >= 7
      },
      {
        'icon': Icons.event_available,
        'name': '月度之星',
        'desc': '坚持学习30天',
        'unlocked': days >= 30
      },
      {
        'icon': Icons.military_tech,
        'name': '学霸',
        'desc': '坚持学习60天',
        'unlocked': days >= 60
      },
      {
        'icon': Icons.diamond,
        'name': '钻石学员',
        'desc': '坚持学习100天',
        'unlocked': days >= 100
      },
      {
        'icon': Icons.auto_awesome,
        'name': '传说',
        'desc': '坚持学习一整学期',
        'unlocked': days >= 120
      },
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏅 学习成就',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: badges.map((b) {
                final unlocked = b['unlocked'] as bool;
                return Container(
                  width: 90,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: unlocked
                        ? Colors.amber.withValues(alpha: 0.15)
                        : (isDark ? Colors.grey[800] : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(10),
                    border: unlocked
                        ? Border.all(color: Colors.amber.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Column(
                    children: [
                      Icon(b['icon'] as IconData,
                          size: 24,
                          color: unlocked ? Colors.amber[700] : Colors.grey),
                      const SizedBox(height: 4),
                      Text(b['name'] as String,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color:
                                  unlocked ? Colors.amber[800] : Colors.grey)),
                      Text(b['desc'] as String,
                          style: TextStyle(
                              fontSize: 9,
                              color: unlocked
                                  ? Colors.amber[600]
                                  : Colors.grey[500]),
                          textAlign: TextAlign.center),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 数据模型 ──────────────────────────────────────────────────────

class _LearningMode {
  final String name;
  final String desc;
  final int studyDays;
  final int restDays;
  final double rate;
  final Color color;
  const _LearningMode(
    this.name,
    this.desc, {
    required this.studyDays,
    required this.restDays,
    required this.rate,
    required this.color,
  });
}
