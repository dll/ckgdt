part of '../lab_tasks_page.dart';

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
  int _totalStudents = 0;

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
      int totalStudents = 0;
      if (_isTeacherOrAdmin) {
        totalStudents = await widget.labTaskDao.getActiveStudentCount();
      }
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
          _totalStudents = totalStudents;
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
      '已打回' => Colors.red,
      '已提交' => Colors.blue,
      _ => Colors.orange,
    };
    final statusIcon = switch (status) {
      '已批改' => Icons.check_circle,
      '已打回' => Icons.assignment_return,
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
    final unsubmitted = _totalStudents > 0 ? _totalStudents - total : 0;
    return Row(
      children: [
        Icon(Icons.people, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(_totalStudents > 0 ? '$total/$_totalStudents人提交' : '$total人提交',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        if (unsubmitted > 0) ...[
          const SizedBox(width: 8),
          Text('$unsubmitted人未交',
              style: TextStyle(fontSize: 12, color: Colors.red[400])),
        ],
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
    String? selectedFilePath;
    String? selectedFileName;
    bool isSubmitting = false;

    final existing = _submissionCache[taskId];
    if (existing != null) {
      contentCtrl.text = existing['content'] as String? ?? '';
      selectedFilePath = existing['file_paths'] as String?;
      selectedFileName = existing['file_names'] as String?;
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
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf'],
                        dialogTitle: '选择 PDF 实验报告',
                      );
                      if (result == null || result.files.single.path == null) {
                        return;
                      }
                      final pickedName = result.files.single.name;
                      final error = LabReportValidationService.validateFileName(
                        fileName: pickedName,
                        studentId: userId ?? '',
                        realName:
                            widget.authService.currentUser?.realName ?? '',
                        taskTitle: task['title'] as String? ?? '',
                      );
                      if (error != null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(error),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                        return;
                      }
                      setDialogState(() {
                        selectedFilePath = result.files.single.path!;
                        selectedFileName = pickedName;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: selectedFilePath == null
                            ? Colors.grey.withValues(alpha: 0.05)
                            : Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedFilePath == null
                              ? Colors.grey.withValues(alpha: 0.25)
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectedFilePath == null
                                ? Icons.upload_file
                                : Icons.picture_as_pdf,
                            color: selectedFilePath == null
                                ? Colors.grey[500]
                                : Colors.red,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedFileName ?? '选择 PDF 实验报告',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '补充说明（可选）',
                      hintText: '可补充说明实验完成情况、遇到的问题及解决方案...',
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
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (selectedFilePath == null ||
                          selectedFileName == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请选择符合命名规范的 PDF 实验报告')),
                        );
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      int? submissionId;
                      try {
                        final extractedText =
                            await PdfTextService.extractFromFile(
                                selectedFilePath!);
                        final bodyError =
                            LabReportValidationService.validateExtractedBody(
                          extractedText: extractedText ?? '',
                          taskTitle: task['title'] as String? ?? '',
                          requirements: task['requirements'] as String?,
                        );
                        if (bodyError != null) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(bodyError),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                          return;
                        }
                        final content = StringBuffer()
                          ..write(
                              LabReportValidationService.buildSubmissionContent(
                            fileName: selectedFileName!,
                            extractedText: extractedText!,
                          ));
                        if (contentCtrl.text.trim().isNotEmpty) {
                          content
                            ..writeln()
                            ..writeln('--- 学生补充说明 ---')
                            ..writeln(contentCtrl.text.trim());
                        }
                        submissionId = await widget.labTaskDao.submitTask(
                          taskId: taskId,
                          userId: userId!,
                          content: content.toString(),
                          filePaths: selectedFilePath,
                          fileNames: selectedFileName,
                        );
                        final draft = await AutoGradingService.instance
                            .gradeLabSubmission(
                          submissionId: submissionId,
                          studentId: userId,
                          studentName:
                              widget.authService.currentUser?.realName ??
                                  userId,
                          taskId: taskId,
                          taskTitle: task['title'] as String? ?? '实验任务',
                          content: content.toString(),
                          requirements: task['requirements'] as String?,
                          maxScore: (task['max_score'] as int?) ?? 100,
                          returnDraft: true,
                          notifyStudent: false,
                        );
                        final passScore =
                            await SettingsService.getEvaluationPassScore();
                        if (draft == null ||
                            !draft.isUsable ||
                            draft.score < passScore) {
                          await widget.labTaskDao
                              .deleteSubmission(submissionId);
                          await GradingResultDao()
                              .deletePendingForTarget('lab', submissionId);
                          submissionId = null;
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(draft == null
                                    ? '提交失败：AI 审核未完成，请稍后重试'
                                    : '提交失败：AI 初评 ${draft.score} 分，未达到 $passScore 分达标线，请修改后重新提交'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                          return;
                        }
                        // 通知教师
                        NotificationService().notifyLabSubmission(
                          studentId: userId,
                          studentName:
                              widget.authService.currentUser?.realName ??
                                  userId,
                          taskTitle: task['title'] as String? ?? '实验任务',
                          taskId: taskId,
                        );
                        // 立即触发同步上传
                        unawaited(SyncService().uploadStudentData(userId));
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('提交成功！AI 初评 ${draft.score} 分，等待教师复核。'),
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
                        if (submissionId != null) {
                          await widget.labTaskDao
                              .deleteSubmission(submissionId);
                          await GradingResultDao()
                              .deletePendingForTarget('lab', submissionId);
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

  /// 学生提交后台触发 AI 批阅草稿
  ///
  /// 设计：AI 出 JSON 草稿写 grading_results.status='pending'，教师在 AI 批阅 Tab 审核 → approve/reject。
  /// 学生侧只看到"已提交"状态，待教师审核完才看到分数（通过 lab_submissions.score 写回）。
  /// 失败静默 — AI 调用失败不影响提交流程，教师可手动批阅。
  Future<void> _triggerAiGradingDraft({
    required int submissionId,
    required int taskId,
    required String taskTitle,
    required String content,
    required String studentId,
  }) async {
    try {
      final agent = GradingAgent();
      final tasks = await widget.labTaskDao.getTasks();
      final task = tasks.firstWhere(
        (t) => (t['id'] as int?) == taskId,
        orElse: () => <String, dynamic>{},
      );
      final maxScore = (task['max_score'] as int?) ?? 100;
      final requirements = task['requirements'] as String?;

      final result = await agent.gradeSubmission(
        taskTitle: taskTitle,
        content: content,
        maxScore: maxScore,
        requirements: requirements,
      );
      final parsed = tryParseGradingJson(result);
      if (parsed == null) return;

      final score = (parsed['score'] as num?)?.toInt() ?? 0;
      final feedback = formatGradingFeedback(parsed);
      final dimensions = parsed['dimensions'] as Map<String, dynamic>?;
      final strengths = (parsed['strengths'] as List?)?.cast<String>() ?? [];
      final improvements =
          (parsed['improvements'] as List?)?.cast<String>() ?? [];
      final aiFlag = (parsed['ai_flag'] as bool?) ?? false;

      await GradingResultDao().saveResult(
        domain: 'lab',
        targetId: submissionId,
        scorerId: 'ai',
        rawJson: result,
        score: score.toDouble(),
        feedback: feedback,
        dimensions: dimensions,
        strengths: strengths,
        improvements: improvements,
        aiFlag: aiFlag,
      );

      final user = widget.authService.currentUser;
      await NotificationService().notifyLabAutoGraded(
        studentId: studentId,
        studentName: user?.realName ?? studentId,
        taskTitle: taskTitle,
        taskId: taskId,
        score: score,
      );
    } catch (e) {
      debugPrint('TaskListTab: AI 批阅草稿后台任务失败 — $e');
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2: 我的提交 / 提交管理
// ══════════════════════════════════════════════════════════════════════════════
