import 'package:flutter/material.dart';
import '../../../data/local/homework_dao.dart';
import '../../../data/models/homework_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/ai_service.dart';
import '../../../core/error_handler.dart';

/// 教师作业批阅页 — 列出所有作业 + 提交统计，可逐个批阅
class HomeworkGradingPage extends StatefulWidget {
  const HomeworkGradingPage({super.key});

  @override
  State<HomeworkGradingPage> createState() => _HomeworkGradingPageState();
}

class _HomeworkGradingPageState extends State<HomeworkGradingPage> {
  final HomeworkDao _dao = HomeworkDao();
  final AuthService _auth = AuthService();
  final AiService _ai = AiService();

  List<HomeworkModel> _homeworks = [];
  Map<int, Map<String, int>> _statsCache = {};
  bool _loading = true;
  String _courseId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      _courseId = await CourseContextService().activeCourseId();
      final homeworks = await _dao.getHomeworks(_courseId);
      // 预加载统计
      for (final hw in homeworks) {
        _statsCache[hw.id] = await _dao.getSubmissionStats(hw.id);
      }
      if (mounted) setState(() { _homeworks = homeworks; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _homeworks.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('暂无作业', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _homeworks.length,
                  itemBuilder: (context, index) => _buildHomeworkCard(theme, _homeworks[index]),
                ),
              );
  }

  Widget _buildHomeworkCard(ThemeData theme, HomeworkModel hw) {
    final stats = _statsCache[hw.id] ?? {'total': 0, 'graded': 0};
    final total = stats['total'] ?? 0;
    final graded = stats['graded'] ?? 0;
    final isClosed = hw.status == 'closed';
    final statusColor = isClosed ? Colors.grey : Colors.orange;
    final statusText = isClosed ? '已截止' : '进行中';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openGradingDetail(hw),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assignment, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(hw.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusText,
                        style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              if (hw.chapterTitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(hw.chapterTitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _statChip(Icons.people_outline, '提交 $total', theme),
                  const SizedBox(width: 12),
                  _statChip(Icons.check_circle_outline, '已批 $graded', theme),
                  const SizedBox(width: 12),
                  _statChip(Icons.pending_actions, '待批 ${total - graded}', theme),
                ],
              ),
              if (hw.deadline != null) ...[
                const SizedBox(height: 6),
                Text('截止: ${hw.deadline!.month}/${hw.deadline!.day}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String text, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  void _openGradingDetail(HomeworkModel hw) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _HomeworkGradingDetail(homework: hw, dao: _dao, ai: _ai),
    ));
  }
}

// ── 作业批阅详情（单次作业的所有学生提交）────────────────────────────────

class _HomeworkGradingDetail extends StatefulWidget {
  final HomeworkModel homework;
  final HomeworkDao dao;
  final AiService ai;
  const _HomeworkGradingDetail({required this.homework, required this.dao, required this.ai});

  @override
  State<_HomeworkGradingDetail> createState() => _HomeworkGradingDetailState();
}

class _HomeworkGradingDetailState extends State<_HomeworkGradingDetail> {
  List<HomeworkItemModel> _items = [];
  // userId → List<HomeworkSubmissionModel>
  Map<String, List<HomeworkSubmissionModel>> _submissionsByUser = {};
  List<String> _studentIds = [];
  bool _loading = true;
  bool _batchGrading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      _items = await widget.dao.getItems(widget.homework.id);
      final allSubs = await widget.dao.getAllSubmissions(widget.homework.id);
      // 按学生分组
      final map = <String, List<HomeworkSubmissionModel>>{};
      for (final sub in allSubs) {
        map.putIfAbsent(sub.userId, () => []).add(sub);
      }
      _studentIds = map.keys.toList()..sort();
      _submissionsByUser = map;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _aiGradeAll() async {
    if (_batchGrading) return;
    setState(() => _batchGrading = true);
    try {
      int count = 0;
      for (final userId in _studentIds) {
        final subs = _submissionsByUser[userId] ?? [];
        for (final sub in subs) {
          if (sub.score != null && sub.score! > 0) continue; // 已有分数跳过
          final item = _items.where((i) => i.id == sub.itemId).firstOrNull;
          if (item == null) continue;
          final prompt = '批阅以下作业回答，题目：${item.question}\n参考答案：${item.referenceAnswer ?? '无'}\n学生回答：${sub.answerText ?? '未作答'}\n满分${item.maxScore}分，请直接返回 JSON: {"score": 分数, "feedback": "评语"}';
          try {
            final resp = await widget.ai.chat(prompt);
            final json = _tryParseJson(resp);
            if (json != null) {
              final score = (json['score'] as num?)?.toInt() ?? 0;
              final feedback = json['feedback']?.toString() ?? '';
              await widget.dao.updateAiGrade(sub.id, score, feedback);
              count++;
            }
          } catch (e) {
            swallowDebug(e, tag: 'hw_grading.aiGrade');
          }
        }
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 批阅完成，批阅 $count 条'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      swallowDebug(e, tag: 'hw_grading.aiGradeAll');
    } finally {
      if (mounted) setState(() => _batchGrading = false);
    }
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      final trimmed = text.trim();
      final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false).firstMatch(trimmed);
      final candidate = fenced != null ? fenced.group(1)!.trim() : trimmed;
      final decoded = Map<String, dynamic>.from(
        const JsonDecoder().convert(candidate) as Map);
      if (decoded.containsKey('score') || decoded.containsKey('feedback')) return decoded;
    } catch (_) {}
    return null;
  }

  Future<void> _updateScore(String userId, HomeworkSubmissionModel sub, int score) async {
    await widget.dao.updateAiGrade(sub.id, score, sub.aiComment ?? '');
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.homework.title} — 批阅'),
        actions: [
          if (_studentIds.isNotEmpty)
            TextButton.icon(
              onPressed: _batchGrading ? null : _aiGradeAll,
              icon: _batchGrading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_batchGrading ? '批阅中...' : 'AI 批阅'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _studentIds.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.how_to_submit, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('暂无提交', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _studentIds.length,
                  itemBuilder: (context, index) => _buildStudentCard(theme, _studentIds[index]),
                ),
    );
  }

  Widget _buildStudentCard(ThemeData theme, String userId) {
    final subs = _submissionsByUser[userId] ?? [];
    final totalScore = subs.where((s) => s.score != null).fold<int>(0, (sum, s) => sum + (s.score ?? 0));
    final maxScore = _items.fold<int>(0, (sum, i) => sum + i.maxScore);
    final gradedCount = subs.where((s) => s.score != null).length;
    final allGraded = gradedCount == _items.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: allGraded ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
          child: Text(allGraded ? '✓' : '$gradedCount/${_items.length}',
              style: TextStyle(fontSize: 12, color: allGraded ? Colors.green : Colors.orange)),
        ),
        title: Text(userId, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('得分: $totalScore / $maxScore',
            style: theme.textTheme.bodySmall?.copyWith(
                color: allGraded ? Colors.green : Colors.grey.shade600)),
        children: subs.map((sub) {
          final item = _items.where((i) => i.id == sub.itemId).firstOrNull;
          return ListTile(
            dense: true,
            title: Text('第${item?.itemIndex ?? '?'}题', style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              (sub.answerText?.isNotEmpty == true) ? sub.answerText! : '未作答',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: sub.score?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  suffixText: '/${item?.maxScore ?? '?'}',
                  suffixStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                style: const TextStyle(fontSize: 13),
                onFieldSubmitted: (v) {
                  final score = int.tryParse(v);
                  if (score != null && item != null) _updateScore(userId, sub, score);
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
