import 'package:flutter/material.dart';
import '../../../data/local/homework_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../data/models/homework_model.dart';
import 'homework_detail_page.dart';

/// 作业列表页（学生端 + 教师端复用）
class HomeworkListPage extends StatefulWidget {
  final bool isTeacher;
  const HomeworkListPage({super.key, this.isTeacher = false});

  @override
  State<HomeworkListPage> createState() => _HomeworkListPageState();
}

class _HomeworkListPageState extends State<HomeworkListPage> {
  final HomeworkDao _dao = HomeworkDao();
  List<HomeworkModel> _homeworks = [];
  bool _loading = true;
  String _courseId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = AuthService().currentUser;
      if (user == null) return;
      // courseId 从 CourseContextService 获取
      final ctx = CourseContextService();
      _courseId = await ctx.activeCourseId();
      final homeworks = await _dao.getHomeworks(_courseId);
      if (mounted) {
        setState(() {
          _homeworks = homeworks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isTeacher ? '作业管理' : '我的作业'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _homeworks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('暂无作业',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _homeworks.length,
                    itemBuilder: (context, index) =>
                        _buildCard(theme, _homeworks[index]),
                  ),
                ),
    );
  }

  Widget _buildCard(ThemeData theme, HomeworkModel hw) {
    final isClosed = hw.status == 'closed';
    final statusColor = isClosed ? Colors.grey : Colors.green;
    final statusText = isClosed ? '已截止' : '进行中';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(hw),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(hw.chapter,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(hw.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(statusText,
                        style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              if (hw.courseObjective.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.track_changes, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text('关联目标: ${hw.courseObjective}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.score, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text('总分 ${hw.totalScore}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                  const Spacer(),
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(_formatDate(hw.createdAt),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(HomeworkModel hw) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HomeworkDetailPage(
          homework: hw,
          isTeacher: widget.isTeacher,
        ),
      ),
    ).then((_) => _loadData());
  }

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
