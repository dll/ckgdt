import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/material.dart';
import '../../../../data/local/achievement_dao.dart';
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

  const ScoreManagementTab({
    required this.authService,
    required this.achievementDao,
  });

  @override
  State<ScoreManagementTab> createState() => _ScoreManagementTabState();
}

class _ScoreManagementTabState extends State<ScoreManagementTab> {
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _scores = [];
  int? _selectedBatchId;
  bool _loadingBatches = true;
  bool _loadingScores = false;
  bool _generating = false;

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
          _loadingBatches = false;
          if (_batches.isNotEmpty && _selectedBatchId == null) {
            _selectedBatchId = _batches.first['id'] as int;
            _loadScores();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  Future<void> _loadScores() async {
    if (_selectedBatchId == null) return;
    setState(() => _loadingScores = true);
    try {
      final scores = await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      if (mounted) {
        setState(() {
          _scores = scores;
          _loadingScores = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingScores = false);
    }
  }

  void _showAddScoreDialog({Map<String, dynamic>? existing}) {
    if (_selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择批次')),
      );
      return;
    }

    final isEdit = existing != null;
    final studentIdCtrl = TextEditingController(
        text: isEdit ? (existing['student_id'] ?? '').toString() : '');
    final studentNameCtrl = TextEditingController(
        text: isEdit ? (existing['student_name'] ?? '').toString() : '');
    final obj1Ctrl = TextEditingController(
        text: isEdit ? ((existing['obj1_score'] ?? 0).toString()) : '80');
    final obj2Ctrl = TextEditingController(
        text: isEdit ? ((existing['obj2_score'] ?? 0).toString()) : '75');
    final obj3Ctrl = TextEditingController(
        text: isEdit ? ((existing['obj3_score'] ?? 0).toString()) : '70');
    final obj4Ctrl = TextEditingController(
        text: isEdit ? ((existing['obj4_score'] ?? 0).toString()) : '85');

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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: obj1Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '目标1',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: obj2Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '目标2',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: obj3Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '目标3',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: obj4Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '目标4',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
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
              final o1 = double.tryParse(obj1Ctrl.text) ?? 0;
              final o2 = double.tryParse(obj2Ctrl.text) ?? 0;
              final o3 = double.tryParse(obj3Ctrl.text) ?? 0;
              final o4 = double.tryParse(obj4Ctrl.text) ?? 0;
              final total = o1 * kDefaultWeights[0] +
                  o2 * kDefaultWeights[1] +
                  o3 * kDefaultWeights[2] +
                  o4 * kDefaultWeights[3];

              if (isEdit) {
                final fm = AchievementConfig.defaults.fullMarks;
                await widget.achievementDao.updateScore(existing['id'] as int, {
                  'student_id': studentIdCtrl.text.trim(),
                  'student_name': studentNameCtrl.text.trim(),
                  'obj1_score': o1,
                  'obj1_achievement': (o1 / fm[0]).clamp(0.0, 1.0),
                  'obj2_score': o2,
                  'obj2_achievement': (o2 / fm[1]).clamp(0.0, 1.0),
                  'obj3_score': o3,
                  'obj3_achievement': (o3 / fm[2]).clamp(0.0, 1.0),
                  'obj4_score': o4,
                  'obj4_achievement': (o4 / fm[3]).clamp(0.0, 1.0),
                  'total_score': total,
                });
              } else {
                await widget.achievementDao.addScore(
                  batchId: _selectedBatchId!,
                  studentId: studentIdCtrl.text.trim(),
                  studentName: studentNameCtrl.text.trim(),
                  objective1Score: o1,
                  objective2Score: o2,
                  objective3Score: o3,
                  objective4Score: o4,
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
              await widget.achievementDao.recalculateAndSaveBatch(_selectedBatchId!);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadScores();
            },
            child: Text(isEdit ? '保存' : '添加'),
          ),
        ],
      ),
    ).then((_) {
      for (final c in [studentIdCtrl, studentNameCtrl, obj1Ctrl, obj2Ctrl, obj3Ctrl, obj4Ctrl]) {
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
      final cfgRows =
          await widget.achievementDao.getCourseObjectives('移动应用开发');
      final cfg = cfgRows.isNotEmpty
          ? AchievementConfig.fromObjectiveRows(cfgRows)
          : AchievementConfig.defaults;
      final bytes = AchievementExcelService.instance
          .buildGradeTemplate(students: students, config: cfg);
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
            action: SnackBarAction(label: '打开', onPressed: () => OpenFilex.open(file.path)),
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
      final components = svc.parseComponentSheets(f.bytes!);
      final total = (components['pingshi']?.length ?? 0) +
          (components['experiment']?.length ?? 0) +
          (components['exam']?.length ?? 0);
      if (total == 0) {
        throw StateError('未解析到平时/实验/期末成绩明细表，请确认使用课程成绩模板');
      }
      // 校验：对比当前批次学生名单、查异常分值/重复
      final roster = await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      final report = svc.validateComponents(components, roster: roster);
      if (!mounted) return;
      setState(() => _generating = false);
      final confirmed = await _showImportConfirm(components, report);
      if (confirmed != true) return;
      if (!mounted) return;
      setState(() => _generating = true);
      final count = await widget.achievementDao
          .importComponentsToDatabase(_selectedBatchId!, components);
      await _loadScores();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入成功：$count 名学生（平时${components['pingshi']?.length ?? 0}/'
                '实验${components['experiment']?.length ?? 0}/'
                '期末${components['exam']?.length ?? 0}），已合成达成度'),
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
    const envName = {'pingshi': '平时', 'experiment': '实验', 'exam': '期末'};

    Widget section(String title, List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                section('目标拆分（大纲驱动）', const [
                  Text('• 平时：课堂→目标1 · 测验→目标2 · 大作业→目标4', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('• 实验：1,2→目标1 · 3,4→目标2 · 5,6→目标3 · 7→目标4', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('• 期末：项目→目标1 · 小组→目标2 · 个人→目标3 · 答辩→目标4', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                if (duplicates.isNotEmpty)
                  section('⚠ 重复学号', [
                    for (final e in duplicates.entries)
                      Text('• ${envName[e.key]}：${(e.value as List).join('、')}',
                          style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ]),
                if (outOfRange.isNotEmpty)
                  section('⚠ 异常分值（应在 0-100）', [
                    for (final r in outOfRange.take(10))
                      Text('• ${envName[r['env']]} ${r['student_id']}：${r['value']}',
                          style: const TextStyle(fontSize: 12, color: Colors.red)),
                    if (outOfRange.length > 10)
                      Text('… 共 ${outOfRange.length} 处', style: const TextStyle(fontSize: 11, color: Colors.red)),
                  ]),
                if (missing.isNotEmpty)
                  section('当前批次中、本次未包含的学生', [
                    for (final e in missing.entries)
                      Text('• ${envName[e.key]}缺 ${(e.value as List).length} 人',
                          style: const TextStyle(fontSize: 12, color: Colors.orange)),
                  ]),
                if (ok)
                  const Text('校验通过，可导入。', style: TextStyle(fontSize: 12, color: Colors.green))
                else
                  const Text('存在上述问题，仍可强制导入，但建议修正后重试。',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ok ? '确认导入' : '仍然导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateFromQuizResults() async {
    if (_selectedBatchId == null) return;
    setState(() => _generating = true);
    try {
      await widget.achievementDao.generateScoresFromQuizResults(_selectedBatchId!);
      await widget.achievementDao.recalculateAndSaveBatch(_selectedBatchId!);
      await _loadScores();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已从测验成绩自动计算'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('计算失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _deleteScore(int scoreId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条成绩记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.achievementDao.deleteScore(scoreId);
      if (_selectedBatchId != null) {
        await widget.achievementDao.recalculateAndSaveBatch(_selectedBatchId!);
      }
      _loadScores();
    }
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
                      onTap: _showAddScoreDialog,
                      color: primary,
                    ),
                    const SizedBox(width: 8),
                    _buildActionChip(
                      icon: Icons.auto_fix_high,
                      label: '自动从学生成绩计算',
                      onTap: _generating ? null : _generateFromQuizResults,
                      color: Colors.green,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_generating)
          const LinearProgressIndicator(),
        const Divider(height: 1),
        // 成绩列表
        Expanded(
          child: _loadingScores
              ? const Center(child: CircularProgressIndicator())
              : _scores.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text('暂无成绩数据', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          const Text(
                            '点击上方按钮添加或自动生成',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadScores,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _scores.length,
                        itemBuilder: (_, index) => _buildScoreCard(_scores[index]),
                      ),
                    ),
        ),
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
          items: _batches.map((b) {
            return DropdownMenuItem<int>(
              value: b['id'] as int,
              child: Text(b['batch_name'] ?? '未命名'),
            );
          }).toList(),
          onChanged: (v) {
            setState(() => _selectedBatchId = v);
            _loadScores();
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

  Widget _buildScoreCard(Map<String, dynamic> score) {
    final scoreId = score['id'] as int? ?? 0;
    final totalScore = (score['total_score'] ?? 0).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 学生信息头
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    (score['student_name'] ?? '?').toString().characters.first,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        score['student_name'] ?? '未知',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      Text(
                        score['student_id'] ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: totalScore >= 60
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '总分 ${totalScore.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: totalScore >= 60 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                  onPressed: () => _showAddScoreDialog(existing: score),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  onPressed: () => _deleteScore(scoreId),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 四个目标分数 + 达成度
            Row(
              children: List.generate(4, (i) {
                final scoreKey = 'obj${i + 1}_score';
                final achieveKey = 'obj${i + 1}_achievement';
                final scoreVal = (score[scoreKey] ?? 0).toDouble();
                final achieveVal = (score[achieveKey] ?? 0).toDouble();
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    decoration: BoxDecoration(
                      color: kObjectiveColors[i].withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '目标${i + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            color: kObjectiveColors[i],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          scoreVal.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: kObjectiveColors[i],
                          ),
                        ),
                        if (achieveVal > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '达成 ${(achieveVal * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 9, color: kObjectiveColors[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 3 — 平时达成（课堂表现→目标1, 期间测验→目标2, 课外学习→目标4）
// ══════════════════════════════════════════════════════════════════════════════

class PingshiAchievementTab extends StatefulWidget {
  final AchievementDao achievementDao;
  const PingshiAchievementTab({required this.achievementDao});

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
  bool _generating = false;

  @override
  void initState() {
    super.initState();
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
          _loadScores();
        }
      });
    }
  }

  Future<void> _loadScores() async {
    if (_selectedBatchId == null) return;
    final scores = await widget.achievementDao.getPingshiScores(_selectedBatchId!);
    final avg = await widget.achievementDao.calculatePingshiClassAverage(_selectedBatchId!);
    if (mounted) {
      setState(() {
        sortScoresInPlace(scores, _sort);
        _scores = scores;
        _classAvg = avg;
      });
    }
  }

  Future<void> _generateDemo() async {
    if (_selectedBatchId == null) return;
    setState(() => _generating = true);
    try {
      await widget.achievementDao.generatePingshiDemoScores(_selectedBatchId!);
      await _loadScores();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('平时成绩演示数据已生成'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
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
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _batches.map((b) => DropdownMenuItem<int>(
                    value: b['id'] as int,
                    child: Text(b['batch_name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                  )).toList(),
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
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _generating ? null : _generateDemo,
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('生成演示'),
              ),
            ],
          ),
        ),

        // 说明卡片
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: primary, size: 18),
                      const SizedBox(width: 8),
                      const Text('平时成绩评价结构（权重20%）', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 课堂表现(20%) → 课程目标1 ｜ 达成度 = 得分/100', style: TextStyle(fontSize: 12)),
                  const Text('• 期间测验(30%) → 课程目标2 ｜ 达成度 = 得分/100', style: TextStyle(fontSize: 12)),
                  const Text('• 课外学习(50%) → 课程目标4 ｜ 达成度 = 得分/100', style: TextStyle(fontSize: 12)),
                  const Text('• 目标3：平时成绩不涉及', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text('总评 = 课堂×0.2 + 测验×0.3 + 课外×0.5', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
            ),
          ),
        ),

        // 班级平均达成度
        if (_classAvg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('班级平均指标点达成度', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (int i = 0; i < 4; i++)
                          Expanded(
                            child: Column(
                              children: [
                                Text('目标${i + 1}', style: TextStyle(fontSize: 11, color: kObjectiveColors[i])),
                                const SizedBox(height: 4),
                                Text(
                                  (_classAvg['obj${i + 1}'] ?? 0).toStringAsFixed(2),
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: achievementLevelColor(_classAvg['obj${i + 1}'] ?? 0)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    objectiveRadarChart(
                      [for (int i = 0; i < 4; i++) _classAvg['obj${i + 1}'] ?? 0],
                      Theme.of(context).colorScheme.primary,
                    ),
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
                      const Icon(Icons.school_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无平时成绩数据', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('点击「生成演示」按钮创建示例数据', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 16,
                      headingRowHeight: 40,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 40,
                      columns: const [
                        DataColumn(label: Text('学号', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('姓名', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('课堂表现', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('目标1达成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('期间测验', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('目标2达成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('课外学习', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('目标4达成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('总评', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                      rows: _scores.map((s) {
                        final classAch = (s['class_activity_achievement'] as num?)?.toDouble() ?? 0;
                        final quizAch = (s['quiz_homework_achievement'] as num?)?.toDouble() ?? 0;
                        final extraAch = (s['extra_learning_achievement'] as num?)?.toDouble() ?? 0;
                        return DataRow(cells: [
                          DataCell(Text(s['student_id']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                          DataCell(Text(s['student_name']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                          DataCell(Text(((s['class_activity_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(classAch.toStringAsFixed(2), style: TextStyle(fontSize: 11, color: achievementLevelColor(classAch)))),
                          DataCell(Text(((s['quiz_homework_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(quizAch.toStringAsFixed(2), style: TextStyle(fontSize: 11, color: achievementLevelColor(quizAch)))),
                          DataCell(Text(((s['extra_learning_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(extraAch.toStringAsFixed(2), style: TextStyle(fontSize: 11, color: achievementLevelColor(extraAch)))),
                          DataCell(Text(((s['total_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 4 — 实验达成（实验1-2→目标1, 实验3-4→目标2, 实验5-6→目标3, 实验7→目标4）
// ══════════════════════════════════════════════════════════════════════════════

class ExperimentAchievementTab extends StatefulWidget {
  final AchievementDao achievementDao;
  const ExperimentAchievementTab({required this.achievementDao});

  @override
  State<ExperimentAchievementTab> createState() => _ExperimentAchievementTabState();
}

class _ExperimentAchievementTabState extends State<ExperimentAchievementTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  List<Map<String, dynamic>> _scores = [];
  Map<String, double> _classAvg = {};
  ScoreSort _sort = ScoreSort.idAsc;
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
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
          _loadScores();
        }
      });
    }
  }

  Future<void> _loadScores() async {
    if (_selectedBatchId == null) return;
    final scores = await widget.achievementDao.getExperimentScores(_selectedBatchId!);
    final avg = await widget.achievementDao.calculateExperimentClassAverage(_selectedBatchId!);
    if (mounted) {
      setState(() {
        sortScoresInPlace(scores, _sort);
        _scores = scores;
        _classAvg = avg;
      });
    }
  }

  Future<void> _generateDemo() async {
    if (_selectedBatchId == null) return;
    setState(() => _generating = true);
    try {
      await widget.achievementDao.generateExperimentDemoScores(_selectedBatchId!);
      await _loadScores();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('实验成绩演示数据已生成'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
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
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _batches.map((b) => DropdownMenuItem<int>(
                    value: b['id'] as int,
                    child: Text(b['batch_name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                  )).toList(),
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
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _generating ? null : _generateDemo,
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('生成演示'),
              ),
            ],
          ),
        ),

        // 说明卡片
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: primary, size: 18),
                      const SizedBox(width: 8),
                      const Text('实验成绩评价结构（权重30%）', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 实验1-2 → 课程目标1 ｜ 达成度 = avg(实验1,实验2)/100', style: TextStyle(fontSize: 12)),
                  const Text('• 实验3-4 → 课程目标2 ｜ 达成度 = avg(实验3,实验4)/100', style: TextStyle(fontSize: 12)),
                  const Text('• 实验5-6 → 课程目标3 ｜ 达成度 = avg(实验5,实验6)/100', style: TextStyle(fontSize: 12)),
                  const Text('• 实验7   → 课程目标4 ｜ 达成度 = 实验7/100', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('总评 = (实验1+…+实验7) / 7', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            ),
          ),
        ),

        // 班级平均
        if (_classAvg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('班级平均指标点达成度', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (int i = 0; i < 4; i++)
                          Expanded(
                            child: Column(
                              children: [
                                Text('目标${i + 1}', style: TextStyle(fontSize: 11, color: kObjectiveColors[i])),
                                const SizedBox(height: 4),
                                Text(
                                  (_classAvg['obj${i + 1}'] ?? 0).toStringAsFixed(2),
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: achievementLevelColor(_classAvg['obj${i + 1}'] ?? 0)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    objectiveRadarChart(
                      [for (int i = 0; i < 4; i++) _classAvg['obj${i + 1}'] ?? 0],
                      Theme.of(context).colorScheme.primary,
                    ),
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
                      const Icon(Icons.science_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无实验成绩数据', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('点击「生成演示」按钮创建示例数据', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 14,
                      headingRowHeight: 40,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 40,
                      columns: const [
                        DataColumn(label: Text('学号', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('姓名', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('实验1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('实验2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('目标1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.red))),
                        DataColumn(label: Text('实验3', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('实验4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('目标2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue))),
                        DataColumn(label: Text('实验5', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('实验6', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('目标3', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.green))),
                        DataColumn(label: Text('实验7', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('目标4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.orange))),
                        DataColumn(label: Text('总评', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      ],
                      rows: _scores.map((s) {
                        final o1 = (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
                        final o2 = (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
                        final o3 = (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
                        final o4 = (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
                        return DataRow(cells: [
                          DataCell(Text(s['student_id']?.toString() ?? '', style: const TextStyle(fontSize: 10))),
                          DataCell(Text(s['student_name']?.toString() ?? '', style: const TextStyle(fontSize: 10))),
                          DataCell(Text(((s['exp1_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                          DataCell(Text(((s['exp2_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                          DataCell(Text(o1.toStringAsFixed(2), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: achievementLevelColor(o1)))),
                          DataCell(Text(((s['exp3_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                          DataCell(Text(((s['exp4_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                          DataCell(Text(o2.toStringAsFixed(2), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: achievementLevelColor(o2)))),
                          DataCell(Text(((s['exp5_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                          DataCell(Text(((s['exp6_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                          DataCell(Text(o3.toStringAsFixed(2), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: achievementLevelColor(o3)))),
                          DataCell(Text(((s['exp7_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                          DataCell(Text(o4.toStringAsFixed(2), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: achievementLevelColor(o4)))),
                          DataCell(Text(((s['total_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                        ]);
                      }).toList(),
                    ),
                  ),
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
  const ExamAchievementTab({required this.achievementDao});

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
  bool _generating = false;

  @override
  void initState() {
    super.initState();
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
          _loadScores();
        }
      });
    }
  }

  Future<void> _loadScores() async {
    if (_selectedBatchId == null) return;
    final scores = await widget.achievementDao.getExamScores(_selectedBatchId!);
    final avg = await widget.achievementDao.calculateExamClassAverage(_selectedBatchId!);
    if (mounted) {
      setState(() {
        sortScoresInPlace(scores, _sort);
        _scores = scores;
        _classAvg = avg;
      });
    }
  }

  Future<void> _generateDemo() async {
    if (_selectedBatchId == null) return;
    setState(() => _generating = true);
    try {
      await widget.achievementDao.generateExamDemoScores(_selectedBatchId!);
      await _loadScores();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('期末考核演示数据已生成'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
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
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _batches.map((b) => DropdownMenuItem<int>(
                    value: b['id'] as int,
                    child: Text(b['batch_name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                  )).toList(),
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
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _generating ? null : _generateDemo,
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('生成演示'),
              ),
            ],
          ),
        ),

        // 说明卡片
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: primary, size: 18),
                      const SizedBox(width: 8),
                      const Text('期末考核评价结构（权重50%）', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 项目(30%) → 课程目标1 ｜ 达成度 = 项目得分/100', style: TextStyle(fontSize: 12)),
                  const Text('• 小组(20%) → 课程目标2 ｜ 达成度 = 小组得分/100', style: TextStyle(fontSize: 12)),
                  const Text('• 个人(20%) → 课程目标3 ｜ 达成度 = 个人得分/100', style: TextStyle(fontSize: 12)),
                  const Text('• 答辩(30%) → 课程目标4 ｜ 达成度 = 答辩得分/100', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('总评 = 项目×0.3 + 小组×0.2 + 个人×0.2 + 答辩×0.3', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
            ),
          ),
        ),

        // 班级平均
        if (_classAvg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('班级平均指标点达成度', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (int i = 0; i < 4; i++)
                          Expanded(
                            child: Column(
                              children: [
                                Text('目标${i + 1}', style: TextStyle(fontSize: 11, color: kObjectiveColors[i])),
                                const SizedBox(height: 4),
                                Text(
                                  (_classAvg['obj${i + 1}'] ?? 0).toStringAsFixed(2),
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: achievementLevelColor(_classAvg['obj${i + 1}'] ?? 0)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    objectiveRadarChart(
                      [for (int i = 0; i < 4; i++) _classAvg['obj${i + 1}'] ?? 0],
                      Theme.of(context).colorScheme.primary,
                    ),
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
                      const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无期末考核数据', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('点击「生成演示」按钮创建示例数据', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 16,
                      headingRowHeight: 40,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 40,
                      columns: const [
                        DataColumn(label: Text('学号', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('姓名', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('项目(30%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('目标1达成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red))),
                        DataColumn(label: Text('小组(20%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('目标2达成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue))),
                        DataColumn(label: Text('个人(20%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('目标3达成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green))),
                        DataColumn(label: Text('答辩(30%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('目标4达成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange))),
                        DataColumn(label: Text('总评', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                      rows: _scores.map((s) {
                        final o1 = (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
                        final o2 = (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
                        final o3 = (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
                        final o4 = (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
                        return DataRow(cells: [
                          DataCell(Text(s['student_id']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                          DataCell(Text(s['student_name']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                          DataCell(Text(((s['project_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(o1.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: achievementLevelColor(o1)))),
                          DataCell(Text(((s['group_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(o2.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: achievementLevelColor(o2)))),
                          DataCell(Text(((s['individual_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(o3.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: achievementLevelColor(o3)))),
                          DataCell(Text(((s['defense_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(o4.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: achievementLevelColor(o4)))),
                          DataCell(Text(((s['total_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
