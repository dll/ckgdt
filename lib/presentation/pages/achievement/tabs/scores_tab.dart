import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/material.dart';
import '../../../../data/local/achievement_dao.dart';
import '../../../../data/local/database_helper.dart';
import '../../../../data/local/score_audit_dao.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/achievement/achievement_excel_service.dart';
import '../../../../services/output_path_service.dart';
import '../../../../core/error_handler.dart';
import '../achievement_shared.dart';
import '../achievement_config.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2 — 成绩管理（录入/自动计算/批量）
// ══════════════════════════════════════════════════════════════════════════════

class ScoreManagementTab extends StatefulWidget {
  final AuthService authService;
  final AchievementDao achievementDao;
  final ValueNotifier<int>? dataRevision;

  const ScoreManagementTab({
    required this.authService,
    required this.achievementDao,
    this.dataRevision,
  });

  @override
  State<ScoreManagementTab> createState() => _ScoreManagementTabState();
}

class _ScoreManagementTabState extends State<ScoreManagementTab>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  bool _loadingBatches = true;
  bool _generating = false;
  bool _loadingComponents = false;
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _ps = [], _es = [], _xs = [], _agg = [];
  List<String> _activeEnvs = ['pingshi', 'experiment', 'exam'];
  List<int> _activeObjectiveIndexes = [0, 1, 2, 3];
  ScoreSort _sort = ScoreSort.idAsc;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadBatches();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _setActiveEnvs(List<String> envs) {
    final next = envs.isEmpty ? ['exam'] : envs;
    if (_activeEnvs.length == next.length &&
        List.generate(next.length, (i) => _activeEnvs[i] == next[i])
            .every((v) => v)) {
      return;
    }
    _tabCtrl.dispose();
    _activeEnvs = next;
    _tabCtrl = TabController(length: _activeEnvs.length, vsync: this);
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      if (mounted) {
        setState(() {
          _batches = batches;
          _loadingBatches = false;
          if (_batches.isNotEmpty && _selectedBatchId == null) {
            _selectedBatchId = _batches.first['id'] as int;
            _loadComponentScores();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  Future<void> _showAddScoreDialog({Map<String, dynamic>? existing}) async {
    if (_selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择批次')),
      );
      return;
    }

    final isEdit = existing != null;
    final fullMarks = await widget.achievementDao
        .resolveObjectiveFullMarks(_selectedBatchId!);
    final objectiveWeights =
        await widget.achievementDao.resolveObjectiveWeights(_selectedBatchId!);
    final activeObjectives = [
      for (var i = 0; i < 4; i++)
        if ((i < fullMarks.length && fullMarks[i] > 0) ||
            (i < objectiveWeights.length && objectiveWeights[i] > 0))
          i
    ];
    if (activeObjectives.isEmpty) activeObjectives.addAll([0, 1, 2, 3]);
    final studentIdCtrl = TextEditingController(
        text: isEdit ? (existing['student_id'] ?? '').toString() : '');
    final studentNameCtrl = TextEditingController(
        text: isEdit ? (existing['student_name'] ?? '').toString() : '');
    final objectiveCtrls = List.generate(
      4,
      (i) => TextEditingController(
        text: isEdit
            ? ((existing['obj${i + 1}_score'] ?? 0).toString())
            : (fullMarks[i] > 0
                ? (fullMarks[i] * 0.8).toStringAsFixed(1)
                : '0'),
      ),
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? '编辑学生成绩' : '添加学生成绩'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: studentIdCtrl,
                decoration: const InputDecoration(
                  labelText: '学号',
                  hintText: '如：2022001',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: studentNameCtrl,
                decoration: const InputDecoration(
                  labelText: '姓名',
                  hintText: '如：姓名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              for (final i in activeObjectives) ...[
                TextField(
                  controller: objectiveCtrls[i],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        '目标${i + 1}（满分${fullMarks[i].toStringAsFixed(0)}）',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (studentIdCtrl.text.trim().isEmpty ||
                  studentNameCtrl.text.trim().isEmpty) {
                return;
              }
              final values = List<double>.generate(4, (i) {
                if (!activeObjectives.contains(i)) return 0;
                return double.tryParse(objectiveCtrls[i].text) ?? 0;
              });
              final total = List<double>.generate(
                4,
                (i) =>
                    values[i] *
                    (i < objectiveWeights.length ? objectiveWeights[i] : 0),
              ).fold<double>(0, (a, b) => a + b);

              if (isEdit) {
                await widget.achievementDao.updateScore(existing['id'] as int, {
                  'student_id': studentIdCtrl.text.trim(),
                  'student_name': studentNameCtrl.text.trim(),
                  for (var i = 0; i < 4; i++) ...{
                    'obj${i + 1}_score': values[i],
                    'obj${i + 1}_achievement': fullMarks[i] > 0
                        ? (values[i] / fullMarks[i]).clamp(0.0, 1.0)
                        : 0,
                  },
                  'total_score': total,
                });
              } else {
                await widget.achievementDao.addScore(
                  batchId: _selectedBatchId!,
                  studentId: studentIdCtrl.text.trim(),
                  studentName: studentNameCtrl.text.trim(),
                  objective1Score: values[0],
                  objective2Score: values[1],
                  objective3Score: values[2],
                  objective4Score: values[3],
                  totalScore: total,
                );
              }
              // 审计：达成度成绩录入/编辑
              try {
                await ScoreAuditDao.instance.logChange(
                  tableName: 'achievement_scores',
                  rowId: _selectedBatchId!,
                  field: 'total/${studentIdCtrl.text.trim()}',
                  newValue: total.toStringAsFixed(2),
                  scorerId: AuthService().getCurrentUserId() ?? '',
                  scorerName: AuthService().currentUser?.realName,
                  op: isEdit ? 'update' : 'create',
                );
              } catch (e, st) {
                swallowDebug(e, tag: 'ScoresTab.audit', stack: st);
              }
              // 录入/编辑后重算批次达成度，保持详情/报告同步
              await widget.achievementDao
                  .recalculateAndSaveBatch(_selectedBatchId!);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadComponentScores();
            },
            child: Text(isEdit ? '保存' : '添加'),
          ),
        ],
      ),
    ).then((_) {
      for (final c in [
        studentIdCtrl,
        studentNameCtrl,
        ...objectiveCtrls,
      ]) {
        c.dispose();
      }
    });
  }

  /// 下载成绩导入模板（含大纲驱动的目标拆分表头），可预填当前批次学生名单。
  Future<void> _downloadTemplate() async {
    try {
      final students = _selectedBatchId != null
          ? await widget.achievementDao.getScoresByBatch(_selectedBatchId!)
          : <Map<String, dynamic>>[];
      // 从当前批次获取课程名，加载对应课程目标配置
      String courseName = '移动应用开发';
      if (_selectedBatchId != null) {
        final batch = _batches.firstWhere(
          (b) => b['id'] == _selectedBatchId,
          orElse: () => {},
        );
        courseName = batch['course_name']?.toString() ?? courseName;
      }
      final cfgRows =
          await widget.achievementDao.getCourseObjectives(courseName);
      final cfg = cfgRows.isNotEmpty
          ? AchievementConfig.fromObjectiveRows(cfgRows)
          : AchievementConfig.defaults;
      final bytes = AchievementExcelService.instance.buildGradeTemplate(
          students: students, config: cfg, objectiveRows: cfgRows);
      if (bytes.isEmpty) throw StateError('模板生成失败');
      final dir = await OutputPathService.getOutputDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .substring(0, 19);
      final file = File('${dir.path}/成绩导入模板_$ts.xlsx');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板已生成：${file.path}'),
            action: SnackBarAction(
                label: '打开', onPressed: () => OpenFilex.open(file.path)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ScoresTab.downloadTemplate', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('模板下载失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 导入课程成绩模板 Excel（平时/实验/期末三明细表）到当前批次。
  Future<void> _importGradesExcel() async {
    if (_selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择批次')),
      );
      return;
    }
    final svc = AchievementExcelService.instance;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (f.bytes == null) throw StateError('无法读取文件内容');
      setState(() => _generating = true);

      String courseName = '移动应用开发';
      final batch = _batches.firstWhere(
        (b) => b['id'] == _selectedBatchId,
        orElse: () => {},
      );
      courseName = batch['course_name']?.toString() ?? courseName;
      final objectiveRows =
          await widget.achievementDao.getCourseObjectives(courseName);

      final dynamicGrades = svc.parseDynamicGradeTemplate(
        f.bytes!,
        objectiveRows: objectiveRows,
      );
      if (dynamicGrades.isNotEmpty) {
        await widget.achievementDao.clearPingshiScores(_selectedBatchId!);
        await widget.achievementDao.clearExperimentScores(_selectedBatchId!);
        await widget.achievementDao.clearExamScores(_selectedBatchId!);
        await widget.achievementDao.clearScores(_selectedBatchId!);
        final count =
            await svc.importToDatabase(_selectedBatchId!, dynamicGrades);
        await widget.achievementDao.recalculateAndSaveBatch(_selectedBatchId!);
        _loadComponentScores();
        widget.dataRevision?.value++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('导入成功：$count 名学生（按大纲动态考核项合成达成度）'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      final components = svc.parseComponentSheets(f.bytes!);
      final total = (components['pingshi']?.length ?? 0) +
          (components['experiment']?.length ?? 0) +
          (components['exam']?.length ?? 0);
      if (total == 0) {
        throw StateError('未解析到成绩明细表，请确认包含平时、实验或考核成绩 sheet');
      }
      // 校验：对比当前批次学生名单、查异常分值/重复
      final roster =
          await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      final report = svc.validateComponents(components, roster: roster);
      if (!mounted) return;
      setState(() => _generating = false);
      final confirmed = await _showImportConfirm(components, report);
      if (confirmed != true) return;
      if (!mounted) return;
      setState(() => _generating = true);
      final count = await widget.achievementDao
          .importComponentsToDatabase(_selectedBatchId!, components);
      _loadComponentScores();
      widget.dataRevision?.value++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('导入成功：$count 名学生（平时${components['pingshi']?.length ?? 0}/'
                    '实验${components['experiment']?.length ?? 0}/'
                    '考核${components['exam']?.length ?? 0}），已合成达成度'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ScoresTab.importExcel', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 导入前确认页：展示目标拆分结构 + 校验结果（计数/缺失/异常/重复）。
  Future<bool?> _showImportConfirm(
      Map<String, List<Map<String, dynamic>>> components,
      Map<String, dynamic> report) {
    final counts = (report['counts'] as Map?) ?? {};
    final missing = (report['missing'] as Map?) ?? {};
    final outOfRange = (report['outOfRange'] as List?) ?? [];
    final duplicates = (report['duplicates'] as Map?) ?? {};
    final ok = report['ok'] == true;
    const envName = {'pingshi': '平时', 'experiment': '实验', 'exam': '考核'};

    Widget section(String title, List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...children,
            const SizedBox(height: 10),
          ],
        );

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber,
              color: ok ? Colors.green : Colors.orange, size: 22),
          const SizedBox(width: 8),
          const Text('导入校验'),
        ]),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                section('识别到的成绩环节与人数', [
                  for (final env in ['pingshi', 'experiment', 'exam'])
                    if (counts[env] != null)
                      Text('• ${envName[env]}成绩：${counts[env]} 名学生',
                          style: const TextStyle(fontSize: 12)),
                ]),
                section('合成规则（大纲驱动）', const [
                  Text('• 按大纲“课程目标达成考核与评价方式及成绩评定对照表”的比例合成',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('• 实验比例为 0 的课程，缺少实验 sheet 不会扣分',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('• 课程设计、项目、综合、答辩等 sheet 会按考核成绩处理',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                if (duplicates.isNotEmpty)
                  section('⚠ 重复学号', [
                    for (final e in duplicates.entries)
                      Text('• ${envName[e.key]}：${(e.value as List).join('、')}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.red)),
                  ]),
                if (outOfRange.isNotEmpty)
                  section('⚠ 异常分值（应在 0-100）', [
                    for (final r in outOfRange.take(10))
                      Text(
                          '• ${envName[r['env']]} ${r['student_id']}：${r['value']}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.red)),
                    if (outOfRange.length > 10)
                      Text('… 共 ${outOfRange.length} 处',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.red)),
                  ]),
                if (missing.isNotEmpty)
                  section('当前批次中、本次未包含的学生', [
                    for (final e in missing.entries)
                      Text('• ${envName[e.key]}缺 ${(e.value as List).length} 人',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.orange)),
                  ]),
                if (ok)
                  const Text('校验通过，可导入。',
                      style: TextStyle(fontSize: 12, color: Colors.green))
                else
                  const Text('存在上述问题，仍可强制导入，但建议修正后重试。',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ok ? '确认导入' : '仍然导入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBatches) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // 批次选择 + 操作按钮
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              // 批次下拉
              _buildBatchDropdown(primary),
              const SizedBox(height: 10),
              // 操作按钮行
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildActionChip(
                      icon: Icons.download,
                      label: '下载模板',
                      onTap: _downloadTemplate,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    _buildActionChip(
                      icon: Icons.upload_file,
                      label: '导入成绩 Excel',
                      onTap: _generating ? null : _importGradesExcel,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    _buildActionChip(
                      icon: Icons.person_add,
                      label: '添加成绩',
                      onTap: () => _showAddScoreDialog(),
                      color: primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_generating) const LinearProgressIndicator(),
        const Divider(height: 1),
        // 子Tab: 按大纲对照表实际存在的考核项显示。
        Container(
            color: primary,
            margin: const EdgeInsets.only(top: 4),
            child: TabBar(
                controller: _tabCtrl,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                labelStyle: const TextStyle(fontSize: 13),
                tabs: [
                  for (final env in _activeEnvs) Tab(text: _envTitle(env)),
                ])),
        if (_loadingComponents) const LinearProgressIndicator(),
        Expanded(
            child: TabBarView(controller: _tabCtrl, children: [
          for (final env in _activeEnvs)
            _buildComponentTable(env, _rowsForEnv(env)),
        ])),
      ],
    );
  }

  String _envTitle(String env) {
    switch (env) {
      case 'pingshi':
        return '平时成绩';
      case 'experiment':
        return '实验成绩';
      case 'aggregate':
        return '达成成绩';
      default:
        return '考核成绩';
    }
  }

  List<Map<String, dynamic>> _rowsForEnv(String env) {
    switch (env) {
      case 'pingshi':
        return _ps;
      case 'experiment':
        return _es;
      case 'aggregate':
        return _agg;
      default:
        return _xs;
    }
  }

  void _loadComponentScores() async {
    if (_selectedBatchId == null) return;
    setState(() => _loadingComponents = true);
    try {
      final weights = await widget.achievementDao
          .resolveObjectiveAssessmentWeights(_selectedBatchId!);
      final objectiveWeights = await widget.achievementDao
          .resolveObjectiveWeights(_selectedBatchId!);
      final fullMarks = await widget.achievementDao
          .resolveObjectiveFullMarks(_selectedBatchId!);
      final activeObjectives = [
        for (var i = 0; i < 4; i++)
          if ((i < objectiveWeights.length && objectiveWeights[i] > 0) ||
              (i < fullMarks.length && fullMarks[i] > 0))
            i
      ];
      if (activeObjectives.isEmpty) activeObjectives.addAll([0, 1, 2, 3]);
      bool close(double a, double b) => (a - b).abs() < 0.0001;
      final standardThreePart = activeObjectives.length == 4 &&
          weights.length >= 4 &&
          activeObjectives.every((i) {
            final w = weights[i];
            return close(w['pingshi'] ?? 0, 0.2) &&
                close(w['experiment'] ?? 0, 0.3) &&
                close(w['exam'] ?? 0, 0.5);
          });
      if (!standardThreePart) {
        final aggregate =
            await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
        sortScoresInPlace(aggregate, _sort);
        if (mounted) {
          setState(() {
            _activeObjectiveIndexes = activeObjectives;
            _setActiveEnvs(['aggregate']);
            _agg = aggregate;
            _ps = [];
            _es = [];
            _xs = [];
            _loadingComponents = false;
          });
        }
        return;
      }

      final active = <String>[];
      bool uses(String env) => weights.any((w) => (w[env] ?? 0) > 0.0001);
      if (uses('pingshi')) active.add('pingshi');
      if (uses('experiment')) active.add('experiment');
      if (uses('exam')) active.add('exam');

      final r = await Future.wait([
        active.contains('pingshi')
            ? widget.achievementDao.getPingshiScores(_selectedBatchId!)
            : Future.value(<Map<String, dynamic>>[]),
        active.contains('experiment')
            ? widget.achievementDao.getExperimentScores(_selectedBatchId!)
            : Future.value(<Map<String, dynamic>>[]),
        active.contains('exam')
            ? widget.achievementDao.getExamScores(_selectedBatchId!)
            : Future.value(<Map<String, dynamic>>[]),
      ]);
      if (mounted) {
        setState(() {
          _activeObjectiveIndexes = activeObjectives;
          _setActiveEnvs(active);
          _ps = r[0];
          _es = r[1];
          _xs = r[2];
          _agg = [];
          _loadingComponents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingComponents = false);
    }
  }

  Widget _buildComponentTable(String env, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline,
                size: 48,
                color:
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('暂无数据，请先导入成绩',
                style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    final cols = _envCols(env);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surface = Theme.of(context).colorScheme.surface;
    final hairline = Theme.of(context).colorScheme.outline;
    final primary = Theme.of(context).colorScheme.primary;

    final headerStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: onSurface,
      letterSpacing: 0.5,
    );
    final cellStyle = TextStyle(
      fontSize: 13,
      color: onSurface.withValues(alpha: 0.85),
    );

    return RefreshIndicator(
      onRefresh: () async => _loadComponentScores(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 表头
            Container(
              color: surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SizedBox(width: 100, child: Text('学号', style: headerStyle)),
                  SizedBox(width: 80, child: Text('姓名', style: headerStyle)),
                  for (final c in cols)
                    Expanded(
                        child: Text(_colLabel(c),
                            style: headerStyle, textAlign: TextAlign.center)),
                  SizedBox(
                      width: 60,
                      child: Text('操作',
                          style: headerStyle, textAlign: TextAlign.center)),
                ],
              ),
            ),
            Divider(height: 1, color: hairline),
            // 数据行
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final r = rows[index];
                  final isEven = index.isEven;
                  return Container(
                    color: isEven ? surface : surface.withValues(alpha: 0.7),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(r['student_id']?.toString() ?? '',
                              style: cellStyle),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(r['student_name']?.toString() ?? '',
                              style: cellStyle),
                        ),
                        for (final k in cols)
                          Expanded(
                            child: Text(
                              ((r[k] as num?)?.toDouble() ?? 0).toStringAsFixed(
                                  k.contains('achievement') ? 2 : 1),
                              style: cellStyle.copyWith(fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        SizedBox(
                          width: 60,
                          child: IconButton(
                            icon: Icon(Icons.edit_rounded,
                                size: 16, color: primary),
                            onPressed: () => _editRow(env, r),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            tooltip: '编辑',
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

  void _editRow(String env, Map<String, dynamic> row) {
    if (env == 'aggregate') {
      _showAddScoreDialog(existing: row);
      return;
    }
    final cols = _envCols(env);
    final ctrls = cols
        .map((k) => TextEditingController(
            text: ((row[k] as num?)?.toDouble() ?? 0).toString()))
        .toList();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('编辑 ${row['student_name'] ?? ''}'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (int i = 0; i < cols.length; i++)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextField(
                            controller: ctrls[i],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: _colLabel(cols[i]),
                                border: const OutlineInputBorder(),
                                isDense: true)))
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        // 不直接写 row[...]：row 来自 sqflite 只读 Map，赋值会抛 read-only。
                        // 直接从输入框收集到 data 落库，再 _loadComponentScores() 刷新。
                        String tn = env == 'pingshi'
                            ? 'achievement_pingshi_scores'
                            : env == 'experiment'
                                ? 'achievement_experiment_scores'
                                : 'achievement_exam_scores';
                        final db = await DatabaseHelper.instance.database;
                        final data = <String, dynamic>{};
                        for (int i = 0; i < cols.length; i++)
                          data[cols[i]] = double.tryParse(ctrls[i].text) ?? 0;
                        data['updated_at'] = DateTime.now().toIso8601String();
                        await db.update(tn, data,
                            where: 'id=?', whereArgs: [row['id']]);
                        final components = {
                          'pingshi': await widget.achievementDao
                              .getPingshiScores(_selectedBatchId!),
                          'experiment': await widget.achievementDao
                              .getExperimentScores(_selectedBatchId!),
                          'exam': await widget.achievementDao
                              .getExamScores(_selectedBatchId!),
                        };
                        await widget.achievementDao.importComponentsToDatabase(
                            _selectedBatchId!, components);
                        _loadComponentScores();
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('已保存并重算达成度'),
                                  backgroundColor: Colors.green));
                      },
                      child: const Text('保存')),
                ]));
  }

  static const _colLabelMap = {
    'class_activity_score': '课堂表现',
    'quiz_homework_score': '期间测验',
    'extra_learning_score': '课外学习',
    'total_score': '总评',
    'exp1_score': '实验1',
    'exp2_score': '实验2',
    'exp3_score': '实验3',
    'exp4_score': '实验4',
    'exp5_score': '实验5',
    'exp6_score': '实验6',
    'exp7_score': '实验7',
    'project_score': '项目得分',
    'group_score': '小组得分',
    'individual_score': '个人得分',
    'defense_score': '答辩得分',
    'obj1_achievement': '目标1达成',
    'obj2_achievement': '目标2达成',
    'obj3_achievement': '目标3达成',
    'obj4_achievement': '目标4达成',
  };
  String _colLabel(String k) => _colLabelMap[k] ?? k;

  List<String> _envCols(String env) {
    switch (env) {
      case 'aggregate':
        return [
          for (final i in _activeObjectiveIndexes) 'obj${i + 1}_achievement',
          'total_score',
        ];
      case 'pingshi':
        return [
          'class_activity_score',
          'quiz_homework_score',
          'extra_learning_score',
          'total_score'
        ];
      case 'experiment':
        return [
          'exp1_score',
          'exp2_score',
          'exp3_score',
          'exp4_score',
          'exp5_score',
          'exp6_score',
          'exp7_score',
          'total_score'
        ];
      default:
        return [
          'project_score',
          'group_score',
          'individual_score',
          'defense_score',
          'total_score'
        ];
    }
  }

  Widget _buildBatchDropdown(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: _selectedBatchId,
          hint: const Text('选择批次'),
          items: _batches.map((b) {
            return DropdownMenuItem<int>(
              value: b['id'] as int,
              child: Text(b['batch_name'] ?? '未命名'),
            );
          }).toList(),
          onChanged: (v) {
            setState(() => _selectedBatchId = v);
            _loadComponentScores();
          },
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onTap,
    );
  }
}

class ComponentAchievementTab extends StatefulWidget {
  final AchievementDao achievementDao;
  final ValueNotifier<int>? dataRevision;
  final String env;

  const ComponentAchievementTab({
    super.key,
    required this.achievementDao,
    required this.env,
    this.dataRevision,
  });

  @override
  State<ComponentAchievementTab> createState() =>
      _ComponentAchievementTabState();
}

class _ComponentAchievementTabState extends State<ComponentAchievementTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, double>> _envWeights = [];
  List<int> _activeObjectives = [];
  Map<String, double> _classAvg = {};
  ScoreSort _sort = ScoreSort.idAsc;
  bool _loading = true;
  bool _loadingRows = false;
  bool _fromAggregate = true;
  bool _usesEnv = false;

  @override
  void initState() {
    super.initState();
    widget.dataRevision?.addListener(_onDataChanged);
    _loadBatches();
  }

  @override
  void dispose() {
    widget.dataRevision?.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _loadRows();
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _loading = false;
        if (_selectedBatchId == null && batches.isNotEmpty) {
          _selectedBatchId = batches.first['id'] as int;
        }
      });
      await _loadRows();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRows() async {
    if (_selectedBatchId == null) return;
    setState(() => _loadingRows = true);
    try {
      final weights = await widget.achievementDao
          .resolveObjectiveWeights(_selectedBatchId!);
      final fullMarks = await widget.achievementDao
          .resolveObjectiveFullMarks(_selectedBatchId!);
      final envWeights = await widget.achievementDao
          .resolveObjectiveAssessmentWeights(_selectedBatchId!);
      final activeObjectives = [
        for (var i = 0; i < 4; i++)
          if ((i < weights.length && weights[i] > 0) ||
              (i < fullMarks.length && fullMarks[i] > 0))
            i
      ];
      if (activeObjectives.isEmpty) activeObjectives.addAll([0, 1, 2, 3]);
      final usesEnv = activeObjectives.any(
          (i) => i < envWeights.length && (envWeights[i][widget.env] ?? 0) > 0);

      var rows = <Map<String, dynamic>>[];
      var fromAggregate = true;
      var classAvg = <String, double>{};
      if (usesEnv) {
        final standard = _isStandardThreePart(activeObjectives, envWeights);
        final componentCount = await _componentRowCount();
        fromAggregate = !standard || componentCount == 0;
        rows = fromAggregate
            ? await widget.achievementDao.getScoresByBatch(_selectedBatchId!)
            : await _loadComponentRows();
        sortScoresInPlace(rows, _sort);

        final combined = await widget.achievementDao
            .calculateCombinedAchievement(_selectedBatchId!);
        final rawAvg = (combined[widget.env] as Map?) ?? {};
        classAvg = {
          for (final i in activeObjectives)
            if (i < envWeights.length && (envWeights[i][widget.env] ?? 0) > 0)
              'obj${i + 1}': (rawAvg['obj${i + 1}'] as num?)?.toDouble() ??
                  _averageObjective(rows, i, fromAggregate)
        };
      }

      if (!mounted) return;
      setState(() {
        _envWeights = envWeights;
        _activeObjectives = activeObjectives;
        _usesEnv = usesEnv;
        _fromAggregate = fromAggregate;
        _rows = rows;
        _classAvg = classAvg;
        _loadingRows = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRows = false);
    }
  }

  Future<int> _componentRowCount() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${_componentTableName()} WHERE batch_id = ?',
        [_selectedBatchId]);
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> _loadComponentRows() {
    switch (widget.env) {
      case 'pingshi':
        return widget.achievementDao.getPingshiScores(_selectedBatchId!);
      case 'experiment':
        return widget.achievementDao.getExperimentScores(_selectedBatchId!);
      default:
        return widget.achievementDao.getExamScores(_selectedBatchId!);
    }
  }

  String _componentTableName() {
    switch (widget.env) {
      case 'pingshi':
        return 'achievement_pingshi_scores';
      case 'experiment':
        return 'achievement_experiment_scores';
      default:
        return 'achievement_exam_scores';
    }
  }

  bool _isStandardThreePart(
      List<int> activeObjectives, List<Map<String, double>> envWeights) {
    if (activeObjectives.length != 4 || envWeights.length < 4) return false;
    bool close(double a, double b) => (a - b).abs() < 0.0001;
    return activeObjectives.every((i) {
      final w = envWeights[i];
      return close(w['pingshi'] ?? 0, 0.2) &&
          close(w['experiment'] ?? 0, 0.3) &&
          close(w['exam'] ?? 0, 0.5);
    });
  }

  double _averageObjective(
      List<Map<String, dynamic>> rows, int objective, bool fromAggregate) {
    if (rows.isEmpty) return 0;
    final total = rows
        .map((row) => _objectiveAchievement(row, objective, fromAggregate))
        .fold<double>(0, (a, b) => a + b);
    return total / rows.length;
  }

  double _objectiveAchievement(
      Map<String, dynamic> row, int objective, bool fromAggregate) {
    if (fromAggregate) {
      return (row['obj${objective + 1}_achievement'] as num?)?.toDouble() ?? 0;
    }
    switch (widget.env) {
      case 'pingshi':
        if (objective == 0) {
          return (row['class_activity_achievement'] as num?)?.toDouble() ?? 0;
        }
        if (objective == 1) {
          return (row['quiz_homework_achievement'] as num?)?.toDouble() ?? 0;
        }
        if (objective == 3) {
          return (row['extra_learning_achievement'] as num?)?.toDouble() ?? 0;
        }
        return 0;
      default:
        return (row['obj${objective + 1}_achievement'] as num?)?.toDouble() ??
            0;
    }
  }

  String _envTitle() {
    switch (widget.env) {
      case 'pingshi':
        return '平时达成';
      case 'experiment':
        return '实验达成';
      default:
        return '考核达成';
    }
  }

  IconData _envIcon() {
    switch (widget.env) {
      case 'pingshi':
        return Icons.school_outlined;
      case 'experiment':
        return Icons.science_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  Color _envColor(BuildContext context) {
    switch (widget.env) {
      case 'pingshi':
        return Colors.blue;
      case 'experiment':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  String _envLabel() {
    switch (widget.env) {
      case 'pingshi':
        return '平时成绩';
      case 'experiment':
        return '实验成绩';
      default:
        return '考核成绩';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: _buildBatchDropdown(primary)),
              const SizedBox(width: 8),
              PopupMenuButton<ScoreSort>(
                tooltip: '排序',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (v) {
                  setState(() {
                    _sort = v;
                    sortScoresInPlace(_rows, _sort);
                  });
                },
                itemBuilder: (_) => [
                  for (final s in ScoreSort.values)
                    PopupMenuItem(value: s, child: Text(scoreSortLabel(s))),
                ],
              ),
            ],
          ),
        ),
        if (_loadingRows) const LinearProgressIndicator(),
        if (!_usesEnv)
          Expanded(child: _buildNoEnvState(context))
        else ...[
          achievementTabHeader(
            context,
            title: _envTitle(),
            classAvg: _classAvg,
            infoCard: _buildInfoCard(context),
          ),
          Expanded(
            child: _rows.isEmpty
                ? _buildEmptyState(context)
                : achievementScoreTable(
                    context,
                    rows: _rows,
                    onRefresh: _loadRows,
                    columns: [
                      for (final i in _activeObjectives)
                        if (i < _envWeights.length &&
                            (_envWeights[i][widget.env] ?? 0) > 0)
                          ScoreColumn(
                            '目标${i + 1}',
                            (row) =>
                                _objectiveAchievement(row, i, _fromAggregate),
                            isAchievement: true,
                            digits: 2,
                            headerColor: kObjectiveColors[i],
                          ),
                      ScoreColumn(
                        _fromAggregate ? '综合得分' : '总评',
                        (row) => (row['total_score'] as num?)?.toDouble() ?? 0,
                        bold: true,
                      ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildBatchDropdown(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: primary.withValues(alpha: 0.3)),
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
                    child: Text(b['batch_name']?.toString() ?? '未命名',
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() => _selectedBatchId = v);
            _loadRows();
          },
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final color = _envColor(context);
    final rows = [
      for (final i in _activeObjectives)
        if (i < _envWeights.length && (_envWeights[i][widget.env] ?? 0) > 0)
          '目标${i + 1}：${((_envWeights[i][widget.env] ?? 0) * 100).toStringAsFixed(0)}%',
    ];
    return Card(
      margin: EdgeInsets.zero,
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${_envLabel()}评价结构',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 8),
            for (final row in rows)
              Text('• $row', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              _fromAggregate ? '当前按大纲聚合达成度展示' : '当前按导入分项成绩展示',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoEnvState(BuildContext context) {
    final color = _envColor(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_envIcon(), size: 64, color: color.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          Text('当前批次未设置${_envLabel()}环节',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('请在达成度概览的大纲对照表中确认评价方式',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_envIcon(), size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('暂无${_envLabel()}数据',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('请在成绩管理中导入或录入成绩数据',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 3 — 平时达成（课堂表现→目标1, 期间测验→目标2, 课外学习→目标4）
// ══════════════════════════════════════════════════════════════════════════════

class PingshiAchievementTab extends StatefulWidget {
  final AchievementDao achievementDao;
  final ValueNotifier<int>? dataRevision;
  const PingshiAchievementTab(
      {required this.achievementDao, this.dataRevision});

  @override
  State<PingshiAchievementTab> createState() => _PingshiAchievementTabState();
}

class _PingshiAchievementTabState extends State<PingshiAchievementTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  List<Map<String, dynamic>> _scores = [];
  Map<String, double> _classAvg = {};
  ScoreSort _sort = ScoreSort.idAsc;
  bool _loading = true;

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
    final batches = await widget.achievementDao.getBatches();
    if (mounted) {
      setState(() {
        _batches = batches;
        _loading = false;
        if (batches.isNotEmpty && _selectedBatchId == null) {
          _selectedBatchId = batches.first['id'] as int;
        }
      });
      if (_selectedBatchId != null) _loadScores();
    }
  }

  Future<void> _loadScores() async {
    if (_selectedBatchId == null) return;
    final scores =
        await widget.achievementDao.getPingshiScores(_selectedBatchId!);
    final avg = await widget.achievementDao
        .calculatePingshiClassAverage(_selectedBatchId!);
    if (mounted) {
      setState(() {
        sortScoresInPlace(scores, _sort);
        _scores = scores;
        _classAvg = avg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        // 批次选择器 + 生成按钮
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedBatchId,
                  decoration: const InputDecoration(
                    labelText: '选择批次',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _batches
                      .map((b) => DropdownMenuItem<int>(
                            value: b['id'] as int,
                            child: Text(b['batch_name']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedBatchId = v);
                    _loadScores();
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ScoreSort>(
                tooltip: '排序',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (v) {
                  setState(() {
                    _sort = v;
                    sortScoresInPlace(_scores, _sort);
                  });
                },
                itemBuilder: (_) => [
                  for (final s in ScoreSort.values)
                    PopupMenuItem(value: s, child: Text(scoreSortLabel(s))),
                ],
              ),
            ],
          ),
        ),

        // 标题 + 说明卡片(左) + 班级平均(右)，水平排布以给下方数据表让出空间
        achievementTabHeader(
          context,
          title: '平时达成',
          classAvg: _classAvg,
          infoCard: Card(
            margin: EdgeInsets.zero,
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: primary, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('平时成绩评价结构（权重20%）',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 课堂表现(20%) → 课程目标1 ｜ 达成度 = 得分/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 期间测验(30%) → 课程目标2 ｜ 达成度 = 得分/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 课外学习(50%) → 课程目标4 ｜ 达成度 = 得分/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 目标3：平时成绩不涉及',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text('总评 = 课堂×0.2 + 测验×0.3 + 课外×0.5',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue)),
                ],
              ),
            ),
          ),
        ),

        // 学生成绩表
        Expanded(
          child: _scores.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无平时成绩数据',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('请在成绩管理中导入或录入成绩数据',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : achievementScoreTable(
                  context,
                  rows: _scores,
                  onRefresh: () async => _loadScores(),
                  columns: [
                    ScoreColumn(
                        '课堂表现',
                        (s) =>
                            (s['class_activity_score'] as num?)?.toDouble() ??
                            0),
                    ScoreColumn(
                        '目标1',
                        (s) =>
                            (s['class_activity_achievement'] as num?)
                                ?.toDouble() ??
                            0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[0]),
                    ScoreColumn(
                        '期间测验',
                        (s) =>
                            (s['quiz_homework_score'] as num?)?.toDouble() ??
                            0),
                    ScoreColumn(
                        '目标2',
                        (s) =>
                            (s['quiz_homework_achievement'] as num?)
                                ?.toDouble() ??
                            0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[1]),
                    ScoreColumn(
                        '课外学习',
                        (s) =>
                            (s['extra_learning_score'] as num?)?.toDouble() ??
                            0),
                    ScoreColumn(
                        '目标4',
                        (s) =>
                            (s['extra_learning_achievement'] as num?)
                                ?.toDouble() ??
                            0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[3]),
                    ScoreColumn('总评',
                        (s) => (s['total_score'] as num?)?.toDouble() ?? 0,
                        bold: true),
                  ],
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 4 — 实验达成（兼容 7 实验学校模板与 6 实验简洁模板）
// ══════════════════════════════════════════════════════════════════════════════

class ExperimentAchievementTab extends StatefulWidget {
  final AchievementDao achievementDao;
  final ValueNotifier<int>? dataRevision;
  const ExperimentAchievementTab(
      {required this.achievementDao, this.dataRevision});

  @override
  State<ExperimentAchievementTab> createState() =>
      _ExperimentAchievementTabState();
}

class _ExperimentAchievementTabState extends State<ExperimentAchievementTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  List<Map<String, dynamic>> _scores = [];
  Map<String, double> _classAvg = {};
  ScoreSort _sort = ScoreSort.idAsc;
  bool _loading = true;

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
    final batches = await widget.achievementDao.getBatches();
    if (mounted) {
      setState(() {
        _batches = batches;
        _loading = false;
        if (batches.isNotEmpty && _selectedBatchId == null) {
          _selectedBatchId = batches.first['id'] as int;
        }
      });
      if (_selectedBatchId != null) _loadScores();
    }
  }

  Future<void> _loadScores() async {
    if (_selectedBatchId == null) return;
    final scores =
        await widget.achievementDao.getExperimentScores(_selectedBatchId!);
    final avg = await widget.achievementDao
        .calculateExperimentClassAverage(_selectedBatchId!);
    if (mounted) {
      setState(() {
        sortScoresInPlace(scores, _sort);
        _scores = scores;
        _classAvg = avg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        // 批次选择器
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedBatchId,
                  decoration: const InputDecoration(
                    labelText: '选择批次',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _batches
                      .map((b) => DropdownMenuItem<int>(
                            value: b['id'] as int,
                            child: Text(b['batch_name']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedBatchId = v);
                    _loadScores();
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ScoreSort>(
                tooltip: '排序',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (v) {
                  setState(() {
                    _sort = v;
                    sortScoresInPlace(_scores, _sort);
                  });
                },
                itemBuilder: (_) => [
                  for (final s in ScoreSort.values)
                    PopupMenuItem(value: s, child: Text(scoreSortLabel(s))),
                ],
              ),
            ],
          ),
        ),

        // 标题 + 说明卡片(左) + 班级平均(右)，水平排布以给下方数据表让出空间
        achievementTabHeader(
          context,
          title: '实验达成',
          classAvg: _classAvg,
          infoCard: Card(
            margin: EdgeInsets.zero,
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: primary, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('实验成绩评价结构（权重30%）',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 实验1-2 → 课程目标1 ｜ 达成度 = avg(实验1,实验2)/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 实验3-4 → 课程目标2 ｜ 达成度 = avg(实验3,实验4)/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 学校模板：实验5-6 → 目标3，实验7 → 目标4',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 6实验模板：实验5 → 目标3，实验6 → 目标4',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('总评按导入模板自动采用 6 次或 7 次实验平均',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ],
              ),
            ),
          ),
        ),

        // 学生成绩表
        Expanded(
          child: _scores.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.science_outlined,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无实验成绩数据',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('请在成绩管理中导入或录入成绩数据',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : achievementScoreTable(
                  context,
                  rows: _scores,
                  onRefresh: () async => _loadScores(),
                  columns: [
                    ScoreColumn('实验1',
                        (s) => (s['exp1_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('实验2',
                        (s) => (s['exp2_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标1',
                        (s) => (s['obj1_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[0]),
                    ScoreColumn('实验3',
                        (s) => (s['exp3_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('实验4',
                        (s) => (s['exp4_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标2',
                        (s) => (s['obj2_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[1]),
                    ScoreColumn('实验5',
                        (s) => (s['exp5_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('实验6',
                        (s) => (s['exp6_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标3',
                        (s) => (s['obj3_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[2]),
                    ScoreColumn('实验7',
                        (s) => (s['exp7_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标4',
                        (s) => (s['obj4_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[3]),
                    ScoreColumn('总评',
                        (s) => (s['total_score'] as num?)?.toDouble() ?? 0,
                        bold: true),
                  ],
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 5 — 考核达成（项目30%→目标1, 小组20%→目标2, 个人20%→目标3, 答辩30%→目标4）
// ══════════════════════════════════════════════════════════════════════════════

class ExamAchievementTab extends StatefulWidget {
  final AchievementDao achievementDao;
  final ValueNotifier<int>? dataRevision;
  const ExamAchievementTab({required this.achievementDao, this.dataRevision});

  @override
  State<ExamAchievementTab> createState() => _ExamAchievementTabState();
}

class _ExamAchievementTabState extends State<ExamAchievementTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  List<Map<String, dynamic>> _scores = [];
  Map<String, double> _classAvg = {};
  ScoreSort _sort = ScoreSort.idAsc;
  bool _loading = true;

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
    final batches = await widget.achievementDao.getBatches();
    if (mounted) {
      setState(() {
        _batches = batches;
        _loading = false;
        if (batches.isNotEmpty && _selectedBatchId == null) {
          _selectedBatchId = batches.first['id'] as int;
        }
      });
      if (_selectedBatchId != null) _loadScores();
    }
  }

  Future<void> _loadScores() async {
    if (_selectedBatchId == null) return;
    final scores = await widget.achievementDao.getExamScores(_selectedBatchId!);
    final avg = await widget.achievementDao
        .calculateExamClassAverage(_selectedBatchId!);
    if (mounted) {
      setState(() {
        sortScoresInPlace(scores, _sort);
        _scores = scores;
        _classAvg = avg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        // 批次选择器
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedBatchId,
                  decoration: const InputDecoration(
                    labelText: '选择批次',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _batches
                      .map((b) => DropdownMenuItem<int>(
                            value: b['id'] as int,
                            child: Text(b['batch_name']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedBatchId = v);
                    _loadScores();
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ScoreSort>(
                tooltip: '排序',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (v) {
                  setState(() {
                    _sort = v;
                    sortScoresInPlace(_scores, _sort);
                  });
                },
                itemBuilder: (_) => [
                  for (final s in ScoreSort.values)
                    PopupMenuItem(value: s, child: Text(scoreSortLabel(s))),
                ],
              ),
            ],
          ),
        ),

        // 标题 + 说明卡片(左) + 班级平均(右)，水平排布以给下方数据表让出空间
        achievementTabHeader(
          context,
          title: '考核达成',
          classAvg: _classAvg,
          infoCard: Card(
            margin: EdgeInsets.zero,
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: primary, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('期末考核评价结构（权重50%）',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 项目(30%) → 课程目标1 ｜ 达成度 = 项目得分/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 小组(20%) → 课程目标2 ｜ 达成度 = 小组得分/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 个人(20%) → 课程目标3 ｜ 达成度 = 个人得分/100',
                      style: TextStyle(fontSize: 12)),
                  const Text('• 答辩(30%) → 课程目标4 ｜ 达成度 = 答辩得分/100',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('总评 = 项目×0.3 + 小组×0.2 + 个人×0.2 + 答辩×0.3',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange)),
                ],
              ),
            ),
          ),
        ),

        // 学生成绩表
        Expanded(
          child: _scores.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.assignment_outlined,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无期末考核数据',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('请在成绩管理中导入或录入成绩数据',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : achievementScoreTable(
                  context,
                  rows: _scores,
                  onRefresh: () async => _loadScores(),
                  columns: [
                    ScoreColumn('项目',
                        (s) => (s['project_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标1',
                        (s) => (s['obj1_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[0]),
                    ScoreColumn('小组',
                        (s) => (s['group_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标2',
                        (s) => (s['obj2_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[1]),
                    ScoreColumn(
                        '个人',
                        (s) =>
                            (s['individual_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标3',
                        (s) => (s['obj3_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[2]),
                    ScoreColumn('答辩',
                        (s) => (s['defense_score'] as num?)?.toDouble() ?? 0),
                    ScoreColumn('目标4',
                        (s) => (s['obj4_achievement'] as num?)?.toDouble() ?? 0,
                        isAchievement: true,
                        digits: 2,
                        headerColor: kObjectiveColors[3]),
                    ScoreColumn('总评',
                        (s) => (s['total_score'] as num?)?.toDouble() ?? 0,
                        bold: true),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ComponentExpandTile extends StatefulWidget {
  final String title, env;
  final IconData icon;
  final Color color;
  final int batchId;
  final List<String> colLabels, colKeys;
  const _ComponentExpandTile(
      {required this.title,
      required this.icon,
      required this.color,
      required this.batchId,
      required this.env,
      required this.colLabels,
      required this.colKeys});
  @override
  State<_ComponentExpandTile> createState() => _ComponentExpandTileState();
}

class _ComponentExpandTileState extends State<_ComponentExpandTile> {
  bool _expanded = false;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  Future<void> _load() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _expanded = true;
      _loading = true;
    });
    final tableName = widget.env == 'pingshi'
        ? 'achievement_pingshi_scores'
        : widget.env == 'experiment'
            ? 'achievement_experiment_scores'
            : 'achievement_exam_scores';
    final db = await DatabaseHelper.instance.database;
    final r = await db.query(tableName,
        where: 'batch_id=?',
        whereArgs: [widget.batchId],
        orderBy: 'student_id ASC');
    if (mounted)
      setState(() {
        _rows = r;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(
          leading: Icon(widget.icon, color: widget.color),
          title:
              Text('${widget.title}${_expanded ? ' (${_rows.length})' : ''}'),
          trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          onTap: _load),
      if (_loading) const LinearProgressIndicator(),
      if (_expanded && !_loading)
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              columns: [
                const DataColumn(
                    label: Text('学号',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold))),
                const DataColumn(
                    label: Text('姓名',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold))),
                for (final l in widget.colLabels)
                  DataColumn(
                      label: Text(l,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)))
              ],
              rows: List.generate(_rows.length, (i) {
                final r = _rows[i];
                return DataRow(
                  color: WidgetStateProperty.all(i.isEven
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.surface.withValues(alpha: 0.6)),
                  cells: [
                    DataCell(Text('${r['student_id'] ?? ''}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.85)))),
                    DataCell(Text('${r['student_name'] ?? ''}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.85)))),
                    for (final k in widget.colKeys)
                      DataCell(Text(
                          ((r[k] as num?)?.toDouble() ?? 0).toStringAsFixed(1),
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.85)))),
                  ],
                );
              }),
            ))
    ]);
  }
}
