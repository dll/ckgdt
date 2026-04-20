import 'package:flutter/material.dart';
import '../../../data/local/teaching_dao.dart';
import '../../../services/auth_service.dart';

/// 教学管理中心 — 大纲管理 / 教案管理 / 教学进度
class TeachingManagePage extends StatefulWidget {
  const TeachingManagePage({super.key});

  @override
  State<TeachingManagePage> createState() => _TeachingManagePageState();
}

class _TeachingManagePageState extends State<TeachingManagePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教学管理中心'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.menu_book), text: '课程大纲'),
            Tab(icon: Icon(Icons.description), text: '教案管理'),
            Tab(icon: Icon(Icons.timeline), text: '教学进度'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _SyllabusTab(),
          _LessonPlanTab(),
          _ProgressTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 1: 课程大纲管理
// ═══════════════════════════════════════════════════════════════════════════════

class _SyllabusTab extends StatefulWidget {
  const _SyllabusTab();

  @override
  State<_SyllabusTab> createState() => _SyllabusTabState();
}

class _SyllabusTabState extends State<_SyllabusTab>
    with AutomaticKeepAliveClientMixin {
  final _dao = TeachingDao();
  List<Map<String, dynamic>> _items = [];
  Map<String, int> _stats = {};
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 首次加载时初始化默认大纲
      await _dao.initDefaultSyllabus();
      final items = await _dao.getAllSyllabusItems();
      final stats = await _dao.getSyllabusStats();
      setState(() {
        _items = items;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: Column(
        children: [
          // 统计栏
          _buildStatsBar(),
          // 列表
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('暂无大纲数据',
                            style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _dao.initDefaultSyllabus();
                            _loadData();
                          },
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('生成默认大纲'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) => _buildSyllabusCard(_items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildStatChip('总计', _stats['total'] ?? 0, Colors.blue),
          const SizedBox(width: 8),
          _buildStatChip('计划中', _stats['planned'] ?? 0, Colors.grey),
          const SizedBox(width: 8),
          _buildStatChip('进行中', _stats['in_progress'] ?? 0, Colors.orange),
          const SizedBox(width: 8),
          _buildStatChip('已完成', _stats['completed'] ?? 0, Colors.green),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildSyllabusCard(Map<String, dynamic> item) {
    final status = item['status'] as String? ?? 'planned';
    final statusInfo = _getStatusInfo(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withValues(alpha: 0.1),
          child: Text(
            '${item['chapter_number']}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ),
        title: Text(
          item['title'] as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusInfo.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusInfo.label,
                style: TextStyle(fontSize: 11, color: statusInfo.color),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${item['hours'] ?? 2} 学时  |  第${item['week_start'] ?? '?'}-${item['week_end'] ?? '?'}周',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((item['description'] as String?)?.isNotEmpty == true) ...[
                  _buildInfoRow(Icons.info_outline, '章节简介',
                      item['description'] as String),
                  const SizedBox(height: 8),
                ],
                if ((item['objectives'] as String?)?.isNotEmpty == true) ...[
                  _buildInfoRow(
                      Icons.flag, '教学目标', item['objectives'] as String),
                  const SizedBox(height: 8),
                ],
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 状态切换
                    PopupMenuButton<String>(
                      child: Chip(
                        label: Text('切换状态',
                            style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                        avatar: Icon(Icons.swap_horiz, size: 16, color: Colors.blue[700]),
                        backgroundColor: Colors.blue.withValues(alpha: 0.08),
                      ),
                      onSelected: (newStatus) async {
                        await _dao.updateSyllabusStatus(
                            item['id'] as int, newStatus);
                        _loadData();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'planned', child: Text('计划中')),
                        const PopupMenuItem(
                            value: 'in_progress', child: Text('进行中')),
                        const PopupMenuItem(
                            value: 'completed', child: Text('已完成')),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // 编辑
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      tooltip: '编辑',
                      onPressed: () => _showEditDialog(item),
                    ),
                    // 删除
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      tooltip: '删除',
                      onPressed: () => _confirmDelete(item),
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

  Widget _buildInfoRow(IconData icon, String label, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700])),
              const SizedBox(height: 2),
              Text(content, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'in_progress':
        return _StatusInfo('进行中', Colors.orange);
      case 'completed':
        return _StatusInfo('已完成', Colors.green);
      default:
        return _StatusInfo('计划中', Colors.grey);
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic>? item) async {
    final isEdit = item != null;
    final titleCtrl =
        TextEditingController(text: item?['title'] as String? ?? '');
    final descCtrl =
        TextEditingController(text: item?['description'] as String? ?? '');
    final objCtrl =
        TextEditingController(text: item?['objectives'] as String? ?? '');
    final hoursCtrl = TextEditingController(
        text: '${item?['hours'] ?? 2}');
    final chapterCtrl = TextEditingController(
        text: '${item?['chapter_number'] ?? (_items.length + 1)}');
    final weekStartCtrl = TextEditingController(
        text: '${item?['week_start'] ?? ''}');
    final weekEndCtrl = TextEditingController(
        text: '${item?['week_end'] ?? ''}');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? '编辑大纲' : '新增大纲'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: chapterCtrl,
                        decoration: const InputDecoration(
                          labelText: '章节号',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: '章节标题 *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: '章节简介',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: objCtrl,
                  decoration: const InputDecoration(
                    labelText: '教学目标',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: hoursCtrl,
                        decoration: const InputDecoration(
                          labelText: '学时',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: weekStartCtrl,
                        decoration: const InputDecoration(
                          labelText: '起始周',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: weekEndCtrl,
                        decoration: const InputDecoration(
                          labelText: '结束周',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
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
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              final data = {
                'chapter_number': int.tryParse(chapterCtrl.text) ?? 1,
                'title': titleCtrl.text.trim(),
                'description': descCtrl.text.trim(),
                'objectives': objCtrl.text.trim(),
                'hours': int.tryParse(hoursCtrl.text) ?? 2,
                'week_start': int.tryParse(weekStartCtrl.text),
                'week_end': int.tryParse(weekEndCtrl.text),
              };
              if (isEdit) {
                await _dao.updateSyllabusItem(item['id'] as int, data);
              } else {
                await _dao.addSyllabusItem(data);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: Text(isEdit ? '保存' : '新增'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除"${item['title']}"？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _dao.deleteSyllabusItem(item['id'] as int);
      _loadData();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 2: 教案管理
// ═══════════════════════════════════════════════════════════════════════════════

class _LessonPlanTab extends StatefulWidget {
  const _LessonPlanTab();

  @override
  State<_LessonPlanTab> createState() => _LessonPlanTabState();
}

class _LessonPlanTabState extends State<_LessonPlanTab>
    with AutomaticKeepAliveClientMixin {
  final _dao = TeachingDao();
  List<Map<String, dynamic>> _plans = [];
  Map<String, int> _stats = {};
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 首次加载时初始化默认教案
      await _dao.initDefaultLessonPlans();
      final plans = await _dao.getAllLessonPlans();
      final stats = await _dao.getLessonPlanStats();
      setState(() {
        _plans = plans;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: Column(
        children: [
          // 统计栏 + 新增按钮
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildStatChip('总计', _stats['total'] ?? 0, Colors.blue),
                const SizedBox(width: 6),
                _buildStatChip('草稿', _stats['draft'] ?? 0, Colors.grey),
                const SizedBox(width: 6),
                _buildStatChip('就绪', _stats['ready'] ?? 0, Colors.green),
                const SizedBox(width: 6),
                _buildStatChip('AI生成', _stats['ai_generated'] ?? 0, Colors.purple),
                const SizedBox(width: 12),
                FloatingActionButton.small(
                  heroTag: 'add_plan',
                  onPressed: () => _showPlanEditor(null),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          // 列表
          Expanded(
            child: _plans.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('暂无教案',
                            style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 8),
                        Text('点击右上角 + 创建新教案',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[400])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _plans.length,
                    itemBuilder: (ctx, i) => _buildPlanCard(_plans[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final status = plan['status'] as String? ?? 'draft';
    final isAi = (plan['ai_generated'] as int? ?? 0) == 1;
    final statusColor = status == 'ready'
        ? Colors.green
        : status == 'used'
            ? Colors.blue
            : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.withValues(alpha: 0.1),
          child: Text(
            '${plan['chapter']}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.indigo),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                plan['title'] as String? ?? '',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isAi)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AI',
                    style: TextStyle(fontSize: 10, color: Colors.purple)),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status == 'ready'
                    ? '就绪'
                    : status == 'used'
                        ? '已使用'
                        : '草稿',
                style: TextStyle(fontSize: 11, color: statusColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              (plan['updated_at'] as String? ?? '').split('T').first,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((plan['objectives'] as String?)?.isNotEmpty == true)
                  _buildSection('教学目标', plan['objectives'] as String),
                if ((plan['key_points'] as String?)?.isNotEmpty == true)
                  _buildSection('教学重点', plan['key_points'] as String),
                if ((plan['difficult_points'] as String?)?.isNotEmpty == true)
                  _buildSection('教学难点', plan['difficult_points'] as String),
                if ((plan['content'] as String?)?.isNotEmpty == true)
                  _buildSection('教学内容', plan['content'] as String),
                if ((plan['activities'] as String?)?.isNotEmpty == true)
                  _buildSection('教学活动', plan['activities'] as String),
                if ((plan['homework'] as String?)?.isNotEmpty == true)
                  _buildSection('课后作业', plan['homework'] as String),
                if ((plan['reflection'] as String?)?.isNotEmpty == true)
                  _buildSection('教学反思', plan['reflection'] as String),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 状态切换
                    PopupMenuButton<String>(
                      child: Chip(
                        label: Text('状态',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue[700])),
                        avatar: Icon(Icons.swap_horiz,
                            size: 16, color: Colors.blue[700]),
                        backgroundColor: Colors.blue.withValues(alpha: 0.08),
                      ),
                      onSelected: (s) async {
                        await _dao.updateLessonPlanStatus(
                            plan['id'] as int, s);
                        _loadData();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'draft', child: Text('草稿')),
                        PopupMenuItem(value: 'ready', child: Text('就绪')),
                        PopupMenuItem(value: 'used', child: Text('已使用')),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      tooltip: '编辑',
                      onPressed: () => _showPlanEditor(plan),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete,
                          size: 20, color: Colors.red),
                      tooltip: '删除',
                      onPressed: () => _confirmDelete(plan),
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

  Widget _buildSection(String label, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
          const SizedBox(height: 2),
          Text(content, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _showPlanEditor(Map<String, dynamic>? plan) async {
    final isEdit = plan != null;
    final chapterCtrl =
        TextEditingController(text: '${plan?['chapter'] ?? 1}');
    final titleCtrl =
        TextEditingController(text: plan?['title'] as String? ?? '');
    final objectivesCtrl =
        TextEditingController(text: plan?['objectives'] as String? ?? '');
    final keyPointsCtrl =
        TextEditingController(text: plan?['key_points'] as String? ?? '');
    final diffPointsCtrl =
        TextEditingController(text: plan?['difficult_points'] as String? ?? '');
    final contentCtrl =
        TextEditingController(text: plan?['content'] as String? ?? '');
    final activitiesCtrl =
        TextEditingController(text: plan?['activities'] as String? ?? '');
    final homeworkCtrl =
        TextEditingController(text: plan?['homework'] as String? ?? '');
    final reflectionCtrl =
        TextEditingController(text: plan?['reflection'] as String? ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
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
                    child: Text(isEdit ? '编辑教案' : '新建教案',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) return;
                      final data = {
                        'chapter': int.tryParse(chapterCtrl.text) ?? 1,
                        'title': titleCtrl.text.trim(),
                        'objectives': objectivesCtrl.text.trim(),
                        'key_points': keyPointsCtrl.text.trim(),
                        'difficult_points': diffPointsCtrl.text.trim(),
                        'content': contentCtrl.text.trim(),
                        'activities': activitiesCtrl.text.trim(),
                        'homework': homeworkCtrl.text.trim(),
                        'reflection': reflectionCtrl.text.trim(),
                        'status': 'draft',
                      };
                      if (isEdit) {
                        await _dao.updateLessonPlan(plan['id'] as int, data);
                      } else {
                        await _dao.addLessonPlan(data);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadData();
                    },
                    child: Text(isEdit ? '保存' : '创建'),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: chapterCtrl,
                      decoration: const InputDecoration(
                        labelText: '章节',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: '教案标题 *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: objectivesCtrl,
                decoration: const InputDecoration(
                  labelText: '教学目标',
                  border: OutlineInputBorder(),
                  hintText: '本节课学生应掌握的知识和技能',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyPointsCtrl,
                decoration: const InputDecoration(
                  labelText: '教学重点',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: diffPointsCtrl,
                decoration: const InputDecoration(
                  labelText: '教学难点',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(
                  labelText: '教学内容',
                  border: OutlineInputBorder(),
                  hintText: '具体教学内容与步骤',
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: activitiesCtrl,
                decoration: const InputDecoration(
                  labelText: '教学活动',
                  border: OutlineInputBorder(),
                  hintText: '课堂练习、分组讨论等',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: homeworkCtrl,
                decoration: const InputDecoration(
                  labelText: '课后作业',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reflectionCtrl,
                decoration: const InputDecoration(
                  labelText: '教学反思（课后填写）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除教案"${plan['title']}"？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _dao.deleteLessonPlan(plan['id'] as int);
      _loadData();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 3: 教学进度
// ═══════════════════════════════════════════════════════════════════════════════

class _ProgressTab extends StatefulWidget {
  const _ProgressTab();

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab>
    with AutomaticKeepAliveClientMixin {
  final _dao = TeachingDao();
  final _authService = AuthService();
  List<Map<String, dynamic>> _progressList = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final list = await _dao.getAllTeachingProgress();
      final stats = await _dao.getProgressStats();
      setState(() {
        _progressList = list;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: Column(
        children: [
          // 统计和进度条
          _buildProgressHeader(),
          // 操作按钮
          if (_progressList.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _generateProgress,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('根据大纲自动生成进度计划'),
              ),
            ),
          // 列表
          Expanded(
            child: _progressList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timeline,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('暂无教学进度数据',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _progressList.length,
                    itemBuilder: (ctx, i) =>
                        _buildProgressCard(_progressList[i], i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHeader() {
    final total = (_stats['total'] as int?) ?? 0;
    final completed = (_stats['completed'] as int?) ?? 0;
    final rate = total > 0 ? completed / total : 0.0;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade400, Colors.teal.shade700],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('教学进度总览',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text('${_stats['progress_rate'] ?? '0.0'}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _headerStat('计划', (_stats['planned'] as int?) ?? 0),
              _headerStat('进行中', (_stats['in_progress'] as int?) ?? 0),
              _headerStat('已完成', completed),
              _headerStat('总计', total),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, int value) {
    return Column(
      children: [
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildProgressCard(Map<String, dynamic> item, int index) {
    final status = item['status'] as String? ?? 'planned';
    final isCompleted = status == 'completed';
    final isInProgress = status == 'in_progress';

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    if (isCompleted) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusLabel = '已完成';
    } else if (isInProgress) {
      statusColor = Colors.orange;
      statusIcon = Icons.play_circle;
      statusLabel = '进行中';
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.radio_button_unchecked;
      statusLabel = '计划';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showProgressDetail(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 时间线圆点
              Column(
                children: [
                  if (index > 0)
                    Container(
                        width: 2,
                        height: 8,
                        color: isCompleted ? Colors.green : Colors.grey[300]),
                  Icon(statusIcon, color: statusColor, size: 28),
                  if (index < _progressList.length - 1)
                    Container(
                        width: 2,
                        height: 8,
                        color: isCompleted ? Colors.green : Colors.grey[300]),
                ],
              ),
              const SizedBox(width: 12),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('第${item['chapter']}章',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue[700])),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  fontSize: 10, color: statusColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['topic'] as String? ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          '计划：${item['planned_date'] ?? '未定'}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                        if (item['actual_date'] != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check, size: 12, color: Colors.green[400]),
                          const SizedBox(width: 4),
                          Text(
                            '实际：${item['actual_date']}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.green[600]),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 操作
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (action) async {
                  switch (action) {
                    case 'start':
                      await _dao.updateTeachingProgress(item['id'] as int, {
                        'status': 'in_progress',
                      });
                      break;
                    case 'complete':
                      await _dao.markProgressCompleted(item['id'] as int);
                      break;
                    case 'reset':
                      await _dao.updateTeachingProgress(item['id'] as int, {
                        'status': 'planned',
                        'actual_date': null,
                      });
                      break;
                    case 'delete':
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('确认删除'),
                          content: const Text('确定删除此进度记录？'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消')),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _dao.deleteTeachingProgress(item['id'] as int);
                      }
                      break;
                  }
                  _loadData();
                },
                itemBuilder: (_) => [
                  if (status == 'planned')
                    const PopupMenuItem(
                        value: 'start', child: Text('开始教学')),
                  if (status != 'completed')
                    const PopupMenuItem(
                        value: 'complete', child: Text('标记完成')),
                  if (status != 'planned')
                    const PopupMenuItem(
                        value: 'reset', child: Text('重置为计划')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProgressDetail(Map<String, dynamic> item) async {
    final notesCtrl =
        TextEditingController(text: item['notes'] as String? ?? '');
    final attendanceCtrl = TextEditingController(
        text: '${item['attendance'] ?? 0}');
    final hwCtrl = TextEditingController(
        text: '${(item['homework_completion'] as num? ?? 0).toStringAsFixed(0)}');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('第${item['chapter']}章 - ${item['topic'] ?? ''}'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: attendanceCtrl,
                        decoration: const InputDecoration(
                          labelText: '出勤人数',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: hwCtrl,
                        decoration: const InputDecoration(
                          labelText: '作业完成率(%)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: '教学备注',
                    border: OutlineInputBorder(),
                    hintText: '课堂表现、教学效果等',
                  ),
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await _dao.updateTeachingProgress(item['id'] as int, {
                'attendance': int.tryParse(attendanceCtrl.text) ?? 0,
                'homework_completion':
                    double.tryParse(hwCtrl.text) ?? 0,
                'notes': notesCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateProgress() async {
    final teacherId = _authService.currentUser?.userId;
    final count = await _dao.generateProgressFromSyllabus(
        teacherId: teacherId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已根据大纲生成 $count 条教学进度')),
      );
    }
    _loadData();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 辅助类
// ─────────────────────────────────────────────────────────────────────────────

class _StatusInfo {
  final String label;
  final Color color;
  const _StatusInfo(this.label, this.color);
}
