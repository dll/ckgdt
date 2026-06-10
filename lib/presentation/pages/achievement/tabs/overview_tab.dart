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
  State<AchievementOverviewTab> createState() =>
      _AchievementOverviewTabState();
}

class _AchievementOverviewTabState extends State<AchievementOverviewTab> {
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _objectives = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      // 课程大纲(课程目标)是课程级数据，已导入则常驻显示
      final objectives =
          await widget.achievementDao.getCourseObjectives('移动应用开发');
      if (mounted) {
        setState(() {
          _batches = batches;
          _objectives = objectives.where((o) => ((o['idx'] as num?)?.toInt() ?? 0) <= 4).toList();
          _loading = false;
        });
      }
      // 数据不完整(chapters/experiments为空)时自动用内置大纲AI解析补全
      final needsAi = objectives.isEmpty ||
          objectives.every((o) => (o['chapters'] ?? '').toString().isEmpty);
      if (needsAi) {
        _autoParseBundledSyllabus();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 从内置资源自动 AI 解析大纲（数据不完整时自动触发，无需用户操作）
  Future<void> _autoParseBundledSyllabus() async {
    try {
      final raw = await rootBundle.loadString('assets/syllabus/软件+6+《移动应用开发》+教学大纲+刘东良+new.md');
      if (raw.trim().isEmpty) return;
      setState(() => _importing = true);
      final svc = AchievementExcelService.instance;
      final rows = await svc.aiExtractSyllabus(raw);
      if (rows.isNotEmpty) {
        await widget.achievementDao.saveCourseObjectives('移动应用开发', rows);
        final objectives = (await widget.achievementDao.getCourseObjectives('移动应用开发'))
            .where((o) => ((o['idx'] as num?)?.toInt() ?? 0) <= 4).toList();
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
      // 优先用 AI 全面解析(目标描述/指标点/权重/满分/章节/实验/三类评价标准)，
      // 失败再回退正则解析。
      List<Map<String, dynamic>> rows = const [];
      if (f.bytes != null) {
        final raw = svc.syllabusRawText(f.bytes!, ext);
        rows = await svc.aiExtractSyllabus(raw);
      }
      if (rows.isEmpty) {
        rows = svc.syllabusToObjectiveRows(parsed);
      }
      if (rows.isEmpty) throw StateError('未从大纲中识别到课程目标/权重');
      if (!mounted) return;
      final edited = await _showSyllabusPreview(rows);
      if (edited == null) return; // 用户取消
      await widget.achievementDao.saveCourseObjectives('移动应用开发', edited);
      await _loadBatches(); // 刷新常驻大纲展示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('大纲解析成功，已保存 ${edited.length} 个课程目标'), backgroundColor: Colors.green),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Overview.uploadSyllabus', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('大纲上传失败：$e'), backgroundColor: Colors.red),
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

  void _showCreateBatchDialog() {
    final nameCtrl = TextEditingController();
    final courseCtrl = TextEditingController(text: '移动应用开发');
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
        RefreshIndicator(
          onRefresh: _loadBatches,
          child: _batches.isEmpty ? _buildEmptyState(primary) : _buildBatchList(primary),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'create') _showCreateBatchDialog();
              if (v == 'syllabus') _uploadSyllabus();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'create', child: ListTile(leading: Icon(Icons.add), title: Text('新建批次'))),
              PopupMenuItem(value: 'syllabus', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('上传课程大纲'))),
            ],
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 3))],
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
              Icon(Icons.analytics_outlined, size: 80, color: Colors.grey.withValues(alpha: 0.5)),
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
              const Text('从真实文档导入', style: TextStyle(fontSize: 13, color: Colors.grey)),
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

  /// 常驻显示已导入的课程大纲（课程目标）。课程为《移动应用开发》，
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
              child: Text('尚未导入课程大纲，点击右下角「上传课程大纲」导入《移动应用开发》大纲',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
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
            const Expanded(
              child: Text('课程大纲 · 移动应用开发',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _importing ? null : _uploadSyllabus,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新上传', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const Divider(height: 16),
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
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
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
          Text([
            if (indicator.isNotEmpty) '支撑毕业要求 $indicator',
            if (assess.isNotEmpty) '考核：$assess',
          ].join(' · '), style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (chapters.isNotEmpty || experiments.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text([
              if (chapters.isNotEmpty) '章节：$chapters',
              if (experiments.isNotEmpty) '实验：$experiments',
            ].join(' ｜ '), style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
          ],
        ]),
      ),
    ]);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                          const PopupMenuItem(value: 'delete', child: Text('删除')),
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
                  _buildInfoRow(Icons.book_outlined, '课程', batch['course_name'] ?? '-'),
                  const SizedBox(height: 4),
                  _buildInfoRow(Icons.class_outlined, '班级', batch['class_name'] ?? '-'),
                  const SizedBox(height: 4),
                  _buildInfoRow(Icons.calendar_month, '学期', batch['semester'] ?? '-'),
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
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
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
        Text('$label：', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_scores.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('暂无成绩数据', style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ..._scores.map(_buildScoreItem),
                      // 计算结果
                      if (_results != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '达成度计算结果',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Text(
                  '总分: ${score['total_score'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                        style: TextStyle(fontSize: 11, color: kObjectiveColors[i]),
                      ),
                      Text(
                        val.toStringAsFixed(1),
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
            ...List.generate(4, (i) => _buildBarRow(kObjectiveNames[i], objectives[i], kObjectiveColors[i])),
            const Divider(height: 24),
            _buildBarRow('加权达成度', weighted, Theme.of(context).colorScheme.primary),
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
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 大纲解析预览（可编辑）────────────────────────────────────────────────────

/// 大纲解析出的课程目标在落库前的可编辑预览。
/// 用户可修正权重/指标点/满分；确认后返回编辑后的行，取消返回 null。
class SyllabusPreviewDialog extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const SyllabusPreviewDialog({super.key, required this.rows});

  @override
  State<SyllabusPreviewDialog> createState() => _SyllabusPreviewDialogState();
}

class _SyllabusPreviewDialogState extends State<SyllabusPreviewDialog> {
  late final List<Map<String, dynamic>> _rows =
      widget.rows
          .map((e) => Map<String, dynamic>.from(e))
          .where((o) => ((o['idx'] as num?)?.toInt() ?? 0) >= 1 && ((o['idx'] as num?)?.toInt() ?? 0) <= 4)
          .toList();
  late final List<TextEditingController> _weightCtrls;
  late final List<TextEditingController> _indicatorCtrls;
  late final List<TextEditingController> _fullMarkCtrls;

  @override
  void initState() {
    super.initState();
    _weightCtrls = _rows
        .map((r) => TextEditingController(text: (r['weight'] ?? 0).toString()))
        .toList();
    _indicatorCtrls = _rows
        .map((r) => TextEditingController(text: (r['indicator'] ?? '').toString()))
        .toList();
    _fullMarkCtrls = _rows
        .map((r) => TextEditingController(text: (r['full_mark'] ?? 0).toString()))
        .toList();
  }

  @override
  void dispose() {
    for (final c in [..._weightCtrls, ..._indicatorCtrls, ..._fullMarkCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _weightSum =>
      _weightCtrls.fold(0.0, (s, c) => s + (double.tryParse(c.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final sum = _weightSum;
    final sumOk = (sum - 1.0).abs() < 0.001;
    // 合成三个汇总表
    final hasExp = _rows.any((r) => (r['experiments'] ?? '').toString().isNotEmpty);
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('课程目标达成考核与评价方式及成绩评定对照表',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 12,
                      headingRowHeight: 32,
                      dataRowMinHeight: 28,
                      columns: const [
                        DataColumn(label: Text('课程目标', style: TextStyle(fontSize: 11))),
                        DataColumn(label: Text('权重', style: TextStyle(fontSize: 11))),
                        DataColumn(label: Text('平时(20%)', style: TextStyle(fontSize: 11))),
                        DataColumn(label: Text('实验(30%)', style: TextStyle(fontSize: 11))),
                        DataColumn(label: Text('期末(50%)', style: TextStyle(fontSize: 11))),
                        DataColumn(label: Text('指标点', style: TextStyle(fontSize: 11))),
                      ],
                      rows: _rows.map((r) {
                        final fm = (r['full_mark'] as num?)?.toDouble() ?? 0;
                        return DataRow(cells: [
                          DataCell(Text('目标${r['idx']}', style: const TextStyle(fontSize: 11))),
                          DataCell(Text((r['weight'] ?? 0).toString(), style: const TextStyle(fontSize: 11))),
                          DataCell(Text('${fm.toInt()}分', style: const TextStyle(fontSize: 11))),
                          DataCell(Text('${fm.toInt()}分', style: const TextStyle(fontSize: 11))),
                          DataCell(Text('${fm.toInt()}分', style: const TextStyle(fontSize: 11))),
                          DataCell(Text('${r['indicator'] ?? ''}', style: const TextStyle(fontSize: 11))),
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('实验项目与目标对应表',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, children: _rows.where((r) => (r['experiments'] ?? '').toString().isNotEmpty).map((r) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kObjectiveColors[(((r['idx'] as num?)?.toInt() ?? 1) - 1).clamp(0, 3)].withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('目标${r['idx']} → ${r['experiments']}',
                          style: const TextStyle(fontSize: 11)),
                    )).toList()),
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('章节与教学安排→目标对应表',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, children: _rows.where((r) => (r['chapters'] ?? '').toString().isNotEmpty).map((r) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kObjectiveColors[(((r['idx'] as num?)?.toInt() ?? 1) - 1).clamp(0, 3)].withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('目标${r['idx']} → ${r['chapters']}',
                          style: const TextStyle(fontSize: 11)),
                    )).toList()),
                  ]),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // 以下：每个课程目标的详细信息（可编辑权重/指标点/满分）
              Text('各目标详情（确认或修正）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 10),
              for (int i = 0; i < _rows.length; i++) ...[
                Text('课程目标${_rows[i]['idx'] ?? i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if ((_rows[i]['description'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(_rows[i]['description'].toString(),
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                ],
                if ((_rows[i]['assess_content'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text('考核内容：${_rows[i]['assess_content']}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
                if ((_rows[i]['chapters'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text('支撑章节：${_rows[i]['chapters']}',
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
                if ((_rows[i]['experiments'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text('支撑实验：${_rows[i]['experiments']}',
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
                if ((_rows[i]['pingshi_standard'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text('平时标准：${_rows[i]['pingshi_standard']}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
                if ((_rows[i]['experiment_standard'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text('实验标准：${_rows[i]['experiment_standard']}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _weightCtrls[i],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '权重', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _indicatorCtrls[i],
                      decoration: const InputDecoration(
                        labelText: '指标点', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _fullMarkCtrls[i],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '满分', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
              ],
              Row(children: [
                Icon(sumOk ? Icons.check_circle : Icons.warning_amber,
                    size: 16, color: sumOk ? Colors.green : Colors.orange),
                const SizedBox(width: 6),
                Text('权重合计 ${sum.toStringAsFixed(2)}${sumOk ? '' : '（建议为 1.00）'}',
                    style: TextStyle(fontSize: 12, color: sumOk ? Colors.green : Colors.orange)),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            for (int i = 0; i < _rows.length; i++) {
              _rows[i]['weight'] = double.tryParse(_weightCtrls[i].text) ?? _rows[i]['weight'];
              _rows[i]['indicator'] = _indicatorCtrls[i].text.trim();
              _rows[i]['full_mark'] = double.tryParse(_fullMarkCtrls[i].text) ?? _rows[i]['full_mark'];
            }
            Navigator.pop(context, _rows);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
