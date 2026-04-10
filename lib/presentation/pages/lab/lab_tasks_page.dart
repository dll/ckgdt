import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/local/lab_task_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/gitee_service.dart';
import '../../../services/course_resource_service.dart';
import '../../../core/constants/app_theme.dart';
import '../admin/repo_detail_page.dart';

/// 实验任务页面
/// 学生: 4 Tab（任务列表 / 我的提交 / 实验报告 / 仓库报表）
/// 教师/管理员: 5 Tab（任务列表 / 提交管理 / 实验报告 / 任务管理 / 仓库报表）
class LabTasksPage extends StatefulWidget {
  const LabTasksPage({super.key});

  @override
  State<LabTasksPage> createState() => _LabTasksPageState();
}

class _LabTasksPageState extends State<LabTasksPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _labTaskDao = LabTaskDao();
  bool _initialized = false;

  bool get _isTeacherOrAdmin => _authService.isTeacher || _authService.isAdmin;

  @override
  void initState() {
    super.initState();
    final tabCount = _isTeacherOrAdmin ? 5 : 4;
    _tabController = TabController(length: tabCount, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    try {
      await _labTaskDao.initDemoDataIfEmpty();
    } catch (_) {}
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Tab 栏
        Container(
          color: primary.withValues(alpha: 0.05),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primary,
            tabs: [
              const Tab(icon: Icon(Icons.science, size: 18), text: '任务列表'),
              Tab(
                icon: const Icon(Icons.assignment_turned_in, size: 18),
                text: _isTeacherOrAdmin ? '提交管理' : '我的提交',
              ),
              const Tab(icon: Icon(Icons.description, size: 18), text: '实验报告'),
              if (!_isTeacherOrAdmin)
                const Tab(icon: Icon(Icons.analytics, size: 18), text: '仓库报表'),
              if (_isTeacherOrAdmin)
                const Tab(icon: Icon(Icons.settings, size: 18), text: '任务管理'),
              if (_isTeacherOrAdmin)
                const Tab(icon: Icon(Icons.analytics, size: 18), text: '仓库报表'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _TaskListTab(authService: _authService, labTaskDao: _labTaskDao),
              _SubmissionTab(
                  authService: _authService, labTaskDao: _labTaskDao),
              _ReportTab(authService: _authService, labTaskDao: _labTaskDao),
              if (!_isTeacherOrAdmin)
                _StudentRepoTab(authService: _authService),
              if (_isTeacherOrAdmin)
                _TaskManageTab(
                    authService: _authService, labTaskDao: _labTaskDao),
              if (_isTeacherOrAdmin) const _RepoReportTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1: 任务列表
// ══════════════════════════════════════════════════════════════════════════════

class _TaskListTab extends StatefulWidget {
  final AuthService authService;
  final LabTaskDao labTaskDao;
  const _TaskListTab({required this.authService, required this.labTaskDao});

  @override
  State<_TaskListTab> createState() => _TaskListTabState();
}

class _TaskListTabState extends State<_TaskListTab> {
  List<Map<String, dynamic>> _tasks = [];
  Map<int, Map<String, dynamic>?> _submissionCache = {};
  Map<int, Map<String, dynamic>> _statsCache = {};
  bool _isLoading = true;
  String _selectedChapter = '全部';

  bool get _isTeacherOrAdmin =>
      widget.authService.isTeacher || widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final tasks = await widget.labTaskDao.getTasks(status: 'active');
      final userId = widget.authService.getCurrentUserId();

      final subCache = <int, Map<String, dynamic>?>{};
      final statsCache = <int, Map<String, dynamic>>{};
      for (final task in tasks) {
        final taskId = task['id'] as int;
        if (_isTeacherOrAdmin) {
          statsCache[taskId] = await widget.labTaskDao.getTaskStats(taskId);
        } else if (userId != null) {
          subCache[taskId] =
              await widget.labTaskDao.getSubmission(taskId, userId);
        }
      }

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _submissionCache = subCache;
          _statsCache = statsCache;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredTasks {
    if (_selectedChapter == '全部') return _tasks;
    return _tasks.where((t) => t['chapter'] == _selectedChapter).toList();
  }

  List<String> get _chapters {
    final set = <String>{'全部'};
    for (final t in _tasks) {
      final ch = t['chapter'] as String?;
      if (ch != null && ch.isNotEmpty) set.add(ch);
    }
    final list = set.toList();
    list.sort((a, b) {
      if (a == '全部') return -1;
      if (b == '全部') return 1;
      return a.compareTo(b);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTasks;

    return Column(
      children: [
        // 章节筛选
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: _chapters.map((ch) {
              final selected = _selectedChapter == ch;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(ch, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedChapter = ch),
                  showCheckmark: false,
                  selectedColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.15),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.science_outlined,
                              size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('暂无实验任务',
                              style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadTasks,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) =>
                            _buildTaskCard(context, filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(BuildContext context, Map<String, dynamic> task) {
    final gradient = AppGradientTheme.of(context).linearGradient;
    final taskId = task['id'] as int;
    final title = task['title'] as String? ?? '';
    final chapter = task['chapter'] as String? ?? '';
    final difficulty = task['difficulty'] as String? ?? '中等';
    final maxScore = task['max_score'] as int? ?? 100;
    final dueDate = task['due_date'] as String?;

    // 学生提交状态
    String? submissionStatus;
    if (!_isTeacherOrAdmin) {
      final sub = _submissionCache[taskId];
      submissionStatus =
          sub == null ? '未提交' : (sub['status'] as String? ?? '已提交');
    }

    // 教师统计
    final stats = _statsCache[taskId];

    // 截止日期
    String dueDateDisplay = '';
    Color dueDateColor = Colors.grey;
    if (dueDate != null) {
      try {
        final due = DateTime.parse(dueDate);
        final diff = due.difference(DateTime.now()).inDays;
        if (diff < 0) {
          dueDateDisplay = '已截止';
          dueDateColor = Colors.red;
        } else if (diff == 0) {
          dueDateDisplay = '今天截止';
          dueDateColor = Colors.orange;
        } else if (diff <= 3) {
          dueDateDisplay = '剩余${diff}天';
          dueDateColor = Colors.orange;
        } else {
          dueDateDisplay = '剩余${diff}天';
          dueDateColor = Colors.green;
        }
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showTaskDetail(context, task),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 6, decoration: BoxDecoration(gradient: gradient)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      _buildDifficultyChip(difficulty),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (chapter.isNotEmpty) ...[
                        Icon(Icons.book, size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(chapter,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                        const SizedBox(width: 12),
                      ],
                      Icon(Icons.star, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text('满分$maxScore',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500])),
                      const Spacer(),
                      if (dueDateDisplay.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: dueDateColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule,
                                  size: 12, color: dueDateColor),
                              const SizedBox(width: 4),
                              Text(dueDateDisplay,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: dueDateColor,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!_isTeacherOrAdmin && submissionStatus != null)
                    _buildStudentStatusRow(submissionStatus),
                  if (_isTeacherOrAdmin && stats != null)
                    _buildTeacherStatsRow(stats),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentStatusRow(String status) {
    final statusColor = switch (status) {
      '已批改' => Colors.green,
      '已提交' => Colors.blue,
      _ => Colors.orange,
    };
    final statusIcon = switch (status) {
      '已批改' => Icons.check_circle,
      '已提交' => Icons.upload_file,
      _ => Icons.pending,
    };
    return Row(
      children: [
        Icon(statusIcon, size: 14, color: statusColor),
        const SizedBox(width: 4),
        Text(status,
            style: TextStyle(
                fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildTeacherStatsRow(Map<String, dynamic> stats) {
    final total = (stats['total_submissions'] as int?) ?? 0;
    final graded = (stats['graded_count'] as int?) ?? 0;
    final avg = (stats['avg_score'] as num?)?.toDouble() ?? 0.0;
    return Row(
      children: [
        Icon(Icons.people, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text('$total人提交',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(width: 12),
        Icon(Icons.grading, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text('$graded人已批改',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        if (avg > 0) ...[
          const SizedBox(width: 12),
          Icon(Icons.analytics, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text('均分${avg.toStringAsFixed(1)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ],
    );
  }

  Widget _buildDifficultyChip(String difficulty) {
    final color = switch (difficulty) {
      '简单' => Colors.green,
      '中等' => Colors.orange,
      '较难' => Colors.red,
      '困难' => Colors.purple,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(difficulty,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  void _showTaskDetail(BuildContext context, Map<String, dynamic> task) {
    final primary = Theme.of(context).colorScheme.primary;
    final taskId = task['id'] as int;
    final title = task['title'] as String? ?? '';
    final chapter = task['chapter'] as String? ?? '';
    final description = task['description'] as String? ?? '暂无描述';
    final requirements = task['requirements'] as String? ?? '暂无要求';
    final deliverables = task['deliverables'] as String? ?? '暂无说明';
    final difficulty = task['difficulty'] as String? ?? '中等';
    final maxScore = task['max_score'] as int? ?? 100;
    final dueDate = task['due_date'] as String?;
    final userId = widget.authService.getCurrentUserId();
    final isStudent = !_isTeacherOrAdmin;
    final submission = _submissionCache[taskId];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) {
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  _buildDifficultyChip(difficulty),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (chapter.isNotEmpty)
                    _detailChip(Icons.book, chapter, primary),
                  _detailChip(Icons.star, '满分$maxScore', primary),
                  if (dueDate != null)
                    _detailChip(Icons.schedule,
                        '截止: ${dueDate.substring(0, 10)}', primary),
                ],
              ),
              const Divider(height: 24),
              _sectionHeader('任务描述', Icons.info_outline, primary),
              const SizedBox(height: 8),
              Text(description,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              const SizedBox(height: 16),
              _sectionHeader('实验要求', Icons.checklist, primary),
              const SizedBox(height: 8),
              Text(requirements,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              const SizedBox(height: 16),
              _sectionHeader('提交物', Icons.folder_open, primary),
              const SizedBox(height: 8),
              Text(deliverables,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              if (isStudent && submission != null) ...[
                const Divider(height: 24),
                if (submission['status'] == '已批改') ...[
                  _sectionHeader('批改结果', Icons.grading, Colors.green),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('得分: ',
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[700])),
                      Text('${submission['score']}/$maxScore',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                  if (submission['feedback'] != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.green.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('教师反馈',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700])),
                          const SizedBox(height: 4),
                          Text(submission['feedback'] as String,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[700])),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  _sectionHeader('提交状态', Icons.upload_file, Colors.blue),
                  const SizedBox(height: 8),
                  Text('已提交，等待批改',
                      style: TextStyle(fontSize: 14, color: Colors.blue[700])),
                ],
              ],
              const SizedBox(height: 20),
              if (isStudent && userId != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showSubmitDialog(context, task);
                    },
                    icon: Icon(
                        submission == null ? Icons.upload_file : Icons.edit),
                    label: Text(submission == null ? '提交实验' : '修改提交'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  void _showSubmitDialog(BuildContext context, Map<String, dynamic> task) {
    final taskId = task['id'] as int;
    final userId = widget.authService.getCurrentUserId();
    final contentCtrl = TextEditingController();
    bool isSubmitting = false;

    final existing = _submissionCache[taskId];
    if (existing != null) {
      contentCtrl.text = existing['content'] as String? ?? '';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.upload_file, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('提交实验 - ${task['title']}',
                    style: const TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: contentCtrl,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: '实验总结 *',
                      hintText: '请简要描述实验完成情况、遇到的问题及解决方案...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('文件上传功能将在后续版本中开放')),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey[300]!, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey[50],
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.cloud_upload_outlined,
                              size: 36, color: Colors.grey[400]),
                          const SizedBox(height: 6),
                          Text('点击上传附件',
                              style: TextStyle(color: Colors.grey[500])),
                          const SizedBox(height: 4),
                          Text('支持 ZIP/PDF/图片 格式',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[400])),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (contentCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请填写实验总结')),
                        );
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      try {
                        await widget.labTaskDao.submitTask(
                          taskId: taskId,
                          userId: userId!,
                          content: contentCtrl.text.trim(),
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('提交成功！'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadTasks();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('提交失败: $e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isSubmitting = false);
                        }
                      }
                    },
              icon: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(isSubmitting ? '提交中...' : '提交'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2: 我的提交 / 提交管理
// ══════════════════════════════════════════════════════════════════════════════

class _SubmissionTab extends StatefulWidget {
  final AuthService authService;
  final LabTaskDao labTaskDao;
  const _SubmissionTab({required this.authService, required this.labTaskDao});

  @override
  State<_SubmissionTab> createState() => _SubmissionTabState();
}

class _SubmissionTabState extends State<_SubmissionTab> {
  List<Map<String, dynamic>> _submissions = [];
  bool _isLoading = true;

  bool get _isTeacherOrAdmin =>
      widget.authService.isTeacher || widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> submissions;
      if (_isTeacherOrAdmin) {
        submissions = await widget.labTaskDao.getSubmissions();
      } else {
        final userId = widget.authService.getCurrentUserId();
        submissions = userId != null
            ? await widget.labTaskDao.getSubmissions(userId: userId)
            : [];
      }
      if (mounted) {
        setState(() {
          _submissions = submissions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: _loadSubmissions,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _submissions.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(_isTeacherOrAdmin ? '暂无学生提交' : '暂无提交记录',
                              style: TextStyle(color: Colors.grey[500])),
                          if (!_isTeacherOrAdmin) ...[
                            const SizedBox(height: 8),
                            Text('请在"任务列表"中选择任务进行提交',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[400])),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : _isTeacherOrAdmin
                  ? _buildTeacherSubmissionList(primary)
                  : _buildStudentSubmissionList(primary),
    );
  }

  Widget _buildStudentSubmissionList(Color primary) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _submissions.length,
      itemBuilder: (ctx, i) {
        final sub = _submissions[i];
        final status = sub['status'] as String? ?? '已提交';
        final score = sub['score'] as int?;
        final taskTitle = sub['task_title'] as String? ?? '';
        final chapter = sub['chapter'] as String? ?? '';
        final maxScore = sub['max_score'] as int? ?? 100;
        final submitTime = sub['submit_time'] as String? ?? '';

        final statusColor = switch (status) {
          '已批改' => Colors.green,
          '已提交' => Colors.blue,
          _ => Colors.orange,
        };
        final statusIcon = switch (status) {
          '已批改' => Icons.check_circle,
          '已提交' => Icons.hourglass_top,
          _ => Icons.pending,
        };

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showSubmissionDetail(sub),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: statusColor.withValues(alpha: 0.1),
                        child: Icon(statusIcon, color: statusColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(taskTitle,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                                '$chapter · 提交于 ${submitTime.isNotEmpty ? submitTime.substring(0, 10) : ""}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[500])),
                          ],
                        ),
                      ),
                      if (score != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _scoreColor(score, maxScore)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$score/$maxScore',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _scoreColor(score, maxScore))),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(status,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor,
                                  fontWeight: FontWeight.w500)),
                        ),
                    ],
                  ),
                  if (sub['feedback'] != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.comment,
                              size: 14, color: Colors.green[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(sub['feedback'] as String,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeacherSubmissionList(Color primary) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final sub in _submissions) {
      final key = sub['task_title'] as String? ?? '未知任务';
      grouped.putIfAbsent(key, () => []).add(sub);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.amber.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber[800], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('点击提交卡片可进行批改评分',
                      style: TextStyle(fontSize: 13, color: Colors.amber[800])),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Row(
                  children: [
                    Icon(Icons.science, size: 16, color: primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(entry.key,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: primary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${entry.value.length}人提交',
                          style: TextStyle(fontSize: 11, color: primary)),
                    ),
                  ],
                ),
              ),
              ...entry.value.map((sub) => _buildTeacherSubmissionCard(sub)),
              const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildTeacherSubmissionCard(Map<String, dynamic> sub) {
    final status = sub['status'] as String? ?? '已提交';
    final score = sub['score'] as int?;
    final userName = sub['user_name'] as String? ?? sub['user_id'] ?? '';
    final submitTime = sub['submit_time'] as String? ?? '';
    final maxScore = sub['max_score'] as int? ?? 100;
    final isGraded = status == '已批改';
    final statusColor = isGraded ? Colors.green : Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showGradeDialog(sub),
        child: ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: statusColor.withValues(alpha: 0.1),
            child: Text(userName.isNotEmpty ? userName.substring(0, 1) : '?',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: statusColor)),
          ),
          title: Text(userName,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
              '提交于 ${submitTime.isNotEmpty ? submitTime.substring(0, 10) : "未知"}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          trailing: isGraded && score != null
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _scoreColor(score, maxScore).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$score分',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _scoreColor(score, maxScore))),
                )
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('待批改',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500)),
                ),
        ),
      ),
    );
  }

  void _showSubmissionDetail(Map<String, dynamic> sub) {
    final primary = Theme.of(context).colorScheme.primary;
    final content = sub['content'] as String? ?? '';
    final taskTitle = sub['task_title'] as String? ?? '';
    final score = sub['score'] as int?;
    final maxScore = sub['max_score'] as int? ?? 100;
    final feedback = sub['feedback'] as String?;
    final submitTime = sub['submit_time'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(taskTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                '提交时间: ${submitTime.isNotEmpty ? submitTime.substring(0, 16).replaceAll('T', ' ') : ""}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const Divider(height: 24),
            Text('实验总结',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(height: 8),
            Text(content.isNotEmpty ? content : '（无内容）',
                style: TextStyle(fontSize: 14, color: Colors.grey[700])),
            if (score != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Text('成绩: ',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: primary)),
                  Text('$score/$maxScore',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _scoreColor(score, maxScore))),
                ],
              ),
            ],
            if (feedback != null && feedback.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('教师反馈',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700])),
                    const SizedBox(height: 6),
                    Text(feedback,
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[700])),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showGradeDialog(Map<String, dynamic> submission) {
    final submissionId = submission['id'] as int;
    final userName =
        submission['user_name'] as String? ?? submission['user_id'] ?? '';
    final content = submission['content'] as String? ?? '';
    final maxScore = submission['max_score'] as int? ?? 100;
    final existingScore = submission['score'] as int?;
    final existingFeedback = submission['feedback'] as String?;

    double scoreValue = (existingScore ?? 80).toDouble();
    final feedbackCtrl = TextEditingController(text: existingFeedback ?? '');
    bool isGrading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.grading, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('批改 - $userName',
                    style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.isNotEmpty) ...[
                    Text('学生提交内容:',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700])),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(content,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      const Text('评分',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${scoreValue.round()} / $maxScore',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color:
                                  _scoreColor(scoreValue.round(), maxScore))),
                    ],
                  ),
                  Slider(
                    value: scoreValue,
                    min: 0,
                    max: maxScore.toDouble(),
                    divisions: maxScore,
                    label: '${scoreValue.round()}',
                    onChanged: (v) => setDialogState(() => scoreValue = v),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [60, 70, 80, 85, 90, 95, 100].map((v) {
                      final clamped = v > maxScore ? maxScore : v;
                      final isSelected = scoreValue.round() == clamped;
                      return ActionChip(
                        label: Text('$clamped',
                            style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.white : null)),
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        onPressed: () => setDialogState(
                            () => scoreValue = clamped.toDouble()),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: feedbackCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '教师反馈',
                      hintText: '请输入批改意见和建议...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              onPressed: isGrading
                  ? null
                  : () async {
                      setDialogState(() => isGrading = true);
                      try {
                        await widget.labTaskDao.gradeSubmission(
                          submissionId,
                          score: scoreValue.round(),
                          feedback: feedbackCtrl.text.trim().isNotEmpty
                              ? feedbackCtrl.text.trim()
                              : null,
                          scorerId: widget.authService.getCurrentUserId(),
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('批改成功！'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadSubmissions();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('批改失败: $e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isGrading = false);
                        }
                      }
                    },
              icon: isGrading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(isGrading ? '提交中...' : '提交评分'),
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int score, int maxScore) {
    final ratio = maxScore > 0 ? score / maxScore : 0.0;
    if (ratio >= 0.9) return Colors.green;
    if (ratio >= 0.8) return Colors.blue;
    if (ratio >= 0.6) return Colors.orange;
    return Colors.red;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 3: 实验报告
// ══════════════════════════════════════════════════════════════════════════════

class _ReportTab extends StatefulWidget {
  final AuthService authService;
  final LabTaskDao labTaskDao;
  const _ReportTab({required this.authService, required this.labTaskDao});

  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> {
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = widget.authService.getCurrentUserId();
      debugPrint('=== _ReportTab: Loading reports for userId=$userId');

      List<Map<String, dynamic>> reports;
      if (userId != null && userId.isNotEmpty) {
        reports = await widget.labTaskDao.getStudentReports(userId: userId);
      } else {
        debugPrint('=== _ReportTab: userId is null/empty, loading all reports');
        reports = await widget.labTaskDao.getStudentReports();
      }

      final templates = await widget.labTaskDao.getReportTemplates();

      debugPrint('=== _ReportTab: Loaded ${reports.length} reports');
      for (final r in reports) {
        debugPrint(
            '  - Report: ${r['title']}, status=${r['status']}, user_id=${r['user_id']}');
      }

      if (mounted) {
        setState(() {
          _reports = reports;
          _templates = templates;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('=== _ReportTab: Error loading data: $e\n$stack');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _reports.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('暂无实验报告',
                                  style: TextStyle(color: Colors.grey[500])),
                              const SizedBox(height: 8),
                              Text('点击右下角按钮新建报告',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[400])),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      itemCount: _reports.length,
                      itemBuilder: (ctx, i) =>
                          _buildReportCard(context, _reports[i]),
                    ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_report',
            onPressed: () => _showTemplatePickerDialog(),
            icon: const Icon(Icons.add),
            label: const Text('新建报告'),
          ),
        ),
      ],
    );
  }

  Widget _buildReportCard(BuildContext context, Map<String, dynamic> report) {
    final primary = Theme.of(context).colorScheme.primary;
    final title = report['title'] as String? ?? '未命名报告';
    final status = report['status'] as String? ?? '草稿';
    final templateName = report['template_name'] as String? ?? '';
    final taskTitle = report['task_title'] as String?;
    final updatedAt = report['updated_at'] as String? ?? '';

    final statusColor = status == '已提交' ? Colors.green : Colors.orange;
    final statusIcon = status == '已提交' ? Icons.check_circle : Icons.edit_note;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showReportEditor(report: report),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: statusColor.withValues(alpha: 0.1),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (templateName.isNotEmpty) ...[
                              Icon(Icons.file_copy,
                                  size: 12, color: Colors.grey[400]),
                              const SizedBox(width: 4),
                              Text(templateName,
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500])),
                              const SizedBox(width: 8),
                            ],
                            if (updatedAt.isNotEmpty)
                              Text(updatedAt.substring(0, 10),
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[400])),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(status,
                        style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              if (taskTitle != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.link, size: 14, color: primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('关联: $taskTitle',
                          style: TextStyle(fontSize: 12, color: primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showTemplatePickerDialog() {
    final primary = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择报告模板'),
        content: SizedBox(
          width: double.maxFinite,
          child: _templates.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open,
                            size: 40, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text('暂无模板', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _templates.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey.withValues(alpha: 0.1),
                          child: const Icon(Icons.article,
                              color: Colors.grey, size: 20),
                        ),
                        title: const Text('空白报告'),
                        subtitle: const Text('从零开始编写',
                            style: TextStyle(fontSize: 12)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showReportEditor();
                        },
                      );
                    }
                    final tmpl = _templates[i - 1];
                    final name = tmpl['name'] as String? ?? '未命名';
                    final desc = tmpl['description'] as String? ?? '';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: primary.withValues(alpha: 0.1),
                        child:
                            Icon(Icons.description, color: primary, size: 20),
                      ),
                      title: Text(name),
                      subtitle: Text(desc,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showReportEditor(template: tmpl);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showReportEditor(
      {Map<String, dynamic>? report, Map<String, dynamic>? template}) {
    final isEditing = report != null;
    final titleCtrl = TextEditingController(
        text: isEditing ? (report['title'] as String? ?? '') : '');

    // 解析模板 sections
    List<Map<String, dynamic>> sections = [];
    final rawJson = template != null
        ? template['sections_json'] as String?
        : (isEditing ? null : null);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List;
        sections = decoded.map((s) => Map<String, dynamic>.from(s)).toList();
      } catch (_) {}
    }

    // 解析已有报告内容
    Map<String, String> contentMap = {};
    if (isEditing) {
      final contentRaw = report['content_json'] as String?;
      if (contentRaw != null && contentRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(contentRaw) as Map;
          contentMap =
              decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        } catch (_) {}
      }
    }

    final sectionControllers = <String, TextEditingController>{};
    for (final s in sections) {
      final sTitle = s['title'] as String? ?? '';
      sectionControllers[sTitle] =
          TextEditingController(text: contentMap[sTitle] ?? '');
    }

    final generalContentCtrl =
        TextEditingController(text: contentMap['content'] ?? '');

    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? '编辑报告' : '新建报告'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: '报告标题 *',
                      hintText: '请输入报告标题',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (sections.isNotEmpty)
                    ...sections.map((s) {
                      final sTitle = s['title'] as String? ?? '';
                      final sHint = s['hint'] as String? ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: sectionControllers[sTitle],
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: sTitle,
                            hintText: sHint,
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      );
                    })
                  else
                    TextField(
                      controller: generalContentCtrl,
                      maxLines: 10,
                      decoration: InputDecoration(
                        labelText: '报告内容',
                        hintText: '请输入报告内容...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: isSaving
                  ? null
                  : () => _saveReport(
                        ctx: ctx,
                        setDialogState: setDialogState,
                        titleCtrl: titleCtrl,
                        sections: sections,
                        sectionControllers: sectionControllers,
                        generalContentCtrl: generalContentCtrl,
                        template: template,
                        existingReport: report,
                        status: '草稿',
                        setIsSaving: (v) => setDialogState(() => isSaving = v),
                      ),
              child: const Text('保存草稿'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () => _saveReport(
                        ctx: ctx,
                        setDialogState: setDialogState,
                        titleCtrl: titleCtrl,
                        sections: sections,
                        sectionControllers: sectionControllers,
                        generalContentCtrl: generalContentCtrl,
                        template: template,
                        existingReport: report,
                        status: '已提交',
                        setIsSaving: (v) => setDialogState(() => isSaving = v),
                      ),
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveReport({
    required BuildContext ctx,
    required StateSetter setDialogState,
    required TextEditingController titleCtrl,
    required List<Map<String, dynamic>> sections,
    required Map<String, TextEditingController> sectionControllers,
    required TextEditingController generalContentCtrl,
    Map<String, dynamic>? template,
    Map<String, dynamic>? existingReport,
    required String status,
    required void Function(bool) setIsSaving,
  }) async {
    if (titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入报告标题')),
      );
      return;
    }

    final userId = widget.authService.getCurrentUserId();
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('用户未登录，请重新登录'), backgroundColor: Colors.red),
      );
      return;
    }

    setIsSaving(true);
    debugPrint(
        '=== _ReportTab: Saving report - title=${titleCtrl.text.trim()}, status=$status, userId=$userId');

    try {
      final contentMap = <String, String>{};
      if (sections.isNotEmpty) {
        for (final entry in sectionControllers.entries) {
          contentMap[entry.key] = entry.value.text.trim();
        }
      } else {
        contentMap['content'] = generalContentCtrl.text.trim();
      }

      final result = await widget.labTaskDao.saveReport(
        id: existingReport != null ? existingReport['id'] as int? : null,
        templateId: template != null ? template['id'] as int? : null,
        userId: userId,
        title: titleCtrl.text.trim(),
        contentJson: jsonEncode(contentMap),
        status: status,
      );

      debugPrint('=== _ReportTab: Save result - rows affected=$result');

      if (ctx.mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == '草稿' ? '草稿已保存' : '报告已提交成功'),
            backgroundColor: status == '草稿' ? null : Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e, stack) {
      debugPrint('=== _ReportTab: Save error - $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setIsSaving(false);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 4: 任务管理（教师/管理员）
// ══════════════════════════════════════════════════════════════════════════════

class _TaskManageTab extends StatefulWidget {
  final AuthService authService;
  final LabTaskDao labTaskDao;
  const _TaskManageTab({required this.authService, required this.labTaskDao});

  @override
  State<_TaskManageTab> createState() => _TaskManageTabState();
}

class _TaskManageTabState extends State<_TaskManageTab> {
  List<Map<String, dynamic>> _tasks = [];
  Map<int, Map<String, dynamic>> _statsCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final tasks = await widget.labTaskDao.getTasks();
      final statsCache = <int, Map<String, dynamic>>{};
      for (final task in tasks) {
        final taskId = task['id'] as int;
        statsCache[taskId] = await widget.labTaskDao.getTaskStats(taskId);
      }
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _statsCache = statsCache;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadTasks,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _tasks.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.science_outlined,
                                  size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('暂无实验任务',
                                  style: TextStyle(color: Colors.grey[500])),
                              const SizedBox(height: 8),
                              Text('点击右下角按钮创建新任务',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[400])),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      itemCount: _tasks.length,
                      itemBuilder: (ctx, i) =>
                          _buildManageCard(context, _tasks[i]),
                    ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_add_task',
            onPressed: () => _showAddTaskDialog(),
            icon: const Icon(Icons.add),
            label: const Text('新建任务'),
          ),
        ),
      ],
    );
  }

  Widget _buildManageCard(BuildContext context, Map<String, dynamic> task) {
    final primary = Theme.of(context).colorScheme.primary;
    final taskId = task['id'] as int;
    final title = task['title'] as String? ?? '';
    final chapter = task['chapter'] as String? ?? '';
    final difficulty = task['difficulty'] as String? ?? '中等';
    final maxScore = task['max_score'] as int? ?? 100;
    final status = task['status'] as String? ?? 'active';
    final dueDate = task['due_date'] as String?;
    final stats = _statsCache[taskId];
    final totalSub = (stats?['total_submissions'] as int?) ?? 0;
    final gradedCount = (stats?['graded_count'] as int?) ?? 0;
    final avgScore = (stats?['avg_score'] as num?)?.toDouble() ?? 0.0;

    final diffColor = switch (difficulty) {
      '简单' => Colors.green,
      '中等' => Colors.orange,
      '较难' => Colors.red,
      '困难' => Colors.purple,
      _ => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                PopupMenuButton<String>(
                  icon:
                      Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showAddTaskDialog(existingTask: task);
                        break;
                      case 'delete':
                        _confirmDelete(taskId, title);
                        break;
                      case 'toggle':
                        _toggleTaskStatus(taskId, status);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑任务')),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(status == 'active' ? '设为归档' : '设为激活')),
                    const PopupMenuItem(
                        value: 'delete',
                        child:
                            Text('删除任务', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (chapter.isNotEmpty) ...[
                  Icon(Icons.book, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(chapter,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(width: 10),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: diffColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(difficulty,
                      style: TextStyle(
                          fontSize: 10,
                          color: diffColor,
                          fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 10),
                Icon(Icons.star, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('$maxScore分',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const Spacer(),
                if (status != 'active')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('已归档',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
              ],
            ),
            if (dueDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text('截止: ${dueDate.substring(0, 10)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem('提交', '$totalSub人', Icons.upload_file, Colors.blue),
                  Container(width: 1, height: 24, color: Colors.grey[200]),
                  _statItem(
                      '已批改', '$gradedCount人', Icons.grading, Colors.green),
                  Container(width: 1, height: 24, color: Colors.grey[200]),
                  _statItem(
                      '均分',
                      avgScore > 0 ? avgScore.toStringAsFixed(1) : '-',
                      Icons.analytics,
                      Colors.orange),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }

  void _confirmDelete(int taskId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除任务"$title"吗？\n此操作将同时删除所有相关提交，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await widget.labTaskDao.deleteTask(taskId);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('任务已删除')),
                  );
                  _loadTasks();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e')),
                  );
                }
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _toggleTaskStatus(int taskId, String currentStatus) async {
    final newStatus = currentStatus == 'active' ? 'archived' : 'active';
    try {
      await widget.labTaskDao.updateTask(taskId, {'status': newStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newStatus == 'archived' ? '任务已归档' : '任务已激活')),
        );
        _loadTasks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _showAddTaskDialog({Map<String, dynamic>? existingTask}) {
    final isEditing = existingTask != null;
    final titleCtrl = TextEditingController(
        text: isEditing ? (existingTask['title'] as String? ?? '') : '');
    final descCtrl = TextEditingController(
        text: isEditing ? (existingTask['description'] as String? ?? '') : '');
    final reqCtrl = TextEditingController(
        text: isEditing ? (existingTask['requirements'] as String? ?? '') : '');
    final delCtrl = TextEditingController(
        text: isEditing ? (existingTask['deliverables'] as String? ?? '') : '');
    String selectedChapter =
        isEditing ? (existingTask['chapter'] as String? ?? '第1章') : '第1章';
    String selectedDifficulty =
        isEditing ? (existingTask['difficulty'] as String? ?? '中等') : '中等';
    final maxScoreCtrl = TextEditingController(
        text:
            '${isEditing ? (existingTask['max_score'] as int? ?? 100) : 100}');

    DateTime dueDate;
    if (isEditing && existingTask['due_date'] != null) {
      try {
        dueDate = DateTime.parse(existingTask['due_date'] as String);
      } catch (_) {
        dueDate = DateTime.now().add(const Duration(days: 14));
      }
    } else {
      dueDate = DateTime.now().add(const Duration(days: 14));
    }

    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? '编辑任务' : '新建实验任务'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: '任务标题 *',
                      hintText: '如：实验1：环境搭建',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedChapter,
                    decoration: InputDecoration(
                      labelText: '所属章节',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    items: ['第1章', '第2章', '第3章', '第4章', '第5章', '第6章']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedChapter = v!),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedDifficulty,
                    decoration: InputDecoration(
                      labelText: '难度等级',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    items: ['简单', '中等', '较难', '困难']
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedDifficulty = v!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: maxScoreCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '满分',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: dueDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => dueDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: '截止日期',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}'),
                          ),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '任务描述',
                      hintText: '请简要描述实验任务的背景和目标...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reqCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '实验要求',
                      hintText: '列出具体的实验步骤要求...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: delCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: '提交物要求',
                      hintText: '说明需要提交的文件和格式...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入任务标题')),
                        );
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        final parsedMaxScore =
                            int.tryParse(maxScoreCtrl.text.trim()) ?? 100;
                        if (isEditing) {
                          await widget.labTaskDao
                              .updateTask(existingTask['id'] as int, {
                            'title': titleCtrl.text.trim(),
                            'chapter': selectedChapter,
                            'description': descCtrl.text.trim().isNotEmpty
                                ? descCtrl.text.trim()
                                : null,
                            'requirements': reqCtrl.text.trim().isNotEmpty
                                ? reqCtrl.text.trim()
                                : null,
                            'deliverables': delCtrl.text.trim().isNotEmpty
                                ? delCtrl.text.trim()
                                : null,
                            'difficulty': selectedDifficulty,
                            'max_score': parsedMaxScore,
                            'due_date': dueDate.toIso8601String(),
                          });
                        } else {
                          await widget.labTaskDao.addTask(
                            title: titleCtrl.text.trim(),
                            chapter: selectedChapter,
                            description: descCtrl.text.trim().isNotEmpty
                                ? descCtrl.text.trim()
                                : null,
                            requirements: reqCtrl.text.trim().isNotEmpty
                                ? reqCtrl.text.trim()
                                : null,
                            deliverables: delCtrl.text.trim().isNotEmpty
                                ? delCtrl.text.trim()
                                : null,
                            difficulty: selectedDifficulty,
                            maxScore: parsedMaxScore,
                            dueDate: dueDate.toIso8601String(),
                            creatorId: widget.authService.getCurrentUserId(),
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isEditing ? '任务已更新' : '任务创建成功'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadTasks();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('保存失败: $e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isSaving = false);
                        }
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(isSaving ? '保存中...' : (isEditing ? '更新' : '创建')),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab: 学生仓库报表（从学生 repositoryUrl 加载仓库详情）
// ═══════════════════════════════════════════════════════════════════════════════

class _StudentRepoTab extends StatefulWidget {
  final AuthService authService;
  const _StudentRepoTab({required this.authService});

  @override
  State<_StudentRepoTab> createState() => _StudentRepoTabState();
}

class _StudentRepoTabState extends State<_StudentRepoTab>
    with AutomaticKeepAliveClientMixin {
  final _giteeService = GiteeService();
  final _resource = CourseResourceService();

  bool _isLoading = true;
  String? _errorMessage;

  // 仓库详情
  Map<String, dynamic>? _repoDetail;
  String _owner = '';
  String _repoName = '';

  // 统计
  int _totalCommits = 0;
  int _totalAdditions = 0;
  int _totalDeletions = 0;
  int _totalFilesChanged = 0;

  // 数据
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _collaborators = [];
  List<Map<String, dynamic>> _releases = [];
  List<_StudentCommitRow> _commitRows = [];

  // 分支筛选
  String? _selectedBranch;
  bool _loadingBranch = false;

  // 加载统计进度
  bool _loadingStats = false;
  double _statsProgress = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRepoData();
  }

  Future<void> _loadRepoData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = widget.authService.currentUser;
    String? repoUrl = user?.repositoryUrl;

    // 如果 repositoryUrl 指向非 chzuczldl 命名空间，自动纠正
    if (repoUrl != null && repoUrl.isNotEmpty) {
      final parsed = GiteeService.parseRepoUrl(repoUrl);
      if (parsed != null &&
          parsed.owner.toLowerCase() !=
              CourseResourceService.enterprise.toLowerCase()) {
        // 替换为 chzuczldl 命名空间下的同名仓库
        repoUrl =
            'https://gitee.com/${CourseResourceService.enterprise}/${parsed.repo}';
        debugPrint(
            'StudentRepoTab: 纠正仓库 URL → $repoUrl (原: ${user?.repositoryUrl})');
      }
    }

    // 如果 repositoryUrl 未配置，尝试通过学号/姓名自动匹配
    if (repoUrl == null || repoUrl.isEmpty) {
      final userId = user?.userId ?? '';
      final realName = user?.realName ?? '';

      try {
        final myRepos = await _resource.getStudentOwnRepos(
          userId: userId,
          realName: realName,
        );

        if (myRepos.isNotEmpty) {
          // 自动使用匹配到的第一个仓库
          repoUrl = myRepos.first['html_url']?.toString();
        }
      } catch (_) {}

      if (repoUrl == null || repoUrl.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '尚未配置 Gitee 仓库地址，且无法自动识别所属仓库。\n'
              '请联系教师在「学生管理」中设置你的仓库 URL。';
        });
        return;
      }
    }

    // 解析仓库 URL
    final parsed = GiteeService.parseRepoUrl(repoUrl);
    if (parsed == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '仓库 URL 格式无效: $repoUrl';
      });
      return;
    }

    _owner = parsed.owner;
    _repoName = parsed.repo;

    try {
      final token = await _giteeService.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Gitee Token 未配置，请联系教师配置。';
        });
        return;
      }

      // 先并行获取详情、分支、提交、releases
      final results = await Future.wait([
        _giteeService.getRepoDetail(_owner, _repoName),
        _giteeService.getBranches(_owner, _repoName),
        _giteeService.getAllCommits(_owner, _repoName),
        _giteeService
            .getReleases(_owner, _repoName)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final repoDetail = results[0] as Map<String, dynamic>;
      final branches = results[1] as List<Map<String, dynamic>>;
      final commits = results[2] as List<Map<String, dynamic>>;
      final releases = results[3] as List<Map<String, dynamic>>;

      // 获取成员（多策略容错，传入 commits 作为兜底数据源）
      final collaborators = await _giteeService
          .getRepoMembers(_owner, _repoName, commits: commits)
          .catchError((_) => <Map<String, dynamic>>[]);

      final commitRows = commits.map((c) {
        final sha = c['sha']?.toString() ?? '';
        final commitMap = c['commit'] as Map<String, dynamic>? ?? {};
        final authorMap = commitMap['author'] as Map<String, dynamic>? ?? {};
        final message = commitMap['message']?.toString() ?? '';
        final dateStr = authorMap['date']?.toString();
        DateTime? date;
        if (dateStr != null) {
          try {
            date = DateTime.parse(dateStr).toLocal();
          } catch (_) {}
        }
        return _StudentCommitRow(
          sha: sha,
          message: message.split('\n').first,
          date: date,
          authorName: authorMap['name']?.toString() ?? '',
        );
      }).toList();

      setState(() {
        _repoDetail = repoDetail;
        _branches = branches;
        _collaborators = collaborators;
        _releases = releases;
        _commitRows = commitRows;
        _totalCommits = commits.length;
        _isLoading = false;
      });

      _loadCommitStats(commits);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载仓库数据失败: $e';
      });
    }
  }

  Future<void> _loadCommitStats(List<Map<String, dynamic>> commits) async {
    if (commits.isEmpty) return;
    setState(() => _loadingStats = true);

    int totalAdd = 0, totalDel = 0, totalFiles = 0;
    final maxLoad = commits.length > 50 ? 50 : commits.length;

    for (int i = 0; i < maxLoad; i++) {
      final sha = commits[i]['sha']?.toString() ?? '';
      if (sha.isEmpty) continue;
      try {
        final detail =
            await _giteeService.getCommitDetail(_owner, _repoName, sha);
        final stats = detail['stats'] as Map<String, dynamic>? ?? {};
        final add = (stats['additions'] as int?) ?? 0;
        final del = (stats['deletions'] as int?) ?? 0;
        final files = detail['files'] as List?;
        totalAdd += add;
        totalDel += del;
        totalFiles += (files?.length ?? 0);

        if (i < _commitRows.length) {
          _commitRows[i] = _commitRows[i].copyWith(
            additions: add,
            deletions: del,
            filesChanged: files?.length ?? 0,
          );
        }
        if (i % 5 == 0 || i == maxLoad - 1) {
          setState(() {
            _totalAdditions = totalAdd;
            _totalDeletions = totalDel;
            _totalFilesChanged = totalFiles;
            _statsProgress = (i + 1) / maxLoad;
          });
        }
      } catch (_) {}
    }
    setState(() => _loadingStats = false);
  }

  Future<void> _switchBranch(String? branchName) async {
    if (branchName == _selectedBranch) return;
    setState(() {
      _selectedBranch = branchName;
      _loadingBranch = true;
      _totalAdditions = 0;
      _totalDeletions = 0;
      _totalFilesChanged = 0;
    });

    try {
      final commits =
          await _giteeService.getAllCommits(_owner, _repoName, sha: branchName);
      final commitRows = commits.map((c) {
        final sha = c['sha']?.toString() ?? '';
        final commitMap = c['commit'] as Map<String, dynamic>? ?? {};
        final authorMap = commitMap['author'] as Map<String, dynamic>? ?? {};
        final message = commitMap['message']?.toString() ?? '';
        final dateStr = authorMap['date']?.toString();
        DateTime? date;
        if (dateStr != null) {
          try {
            date = DateTime.parse(dateStr).toLocal();
          } catch (_) {}
        }
        return _StudentCommitRow(
          sha: sha,
          message: message.split('\n').first,
          date: date,
          authorName: authorMap['name']?.toString() ?? '',
        );
      }).toList();
      setState(() {
        _commitRows = commitRows;
        _totalCommits = commits.length;
        _loadingBranch = false;
      });
      _loadCommitStats(commits);
    } catch (e) {
      setState(() => _loadingBranch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载仓库数据...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadRepoData,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final repo = _repoDetail;
    final fullName = repo?['full_name']?.toString() ?? '$_owner/$_repoName';
    final desc = repo?['description']?.toString() ?? '';
    final language = repo?['language']?.toString();
    final stars = repo?['stargazers_count'] ?? 0;
    final forks = repo?['forks_count'] ?? 0;
    final htmlUrl = repo?['html_url']?.toString() ?? '';

    return RefreshIndicator(
      onRefresh: _loadRepoData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 仓库头部 ──
          Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.indigo.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_special,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(fullName,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(desc,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (language != null) _chipWhite(Icons.code, language),
                      _chipWhite(Icons.star_border, '$stars'),
                      _chipWhite(Icons.call_split, '$forks'),
                      _chipWhite(
                          Icons.people_outline, '${_collaborators.length} 成员'),
                    ],
                  ),
                  if (htmlUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(htmlUrl,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                            decoration: TextDecoration.underline)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 4 统计卡片 ──
          Row(
            children: [
              _statCard('提交次数', '$_totalCommits', Colors.blue, Icons.commit),
              const SizedBox(width: 8),
              _statCard(
                  '新增行数',
                  _loadingStats ? '...' : _fmtNum(_totalAdditions),
                  Colors.green,
                  Icons.add_circle_outline),
              const SizedBox(width: 8),
              _statCard(
                  '删除行数',
                  _loadingStats ? '...' : _fmtNum(_totalDeletions),
                  Colors.red,
                  Icons.remove_circle_outline),
              const SizedBox(width: 8),
              _statCard(
                  '修改文件',
                  _loadingStats ? '...' : _fmtNum(_totalFilesChanged),
                  Colors.cyan,
                  Icons.description_outlined),
            ],
          ),
          if (_loadingStats) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _statsProgress),
            const SizedBox(height: 4),
            Text('正在加载提交统计... ${(_statsProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),

          // ── 成员列表 ──
          _buildMembersCard(),
          const SizedBox(height: 16),

          // ── 分支列表 ──
          _buildBranchCard(),
          const SizedBox(height: 16),

          // ── 提交记录 (带分支切换) ──
          _buildCommitSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _chipWhite(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white60),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  Widget _statCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 2,
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(height: 6),
              Text(title,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembersCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.people, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Text('仓库成员 (${_collaborators.length})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (_collaborators.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无成员数据', style: TextStyle(color: Colors.grey)))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _collaborators.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final m = _collaborators[i];
                final login = m['login']?.toString() ?? '';
                final name = m['name']?.toString() ?? login;
                final avatar = m['avatar_url']?.toString();
                final isAdmin = m['permissions']?['admin'] == true;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null
                        ? Text(name.isNotEmpty ? name[0] : '?')
                        : null,
                  ),
                  title: Text(name),
                  subtitle: Text(login, style: const TextStyle(fontSize: 12)),
                  trailing: isAdmin
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('管理员',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange)),
                        )
                      : const Text('成员',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBranchCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.call_split, size: 18, color: Colors.teal),
                const SizedBox(width: 8),
                Text('分支列表 (${_branches.length})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (_branches.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无分支数据', style: TextStyle(color: Colors.grey)))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _branches.map((b) {
                final name = b['name']?.toString() ?? '';
                final isSelected = _selectedBranch == name;
                final isDefault = name == 'master' || name == 'main';
                Color color = Colors.grey;
                if (isDefault)
                  color = Colors.blue;
                else if (name == 'develop')
                  color = Colors.cyan;
                else if (name.startsWith('feature'))
                  color = Colors.orange;
                else if (name == 'release') color = Colors.green;

                return Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: ActionChip(
                    label: Text(name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        )),
                    backgroundColor:
                        isSelected ? color : color.withValues(alpha: 0.1),
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                    onPressed: () => _switchBranch(isSelected ? null : name),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCommitSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Text('提交记录 ($_totalCommits)',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                if (_loadingBranch) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                const Spacer(),
                if (_selectedBranch != null)
                  Chip(
                    label: Text(_selectedBranch!,
                        style: const TextStyle(fontSize: 11)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => _switchBranch(null),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          if (_commitRows.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无提交记录', style: TextStyle(color: Colors.grey)))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 52,
                columns: const [
                  DataColumn(
                      label: Text('SHA',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('日期',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('作者',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('消息',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('新增',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  DataColumn(
                      label: Text('删除',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  DataColumn(
                      label: Text('文件',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                ],
                rows: _commitRows.map((c) {
                  final shortSha =
                      c.sha.length > 7 ? c.sha.substring(0, 7) : c.sha;
                  final dateStr = c.date != null
                      ? DateFormat('MM-dd HH:mm').format(c.date!)
                      : '-';
                  return DataRow(cells: [
                    DataCell(Text(shortSha,
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.blue))),
                    DataCell(
                        Text(dateStr, style: const TextStyle(fontSize: 12))),
                    DataCell(Text(c.authorName,
                        style: const TextStyle(fontSize: 12))),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(c.message,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(c.additions != null
                        ? Text('+${c.additions}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green))
                        : const Text('-',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey))),
                    DataCell(c.deletions != null
                        ? Text('-${c.deletions}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red))
                        : const Text('-',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey))),
                    DataCell(Text(
                        c.filesChanged != null ? '${c.filesChanged}' : '-',
                        style: const TextStyle(fontSize: 12))),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtNum(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _StudentCommitRow {
  final String sha;
  final String message;
  final DateTime? date;
  final String authorName;
  final int? additions;
  final int? deletions;
  final int? filesChanged;

  const _StudentCommitRow({
    required this.sha,
    required this.message,
    this.date,
    required this.authorName,
    this.additions,
    this.deletions,
    this.filesChanged,
  });

  _StudentCommitRow copyWith(
      {int? additions, int? deletions, int? filesChanged}) {
    return _StudentCommitRow(
      sha: sha,
      message: message,
      date: date,
      authorName: authorName,
      additions: additions ?? this.additions,
      deletions: deletions ?? this.deletions,
      filesChanged: filesChanged ?? this.filesChanged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 5: 仓库报表（教师/管理员）
// ═══════════════════════════════════════════════════════════════════════════════

class _RepoReportTab extends StatefulWidget {
  const _RepoReportTab();

  @override
  State<_RepoReportTab> createState() => _RepoReportTabState();
}

class _RepoReportTabState extends State<_RepoReportTab>
    with AutomaticKeepAliveClientMixin {
  final _giteeService = GiteeService();

  bool _isLoading = true;
  String? _errorMessage;
  List<_RepoReportItem> _repoItems = [];

  // 汇总
  int _totalStudents = 0;
  int _totalCommits = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRepoReport();
  }

  Future<void> _loadRepoReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await _giteeService.getToken();
      final owner = await _giteeService.getDefaultOwner();
      final prefix = await _giteeService.getRepoPrefix();
      // 默认只显示实验班组仓库
      final effectivePrefix =
          (prefix == null || prefix.isEmpty) ? 'cg1-,cg2-,cg3-' : prefix;

      if (token == null || token.isEmpty || owner == null || owner.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '请先在「仓库分析」页面配置 Gitee Token 和用户名';
        });
        return;
      }

      // 获取仓库列表
      final allRepos = await _giteeService.getMyRepos(perPage: 100);
      final filteredRepos =
          _giteeService.filterReposByPrefix(allRepos, effectivePrefix);

      if (filteredRepos.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '没有匹配前缀 "$effectivePrefix" 的仓库';
        });
        return;
      }

      final items = <_RepoReportItem>[];
      int totalStudents = 0;
      int totalCommits = 0;

      for (final repo in filteredRepos) {
        final repoName = repo['name']?.toString() ?? '';
        // Gitee API 路径需要 path（URL 安全的小写名称），而非 name（显示名）
        final repoPath = repo['path']?.toString() ?? repoName;
        final fullName = repo['full_name']?.toString() ?? '';
        // 从 full_name 解析 owner（full_name 格式: owner_path/repo_path）
        final repoOwner = fullName.contains('/')
            ? fullName.split('/').first
            : ((repo['owner'] as Map?)?['login']?.toString() ?? owner);

        debugPrint(
            '_RepoReportTab: loading $repoName path=$repoPath owner=$repoOwner (full=$fullName)');

        try {
          // 并行获取提交和分支，每个调用单独容错
          final results = await Future.wait([
            _giteeService
                .getCommits(repoOwner, repoPath, perPage: 100)
                .catchError((_) => <Map<String, dynamic>>[]),
            _giteeService
                .getBranches(repoOwner, repoPath)
                .catchError((_) => <Map<String, dynamic>>[]),
          ]);

          var commits = results[0] as List<Map<String, dynamic>>;
          var branches = results[1] as List<Map<String, dynamic>>;

          // 用于 getRepoMembers 的 effectiveOwner
          var effectiveOwner = repoOwner;

          // 如果全部返回空且 owner 可能不对，尝试用 namespace.path 重试
          if (commits.isEmpty && branches.isEmpty) {
            final nsPath = (repo['namespace'] as Map?)?['path']?.toString();
            final ownerLogin = (repo['owner'] as Map?)?['login']?.toString();
            final altOwner = nsPath != null && nsPath != repoOwner
                ? nsPath
                : (ownerLogin != null && ownerLogin != repoOwner
                    ? ownerLogin
                    : null);
            if (altOwner != null) {
              debugPrint(
                  '_RepoReportTab: retrying $repoPath with altOwner=$altOwner');
              effectiveOwner = altOwner;
              final retryResults = await Future.wait([
                _giteeService
                    .getCommits(altOwner, repoPath, perPage: 100)
                    .catchError((_) => <Map<String, dynamic>>[]),
                _giteeService
                    .getBranches(altOwner, repoPath)
                    .catchError((_) => <Map<String, dynamic>>[]),
              ]);
              commits = retryResults[0] as List<Map<String, dynamic>>;
              branches = retryResults[1] as List<Map<String, dynamic>>;
            }
          }

          // 获取成员（多策略容错，传入 commits 作为兜底数据源）
          final collaborators = await _giteeService
              .getRepoMembers(effectiveOwner, repoPath, commits: commits)
              .catchError((_) => <Map<String, dynamic>>[]);

          // 从提交记录中提取 unique 作者
          final authorSet = <String>{};
          for (final c in commits) {
            final authorName =
                (c['commit'] as Map?)?['author']?['name']?.toString();
            if (authorName != null && authorName.isNotEmpty) {
              authorSet.add(authorName);
            }
          }

          // 最近一次提交时间
          String? lastCommitDate;
          if (commits.isNotEmpty) {
            final dateStr = (commits.first['commit'] as Map?)?['committer']
                    ?['date']
                ?.toString();
            if (dateStr != null) {
              try {
                final dt = DateTime.parse(dateStr);
                lastCommitDate =
                    DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
              } catch (_) {
                lastCommitDate = dateStr;
              }
            }
          }

          // 最近 7 天提交数
          final now = DateTime.now();
          final weekAgo = now.subtract(const Duration(days: 7));
          int recentCommits = 0;
          for (final c in commits) {
            final dateStr =
                (c['commit'] as Map?)?['committer']?['date']?.toString();
            if (dateStr != null) {
              try {
                final dt = DateTime.parse(dateStr);
                if (dt.isAfter(weekAgo)) recentCommits++;
              } catch (_) {}
            }
          }

          final memberCount = collaborators.length;
          final commitCount = commits.length;

          totalStudents += memberCount;
          totalCommits += commitCount;

          // 如果全部为空，标记为部分加载失败
          final partialError =
              commits.isEmpty && branches.isEmpty ? '无法获取提交/分支数据（可能无权限）' : null;

          items.add(_RepoReportItem(
            repoName: repoName,
            repoPath: repoPath,
            fullName: fullName,
            memberCount: memberCount,
            commitCount: commitCount,
            branchCount: branches.length,
            authorCount: authorSet.length,
            recentCommits: recentCommits,
            lastCommitDate: lastCommitDate,
            description: repo['description']?.toString(),
            htmlUrl: repo['html_url']?.toString(),
            error: partialError,
          ));
        } catch (e) {
          debugPrint('_RepoReportTab: error loading $repoName: $e');
          items.add(_RepoReportItem(
            repoName: repoName,
            repoPath: repoPath,
            fullName: fullName,
            memberCount: 0,
            commitCount: 0,
            branchCount: 0,
            authorCount: 0,
            recentCommits: 0,
            lastCommitDate: null,
            description: repo['description']?.toString(),
            htmlUrl: repo['html_url']?.toString(),
            error: e.toString(),
          ));
        }
      }

      // 按提交数降序排列
      items.sort((a, b) => b.commitCount.compareTo(a.commitCount));

      setState(() {
        _repoItems = items;
        _totalStudents = totalStudents;
        _totalCommits = totalCommits;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载仓库报表失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载仓库报表...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadRepoReport,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRepoReport,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 汇总卡片 ──
          _buildSummaryCard(),
          const SizedBox(height: 16),

          // ── 各仓库列表 ──
          ..._repoItems.map(_buildRepoCard),
        ],
      ),
    );
  }

  // ── 汇总卡片 ──────────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final avgCommits =
        _repoItems.isEmpty ? 0.0 : _totalCommits / _repoItems.length;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [Colors.indigo.shade400, Colors.indigo.shade700],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '仓库报表总览',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildSummaryItem(
                  Icons.folder,
                  '${_repoItems.length}',
                  '仓库数',
                ),
                _buildSummaryItem(
                  Icons.people,
                  '$_totalStudents',
                  '总成员',
                ),
                _buildSummaryItem(
                  Icons.commit,
                  '$_totalCommits',
                  '总提交',
                ),
                _buildSummaryItem(
                  Icons.trending_up,
                  avgCommits.toStringAsFixed(1),
                  '平均提交',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  // ── 仓库卡片 ──────────────────────────────────────────────────────────────

  Widget _buildRepoCard(_RepoReportItem item) {
    final hasError = item.error != null;
    // 区分：是完全加载失败(404)还是部分数据缺失(无权限)
    final isFatalError = hasError &&
        item.commitCount == 0 &&
        item.branchCount == 0 &&
        item.memberCount == 0 &&
        item.error!.contains('GiteeApiException');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final owner =
              item.fullName.contains('/') ? item.fullName.split('/').first : '';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RepoDetailPage(
                owner: owner,
                repoName: item.repoPath,
                description: item.description,
                htmlUrl: item.htmlUrl,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 仓库名 + 描述
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: isFatalError
                        ? Colors.red
                        : (hasError ? Colors.orange : Colors.indigo),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.repoName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isFatalError ? Colors.red : null,
                      ),
                    ),
                  ),
                  if (item.recentCommits > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '近7天 ${item.recentCommits} 提交',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (!hasError)
                    Icon(Icons.chevron_right,
                        color: Colors.grey[400], size: 20),
                  if (hasError)
                    Icon(Icons.chevron_right,
                        color: Colors.grey[400], size: 20),
                ],
              ),

              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.description!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              if (hasError) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                        isFatalError
                            ? Icons.error_outline
                            : Icons.warning_amber,
                        size: 14,
                        color: isFatalError ? Colors.red : Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.error!,
                        style: TextStyle(
                            fontSize: 11,
                            color: isFatalError ? Colors.red : Colors.orange),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              // 统计行 — 始终显示
              Row(
                children: [
                  _buildRepoStatChip(
                    Icons.people_outline,
                    '${item.memberCount}',
                    '成员',
                    Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  _buildRepoStatChip(
                    Icons.commit,
                    '${item.commitCount}',
                    '提交',
                    Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  _buildRepoStatChip(
                    Icons.call_split,
                    '${item.branchCount}',
                    '分支',
                    Colors.teal,
                  ),
                  const SizedBox(width: 12),
                  _buildRepoStatChip(
                    Icons.person_outline,
                    '${item.authorCount}',
                    '贡献者',
                    Colors.purple,
                  ),
                ],
              ),

              if (item.lastCommitDate != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '最近提交: ${item.lastCommitDate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRepoStatChip(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 仓库报表数据模型 ────────────────────────────────────────────────────────

class _RepoReportItem {
  final String repoName; // 显示名称 (e.g. CG1-CIFMS)
  final String repoPath; // API 路径 (e.g. cg1cifms)
  final String fullName;
  final int memberCount;
  final int commitCount;
  final int branchCount;
  final int authorCount;
  final int recentCommits;
  final String? lastCommitDate;
  final String? description;
  final String? htmlUrl;
  final String? error;

  const _RepoReportItem({
    required this.repoName,
    required this.repoPath,
    required this.fullName,
    required this.memberCount,
    required this.commitCount,
    required this.branchCount,
    required this.authorCount,
    required this.recentCommits,
    this.lastCommitDate,
    this.description,
    this.htmlUrl,
    this.error,
  });
}
