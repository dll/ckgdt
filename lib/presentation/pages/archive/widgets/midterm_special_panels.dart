import 'package:flutter/material.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/database_helper.dart';
import '../../../../data/local/teaching_dao.dart';

/// 期中特有面板：课程进度与教学计划一致性检查 + 作业/批阅次数统计。
///
/// 自包含状态：自己懒加载 syllabus_items / teaching_progress（经 [TeachingDao]）
/// 与 quiz_results / lab_submissions / wrong_answers 计数，不依赖父 [ArchivePeriodTab]。
/// 作为 extraHeader 注入到期中 tab 文档列表上方。
class MidtermSpecialPanels extends StatefulWidget {
  const MidtermSpecialPanels({super.key});

  @override
  State<MidtermSpecialPanels> createState() => _MidtermSpecialPanelsState();
}

class _MidtermSpecialPanelsState extends State<MidtermSpecialPanels> {
  final _teachingDao = TeachingDao();

  List<Map<String, dynamic>> _progressItems = [];
  List<Map<String, dynamic>> _syllabusItems = [];
  bool _progressLoading = false;

  int _quizCount = 0;
  int _graderCount = 0;
  int _wrongCount = 0;
  int _labSubmissionCount = 0;
  bool _statsLoading = false;

  Future<void> _loadProgressCheck() async {
    setState(() => _progressLoading = true);
    try {
      _syllabusItems = await _teachingDao.getAllSyllabusItems();
      _progressItems = await _teachingDao.getAllTeachingProgress();
      if (mounted) setState(() => _progressLoading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'MidtermSpecialPanels._loadProgress', stack: st);
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
      swallowDebug(e, tag: 'MidtermSpecialPanels._loadStats', stack: st);
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        _buildProgressSection(primary),
        const SizedBox(height: 12),
        _buildStatsSection(primary),
      ],
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
              Text('点击"加载数据"从教学大纲与进度记录中读取',
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
        return title.isNotEmpty && (content.contains(title) || title.contains(content));
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
        Text('一致率：$rate%（$matchCount/$totalSyllabus 计划项匹配）',
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
}
