import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/score_colors.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/assessment_dao.dart';
import '../../../services/agent/agents/grading_agent.dart';
import '../../../services/assessment_pdf_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/pdf_text_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/sync_service.dart';

/// 审核打印面板。
///
/// 学生端提交单份「课程考核大作业报告」终稿；教师端审核该终稿，
/// 审核通过后生成封面 + 指导教师评语/成绩 + 终稿正文的完整打印 PDF。
class AuditPrintPanel extends StatefulWidget {
  final bool isStudent;
  final String? currentUserId;
  final AuthService authService;
  final List<Map<String, dynamic>> submissions;
  final Future<void> Function(String reportType) onPickAndUploadPdf;
  final void Function(Map<String, dynamic> submission) onShowGradeDialog;
  final void Function(String filePath, String title,
      {String? userId, String? fileName}) onOpenPdfPreview;
  final Future<void> Function(int id) onDeleteSubmission;
  final Future<void> Function() onReload;

  const AuditPrintPanel({
    super.key,
    required this.isStudent,
    required this.currentUserId,
    required this.authService,
    required this.submissions,
    required this.onPickAndUploadPdf,
    required this.onShowGradeDialog,
    required this.onOpenPdfPreview,
    required this.onDeleteSubmission,
    required this.onReload,
  });

  @override
  State<AuditPrintPanel> createState() => _AuditPrintPanelState();
}

class _AuditPrintPanelState extends State<AuditPrintPanel> {
  final _dao = AssessmentDao();

  int _step = 0;
  int? _selectedReportId;
  bool _generating = false;
  bool _aiGenerating = false;
  bool _autoFilled = false;
  double _pageMarginMm = 20;
  bool _duplex = true;

  final _docTitleCtrl = TextEditingController(text: '软件开发类课程考查报告');
  final _collegeCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _classNameCtrl = TextEditingController();
  final _studentNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _projectTitleCtrl = TextEditingController();
  final _advisorCtrl = TextEditingController();
  final _dateRangeCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  int? _projectScore;
  int? _groupScore;
  int? _personalScore;
  int? _defenseScore;

  bool get _canEditReview => !widget.isStudent;

  List<Map<String, dynamic>> get _finalReports => widget.submissions
      .where((s) =>
          (s['title'] as String?) == AssessmentDao.finalAssessmentReportType)
      .toList();

  Map<String, dynamic>? get _selectedReport {
    final reports = _finalReports;
    if (reports.isEmpty) return null;
    if (_selectedReportId != null) {
      for (final report in reports) {
        if (report['id'] == _selectedReportId) return report;
      }
    }
    if (widget.isStudent) {
      final uid = widget.currentUserId;
      for (final report in reports) {
        if (report['user_id'] == uid) return report;
      }
    }
    return reports.first;
  }

  bool get _isApproved => _selectedReport?['status'] == '审核通过';

  @override
  void initState() {
    super.initState();
    _selectDefaultReport();
    _autoFillFromSystem();
  }

