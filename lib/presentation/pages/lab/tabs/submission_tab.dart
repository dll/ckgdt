part of '../lab_tasks_page.dart';

class _SubmissionTab extends StatefulWidget {
  final AuthService authService;
  final LabTaskDao labTaskDao;
  const _SubmissionTab({required this.authService, required this.labTaskDao});

  @override
  State<_SubmissionTab> createState() => _SubmissionTabState();
}

class _SubmissionTabState extends State<_SubmissionTab> {
  List<Map<String, dynamic>> _submissions = [];
  Map<int, List<Map<String, dynamic>>> _unsubmittedByTask = {};
  Map<String, dynamic> _classOverview = {};
  bool _isLoading = true;
  // Cached stats (computed once in _loadSubmissions, used in build)
  double _avgScore = 0;
  int _excellentCount = 0;
  int _failCount = 0;
  int _passScore = SettingsService.defaultEvaluationPassScore;

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
      // 教师打开提交管理时自动拉取最新学生数据
      if (_isTeacherOrAdmin) {
        try {
          await SyncService().downloadAllStudentData();
        } catch (_) {}
      }
      List<Map<String, dynamic>> submissions;
      final passScore = await SettingsService.getEvaluationPassScore();
      if (_isTeacherOrAdmin) {
        submissions = await widget.labTaskDao.getSubmissions();
      } else {
        final userId = widget.authService.getCurrentUserId();
        submissions = userId != null
            ? await widget.labTaskDao.getSubmissions(userId: userId)
            : [];
      }
      if (mounted) {
        // 教师端：加载每个任务的未提交学生
        final unsub = <int, List<Map<String, dynamic>>>{};
        if (_isTeacherOrAdmin) {
          final tasks = await widget.labTaskDao.getTasks(status: 'active');
          for (final t in tasks) {
            final tid = t['id'] as int;
            unsub[tid] = await widget.labTaskDao.getUnsubmittedStudents(tid);
          }
          _classOverview =
              await widget.labTaskDao.getClassLabOverview(passScore: passScore);
        }
        // 计算缓存统计（一次计算，build 中复用）
        final graded = submissions.where((s) => s['score'] != null).toList();
        final avg = graded.isEmpty
            ? 0.0
            : graded.fold<double>(0, (sum, s) => sum + (s['score'] as int)) /
                graded.length;
        setState(() {
          _submissions = submissions;
          _unsubmittedByTask = unsub;
          _passScore = passScore;
          _avgScore = avg;
          _excellentCount =
              graded.where((s) => (s['score'] as int) >= passScore).length;
          _failCount = graded.where((s) => (s['score'] as int) < 60).length;
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
    final graded = _submissions.where((s) => s['score'] != null).toList();

    final items = <Widget>[
      _buildScoreSummaryCard(graded, _avgScore, _excellentCount, _failCount),
      const SizedBox(height: 12),
    ];
    for (final sub in _submissions) {
      items.add(_buildSubmissionCard(sub));
    }

    return ListView(padding: const EdgeInsets.all(16), children: items);
  }

  Widget _buildScoreSummaryCard(List<Map<String, dynamic>> graded,
      double avgScore, int excellentCount, int failCount) {
    final allGradedCount = graded.length;
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.04),
              theme.colorScheme.secondary.withValues(alpha: 0.02)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.analytics_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('实验成绩总览',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary)),
            const Spacer(),
            Text('已批阅 $allGradedCount/${_submissions.length}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _buildStatChip(
                '平均分', avgScore.toStringAsFixed(1), theme.colorScheme.primary),
            const SizedBox(width: 10),
            _buildStatChip(
                '达标(≥$_passScore)',
                '$excellentCount',
                excellentCount == allGradedCount && allGradedCount > 0
                    ? Colors.green
                    : Colors.orange),
            const SizedBox(width: 10),
            _buildStatChip('待提升(<60)', '$failCount',
                failCount > 0 ? Colors.red : Colors.grey),
          ]),
          if (allGradedCount > 0) ...[
            const SizedBox(height: 14),
            SizedBox(
                height: 80,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: graded.map((s) {
                    final score = (s['score'] as int).toDouble();
                    final maxScore = (s['max_score'] as int? ?? 100).toDouble();
                    final ratio = (score / maxScore).clamp(0.05, 1.0);
                    final color = score >= _passScore
                        ? Colors.green
                        : score >= 60
                            ? Colors.blue
                            : Colors.red;
                    final title = (s['task_title'] as String? ?? '?');
                    final short =
                        title.length > 6 ? '${title.substring(0, 5)}…' : title;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(score.toStringAsFixed(0),
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: color)),
                              const SizedBox(height: 2),
                              Flexible(
                                  child: Container(
                                height: 55 * ratio,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.7),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              )),
                              const SizedBox(height: 3),
                              Text(short,
                                  style: TextStyle(
                                      fontSize: 8, color: Colors.grey[600]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ]),
                      ),
                    );
                  }).toList(),
                )),
          ],
          if (excellentCount == allGradedCount && allGradedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.emoji_events, size: 16, color: Colors.amber[700]),
                const SizedBox(width: 6),
                Text('全部实验达标！满足答辩条件①',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber[800],
                        fontWeight: FontWeight.w500)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }

  Widget _buildSubmissionCard(Map<String, dynamic> sub) {
    final status = sub['status'] as String? ?? '已提交';
    final score = sub['score'] as int?;
    final taskTitle = sub['task_title'] as String? ?? '';
    final chapter = sub['chapter'] as String? ?? '';
    final maxScore = sub['max_score'] as int? ?? 100;
    final submitTime = sub['submit_time'] as String? ?? '';
    final statusColor = switch (status) {
      '已批改' => Colors.green,
      '已打回' => Colors.red,
      '已提交' => Colors.blue,
      _ => Colors.orange,
    };
    final statusIcon = switch (status) {
      '已批改' => Icons.check_circle,
      '已打回' => Icons.assignment_return,
      '已提交' => Icons.hourglass_top,
      _ => Icons.pending,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showSubmissionDetail(sub),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                  radius: 18,
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  child: Icon(statusIcon, color: statusColor, size: 20)),
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
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ])),
              if (score != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _scoreColor(score, maxScore).withValues(alpha: 0.1),
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
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
                onSelected: (value) {
                  if (value == 'edit') _showEditSubmissionDialog(sub);
                  if (value == 'delete') _confirmDeleteSubmission(sub);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('编辑')
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.red))
                      ])),
                ],
              ),
            ]),
            if (sub['feedback'] != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.comment, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(sub['feedback'] as String,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  void _showEditSubmissionDialog(Map<String, dynamic> submission) {
    final submissionId = submission['id'] as int;
    final contentCtrl =
        TextEditingController(text: submission['content'] as String? ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit, size: 20),
              SizedBox(width: 8),
              Text('编辑提交'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: contentCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: '实验总结 *',
                hintText: '请简要描述实验完成情况...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (contentCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请填写实验总结')),
                        );
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        await widget.labTaskDao.updateSubmission(
                          submissionId: submissionId,
                          content: contentCtrl.text.trim(),
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('修改成功'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadSubmissions();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('修改失败: $e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isSaving = false);
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSubmission(Map<String, dynamic> submission) {
    final submissionId = submission['id'] as int?;
    final taskTitle = submission['task_title'] as String? ?? '未知任务';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除任务"$taskTitle"的提交吗？\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (submissionId == null) return;
              Navigator.pop(ctx);
              try {
                await widget.labTaskDao.deleteSubmission(submissionId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('提交已删除')),
                  );
                  _loadSubmissions();
                }
              } catch (e) {
                if (mounted) {
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

  Widget _buildTeacherClassOverviewCard(Color primary) {
    final studentCount = _classOverview['student_count'] ?? 0;
    final avgScore = (_classOverview['avg_score'] as num?)?.toDouble() ?? 0;
    final maxScore = _classOverview['max_score'] as int? ?? 0;
    final minScore = _classOverview['min_score'] as int?;
    final excellentCount = _classOverview['excellent_count'] as int? ?? 0;
    final passCount = _classOverview['pass_count'] as int? ?? 0;
    final failCount = _classOverview['fail_count'] as int? ?? 0;
    final ungradedCount = _classOverview['ungraded_count'] as int? ?? 0;
    final totalGraded = _classOverview['total_graded'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              primary.withValues(alpha: 0.05),
              primary.withValues(alpha: 0.12)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.analytics_outlined, size: 20, color: primary),
            const SizedBox(width: 8),
            Text('班级实验总览',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
            const Spacer(),
            Text('$studentCount人 · ${totalGraded}份批改',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]),
          const SizedBox(height: 12),
          // 核心统计
          Row(children: [
            _buildStatChip('班级均分', avgScore.toStringAsFixed(1), primary),
            const SizedBox(width: 10),
            _buildStatChip('最高分', '$maxScore', Colors.green),
            const SizedBox(width: 10),
            _buildStatChip(
                '最低分', minScore != null ? '$minScore' : '—', Colors.red),
          ]),
          const SizedBox(height: 12),
          // 分数段分布条
          if (totalGraded > 0) ...[
            Row(children: [
              Text('分数段分布',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 24,
                child: Row(children: [
                  if (excellentCount > 0)
                    Expanded(
                      flex: excellentCount,
                      child: Container(
                        color: Colors.green,
                        child: Center(
                          child: Text(
                              excellentCount > totalGraded * 0.15
                                  ? '≥$_passScore: $excellentCount'
                                  : '',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.white)),
                        ),
                      ),
                    ),
                  if (passCount > 0)
                    Expanded(
                      flex: passCount,
                      child: Container(
                        color: Colors.blue,
                        child: Center(
                          child: Text(
                              passCount > totalGraded * 0.15
                                  ? '60-${_passScore - 1}: $passCount'
                                  : '',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.white)),
                        ),
                      ),
                    ),
                  if (failCount > 0)
                    Expanded(
                      flex: failCount,
                      child: Container(
                        color: Colors.red,
                        child: Center(
                          child: Text(
                              failCount > totalGraded * 0.15
                                  ? '<60: $failCount'
                                  : '',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.white)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              _legendDot(Colors.green, '达标≥$_passScore ($excellentCount)'),
              const SizedBox(width: 12),
              _legendDot(Colors.blue, '及格60-${_passScore - 1} ($passCount)'),
              const SizedBox(width: 12),
              _legendDot(Colors.red, '不及格<60 ($failCount)'),
            ]),
          ],
          // 答辩资格提示
          if (failCount > 0 || ungradedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber,
                      size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                            if (failCount > 0) '$failCount人实验不及格',
                            if (ungradedCount > 0) '$ungradedCount份未批改',
                          ].join('，') +
                          ' — 部分学生不满足答辩条件①',
                      style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }

  Widget _buildTeacherSubmissionList(Color primary) {
    // 按任务分组，同时保留 task_id
    final grouped = <String, List<Map<String, dynamic>>>{};
    final taskIdByTitle = <String, int>{};
    for (final sub in _submissions) {
      final key = sub['task_title'] as String? ?? '未知任务';
      grouped.putIfAbsent(key, () => []).add(sub);
      if (sub['task_id'] != null) {
        taskIdByTitle[key] = sub['task_id'] as int;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_classOverview.isNotEmpty) _buildTeacherClassOverviewCard(primary),
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
          final taskId = taskIdByTitle[entry.key];
          final unsubmitted = taskId != null
              ? (_unsubmittedByTask[taskId] ?? [])
              : <Map<String, dynamic>>[];
          final totalStudents = entry.value.length + unsubmitted.length;

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
                      child: Text('${entry.value.length}/$totalStudents人提交',
                          style: TextStyle(fontSize: 11, color: primary)),
                    ),
                    if (unsubmitted.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${unsubmitted.length}人未交',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.red)),
                      ),
                    ],
                  ],
                ),
              ),
              ...entry.value.map((sub) => _buildTeacherSubmissionCard(sub)),
              // 未提交学生折叠列表
              if (unsubmitted.isNotEmpty) _buildUnsubmittedSection(unsubmitted),
              const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildUnsubmittedSection(List<Map<String, dynamic>> students) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Icon(Icons.person_off, size: 18, color: Colors.red[300]),
      title: Text('未提交 (${students.length}人)',
          style: TextStyle(fontSize: 13, color: Colors.red[400])),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: students.map((s) {
            final name = s['real_name'] as String? ?? s['user_id'] as String;
            return Chip(
              avatar:
                  Icon(Icons.person_outline, size: 14, color: Colors.red[300]),
              label: Text(name, style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.red.withValues(alpha: 0.05),
              side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTeacherSubmissionCard(Map<String, dynamic> sub) {
    final status = sub['status'] as String? ?? '已提交';
    final score = sub['score'] as int?;
    final userName = sub['real_name'] as String? ??
        sub['user_name'] as String? ??
        sub['user_id'] ??
        '';
    final submitTime = sub['submit_time'] as String? ?? '';
    final maxScore = sub['max_score'] as int? ?? 100;
    final isGraded = status == '已批改';
    final isReturned = status == '已打回';
    final statusColor = isGraded
        ? Colors.green
        : isReturned
            ? Colors.red
            : Colors.blue;

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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isGraded && score != null)
                Container(
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
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isReturned ? Colors.red : Colors.orange)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isReturned ? '已打回' : '待批改',
                      style: TextStyle(
                          fontSize: 11,
                          color: isReturned ? Colors.red : Colors.orange,
                          fontWeight: FontWeight.w500)),
                ),
              if (widget.authService.isAdmin)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.red),
                  tooltip: '删除提交',
                  onPressed: () => _confirmDeleteSubmission(sub),
                ),
            ],
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
    final userName = submission['real_name'] as String? ??
        submission['user_name'] as String? ??
        submission['user_id'] ??
        '';
    final studentId = submission['user_id'] as String? ?? '';
    final content = submission['content'] as String? ?? '';
    final maxScore = submission['max_score'] as int? ?? 100;
    final existingScore = submission['score'] as int?;
    final existingFeedback = submission['feedback'] as String?;
    final taskTitle = submission['task_title'] as String? ?? '实验任务';
    final filePaths = submission['file_paths'] as String? ?? '';
    final fileNames = submission['file_names'] as String? ?? '';

    double scoreValue = (existingScore ?? 80).toDouble();
    final feedbackCtrl = TextEditingController(text: existingFeedback ?? '');
    bool isGrading = false;
    bool isAiGrading = false;
    bool isReturning = false;

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
                  if (filePaths.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.picture_as_pdf,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            fileNames.isNotEmpty ? fileNames : '实验报告.pdf',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.visibility, size: 16),
                          label: const Text('预览PDF',
                              style: TextStyle(fontSize: 12)),
                          onPressed: () => previewOrPromptSync(
                            context,
                            filePaths: filePaths,
                            fileNames: fileNames,
                            userId: submission['user_id'] as String? ?? '',
                            title: '$userName - $taskTitle',
                            onSyncFinished: _loadSubmissions,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
            OutlinedButton.icon(
              onPressed: isReturning
                  ? null
                  : () async {
                      setDialogState(() => isReturning = true);
                      try {
                        final reason = await _buildReturnReason(
                          submission: submission,
                          taskTitle: taskTitle,
                          content: content,
                          filePaths: filePaths,
                          fileNames: fileNames,
                          maxScore: maxScore,
                          teacherFeedback: feedbackCtrl.text.trim(),
                        );
                        if (!context.mounted) return;
                        setDialogState(() => isReturning = false);
                        final confirmedReason =
                            await _confirmReturnSubmission(reason);
                        if (confirmedReason == null ||
                            confirmedReason.trim().isEmpty) {
                          return;
                        }
                        if (!context.mounted) return;
                        setDialogState(() => isReturning = true);
                        await widget.labTaskDao.returnSubmission(
                          submissionId,
                          reason: confirmedReason.trim(),
                          reviewerId: widget.authService.getCurrentUserId(),
                        );
                        await GradingResultDao()
                            .deletePendingForTarget('lab', submissionId);
                        await NotificationService().notifyLabSubmissionReturned(
                          studentId: studentId,
                          taskTitle: taskTitle,
                          reason: confirmedReason.trim(),
                        );
                        if (studentId.isNotEmpty) {
                          unawaited(SyncService().uploadStudentData(studentId));
                        }
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已打回并通知学生'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          _loadSubmissions();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('打回失败: $e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isReturning = false);
                        }
                      }
                    },
              icon: isReturning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_return, size: 16),
              label: Text(isReturning ? '生成理由中...' : '打回'),
            ),
            // AI 批阅按钮
            OutlinedButton.icon(
              onPressed: isAiGrading
                  ? null
                  : () async {
                      if (content.isEmpty && filePaths.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('学生未提交内容，无法AI批阅')),
                        );
                        return;
                      }
                      setDialogState(() => isAiGrading = true);
                      try {
                        // 兜底：旧提交可能只有文件名占位，需要从 PDF 重新提取
                        final prepared = await prepareGradingContent(
                          rawContent: content,
                          filePaths: filePaths,
                          fileNames: fileNames,
                        );
                        if (!prepared.hasBody) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('无法读取报告正文：PDF 文件未同步到本机或损坏，请使用手动批改'),
                                duration: Duration(seconds: 4),
                              ),
                            );
                            setDialogState(() => isAiGrading = false);
                          }
                          return;
                        }
                        final agent = GradingAgent();
                        final result = await agent.gradeSubmission(
                          taskTitle: taskTitle,
                          content: prepared.content,
                          maxScore: maxScore,
                        );
                        // 尝试解析 JSON 结果
                        final parsed = _tryParseGradingJson(result);
                        if (parsed != null) {
                          setDialogState(() {
                            scoreValue =
                                (parsed['score'] as num?)?.toDouble() ??
                                    scoreValue;
                            if (scoreValue > maxScore) {
                              scoreValue = maxScore.toDouble();
                            }
                            feedbackCtrl.text = _formatGradingFeedback(parsed);
                          });
                        } else {
                          setDialogState(() {
                            feedbackCtrl.text = _formatRawAiFeedback(result);
                          });
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('AI批阅失败: $e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isAiGrading = false);
                        }
                      }
                    },
              icon: isAiGrading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(isAiGrading ? 'AI批阅中...' : 'AI批阅'),
            ),
            if (widget.authService.isAdmin)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmDeleteSubmission(submission);
                },
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
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

  Future<String> _buildReturnReason({
    required Map<String, dynamic> submission,
    required String taskTitle,
    required String content,
    required String filePaths,
    required String fileNames,
    required int maxScore,
    required String teacherFeedback,
  }) async {
    final reasons = <String>[];
    final fileError =
        LabReportValidationService.validateStoredSubmission(submission);
    if (fileError != null) {
      reasons.add('文件审核不通过：$fileError');
    }

    final prepared = await prepareGradingContent(
      rawContent: content,
      filePaths: filePaths,
      fileNames: fileNames,
    );
    if (!prepared.hasBody) {
      reasons.add('内容审核不通过：无法读取 PDF 正文，不能确认报告内容与实验任务一致。');
    } else {
      final result = await GradingAgent().gradeSubmission(
        taskTitle: taskTitle,
        content: prepared.content,
        maxScore: maxScore,
      );
      final parsed = _tryParseGradingJson(result);
      if (parsed != null) {
        final passScore = await SettingsService.getEvaluationPassScore();
        final score = (parsed['score'] as num?)?.round() ??
            (parsed['total_score'] as num?)?.round() ??
            0;
        final aiFlag = parsed['ai_flag'] == true;
        if (score < passScore || aiFlag) {
          reasons.add('AI 审核建议打回：评分 $score/$maxScore，未达到 $passScore 分达标线'
              '${aiFlag ? '，且疑似 AI 生成' : ''}。');
        }
        final formatted = _formatGradingFeedback(parsed);
        if (formatted.isNotEmpty) {
          reasons.add(formatted);
        }
      } else {
        final cleaned = _formatRawAiFeedback(result);
        if (cleaned.isNotEmpty) {
          reasons.add(cleaned);
        }
      }
    }

    if (teacherFeedback.isNotEmpty) {
      reasons.add('教师补充意见：$teacherFeedback');
    }
    if (reasons.isEmpty) {
      reasons.add('报告未通过审核：请确认文件命名、实验主题、报告正文、截图与代码说明均与当前实验一致后重新提交。');
    }
    return reasons.join('\n\n');
  }

  Future<String?> _confirmReturnSubmission(String initialReason) async {
    final reasonCtrl = TextEditingController(text: initialReason.trim());
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('确认打回'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('以下理由将通知学生，可在发送前修改。'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                minLines: 8,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: '打回理由',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, reasonCtrl.text.trim()),
            icon: const Icon(Icons.assignment_return, size: 18),
            label: const Text('确认打回'),
          ),
        ],
      ),
    );
  }

  /// 尝试从 AI 批阅结果中解析 JSON（委托顶层函数）
  Map<String, dynamic>? _tryParseGradingJson(String text) =>
      tryParseGradingJson(text);

  /// 将 AI 批阅的 JSON 结果转为人类可读的反馈文本（委托顶层函数）
  String _formatGradingFeedback(Map<String, dynamic> parsed) =>
      formatGradingFeedback(parsed);

  String _formatRawAiFeedback(String text) {
    final parsed = _tryParseGradingJson(text);
    if (parsed != null) return _formatGradingFeedback(parsed);
    return text
        .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();
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
