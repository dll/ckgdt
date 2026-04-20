import 'package:flutter/material.dart';
import '../../../data/local/lab_task_dao.dart';
import '../../../services/auth_service.dart';

/// 实验任务管理页面 — 教师发布/管理实验任务，查看提交情况
class LabTaskManagePage extends StatefulWidget {
  const LabTaskManagePage({super.key});

  @override
  State<LabTaskManagePage> createState() => _LabTaskManagePageState();
}

class _LabTaskManagePageState extends State<LabTaskManagePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _dao = LabTaskDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _submissions = [];
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      await _dao.initDemoDataIfEmpty();
      final tasks = await _dao.getTasks();
      final submissions = await _dao.getSubmissions();
      final templates = await _dao.getReportTemplates();
      setState(() {
        _tasks = tasks;
        _submissions = submissions;
        _templates = templates;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实验任务管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.assignment), text: '实验任务'),
            Tab(icon: Icon(Icons.upload_file), text: '提交管理'),
            Tab(icon: Icon(Icons.description), text: '报告模板'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTasksTab(),
                _buildSubmissionsTab(),
                _buildTemplatesTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tab 1: 实验任务列表
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTasksTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: Column(
        children: [
          // 操作栏
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.assignment, size: 16),
                  label: Text('共 ${_tasks.length} 个实验'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _showAddTaskDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('发布实验'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('暂无实验任务', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _tasks.length,
                    itemBuilder: (ctx, i) => _buildTaskCard(_tasks[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final difficulty = task['difficulty'] as String? ?? '中等';
    final diffColor = difficulty == '简单'
        ? Colors.green
        : difficulty == '较难'
            ? Colors.red
            : Colors.orange;
    final status = task['status'] as String? ?? 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.assignment, color: Colors.blue, size: 22),
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
            if (task['chapter'] != null)
              Text(task['chapter'] as String,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(width: 6),
            if (status != 'active')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(status == 'closed' ? '已关闭' : status,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ),
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
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(task['requirements'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 8),
                ],
                if ((task['deliverables'] as String?)?.isNotEmpty == true) ...[
                  const Text('提交物：',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(task['deliverables'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '截止：${(task['due_date'] as String? ?? '').split('T').first}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.star, size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '满分：${task['max_score'] ?? 100}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _viewTaskSubmissions(task),
                      icon: const Icon(Icons.people, size: 16),
                      label: const Text('查看提交', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      tooltip: '编辑',
                      onPressed: () => _showEditTaskDialog(task),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      tooltip: '删除',
                      onPressed: () => _confirmDeleteTask(task),
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

  Future<void> _showAddTaskDialog() async {
    await _showTaskEditor(null);
  }

  Future<void> _showEditTaskDialog(Map<String, dynamic> task) async {
    await _showTaskEditor(task);
  }

  Future<void> _showTaskEditor(Map<String, dynamic>? task) async {
    final isEdit = task != null;
    final titleCtrl = TextEditingController(text: task?['title'] as String? ?? '');
    final chapterCtrl = TextEditingController(text: task?['chapter'] as String? ?? '');
    final descCtrl = TextEditingController(text: task?['description'] as String? ?? '');
    final reqCtrl = TextEditingController(text: task?['requirements'] as String? ?? '');
    final delivCtrl = TextEditingController(text: task?['deliverables'] as String? ?? '');
    String difficulty = task?['difficulty'] as String? ?? '中等';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollCtrl) => Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: scrollCtrl,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(isEdit ? '编辑实验' : '发布实验',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isEmpty) return;
                        if (isEdit) {
                          await _dao.updateTask(task['id'] as int, {
                            'title': titleCtrl.text.trim(),
                            'chapter': chapterCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'requirements': reqCtrl.text.trim(),
                            'deliverables': delivCtrl.text.trim(),
                            'difficulty': difficulty,
                          });
                        } else {
                          await _dao.addTask(
                            title: titleCtrl.text.trim(),
                            chapter: chapterCtrl.text.trim().isNotEmpty ? chapterCtrl.text.trim() : null,
                            description: descCtrl.text.trim(),
                            requirements: reqCtrl.text.trim(),
                            deliverables: delivCtrl.text.trim(),
                            difficulty: difficulty,
                            creatorId: _authService.currentUser?.userId,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadAll();
                      },
                      child: Text(isEdit ? '保存' : '发布'),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: '实验标题 *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: chapterCtrl,
                        decoration: const InputDecoration(labelText: '所属章节', border: OutlineInputBorder(), hintText: '如：第1章'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: difficulty,
                        decoration: const InputDecoration(labelText: '难度', border: OutlineInputBorder()),
                        items: ['简单', '中等', '较难']
                            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                            .toList(),
                        onChanged: (v) => setSheetState(() => difficulty = v ?? '中等'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: '实验描述', border: OutlineInputBorder()),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reqCtrl,
                  decoration: const InputDecoration(labelText: '实验要求', border: OutlineInputBorder(), hintText: '1. 步骤一\n2. 步骤二'),
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: delivCtrl,
                  decoration: const InputDecoration(labelText: '提交物', border: OutlineInputBorder(), hintText: '源码、截图、实验报告'),
                  maxLines: 2,
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除"${task['title']}"？\n相关提交也将被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _dao.deleteTask(task['id'] as int);
      _loadAll();
    }
  }

  void _viewTaskSubmissions(Map<String, dynamic> task) {
    _tabController.animateTo(1);
    // Filter submissions by this task
    setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tab 2: 提交管理
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSubmissionsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.upload_file, size: 16),
                  label: Text('共 ${_submissions.length} 个提交'),
                ),
                const Spacer(),
                _buildSubmissionStats(),
              ],
            ),
          ),
          Expanded(
            child: _submissions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_file, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('暂无学生提交', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _submissions.length,
                    itemBuilder: (ctx, i) => _buildSubmissionCard(_submissions[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionStats() {
    final graded = _submissions.where((s) => s['score'] != null).length;
    final pending = _submissions.length - graded;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('已批 $graded', style: const TextStyle(fontSize: 11, color: Colors.green)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('待批 $pending', style: const TextStyle(fontSize: 11, color: Colors.orange)),
        ),
      ],
    );
  }

  Widget _buildSubmissionCard(Map<String, dynamic> sub) {
    final score = sub['score'] as int?;
    final isGraded = score != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isGraded ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
          child: Icon(
            isGraded ? Icons.check_circle : Icons.hourglass_bottom,
            color: isGraded ? Colors.green : Colors.orange,
            size: 22,
          ),
        ),
        title: Text(
          sub['task_title'] as String? ?? '实验任务',
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '学号：${sub['user_id']}  |  提交：${(sub['submit_time'] as String? ?? '').split('T').first}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: isGraded
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$score分', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              )
            : FilledButton.tonal(
                onPressed: () => _showGradeDialog(sub),
                child: const Text('批改', style: TextStyle(fontSize: 12)),
              ),
        onTap: () => _showSubmissionDetail(sub),
      ),
    );
  }

  Future<void> _showGradeDialog(Map<String, dynamic> sub) async {
    final scoreCtrl = TextEditingController(text: '${sub['score'] ?? ''}');
    final feedbackCtrl = TextEditingController(text: sub['feedback'] as String? ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批改 - ${sub['user_id']}'),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: scoreCtrl,
                decoration: InputDecoration(
                  labelText: '评分',
                  border: const OutlineInputBorder(),
                  suffixText: '/ ${sub['max_score'] ?? 100}',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: feedbackCtrl,
                decoration: const InputDecoration(
                  labelText: '批改反馈',
                  border: OutlineInputBorder(),
                  hintText: '评语、改进建议等',
                ),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final score = int.tryParse(scoreCtrl.text);
              if (score == null) return;
              await _dao.gradeSubmission(
                sub['id'] as int,
                score: score,
                feedback: feedbackCtrl.text.trim(),
                scorerId: _authService.currentUser?.userId,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadAll();
            },
            child: const Text('确认批改'),
          ),
        ],
      ),
    );
  }

  void _showSubmissionDetail(Map<String, dynamic> sub) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('提交详情',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              _detailRow('实验', sub['task_title'] as String? ?? ''),
              _detailRow('学号', sub['user_id'] as String? ?? ''),
              _detailRow('提交时间', (sub['submit_time'] as String? ?? '').replaceAll('T', ' ')),
              _detailRow('状态', sub['status'] as String? ?? ''),
              if (sub['content'] != null)
                _detailRow('提交内容', sub['content'] as String),
              if (sub['file_names'] != null)
                _detailRow('附件', sub['file_names'] as String),
              if (sub['score'] != null)
                _detailRow('评分', '${sub['score']} / ${sub['max_score'] ?? 100}'),
              if (sub['feedback'] != null)
                _detailRow('批改反馈', sub['feedback'] as String),
              const SizedBox(height: 16),
              if (sub['score'] == null)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showGradeDialog(sub);
                  },
                  icon: const Icon(Icons.grading),
                  label: const Text('去批改'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tab 3: 报告模板
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTemplatesTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.description, size: 16),
                  label: Text('共 ${_templates.length} 个模板'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _showAddTemplateDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建模板'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _templates.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('暂无报告模板', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _templates.length,
                    itemBuilder: (ctx, i) => _buildTemplateCard(_templates[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> template) {
    final isDefault = (template['is_default'] as int? ?? 0) == 1;
    final category = template['category'] as String? ?? '实验报告';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.article, color: Colors.purple, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(template['name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
            ),
            if (isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('默认', style: TextStyle(fontSize: 10, color: Colors.blue)),
              ),
          ],
        ),
        subtitle: Text(
          '$category  |  ${template['description'] ?? ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (action) async {
            if (action == 'delete') {
              await _dao.deleteReportTemplate(template['id'] as int);
              _loadAll();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddTemplateDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = '实验报告';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建报告模板'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '模板名称 *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: '模板类型',
                      border: OutlineInputBorder(),
                    ),
                    items: ['实验报告', '项目文档', '答辩材料']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => category = v ?? '实验报告'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: '模板描述',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final defaultSections = '''[
                  {"title":"实验目的","hint":"描述本次实验的目标","required":true},
                  {"title":"实验步骤","hint":"详细操作步骤","required":true},
                  {"title":"实验结果","hint":"运行结果与分析","required":true},
                  {"title":"实验总结","hint":"收获与体会","required":true}
                ]''';
                await _dao.addReportTemplate(
                  name: nameCtrl.text.trim(),
                  category: category,
                  sectionsJson: defaultSections,
                  description: descCtrl.text.trim(),
                  creatorId: _authService.currentUser?.userId,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadAll();
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }
}
