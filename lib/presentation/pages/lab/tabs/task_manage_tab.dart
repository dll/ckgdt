part of '../lab_tasks_page.dart';

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
                    color: diffColor.withOpacity(0.1),
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
                      color: Colors.grey.withOpacity(0.1),
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
                color: primary.withOpacity(0.04),
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
                  DropdownButtonFormField<String>(value: selectedChapter,
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
                  DropdownButtonFormField<String>(value: selectedDifficulty,
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

