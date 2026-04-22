import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../data/local/achievement_dao.dart';
import '../achievement_shared.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Tab 4 — 计算过程（大纲目标 + 考核结构 + 公式 + 班级概览 + 学生表 + 分布图）
// ══════════════════════════════════════════════════════════════════════════════

class CalculationProcessTab extends StatefulWidget {
  final AchievementDao achievementDao;

  const CalculationProcessTab({super.key, required this.achievementDao});

  @override
  State<CalculationProcessTab> createState() => _CalculationProcessTabState();
}

class _CalculationProcessTabState extends State<CalculationProcessTab> {
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _scores = [];
  int? _selectedBatchId;
  bool _loading = true;
  List<double> _classAvgAchievements = [0, 0, 0, 0];
  double _weightedAchievement = 0;
  Map<String, dynamic>? _surveySummary;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      // 加载问卷满意度数据
      Map<String, dynamic>? surveyData;
      try {
        surveyData =
            await widget.achievementDao.getSurveySatisfactionSummary();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _batches = batches;
          _surveySummary = surveyData;
          _loading = false;
          if (_batches.isNotEmpty && _selectedBatchId == null) {
            _selectedBatchId = _batches.first['id'] as int;
            _loadScoresAndCalc();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadScoresAndCalc() async {
    if (_selectedBatchId == null) return;
    setState(() => _loading = true);
    try {
      final scores = await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      if (scores.isNotEmpty) {
        final avgs = List<double>.filled(4, 0);
        for (final s in scores) {
          for (int i = 0; i < 4; i++) {
            avgs[i] += (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
          }
        }
        for (int i = 0; i < 4; i++) avgs[i] /= scores.length;
        double weighted = 0;
        for (int i = 0; i < 4; i++) weighted += avgs[i] * kDefaultWeights[i];
        _classAvgAchievements = avgs;
        _weightedAchievement = weighted;
      }
      if (mounted) setState(() { _scores = scores; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _batches.isEmpty) return const Center(child: CircularProgressIndicator());
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildBatchSelector(primary),
        const SizedBox(height: 16),
        _buildSyllabusObjectives(primary),
        const SizedBox(height: 16),
        _buildAssessmentStructure(primary),
        const SizedBox(height: 16),
        _buildFormula(primary),
        const SizedBox(height: 16),
        if (_scores.isNotEmpty) ...[
          _buildClassOverview(primary),
          const SizedBox(height: 16),
          _buildStudentTable(primary),
          const SizedBox(height: 16),
          _buildObjectiveCharts(primary),
          const SizedBox(height: 16),
        ],
        // 七、问卷满意度调查
        _buildSurveySatisfaction(primary),
        if (_scores.isEmpty && !_loading)
          Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Column(children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('暂无成绩数据，请先在"成绩管理"中录入', style: TextStyle(color: Colors.grey)),
          ]))),
      ]),
    );
  }

  Widget _buildBatchSelector(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: primary.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(child: DropdownButton<int>(
        isExpanded: true, value: _selectedBatchId, hint: const Text('选择批次'),
        items: _batches.map((b) => DropdownMenuItem<int>(value: b['id'] as int, child: Text(b['batch_name'] ?? '未命名'))).toList(),
        onChanged: (v) { setState(() { _selectedBatchId = v; _scores = []; }); _loadScoresAndCalc(); },
      )),
    );
  }

  Widget _buildSyllabusObjectives(Color primary) {
    const objectives = [
      {'id': '课程目标1', 'weight': 0.15, 'req': '毕业要求 1.4', 'desc': '掌握移动应用开发技术体系（原生/混合/跨平台）及主流平台特性，理解技术选型逻辑', 'ch': '第1章 + 第2章'},
      {'id': '课程目标2', 'weight': 0.25, 'req': '毕业要求 3.2', 'desc': '运用跨平台开发框架及小程序技术，结合AI编程工具与后端API交互，设计实现跨平台应用', 'ch': '第3章 + 第4章'},
      {'id': '课程目标3', 'weight': 0.30, 'req': '毕业要求 4.2', 'desc': '调研对比多端开发方案，分析不同技术栈在跨设备适配场景中的优劣，具备技术方案评估与选型能力', 'ch': '第5章'},
      {'id': '课程目标4', 'weight': 0.30, 'req': '毕业要求 5.1', 'desc': '遵循软件工程规范，使用现代开发工具（含AI编程工具、Git版本控制）完成应用测试与优化', 'ch': '第6章'},
    ];
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.menu_book, color: primary, size: 22), const SizedBox(width: 8), const Text('一、大纲课程目标', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
      const Divider(height: 20),
      ...objectives.asMap().entries.map((e) {
        final i = e.key; final o = e.value;
        return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 70, padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
            decoration: BoxDecoration(color: kObjectiveColors[i].withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Column(children: [
              Text(o['id'] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kObjectiveColors[i])),
              Text('权重 ${((o['weight'] as double) * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o['desc'] as String, style: const TextStyle(fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 2),
            Text('${o['req']} · ${o['ch']}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ])),
        ]));
      }),
    ])));
  }

  Widget _buildAssessmentStructure(Color primary) {
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.assignment, color: primary, size: 22), const SizedBox(width: 8), const Text('二、考核方式与满分分配', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
      const Divider(height: 20),
      Row(children: [_wChip('平时成绩', '20%', Colors.blue), const SizedBox(width: 8), _wChip('实验成绩', '30%', Colors.green), const SizedBox(width: 8), _wChip('期末成绩', '50%', Colors.orange)]),
      const SizedBox(height: 16),
      Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
        child: Table(border: TableBorder.symmetric(inside: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.5), 2: FlexColumnWidth(1.5), 3: FlexColumnWidth(1.5)},
          children: [
            _tRow(['课程目标', '平时(20%)', '实验(30%)', '期末(50%)'], h: true, p: primary),
            _tRow(['目标1', '15分', '15分', '15分']), _tRow(['目标2', '25分', '25分', '25分']),
            _tRow(['目标3', '30分', '30分', '30分']), _tRow(['目标4', '30分', '30分', '30分']),
            _tRow(['合计', '100分', '100分', '100分'], h: true, p: primary),
          ])),
    ])));
  }

  Widget _wChip(String label, String value, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(children: [Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), const SizedBox(height: 2), Text(label, style: TextStyle(fontSize: 11, color: color))]),
  ));

  TableRow _tRow(List<String> c, {bool h = false, Color? p}) => TableRow(
    decoration: h ? BoxDecoration(color: (p ?? Colors.grey).withValues(alpha: 0.06)) : null,
    children: c.map((t) => Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: h ? FontWeight.bold : FontWeight.normal)))).toList(),
  );

  Widget _buildFormula(Color primary) {
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.functions, color: primary, size: 22), const SizedBox(width: 8), const Text('三、达成度计算公式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
      const Divider(height: 20),
      _fItem('Step 1', '目标i综合得分', '= 平时目标i分×0.20 + 实验目标i分×0.30 + 期末目标i分×0.50'),
      _fItem('Step 2', '目标i达成度', '= 目标i综合得分 / 目标i满分\n  满分：目标1=15, 目标2=25, 目标3=30, 目标4=30'),
      _fItem('Step 3', '班级平均达成度', '= Σ(所有学生目标i达成度) / 学生人数'),
      _fItem('Step 4', '加权总达成度', '= 目标1×0.15 + 目标2×0.25 + 目标3×0.30 + 目标4×0.30'),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withValues(alpha: 0.15))),
        child: Row(children: [const Icon(Icons.info_outline, size: 16, color: Colors.blue), const SizedBox(width: 8),
          Expanded(child: Text('等级标准：≥85% 优秀 · ≥70% 良好 · ≥60% 中等 · <60% 未达成', style: TextStyle(fontSize: 11, color: Colors.blue[700])))])),
    ])));
  }

  Widget _fItem(String step, String title, String formula) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(step, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo))),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(formula, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontFamily: 'monospace')),
    ])),
  ]));

  Widget _buildClassOverview(Color primary) {
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.bar_chart, color: primary, size: 22), const SizedBox(width: 8), Text('四、班级达成度概览（${_scores.length}人）', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
      const Divider(height: 20),
      ...List.generate(4, (i) {
        final val = _classAvgAchievements[i];
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
          SizedBox(width: 65, child: Text('目标${i + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kObjectiveColors[i]))),
          Text('${(kDefaultWeights[i] * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(child: Stack(children: [
            Container(height: 22, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4))),
            FractionallySizedBox(widthFactor: val.clamp(0.0, 1.0), child: Container(height: 22, decoration: BoxDecoration(color: kObjectiveColors[i].withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)))),
          ])),
          const SizedBox(width: 8),
          SizedBox(width: 50, child: Text('${(val * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kObjectiveColors[i]), textAlign: TextAlign.right)),
        ]));
      }),
      const Divider(),
      Row(children: [
        const SizedBox(width: 65, child: Text('总达成度', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        const SizedBox(width: 34),
        Expanded(child: Stack(children: [
          Container(height: 26, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5))),
          FractionallySizedBox(widthFactor: _weightedAchievement.clamp(0.0, 1.0), child: Container(height: 26, decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primary.withValues(alpha: 0.8), primary.withValues(alpha: 0.5)]), borderRadius: BorderRadius.circular(5)))),
        ])),
        const SizedBox(width: 8),
        SizedBox(width: 50, child: Text('${(_weightedAchievement * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary), textAlign: TextAlign.right)),
      ]),
      const SizedBox(height: 10),
      Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: achievementLevelColor(_weightedAchievement).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
        child: Text('达成等级：${achievementLevel(_weightedAchievement)}', style: TextStyle(fontWeight: FontWeight.bold, color: achievementLevelColor(_weightedAchievement))))),
    ])));
  }

  Widget _buildStudentTable(Color primary) {
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.people, color: primary, size: 22), const SizedBox(width: 8), const Text('五、学生个体达成度', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
      const Divider(height: 20),
      Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), decoration: BoxDecoration(color: primary.withValues(alpha: 0.06), borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
        child: const Row(children: [
          SizedBox(width: 70, child: Text('学号', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 50, child: Text('姓名', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(child: Text('目标1', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(child: Text('目标2', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(child: Text('目标3', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(child: Text('目标4', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 45, child: Text('总分', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        ])),
      ...(_scores.length > 30 ? _scores.sublist(0, 30) : _scores).asMap().entries.map((entry) {
        final i = entry.key; final s = entry.value;
        final total = (s['total_score'] as num?)?.toDouble() ?? 0;
        return Container(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(color: i.isEven ? Colors.transparent : Colors.grey.withValues(alpha: 0.03), border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.08)))),
          child: Row(children: [
            SizedBox(width: 70, child: Text(s['student_id']?.toString() ?? '', style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))),
            SizedBox(width: 50, child: Text(s['student_name']?.toString() ?? '', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
            ...List.generate(4, (j) {
              final ach = (s['obj${j + 1}_achievement'] as num?)?.toDouble() ?? 0;
              return Expanded(child: Text((ach * 100).toStringAsFixed(1), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: achievementLevelColor(ach))));
            }),
            SizedBox(width: 45, child: Text(total.toStringAsFixed(1), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500))),
          ]));
      }),
      if (_scores.length > 30) Padding(padding: const EdgeInsets.only(top: 8), child: Text('... 仅显示前30条，共${_scores.length}条', style: const TextStyle(fontSize: 11, color: Colors.grey))),
    ])));
  }

  Widget _buildObjectiveCharts(Color primary) {
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.insert_chart, color: primary, size: 22), const SizedBox(width: 8), const Text('六、各目标达成度分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
      const Divider(height: 20),
      ...List.generate(4, (objIdx) => _buildSingleObjChart(objIdx)),
    ])));
  }

  Widget _buildSingleObjChart(int objIdx) {
    final color = kObjectiveColors[objIdx];
    final key = 'obj${objIdx + 1}_achievement';
    final fullMark = [15.0, 25.0, 30.0, 30.0][objIdx];
    int cLow = 0, cMid = 0, cGood = 0, cExcel = 0;
    for (final s in _scores) {
      final v = (s[key] as num?)?.toDouble() ?? 0;
      if (v >= 0.85) cExcel++; else if (v >= 0.70) cGood++; else if (v >= 0.60) cMid++; else cLow++;
    }
    final total = _scores.length;
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text('课程目标${objIdx + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(width: 8),
        Text('满分${fullMark.toInt()}分 · 权重${(kDefaultWeights[objIdx] * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const Spacer(),
        Text('均值 ${(_classAvgAchievements[objIdx] * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _distBar('未达成', cLow, total, Colors.red), const SizedBox(width: 4),
        _distBar('中等', cMid, total, Colors.orange), const SizedBox(width: 4),
        _distBar('良好', cGood, total, Colors.blue), const SizedBox(width: 4),
        _distBar('优秀', cExcel, total, Colors.green),
      ]),
    ]));
  }

  Widget _distBar(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Expanded(flex: max(1, (pct * 100).round()), child: Column(children: [
      Container(height: 20, decoration: BoxDecoration(color: color.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
        child: Center(child: Text(count > 0 ? '$count' : '', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)))),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 8, color: color)),
    ]));
  }

  /// 七、问卷满意度调查
  Widget _buildSurveySatisfaction(Color primary) {
    final hasSurvey = _surveySummary?['hasSurveyData'] == true;
    final totalResponses = _surveySummary?['totalResponses'] as int? ?? 0;
    final overallSat =
        (_surveySummary?['overallSatisfaction'] as double?) ?? 0.0;
    final questionStats = (_surveySummary?['questionStats']
            as List<Map<String, dynamic>>?) ??
        [];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.poll, color: primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('七、课程满意度调查',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (hasSurvey)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$totalResponses份回收',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.green)),
                ),
            ]),
            const Divider(height: 20),
            if (!hasSurvey) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('暂无问卷调查数据。请在「管理 > 问卷管理」中创建并发布课程满意度调查问卷。',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange)),
                  ),
                ]),
              ),
            ] else ...[
              // 满意度概览
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: achievementLevelColor(overallSat)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(children: [
                      Text(
                        '${(overallSat * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: achievementLevelColor(overallSat),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('综合满意度',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  achievementLevelColor(overallSat))),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(children: [
                      Text('$totalResponses',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: primary)),
                      const SizedBox(height: 2),
                      Text('有效回收',
                          style: TextStyle(
                              fontSize: 11, color: primary)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // 逐题统计
              ...questionStats.take(6).map((qs) {
                final type = qs['type'] as String;
                final question = qs['question'] as String? ?? '';
                if (type == 'single_choice') {
                  final counts =
                      qs['counts'] as Map<String, int>? ?? {};
                  final total = (qs['total'] as int?) ?? 1;
                  return _buildSurveyQuestion(
                      question, counts, total);
                } else if (type == 'rating') {
                  final avg = (qs['average'] as double?) ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: Text(question,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      Row(children: List.generate(5, (i) {
                        return Icon(
                          i < avg.round()
                              ? Icons.star
                              : Icons.star_border,
                          size: 14,
                          color: Colors.amber,
                        );
                      })),
                      const SizedBox(width: 4),
                      Text('${avg.toStringAsFixed(1)}/5.0',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ]),
                  );
                } else if (type == 'text') {
                  final answers =
                      qs['answers'] as List<String>? ?? [];
                  if (answers.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(question,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        ...answers.take(3).map((a) => Padding(
                              padding:
                                  const EdgeInsets.only(left: 8, bottom: 2),
                              child: Text('• $a',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey)),
                            )),
                        if (answers.length > 3)
                          Text('  ... 共${answers.length}条',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSurveyQuestion(
      String question, Map<String, int> counts, int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          ...counts.entries.map((entry) {
            final pct =
                total > 0 ? entry.value / total : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                SizedBox(
                    width: 65,
                    child: Text(entry.key,
                        style: const TextStyle(fontSize: 10))),
                Expanded(
                  child: Stack(children: [
                    Container(
                        height: 14,
                        decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3))),
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(3))),
                    ),
                  ]),
                ),
                const SizedBox(width: 6),
                SizedBox(
                    width: 55,
                    child: Text(
                        '${entry.value}人 (${(pct * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 9),
                        textAlign: TextAlign.right)),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 5 — 持续改进（基于达成度分析的教学改进建议）
// ══════════════════════════════════════════════════════════════════════════════

class ContinuousImprovementTab extends StatefulWidget {
  final AchievementDao achievementDao;

  const ContinuousImprovementTab({super.key, required this.achievementDao});

  @override
  State<ContinuousImprovementTab> createState() =>
      _ContinuousImprovementTabState();
}

class _ContinuousImprovementTabState
    extends State<ContinuousImprovementTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  bool _loading = true;
  bool _analyzing = false;
  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _surveySummary;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      if (mounted) {
        setState(() {
          _batches = batches;
          _loading = false;
          if (_batches.isNotEmpty && _selectedBatchId == null) {
            _selectedBatchId = _batches.first['id'] as int;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _analyzeAndSuggest() async {
    if (_selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择批次')),
      );
      return;
    }

    setState(() => _analyzing = true);

    try {
      final suggestions = await widget.achievementDao
          .generateImprovementSuggestions(_selectedBatchId!);
      Map<String, dynamic>? surveyData;
      try {
        surveyData =
            await widget.achievementDao.getSurveySatisfactionSummary();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _surveySummary = surveyData;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _analyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('分析失败：$e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 批次选择
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _selectedBatchId,
                hint: const Text('选择批次'),
                items: _batches
                    .map((b) => DropdownMenuItem<int>(
                          value: b['id'] as int,
                          child: Text(b['batch_name'] ?? '未命名'),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedBatchId = v;
                    _suggestions = [];
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 分析按钮
          Center(
            child: FilledButton.icon(
              onPressed: _analyzing ? null : _analyzeAndSuggest,
              icon: _analyzing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_fix_high, size: 18),
              label: Text(_analyzing ? '分析中...' : '分析达成度 & 生成改进建议'),
            ),
          ),
          const SizedBox(height: 16),

          if (_analyzing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在分析达成度数据并生成改进建议...',
                      style: TextStyle(color: Colors.grey)),
                ]),
              ),
            ),

          if (_suggestions.isNotEmpty && !_analyzing) ...[
            // 一、本轮教学改进措施执行情况
            _buildPreviousImprovementCard(primary),
            const SizedBox(height: 16),

            // 二、各目标达成情况与改进建议
            ..._suggestions.where((s) => s['objectiveIndex'] != -1).map(
                (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child:
                        _buildObjectiveImprovementCard(s, primary))),

            // 三、整体教学改进建议
            ..._suggestions
                .where((s) => s['objectiveIndex'] == -1)
                .map((s) => _buildOverallImprovementCard(s, primary)),
            const SizedBox(height: 16),

            // 四、满意度反馈
            _buildSurveyFeedbackCard(primary),
          ],

          if (_suggestions.isEmpty && !_analyzing)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(children: [
                  Icon(Icons.build_outlined,
                      size: 80,
                      color: Colors.grey.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  const Text('选择批次后点击"分析达成度"查看改进建议',
                      style:
                          TextStyle(color: Colors.grey, fontSize: 14)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviousImprovementCard(Color primary) {
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.history, color: primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('一、上轮教学改进措施执行情况',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
            const Divider(height: 20),
            _previousItem(
                '1',
                '加大运用移动应用开发技术体系分析实际应用问题的题目训练',
                '已执行。平时作业中增设了技术选型分析题，学生对技术体系理解有明显提升。',
                Colors.green),
            _previousItem(
                '2',
                '增加章节结束后知识图谱创建训练',
                '已执行。在每章布置知识图谱绘制作业，帮助学生梳理知识结构。',
                Colors.green),
            _previousItem(
                '3',
                '优化期末项目考核的场景设计',
                '已执行。降低跨设备适配模块分值占比，增加AI工具辅助开发评分维度。',
                Colors.green),
            _previousItem(
                '4',
                '对过程性考核中达标偏低的同学制定帮扶计划',
                '部分执行。已组织3次技术专题工作坊，但个别化辅导仍需加强。',
                Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _previousItem(
      String num, String title, String status, Color statusColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(num,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(status,
                    style: TextStyle(
                        fontSize: 11, color: statusColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectiveImprovementCard(
      Map<String, dynamic> suggestion, Color primary) {
    final objIdx = suggestion['objectiveIndex'] as int;
    final objName = suggestion['objectiveName'] as String;
    final ach = (suggestion['achievement'] as double?) ?? 0;
    final level = suggestion['level'] as String? ?? '';
    final lowCount = suggestion['lowStudentCount'] as int? ?? 0;
    final totalStudents = suggestion['totalStudents'] as int? ?? 0;
    final chapters = suggestion['chapters'] as String? ?? '';
    final topics =
        (suggestion['topics'] as List<String>?) ?? [];
    final actions =
        (suggestion['actions'] as List<String>?) ?? [];
    final color = kObjectiveColors[objIdx.clamp(0, 3)];

    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 目标名称 + 达成度
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(objName,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
              const SizedBox(width: 8),
              Text('达成度 ${(ach * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: achievementLevelColor(ach))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: achievementLevelColor(ach)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(level,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: achievementLevelColor(ach))),
              ),
            ]),
            const SizedBox(height: 8),

            // 现状分析
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关联内容: $chapters',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  Text('核心知识点: ${topics.join("、")}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  if (lowCount > 0 && totalStudents > 0)
                    Text(
                        '未达标学生: $lowCount人（占$totalStudents人的${(lowCount / totalStudents * 100).toStringAsFixed(0)}%）',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.red)),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 改进建议
            const Text('改进措施：',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...actions.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text('${entry.key + 1}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: color)),
                      ),
                    ),
                    Expanded(
                      child: Text(entry.value,
                          style: const TextStyle(
                              fontSize: 12, height: 1.4)),
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

  Widget _buildOverallImprovementCard(
      Map<String, dynamic> suggestion, Color primary) {
    final ach = (suggestion['achievement'] as double?) ?? 0;
    final actions =
        (suggestion['actions'] as List<String>?) ?? [];
    final graphNodes =
        suggestion['graphNodeCount'] as int? ?? 0;
    final quizCount =
        suggestion['quizQuestionCount'] as int? ?? 0;

    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.lightbulb_outline,
                  color: primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('三、整体教学改进建议',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
            const Divider(height: 20),

            // 现状概览
            Row(children: [
              _statChip('加权达成度',
                  '${(ach * 100).toStringAsFixed(1)}%', primary),
              const SizedBox(width: 8),
              _statChip('图谱节点', '$graphNodes个', Colors.teal),
              const SizedBox(width: 8),
              _statChip('测验题库', '$quizCount道', Colors.orange),
            ]),
            const SizedBox(height: 12),

            // 建议列表
            ...actions.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_forward_ios,
                          size: 12, color: primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(entry.value,
                            style: const TextStyle(
                                fontSize: 12, height: 1.4)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: color.withValues(alpha: 0.15)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: color)),
        ]),
      ),
    );
  }

  Widget _buildSurveyFeedbackCard(Color primary) {
    final hasSurvey = _surveySummary?['hasSurveyData'] == true;
    final overallSat =
        (_surveySummary?['overallSatisfaction'] as double?) ?? 0.0;
    final totalResponses =
        _surveySummary?['totalResponses'] as int? ?? 0;
    final questionStats = (_surveySummary?['questionStats']
            as List<Map<String, dynamic>>?) ??
        [];

    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.feedback_outlined,
                  color: primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('四、课程满意度调查反馈',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
            const Divider(height: 20),
            if (!hasSurvey) ...[
              const Text('暂无满意度调查数据，建议在下学期增加课程满意度调查。',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey)),
            ] else ...[
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: achievementLevelColor(overallSat)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(children: [
                      Text(
                          '${(overallSat * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: achievementLevelColor(
                                  overallSat))),
                      const Text('综合满意度',
                          style: TextStyle(fontSize: 11)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(children: [
                      Text('$totalResponses',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: primary)),
                      const Text('有效回收数',
                          style: TextStyle(fontSize: 11)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // 学生建议汇总
              ..._buildTextSuggestions(questionStats),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTextSuggestions(
      List<Map<String, dynamic>> questionStats) {
    final textQuestions =
        questionStats.where((q) => q['type'] == 'text').toList();
    if (textQuestions.isEmpty) return [];

    final widgets = <Widget>[
      const Text('学生改进建议汇总：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
    ];

    for (final q in textQuestions) {
      final answers = q['answers'] as List<String>? ?? [];
      for (final a in answers.take(5)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(color: Colors.grey)),
              Expanded(
                child: Text(a,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ),
            ],
          ),
        ));
      }
    }

    return widgets;
  }
}
