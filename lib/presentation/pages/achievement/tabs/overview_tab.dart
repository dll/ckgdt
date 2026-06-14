import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../../core/error_handler.dart';
import '../../../../data/local/achievement_dao.dart';
import '../../../../services/achievement/achievement_excel_service.dart';
import '../../../../services/auth_service.dart';
import '../achievement_shared.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1 — 达成度概览
// ══════════════════════════════════════════════════════════════════════════════

class AchievementOverviewTab extends StatefulWidget {
  final AuthService authService;
  final AchievementDao achievementDao;

  const AchievementOverviewTab({
    super.key,
    required this.authService,
    required this.achievementDao,
  });

  @override
  State<AchievementOverviewTab> createState() => _AchievementOverviewTabState();
}

class _AchievementOverviewTabState extends State<AchievementOverviewTab> {
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _objectives = [];
  bool _loading = true;
  String _currentCourseName = '移动应用开发';

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      // 从已有批次推断当前课程名；无批次时保留默认
      if (batches.isNotEmpty) {
        _currentCourseName =
            batches.first['course_name']?.toString() ?? '移动应用开发';
      }
      // 课程大纲(课程目标)是课程级数据，已导入则常驻显示
      final objectives =
          await widget.achievementDao.getCourseObjectives(_currentCourseName);
      if (mounted) {
        setState(() {
          _batches = batches;
          _objectives = objectives
              .where((o) => ((o['idx'] as num?)?.toInt() ?? 0) <= 4)
              .toList();
          _loading = false;
        });
      }
      // 数据不完整(chapters/experiments为空)时自动用内置大纲AI解析补全（仅默认课程）
      final needsAi = objectives.isEmpty ||
          objectives.every((o) => (o['chapters'] ?? '').toString().isEmpty);
      if (needsAi && _currentCourseName == '移动应用开发') {
        _autoParseBundledSyllabus();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 从内置资源自动 AI 解析大纲（数据不完整时自动触发，无需用户操作）
  Future<void> _autoParseBundledSyllabus() async {
    try {
      final raw = await rootBundle
          .loadString('assets/syllabus/软件+6+《移动应用开发》+教学大纲+刘东良+new.md');
      if (raw.trim().isEmpty) return;
      setState(() => _importing = true);
      final svc = AchievementExcelService.instance;
      var rows = await svc.aiExtractSyllabus(raw);
      // AI 不可用(无网络/超时)时回退正则解析，确保首次启动就有大纲数据
      if (rows.isEmpty) {
        rows = svc.syllabusToObjectiveRows(
            svc.parseSyllabusBytes(Uint8List.fromList(raw.codeUnits), 'md'));
      }
      if (rows.isNotEmpty) {
        await widget.achievementDao
            .saveCourseObjectives(_currentCourseName, rows);
        final objectives = (await widget.achievementDao
                .getCourseObjectives(_currentCourseName))
            .where((o) => ((o['idx'] as num?)?.toInt() ?? 0) <= 4)
            .toList();
        if (mounted) setState(() => _objectives = objectives);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Overview.autoParse', stack: st);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  bool _importing = false;

  /// 上传课程大纲（md/docx）→ 提取课程目标+权重 → 落库 course_objectives。
  Future<void> _uploadSyllabus() async {
    final svc = AchievementExcelService.instance;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'docx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final ext = (f.extension ?? '').toLowerCase();
      setState(() => _importing = true);
      Map<String, dynamic> parsed;
      if (f.bytes != null) {
        parsed = svc.parseSyllabusBytes(f.bytes!, ext);
      } else if (f.path != null) {
        parsed = await svc.parseSyllabus(f.path!);
      } else {
        throw StateError('无法读取文件内容');
      }
      if (parsed['error'] != null) throw StateError(parsed['error'] as String);
      // 先用平台确定性解析提取表格字段；AI 只补充缺失字段，不能覆盖权重/满分等关键值。
      final deterministicRows = svc.syllabusToObjectiveRows(parsed);
      List<Map<String, dynamic>> aiRows = const [];
      if (f.bytes != null) {
        final raw = svc.syllabusRawText(f.bytes!, ext);
        aiRows = await svc.aiExtractSyllabus(raw);
      }
      final rows = svc.mergeSyllabusRows(deterministicRows, aiRows);
      if (rows.isEmpty) throw StateError('未从大纲中识别到课程目标/权重');
      // 尝试从解析结果推断课程名（parsed 中可能含 'courseName' 字段）
      final parsedCourseName = parsed['courseName']?.toString().trim();
      if (parsedCourseName != null && parsedCourseName.isNotEmpty) {
        _currentCourseName = parsedCourseName;
      }
      if (!mounted) return;
      final edited = await _showSyllabusPreview(rows);
      if (edited == null) return; // 用户取消
      await _saveObjectiveRows(_currentCourseName, edited);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('大纲解析成功，已保存 ${edited.length} 个课程目标'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Overview.uploadSyllabus', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('大纲上传失败：$e，可手动录入关键对照表'),
              backgroundColor: Colors.red),
        );
      }
      if (mounted) {
        setState(() => _importing = false);
        await _openAssessmentMatrixEditor(
          initialRows: _defaultManualObjectiveRows(),
          title: '手动录入课程目标达成考核与评价方式及成绩评定对照表',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<List<Map<String, dynamic>>?> _showSyllabusPreview(
      List<Map<String, dynamic>> rows) {
    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => SyllabusPreviewDialog(rows: rows),
    );
  }

  Future<void> _saveObjectiveRows(
      String courseName, List<Map<String, dynamic>> rows) async {
    final normalizedCourseName =
        courseName.trim().isNotEmpty ? courseName.trim() : _currentCourseName;
    await widget.achievementDao
        .saveCourseObjectives(normalizedCourseName, rows);
    final batches = await widget.achievementDao.getBatches();
    final objectives =
        (await widget.achievementDao.getCourseObjectives(normalizedCourseName))
            .where((o) => ((o['idx'] as num?)?.toInt() ?? 0) <= 4)
            .toList();
    if (!mounted) return;
    setState(() {
      _currentCourseName = normalizedCourseName;
      _batches = batches;
      _objectives = objectives;
    });
  }

  List<Map<String, dynamic>> _defaultManualObjectiveRows() {
    return List.generate(4, (i) {
      final idx = i + 1;
      return {
        'idx': idx,
        'name': '课程目标$idx',
        'indicator': '',
        'weight': 0.0,
        'full_mark': 0.0,
        'pingshi_ratio': 0.20,
        'experiment_ratio': 0.30,
        'exam_ratio': 0.50,
        'description': '',
        'chapters': '',
        'experiments': '',
        'assess_content': '',
      };
    });
  }

  Future<void> _openAssessmentMatrixEditor({
    List<Map<String, dynamic>>? initialRows,
    String title = '编辑课程目标达成考核与评价方式及成绩评定对照表',
  }) async {
    final result = await showDialog<_SyllabusMatrixEditResult>(
      context: context,
      builder: (_) => SyllabusAssessmentMatrixDialog(
        title: title,
        courseName: _currentCourseName,
        rows: initialRows ?? _objectives,
      ),
    );
    if (result == null || result.rows.isEmpty) return;
    await _saveObjectiveRows(result.courseName, result.rows);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已保存 ${result.rows.length} 个课程目标对照表信息'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showCreateBatchDialog() {
    final nameCtrl = TextEditingController();
    final courseCtrl = TextEditingController(text: _currentCourseName);
    final classCtrl = TextEditingController();
    final semesterCtrl = TextEditingController(text: '2024-2025-2');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建达成度批次'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '批次名称',
                  hintText: '如：2024春季班',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: courseCtrl,
                decoration: const InputDecoration(
                  labelText: '课程名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: classCtrl,
                decoration: const InputDecoration(
                  labelText: '班级名称',
                  hintText: '如：软件工程2201',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: semesterCtrl,
                decoration: const InputDecoration(
                  labelText: '学期',
                  border: OutlineInputBorder(),
                ),
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
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入批次名称')),
                );
                return;
              }
              final teacherId =
                  widget.authService.currentUser?.userId ?? 'unknown';
              await widget.achievementDao.addBatch(
                batchName: nameCtrl.text.trim(),
                courseName: courseCtrl.text.trim(),
                className: classCtrl.text.trim(),
                semester: semesterCtrl.text.trim(),
                teacherId: teacherId,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadBatches();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBatch(int batchId, String batchName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除批次「$batchName」及其所有关联数据吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.achievementDao.deleteBatch(batchId);
      _loadBatches();
    }
  }

  void _navigateToBatchDetail(Map<String, dynamic> batch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => BatchDetailSheet(
          batch: batch,
          achievementDao: widget.achievementDao,
          scrollController: scrollCtrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        Column(children: [
          if (_importing) LinearProgressIndicator(color: primary),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadBatches,
              child: _batches.isEmpty
                  ? _buildEmptyState(primary)
                  : _buildBatchList(primary),
            ),
          ),
        ]),
        Positioned(
          right: 16,
          bottom: 16,
          child: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'create') _showCreateBatchDialog();
              if (v == 'syllabus') _uploadSyllabus();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'create',
                  child:
                      ListTile(leading: Icon(Icons.add), title: Text('新建批次'))),
              PopupMenuItem(
                  value: 'syllabus',
                  child: ListTile(
                      leading: Icon(Icons.description_outlined),
                      title: Text('上传课程大纲'))),
            ],
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3))
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(Color primary) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        _buildSyllabusCard(primary),
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 80, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              const Text(
                '暂无达成度批次',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                '上传课程大纲与成绩 Excel 开始使用',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _showCreateBatchDialog,
                icon: const Icon(Icons.add),
                label: const Text('新建批次'),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, indent: 40, endIndent: 40),
              const SizedBox(height: 12),
              const Text('从真实文档导入',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _importing ? null : _uploadSyllabus,
                icon: const Icon(Icons.description_outlined),
                label: const Text('上传课程大纲（md/docx）'),
              ),
              const SizedBox(height: 8),
              const Text('成绩导入请在「成绩管理」标签页操作',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  /// 常驻显示已导入的课程大纲（课程目标）。大纲已导入则直接展示，
  /// 大纲已导入则直接展示，无需用户操作；重新上传会刷新此卡片。
  Widget _buildSyllabusCard(Color primary) {
    if (_objectives.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.menu_book_outlined, color: primary, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('尚未导入课程大纲，点击右下角「上传课程大纲」导入大纲',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _importing
                  ? null
                  : () => _openAssessmentMatrixEditor(
                        initialRows: _defaultManualObjectiveRows(),
                        title: '手动录入课程目标达成考核与评价方式及成绩评定对照表',
                      ),
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('手动录入', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.menu_book, color: primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('课程大纲 · $_currentCourseName',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _importing ? null : _openAssessmentMatrixEditor,
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('编辑对照表', style: TextStyle(fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: _importing ? null : _uploadSyllabus,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新上传', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const Divider(height: 16),
          _buildAssessmentMatrixSummary(primary),
          const SizedBox(height: 12),
          for (int i = 0; i < _objectives.length; i++) ...[
            _buildObjectiveRow(_objectives[i], i),
            if (i < _objectives.length - 1) const SizedBox(height: 10),
          ],
        ]),
      ),
    );
  }

  Widget _buildObjectiveRow(Map<String, dynamic> o, int i) {
    final color = kObjectiveColors[i % kObjectiveColors.length];
    final weight = (o['weight'] as num?)?.toDouble() ?? 0;
    final indicator = (o['indicator'] ?? '').toString();
    final desc = (o['description'] ?? '').toString();
    final assess = (o['assess_content'] ?? '').toString();
    final chapters = (o['chapters'] ?? '').toString();
    final experiments = (o['experiments'] ?? '').toString();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          Text('目标${o['idx'] ?? i + 1}',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          Text('权重${(weight * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (desc.isNotEmpty)
            Text(desc, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 2),
          Text(
              [
                if (indicator.isNotEmpty) '支撑毕业要求 $indicator',
                if (assess.isNotEmpty) '考核：$assess',
              ].join(' · '),
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (chapters.isNotEmpty || experiments.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
                [
                  if (chapters.isNotEmpty) '章节：$chapters',
                  if (experiments.isNotEmpty) '实验：$experiments',
                ].join(' ｜ '),
                style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
          ],
        ]),
      ),
    ]);
  }

  Widget _buildAssessmentMatrixSummary(Color primary) {
    final totalWeight = _objectives.fold<double>(
        0, (s, r) => s + ((r['weight'] as num?)?.toDouble() ?? 0));
    final totalFull = _objectives.fold<double>(
        0, (s, r) => s + ((r['full_mark'] as num?)?.toDouble() ?? 0));
    final envColumns = <(String, String)>[
      if (_objectives
          .any((r) => ((r['pingshi_ratio'] as num?)?.toDouble() ?? 0) > 0))
        ('平时', 'pingshi_ratio'),
      if (_objectives
          .any((r) => ((r['experiment_ratio'] as num?)?.toDouble() ?? 0) > 0))
        ('实验', 'experiment_ratio'),
      if (_objectives
          .any((r) => ((r['exam_ratio'] as num?)?.toDouble() ?? 0) > 0))
        ('考核', 'exam_ratio'),
    ];
    if (envColumns.isEmpty) envColumns.add(('考核', 'exam_ratio'));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('课程目标达成考核与评价方式及成绩评定对照表',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowHeight: 34,
            dataRowMinHeight: 38,
            columns: [
              const DataColumn(label: Text('课程目标')),
              const DataColumn(label: Text('权重')),
              const DataColumn(label: Text('毕业要求')),
              for (final env in envColumns) DataColumn(label: Text(env.$1)),
            ],
            rows: [
              for (final row in _objectives)
                DataRow(cells: [
                  DataCell(Text('课程目标${row['idx']}')),
                  DataCell(Text(_formatWeight(row['weight']))),
                  DataCell(Text(_formatIndicator(row['indicator']))),
                  for (final env in envColumns)
                    DataCell(Text(_formatAssessmentCell(row, env.$2))),
                ]),
              DataRow(cells: [
                const DataCell(
                    Text('合计', style: TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(_formatWeight(totalWeight),
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                const DataCell(Text('')),
                for (final env in envColumns)
                  DataCell(Text(_formatTotalAssessmentCell(
                      totalFull, _objectives, env.$2))),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  String _formatWeight(Object? value) {
    final v = (value as num?)?.toDouble() ?? 0;
    if (v == 0) return '-';
    return _compactNumber(v);
  }

  String _formatIndicator(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return '-';
    return '支撑毕业要求 $text';
  }

  String _formatAssessmentCell(Map<String, dynamic> row, String ratioKey) {
    final full = (row['full_mark'] as num?)?.toDouble() ?? 0;
    final ratio = (row[ratioKey] as num?)?.toDouble() ?? 0;
    if (full == 0 || ratio <= 0) return '-';
    return '${_compactNumber(full)} (${_compactNumber(ratio * 100)}%)';
  }

  String _formatTotalAssessmentCell(
      double totalFull, List<Map<String, dynamic>> rows, String ratioKey) {
    if (rows.isEmpty || totalFull == 0) return '-';
    var full = 0.0;
    var weightedRatio = 0.0;
    for (final row in rows) {
      final rowFull = (row['full_mark'] as num?)?.toDouble() ?? 0;
      final ratio = (row[ratioKey] as num?)?.toDouble() ?? 0;
      if (rowFull <= 0 || ratio <= 0) continue;
      full += rowFull;
      weightedRatio += rowFull * ratio;
    }
    if (full <= 0) return '-';
    final ratio = weightedRatio / full;
    return '${_compactNumber(full)} (${_compactNumber(ratio * 100)}%)';
  }

  String _compactNumber(double value) {
    if ((value - value.roundToDouble()).abs() < 0.0001) {
      return value.round().toString();
    }
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  Widget _buildBatchList(Color primary) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _batches.length + 1,
      itemBuilder: (context, i) {
        // 批次列表在上，课程大纲卡片在末尾（上下互换）
        if (i == _batches.length) return _buildSyllabusCard(primary);
        final index = i;
        final batch = _batches[index];
        final status = batch['status'] as String? ?? 'draft';
        final studentCount = batch['student_count'] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _navigateToBatchDetail(batch),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          batch['batch_name'] ?? '未命名批次',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor(status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          statusLabel(status),
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor(status),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'delete', child: Text('删除')),
                        ],
                        onSelected: (v) {
                          if (v == 'delete') {
                            _deleteBatch(
                              batch['id'] as int,
                              batch['batch_name'] ?? '',
                            );
                          }
                        },
                        icon: const Icon(Icons.more_vert, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                      Icons.book_outlined, '课程', batch['course_name'] ?? '-'),
                  const SizedBox(height: 4),
                  _buildInfoRow(
                      Icons.class_outlined, '班级', batch['class_name'] ?? '-'),
                  const SizedBox(height: 4),
                  _buildInfoRow(
                      Icons.calendar_month, '学期', batch['semester'] ?? '-'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.people_outline, size: 16, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        '$studentCount 名学生',
                        style: TextStyle(fontSize: 13, color: primary),
                      ),
                      const Spacer(),
                      Text(
                        batch['created_at']?.toString().substring(0, 10) ?? '',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Text('$label：',
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── 批次详情底部弹窗 ──────────────────────────────────────────────────────────

class BatchDetailSheet extends StatefulWidget {
  final Map<String, dynamic> batch;
  final AchievementDao achievementDao;
  final ScrollController scrollController;

  const BatchDetailSheet({
    super.key,
    required this.batch,
    required this.achievementDao,
    required this.scrollController,
  });

  @override
  State<BatchDetailSheet> createState() => _BatchDetailSheetState();
}

class _BatchDetailSheetState extends State<BatchDetailSheet> {
  List<Map<String, dynamic>> _scores = [];
  Map<String, dynamic>? _results;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final batchId = widget.batch['id'] as int;
      // 批次本身已限定班级，不再按"默认班级"二次过滤
      // （否则概览卡片计数与详情人数不一致：卡片用原始 COUNT，详情被默认班过滤）
      final scores = await widget.achievementDao.getScoresByBatch(batchId);
      Map<String, dynamic>? results;
      try {
        results = await widget.achievementDao.getCalculationResults(batchId);
      } catch (e) {
        swallow(e, tag: 'AchievementOverview.getCalculationResults');
      }

      if (mounted) {
        setState(() {
          _scores = scores;
          _results = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 拖拽手柄
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.analytics, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.batch['batch_name'] ?? '批次详情',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 概要信息
                      _buildSummaryCard(),
                      const SizedBox(height: 16),
                      // 成绩列表
                      Text(
                        '学生成绩 (${_scores.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_scores.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('暂无成绩数据',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ..._scores.map(_buildScoreItem),
                      // 计算结果
                      if (_results != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '达成度计算结果',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _buildResultsSummary(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _detailRow('课程', widget.batch['course_name'] ?? '-'),
            _detailRow('班级', widget.batch['class_name'] ?? '-'),
            _detailRow('学期', widget.batch['semester'] ?? '-'),
            _detailRow('学生人数', '${_scores.length}'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildScoreItem(Map<String, dynamic> score) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    (score['student_name'] ?? '?').toString().substring(0, 1),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        score['student_id'] ?? '',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Text(
                  '总分: ${(score['total_score'] as num?)?.toDouble().toStringAsFixed(3) ?? '0.000'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(4, (i) {
                final key = 'obj${i + 1}_score';
                final val = (score[key] ?? 0).toDouble();
                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        '目标${i + 1}',
                        style:
                            TextStyle(fontSize: 11, color: kObjectiveColors[i]),
                      ),
                      Text(
                        val.toStringAsFixed(3),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: kObjectiveColors[i],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSummary() {
    if (_results == null) return const SizedBox.shrink();

    final objectives = List.generate(4, (i) {
      final key = 'obj${i + 1}_achievement';
      return (_results![key] ?? 0.0) as double;
    });
    final weighted = (_results!['weighted_achievement'] ?? 0.0) as double;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ...List.generate(
                4,
                (i) => _buildBarRow(
                    kObjectiveNames[i], objectives[i], kObjectiveColors[i])),
            const Divider(height: 24),
            _buildBarRow(
                '加权达成度', weighted, Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: achievementLevelColor(weighted).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                achievementLevel(weighted),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: achievementLevelColor(weighted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              '${(value * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 大纲解析预览（可编辑）────────────────────────────────────────────────────

class _SyllabusMatrixEditResult {
  const _SyllabusMatrixEditResult({
    required this.courseName,
    required this.rows,
  });

  final String courseName;
  final List<Map<String, dynamic>> rows;
}

class _ObjectiveEditRow {
  _ObjectiveEditRow(Map<String, dynamic> row)
      : idx = ((row['idx'] as num?)?.toInt() ?? 0).clamp(1, 4),
        description =
            TextEditingController(text: (row['description'] ?? '').toString()),
        weight = TextEditingController(text: (row['weight'] ?? 0).toString()),
        indicator =
            TextEditingController(text: (row['indicator'] ?? '').toString()),
        fullMark =
            TextEditingController(text: (row['full_mark'] ?? 0).toString()),
        pingshiRatio = TextEditingController(
            text: _ratioText(row['pingshi_ratio'] ?? 0.20)),
        experimentRatio = TextEditingController(
            text: _ratioText(row['experiment_ratio'] ?? 0.30)),
        examRatio =
            TextEditingController(text: _ratioText(row['exam_ratio'] ?? 0.50)),
        chapters =
            TextEditingController(text: (row['chapters'] ?? '').toString()),
        experiments =
            TextEditingController(text: (row['experiments'] ?? '').toString()),
        assessContent = TextEditingController(
            text: (row['assess_content'] ?? '').toString());

  int idx;
  final TextEditingController description;
  final TextEditingController weight;
  final TextEditingController indicator;
  final TextEditingController fullMark;
  final TextEditingController pingshiRatio;
  final TextEditingController experimentRatio;
  final TextEditingController examRatio;
  final TextEditingController chapters;
  final TextEditingController experiments;
  final TextEditingController assessContent;

  static String _ratioText(Object value) {
    final ratio = (value as num?)?.toDouble() ?? 0;
    final percent = ratio <= 1 ? ratio * 100 : ratio;
    if ((percent - percent.roundToDouble()).abs() < 0.0001) {
      return percent.round().toString();
    }
    return percent.toStringAsFixed(2);
  }

  Map<String, dynamic> toMap() {
    final pingshi = _parseRatio(pingshiRatio.text, 0.20);
    final experiment = _parseRatio(experimentRatio.text, 0.30);
    final exam = _parseRatio(examRatio.text, 0.50);
    final items = [
      if (pingshi > 0)
        {
          'label': '平时成绩',
          'kind': 'pingshi',
          'full': _parseNumber(fullMark.text),
          'ratio': pingshi
        },
      if (experiment > 0)
        {
          'label': '实验成绩',
          'kind': 'experiment',
          'full': _parseNumber(fullMark.text),
          'ratio': experiment
        },
      if (exam > 0)
        {
          'label': '考核成绩',
          'kind': 'exam',
          'full': _parseNumber(fullMark.text),
          'ratio': exam
        },
    ];
    return {
      'idx': idx,
      'name': '课程目标$idx',
      'description': description.text.trim(),
      'indicator': indicator.text.trim(),
      'weight': _parseNumber(weight.text),
      'full_mark': _parseNumber(fullMark.text),
      'pingshi_ratio': pingshi,
      'experiment_ratio': experiment,
      'exam_ratio': exam,
      'chapters': chapters.text.trim(),
      'experiments': experiments.text.trim(),
      'assess_content': assessContent.text.trim(),
      'assessment_items_json': jsonEncode(items),
    };
  }

  void dispose() {
    description.dispose();
    weight.dispose();
    indicator.dispose();
    fullMark.dispose();
    pingshiRatio.dispose();
    experimentRatio.dispose();
    examRatio.dispose();
    chapters.dispose();
    experiments.dispose();
    assessContent.dispose();
  }

  static double _parseNumber(String text) =>
      double.tryParse(text.trim()) ?? 0.0;

  static double _parseRatio(String text, double fallback) {
    final value = double.tryParse(text.trim());
    if (value == null) return fallback;
    return value > 1 ? value / 100 : value;
  }
}

class SyllabusAssessmentMatrixDialog extends StatefulWidget {
  const SyllabusAssessmentMatrixDialog({
    super.key,
    required this.title,
    required this.courseName,
    required this.rows,
  });

  final String title;
  final String courseName;
  final List<Map<String, dynamic>> rows;

  @override
  State<SyllabusAssessmentMatrixDialog> createState() =>
      _SyllabusAssessmentMatrixDialogState();
}

class _SyllabusAssessmentMatrixDialogState
    extends State<SyllabusAssessmentMatrixDialog> {
  late final TextEditingController _courseCtrl;
  late final List<_ObjectiveEditRow> _rows;

  @override
  void initState() {
    super.initState();
    _courseCtrl = TextEditingController(text: widget.courseName);
    final source = widget.rows.isEmpty
        ? List.generate(4, (i) => {'idx': i + 1})
        : widget.rows;
    _rows = source
        .map((row) => _ObjectiveEditRow(Map<String, dynamic>.from(row)))
        .toList()
      ..sort((a, b) => a.idx.compareTo(b.idx));
    _reindex();
  }

  @override
  void dispose() {
    _courseCtrl.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _reindex() {
    for (var i = 0; i < _rows.length; i++) {
      _rows[i].idx = i + 1;
    }
  }

  void _addRow() {
    if (_rows.length >= 4) return;
    setState(() {
      _rows.add(_ObjectiveEditRow({
        'idx': _rows.length + 1,
        'pingshi_ratio': 0.20,
        'experiment_ratio': 0.30,
        'exam_ratio': 0.50,
      }));
      _reindex();
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      final row = _rows.removeAt(index);
      row.dispose();
      _reindex();
    });
  }

  void _markNoExperimentCourse() {
    setState(() {
      for (final row in _rows) {
        final pingshi =
            _ObjectiveEditRow._parseRatio(row.pingshiRatio.text, 0.20);
        final exam = (1 - pingshi).clamp(0.0, 1.0);
        row.experimentRatio.text = '0';
        row.experiments.text = '';
        row.examRatio.text = _ObjectiveEditRow._ratioText(exam);
      }
    });
  }

  void _enableExperimentCourse() {
    setState(() {
      for (final row in _rows) {
        final pingshi =
            _ObjectiveEditRow._parseRatio(row.pingshiRatio.text, 0.20);
        const experiment = 0.30;
        final exam = (1 - pingshi - experiment).clamp(0.0, 1.0);
        row.experimentRatio.text = _ObjectiveEditRow._ratioText(experiment);
        row.examRatio.text = _ObjectiveEditRow._ratioText(exam);
      }
    });
  }

  double get _weightSum =>
      _rows.fold(0, (s, r) => s + (double.tryParse(r.weight.text) ?? 0));

  bool get _showExperimentColumns => _rows.any((row) =>
      _ObjectiveEditRow._parseRatio(row.experimentRatio.text, 0) > 0 ||
      row.experiments.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final showExperimentColumns = _showExperimentColumns;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 980,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _courseCtrl,
              decoration: const InputDecoration(
                labelText: '课程名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text('课程目标达成考核与评价方式及成绩评定对照表',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primary)),
              const Spacer(),
              TextButton.icon(
                onPressed: showExperimentColumns
                    ? _markNoExperimentCourse
                    : _enableExperimentCourse,
                icon: const Icon(Icons.science_outlined, size: 16),
                label: Text(showExperimentColumns ? '无实验' : '启用实验'),
              ),
              TextButton.icon(
                onPressed: _rows.length >= 4 ? null : _addRow,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新增目标'),
              ),
            ]),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                headingRowHeight: 34,
                dataRowMinHeight: 74,
                columns: [
                  const DataColumn(label: Text('课程目标')),
                  const DataColumn(label: Text('目标描述')),
                  const DataColumn(label: Text('权重')),
                  const DataColumn(label: Text('毕业要求')),
                  const DataColumn(label: Text('满分')),
                  const DataColumn(label: Text('平时%')),
                  if (showExperimentColumns)
                    const DataColumn(label: Text('实验%')),
                  const DataColumn(label: Text('考核%')),
                  const DataColumn(label: Text('章节')),
                  if (showExperimentColumns)
                    const DataColumn(label: Text('实验')),
                  const DataColumn(label: Text('考核内容')),
                  const DataColumn(label: Text('')),
                ],
                rows: [
                  for (var i = 0; i < _rows.length; i++)
                    DataRow(cells: [
                      DataCell(Text('课程目标${_rows[i].idx}')),
                      DataCell(_field(_rows[i].description, width: 260)),
                      DataCell(_field(_rows[i].weight, width: 72)),
                      DataCell(_field(_rows[i].indicator, width: 92)),
                      DataCell(_field(_rows[i].fullMark, width: 72)),
                      DataCell(_field(_rows[i].pingshiRatio, width: 66)),
                      if (showExperimentColumns)
                        DataCell(_field(_rows[i].experimentRatio, width: 66)),
                      DataCell(_field(_rows[i].examRatio, width: 66)),
                      DataCell(_field(_rows[i].chapters, width: 140)),
                      if (showExperimentColumns)
                        DataCell(_field(_rows[i].experiments, width: 140)),
                      DataCell(_field(_rows[i].assessContent, width: 220)),
                      DataCell(IconButton(
                        tooltip: '删除目标',
                        onPressed:
                            _rows.length <= 1 ? null : () => _removeRow(i),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      )),
                    ]),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                (_weightSum - 1.0).abs() < 0.001
                    ? Icons.check_circle
                    : Icons.warning_amber,
                size: 16,
                color: (_weightSum - 1.0).abs() < 0.001
                    ? Colors.green
                    : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                '权重合计 ${_weightSum.toStringAsFixed(2)}，比例字段填写 20 或 0.20 均可',
                style: TextStyle(
                  fontSize: 12,
                  color: (_weightSum - 1.0).abs() < 0.001
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              _SyllabusMatrixEditResult(
                courseName: _courseCtrl.text.trim(),
                rows: _rows.map((row) => row.toMap()).toList(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, {required double width}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: width >= 180 ? 3 : 1,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

/// 大纲解析出的课程目标在落库前的可编辑预览。
/// 用户可修正权重/指标点/满分；确认后返回编辑后的行，取消返回 null。
class SyllabusPreviewDialog extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const SyllabusPreviewDialog({super.key, required this.rows});

  @override
  State<SyllabusPreviewDialog> createState() => _SyllabusPreviewDialogState();
}

class _SyllabusPreviewDialogState extends State<SyllabusPreviewDialog> {
  late final List<Map<String, dynamic>> _rows = widget.rows
      .map((e) => Map<String, dynamic>.from(e))
      .where((o) =>
          ((o['idx'] as num?)?.toInt() ?? 0) >= 1 &&
          ((o['idx'] as num?)?.toInt() ?? 0) <= 4)
      .toList();
  late final List<TextEditingController> _weightCtrls;
  late final List<TextEditingController> _indicatorCtrls;
  late final List<TextEditingController> _fullMarkCtrls;
  late final List<TextEditingController> _chaptersCtrls;
  late final List<TextEditingController> _experimentsCtrls;

  @override
  void initState() {
    super.initState();
    _weightCtrls = _rows
        .map((r) => TextEditingController(text: (r['weight'] ?? 0).toString()))
        .toList();
    _indicatorCtrls = _rows
        .map((r) =>
            TextEditingController(text: (r['indicator'] ?? '').toString()))
        .toList();
    _fullMarkCtrls = _rows
        .map((r) =>
            TextEditingController(text: (r['full_mark'] ?? 0).toString()))
        .toList();
    _chaptersCtrls = _rows
        .map((r) =>
            TextEditingController(text: (r['chapters'] ?? '').toString()))
        .toList();
    _experimentsCtrls = _rows
        .map((r) =>
            TextEditingController(text: (r['experiments'] ?? '').toString()))
        .toList();
  }

  @override
  void dispose() {
    for (final c in [
      ..._weightCtrls,
      ..._indicatorCtrls,
      ..._fullMarkCtrls,
      ..._chaptersCtrls,
      ..._experimentsCtrls
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _weightSum =>
      _weightCtrls.fold(0.0, (s, c) => s + (double.tryParse(c.text) ?? 0));

  List<String> get _activeEnvKeys {
    final keys = [
      for (final key in ['pingshi', 'experiment', 'exam'])
        if (_rows.any((row) => _ratioFor(row, key) > 0)) key
    ];
    return keys.isEmpty ? ['exam'] : keys;
  }

  double _ratioFor(Map<String, dynamic> row, String key) {
    final directKey = switch (key) {
      'pingshi' => 'pingshi_ratio',
      'experiment' => 'experiment_ratio',
      _ => 'exam_ratio',
    };
    var value = (row[directKey] as num?)?.toDouble() ?? 0;
    if (value <= 0) {
      final rawJson = (row['assessment_items_json'] ?? '').toString();
      if (rawJson.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(rawJson) as List;
          for (final item in parsed) {
            final map = item as Map;
            final kind = (map['kind'] ?? '').toString();
            if (kind == key) {
              value += (map['ratio'] as num?)?.toDouble() ?? 0;
            }
          }
        } catch (e, st) {
          swallowDebug(e, tag: 'SyllabusPreview.assessmentItems', stack: st);
        }
      }
    }
    return value > 1 ? value / 100 : value;
  }

  String _envLabel(String key) {
    switch (key) {
      case 'pingshi':
        return '平时';
      case 'experiment':
        return '实验';
      default:
        return '考核';
    }
  }

  String _envCell(Map<String, dynamic> row, String key) {
    final ratio = _ratioFor(row, key);
    if (ratio <= 0) return '—';
    final fullMark = (row['full_mark'] as num?)?.toDouble() ?? 0;
    return '${fullMark.toInt()}分 / ${(ratio * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final sum = _weightSum;
    final sumOk = (sum - 1.0).abs() < 0.001;
    final activeEnvKeys = _activeEnvKeys;
    // 合成三个汇总表
    final hasExp =
        _rows.any((r) => (r['experiments'] ?? '').toString().isNotEmpty);
    final hasCh = _rows.any((r) => (r['chapters'] ?? '').toString().isNotEmpty);

    return AlertDialog(
      title: const Text('大纲 AI 解析结果'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ═══ 表1：课程目标达成考核与评价方式及成绩评定对照表 ═══
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('课程目标达成考核与评价方式及成绩评定对照表',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 12,
                          headingRowHeight: 32,
                          dataRowMinHeight: 28,
                          columns: [
                            const DataColumn(
                                label: Text('课程目标',
                                    style: TextStyle(fontSize: 11))),
                            const DataColumn(
                                label:
                                    Text('权重', style: TextStyle(fontSize: 11))),
                            for (final env in activeEnvKeys)
                              DataColumn(
                                  label: Text(_envLabel(env),
                                      style: const TextStyle(fontSize: 11))),
                            const DataColumn(
                                label: Text('指标点',
                                    style: TextStyle(fontSize: 11))),
                          ],
                          rows: _rows.map((r) {
                            return DataRow(cells: [
                              DataCell(Text('目标${r['idx']}',
                                  style: const TextStyle(fontSize: 11))),
                              DataCell(Text((r['weight'] ?? 0).toString(),
                                  style: const TextStyle(fontSize: 11))),
                              for (final env in activeEnvKeys)
                                DataCell(Text(_envCell(r, env),
                                    style: const TextStyle(fontSize: 11))),
                              DataCell(Text('${r['indicator'] ?? ''}',
                                  style: const TextStyle(fontSize: 11))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ]),
              ),

              // ═══ 表2：实验→目标分配 ═══
              if (hasExp) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.15)),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('实验项目与目标对应表',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: _rows
                                .where((r) => (r['experiments'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                .map((r) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: kObjectiveColors[
                                                (((r['idx'] as num?)?.toInt() ??
                                                            1) -
                                                        1)
                                                    .clamp(0, 3)]
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                          '目标${r['idx']} → ${r['experiments']}',
                                          style: const TextStyle(fontSize: 11)),
                                    ))
                                .toList()),
                      ]),
                ),
              ],

              // ═══ 表3：章节→目标分配 ═══
              if (hasCh) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('章节与教学安排→目标对应表',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: _rows
                                .where((r) =>
                                    (r['chapters'] ?? '').toString().isNotEmpty)
                                .map((r) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: kObjectiveColors[
                                                (((r['idx'] as num?)?.toInt() ??
                                                            1) -
                                                        1)
                                                    .clamp(0, 3)]
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                          '目标${r['idx']} → ${r['chapters']}',
                                          style: const TextStyle(fontSize: 11)),
                                    ))
                                .toList()),
                      ]),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // 以下：每个课程目标的详细信息（可编辑权重/指标点/满分）
              Text('各目标详情（确认或修正）',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 10),
              for (int i = 0; i < _rows.length; i++) ...[
                Text('课程目标${_rows[i]['idx'] ?? i + 1}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                if ((_rows[i]['description'] as String?)?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 4),
                  Text(_rows[i]['description'].toString(),
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                ],
                if ((_rows[i]['assess_content'] as String?)?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 2),
                  Text('考核内容：${_rows[i]['assess_content']}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
                const SizedBox(height: 4),
                TextField(
                  controller: _chaptersCtrls[i],
                  decoration: const InputDecoration(
                      labelText: '支撑章节',
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _experimentsCtrls[i],
                  decoration: const InputDecoration(
                      labelText: '支撑实验',
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
                if ((_rows[i]['pingshi_standard'] as String?)?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 2),
                  Text('平时标准：${_rows[i]['pingshi_standard']}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
                if ((_rows[i]['experiment_standard'] as String?)?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 2),
                  Text('实验标准：${_rows[i]['experiment_standard']}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _weightCtrls[i],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: '权重',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _indicatorCtrls[i],
                      decoration: const InputDecoration(
                          labelText: '指标点',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _fullMarkCtrls[i],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: '满分',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
              ],
              Row(children: [
                Icon(sumOk ? Icons.check_circle : Icons.warning_amber,
                    size: 16, color: sumOk ? Colors.green : Colors.orange),
                const SizedBox(width: 6),
                Text(
                    '权重合计 ${sum.toStringAsFixed(2)}${sumOk ? '' : '（建议为 1.00）'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: sumOk ? Colors.green : Colors.orange)),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            for (int i = 0; i < _rows.length; i++) {
              _rows[i]['weight'] =
                  double.tryParse(_weightCtrls[i].text) ?? _rows[i]['weight'];
              _rows[i]['indicator'] = _indicatorCtrls[i].text.trim();
              _rows[i]['full_mark'] = double.tryParse(_fullMarkCtrls[i].text) ??
                  _rows[i]['full_mark'];
              _rows[i]['chapters'] = _chaptersCtrls[i].text.trim();
              _rows[i]['experiments'] = _experimentsCtrls[i].text.trim();
            }
            Navigator.pop(context, _rows);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
