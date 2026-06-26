import 'package:flutter/material.dart';

import '../../../../data/local/archive_dao.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../services/archive/midterm_check_draft_service.dart';

class MidtermCheckPanel extends StatefulWidget {
  final String courseType;
  final ArchiveDao dao;
  final VoidCallback? onSaved;

  const MidtermCheckPanel({
    super.key,
    required this.courseType,
    required this.dao,
    this.onSaved,
  });

  @override
  State<MidtermCheckPanel> createState() => _MidtermCheckPanelState();
}

class _MidtermCheckPanelState extends State<MidtermCheckPanel> {
  MidtermProgressStatus _progressStatus = MidtermProgressStatus.aligned;
  final _plannedController = TextEditingController(text: '期中前计划教学内容');
  final _actualController = TextEditingController(text: '期中前实际完成内容');
  final _noteController = TextEditingController();
  bool _hoursMatched = true;
  bool _labMatched = true;
  bool _adjustmentRecorded = true;
  int _homeworkAssignedCount = 0;
  int _homeworkReviewedCount = 0;
  bool _homeworkAligned = true;
  bool _homeworkFeedbackComplete = true;
  bool _examConducted = false;
  String _examMode = '阶段测验';
  bool _paperSubmitted = false;
  bool _answerSubmitted = false;
  bool _scoreSubmitted = false;
  bool _analysisSubmitted = false;
  bool _saving = false;

  @override
  void dispose() {
    _plannedController.dispose();
    _actualController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  MidtermCheckFormData _data() => MidtermCheckFormData(
        progressStatus: _progressStatus,
        plannedProgress: _plannedController.text,
        actualProgress: _actualController.text,
        hoursMatched: _hoursMatched,
        labMatched: _labMatched,
        adjustmentRecorded: _adjustmentRecorded,
        homeworkAssignedCount: _homeworkAssignedCount,
        homeworkReviewedCount: _homeworkReviewedCount,
        homeworkAligned: _homeworkAligned,
        homeworkFeedbackComplete: _homeworkFeedbackComplete,
        examConducted: _examConducted,
        examMode: _examMode,
        paperSubmitted: _paperSubmitted,
        answerSubmitted: _answerSubmitted,
        scoreSubmitted: _scoreSubmitted,
        analysisSubmitted: _analysisSubmitted,
        note: _noteController.text,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = _data();
    try {
      await _upsertDoc(
        documentType: 'midterm_progress_check',
        label: '课程进度执行检查',
        content: MidtermCheckDraftService.progressContent(data),
      );
      await _upsertDoc(
        documentType: 'midterm_homework_review',
        label: '作业与批阅次数统计',
        content: MidtermCheckDraftService.homeworkContent(data),
      );
      await _upsertDoc(
        documentType: 'midterm_exam',
        label: '期中考试',
        content: MidtermCheckDraftService.examContent(data),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已生成/更新期中核查材料')),
      );
      widget.onSaved?.call();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upsertDoc({
    required String documentType,
    required String label,
    required String content,
  }) async {
    final existing = await widget.dao.getDocuments(
      period: 'midterm',
      documentType: documentType,
    );
    final old = existing.isNotEmpty ? existing.first : null;
    final doc = ArchiveDocument(
      id: old?.id,
      title: '期中$label',
      documentType: documentType,
      period: 'midterm',
      courseId: old?.courseId,
      courseType: widget.courseType,
      status: 'draft',
      content: content.trim(),
      isGenerated: true,
      reviewJson: '',
      reviewedAt: '',
      createdAt: old?.createdAt,
    );
    await widget.dao.saveDocument(doc);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '期中重点核查',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('生成核查材料'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionTitle('进度'),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _statusChip(MidtermProgressStatus.aligned, '对齐'),
                _statusChip(MidtermProgressStatus.delayed, '滞后/延时'),
                _statusChip(MidtermProgressStatus.ahead, '超前'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _textField(
                    controller: _plannedController,
                    label: '计划进度',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _textField(
                    controller: _actualController,
                    label: '实际进度',
                  ),
                ),
              ],
            ),
            _checkbox('理论/实验学时已核对', _hoursMatched,
                (v) => setState(() => _hoursMatched = v)),
            _checkbox('实验/实践任务按进度实施', _labMatched,
                (v) => setState(() => _labMatched = v)),
            _checkbox('调课、停课、补课已有记录', _adjustmentRecorded,
                (v) => setState(() => _adjustmentRecorded = v)),
            const Divider(height: 20),
            _sectionTitle('作业'),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _counter(
                  label: '布置作业',
                  value: _homeworkAssignedCount,
                  onChanged: (v) => setState(() {
                    _homeworkAssignedCount = v;
                    if (_homeworkReviewedCount > v) {
                      _homeworkReviewedCount = v;
                    }
                  }),
                ),
                _counter(
                  label: '已批阅',
                  value: _homeworkReviewedCount,
                  max: _homeworkAssignedCount,
                  onChanged: (v) => setState(() => _homeworkReviewedCount = v),
                ),
              ],
            ),
            _checkbox('作业布置与教学进度对齐', _homeworkAligned,
                (v) => setState(() => _homeworkAligned = v)),
            _checkbox('已完成作业反馈或课堂讲评', _homeworkFeedbackComplete,
                (v) => setState(() => _homeworkFeedbackComplete = v)),
            const Divider(height: 20),
            _sectionTitle('期中考试/阶段考核'),
            _checkbox('已组织期中考试或阶段考核', _examConducted,
                (v) => setState(() => _examConducted = v)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: _examMode,
              decoration: const InputDecoration(
                labelText: '考核方式',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '期中考试', child: Text('期中考试')),
                DropdownMenuItem(value: '阶段测验', child: Text('阶段测验')),
                DropdownMenuItem(value: '项目检查', child: Text('项目检查')),
                DropdownMenuItem(value: '作业/实验阶段检查', child: Text('作业/实验阶段检查')),
                DropdownMenuItem(value: '无独立期中考试', child: Text('无独立期中考试')),
              ],
              onChanged: (v) => setState(() {
                _examMode = v ?? _examMode;
                _examConducted = _examMode != '无独立期中考试';
              }),
            ),
            const SizedBox(height: 4),
            _checkbox('已提交试卷或阶段任务书', _paperSubmitted,
                (v) => setState(() => _paperSubmitted = v)),
            _checkbox('已提交参考答案或评分标准', _answerSubmitted,
                (v) => setState(() => _answerSubmitted = v)),
            _checkbox('已提交学生成绩记录', _scoreSubmitted,
                (v) => setState(() => _scoreSubmitted = v)),
            _checkbox('已提交成绩质量分析', _analysisSubmitted,
                (v) => setState(() => _analysisSubmitted = v)),
            const SizedBox(height: 8),
            _textField(
              controller: _noteController,
              label: '补充说明',
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );

  Widget _statusChip(MidtermProgressStatus value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _progressStatus == value,
      onSelected: (_) => setState(() => _progressStatus = value),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _checkbox(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onChanged: (v) => onChanged(v ?? false),
    );
  }

  Widget _counter({
    required String label,
    required int value,
    int? max,
    required ValueChanged<int> onChanged,
  }) {
    final limit = max ?? 99;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label：', style: const TextStyle(fontSize: 13)),
        IconButton(
          tooltip: '减少',
          onPressed: value <= 0 ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '增加',
          onPressed: value >= limit ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
      ],
    );
  }
}
