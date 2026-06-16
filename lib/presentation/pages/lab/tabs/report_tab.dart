part of '../lab_tasks_page.dart';

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

  /// 教师视图下报告分组方式：byStudent（学号）/ byTask（实验任务）/ byGrade（成绩等级）
  String _groupBy = 'byStudent';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool get _isTeacherOrAdmin =>
      widget.authService.isTeacher || widget.authService.isAdmin;

  Future<List<Map<String, dynamic>>> _cleanupInvalidSubmissions(
    List<Map<String, dynamic>> submissions,
  ) async {
    if (!_isTeacherOrAdmin) return submissions;
    final valid = <Map<String, dynamic>>[];
    var removed = 0;
    for (final sub in submissions) {
      final subId = sub['id'] as int?;
      final error = LabReportValidationService.validateStoredSubmission(sub);
      if (subId != null && error != null) {
        removed++;
        await widget.labTaskDao.deleteSubmission(subId);
        await GradingResultDao().deletePendingForTarget('lab', subId);
        debugPrint(
            'LabReportTab: removed invalid submission $subId, reason=$error');
      } else {
        valid.add(sub);
      }
    }
    if (removed > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理 $removed 条不合规实验报告提交')),
      );
    }
    return valid;
  }

  Future<Map<int, Map<String, dynamic>>> _loadPendingAiDrafts() async {
    final rows = await GradingResultDao().getPendingResults('lab');
    final result = <int, Map<String, dynamic>>{};
    for (final row in rows) {
      final targetId = row['target_id'] as int?;
      if (targetId == null) continue;
      result[targetId] = {
        '_ai_result_id': row['id'],
        '_ai_score': (row['score'] as num?)?.round(),
        '_ai_feedback': (row['feedback'] as String? ?? '').trim(),
        '_ai_created_at': row['created_at'] as String? ?? '',
      };
    }
    return result;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 教师打开实验报告时自动拉取最新学生数据
      if (_isTeacherOrAdmin) {
        try {
          await SyncService().downloadAllStudentData();
        } catch (e) {
          swallow(e, tag: 'LabReportTab.downloadAll');
        }
      } else {
        // 学生打开时从云端同步自己在其他设备提交的数据
        final userId = widget.authService.getCurrentUserId();
        if (userId != null && userId.isNotEmpty) {
          try {
            await SyncService().downloadOwnData(userId);
          } catch (e) {
            swallow(e, tag: 'LabReportTab.downloadOwn');
          }
        }
      }

      final userId = widget.authService.getCurrentUserId();
      debugPrint(
          '=== _ReportTab: Loading reports for userId=$userId, isTeacherOrAdmin=$_isTeacherOrAdmin');

      List<Map<String, dynamic>> reports;
      if (_isTeacherOrAdmin) {
        reports = List<Map<String, dynamic>>.from(
            await widget.labTaskDao.getStudentReports());
        // 同时加载 lab_submissions 中的提交（学生通过 submitTask 提交的）
        // 将其转换为与 student_reports 兼容的格式合并显示
        final submissions = await _cleanupInvalidSubmissions(
            await widget.labTaskDao.getSubmissions());
        final aiDrafts = await _loadPendingAiDrafts();
        for (final sub in submissions) {
          // 检查是否已有对应的 student_reports 记录（避免重复显示）
          final subUserId = sub['user_id'] as String? ?? '';
          final subTaskId = sub['task_id'] as int?;
          final alreadyHasReport = reports.any(
              (r) => r['user_id'] == subUserId && r['task_id'] == subTaskId);
          if (!alreadyHasReport) {
            reports.add({
              ...sub,
              ...?aiDrafts[sub['id'] as int?],
              'title': sub['task_title'] as String? ??
                  sub['content'] as String? ??
                  '实验提交',
              'status': sub['status'] as String? ?? '已提交',
              'updated_at': sub['submit_time'] as String? ??
                  sub['created_at'] as String? ??
                  '',
              'template_name': '',
              '_from_submissions': true, // 标记来源
            });
          }
        }
        debugPrint(
            '=== _ReportTab: Teacher/Admin - ${reports.length} reports (incl. submissions)');
      } else if (userId != null && userId.isNotEmpty) {
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

  String _gradeBand(int? score) {
    if (score == null) return '未批阅';
    if (score >= 90) return '优秀 90-100';
    if (score >= 80) return '良好 80-89';
    if (score >= 70) return '中等 70-79';
    if (score >= 60) return '及格 60-69';
    return '不及格 0-59';
  }

  int _gradeBandOrder(String band) {
    if (band.startsWith('优秀')) return 0;
    if (band.startsWith('良好')) return 1;
    if (band.startsWith('中等')) return 2;
    if (band.startsWith('及格')) return 3;
    if (band.startsWith('不及格')) return 4;
    if (band == '未批阅') return 5;
    return _groupBy == 'byGrade' ? 99 : 0;
  }

  IconData _groupIcon() {
    if (_groupBy == 'byTask') return Icons.assignment;
    if (_groupBy == 'byGrade') return Icons.workspace_premium;
    return Icons.person;
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
                              Text(_isTeacherOrAdmin ? '暂无学生提交报告' : '暂无实验报告',
                                  style: TextStyle(color: Colors.grey[500])),
                              const SizedBox(height: 8),
                              if (!_isTeacherOrAdmin)
                                Text('点击右下角按钮新建报告',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[400])),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _isTeacherOrAdmin
                      ? _buildGroupedReportsList()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: _reports.length,
                          itemBuilder: (ctx, i) =>
                              _buildReportCard(context, _reports[i]),
                        ),
        ),
        if (!_isTeacherOrAdmin)
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

  /// 教师视图：按学号或实验任务分组的列表
  Widget _buildGroupedReportsList() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in _reports) {
      final key = _groupBy == 'byTask'
          ? ((r['task_title'] as String?)?.trim().isNotEmpty == true
              ? r['task_title'] as String
              : (r['title'] as String? ?? '未知任务'))
          : _groupBy == 'byGrade'
              ? _gradeBand((r['score'] as num?)?.round() ??
                  (r['_ai_score'] as num?)?.round())
              : ((r['user_id'] as String?)?.trim().isNotEmpty == true
                  ? r['user_id'] as String
                  : '未知学生');
      (groups[key] ??= []).add(r);
    }

    final keys = groups.keys.toList()
      ..sort((a, b) => _groupBy == 'byGrade'
          ? _gradeBandOrder(a).compareTo(_gradeBandOrder(b))
          : a.compareTo(b));
    final primary = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        // 分组切换 + 总数
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 16, color: Colors.indigo),
                const SizedBox(width: 6),
                const Text('分组方式',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'byStudent',
                          icon: Icon(Icons.person, size: 14),
                          label: Text('按学号', style: TextStyle(fontSize: 11))),
                      ButtonSegment(
                          value: 'byTask',
                          icon: Icon(Icons.assignment, size: 14),
                          label: Text('按实验', style: TextStyle(fontSize: 11))),
                      ButtonSegment(
                          value: 'byGrade',
                          icon: Icon(Icons.workspace_premium, size: 14),
                          label: Text('按成绩', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_groupBy},
                    onSelectionChanged: (s) =>
                        setState(() => _groupBy = s.first),
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('共 ${_reports.length}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final k in keys) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(color: primary, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _groupIcon(),
                  size: 14,
                  color: primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(k,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: primary)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${groups[k]!.length}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          for (final r in groups[k]!) _buildReportCard(context, r),
        ],
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
    final userId = report['user_id'] as String? ?? '';
    final isFromSubmissions = report['_from_submissions'] == true;
    final aiScore = (report['_ai_score'] as num?)?.round();
    final aiFeedback = report['_ai_feedback'] as String? ?? '';

    final statusColor = status == '已批改'
        ? Colors.blue
        : status == '已提交' || status == '待批改'
            ? Colors.green
            : Colors.orange;
    final statusIcon = status == '已批改'
        ? Icons.check_circle
        : status == '已提交' || status == '待批改'
            ? Icons.hourglass_bottom
            : Icons.edit_note;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isFromSubmissions && _isTeacherOrAdmin) {
            _showSubmissionGradeDialog(report);
          } else if (_isTeacherOrAdmin) {
            _showReportPreview(report);
          } else {
            _showReportEditor(report: report);
          }
        },
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
                            if (_isTeacherOrAdmin) ...[
                              Icon(Icons.person,
                                  size: 12, color: Colors.grey[400]),
                              const SizedBox(width: 4),
                              Text(userId,
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500])),
                              const SizedBox(width: 8),
                            ],
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
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 20, color: Colors.grey[500]),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showReportEditor(report: report);
                      } else if (value == 'delete') {
                        if (isFromSubmissions) {
                          _confirmDeleteSubmission(report);
                        } else {
                          _confirmDeleteReport(report);
                        }
                      } else if (value == 'preview') {
                        _showReportPreview(report);
                      } else if (value == 'grade') {
                        if (isFromSubmissions) {
                          _showSubmissionGradeDialog(report);
                        } else {
                          _showReportGradeDialog(report);
                        }
                      }
                    },
                    itemBuilder: (ctx) => _isTeacherOrAdmin
                        ? [
                            const PopupMenuItem(
                              value: 'preview',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility, size: 18),
                                  SizedBox(width: 8),
                                  Text('预览报告'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'grade',
                              child: Row(
                                children: [
                                  Icon(Icons.grading, size: 18),
                                  SizedBox(width: 8),
                                  Text('批阅'),
                                ],
                              ),
                            ),
                            if (widget.authService.isAdmin)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete,
                                        size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('删除',
                                        style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                          ]
                        : [
                            if (status != '已批改')
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    SizedBox(width: 8),
                                    Text('编辑'),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('删除',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
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
              if (aiScore != null || aiFeedback.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.purple.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 15, color: Colors.purple),
                      const SizedBox(width: 6),
                      Text(
                        aiScore == null ? 'AI 初评' : 'AI 初评：$aiScore 分',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple,
                        ),
                      ),
                      if (aiFeedback.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            aiFeedback.replaceAll('\n', ' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 教师预览学生报告内容（只读）
  void _showReportPreview(Map<String, dynamic> report) {
    final title = report['title'] as String? ?? '未命名报告';
    final userId = report['user_id'] as String? ?? '';
    final status = report['status'] as String? ?? '草稿';
    final updatedAt = report['updated_at'] as String? ?? '';
    final score = report['score'] as int?;
    final feedback = report['feedback'] as String?;

    // PDF 附件信息（lab_submissions 来源主要走这里）
    final filePaths = report['file_paths'] as String? ?? '';
    final fileNames = report['file_names'] as String? ?? '';
    final plainContent = report['content'] as String? ?? '';

    // 解析报告内容（student_reports 的结构化字段）
    Map<String, String> contentMap = {};
    final contentRaw = report['content_json'] as String?;
    if (contentRaw != null && contentRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(contentRaw) as Map;
        contentMap =
            decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (e, st) {
        swallowDebug(e, tag: 'LabReportTab.parseContent', stack: st);
      }
    }

    final hasAnyContent = contentMap.isNotEmpty ||
        plainContent.isNotEmpty ||
        filePaths.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.article_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 16),
                  maxLines: 2,
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
                // 学生信息
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text('学生：$userId',
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[700])),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == '已批改'
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(status,
                            style: TextStyle(
                                fontSize: 11,
                                color: status == '已批改'
                                    ? Colors.blue
                                    : Colors.green)),
                      ),
                    ],
                  ),
                ),
                if (updatedAt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('提交时间：$updatedAt',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
                const Divider(height: 24),
                // PDF 附件块（lab_submissions 主要数据源）
                if (filePaths.isNotEmpty || fileNames.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf,
                            color: Colors.red, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PDF 附件',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(
                                fileNames.isNotEmpty
                                    ? fileNames
                                    : filePaths
                                        .split('/')
                                        .last
                                        .split('\\')
                                        .last,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[700]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.visibility, size: 14),
                          label: const Text('打开 PDF',
                              style: TextStyle(fontSize: 11)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () => previewOrPromptSync(
                            context,
                            filePaths: filePaths,
                            fileNames: fileNames,
                            userId: userId,
                            title: '$userId - $title',
                            onSyncFinished: _loadData,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // 简单文本提交（lab_submissions.content）
                if (plainContent.isNotEmpty && contentMap.isEmpty) ...[
                  const Text('提交说明',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Text(
                      plainContent
                              .contains(LabReportValidationService.bodyMarker)
                          ? '报告正文已从 PDF 提取，用于 AI 批阅。请点击上方“打开 PDF”查看原始版式。'
                          : plainContent,
                      style: const TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // 结构化报告内容（student_reports.content_json）
                if (contentMap.isNotEmpty)
                  ...contentMap.entries.map((entry) {
                    final sectionTitle =
                        entry.key == 'content' ? '报告内容' : entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sectionTitle,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: SelectableText(
                              entry.value.isEmpty ? '（未填写）' : entry.value,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: entry.value.isEmpty
                                    ? Colors.grey[400]
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                else if (!hasAnyContent)
                  Center(
                    child: Text('报告内容为空',
                        style: TextStyle(color: Colors.grey[400])),
                  ),
                // 已有批改结果
                if (score != null) ...[
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.grading,
                                size: 16, color: Colors.blue),
                            const SizedBox(width: 6),
                            const Text('批阅结果',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                            const Spacer(),
                            Text('$score 分',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: score >= 90
                                        ? Colors.green
                                        : score >= 60
                                            ? Colors.blue
                                            : Colors.red)),
                          ],
                        ),
                        if (feedback != null && feedback.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(feedback,
                              style:
                                  const TextStyle(fontSize: 12, height: 1.5)),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showReportGradeDialog(report);
            },
            icon: const Icon(Icons.grading, size: 18),
            label: const Text('批阅'),
          ),
        ],
      ),
    );
  }

  /// 教师批阅学生报告（student_reports 来源）
  void _showReportGradeDialog(Map<String, dynamic> report) {
    final reportId = report['id'] as int?;
    final title = report['title'] as String? ?? '未命名报告';
    final userId = report['user_id'] as String? ?? '';
    final existingScore = report['score'] as int?;
    final existingFeedback = report['feedback'] as String?;

    double scoreValue = (existingScore ?? 80).toDouble();
    final feedbackCtrl = TextEditingController(text: existingFeedback ?? '');
    bool isGrading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scoreColor = scoreValue >= 90
              ? Colors.green
              : scoreValue >= 80
                  ? Colors.blue
                  : scoreValue >= 60
                      ? Colors.orange
                      : Colors.red;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.grading, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('批阅 - $title',
                      style: const TextStyle(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: SizedBox(
              width: 760,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('学生：$userId',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('评分',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${scoreValue.round()} / 100',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: scoreColor)),
                    ],
                  ),
                  Slider(
                    value: scoreValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${scoreValue.round()}',
                    onChanged: (v) => setDialogState(() => scoreValue = v),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [60, 70, 80, 85, 90, 95, 100].map((v) {
                      final isSelected = scoreValue.round() == v;
                      return ActionChip(
                        label: Text('$v',
                            style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.white : null)),
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        onPressed: () =>
                            setDialogState(() => scoreValue = v.toDouble()),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: feedbackCtrl,
                    minLines: 6,
                    maxLines: 8,
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: isGrading
                    ? null
                    : () async {
                        if (reportId == null) return;
                        setDialogState(() => isGrading = true);
                        try {
                          await widget.labTaskDao.gradeReport(
                            id: reportId,
                            score: scoreValue.round(),
                            feedback: feedbackCtrl.text.trim(),
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('批阅成功'),
                                  backgroundColor: Colors.green),
                            );
                            _loadData();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('批阅失败: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          setDialogState(() => isGrading = false);
                        }
                      },
                child: const Text('提交批阅'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteReport(Map<String, dynamic> report) {
    final reportId = report['id'] as int?;
    final title = report['title'] as String? ?? '未命名报告';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除报告"$title"吗？\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (reportId == null) return;
              Navigator.pop(ctx);
              try {
                await widget.labTaskDao.deleteReport(reportId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('报告已删除')),
                  );
                  _loadData();
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

  /// 确认删除提交（管理员）
  void _confirmDeleteSubmission(Map<String, dynamic> sub) {
    final subId = sub['id'] as int?;
    final userId = sub['user_id'] as String? ?? '';
    final title = sub['title'] as String? ?? sub['task_title'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
            '确定删除 $userId 的提交${title.isNotEmpty ? "「$title」" : ""}？\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (subId == null) return;
              Navigator.pop(ctx);
              try {
                await widget.labTaskDao.deleteSubmission(subId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已删除提交')),
                  );
                  _loadData();
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

  /// 教师批改来自 lab_submissions 的提交（含 AI 批阅）
  void _showSubmissionGradeDialog(Map<String, dynamic> submission) {
    final subId = submission['id'] as int?;
    final title = submission['title'] as String? ?? '实验提交';
    final content = submission['content'] as String? ?? '';
    final fileNames = submission['file_names'] as String? ?? '';
    final filePaths = submission['file_paths'] as String? ?? '';
    final userId = submission['user_id'] as String? ?? '';
    final existingScore = submission['score'] as int?;
    final existingFeedback = submission['feedback'] as String?;
    final aiScore = (submission['_ai_score'] as num?)?.round();
    final aiFeedback = submission['_ai_feedback'] as String? ?? '';
    final aiResultId = submission['_ai_result_id'] as int?;

    double scoreValue = (existingScore ?? aiScore ?? 80).toDouble();
    final feedbackCtrl = TextEditingController(
        text: (existingFeedback?.trim().isNotEmpty == true)
            ? existingFeedback
            : aiFeedback);
    bool isGrading = false;
    bool isAiGrading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scoreColor = scoreValue >= 90
              ? Colors.green
              : scoreValue >= 80
                  ? Colors.blue
                  : scoreValue >= 60
                      ? Colors.orange
                      : Colors.red;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.grading, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('批改 - $title',
                      style: const TextStyle(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: SizedBox(
              width: 760,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('学生：$userId',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('报告正文：已提取，点击附件预览查看 PDF 原文',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                  if (fileNames.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.picture_as_pdf,
                            color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('附件：$fileNames',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (filePaths.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.visibility, size: 14),
                            label: const Text('预览',
                                style: TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => previewOrPromptSync(
                              context,
                              filePaths: filePaths,
                              fileNames: fileNames,
                              userId: userId,
                              title: '$userId - $title',
                              onSyncFinished: _loadData,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (aiScore != null || aiFeedback.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.purple.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 16, color: Colors.purple),
                              const SizedBox(width: 6),
                              Text(
                                aiScore == null ? 'AI 初评' : 'AI 初评：$aiScore 分',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple),
                              ),
                            ],
                          ),
                          if (aiFeedback.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(aiFeedback,
                                style: const TextStyle(
                                    fontSize: 12, height: 1.35)),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 评分
                  Row(
                    children: [
                      const Text('评分',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${scoreValue.round()} / 100',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: scoreColor)),
                    ],
                  ),
                  Slider(
                    value: scoreValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${scoreValue.round()}',
                    onChanged: (v) => setDialogState(() => scoreValue = v),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [60, 70, 80, 85, 90, 95, 100].map((v) {
                      final isSelected = scoreValue.round() == v;
                      return ActionChip(
                        label: Text('$v',
                            style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.white : null)),
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        onPressed: () =>
                            setDialogState(() => scoreValue = v.toDouble()),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: feedbackCtrl,
                    minLines: 6,
                    maxLines: 8,
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
            actions: [
              // AI 批阅按钮
              OutlinedButton.icon(
                onPressed: isAiGrading
                    ? null
                    : () async {
                        setDialogState(() => isAiGrading = true);
                        try {
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
                            taskTitle: title,
                            content: prepared.content,
                          );
                          // 尝试解析 JSON 格式评分
                          final parsed = tryParseGradingJson(result);
                          if (parsed != null) {
                            setDialogState(() {
                              scoreValue =
                                  (parsed['total_score'] as num?)?.toDouble() ??
                                      (parsed['score'] as num?)?.toDouble() ??
                                      scoreValue;
                              if (scoreValue > 100) scoreValue = 100;
                              feedbackCtrl.text = formatGradingFeedback(parsed);
                            });
                          } else {
                            setDialogState(() {
                              feedbackCtrl.text = result
                                  .replaceAll(
                                      RegExp(r'```(?:json)?',
                                          caseSensitive: false),
                                      '')
                                  .replaceAll('```', '')
                                  .trim();
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
                          if (subId != null) {
                            await widget.labTaskDao.gradeSubmission(
                              subId,
                              score: scoreValue.round(),
                              feedback: feedbackCtrl.text.trim().isNotEmpty
                                  ? feedbackCtrl.text.trim()
                                  : null,
                              scorerId: widget.authService.getCurrentUserId(),
                            );
                            if (aiResultId != null) {
                              await GradingResultDao().approveResult(
                                aiResultId,
                                widget.authService.getCurrentUserId() ??
                                    'teacher',
                              );
                            }
                          }
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('批改成功')),
                            );
                          }
                          _loadData();
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
                icon: const Icon(Icons.check, size: 18),
                label: const Text('提交批改'),
              ),
            ],
          );
        },
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
      } catch (e, st) {
        swallowDebug(e, tag: 'LabReportTab.parseSections', stack: st);
      }
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
        } catch (e, st) {
          swallowDebug(e, tag: 'LabReportTab.parseEditContent', stack: st);
        }
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
                          Text('支持 ZIP/PDF/图片 格式（后续版本开放）',
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

      // 提交报告后立即触发同步上传
      if (status == '已提交') {
        unawaited(SyncService().uploadStudentData(userId));
      }

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
