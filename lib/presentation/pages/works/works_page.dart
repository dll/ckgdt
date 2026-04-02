import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../data/local/works_dao.dart';
import '../../../services/auth_service.dart';

/// 作品管理页面 — 参考 Python 版 works_tab.py
/// 四大子页: 作品展示 / 作品上传 / 评分记录 / 排行榜
class WorksPage extends StatefulWidget {
  const WorksPage({super.key});

  @override
  State<WorksPage> createState() => _WorksPageState();
}

class _WorksPageState extends State<WorksPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _worksDao = WorksDao();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    await _worksDao.initDemoDataIfEmpty();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // Tab 栏
        Container(
          color: primary.withValues(alpha: 0.05),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primary,
            tabs: const [
              Tab(icon: Icon(Icons.workspace_premium, size: 18), text: '作品展示'),
              Tab(icon: Icon(Icons.upload_file, size: 18), text: '作品上传'),
              Tab(icon: Icon(Icons.star_rate, size: 18), text: '评分记录'),
              Tab(icon: Icon(Icons.leaderboard, size: 18), text: '排行榜'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _WorksGalleryTab(authService: _authService),
              _WorksUploadTab(authService: _authService),
              _ScoreRecordTab(authService: _authService),
              _LeaderboardTab(authService: _authService),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 作品展示 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _WorksGalleryTab extends StatefulWidget {
  final AuthService authService;
  const _WorksGalleryTab({required this.authService});

  @override
  State<_WorksGalleryTab> createState() => _WorksGalleryTabState();
}

class _WorksGalleryTabState extends State<_WorksGalleryTab> {
  String _selectedFilter = '全部';
  final _searchController = TextEditingController();
  final _worksDao = WorksDao();

  List<Map<String, dynamic>> _works = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorks();
  }

  Future<void> _loadWorks() async {
    setState(() => _isLoading = true);
    try {
      final filter = _selectedFilter == '全部' ? null : _selectedFilter;
      final works = await _worksDao.getWorks(workType: filter);
      if (mounted) setState(() { _works = works; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredWorks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _works;
    return _works
        .where((w) =>
            (w['title'] as String? ?? '').toLowerCase().contains(query) ||
            (w['group_name'] as String? ?? '').toLowerCase().contains(query) ||
            (w['tech_stack'] as String? ?? '').toLowerCase().contains(query))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredWorks;
    final isTeacherOrAdmin =
        widget.authService.isTeacher || widget.authService.isAdmin;

    return Stack(
      children: [
        Column(
          children: [
            // 搜索栏 + 筛选
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索作品名称、小组、技术栈...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            // 筛选 Chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: ['全部', '综合项目', '实验作业', '课外实践'].map((label) {
                  final selected = _selectedFilter == label;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _selectedFilter = label);
                        _loadWorks();
                      },
                      showCheckmark: false,
                      selectedColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            // 作品列表
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('没有找到匹配的作品',
                                  style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadWorks,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) =>
                                _buildWorkCard(context, filtered[i]),
                          ),
                        ),
            ),
          ],
        ),
        // 教师/管理员添加作品按钮
        if (isTeacherOrAdmin)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'gallery_add',
              onPressed: () => _showAddWorkDialog(context),
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  void _showAddWorkDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final techCtrl = TextEditingController();
    final groupCtrl = TextEditingController();
    final leaderCtrl = TextEditingController();
    String selectedType = '综合项目';
    final tagsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加作品'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: '作品名称 *',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: InputDecoration(
                    labelText: '作品类型',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  items: ['综合项目', '实验作业', '课外实践']
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedType = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: groupCtrl,
                  decoration: InputDecoration(
                    labelText: '小组名称',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: leaderCtrl,
                  decoration: InputDecoration(
                    labelText: '组长姓名',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: techCtrl,
                  decoration: InputDecoration(
                    labelText: '技术栈',
                    hintText: '如: Flutter + Android',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '作品描述',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tagsCtrl,
                  decoration: InputDecoration(
                    labelText: '标签（逗号分隔）',
                    hintText: 'Flutter, Android, 跨平台',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入作品名称')),
                  );
                  return;
                }
                final tagsList = tagsCtrl.text
                    .split(',')
                    .map((t) => t.trim())
                    .where((t) => t.isNotEmpty)
                    .toList();
                try {
                  await _worksDao.addWork(
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim().isNotEmpty
                        ? descCtrl.text.trim()
                        : null,
                    techStack: techCtrl.text.trim().isNotEmpty
                        ? techCtrl.text.trim()
                        : null,
                    workType: selectedType,
                    groupName: groupCtrl.text.trim().isNotEmpty
                        ? groupCtrl.text.trim()
                        : null,
                    leaderName: leaderCtrl.text.trim().isNotEmpty
                        ? leaderCtrl.text.trim()
                        : null,
                    userId: widget.authService.getCurrentUserId(),
                    status: '待提交',
                    tags: tagsList.isNotEmpty ? tagsList : null,
                  );
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('作品添加成功')),
                    );
                    _loadWorks();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('添加失败: $e')),
                    );
                  }
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkCard(BuildContext context, Map<String, dynamic> work) {
    final status = work['status'] as String? ?? '待提交';
    final statusColor = switch (status) {
      '已评分' => Colors.green,
      '已提交' => Colors.blue,
      '待提交' => Colors.orange,
      _ => Colors.grey,
    };
    final score = work['score'] as int?;
    final tags = work['tags'] != null
        ? (jsonDecode(work['tags'] as String) as List)
        : [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showWorkDetail(work),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题 + 状态
              Row(
                children: [
                  Expanded(
                    child: Text(work['title'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(status,
                        style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 描述
              Text(work['description'] as String? ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              // 信息行
              Row(
                children: [
                  Icon(Icons.group, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                      '${work['group_name'] ?? '未分组'} · ${work['leader_name'] ?? '未指定'}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(width: 12),
                  Icon(Icons.code, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(work['tech_stack'] as String? ?? '',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (score != null)
                    Text('$score分',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: score >= 90
                                ? Colors.green
                                : score >= 80
                                    ? Colors.blue
                                    : Colors.orange)),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                // 标签
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(t.toString(),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary)),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showWorkDetail(Map<String, dynamic> work) {
    final tags = work['tags'] != null
        ? (jsonDecode(work['tags'] as String) as List)
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) {
          final primary = Theme.of(context).colorScheme.primary;
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              // 拖拽手柄
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(work['title'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // 基本信息
              _detailRow(Icons.group, '小组',
                  '${work['group_name'] ?? '未分组'} (组长: ${work['leader_name'] ?? '未指定'})'),
              _detailRow(Icons.code, '技术栈',
                  work['tech_stack'] as String? ?? '未指定'),
              _detailRow(Icons.category, '类型',
                  work['work_type'] as String? ?? '未分类'),
              if (work['submit_time'] != null)
                _detailRow(Icons.schedule, '提交时间',
                    work['submit_time'] as String),
              if (work['created_at'] != null && work['submit_time'] == null)
                _detailRow(Icons.schedule, '创建时间',
                    work['created_at'] as String),
              _detailRow(
                  Icons.flag, '状态', work['status'] as String? ?? '待提交'),
              if (work['score'] != null)
                _detailRow(Icons.star, '评分', '${work['score']}分'),
              if (work['score_comment'] != null) ...[
                const Divider(height: 24),
                Text('教师评语',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primary)),
                const SizedBox(height: 8),
                Text(work['score_comment'] as String,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              ],
              const Divider(height: 24),
              Text('作品描述',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primary)),
              const SizedBox(height: 8),
              Text(work['description'] as String? ?? '暂无描述',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('技术标签',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: tags
                      .map((t) => Chip(
                            label: Text(t.toString(),
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor:
                                primary.withValues(alpha: 0.08),
                          ))
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 作品上传 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _WorksUploadTab extends StatefulWidget {
  final AuthService authService;
  const _WorksUploadTab({required this.authService});

  @override
  State<_WorksUploadTab> createState() => _WorksUploadTabState();
}

class _WorksUploadTabState extends State<_WorksUploadTab> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _techCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String _selectedType = '综合项目';
  final _worksDao = WorksDao();

  List<Map<String, dynamic>> _uploadRecords = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadUploadRecords();
  }

  Future<void> _loadUploadRecords() async {
    setState(() => _isLoading = true);
    try {
      final userId = widget.authService.getCurrentUserId();
      if (userId != null) {
        final records = await _worksDao.getWorks(userId: userId);
        if (mounted) setState(() { _uploadRecords = records; _isLoading = false; });
      } else {
        if (mounted) setState(() { _uploadRecords = []; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitWork() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入作品名称')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userId = widget.authService.getCurrentUserId();
      final tagsList = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      // 先添加作品
      final workId = await _worksDao.addWork(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : null,
        techStack: _techCtrl.text.trim().isNotEmpty
            ? _techCtrl.text.trim()
            : null,
        workType: _selectedType,
        userId: userId,
        status: '待提交',
        tags: tagsList.isNotEmpty ? tagsList : null,
      );

      // 再提交作品
      await _worksDao.submitWork(workId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('作品提交成功！'),
            backgroundColor: Colors.green,
          ),
        );
        // 清空表单
        _titleCtrl.clear();
        _descCtrl.clear();
        _techCtrl.clear();
        _tagsCtrl.clear();
        setState(() => _selectedType = '综合项目');
        // 刷新上传记录
        _loadUploadRecords();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _techCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 上传表单
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_upload, color: primary, size: 20),
                    const SizedBox(width: 8),
                    Text('提交作品',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primary)),
                  ],
                ),
                const SizedBox(height: 16),
                // 作品名称
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: '作品名称 *',
                    hintText: '请输入作品名称',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                // 作品类型
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: InputDecoration(
                    labelText: '作品类型',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  items: ['综合项目', '实验作业', '课外实践']
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
                const SizedBox(height: 12),
                // 技术栈
                TextField(
                  controller: _techCtrl,
                  decoration: InputDecoration(
                    labelText: '技术栈',
                    hintText: '如: Flutter + Android + HarmonyOS',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                // 标签
                TextField(
                  controller: _tagsCtrl,
                  decoration: InputDecoration(
                    labelText: '标签（逗号分隔）',
                    hintText: 'Flutter, Android, 跨平台',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                // 描述
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '作品描述',
                    hintText: '请简要描述你的作品功能和特点',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // 文件选择区域
                InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('文件选择功能将在后续版本中开放')),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.grey[300]!, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[50],
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            size: 40, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('点击选择文件上传',
                            style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('支持 ZIP/APK/PDF 格式，最大 100MB',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 提交按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitWork,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSubmitting ? '提交中...' : '提交作品'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 上传记录
        const Text('提交记录',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_isLoading)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ))
        else if (_uploadRecords.isEmpty)
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 40, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text('暂无提交记录',
                        style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              ),
            ),
          )
        else
          ..._uploadRecords.map((r) {
            final status = r['status'] as String? ?? '待提交';
            final isSubmitted = status == '已提交' || status == '已评分';
            final statusColor = isSubmitted ? Colors.green : Colors.orange;
            final statusIcon =
                isSubmitted ? Icons.check_circle : Icons.pending;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  child:
                      Icon(statusIcon, color: statusColor, size: 20),
                ),
                title: Text(r['title'] as String? ?? '',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(
                    '${r['submit_time'] ?? r['created_at'] ?? '未知时间'}'
                    '${r['file_size'] != null ? ' · ${r['file_size']}' : ''}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500])),
                trailing: Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w500)),
              ),
            );
          }),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 评分记录 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ScoreRecordTab extends StatefulWidget {
  final AuthService authService;
  const _ScoreRecordTab({required this.authService});

  @override
  State<_ScoreRecordTab> createState() => _ScoreRecordTabState();
}

class _ScoreRecordTabState extends State<_ScoreRecordTab> {
  final _worksDao = WorksDao();
  List<Map<String, dynamic>> _scoreRecords = [];
  bool _isLoading = true;

  // 评分维度
  static const dimensions = [
    {'name': '功能完整性', 'max': 25, 'icon': Icons.check_circle},
    {'name': '技术实现深度', 'max': 20, 'icon': Icons.code},
    {'name': '跨框架整合', 'max': 25, 'icon': Icons.integration_instructions},
    {'name': '性能与质量', 'max': 15, 'icon': Icons.speed},
    {'name': '文档与协作', 'max': 15, 'icon': Icons.description},
  ];

  @override
  void initState() {
    super.initState();
    _loadScoreRecords();
  }

  Future<void> _loadScoreRecords() async {
    setState(() => _isLoading = true);
    try {
      final records = await _worksDao.getScoreRecords();
      if (mounted) setState(() { _scoreRecords = records; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showScoreDialog(BuildContext context) async {
    // Load unscored works (status = '已提交')
    final works = await _worksDao.getWorks();
    final unscoredWorks = works
        .where((w) => w['status'] == '已提交')
        .toList();

    if (!mounted) return;

    if (unscoredWorks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有待评分的作品')),
      );
      return;
    }

    Map<String, dynamic>? selectedWork = unscoredWorks.first;
    double functionality = 15;
    double techDepth = 12;
    double integration = 15;
    double quality = 9;
    double documentation = 9;
    final commentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total = functionality.round() +
              techDepth.round() +
              integration.round() +
              quality.round() +
              documentation.round();
          return AlertDialog(
            title: const Text('作品评分'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 选择作品
                    DropdownButtonFormField<int>(
                      value: selectedWork!['id'] as int,
                      decoration: InputDecoration(
                        labelText: '选择作品',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      items: unscoredWorks.map((w) {
                        return DropdownMenuItem<int>(
                          value: w['id'] as int,
                          child: Text(w['title'] as String? ?? '',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setDialogState(() {
                          selectedWork = unscoredWorks
                              .firstWhere((w) => w['id'] == v);
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    // 功能完整性 (max 25)
                    _sliderDimension(
                      '功能完整性',
                      functionality,
                      25,
                      (v) => setDialogState(() => functionality = v),
                    ),
                    // 技术实现深度 (max 20)
                    _sliderDimension(
                      '技术实现深度',
                      techDepth,
                      20,
                      (v) => setDialogState(() => techDepth = v),
                    ),
                    // 跨框架整合 (max 25)
                    _sliderDimension(
                      '跨框架整合',
                      integration,
                      25,
                      (v) => setDialogState(() => integration = v),
                    ),
                    // 性能与质量 (max 15)
                    _sliderDimension(
                      '性能与质量',
                      quality,
                      15,
                      (v) => setDialogState(() => quality = v),
                    ),
                    // 文档与协作 (max 15)
                    _sliderDimension(
                      '文档与协作',
                      documentation,
                      15,
                      (v) => setDialogState(() => documentation = v),
                    ),
                    const SizedBox(height: 8),
                    // 总分
                    Center(
                      child: Text('总分: $total / 100',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: total >= 90
                                  ? Colors.green
                                  : total >= 80
                                      ? Colors.blue
                                      : total >= 60
                                          ? Colors.orange
                                          : Colors.red)),
                    ),
                    const SizedBox(height: 12),
                    // 评语
                    TextField(
                      controller: commentCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: '教师评语',
                        hintText: '请输入评语...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final user = widget.authService.currentUser;
                    await _worksDao.scoreWork(
                      workId: selectedWork!['id'] as int,
                      scorerId: widget.authService.getCurrentUserId(),
                      scorerName: user?.realName ?? '教师',
                      functionality: functionality.round(),
                      techDepth: techDepth.round(),
                      integration: integration.round(),
                      quality: quality.round(),
                      documentation: documentation.round(),
                      comment: commentCtrl.text.trim().isNotEmpty
                          ? commentCtrl.text.trim()
                          : null,
                    );
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('评分成功！'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadScoreRecords();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('评分失败: $e')),
                      );
                    }
                  }
                },
                child: const Text('提交评分'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sliderDimension(
      String name, double value, int max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      Text(name, style: const TextStyle(fontSize: 13))),
              Text('${value.round()} / $max',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: max.toDouble(),
            divisions: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isTeacherOrAdmin =
        widget.authService.isTeacher || widget.authService.isAdmin;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadScoreRecords,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 评分标准说明
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        primary.withValues(alpha: 0.08),
                        primary.withValues(alpha: 0.02)
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.rule, color: primary, size: 20),
                          const SizedBox(width: 8),
                          Text('作品评分标准（100分）',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: primary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...dimensions.map((d) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(d['icon'] as IconData,
                                    size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(d['name'] as String,
                                      style:
                                          const TextStyle(fontSize: 13)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        primary.withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Text('${d['max']}分',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: primary,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 教师打分提示
              if (isTeacherOrAdmin)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: Colors.amber.shade50,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.amber[800], size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                '作为教师，您可以点击右下方按钮对已提交作品进行评分',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.amber[800])),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 评分记录列表
              const Text('评分记录',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_isLoading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ))
              else if (_scoreRecords.isEmpty)
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.star_border,
                              size: 40, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          Text('暂无评分记录',
                              style:
                                  TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ..._scoreRecords.map(
                    (r) => _buildScoreRecordCard(context, r)),
            ],
          ),
        ),
        // 教师评分按钮
        if (isTeacherOrAdmin)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'score_fab',
              onPressed: () => _showScoreDialog(context),
              icon: const Icon(Icons.rate_review),
              label: const Text('评分'),
            ),
          ),
      ],
    );
  }

  Widget _buildScoreRecordCard(
      BuildContext context, Map<String, dynamic> record) {
    final total = (record['total_score'] as int?) ?? 0;
    final scoreColor = total >= 90
        ? Colors.green
        : total >= 80
            ? Colors.blue
            : total >= 60
                ? Colors.orange
                : Colors.red;

    final functionality = record['score_functionality'] as int?;
    final techDepth = record['score_tech_depth'] as int?;
    final integration = record['score_integration'] as int?;
    final quality = record['score_quality'] as int?;
    final documentation = record['score_documentation'] as int?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: scoreColor.withValues(alpha: 0.1),
          child: Text('$total',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: scoreColor)),
        ),
        title: Text(record['work_title'] as String? ?? '',
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
            '${record['group_name'] ?? '未分组'} · ${record['scorer_name'] ?? '教师'} · ${record['scored_at'] ?? ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 各维度分数条
                if (functionality != null)
                  _dimensionBar('功能完整性', functionality, 25),
                if (techDepth != null)
                  _dimensionBar('技术实现深度', techDepth, 20),
                if (integration != null)
                  _dimensionBar('跨框架整合', integration, 25),
                if (quality != null)
                  _dimensionBar('性能与质量', quality, 15),
                if (documentation != null)
                  _dimensionBar('文档与协作', documentation, 15),
                const SizedBox(height: 8),
                // 教师评语
                if (record['comment'] != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('教师评语',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700])),
                        const SizedBox(height: 4),
                        Text(record['comment'] as String,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dimensionBar(String name, int score, int max) {
    final color = score / max >= 0.9
        ? Colors.green
        : score / max >= 0.7
            ? Colors.blue
            : Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(name, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / max,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$score/$max',
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 排行榜 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _LeaderboardTab extends StatefulWidget {
  final AuthService authService;
  const _LeaderboardTab({required this.authService});

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  final _worksDao = WorksDao();
  List<Map<String, dynamic>> _leaderboard = [];
  Map<String, dynamic> _overview = {
    'total_works': 0,
    'avg_score': 0.0,
    'max_score': 0,
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final leaderboard = await _worksDao.getLeaderboard();
      final overview = await _worksDao.getOverview();
      if (mounted) {
        setState(() {
          _leaderboard = leaderboard;
          _overview = overview;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalWorks = _overview['total_works'] ?? 0;
    final avgScore = (_overview['avg_score'] as num?)?.toDouble() ?? 0.0;
    final maxScore = _overview['max_score'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 统计概览
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.7)],
                ),
              ),
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _overviewItem(
                      '作品总数', '$totalWorks', Icons.workspace_premium),
                  Container(
                      width: 1, height: 40, color: Colors.white30),
                  _overviewItem('平均分', avgScore.toStringAsFixed(1),
                      Icons.analytics),
                  Container(
                      width: 1, height: 40, color: Colors.white30),
                  _overviewItem(
                      '最高分', '$maxScore', Icons.emoji_events),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 领奖台
          if (_leaderboard.length >= 3)
            _buildPodium(context, _leaderboard),
          const SizedBox(height: 20),

          // 完整排行
          const Text('完整排行',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_leaderboard.isEmpty)
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.leaderboard,
                          size: 40, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text('暂无排行数据',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                ),
              ),
            )
          else
            ...List.generate(_leaderboard.length, (i) {
              final entry = Map<String, dynamic>.from(_leaderboard[i]);
              entry['rank'] = i + 1;
              return _buildRankCard(context, entry);
            }),
        ],
      ),
    );
  }

  Widget _overviewItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _buildPodium(
      BuildContext context, List<Map<String, dynamic>> leaderboard) {
    if (leaderboard.length < 3) return const SizedBox.shrink();

    final first = Map<String, dynamic>.from(leaderboard[0]);
    first['rank'] = 1;
    final second = Map<String, dynamic>.from(leaderboard[1]);
    second['rank'] = 2;
    final third = Map<String, dynamic>.from(leaderboard[2]);
    third['rank'] = 3;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 第2名
        _podiumItem(second, Colors.grey.shade400, 80),
        const SizedBox(width: 8),
        // 第1名
        _podiumItem(first, Colors.amber, 100),
        const SizedBox(width: 8),
        // 第3名
        _podiumItem(third, Colors.brown.shade300, 64),
      ],
    );
  }

  Widget _podiumItem(
      Map<String, dynamic> entry, Color color, double height) {
    final rank = entry['rank'] as int;
    final score = entry['score'] as int? ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 奖杯图标
        if (rank == 1)
          const Icon(Icons.emoji_events, color: Colors.amber, size: 32),
        CircleAvatar(
          radius: rank == 1 ? 24 : 20,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('#$rank',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: rank == 1 ? 16 : 14)),
        ),
        const SizedBox(height: 4),
        Text(entry['group_name'] as String? ?? '未分组',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600)),
        Text('$score分',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 4),
        // 底座
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          alignment: Alignment.center,
          child: Text(
            entry['title'] as String? ?? '',
            style: const TextStyle(fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildRankCard(
      BuildContext context, Map<String, dynamic> entry) {
    final rank = entry['rank'] as int;
    final score = entry['score'] as int? ?? 0;
    final rankColor = rank == 1
        ? Colors.amber
        : rank == 2
            ? Colors.grey.shade400
            : rank == 3
                ? Colors.brown.shade300
                : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor.withValues(alpha: 0.15),
          child: Text('#$rank',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: rankColor,
                  fontSize: 14)),
        ),
        title: Text(entry['title'] as String? ?? '',
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${entry['group_name'] ?? '未分组'} · 组长: ${entry['leader_name'] ?? '未指定'}',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[500])),
            if (entry['comment'] != null) ...[
              const SizedBox(height: 2),
              Text(entry['comment'] as String,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[400]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
        trailing: Text('$score',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: score >= 90
                    ? Colors.green
                    : score >= 80
                        ? Colors.blue
                        : Colors.orange)),
      ),
    );
  }
}
