import 'package:flutter/material.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/local/database_helper.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import '../archive_constants.dart';

class FinalTab extends StatefulWidget {
  final String courseType;
  final ArchiveDao dao;
  final ArchiveAgent agent;

  const FinalTab({
    super.key,
    required this.courseType,
    required this.dao,
    required this.agent,
  });

  @override
  State<FinalTab> createState() => _FinalTabState();
}

class _FinalTabState extends State<FinalTab> {
  List<ArchiveDocument> _docs = [];
  bool _loading = true;

  // 考核材料
  int _groupCount = 0;
  int _projectCount = 0;
  int _defenseCount = 0;
  bool _assessmentLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FinalTab old) {
    super.didUpdateWidget(old);
    if (old.courseType != widget.courseType) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _docs = await widget.dao.getDocuments(
        period: 'final',
        courseType: widget.courseType,
      );
      if (mounted) setState(() => _loading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'FinalTab._load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  ArchiveDocument? _findDoc(String type) {
    for (final d in _docs) {
      if (d.documentType == type) return d;
    }
    return null;
  }

  Future<void> _generateDoc(String type, String label, {String titlePrefix = '期末'}) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await widget.agent.generateDocument(
        title: '$titlePrefix$label',
        documentType: type,
        period: 'final',
        courseType: widget.courseType,
      );
      if (mounted) Navigator.of(context).pop();
      _load();
    } catch (e, st) {
      swallowDebug(e, tag: 'FinalTab._generateDoc', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生成失败，请重试')),
        );
      }
    }
  }

  Future<void> _loadAssessmentData() async {
    setState(() => _assessmentLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final groups = await db.query('assessment_groups');
      final projects = await db.query('assessment_projects');
      final defenses = await db.query('defense_records');
      _groupCount = groups.length;
      _projectCount = projects.length;
      _defenseCount = defenses.length;
      if (mounted) setState(() => _assessmentLoading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'FinalTab._loadAssessment', stack: st);
      if (mounted) setState(() => _assessmentLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isExam = isExamCourse(widget.courseType);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildReviewFormSection(primary, isExam),
          const SizedBox(height: 12),
          _buildAssessmentPlanSection(primary, isExam),
          const SizedBox(height: 12),
          _buildAssessmentMaterialsSection(primary),
          const SizedBox(height: 12),
          _buildCourseDescriptionSection(primary, isExam),
        ],
      ),
    );
  }

  Widget _buildReviewFormSection(Color primary, bool isExam) {
    final key = isExam ? 'exam_review_form' : 'assessment_review_form';
    final label = isExam ? '试卷审核表' : '命题审核表（非试卷类）';
    final doc = _findDoc(key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.approval, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(child: Text('课程期末考核命题审核表${isExam ? '' : '（非试卷类）'}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary))),
            ]),
            const SizedBox(height: 8),
            Text(isExam ? '考试课程 — 试卷命题审核' : '考查课程 — 非试卷类考核命题审核',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (doc != null) ...[
              const SizedBox(height: 8),
              _docTile(doc, primary),
            ] else ...[
              const SizedBox(height: 8),
              Text('未生成', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ],
            const SizedBox(height: 8),
            Row(children: [
              if (doc != null) ...[
                _actionChip(Icons.visibility, '预览', () => _previewDoc(doc), primary),
                const SizedBox(width: 6),
              ],
              _actionChip(Icons.auto_awesome, '生成', () => _generateDoc(key, label), Colors.deepPurple),
              if (doc != null) ...[
                const SizedBox(width: 6),
                _actionChip(Icons.delete_outline, '删除', () => _deleteDoc(doc), Colors.red[300]!),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentPlanSection(Color primary, bool isExam) {
    const key = 'final_assessment';
    const label = '考核方案';
    final doc = _findDoc(key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.assignment_turned_in, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(child: Text('课程期末考核方案',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary))),
            ]),
            const SizedBox(height: 8),
            if (doc != null)
              _docTile(doc, primary)
            else
              Text('未生成', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 8),
            Row(children: [
              if (doc != null) ...[
                _actionChip(Icons.visibility, '预览', () => _previewDoc(doc), primary),
                const SizedBox(width: 6),
              ],
              _actionChip(Icons.auto_awesome, '生成', () => _generateDoc(key, label), Colors.deepPurple),
              if (doc != null) ...[
                const SizedBox(width: 6),
                _actionChip(Icons.delete_outline, '删除', () => _deleteDoc(doc), Colors.red[300]!),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentMaterialsSection(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.folder_special, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(child: Text('考核材料',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary))),
              TextButton.icon(
                onPressed: _loadAssessmentData,
                icon: Icon(Icons.refresh, size: 16, color: primary),
                label: Text('加载', style: TextStyle(fontSize: 12, color: primary)),
              ),
            ]),
            const SizedBox(height: 8),
            Text('来自主菜单"考核"模块：四个过程报告、四个最终报告、两个审核打印报告',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 12),
            if (_assessmentLoading)
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              _materialCard(Icons.group, '考核分组', '$_groupCount 组', Colors.blue, primary),
              const SizedBox(height: 6),
              _materialCard(Icons.assignment, '考核项目', '$_projectCount 个', Colors.purple, primary),
              const SizedBox(height: 6),
              _materialCard(Icons.record_voice_over, '答辩记录', '$_defenseCount 条', Colors.teal, primary),
              const SizedBox(height: 12),
              if (_groupCount == 0 && _projectCount == 0)
                Text('点击"加载"从 assessment_groups / assessment_projects / defense_records 表读取数据',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]))
              else ...[
                const Divider(),
                Text('报告类型', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _checkRow('四个过程报告', _projectCount >= 4),
                _checkRow('四个最终报告', _defenseCount >= 4),
                _checkRow('两个审核打印报告', _groupCount >= 2),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCourseDescriptionSection(Color primary, bool isExam) {
    final key = isExam ? 'course_summary' : 'course_summary';
    final doc = _findDoc(key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.description, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(child: Text('课程考核说明',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary))),
            ]),
            const SizedBox(height: 8),
            Text('课程考核说明${isExam ? '（考试）' : '（考查）'}文档',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (doc != null) ...[
              const SizedBox(height: 8),
              _docTile(doc, primary),
            ] else ...[
              const SizedBox(height: 8),
              Text('未生成', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ],
            const SizedBox(height: 8),
            Row(children: [
              if (doc != null) ...[
                _actionChip(Icons.visibility, '预览', () => _previewDoc(doc), primary),
                const SizedBox(width: 6),
              ],
              _actionChip(Icons.auto_awesome, '生成', () => _generateDoc(key, '考核说明'), Colors.deepPurple),
              if (doc != null) ...[
                const SizedBox(width: 6),
                _actionChip(Icons.delete_outline, '删除', () => _deleteDoc(doc), Colors.red[300]!),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _materialCard(IconData icon, String label, String value, Color color, Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _checkRow(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(done ? Icons.check_circle : Icons.pending, size: 16,
            color: done ? Colors.green : Colors.orange),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, color: done ? Colors.green[700] : Colors.orange[700])),
        const Spacer(),
        Text(done ? '已完成' : '未完成', style: TextStyle(fontSize: 12, color: done ? Colors.green : Colors.orange)),
      ]),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap, Color color) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _docTile(ArchiveDocument doc, Color primary) {
    final status = doc.status == 'archived' ? '已归档' : doc.isGenerated ? '已生成' : '草稿';
    final color = doc.status == 'archived' ? Colors.green : doc.isGenerated ? Colors.blue : Colors.grey;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(status, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(doc.createdAt.substring(0, 10),
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ),
    ]);
  }

  void _previewDoc(ArchiveDocument doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              Expanded(child: Text(doc.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              child: Text(doc.content ?? '暂无内容'),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _deleteDoc(ArchiveDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除"${doc.title}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && doc.id != null) {
      await widget.dao.deleteDocument(doc.id!);
      _load();
    }
  }
}
