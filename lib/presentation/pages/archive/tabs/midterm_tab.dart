import 'package:flutter/material.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/local/database_helper.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../services/agent/agents/archive_agent.dart';

class MidtermTab extends StatefulWidget {
  final String courseType;
  final ArchiveDao dao;
  final ArchiveAgent agent;

  const MidtermTab({
    super.key,
    required this.courseType,
    required this.dao,
    required this.agent,
  });

  @override
  State<MidtermTab> createState() => _MidtermTabState();
}

class _MidtermTabState extends State<MidtermTab> {
  List<ArchiveDocument> _docs = [];
  bool _loading = true;

  // 进度一致性数据
  List<Map<String, dynamic>> _progressItems = [];
  List<Map<String, dynamic>> _syllabusItems = [];
  bool _progressLoading = false;

  // 统计
  int _quizCount = 0;
  int _graderCount = 0;
  int _wrongCount = 0;
  int _labSubmissionCount = 0;
  bool _statsLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MidtermTab old) {
    super.didUpdateWidget(old);
    if (old.courseType != widget.courseType) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _docs = await widget.dao.getDocuments(
        period: 'midterm',
        courseType: widget.courseType,
      );
      if (mounted) setState(() => _loading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'MidtermTab._load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  ArchiveDocument? _findDoc(String type) {
    for (final d in _docs) {
      if (d.documentType == type) return d;
    }
    return null;
  }

  Future<void> _generateDoc(String type, String label) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await widget.agent.generateDocument(
        title: '期中$label',
        documentType: type,
        period: 'midterm',
        courseType: widget.courseType,
      );
      if (mounted) Navigator.of(context).pop();
      _load();
    } catch (e, st) {
      swallowDebug(e, tag: 'MidtermTab._generateDoc', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生成失败，请重试')),
        );
      }
    }
  }

  Future<void> _loadProgressCheck() async {
    setState(() => _progressLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      _syllabusItems = await db.query('syllabus_items', limit: 50);
      _progressItems = await db.query('teaching_progress', limit: 50);
      if (mounted) setState(() => _progressLoading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'MidtermTab._loadProgress', stack: st);
      if (mounted) setState(() => _progressLoading = false);
    }
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      final qr = await db.rawQuery('SELECT COUNT(*) as c FROM quiz_results');
      _quizCount = (qr.first['c'] as int?) ?? 0;

      final gr = await db.rawQuery(
          'SELECT COUNT(*) as c FROM lab_submissions WHERE score IS NOT NULL');
      _graderCount = (gr.first['c'] as int?) ?? 0;

      final wr = await db.rawQuery('SELECT COUNT(*) as c FROM wrong_answers');
      _wrongCount = (wr.first['c'] as int?) ?? 0;

      final lr = await db.rawQuery('SELECT COUNT(*) as c FROM lab_submissions');
      _labSubmissionCount = (lr.first['c'] as int?) ?? 0;

      if (mounted) setState(() => _statsLoading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'MidtermTab._loadStats', stack: st);
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildExamPaperSection(primary),
          const SizedBox(height: 12),
          _buildExamAnswersSection(primary),
          const SizedBox(height: 12),
          _buildProgressSection(primary),
          const SizedBox(height: 12),
          _buildStatsSection(primary),
        ],
      ),
    );
  }

  Widget _buildExamPaperSection(Color primary) {
    final doc = _findDoc('midterm_exam');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.assignment, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('期中考试的试卷',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
              ),
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
                _actionChip(Icons.rate_review_outlined, '审核', () => _reviewDoc(doc), Colors.teal),
                const SizedBox(width: 6),
              ],
              _actionChip(Icons.auto_awesome, '生成', () => _generateDoc('midterm_exam', '考试的试卷'), Colors.deepPurple),
              const SizedBox(width: 6),
              if (doc != null)
                _actionChip(Icons.delete_outline, '删除', () => _deleteDoc(doc), Colors.red[300]!),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildExamAnswersSection(Color primary) {
    final doc = _findDoc('midterm_answers');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.quiz, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('期中考试的答案',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
              ),
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
              _actionChip(Icons.auto_awesome, '生成', () => _generateDoc('midterm_answers', '考试的答案'), Colors.deepPurple),
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

  Widget _buildProgressSection(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.compare_arrows, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('课程进度与教学计划一致性检查',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
              ),
              TextButton.icon(
                onPressed: _loadProgressCheck,
                icon: Icon(Icons.refresh, size: 16, color: primary),
                label: Text('加载数据', style: TextStyle(fontSize: 12, color: primary)),
              ),
            ]),
            const SizedBox(height: 8),
            if (_progressLoading)
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_syllabusItems.isEmpty && _progressItems.isEmpty)
              Text('点击"加载数据"从 syllabus_items 和 teaching_progress 表读取',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]))
            else ...[
              Text('大纲计划 ${_syllabusItems.length} 项，进度记录 ${_progressItems.length} 项',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              const SizedBox(height: 8),
              if (_syllabusItems.isNotEmpty) ...[
                Text('教学大纲条目：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(height: 4),
                ..._syllabusItems.take(10).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('  • ${item['chapter'] ?? item['title'] ?? ''}',
                      style: const TextStyle(fontSize: 12)),
                )),
              ],
              if (_progressItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('进度记录：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(height: 4),
                ..._progressItems.take(10).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('  • 第${item['week'] ?? '?'}周: ${item['content'] ?? item['topic'] ?? ''}',
                      style: const TextStyle(fontSize: 12)),
                )),
              ],
              const SizedBox(height: 8),
              _buildConsistencySummary(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsistencySummary() {
    final matchCount = _progressItems.where((p) {
      final content = (p['content'] as String? ?? '').toLowerCase();
      return _syllabusItems.any((s) {
        final title = (s['title'] as String? ?? '').toLowerCase();
        return content.contains(title) || title.contains(content);
      });
    }).length;
    final totalSyllabus = _syllabusItems.length;
    final rate = totalSyllabus > 0 ? (matchCount / totalSyllabus * 100).toStringAsFixed(0) : '0';
    final color = matchCount >= totalSyllabus * 0.7 ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(Icons.check_circle, size: 16, color: color),
        const SizedBox(width: 6),
        Text('一致率：$rate%（$matchCount/$totalSyllabus  计划项匹配）',
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildStatsSection(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bar_chart, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('作业次数与批阅次数统计',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
              ),
              TextButton.icon(
                onPressed: _loadStats,
                icon: Icon(Icons.refresh, size: 16, color: primary),
                label: Text('刷新', style: TextStyle(fontSize: 12, color: primary)),
              ),
            ]),
            const SizedBox(height: 12),
            if (_statsLoading)
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              Row(children: [
                Expanded(child: _statCard(Icons.quiz_outlined, '测验次数', '$_quizCount', Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _statCard(Icons.check_circle_outline, '已批阅', '$_graderCount', Colors.green)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _statCard(Icons.error_outline, '错题数', '$_wrongCount', Colors.red)),
                const SizedBox(width: 8),
                Expanded(child: _statCard(Icons.science_outlined, '实验提交', '$_labSubmissionCount', Colors.purple)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
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

  void _reviewDoc(ArchiveDocument doc) async {
    if (doc.content == null || doc.content!.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final review = await widget.agent.reviewDocument(doc);
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('AI 审核结果'),
            content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Text(review))),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
          ),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'MidtermTab._reviewDoc', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('审核失败')));
      }
    }
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
