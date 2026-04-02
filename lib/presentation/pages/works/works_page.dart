import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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

  // 模拟作品数据
  final List<Map<String, dynamic>> _works = [
    {
      'title': '智慧校园生活服务平台',
      'group': '第1组',
      'leader': '张三',
      'tech': 'Flutter + Android 原生',
      'desc': '面向高校师生的跨平台校园服务，整合课表、场馆预约、校园导航等功能',
      'status': '已提交',
      'submitTime': '2024-12-15 14:30',
      'score': 92,
      'tags': ['Flutter', 'Android', '跨平台'],
      'type': '综合项目',
    },
    {
      'title': '在线学习辅助平台',
      'group': '第2组',
      'leader': '陈九',
      'tech': 'Flutter + React Native',
      'desc': '提供在线学习、笔记管理、学习计划和协作讨论功能',
      'status': '已提交',
      'submitTime': '2024-12-14 16:20',
      'score': 88,
      'tags': ['Flutter', 'React Native', '学习'],
      'type': '综合项目',
    },
    {
      'title': '智能健康运动记录',
      'group': '第3组',
      'leader': '卫五',
      'tech': 'Flutter + HarmonyOS',
      'desc': '记录运动轨迹、健康数据分析、社交分享健身成果',
      'status': '已评分',
      'submitTime': '2024-12-13 10:45',
      'score': 85,
      'tags': ['Flutter', 'HarmonyOS', '健康'],
      'type': '综合项目',
    },
    {
      'title': '二手物品交易平台',
      'group': '第4组',
      'leader': '秦一',
      'tech': 'Flutter + 小程序',
      'desc': '校园二手商品发布、搜索、即时聊天、交易管理',
      'status': '已评分',
      'submitTime': '2024-12-12 09:30',
      'score': 90,
      'tags': ['Flutter', '小程序', '电商'],
      'type': '综合项目',
    },
    {
      'title': 'Android 原生 TODO 应用',
      'group': '第1组',
      'leader': '张三',
      'tech': 'Android (Kotlin)',
      'desc': '基于 Room + MVVM 架构的本地待办事项管理应用',
      'status': '已提交',
      'submitTime': '2024-11-20 11:00',
      'score': null,
      'tags': ['Android', 'Kotlin', 'MVVM'],
      'type': '实验作业',
    },
    {
      'title': '微信小程序天气查询',
      'group': '第2组',
      'leader': '陈九',
      'tech': '微信小程序',
      'desc': '基于和风天气 API 的小程序，支持城市搜索和 7 天预报',
      'status': '待提交',
      'submitTime': null,
      'score': null,
      'tags': ['小程序', 'API', '天气'],
      'type': '实验作业',
    },
  ];

  List<Map<String, dynamic>> get _filteredWorks {
    var result = _works;
    if (_selectedFilter != '全部') {
      result = result.where((w) => w['type'] == _selectedFilter).toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result
          .where((w) =>
              (w['title'] as String).toLowerCase().contains(query) ||
              (w['group'] as String).toLowerCase().contains(query) ||
              (w['tech'] as String).toLowerCase().contains(query))
          .toList();
    }
    return result;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredWorks;
    return Column(
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
            children: ['全部', '综合项目', '实验作业'].map((label) {
              final selected = _selectedFilter == label;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedFilter = label),
                  showCheckmark: false,
                  selectedColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
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
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('没有找到匹配的作品',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) =>
                      _buildWorkCard(context, filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildWorkCard(BuildContext context, Map<String, dynamic> work) {
    final statusColor = switch (work['status']) {
      '已评分' => Colors.green,
      '已提交' => Colors.blue,
      '待提交' => Colors.orange,
      _ => Colors.grey,
    };
    final score = work['score'] as int?;
    final tags = work['tags'] as List;

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
                    child: Text(work['title'] as String,
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
                    child: Text(work['status'] as String,
                        style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 描述
              Text(work['desc'] as String,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              // 信息行
              Row(
                children: [
                  Icon(Icons.group, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text('${work['group']} · ${work['leader']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(width: 12),
                  Icon(Icons.code, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(work['tech'] as String,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWorkDetail(Map<String, dynamic> work) {
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
              Text(work['title'] as String,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // 基本信息
              _detailRow(Icons.group, '小组', '${work['group']} (组长: ${work['leader']})'),
              _detailRow(Icons.code, '技术栈', work['tech'] as String),
              _detailRow(Icons.category, '类型', work['type'] as String),
              if (work['submitTime'] != null)
                _detailRow(Icons.schedule, '提交时间', work['submitTime'] as String),
              _detailRow(Icons.flag, '状态', work['status'] as String),
              if (work['score'] != null)
                _detailRow(Icons.star, '评分', '${work['score']}分'),
              const Divider(height: 24),
              Text('作品描述',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primary)),
              const SizedBox(height: 8),
              Text(work['desc'] as String,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              const SizedBox(height: 16),
              // 标签
              Text('技术标签',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: (work['tags'] as List)
                    .map((t) => Chip(
                          label: Text(t.toString(),
                              style: const TextStyle(fontSize: 12)),
                          backgroundColor: primary.withValues(alpha: 0.08),
                        ))
                    .toList(),
              ),
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
            child:
                Text(value, style: const TextStyle(fontSize: 13)),
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
  String _selectedType = '综合项目';

  // 模拟上传记录
  final List<Map<String, dynamic>> _uploadRecords = [
    {
      'title': '智慧校园生活服务平台',
      'time': '2024-12-15 14:30',
      'size': '25.6 MB',
      'status': '上传成功',
    },
    {
      'title': 'Android TODO 应用',
      'time': '2024-11-20 11:00',
      'size': '12.3 MB',
      'status': '上传成功',
    },
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _techCtrl.dispose();
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
                    labelText: '作品名称',
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
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
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
                    onPressed: () {
                      if (_titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入作品名称')),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('提交功能将在后续版本中开放')),
                      );
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('提交作品'),
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
        const Text('上传记录',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._uploadRecords.map((r) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.withValues(alpha: 0.1),
                  child: const Icon(Icons.check_circle,
                      color: Colors.green, size: 20),
                ),
                title: Text(r['title'] as String,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(
                    '${r['time']} · ${r['size']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                trailing: Text(r['status'] as String,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w500)),
              ),
            )),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 评分记录 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ScoreRecordTab extends StatelessWidget {
  final AuthService authService;
  const _ScoreRecordTab({required this.authService});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isTeacherOrAdmin = authService.isTeacher || authService.isAdmin;

    // 评分维度
    const dimensions = [
      {'name': '功能完整性', 'max': 25, 'icon': Icons.check_circle},
      {'name': '技术实现深度', 'max': 20, 'icon': Icons.code},
      {'name': '跨框架整合', 'max': 25, 'icon': Icons.integration_instructions},
      {'name': '性能与质量', 'max': 15, 'icon': Icons.speed},
      {'name': '文档与协作', 'max': 15, 'icon': Icons.description},
    ];

    // 模拟评分记录
    final scoreRecords = [
      {
        'title': '智慧校园生活服务平台',
        'group': '第1组',
        'scores': {'功能完整性': 23, '技术实现深度': 18, '跨框架整合': 22, '性能与质量': 13, '文档与协作': 14},
        'total': 92,
        'teacher': '刘东良教师',
        'time': '2024-12-16',
        'comment': '功能完整，技术栈选型合理，UI 交互流畅',
      },
      {
        'title': '二手物品交易平台',
        'group': '第4组',
        'scores': {'功能完整性': 22, '技术实现深度': 18, '跨框架整合': 21, '性能与质量': 14, '文档与协作': 13},
        'total': 90,
        'teacher': '刘东良教师',
        'time': '2024-12-16',
        'comment': '交易流程完善，即时聊天功能亮点突出',
      },
      {
        'title': '在线学习辅助平台',
        'group': '第2组',
        'scores': {'功能完整性': 21, '技术实现深度': 17, '跨框架整合': 20, '性能与质量': 13, '文档与协作': 12},
        'total': 88,
        'teacher': '刘东良教师',
        'time': '2024-12-16',
        'comment': '学习功能全面，建议优化笔记同步性能',
      },
      {
        'title': '智能健康运动记录',
        'group': '第3组',
        'scores': {'功能完整性': 20, '技术实现深度': 16, '跨框架整合': 20, '性能与质量': 12, '文档与协作': 12},
        'total': 85,
        'teacher': '刘东良教师',
        'time': '2024-12-16',
        'comment': '运动记录功能扎实，HarmonyOS 适配值得肯定',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 评分标准说明
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
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
                      child: Text('作为教师，您可以点击作品卡片进行评分操作',
                          style: TextStyle(
                              fontSize: 13, color: Colors.amber[800])),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 评分记录列表
        const Text('评分记录',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...scoreRecords.map((r) => _buildScoreRecordCard(context, r)),
      ],
    );
  }

  Widget _buildScoreRecordCard(
      BuildContext context, Map<String, dynamic> record) {
    final scores = record['scores'] as Map<String, int>;
    final total = record['total'] as int;
    final scoreColor = total >= 90
        ? Colors.green
        : total >= 80
            ? Colors.blue
            : total >= 60
                ? Colors.orange
                : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: scoreColor.withValues(alpha: 0.1),
          child: Text('$total',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: scoreColor)),
        ),
        title: Text(record['title'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
            '${record['group']} · ${record['teacher']} · ${record['time']}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 各维度分数条
                ...scores.entries.map((e) {
                  final max = e.key == '功能完整性' || e.key == '跨框架整合'
                      ? 25
                      : e.key == '技术实现深度'
                          ? 20
                          : 15;
                  return _dimensionBar(e.key, e.value, max);
                }),
                const SizedBox(height: 8),
                // 教师评语
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
                  fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 排行榜 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _LeaderboardTab extends StatelessWidget {
  final AuthService authService;
  const _LeaderboardTab({required this.authService});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final leaderboard = [
      {
        'rank': 1,
        'title': '智慧校园生活服务平台',
        'group': '第1组',
        'leader': '张三',
        'score': 92,
        'highlight': '功能完整，跨平台体验优秀',
      },
      {
        'rank': 2,
        'title': '二手物品交易平台',
        'group': '第4组',
        'leader': '秦一',
        'score': 90,
        'highlight': '交易流程完善，即时聊天亮点',
      },
      {
        'rank': 3,
        'title': '在线学习辅助平台',
        'group': '第2组',
        'leader': '陈九',
        'score': 88,
        'highlight': '学习功能全面，协作设计出色',
      },
      {
        'rank': 4,
        'title': '智能健康运动记录',
        'group': '第3组',
        'leader': '卫五',
        'score': 85,
        'highlight': 'HarmonyOS 适配值得肯定',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 统计概览
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                _overviewItem('作品总数', '6', Icons.workspace_premium),
                Container(width: 1, height: 40, color: Colors.white30),
                _overviewItem('平均分', '88.8', Icons.analytics),
                Container(width: 1, height: 40, color: Colors.white30),
                _overviewItem('最高分', '92', Icons.emoji_events),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 领奖台
        _buildPodium(context, leaderboard),
        const SizedBox(height: 20),

        // 完整排行
        const Text('完整排行',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...leaderboard.map((s) => _buildRankCard(context, s)),
      ],
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
            style:
                TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _buildPodium(
      BuildContext context, List<Map<String, dynamic>> leaderboard) {
    if (leaderboard.length < 3) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 第2名
        _podiumItem(leaderboard[1], Colors.grey.shade400, 80),
        const SizedBox(width: 8),
        // 第1名
        _podiumItem(leaderboard[0], Colors.amber, 100),
        const SizedBox(width: 8),
        // 第3名
        _podiumItem(leaderboard[2], Colors.brown.shade300, 64),
      ],
    );
  }

  Widget _podiumItem(
      Map<String, dynamic> entry, Color color, double height) {
    final rank = entry['rank'] as int;
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
        Text(entry['group'] as String,
            style:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        Text('${entry['score']}分',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
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
            entry['title'] as String,
            style: const TextStyle(fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildRankCard(BuildContext context, Map<String, dynamic> entry) {
    final rank = entry['rank'] as int;
    final score = entry['score'] as int;
    final rankColor = rank == 1
        ? Colors.amber
        : rank == 2
            ? Colors.grey.shade400
            : rank == 3
                ? Colors.brown.shade300
                : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor.withValues(alpha: 0.15),
          child: Text('#$rank',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: rankColor, fontSize: 14)),
        ),
        title: Text(entry['title'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry['group']} · 组长: ${entry['leader']}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 2),
            Text(entry['highlight'] as String,
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
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