  @override
  void didUpdateWidget(covariant AuditPrintPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.submissions, widget.submissions)) {
      _selectDefaultReport();
      _autoFillFromSystem();
    }
  }

  @override
  void dispose() {
    _docTitleCtrl.dispose();
    _collegeCtrl.dispose();
    _courseCtrl.dispose();
    _classNameCtrl.dispose();
    _studentNameCtrl.dispose();
    _studentIdCtrl.dispose();
    _projectTitleCtrl.dispose();
    _advisorCtrl.dispose();
    _dateRangeCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _selectDefaultReport() {
    final reports = _finalReports;
    if (reports.isEmpty) {
      _selectedReportId = null;
      return;
    }
    final currentStillExists = reports.any((r) => r['id'] == _selectedReportId);
    if (currentStillExists) return;
    if (widget.isStudent) {
      final uid = widget.currentUserId;
      final own = reports.where((r) => r['user_id'] == uid).toList();
      _selectedReportId =
          (own.isNotEmpty ? own.first : reports.first)['id'] as int?;
    } else {
      _selectedReportId = reports.first['id'] as int?;
    }
  }

  Future<void> _autoFillFromSystem() async {
    final selected = _selectedReport;
    final user = widget.authService.currentUser;
    final uid = _targetUserId();

    final advisor = await SettingsService.getAdvisorName();
    final college = await SettingsService.getCollegeName();
    final course = await SettingsService.getCourseName();

    Map<String, dynamic> coverData = const {};
    if (uid.isNotEmpty) {
      try {
        coverData = await _dao.getCoverData(uid);
      } catch (e, st) {
        swallowDebug(e, tag: 'AuditPrintPanel.coverData', stack: st);
      }
    }

    final review = _decodeObject(selected?['review_json'] as String?);
    final cover = _decodeNested(review, 'cover');
    final grading = _decodeNested(review, 'grading');
    final printSettings =
        _decodeObject(selected?['print_settings_json'] as String?);

    if (!mounted) return;
    setState(() {
      _docTitleCtrl.text =
          _stringValue(cover['docTitle'], fallback: '软件开发类课程考查报告');
      _collegeCtrl.text = _stringValue(cover['collegeName'], fallback: college);
      _courseCtrl.text = _stringValue(cover['courseName'], fallback: course);
      _classNameCtrl.text = _stringValue(
        cover['className'],
        fallback: (coverData['className'] as String? ?? '').trim(),
      );
      _studentNameCtrl.text = _stringValue(
        cover['studentName'],
        fallback: (coverData['studentName'] as String? ?? '').trim().isNotEmpty
            ? (coverData['studentName'] as String).trim()
            : (uid == user?.userId ? (user?.realName ?? '') : ''),
      );
      _studentIdCtrl.text = _stringValue(cover['studentId'], fallback: uid);
      _projectTitleCtrl.text = _stringValue(
        cover['projectTitle'],
        fallback: (coverData['projectName'] as String? ?? '').trim(),
      );
      _advisorCtrl.text = _stringValue(cover['advisorName'], fallback: advisor);
      _dateRangeCtrl.text =
          _stringValue(cover['dateRange'], fallback: _defaultDateRange());

      _commentCtrl.text = _stringValue(
        grading['advisorComment'],
        fallback: (selected?['feedback'] as String? ?? '').isNotEmpty
            ? selected!['feedback'] as String
            : _composeFallbackComment(
                (coverData['feedbacks'] as Map<String, String>?) ?? const {}),
      );
      _projectScore = _intValue(grading['projectScore']) ??
          _scoreFromCoverData(coverData, '项目报告');
      _groupScore = _intValue(grading['groupScore']) ??
          _scoreFromCoverData(coverData, '小组报告');
      _personalScore = _intValue(grading['personalScore']) ??
          _scoreFromCoverData(coverData, '个人报告');
      _defenseScore = _intValue(grading['defenseScore']) ??
          _scoreFromCoverData(coverData, '答辩报告');

      _pageMarginMm =
          (_numValue(printSettings?['pageMarginMm']) ?? _pageMarginMm)
              .clamp(10, 30)
              .toDouble();
      _duplex = printSettings?['duplex'] as bool? ?? _duplex;
      _autoFilled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onReload,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepper(),
            const SizedBox(height: 14),
            if (_step == 0) _buildAuditStep() else _buildPrintStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Row(
      children: [
        _stepDot(0, '审核版本', Icons.fact_check),
        Expanded(
          child: Container(
            height: 2,
            color: _step >= 1 ? Colors.indigo : Colors.grey[300],
          ),
        ),
        _stepDot(1, '打印', Icons.print),
      ],
    );
  }

  Widget _stepDot(int idx, String label, IconData icon) {
    final active = _step >= idx;
    final color = active ? Colors.indigo : Colors.grey[400]!;
    return InkWell(
      onTap: () {
        if (idx == 1 && !_isApproved) {
          _showSnack('审核通过后才能进入打印页', isError: true);
          return;
        }
        setState(() => _step = idx);
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditStep() {
    final selected = _selectedReport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isStudent)
          _buildStudentSubmitCard()
        else
          _buildTeacherSelector(),
        const SizedBox(height: 14),
        if (!widget.isStudent && selected == null)
          _emptyCard('暂无学生提交最终大作业报告')
        else ...[
          _buildCoverFormCard(),
          const SizedBox(height: 14),
          _buildGradingFormCard(),
          const SizedBox(height: 14),
          _buildScoreFormCard(),
          const SizedBox(height: 14),
          _buildAuditActionsCard(),
        ],
      ],
    );
  }

  Widget _buildStudentSubmitCard() {
    final report = _selectedReport;
    final status = report?['status'] as String? ?? '未提交';
    final fileName = report?['content_json'] as String? ?? '';
    final isApproved = status == '审核通过';
    final canReplace = !isApproved;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.upload_file, size: 18, color: Colors.indigo),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('提交最终大作业报告',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              fileName.isEmpty
                  ? '尚未提交 ${AssessmentDao.finalAssessmentReportType}.pdf'
                  : fileName,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            if ((report?['feedback'] as String?)?.isNotEmpty == true &&
                status == '已打回') ...[
              const SizedBox(height: 8),
              _warningBox(report!['feedback'] as String),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: canReplace
                      ? () => widget.onPickAndUploadPdf(
                            AssessmentDao.finalAssessmentReportType,
                          )
                      : null,
                  icon: Icon(report == null ? Icons.upload : Icons.refresh,
                      size: 16),
                  label: Text(report == null ? '上传终稿' : '重新提交'),
                ),
                if (report != null)
                  OutlinedButton.icon(
                    onPressed: () => _previewOriginalReport(report),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('预览终稿'),
                  ),
                if (report != null && canReplace)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await widget.onDeleteSubmission(report['id'] as int);
                      _selectDefaultReport();
                      await _autoFillFromSystem();
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherSelector() {
    final reports = _finalReports;
    if (reports.isEmpty) return _emptyCard('暂无学生提交最终大作业报告');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.manage_search, size: 18, color: Colors.indigo),
                SizedBox(width: 6),
                Text('选择审核版本',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: ValueKey(_selectedReport?['id']),
              value: _selectedReport?['id'] as int?,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: reports.map((report) {
                final id = report['id'] as int;
                final uid = report['user_id'] as String? ?? '';
                final fileName = report['content_json'] as String? ?? '';
                final status = report['status'] as String? ?? '已提交';
                return DropdownMenuItem<int>(
                  value: id,
                  child: Text(
                    '$uid · ${fileName.isNotEmpty ? fileName : AssessmentDao.finalAssessmentReportType} · $status',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id == null) return;
                setState(() => _selectedReportId = id);
                _autoFillFromSystem();
              },
            ),
            const SizedBox(height: 10),
            _buildSelectedReportMeta(),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedReportMeta() {
    final report = _selectedReport;
    if (report == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _statusChip(report['status'] as String? ?? '已提交'),
        if ((report['printed_at'] as String?)?.isNotEmpty == true)
          Chip(
            avatar: const Icon(Icons.print, size: 14),
            label: Text('已打印 ${report['print_count'] ?? 1} 次',
                style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
          ),
        OutlinedButton.icon(
          onPressed: () => _previewOriginalReport(report),
          icon: const Icon(Icons.visibility, size: 16),
          label: const Text('预览学生终稿'),
        ),
      ],
    );
  }

  Widget _buildCoverFormCard() {
    return _formCard(
      icon: Icons.article_outlined,
      title: '一、封面信息',
      subtitle: _autoFilled ? '根据学生 ID 自动填充' : '正在自动填充',
      action: TextButton.icon(
        onPressed: _autoFillFromSystem,
        icon: const Icon(Icons.refresh, size: 14),
        label: const Text('重新填充', style: TextStyle(fontSize: 11)),
      ),
      child: Column(
        children: [
          _formField('报告标题', _docTitleCtrl),
          _formField('学院名称', _collegeCtrl),
          _formField('课程名称', _courseCtrl),
          _formField('班级名称', _classNameCtrl),
          _formField('学生姓名', _studentNameCtrl),
          _formField('学    号', _studentIdCtrl),
          _formField('题    目', _projectTitleCtrl),
          _formField('指导教师', _advisorCtrl),
          _formField('起止日期', _dateRangeCtrl),
        ],
      ),
    );
  }

  Widget _buildGradingFormCard() {
    return _formCard(
      icon: Icons.rate_review,
      title: '二、指导教师评语',
      subtitle: widget.isStudent ? '教师审核后显示最终评语' : 'AI 自动生成，可人工修订',
      action: widget.isStudent
          ? null
          : OutlinedButton.icon(
              onPressed: _aiGenerating ? null : _generateAdvisorComment,
              icon: _aiGenerating
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 14),
              label: Text(_aiGenerating ? '生成中' : 'AI 生成',
                  style: const TextStyle(fontSize: 11)),
              style:
                  OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple),
            ),
      child: TextField(
        controller: _commentCtrl,
        enabled: _canEditReview,
        maxLines: 6,
        minLines: 4,
        decoration: InputDecoration(
          hintText: '请输入指导教师评语',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: const TextStyle(fontSize: 13, height: 1.6),
      ),
    );
  }

  Widget _buildScoreFormCard() {
    final total = _computedTotal();
    return _formCard(
      icon: Icons.leaderboard,
      title: '三、成绩评定',
      subtitle: widget.isStudent ? '成绩由教师审核后填入' : '教师手动填写，AI 不直接决定最终成绩',
      child: Column(
        children: [
          _scoreRow('项目', 30, _projectScore,
              (v) => setState(() => _projectScore = v)),
          _scoreRow(
              '小组', 20, _groupScore, (v) => setState(() => _groupScore = v)),
          _scoreRow('个人', 20, _personalScore,
              (v) => setState(() => _personalScore = v)),
          _scoreRow('答辩', 30, _defenseScore,
              (v) => setState(() => _defenseScore = v)),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('总成绩',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              Text(total == null ? '未评' : '$total 分',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scoreColorMaterial(total))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuditActionsCard() {
    final selected = _selectedReport;
    final approved = selected?['status'] == '审核通过';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check, size: 18, color: Colors.indigo),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('审核操作',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                if (selected != null)
                  _statusChip(selected['status'] as String? ?? '已提交'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: selected == null || _generating
                      ? null
                      : _previewReviewPdf,
                  icon: _busyIcon(Icons.visibility),
                  label: const Text('全文预览审核版本'),
                ),
                if (!widget.isStudent) ...[
                  FilledButton.icon(
                    onPressed:
                        selected == null || _generating ? null : _approveReport,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('审核通过'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        selected == null || _generating ? null : _rejectReport,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('不通过'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700]),
                  ),
                ],
                FilledButton.tonalIcon(
                  onPressed: approved ? () => setState(() => _step = 1) : null,
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('进入打印'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrintStep() {
    final selected = _selectedReport;
    if (selected == null) return _emptyCard('暂无可打印的审核版本');
    if (selected['status'] != '审核通过') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emptyCard('审核通过后才能打印'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回审核'),
          ),
        ],
      );
    }

    final total = _computedTotal();
    final printedAt = selected['printed_at'] as String? ?? '';
    final printCount = selected['print_count'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _formCard(
          icon: Icons.summarize,
          title: '打印预览',
          child: Column(
            children: [
              _summaryRow(Icons.person, '学生',
                  '${_studentNameCtrl.text} (${_studentIdCtrl.text})'),
              _summaryRow(Icons.class_, '班级', _classNameCtrl.text),
              _summaryRow(Icons.assignment, '项目题目', _projectTitleCtrl.text),
              _summaryRow(Icons.school, '指导教师', _advisorCtrl.text),
              _summaryRow(Icons.picture_as_pdf, '终稿文件',
                  selected['content_json'] as String? ?? ''),
              const Divider(),
              _summaryRow(
                  Icons.leaderboard, '总成绩', total == null ? '未评' : '$total 分'),
              _summaryRow(
                Icons.print,
                '打印状态',
                printedAt.isEmpty ? '未打印' : '已打印 $printCount 次',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildPrintSettingsCard(),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('返回审核'),
            ),
            OutlinedButton.icon(
              onPressed: _generating ? null : _previewReviewPdf,
              icon: _busyIcon(Icons.visibility),
              label: const Text('预览打印稿'),
            ),
            FilledButton.icon(
              onPressed: _generating ? null : _printNow,
              icon: _busyIcon(Icons.print),
              label: Text(_generating ? '生成中' : '打印'),
            ),
            OutlinedButton.icon(
              onPressed: _generating ? null : _saveReviewPdf,
              icon: const Icon(Icons.save_alt, size: 16),
              label: const Text('保存 PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _generating ? null : _markPrintedManually,
              icon: const Icon(Icons.done_all, size: 16),
              label: const Text('标记已打印'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrintSettingsCard() {
    return _formCard(
      icon: Icons.tune,
      title: '打印设置',
      subtitle: '页边距会应用到审核 PDF；双面打印需在系统打印对话框中确认',
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 86,
                child: Text('统一页边距',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Slider(
                  value: _pageMarginMm,
                  min: 10,
                  max: 30,
                  divisions: 20,
                  label: '${_pageMarginMm.round()} mm',
                  onChanged: (v) => setState(() => _pageMarginMm = v),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text('${_pageMarginMm.round()} mm',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _duplex,
            onChanged: (v) => setState(() => _duplex = v),
            title: const Text('双面打印', style: TextStyle(fontSize: 13)),
            subtitle:
                const Text('打印时在系统对话框选择双面', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _formCard({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
    required Widget child,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.indigo),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      if (subtitle != null)
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                ),
                if (action != null) action,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _formField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              enabled: _canEditReview,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreRow(
      String label, int weight, int? score, ValueChanged<int?> onChanged) {
    final color = scoreColorMaterial(score);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$weight%',
                style: TextStyle(fontSize: 10, color: Colors.grey[700])),
          ),
          Expanded(
            child: Slider(
              value: (score ?? 0).toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              activeColor: color,
              label: score?.toString() ?? '0',
              onChanged: _canEditReview ? (v) => onChanged(v.round()) : null,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              score == null ? '未评' : '$score 分',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.indigo),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Flexible(
            flex: 2,
            child: Text(value.isNotEmpty ? value : '—',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(_statusIcon(status), size: 14, color: color),
      label: Text(status, style: TextStyle(fontSize: 11, color: color)),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }

  Widget _warningBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: Colors.red[700], height: 1.4)),
    );
  }

  Widget _emptyCard(String message) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 42, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Widget _busyIcon(IconData icon) {
    if (!_generating) return Icon(icon, size: 16);
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _generateAdvisorComment() async {
    if (!await SettingsService.isTeacherAiGradingEnabled()) {
      _showSnack('教师 AI 批阅已关闭，请在系统设置中开启后再使用。', isError: true);
      return;
    }
    final report = _selectedReport;
    if (report == null) return;

    setState(() => _aiGenerating = true);
    try {
      final filePath = report['file_path'] as String? ?? '';
      var content = report['content_json'] as String? ?? '';
      if (filePath.isNotEmpty && File(filePath).existsSync()) {
        final extracted =
            await PdfTextService.extractFromFile(filePath, maxChars: 9000);
        if (extracted != null && extracted.trim().isNotEmpty) {
          content = extracted;
        }
      }
      final result = await GradingAgent().gradeReport(
        reportType: '课程考核大作业教师评语',
        studentName: _studentNameCtrl.text,
        projectName: _projectTitleCtrl.text,
        groupName: _classNameCtrl.text,
        content:
            '请只生成 200-400 字指导教师评语，不给最终成绩。评语需覆盖选题、实现、团队/个人贡献、答辩表现、不足与改进。\n\n$content',
      );
      if (!mounted) return;
      setState(() => _commentCtrl.text = _stripJsonWrap(result));
    } catch (e) {
      _showSnack('AI 生成失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _aiGenerating = false);
    }
  }

  Future<void> _approveReport() async {
    final report = _selectedReport;
    if (report == null) return;
    final total = _computedTotal();
    if (total == null) {
      _showSnack('请先填写项目、小组、个人、答辩成绩', isError: true);
      return;
    }
    setState(() => _generating = true);
    try {
      await _dao.approveFinalAssessmentReport(
        reportId: report['id'] as int,
        score: total,
        feedback: _commentCtrl.text.trim(),
        reviewData: _currentReviewData(),
        reviewerId: widget.authService.getCurrentUserId(),
      );
      await NotificationService().notifyAssessmentGradeApproved(
        studentId: report['user_id'] as String? ?? '',
        reportType: AssessmentDao.finalAssessmentReportType,
        score: total,
      );
      await widget.onReload();
      if ((report['user_id'] as String?)?.isNotEmpty == true) {
        await SyncService().uploadStudentData(report['user_id'] as String);
      }
      if (!mounted) return;
      _selectDefaultReport();
      setState(() => _step = 1);
      _showSnack('审核通过，已进入打印页');
    } catch (e) {
      _showSnack('审核通过失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _rejectReport() async {
    final report = _selectedReport;
    if (report == null) return;
    final ctrl =
        TextEditingController(text: report['feedback'] as String? ?? '');
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('审核不通过'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            minLines: 6,
            maxLines: 10,
            decoration: InputDecoration(
              labelText: '问题与改进建议',
              hintText: '说明未通过原因，以及学生需要补充或修改的内容',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            icon: const Icon(Icons.assignment_return, size: 18),
            label: const Text('确认退回'),
          ),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _generating = true);
    try {
      await _dao.returnStudentReport(
        report['id'] as int,
        reason: reason.trim(),
        reviewerId: widget.authService.getCurrentUserId(),
      );
      await NotificationService().notifyAssessmentReportReturned(
        studentId: report['user_id'] as String? ?? '',
        reportTitle: AssessmentDao.finalAssessmentReportType,
        reason: reason.trim(),
      );
      await widget.onReload();
      if ((report['user_id'] as String?)?.isNotEmpty == true) {
        await SyncService().uploadStudentData(report['user_id'] as String);
      }
      if (!mounted) return;
      _selectDefaultReport();
      setState(() => _step = 0);
      _showSnack('已退回并通知学生');
    } catch (e) {
      _showSnack('退回失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _previewReviewPdf() async {
    setState(() => _generating = true);
    try {
      final path = await _saveGeneratedPdf();
      if (path == null) throw Exception('PDF 生成失败');
      if (!mounted) return;
      widget.onOpenPdfPreview(path, '课程考核大作业审核版本');
    } catch (e) {
      _showSnack('预览失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveReviewPdf() async {
    setState(() => _generating = true);
    try {
      final path = await _saveGeneratedPdf();
      if (path == null) throw Exception('PDF 生成失败');
      _showSnack('已保存：$path');
    } catch (e) {
      _showSnack('保存失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _printNow() async {
    final report = _selectedReport;
    if (report == null) return;
    setState(() => _generating = true);
    try {
      final bytes = await _generatePdf();
      final printed = await AssessmentPdfService.printPdf(
        bytes,
        name: '${_studentIdCtrl.text}-课程考核大作业审核版',
        pageMarginMm: _pageMarginMm,
      );
      if (printed) {
        await _markPrinted(report);
        _showSnack('已打印并标记');
      }
    } catch (e) {
      _showSnack('打印失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _markPrintedManually() async {
    final report = _selectedReport;
    if (report == null) return;
    setState(() => _generating = true);
    try {
      await _markPrinted(report);
      _showSnack('已标记为已打印');
    } catch (e) {
      _showSnack('标记失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _markPrinted(Map<String, dynamic> report) async {
    await _dao.markFinalAssessmentReportPrinted(
      reportId: report['id'] as int,
      printSettings: _printSettings(),
    );
    await widget.onReload();
    _selectDefaultReport();
  }

  Future<String?> _saveGeneratedPdf() async {
    final bytes = await _generatePdf();
    final fileName =
        '${_studentIdCtrl.text}-课程考核大作业审核版-${DateTime.now().millisecondsSinceEpoch}';
    return AssessmentPdfService.saveToFile(bytes, fileName);
  }

  Future<Uint8List> _generatePdf() {
    final data = AuditedReportData(
      cover: _cover(),
      grading: _grading(),
      reports: const [],
      finalReport: _finalReportAttachment(),
    );
    return AssessmentPdfService.buildAuditedReportPdf(
      data: data,
      includeCover: true,
      includeGrading: true,
      includeReports: false,
      includeFinalReport: true,
      pageMarginMm: _pageMarginMm,
    );
  }

  void _previewOriginalReport(Map<String, dynamic> report) {
    widget.onOpenPdfPreview(
      report['file_path'] as String? ?? '',
      AssessmentDao.finalAssessmentReportType,
      userId: report['user_id'] as String?,
      fileName: report['content_json'] as String?,
    );
  }

  CoverInfo _cover() => CoverInfo(
        docTitle: _docTitleCtrl.text.trim(),
        collegeName: _collegeCtrl.text.trim(),
        courseName: _courseCtrl.text.trim(),
        className: _classNameCtrl.text.trim(),
        studentName: _studentNameCtrl.text.trim(),
        studentId: _studentIdCtrl.text.trim(),
        projectTitle: _projectTitleCtrl.text.trim(),
        advisorName: _advisorCtrl.text.trim(),
        dateRange: _dateRangeCtrl.text.trim(),
      );

  GradingInfo _grading() => GradingInfo(
        advisorComment: _commentCtrl.text.trim(),
        projectScore: _projectScore,
        groupScore: _groupScore,
        personalScore: _personalScore,
        defenseScore: _defenseScore,
        advisorName: _advisorCtrl.text.trim(),
        signDate: _todayCN(),
      );

  FinalReportAttachment? _finalReportAttachment() {
    final report = _selectedReport;
    if (report == null) return null;
    return FinalReportAttachment(
      title: AssessmentDao.finalAssessmentReportType,
      fileName: report['content_json'] as String? ?? '',
      filePath: report['file_path'] as String? ?? '',
      status: report['status'] as String? ?? '已提交',
      submittedAt: report['submit_time'] as String? ?? '',
    );
  }

  Map<String, dynamic> _currentReviewData() => {
        'cover': {
          'docTitle': _docTitleCtrl.text.trim(),
          'collegeName': _collegeCtrl.text.trim(),
          'courseName': _courseCtrl.text.trim(),
          'className': _classNameCtrl.text.trim(),
          'studentName': _studentNameCtrl.text.trim(),
          'studentId': _studentIdCtrl.text.trim(),
          'projectTitle': _projectTitleCtrl.text.trim(),
          'advisorName': _advisorCtrl.text.trim(),
          'dateRange': _dateRangeCtrl.text.trim(),
        },
        'grading': {
          'advisorComment': _commentCtrl.text.trim(),
          'projectScore': _projectScore,
          'groupScore': _groupScore,
          'personalScore': _personalScore,
          'defenseScore': _defenseScore,
          'totalScore': _computedTotal(),
          'advisorName': _advisorCtrl.text.trim(),
          'signDate': _todayCN(),
        },
        'finalReport': {
          'id': _selectedReport?['id'],
          'fileName': _selectedReport?['content_json'],
          'submittedAt': _selectedReport?['submit_time'],
        },
      };

  Map<String, dynamic> _printSettings() => {
        'pageMarginMm': _pageMarginMm.round(),
        'duplex': _duplex,
        'paper': 'A4',
      };

  int? _computedTotal() => _grading().totalScore;

  String _targetUserId() {
    final selected = _selectedReport;
    final selectedUser = selected?['user_id'] as String?;
    if (selectedUser != null && selectedUser.isNotEmpty) return selectedUser;
    return widget.currentUserId ?? widget.authService.currentUser?.userId ?? '';
  }

  int? _scoreFromCoverData(Map<String, dynamic> coverData, String key) {
    final scores = coverData['scores'];
    if (scores is Map<String, int>) return scores[key];
    if (scores is Map) return _intValue(scores[key]);
    return null;
  }

  String _composeFallbackComment(Map<String, String> feedbacks) {
    if (feedbacks.isEmpty) return '';
    final parts = <String>[];
    for (final key in const ['项目报告', '小组报告', '个人报告', '答辩报告']) {
      final fb = feedbacks[key];
      if (fb != null && fb.isNotEmpty) parts.add('【$key】$fb');
    }
    return parts.join('\n\n');
  }

  String _defaultDateRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, now.day);
    return '${start.year}年${start.month}月${start.day}日至'
        '${now.year}年${now.month}月${now.day}日';
  }

  String _todayCN() {
    final now = DateTime.now();
    return '${now.year}年${now.month}月${now.day}日';
  }

  Map<String, dynamic>? _decodeObject(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e, st) {
      swallowDebug(e, tag: 'AuditPrintPanel.decodeJson', stack: st);
    }
    return null;
  }

  Map<String, dynamic> _decodeNested(Map<String, dynamic>? raw, String key) {
    final value = raw?[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String _stringValue(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  num? _numValue(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String _stripJsonWrap(String s) {
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(s);
    if (m == null) return s.trim();
    try {
      final decoded = jsonDecode(m.group(0)!);
      if (decoded is Map) {
        final feedback = decoded['feedback'] ?? decoded['summary'];
        if (feedback != null && feedback.toString().trim().isNotEmpty) {
          return feedback.toString().trim();
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AuditPrintPanel.stripJson', stack: st);
    }
    return s.trim();
  }

  Color _statusColor(String status) {
    if (status == '审核通过' || status == '已批改') return Colors.green;
    if (status == '已打回' || status == '审核未通过') return Colors.red;
    if (status.contains('打印')) return Colors.teal;
    return Colors.orange;
  }

  IconData _statusIcon(String status) {
    if (status == '审核通过' || status == '已批改') return Icons.check_circle;
    if (status == '已打回' || status == '审核未通过') return Icons.cancel;
    if (status.contains('打印')) return Icons.print;
    return Icons.pending_actions;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}
