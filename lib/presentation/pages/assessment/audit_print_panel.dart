import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/score_colors.dart';
import '../../../data/local/assessment_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/assessment_pdf_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/agent/agents/grading_agent.dart';

/// 审核打印面板 — 替代原"提交"Tab。
///
/// 两步流程：
///   ① 审核支撑材料：上传/审核 4 项 PDF + 填写 [封面 / 批阅 / 成绩] 表单（自动预填）
///   ② 打印完整报告：对齐学院模板生成单一整合 PDF（封面 + 评定页 + 支撑材料审核明细）
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
  /// 步骤切换 0=审核 1=打印
  int _step = 0;

  /// PDF 内容开关（封面 / 评定 / 报告明细）
  bool _includeCover = true;
  bool _includeGrading = true;
  bool _includeReports = true;

  bool _generating = false;
  bool _aiGenerating = false;

  /// 封面字段
  final _docTitleCtrl = TextEditingController(text: '软件开发类课程考查报告');
  final _collegeCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _classNameCtrl = TextEditingController();
  final _studentNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _projectTitleCtrl = TextEditingController();
  final _advisorCtrl = TextEditingController();
  final _dateRangeCtrl = TextEditingController();

  /// 批阅 / 成绩字段
  final _commentCtrl = TextEditingController();
  int? _projectScore;
  int? _groupScore;
  int? _personalScore;
  int? _defenseScore;

  bool _autoFilled = false;

  @override
  void initState() {
    super.initState();
    _autoFillFromSystem();
  }

  @override
  void didUpdateWidget(covariant AuditPrintPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.submissions, widget.submissions)) {
      _refillScoresFromSubmissions();
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

  Future<void> _autoFillFromSystem() async {
    final user = widget.authService.currentUser;
    final uid = widget.currentUserId ?? user?.userId ?? '';

    final advisor = await SettingsService.getAdvisorName();
    final college = await SettingsService.getCollegeName();
    final course = await SettingsService.getCourseName();

    Map<String, dynamic> coverData = const {};
    if (uid.isNotEmpty) {
      try {
        coverData = await AssessmentDao().getCoverData(uid);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _collegeCtrl.text = college;
      _courseCtrl.text = course;
      _classNameCtrl.text = (coverData['className'] as String? ?? '').trim();
      _studentNameCtrl.text = user?.realName ?? '';
      _studentIdCtrl.text = uid;
      _projectTitleCtrl.text =
          (coverData['projectName'] as String? ?? '').trim();
      _advisorCtrl.text = advisor;
      _dateRangeCtrl.text = _defaultDateRange();

      final scores = (coverData['scores'] as Map<String, int>?) ?? {};
      _projectScore = scores['项目报告'];
      _groupScore = scores['小组报告'];
      _personalScore = scores['个人报告'];
      _defenseScore = scores['答辩报告'];

      final feedbacks = (coverData['feedbacks'] as Map<String, String>?) ?? {};
      if (_commentCtrl.text.isEmpty) {
        _commentCtrl.text = _composeFallbackComment(feedbacks);
      }

      _autoFilled = true;
    });
  }

  /// 当父组件重新加载提交（如完成批阅后），用最新评分覆盖未手改的字段。
  void _refillScoresFromSubmissions() {
    final byType = <String, Map<String, dynamic>>{};
    for (final s in widget.submissions) {
      final title = s['title'] as String? ?? '';
      for (final key in const ['答辩报告', '个人报告', '小组报告', '项目报告']) {
        if (title.contains(key)) {
          byType[key] = s;
          break;
        }
      }
    }
    setState(() {
      _projectScore ??= byType['项目报告']?['score'] as int?;
      _groupScore ??= byType['小组报告']?['score'] as int?;
      _personalScore ??= byType['个人报告']?['score'] as int?;
      _defenseScore ??= byType['答辩报告']?['score'] as int?;
    });
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

  // ════════════════════════════════════════════════════════
  //  Build
  // ════════════════════════════════════════════════════════
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
        _stepDot(0, '审核材料', Icons.fact_check),
        Expanded(
          child: Container(
            height: 2,
            color: _step >= 1 ? Colors.indigo : Colors.grey[300],
          ),
        ),
        _stepDot(1, '完整报告', Icons.print),
      ],
    );
  }

  Widget _stepDot(int idx, String label, IconData icon) {
    final active = _step >= idx;
    final color = active ? Colors.indigo : Colors.grey[400]!;
    return InkWell(
      onTap: () => setState(() => _step = idx),
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

  // ════════════════════════════════════════════════════════
  //  步骤一：审核
  // ════════════════════════════════════════════════════════
  Widget _buildAuditStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isStudent) ...[
          _buildUploadSection(),
          const SizedBox(height: 14),
        ],
        _buildCoverFormCard(),
        const SizedBox(height: 14),
        _buildGradingFormCard(),
        const SizedBox(height: 14),
        _buildScoreFormCard(),
        const SizedBox(height: 14),
        _buildIncludeOptionsCard(),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => setState(() => _step = 1),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('下一步：生成完整报告'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  // ── 上传卡 ─────────────────────────────────────────────
  Widget _buildUploadSection() {
    final reportTypes = [
      {'key': '答辩报告', 'icon': Icons.record_voice_over, 'color': Colors.red},
      {'key': '个人报告', 'icon': Icons.person, 'color': Colors.blue},
      {'key': '小组报告', 'icon': Icons.groups, 'color': Colors.green},
      {'key': '项目报告', 'icon': Icons.folder_special, 'color': Colors.orange},
    ];
    int n = 0;
    for (final rt in reportTypes) {
      final key = rt['key'] as String;
      if (widget.submissions
          .any((s) => (s['title'] as String?)?.contains(key) == true)) {
        n++;
      }
    }

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
                const Text('上传 4 项支撑材料',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$n/4',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo[700])),
              ],
            ),
            const SizedBox(height: 8),
            ...reportTypes.map((rt) => _buildUploadRow(rt)),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadRow(Map<String, dynamic> rt) {
    final key = rt['key'] as String;
    final color = rt['color'] as Color;
    final submitted = widget.submissions
        .where((s) => (s['title'] as String?)?.contains(key) == true)
        .toList();
    final done = submitted.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : (rt['icon'] as IconData),
              size: 18, color: done ? color : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(key,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: done ? FontWeight.w600 : FontWeight.normal,
                    color: done ? color : null)),
          ),
          if (done)
            IconButton(
              icon: const Icon(Icons.visibility, size: 18),
              tooltip: '预览',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => widget.onOpenPdfPreview(
                submitted.first['file_path'] as String? ?? '',
                key,
                userId: submitted.first['user_id'] as String?,
                fileName: submitted.first['content_json'] as String?,
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => widget.onPickAndUploadPdf(key),
            icon: Icon(done ? Icons.refresh : Icons.upload, size: 14),
            label:
                Text(done ? '替换' : '上传', style: const TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  // ── 封面表单 ──────────────────────────────────────────
  Widget _buildCoverFormCard() {
    return _formCard(
      icon: Icons.article_outlined,
      title: '一、封面信息',
      subtitle: _autoFilled ? '已自动填充，可手动修改' : '正在自动填充…',
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
          _formField('班级名称', _classNameCtrl, hint: '如 计科222'),
          _formField('学生姓名', _studentNameCtrl),
          _formField('学    号', _studentIdCtrl),
          _formField('题    目', _projectTitleCtrl, hint: '项目题目'),
          _formField('指导教师', _advisorCtrl),
          _formField('起止日期', _dateRangeCtrl, hint: '2025年10月24日至2025年11月24日'),
        ],
      ),
    );
  }

  // ── 批阅表单（教师评语） ─────────────────────────────
  Widget _buildGradingFormCard() {
    return _formCard(
      icon: Icons.rate_review,
      title: '二、指导教师评语',
      subtitle: '可基于 AI 自动总评，或手动输入',
      action: OutlinedButton.icon(
        onPressed: _aiGenerating ? null : _generateAdvisorComment,
        icon: _aiGenerating
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome, size: 14),
        label: Text(_aiGenerating ? '生成中…' : 'AI 生成总评',
            style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple),
      ),
      child: TextField(
        controller: _commentCtrl,
        maxLines: 6,
        minLines: 4,
        decoration: InputDecoration(
          hintText: '请输入或 AI 生成总评（200-400 字推荐）',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: const TextStyle(fontSize: 13, height: 1.6),
      ),
    );
  }

  // ── 成绩表单 ────────────────────────────────────────
  Widget _buildScoreFormCard() {
    final total = _computedTotal();
    return _formCard(
      icon: Icons.leaderboard,
      title: '三、成绩评定',
      subtitle: '4项材料用于审核与评分，最终只生成一份完整课程考核大作业报告',
      action: TextButton.icon(
        onPressed: _refillScoresFromSubmissions,
        icon: const Icon(Icons.sync, size: 14),
        label: const Text('从提交回填', style: TextStyle(fontSize: 11)),
      ),
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
              Text(total == null ? '—' : '$total 分',
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
              onChanged: (v) => onChanged(v.round()),
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

  int? _computedTotal() => _grading().totalScore;

  // ── 内容开关 ─────────────────────────────────────────
  Widget _buildIncludeOptionsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.tune, size: 18, color: Colors.indigo),
                SizedBox(width: 6),
                Text('PDF 包含内容',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _includeCover,
              title: const Text('封面页', style: TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => _includeCover = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _includeGrading,
              title:
                  const Text('指导教师评语 + 成绩评定页', style: TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => _includeGrading = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _includeReports,
              title:
                  const Text('附 4 项支撑材料审核明细', style: TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => _includeReports = v ?? false),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  步骤二：打印
  // ════════════════════════════════════════════════════════
  Widget _buildPrintStep() {
    final total = _computedTotal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('完整报告预览',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _summaryRow(Icons.person, '学生',
                    '${_studentNameCtrl.text} (${_studentIdCtrl.text})'),
                _summaryRow(Icons.class_, '班级', _classNameCtrl.text),
                _summaryRow(Icons.assignment, '项目题目', _projectTitleCtrl.text),
                _summaryRow(Icons.school, '指导教师', _advisorCtrl.text),
                const Divider(),
                _summaryToggleRow(Icons.article_outlined, '封面', _includeCover),
                _summaryToggleRow(Icons.rate_review, '评语+成绩', _includeGrading),
                _summaryToggleRow(Icons.list_alt, '支撑材料审核明细', _includeReports),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('总成绩',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(total == null ? '—' : '$total 分',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: scoreColorMaterial(total))),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _step = 0),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('返回审核'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _generating ? null : _printNow,
                icon: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print, size: 18),
                label: Text(_generating ? '生成中…' : '生成完整报告 PDF'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _generating ? null : _saveOnly,
          icon: const Icon(Icons.save_alt, size: 16),
          label: const Text('仅保存到本地'),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10)),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  通用辅助
  // ════════════════════════════════════════════════════════
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

  Widget _formField(String label, TextEditingController ctrl, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              decoration: InputDecoration(
                hintText: hint,
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

  Widget _summaryRow(IconData icon, String label, String value,
      {bool enabled = true}) {
    final color = enabled ? Colors.indigo : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(value.isNotEmpty ? value : '—',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _summaryToggleRow(IconData icon, String label, bool enabled) =>
      _summaryRow(icon, label, enabled ? '包含' : '不含', enabled: enabled);

  // ════════════════════════════════════════════════════════
  //  AI 总评 / PDF 生成 / 保存
  // ════════════════════════════════════════════════════════
  Future<void> _generateAdvisorComment() async {
    if (!await SettingsService.isTeacherAiGradingEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('教师 AI 批阅已关闭，请在「系统设置 → 教师 AI 批阅」中开启后再使用。'),
          ),
        );
      }
      return;
    }
    setState(() => _aiGenerating = true);
    try {
      final agent = GradingAgent();
      final reports = _matchedReports();
      final feedbackJoined = reports
          .map((r) => '【${r.type}（${r.score ?? "未批"}分）】${r.feedback ?? ""}')
          .where((s) => s.contains('】') && s.endsWith(']') == false)
          .join('\n');
      final result = await agent.gradeReport(
        reportType: '考核大作业总评',
        studentName: _studentNameCtrl.text,
        content: '请基于以下4份子报告的批阅结果，撰写一段 200-400 字的指导教师评语，'
            '指出选题价值、技术亮点、不足与改进方向。\n\n$feedbackJoined',
        projectName: _projectTitleCtrl.text,
        groupName: _classNameCtrl.text,
      );
      if (mounted) {
        setState(() => _commentCtrl.text = _stripJsonWrap(result));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 生成失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiGenerating = false);
    }
  }

  String _stripJsonWrap(String s) {
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(s);
    if (m == null) return s.trim();
    try {
      final body = s.substring(m.start, m.end);
      final fb = RegExp(r'"feedback"\s*:\s*"([^"]+)"').firstMatch(body);
      if (fb != null) return fb.group(1)!.trim();
    } catch (_) {}
    return s.trim();
  }

  List<AuditedReport> _matchedReports() {
    final result = <AuditedReport>[];
    for (final key in const ['项目报告', '小组报告', '个人报告', '答辩报告']) {
      final m = widget.submissions.firstWhere(
        (s) => (s['title'] as String?)?.contains(key) == true,
        orElse: () => const {},
      );
      if (m.isEmpty) {
        result.add(AuditedReport(type: key, title: key));
      } else {
        result.add(AuditedReport(
          type: key,
          title: m['content_json'] as String? ?? key,
          score: m['score'] as int?,
          feedback: m['feedback'] as String?,
          status: m['status'] as String? ?? '已提交',
        ));
      }
    }
    return result;
  }

  CoverInfo _cover() => CoverInfo(
        docTitle: _docTitleCtrl.text,
        collegeName: _collegeCtrl.text,
        courseName: _courseCtrl.text,
        className: _classNameCtrl.text,
        studentName: _studentNameCtrl.text,
        studentId: _studentIdCtrl.text,
        projectTitle: _projectTitleCtrl.text,
        advisorName: _advisorCtrl.text,
        dateRange: _dateRangeCtrl.text,
      );

  GradingInfo _grading() => GradingInfo(
        advisorComment: _commentCtrl.text,
        projectScore: _projectScore,
        groupScore: _groupScore,
        personalScore: _personalScore,
        defenseScore: _defenseScore,
        advisorName: _advisorCtrl.text,
        signDate: _todayCN(),
      );

  Future<Uint8List?> _generatePdf() async {
    final data = AuditedReportData(
      cover: _cover(),
      grading: _grading(),
      reports: _matchedReports(),
    );
    return AssessmentPdfService.buildAuditedReportPdf(
      data: data,
      includeCover: _includeCover,
      includeGrading: _includeGrading,
      includeReports: _includeReports,
    );
  }

  Future<void> _printNow() async {
    setState(() => _generating = true);
    try {
      final bytes = await _generatePdf();
      if (bytes == null) throw Exception('PDF 数据为空');
      await AssessmentPdfService.printPdf(bytes,
          name: '${widget.currentUserId ?? "report"}-考核报告');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打印失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveOnly() async {
    setState(() => _generating = true);
    try {
      final bytes = await _generatePdf();
      if (bytes == null) throw Exception('PDF 数据为空');
      final fileName =
          '${widget.currentUserId ?? "report"}-考核报告-${DateTime.now().millisecondsSinceEpoch}';
      final path = await AssessmentPdfService.saveToFile(bytes, fileName);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存：$path'),
            action: SnackBarAction(
              label: '打开',
              onPressed: () {
                if (kIsWeb) return;
                if (Platform.isWindows) {
                  Process.run('explorer', [File(path).parent.path]);
                } else if (Platform.isMacOS) {
                  Process.run('open', [File(path).parent.path]);
                }
              },
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}
