import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_resource_service.dart';
import '../../../data/local/assessment_dao.dart';

/// 考核页面 — 参考 Python 版 assessment_tab.py
/// 五大子页: 分组管理 / 项目立项 / 贡献评分 / 答辩安排 / 成绩统计
class AssessmentPage extends StatefulWidget {
  const AssessmentPage({super.key});

  @override
  State<AssessmentPage> createState() => _AssessmentPageState();
}

class _AssessmentPageState extends State<AssessmentPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _assessmentDao = AssessmentDao();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initDemoData();
  }

  Future<void> _initDemoData() async {
    try {
      await _assessmentDao.initDemoDataIfEmpty();
    } catch (_) {}
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

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
              Tab(icon: Icon(Icons.groups, size: 18), text: '分组'),
              Tab(icon: Icon(Icons.assignment, size: 18), text: '项目'),
              Tab(icon: Icon(Icons.star_rate, size: 18), text: '贡献'),
              Tab(
                  icon: Icon(Icons.record_voice_over, size: 18),
                  text: '答辩'),
              Tab(icon: Icon(Icons.leaderboard, size: 18), text: '成绩'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GroupTab(authService: _authService),
              _ProjectTab(authService: _authService),
              _ContributionTab(authService: _authService),
              _DefenseTab(authService: _authService),
              _ScoreTab(authService: _authService),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 分组管理 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _GroupTab extends StatefulWidget {
  final AuthService authService;
  const _GroupTab({required this.authService});

  @override
  State<_GroupTab> createState() => _GroupTabState();
}

class _GroupTabState extends State<_GroupTab> {
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final groups = await _dao.getGroups();
      final stats = await _dao.getGroupStats();
      if (mounted) {
        setState(() {
          _groups = groups;
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _parseMemberNames(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.cast<String>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.cast<String>();
      } catch (_) {}
    }
    return [];
  }

  void _showAddGroupDialog() {
    final nameCtrl = TextEditingController();
    final leaderCtrl = TextEditingController();
    final membersCtrl = TextEditingController();
    final projectCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: '组名', hintText: '如：第5组'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: leaderCtrl,
                decoration: const InputDecoration(
                    labelText: '组长姓名', hintText: '如：刘一'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: membersCtrl,
                decoration: const InputDecoration(
                  labelText: '组员姓名',
                  hintText: '逗号分隔，如：刘一,陈二,张三',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: projectCtrl,
                decoration: const InputDecoration(
                    labelText: '项目名称（可选）'),
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
              if (nameCtrl.text.trim().isEmpty) return;
              final members = membersCtrl.text
                  .split(RegExp(r'[,，]'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              await _dao.addGroup(
                name: nameCtrl.text.trim(),
                leader: leaderCtrl.text.trim().isNotEmpty
                    ? leaderCtrl.text.trim()
                    : null,
                memberNames: members.isNotEmpty ? members : null,
                projectName: projectCtrl.text.trim().isNotEmpty
                    ? projectCtrl.text.trim()
                    : null,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final canEdit = widget.authService.isTeacher || widget.authService.isAdmin;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: _groups.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.groups_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('暂无分组数据',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatsRow(),
                    const SizedBox(height: 16),
                    ..._groups.map((g) => _buildGroupCard(g)),
                    // leave room for FAB
                    if (canEdit) const SizedBox(height: 72),
                  ],
                ),
        ),
        if (canEdit)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'fab_group',
              onPressed: _showAddGroupDialog,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final groupCount = _stats['group_count'] ?? 0;
    final totalMembers = _stats['total_members'] ?? 0;
    final avgMembers = _stats['avg_members'] ?? 0.0;
    return Row(
      children: [
        _statCard('小组数', '$groupCount', Icons.groups, Colors.blue),
        const SizedBox(width: 10),
        _statCard('总人数', '$totalMembers', Icons.people, Colors.green),
        const SizedBox(width: 10),
        _statCard(
            '人均',
            (avgMembers as num).toStringAsFixed(1),
            Icons.person,
            Colors.orange),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final members = _parseMemberNames(group['member_names']);
    final leader = group['leader'] as String? ?? '';
    final name = group['name'] as String? ?? '';
    final project = group['project_name'] as String? ?? '未分配项目';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withValues(alpha: 0.1),
          child: Text(
              name.replaceAll('第', '').replaceAll('组', ''),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.blue)),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '组长: $leader · ${members.length}人 · $project',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('组员列表',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: members
                      .map((m) => Chip(
                            avatar: CircleAvatar(
                              backgroundColor: m == leader
                                  ? Colors.orange
                                  : Colors.grey[300],
                              radius: 12,
                              child: Text(m.substring(0, 1),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: m == leader
                                          ? Colors.white
                                          : Colors.black87)),
                            ),
                            label: Text(m,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Text('项目: $project',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 项目立项 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ProjectTab extends StatefulWidget {
  final AuthService authService;
  const _ProjectTab({required this.authService});

  @override
  State<_ProjectTab> createState() => _ProjectTabState();
}

class _ProjectTabState extends State<_ProjectTab> {
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final projects = await _dao.getProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddProjectDialog() async {
    final groups = await _dao.getGroups();
    if (!mounted) return;

    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final techCtrl = TextEditingController();
    int? selectedGroupId;
    String selectedStatus = '设计阶段';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建项目'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '项目名称'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: '项目描述'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: techCtrl,
                  decoration: const InputDecoration(
                      labelText: '技术栈',
                      hintText: '如：Flutter + Android'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: '所属小组'),
                  value: selectedGroupId,
                  items: groups
                      .map((g) => DropdownMenuItem<int>(
                            value: g['id'] as int,
                            child: Text(g['name'] as String? ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedGroupId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '状态'),
                  value: selectedStatus,
                  items: ['设计阶段', '开发中', '测试阶段', '已完成']
                      .map((s) => DropdownMenuItem(
                          value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedStatus = v);
                    }
                  },
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
                if (nameCtrl.text.trim().isEmpty) return;
                await _dao.addProject(
                  groupId: selectedGroupId,
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isNotEmpty
                      ? descCtrl.text.trim()
                      : null,
                  techStack: techCtrl.text.trim().isNotEmpty
                      ? techCtrl.text.trim()
                      : null,
                  status: selectedStatus,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final canEdit = widget.authService.isTeacher || widget.authService.isAdmin;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: _projects.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.assignment_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('暂无项目数据',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount:
                      _projects.length + (canEdit ? 1 : 0), // extra for FAB space
                  itemBuilder: (ctx, i) {
                    if (i >= _projects.length) {
                      return const SizedBox(height: 72);
                    }
                    return _buildProjectCard(context, _projects[i]);
                  },
                ),
        ),
        if (canEdit)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'fab_project',
              onPressed: _showAddProjectDialog,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  Widget _buildProjectCard(
      BuildContext context, Map<String, dynamic> project) {
    final progress = ((project['progress'] as num?) ?? 0).toDouble();
    final status = (project['status'] as String?) ?? '未知';
    final groupName = (project['group_name'] as String?) ?? '未分配';
    final techStack = (project['tech_stack'] as String?) ?? '';
    final description = (project['description'] as String?) ?? '';
    final name = (project['name'] as String?) ?? '';

    final statusColor = switch (status) {
      '测试阶段' => Colors.orange,
      '开发中' => Colors.blue,
      '设计阶段' => Colors.purple,
      '已完成' => Colors.green,
      _ => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
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
            if (description.isNotEmpty)
              Text(description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.group, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(groupName,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(width: 12),
                if (techStack.isNotEmpty) ...[
                  Icon(Icons.code, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(techStack,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(statusColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${(progress * 100).toInt()}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 贡献评分 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ContributionTab extends StatefulWidget {
  final AuthService authService;
  const _ContributionTab({required this.authService});

  @override
  State<_ContributionTab> createState() => _ContributionTabState();
}

class _ContributionTabState extends State<_ContributionTab> {
  Map<String, dynamic>? _remoteAssessment;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAssessment();
  }

  Future<void> _loadAssessment() async {
    try {
      final data = await CourseResourceService().getAssessment();
      if (mounted) {
        setState(() {
          _remoteAssessment = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 评分维度 — 优先从远程加载，否则使用默认值
    final dimensions = _buildDimensions();
    final components = _buildScoreComponents();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 数据来源指示器
        if (_remoteAssessment != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_done, size: 14, color: Colors.green[400]),
                const SizedBox(width: 4),
                Text('考核方案已从远程同步',
                    style: TextStyle(fontSize: 11, color: Colors.green[400])),
              ],
            ),
          ),
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
                    Text('综合评分体系（100分）',
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

        // 课程总评构成
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('课程总评成绩构成',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...components,
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建评分维度：优先远程数据，fallback 硬编码
  List<Map<String, dynamic>> _buildDimensions() {
    if (_remoteAssessment != null) {
      final dims = _remoteAssessment!['scoring_dimensions'];
      if (dims is List && dims.isNotEmpty) {
        const iconMap = {
          '功能完整性': Icons.check_circle,
          '技术实现深度': Icons.code,
          '跨框架整合': Icons.integration_instructions,
          '性能与质量': Icons.speed,
          '文档与协作': Icons.description,
        };
        return dims.map((d) {
          final name = d['name']?.toString() ?? '';
          return {
            'name': name,
            'max': d['max_score'] ?? d['max'] ?? 20,
            'icon': iconMap[name] ?? Icons.star,
          };
        }).toList().cast<Map<String, dynamic>>();
      }
    }
    // Fallback 默认维度
    return const [
      {'name': '功能完整性', 'max': 25, 'icon': Icons.check_circle},
      {'name': '技术实现深度', 'max': 20, 'icon': Icons.code},
      {'name': '跨框架整合', 'max': 25, 'icon': Icons.integration_instructions},
      {'name': '性能与质量', 'max': 15, 'icon': Icons.speed},
      {'name': '文档与协作', 'max': 15, 'icon': Icons.description},
    ];
  }

  /// 构建成绩构成组件：优先远程数据，fallback 硬编码
  List<Widget> _buildScoreComponents() {
    if (_remoteAssessment != null) {
      final comps = _remoteAssessment!['components'];
      if (comps is List && comps.isNotEmpty) {
        final colorMap = {
          '理论考核': Colors.blue,
          '平时成绩': Colors.blue,
          '实验考核': Colors.green,
          '综合项目': Colors.orange,
          '期末考核': Colors.purple,
        };
        return comps.map<Widget>((c) {
          final name = c['name']?.toString() ?? '';
          final weight = c['weight'] ?? c['percent'] ?? 0;
          final percent = weight is double
              ? (weight * 100).toInt()
              : (weight is int ? weight : 0);
          final details = c['details'] ?? c['sub_items'];
          final detailList = details is List
              ? details.map((d) => d.toString()).toList()
              : <String>[];
          final color = colorMap[name] ?? Colors.grey;
          return _scoreComponent(name, percent, color, detailList);
        }).toList();
      }
    }
    // Fallback 默认构成
    return [
      _scoreComponent('理论考核', 40, Colors.blue, [
        '平时成绩 15%（课堂5%+作业5%+小测5%）',
        '期末考试 25%（选择8%+简答10%+综合7%）',
      ]),
      _scoreComponent('实验考核', 35, Colors.green, [
        '实验1-6 各5%（环境/Android/Flutter/UniApp/小程序/华为）',
        '实验7 综合实战 5%',
      ]),
      _scoreComponent('综合项目', 25, Colors.orange, [
        '项目设计 8%',
        '技术实现 10%',
        '团队协作 4%',
        '项目答辩 3%',
      ]),
    ];
  }

  Widget _scoreComponent(
      String title, int percent, Color color, List<String> details) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('$title ($percent%)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: color)),
            ],
          ),
          ...details.map((d) => Padding(
                padding: const EdgeInsets.only(left: 22, top: 3),
                child: Text(d,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              )),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 答辩安排 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _DefenseTab extends StatefulWidget {
  final AuthService authService;
  const _DefenseTab({required this.authService});

  @override
  State<_DefenseTab> createState() => _DefenseTabState();
}

class _DefenseTabState extends State<_DefenseTab> {
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _defenseRecords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final records = await _dao.getDefenseRecords();
      if (mounted) {
        setState(() {
          _defenseRecords = records;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddDefenseDialog() async {
    final groups = await _dao.getGroups();
    final projects = await _dao.getProjects();
    if (!mounted) return;

    final timeCtrl = TextEditingController();
    final locationCtrl = TextEditingController(text: '实验楼A301');
    int? selectedGroupId;
    int? selectedProjectId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建答辩安排'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: '答辩小组'),
                  value: selectedGroupId,
                  items: groups
                      .map((g) => DropdownMenuItem<int>(
                            value: g['id'] as int,
                            child: Text(g['name'] as String? ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedGroupId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: '答辩项目（可选）'),
                  value: selectedProjectId,
                  items: projects
                      .map((p) => DropdownMenuItem<int>(
                            value: p['id'] as int,
                            child: Text(p['name'] as String? ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedProjectId = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: timeCtrl,
                  decoration: const InputDecoration(
                    labelText: '答辩时间',
                    hintText: '如：第16周 周一 10:00-10:15',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: '答辩地点'),
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
                if (selectedGroupId == null ||
                    timeCtrl.text.trim().isEmpty) return;
                await _dao.addDefenseRecord(
                  groupId: selectedGroupId!,
                  projectId: selectedProjectId,
                  scheduledTime: timeCtrl.text.trim(),
                  location: locationCtrl.text.trim().isNotEmpty
                      ? locationCtrl.text.trim()
                      : '实验楼A301',
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final canEdit = widget.authService.isTeacher || widget.authService.isAdmin;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 答辩流程说明（硬编码 OK）
              Card(
                color: Colors.amber.shade50,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.amber[800], size: 18),
                          const SizedBox(width: 8),
                          Text('答辩流程（15分钟/组）',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[800])),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _flowStep('1', '项目演示', '5分钟', Colors.blue),
                      _flowStep('2', '技术讲解', '5分钟', Colors.green),
                      _flowStep('3', '评委提问', '3分钟', Colors.orange),
                      _flowStep('4', '评分记录', '2分钟', Colors.purple),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('答辩安排',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_defenseRecords.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.event_busy,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text('暂无答辩安排',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  ),
                )
              else
                ..._defenseRecords
                    .map((d) => _buildDefenseCard(context, d)),
              // leave room for FAB
              if (canEdit) const SizedBox(height: 72),
            ],
          ),
        ),
        if (canEdit)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'fab_defense',
              onPressed: _showAddDefenseDialog,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  Widget _flowStep(String num, String title, String time, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          CircleAvatar(
              radius: 12,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Text(num,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(time,
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildDefenseCard(
      BuildContext context, Map<String, dynamic> defense) {
    final groupName = (defense['group_name'] as String?) ?? '未知小组';
    final projectName = (defense['project_name'] as String?) ?? '未指定项目';
    final scheduledTime = (defense['scheduled_time'] as String?) ?? '';
    final location = (defense['location'] as String?) ?? '待定';
    final status = (defense['status'] as String?) ?? '待答辩';

    final statusColor = switch (status) {
      '已完成' => Colors.green,
      '进行中' => Colors.blue,
      _ => Colors.amber,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.withValues(alpha: 0.1),
          child: const Icon(Icons.record_voice_over,
              color: Colors.indigo, size: 20),
        ),
        title: Text(groupName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(projectName,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.schedule, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(scheduledTime,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Icon(Icons.location_on, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(location,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(status,
              style: TextStyle(
                  fontSize: 11,
                  color: statusColor == Colors.amber
                      ? Colors.amber[800]
                      : statusColor,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 成绩统计 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ScoreTab extends StatefulWidget {
  final AuthService authService;
  const _ScoreTab({required this.authService});

  @override
  State<_ScoreTab> createState() => _ScoreTabState();
}

class _ScoreTabState extends State<_ScoreTab> {
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _ranking = [];
  Map<String, dynamic> _overview = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final ranking = await _dao.getScoreRanking();
      final overview = await _dao.getScoreOverview();
      if (mounted) {
        setState(() {
          _ranking = ranking;
          _overview = overview;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    final avgScore =
        (_overview['avg_score'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final maxScore = '${(_overview['max_score'] ?? 0)}';
    final passRate = (_overview['pass_rate'] as String?) ?? '0%';

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
                  _overviewItem('平均分', avgScore, Icons.analytics),
                  Container(
                      width: 1, height: 40, color: Colors.white30),
                  _overviewItem('最高分', maxScore, Icons.emoji_events),
                  Container(
                      width: 1, height: 40, color: Colors.white30),
                  _overviewItem('及格率', passRate, Icons.check_circle),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 排行榜
          const Text('成绩排行',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          if (_ranking.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.leaderboard_outlined,
                        size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text('暂无成绩数据',
                        style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              ),
            )
          else
            ..._ranking.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final s = entry.value;
              return _buildScoreCard(context, {
                'group': s['group_name'] ?? '未知小组',
                'project': s['project_name'] ?? '未指定项目',
                'score': (s['total_score'] as num?)?.toInt() ?? 0,
                'rank': rank,
                'comment': s['comment'],
                'functionality': s['score_functionality'],
                'tech_depth': s['score_tech_depth'],
                'integration': s['score_integration'],
                'quality': s['score_quality'],
                'documentation': s['score_documentation'],
              });
            }),

          const SizedBox(height: 16),

          // 成绩明细说明 — 使用排行第一名的数据（如果有）
          if (_ranking.isNotEmpty) _buildDimensionDetail(),
        ],
      ),
    );
  }

  Widget _buildDimensionDetail() {
    // Use the top-ranked entry for the dimension detail display
    final top = _ranking.first;
    final functionality =
        (top['score_functionality'] as num?)?.toInt() ?? 0;
    final techDepth = (top['score_tech_depth'] as num?)?.toInt() ?? 0;
    final integration =
        (top['score_integration'] as num?)?.toInt() ?? 0;
    final quality = (top['score_quality'] as num?)?.toInt() ?? 0;
    final documentation =
        (top['score_documentation'] as num?)?.toInt() ?? 0;

    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '评分维度明细（${top['group_name'] ?? '第一名'}）',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            _dimensionBar('功能完整性', functionality, 25, Colors.blue),
            _dimensionBar('技术实现深度', techDepth, 20, Colors.green),
            _dimensionBar('跨框架整合', integration, 25, Colors.purple),
            _dimensionBar('性能与质量', quality, 15, Colors.orange),
            _dimensionBar('文档与协作', documentation, 15, Colors.teal),
          ],
        ),
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
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11)),
      ],
    );
  }

  Widget _buildScoreCard(
      BuildContext context, Map<String, dynamic> score) {
    final rank = score['rank'] as int;
    final totalScore = score['score'] as int;
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
        title: Text(score['group'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(score['project'] as String,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        trailing: Text('$totalScore',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: totalScore >= 90
                    ? Colors.green
                    : totalScore >= 80
                        ? Colors.blue
                        : totalScore >= 60
                            ? Colors.orange
                            : Colors.red)),
      ),
    );
  }

  Widget _dimensionBar(String name, int score, int max, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
                value: max > 0 ? score / max : 0,
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
