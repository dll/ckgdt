import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/achievement_dao.dart';
import '../../../../services/achievement/achievement_excel_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/default_class_service.dart';
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
  bool _loading = true;
  bool _generatingDemo = false;

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
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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
      final rows = svc.syllabusToObjectiveRows(parsed);
      if (rows.isEmpty) throw StateError('未从大纲中识别到课程目标/权重');
      if (!mounted) return;
      final ok = await _showSyllabusPreview(rows);
      if (ok != true) return;
      await widget.achievementDao.saveCourseObjectives('移动应用开发', rows);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('大纲解析成功，已保存 ${rows.length} 个课程目标'), backgroundColor: Colors.green),
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

  Future<bool?> _showSyllabusPreview(List<Map<String, dynamic>> rows) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('大纲解析结果'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('确认课程目标与权重无误后保存：', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '目标${r['idx']} · 指标点${r['indicator'] ?? '-'} · 权重${r['weight']} · 满分${r['full_mark']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
  }

  /// 上传学生成绩 Excel → 解析 →（选批次/新建）→ 导入 achievement_scores。
  Future<void> _uploadGrades() async {
    final svc = AchievementExcelService.instance;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      setState(() => _importing = true);
      List<Map<String, dynamic>> grades;
      if (f.bytes != null) {
        grades = svc.parseGradeBytes(f.bytes!);
      } else if (f.path != null) {
        grades = await svc.parseGradeFile(f.path!);
      } else {
        throw StateError('无法读取文件内容');
      }
      if (grades.isEmpty) throw StateError('未解析到学生成绩，请确认表格含「学生个体课程目标达成度」表');
      if (!mounted) return;
      final batchName = '导入成绩 ${DateTime.now().toString().substring(0, 16)}';
      final batchId = await widget.achievementDao.createBatch({
        'batch_name': batchName,
        'course_name': '移动应用开发',
        'class_name': '计科22',
        'teacher_id': widget.authService.getCurrentUserId() ?? '',
        'status': 'draft',
      });
      final count = await svc.importToDatabase(batchId, grades);
      await _loadBatches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成绩导入成功：$count/${grades.length} 名学生'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Overview.uploadGrades', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成绩上传失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _generateDemoData() async {
    setState(() => _generatingDemo = true);
    try {
      await widget.achievementDao.initDemoDataIfEmpty();
      await _loadBatches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('演示数据生成成功'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingDemo = false);
    }
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
              if (v == 'grades') _uploadGrades();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'create', child: ListTile(leading: Icon(Icons.add), title: Text('新建批次'))),
              PopupMenuItem(value: 'syllabus', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('上传课程大纲'))),
              PopupMenuItem(value: 'grades', child: ListTile(leading: Icon(Icons.upload_file), title: Text('上传成绩 Excel'))),
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
      children: [
        const SizedBox(height: 80),
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
                '创建批次或生成演示数据开始使用',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _generatingDemo ? null : _generateDemoData,
                icon: _generatingDemo
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_generatingDemo ? '生成中...' : '生成演示数据'),
              ),
              const SizedBox(height: 12),
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
              OutlinedButton.icon(
                onPressed: _importing ? null : _uploadGrades,
                icon: const Icon(Icons.upload_file),
                label: const Text('上传成绩 Excel（xlsx）'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBatchList(Color primary) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _batches.length,
      itemBuilder: (context, index) {
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
      final rawScores = await widget.achievementDao.getScoresByBatch(batchId);
      final scores = await DefaultClassService.instance.filterByDefaultClass(
          rawScores, (s) => (s['student_id'] ?? '').toString());
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
