import 'package:flutter/material.dart';
import '../../../data/local/lab_task_dao.dart';
import '../../../services/auth_service.dart';

/// 学生实验中心 — 查看实验任务、提交作业、查看成绩
class StudentLabPage extends StatefulWidget {
  const StudentLabPage({super.key});

  @override
  State<StudentLabPage> createState() => _StudentLabPageState();
}

class _StudentLabPageState extends State<StudentLabPage> {
  final _dao = LabTaskDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _mySubmissions = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  String get _userId => _authService.currentUser?.userId ?? '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _dao.initDemoDataIfEmpty();
      final tasks = await _dao.getTasks(status: 'active');
      final subs = await _dao.getSubmissions(userId: _userId);
      final stats = await _dao.getStudentLabStats(_userId);
      setState(() {
        _tasks = tasks;
        _mySubmissions = subs;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的实验')),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 统计卡片
            _buildStatsCard(),
            const SizedBox(height: 16),
            // 实验任务列表
            const Text('实验任务',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._tasks.map(_buildTaskItem),
            if (_tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.assignment, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text('暂无实验任务',
                          style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final submitted = _stats['submitted_tasks'] ?? 0;
    final total = _stats['total_tasks'] ?? 0;
    final avgScore = _stats['avg_score'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _statItem(
                Icons.assignment_turned_in,
                '$submitted / $total',
                '已提交',
                Colors.blue,
              ),
            ),
            Container(width: 1, height: 40, color: Colors.grey[200]),
            Expanded(
              child: _statItem(
                Icons.score,
                avgScore != null
                    ? (avgScore as num).toStringAsFixed(1)
                    : '--',
                '平均分',
                Colors.green,
              ),
            ),
            Container(width: 1, height: 40, color: Colors.grey[200]),
            Expanded(
              child: _statItem(
                Icons.grading,
                '${_stats['graded_count'] ?? 0}',
                '已批改',
                Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildTaskItem(Map<String, dynamic> task) {
    // Find my submission for this task
    final mySub = _mySubmissions.where((s) => s['task_id'] == task['id']).toList();
    final hasSubmitted = mySub.isNotEmpty;
    final score = hasSubmitted ? mySub.first['score'] as int? : null;

    final difficulty = task['difficulty'] as String? ?? '中等';
    final diffColor = difficulty == '简单'
        ? Colors.green
        : difficulty == '较难'
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (hasSubmitted ? Colors.green : Colors.blue)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            hasSubmitted ? Icons.check_circle : Icons.assignment,
            color: hasSubmitted ? Colors.green : Colors.blue,
            size: 22,
          ),
        ),
        title: Text(
          task['title'] as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: diffColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(difficulty,
                  style: TextStyle(fontSize: 10, color: diffColor)),
            ),
            const SizedBox(width: 6),
            if (score != null)
              Text('得分：$score',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                      fontWeight: FontWeight.w500))
            else if (hasSubmitted)
              const Text('已提交·待批改',
                  style: TextStyle(fontSize: 11, color: Colors.orange))
            else
              const Text('未提交',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((task['description'] as String?)?.isNotEmpty == true) ...[
                  Text(task['description'] as String,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                if ((task['requirements'] as String?)?.isNotEmpty == true) ...[
                  const Text('实验要求：',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(task['requirements'] as String,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 13, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '截止：${(task['due_date'] as String? ?? '').split('T').first}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
                // 批改反馈
                if (hasSubmitted && mySub.first['feedback'] != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.rate_review,
                          size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      const Text('教师批改反馈：',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(mySub.first['feedback'] as String,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          _showSubmitDialog(task, hasSubmitted ? mySub.first : null),
                      icon: Icon(hasSubmitted ? Icons.edit : Icons.upload,
                          size: 16),
                      label:
                          Text(hasSubmitted ? '重新提交' : '提交作业'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSubmitDialog(
      Map<String, dynamic> task, Map<String, dynamic>? existing) async {
    final contentCtrl =
        TextEditingController(text: existing?['content'] as String? ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('提交 - ${task['title']}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(
                  labelText: '实验内容',
                  border: OutlineInputBorder(),
                  hintText: '描述你的实验过程和结果...',
                ),
                maxLines: 6,
              ),
              const SizedBox(height: 8),
              Text(
                '提示：可在内容中粘贴代码仓库链接或截图描述',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (contentCtrl.text.trim().isEmpty) return;
              await _dao.submitTask(
                taskId: task['id'] as int,
                userId: _userId,
                content: contentCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('提交成功！')),
                );
              }
              _loadData();
            },
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
  }
}
