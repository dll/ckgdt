import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../services/auth_service.dart';

/// 课程达成度计算系统 — 参考 Python tkinter 版本
/// 三大子页: 达成度概览 / 成绩管理 / 报告生成
class AchievementPage extends StatefulWidget {
  const AchievementPage({super.key});

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _achievementDao = AchievementDao();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Container(
          color: primary.withValues(alpha: 0.05),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primary,
            tabs: const [
              Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: '达成度概览'),
              Tab(icon: Icon(Icons.edit_note, size: 18), text: '成绩管理'),
              Tab(icon: Icon(Icons.summarize_outlined, size: 18), text: '报告生成'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _AchievementOverviewTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              _ScoreManagementTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              _ReportTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 常量
// ══════════════════════════════════════════════════════════════════════════════

const _kObjectiveColors = [Colors.red, Colors.blue, Colors.green, Colors.orange];
const _kObjectiveNames = ['课程目标1', '课程目标2', '课程目标3', '课程目标4'];
const _kDefaultWeights = [0.15, 0.25, 0.30, 0.30];

Color _statusColor(String? status) {
  switch (status) {
    case 'completed':
      return Colors.green;
    case 'in_progress':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

String _statusLabel(String? status) {
  switch (status) {
    case 'completed':
      return '已完成';
    case 'in_progress':
      return '进行中';
    default:
      return '草稿';
  }
}

String _achievementLevel(double value) {
  if (value >= 0.9) return '优秀';
  if (value >= 0.7) return '良好';
  if (value >= 0.6) return '中等';
  return '未达成';
}

Color _achievementLevelColor(double value) {
  if (value >= 0.9) return Colors.green;
  if (value >= 0.7) return Colors.blue;
  if (value >= 0.6) return Colors.orange;
  return Colors.red;
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1 — 达成度概览
// ══════════════════════════════════════════════════════════════════════════════

class _AchievementOverviewTab extends StatefulWidget {
  final AuthService authService;
  final AchievementDao achievementDao;

  const _AchievementOverviewTab({
    required this.authService,
    required this.achievementDao,
  });

  @override
  State<_AchievementOverviewTab> createState() =>
      _AchievementOverviewTabState();
}

class _AchievementOverviewTabState extends State<_AchievementOverviewTab> {
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
        builder: (_, scrollCtrl) => _BatchDetailSheet(
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
          child: FloatingActionButton(
            heroTag: 'fab_overview',
            onPressed: _showCreateBatchDialog,
            backgroundColor: primary,
            child: const Icon(Icons.add, color: Colors.white),
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
                          color: _statusColor(status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            fontSize: 12,
                            color: _statusColor(status),
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

class _BatchDetailSheet extends StatefulWidget {
  final Map<String, dynamic> batch;
  final AchievementDao achievementDao;
  final ScrollController scrollController;

  const _BatchDetailSheet({
    required this.batch,
    required this.achievementDao,
    required this.scrollController,
  });

  @override
  State<_BatchDetailSheet> createState() => _BatchDetailSheetState();
}

class _BatchDetailSheetState extends State<_BatchDetailSheet> {
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
      final scores = await widget.achievementDao.getScoresByBatch(batchId);
      Map<String, dynamic>? results;
      try {
        results = await widget.achievementDao.getCalculationResults(batchId);
      } catch (_) {}

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
                        style: TextStyle(fontSize: 11, color: _kObjectiveColors[i]),
                      ),
                      Text(
                        val.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _kObjectiveColors[i],
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
            ...List.generate(4, (i) => _buildBarRow(_kObjectiveNames[i], objectives[i], _kObjectiveColors[i])),
            const Divider(height: 24),
            _buildBarRow('加权达成度', weighted, Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _achievementLevelColor(weighted).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _achievementLevel(weighted),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _achievementLevelColor(weighted),
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

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2 — 成绩管理
// ══════════════════════════════════════════════════════════════════════════════

class _ScoreManagementTab extends StatefulWidget {
  final AuthService authService;
  final AchievementDao achievementDao;

  const _ScoreManagementTab({
    required this.authService,
    required this.achievementDao,
  });

  @override
  State<_ScoreManagementTab> createState() => _ScoreManagementTabState();
}

class _ScoreManagementTabState extends State<_ScoreManagementTab> {
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

  void _showAddScoreDialog() {
    if (_selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择批次')),
      );
      return;
    }

    final studentIdCtrl = TextEditingController();
    final studentNameCtrl = TextEditingController();
    final obj1Ctrl = TextEditingController(text: '80');
    final obj2Ctrl = TextEditingController(text: '75');
    final obj3Ctrl = TextEditingController(text: '70');
    final obj4Ctrl = TextEditingController(text: '85');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加学生成绩'),
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
                  hintText: '如：张三',
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
              final total = o1 * _kDefaultWeights[0] +
                  o2 * _kDefaultWeights[1] +
                  o3 * _kDefaultWeights[2] +
                  o4 * _kDefaultWeights[3];

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
              if (ctx.mounted) Navigator.pop(ctx);
              _loadScores();
            },
            child: const Text('添加'),
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

  Future<void> _batchGenerateDemo() async {
    if (_selectedBatchId == null) return;
    setState(() => _generating = true);
    try {
      await widget.achievementDao.generateDemoScores(_selectedBatchId!);
      await _loadScores();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('演示成绩已批量录入'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录入失败：$e'), backgroundColor: Colors.red),
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
                    const SizedBox(width: 8),
                    _buildActionChip(
                      icon: Icons.group_add,
                      label: '批量录入',
                      onTap: _generating ? null : _batchGenerateDemo,
                      color: Colors.orange,
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
                      color: _kObjectiveColors[i].withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '目标${i + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            color: _kObjectiveColors[i],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          scoreVal.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _kObjectiveColors[i],
                          ),
                        ),
                        if (achieveVal > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '达成 ${(achieveVal * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 9, color: _kObjectiveColors[i]),
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
// Tab 3 — 报告生成
// ══════════════════════════════════════════════════════════════════════════════

class _ReportTab extends StatefulWidget {
  final AuthService authService;
  final AchievementDao achievementDao;

  const _ReportTab({
    required this.authService,
    required this.achievementDao,
  });

  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  bool _loadingBatches = true;
  bool _calculating = false;
  bool _generatingReport = false;

  // 计算结果
  Map<String, dynamic>? _calcResults;
  List<double> _objectiveAchievements = [0, 0, 0, 0];
  double _weightedAchievement = 0.0;
  Map<String, List<double>> _statistics = {}; // objectiveKey -> [mean, max, min, std]

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
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  Future<void> _calculateAchievement() async {
    if (_selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择批次')),
      );
      return;
    }

    setState(() {
      _calculating = true;
      _calcResults = null;
    });

    try {
      // 获取该批次所有成绩
      final scores = await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      if (scores.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('该批次无成绩数据，请先录入成绩'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _calculating = false);
        }
        return;
      }

      // 计算每个目标的达成度
      final objScores = List<List<double>>.generate(4, (i) {
        return scores.map<double>((s) {
          return (s['obj${i + 1}_score'] ?? 0).toDouble();
        }).toList();
      });

      final objAchievements = List<double>.generate(4, (i) {
        final values = objScores[i];
        final mean = values.reduce((a, b) => a + b) / values.length;
        return (mean / 100.0).clamp(0.0, 1.0);
      });

      // 加权达成度
      double weighted = 0;
      for (int i = 0; i < 4; i++) {
        weighted += objAchievements[i] * _kDefaultWeights[i];
      }

      // 统计数据：mean, max, min, std
      final stats = <String, List<double>>{};
      for (int i = 0; i < 4; i++) {
        final List<double> values = objScores[i];
        final mean = values.reduce((a, b) => a + b) / values.length;
        final maxVal = values.reduce(max<double>);
        final minVal = values.reduce(min<double>);
        final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
        final std = sqrt(variance);
        stats['objective${i + 1}'] = [mean, maxVal, minVal, std];
      }

      // 保存计算结果到数据库
      await widget.achievementDao.saveCalculationResults(
        batchId: _selectedBatchId!,
        objective1Achievement: objAchievements[0],
        objective2Achievement: objAchievements[1],
        objective3Achievement: objAchievements[2],
        objective4Achievement: objAchievements[3],
        weightedAchievement: weighted,
      );

      // 同时更新批次状态
      await widget.achievementDao.updateBatchStatus(_selectedBatchId!, 'completed');

      if (mounted) {
        setState(() {
          _objectiveAchievements = objAchievements;
          _weightedAchievement = weighted;
          _statistics = stats;
          _calcResults = {
            'student_count': scores.length,
            'batch_name': _batches.firstWhere(
              (b) => b['id'] == _selectedBatchId,
              orElse: () => {'batch_name': ''},
            )['batch_name'],
          };
          _calculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('计算失败：$e'), backgroundColor: Colors.red),
        );
        setState(() => _calculating = false);
      }
    }
  }

  Future<void> _generateMarkdownReport() async {
    if (_calcResults == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先计算达成度')),
      );
      return;
    }

    setState(() => _generatingReport = true);

    try {
      final batchName = _calcResults!['batch_name'] ?? '未命名';
      final batch = _batches.firstWhere(
        (b) => b['id'] == _selectedBatchId,
        orElse: () => <String, dynamic>{},
      );

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final buffer = StringBuffer();
      buffer.writeln('# 课程达成度计算报告');
      buffer.writeln();
      buffer.writeln('## 基本信息');
      buffer.writeln();
      buffer.writeln('| 项目 | 内容 |');
      buffer.writeln('|------|------|');
      buffer.writeln('| 批次名称 | $batchName |');
      buffer.writeln('| 课程名称 | ${batch['course_name'] ?? '-'} |');
      buffer.writeln('| 班级 | ${batch['class_name'] ?? '-'} |');
      buffer.writeln('| 学期 | ${batch['semester'] ?? '-'} |');
      buffer.writeln('| 学生人数 | ${_calcResults!['student_count']} |');
      buffer.writeln('| 生成日期 | $dateStr |');
      buffer.writeln();
      buffer.writeln('## 课程目标达成度');
      buffer.writeln();
      buffer.writeln('| 课程目标 | 权重 | 达成度 | 等级 |');
      buffer.writeln('|----------|------|--------|------|');
      for (int i = 0; i < 4; i++) {
        final w = _kDefaultWeights[i];
        final a = _objectiveAchievements[i];
        buffer.writeln(
          '| ${_kObjectiveNames[i]} | ${(w * 100).toStringAsFixed(0)}% | '
          '${(a * 100).toStringAsFixed(1)}% | ${_achievementLevel(a)} |',
        );
      }
      buffer.writeln();
      buffer.writeln('**加权总达成度：${(_weightedAchievement * 100).toStringAsFixed(1)}%**');
      buffer.writeln();
      buffer.writeln('**达成等级：${_achievementLevel(_weightedAchievement)}**');
      buffer.writeln();
      buffer.writeln('## 成绩统计');
      buffer.writeln();
      buffer.writeln('| 课程目标 | 平均分 | 最高分 | 最低分 | 标准差 |');
      buffer.writeln('|----------|--------|--------|--------|--------|');
      for (int i = 0; i < 4; i++) {
        final s = _statistics['objective${i + 1}'];
        if (s != null) {
          buffer.writeln(
            '| ${_kObjectiveNames[i]} | ${s[0].toStringAsFixed(1)} | '
            '${s[1].toStringAsFixed(1)} | ${s[2].toStringAsFixed(1)} | '
            '${s[3].toStringAsFixed(1)} |',
          );
        }
      }
      buffer.writeln();
      buffer.writeln('## 分析与建议');
      buffer.writeln();
      for (int i = 0; i < 4; i++) {
        final a = _objectiveAchievements[i];
        if (a < 0.6) {
          buffer.writeln('- ⚠️ ${_kObjectiveNames[i]}达成度为${(a * 100).toStringAsFixed(1)}%，未达标，需重点改进教学方法');
        } else if (a < 0.7) {
          buffer.writeln('- 📋 ${_kObjectiveNames[i]}达成度为${(a * 100).toStringAsFixed(1)}%，达标但有提升空间');
        } else {
          buffer.writeln('- ✅ ${_kObjectiveNames[i]}达成度为${(a * 100).toStringAsFixed(1)}%，表现${a >= 0.9 ? "优秀" : "良好"}');
        }
      }
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln('*报告由知识图谱教学系统自动生成*');

      final reportText = buffer.toString();

      if (mounted) {
        setState(() => _generatingReport = false);
        _showReportDialog(reportText);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generatingReport = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('报告生成失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showReportDialog(String reportText) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.description, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Markdown 报告')),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '复制到剪贴板',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: reportText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('报告已复制到剪贴板'), backgroundColor: Colors.green),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                reportText,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: reportText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('报告已复制到剪贴板'), backgroundColor: Colors.green),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制并关闭'),
          ),
        ],
      ),
    );
  }

  void _exportReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('导出功能将在后续版本中支持，敬请期待'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBatches) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 批次选择
          _buildBatchSelector(primary),
          const SizedBox(height: 16),

          // 操作按钮组
          _buildActionButtons(primary),
          const SizedBox(height: 16),

          // 计算中提示
          if (_calculating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在计算达成度...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),

          // 计算结果面板
          if (_calcResults != null && !_calculating) ...[
            _buildResultsPanel(primary),
            const SizedBox(height: 16),
            _buildStatisticsTable(primary),
          ],

          // 空状态
          if (_calcResults == null && !_calculating)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bar_chart, size: 80, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text(
                      '选择批次后点击"计算达成度"查看结果',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBatchSelector(Color primary) {
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
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(b['status'] as String?),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(b['batch_name'] ?? '未命名'),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            setState(() {
              _selectedBatchId = v;
              _calcResults = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildActionButtons(Color primary) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _calculating ? null : _calculateAchievement,
          icon: _calculating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.calculate, size: 18),
          label: Text(_calculating ? '计算中...' : '计算达成度'),
        ),
        OutlinedButton.icon(
          onPressed: (_calcResults != null && !_generatingReport)
              ? _generateMarkdownReport
              : null,
          icon: _generatingReport
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.description_outlined, size: 18),
          label: const Text('生成Markdown报告'),
        ),
        OutlinedButton.icon(
          onPressed: _calcResults != null ? _exportReport : null,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('导出报告'),
        ),
      ],
    );
  }

  Widget _buildResultsPanel(Color primary) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  '达成度计算结果',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_calcResults!['student_count']}人',
                    style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 四个课程目标达成度
            ...List.generate(4, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildAchievementBar(
                  label: _kObjectiveNames[i],
                  value: _objectiveAchievements[i],
                  weight: _kDefaultWeights[i],
                  color: _kObjectiveColors[i],
                ),
              );
            }),

            // 分割线
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              height: 1,
              color: Colors.grey.withValues(alpha: 0.2),
            ),

            // 加权总达成度
            _buildAchievementBar(
              label: '加权总达成度',
              value: _weightedAchievement,
              weight: 1.0,
              color: primary,
              isBold: true,
            ),

            const SizedBox(height: 16),

            // 达成等级徽章
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _achievementLevelColor(_weightedAchievement).withValues(alpha: 0.15),
                      _achievementLevelColor(_weightedAchievement).withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _achievementLevelColor(_weightedAchievement).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _weightedAchievement >= 0.7 ? Icons.emoji_events : Icons.info_outline,
                      color: _achievementLevelColor(_weightedAchievement),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '达成等级：${_achievementLevel(_weightedAchievement)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _achievementLevelColor(_weightedAchievement),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${(_weightedAchievement * 100).toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 14,
                        color: _achievementLevelColor(_weightedAchievement),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementBar({
    required String label,
    required double value,
    required double weight,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isBold ? 14 : 13,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (!isBold) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '权重${(weight * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        height: isBold ? 24 : 20,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(isBold ? 6 : 4),
                        ),
                      ),
                      Container(
                        height: isBold ? 24 : 20,
                        width: constraints.maxWidth * value.clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.8),
                              color.withValues(alpha: 0.5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(isBold ? 6 : 4),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 55,
              child: Text(
                '${(value * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: isBold ? 15 : 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatisticsTable(Color primary) {
    if (_statistics.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart, color: primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  '成绩统计分析',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 表头
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text('课程目标', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(flex: 2, child: Text('平均分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('最高分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('最低分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('标准差', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                ],
              ),
            ),
            // 数据行
            ...List.generate(4, (i) {
              final s = _statistics['objective${i + 1}'];
              if (s == null) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: i.isEven ? Colors.transparent : Colors.grey.withValues(alpha: 0.04),
                  border: i == 3
                      ? null
                      : Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _kObjectiveColors[i],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_kObjectiveNames[i], style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        s[0].toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        s[1].toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: Colors.green),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        s[2].toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        s[3].toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }),

            // 底部圆角
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.04),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
            ),

            const SizedBox(height: 16),

            // 各目标达成度对比迷你图
            const Text(
              '目标达成度对比',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(4, (i) {
                final achievement = _objectiveAchievements[i];
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kObjectiveColors[i].withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _kObjectiveColors[i].withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '目标${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _kObjectiveColors[i],
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: achievement.clamp(0.0, 1.0),
                                strokeWidth: 4,
                                backgroundColor: Colors.grey.withValues(alpha: 0.15),
                                color: _kObjectiveColors[i],
                              ),
                              Text(
                                '${(achievement * 100).toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _kObjectiveColors[i],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _achievementLevelColor(achievement).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _achievementLevel(achievement),
                            style: TextStyle(
                              fontSize: 9,
                              color: _achievementLevelColor(achievement),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
