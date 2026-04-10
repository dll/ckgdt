import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
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
    _tabController = TabController(length: 6, vsync: this);
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
              Tab(icon: Icon(Icons.record_voice_over, size: 18), text: '答辩'),
              Tab(icon: Icon(Icons.summarize, size: 18), text: '报告'),
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
              _AssessmentReportTab(authService: _authService),
              _ScoreTab(authService: _authService),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 分组管理 Tab — 支持5种维度分组：仓库/班组/项目/角色/技术栈
// ══════════════════════════════════════════════════════════════════════════════

/// 分组维度定义
enum _GroupDimension {
  repo('仓库', 'repo', Icons.folder_copy, Colors.blue),
  classGroup('班组', 'classGroup', Icons.class_, Colors.teal),
  project('项目', 'project', Icons.science, Colors.purple),
  role('角色', 'role', Icons.engineering, Colors.orange),
  techStack('技术栈', 'techStack', Icons.code, Colors.indigo);

  final String label;
  final String jsonKey;
  final IconData icon;
  final Color color;
  const _GroupDimension(this.label, this.jsonKey, this.icon, this.color);
}

class _GroupTab extends StatefulWidget {
  final AuthService authService;
  const _GroupTab({required this.authService});

  @override
  State<_GroupTab> createState() => _GroupTabState();
}

class _GroupTabState extends State<_GroupTab>
    with SingleTickerProviderStateMixin {
  late TabController _dimTabController;
  List<Map<String, dynamic>> _allStudents = [];
  Map<String, dynamic>? _myInfo; // 当前登录学生的信息
  bool _loading = true;
  String? _error;

  // 当前选中的维度
  _GroupDimension _currentDim = _GroupDimension.repo;

  // 按维度分组后的结果缓存
  final Map<_GroupDimension, List<_GroupEntry>> _groupCache = {};

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _dimTabController = TabController(
      length: _GroupDimension.values.length,
      vsync: this,
    );
    _dimTabController.addListener(() {
      if (!_dimTabController.indexIsChanging) {
        setState(() {
          _currentDim = _GroupDimension.values[_dimTabController.index];
        });
      }
    });
    _loadStudentData();
  }

  @override
  void dispose() {
    _dimTabController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentData() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final allStudents =
          decoded.map((e) => Map<String, dynamic>.from(e)).toList();

      // 学生角色：只显示自己所在仓库（同项目组）的数据
      final userId = widget.authService.getCurrentUserId();
      if (_isStudent && userId != null) {
        _myInfo = allStudents.firstWhere(
          (s) => s['userId'] == userId,
          orElse: () => <String, dynamic>{},
        );
        if (_myInfo != null && _myInfo!.isNotEmpty) {
          final myRepo = _myInfo!['repo'] as String? ?? '';
          _allStudents = allStudents.where((s) => s['repo'] == myRepo).toList();
        } else {
          _allStudents = [];
        }
      } else {
        _allStudents = allStudents;
      }

      _groupCache.clear();
      for (final dim in _GroupDimension.values) {
        _groupCache[dim] = _computeGroups(dim);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载分组数据失败: $e';
        });
      }
    }
  }

  /// 按指定维度对学生进行分组
  List<_GroupEntry> _computeGroups(_GroupDimension dim) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final s in _allStudents) {
      final key = (s[dim.jsonKey] as String?)?.trim() ?? '未分配';
      grouped.putIfAbsent(key, () => []).add(s);
    }
    // 排序：按分组名称
    final sortedKeys = grouped.keys.toList()..sort();
    return sortedKeys.map((key) {
      final members = grouped[key]!;
      return _GroupEntry(
        groupName: key,
        members: members,
        memberCount: members.length,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadStudentData();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final groups = _groupCache[_currentDim] ?? [];

    return Column(
      children: [
        // 学生：显示个人信息卡片
        if (_isStudent && _myInfo != null && _myInfo!.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_myInfo!['name']} · ${_myInfo!['repo']} · ${_myInfo!['role']}',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // 维度选择 TabBar
        Container(
          color: _currentDim.color.withValues(alpha: 0.05),
          child: TabBar(
            controller: _dimTabController,
            isScrollable: true,
            labelColor: _currentDim.color,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _currentDim.color,
            tabs: _GroupDimension.values
                .map((d) => Tab(
                      icon: Icon(d.icon, size: 16),
                      text: d.label,
                    ))
                .toList(),
          ),
        ),
        // 统计行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _buildStatsRow(groups),
        ),
        // 分组列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadStudentData,
            child: groups.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    Center(
                      child: Column(children: [
                        Icon(Icons.groups_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('暂无分组数据', style: TextStyle(color: Colors.grey)),
                      ]),
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: groups.length,
                    itemBuilder: (ctx, i) => _buildGroupCard(groups[i], i),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(List<_GroupEntry> groups) {
    final groupCount = groups.length;
    final totalMembers = groups.fold<int>(0, (sum, g) => sum + g.memberCount);
    final avg = groupCount > 0 ? totalMembers / groupCount : 0.0;
    return Row(
      children: [
        _statCard('分组数', '$groupCount', Icons.category, _currentDim.color),
        const SizedBox(width: 10),
        _statCard('总人数', '$totalMembers', Icons.people, Colors.green),
        const SizedBox(width: 10),
        _statCard('人均', avg.toStringAsFixed(1), Icons.person, Colors.orange),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(_GroupEntry group, int index) {
    final color = _currentDim.color;
    // 根据当前维度决定展示的附加信息
    final subtitle = _buildSubtitle(group);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text('${group.memberCount}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        ),
        title: Text(group.groupName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('成员列表 (${group.memberCount}人)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                // 成员表格
                _buildMemberTable(group.members),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitle(_GroupEntry group) {
    switch (_currentDim) {
      case _GroupDimension.repo:
        // 展示项目
        final projects = group.members
            .map((m) => m['project'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toSet();
        return '${group.memberCount}人 · ${projects.join(', ')}';
      case _GroupDimension.classGroup:
        // 展示班级下有哪些仓库
        final repos = group.members
            .map((m) => m['repo'] as String? ?? '')
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        return '${group.memberCount}人 · ${repos.length}个仓库';
      case _GroupDimension.project:
        // 展示仓库
        final repos = group.members
            .map((m) => m['repo'] as String? ?? '')
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        return '${group.memberCount}人 · ${repos.join(', ')}';
      case _GroupDimension.role:
        // 展示角色下的技术栈统计
        final stacks = group.members
            .map((m) => m['techStack'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toSet();
        return '${group.memberCount}人 · ${stacks.length}种技术栈';
      case _GroupDimension.techStack:
        // 展示此技术栈对应的角色
        final roles = group.members
            .map((m) => m['role'] as String? ?? '')
            .where((r) => r.isNotEmpty)
            .toSet();
        return '${group.memberCount}人 · ${roles.join(', ')}';
    }
  }

  Widget _buildMemberTable(List<Map<String, dynamic>> members) {
    // 根据维度选择显示的列
    final columns = _getColumnsForDimension();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 12,
        horizontalMargin: 8,
        headingRowHeight: 36,
        dataRowMinHeight: 60,
        dataRowMaxHeight: 200,
        columns: columns
            .map((col) => DataColumn(
                  label: Text(col.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                ))
            .toList(),
        rows: members.map((m) {
          return DataRow(
            cells: columns.map((col) {
              final val = m[col.key] as String? ?? '';
              return DataCell(
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: col.maxWidth),
                  child: Text(val, style: const TextStyle(fontSize: 11)),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  List<_ColDef> _getColumnsForDimension() {
    // 基础列：学号、姓名
    final base = [
      _ColDef('学号', 'userId', 100),
      _ColDef('姓名', 'name', 70),
    ];
    switch (_currentDim) {
      case _GroupDimension.repo:
        return [
          ...base,
          _ColDef('班组', 'classGroup', 60),
          _ColDef('角色', 'role', 140),
          _ColDef('特色功能', 'features', 350),
          _ColDef('功能详解', 'feature_detail', 400),
        ];
      case _GroupDimension.classGroup:
        return [
          ...base,
          _ColDef('仓库', 'repo', 100),
          _ColDef('项目', 'project', 160),
          _ColDef('角色', 'role', 140),
        ];
      case _GroupDimension.project:
        return [
          ...base,
          _ColDef('仓库', 'repo', 100),
          _ColDef('角色', 'role', 140),
          _ColDef('技术栈', 'techStack', 140),
        ];
      case _GroupDimension.role:
        return [
          ...base,
          _ColDef('仓库', 'repo', 100),
          _ColDef('技术栈', 'techStack', 140),
          _ColDef('特色功能', 'features', 350),
          _ColDef('功能详解', 'feature_detail', 400),
        ];
      case _GroupDimension.techStack:
        return [
          ...base,
          _ColDef('仓库', 'repo', 100),
          _ColDef('角色', 'role', 140),
          _ColDef('特色功能', 'features', 350),
          _ColDef('功能详解', 'feature_detail', 400),
        ];
    }
  }
}

/// 分组条目
class _GroupEntry {
  final String groupName;
  final List<Map<String, dynamic>> members;
  final int memberCount;
  const _GroupEntry({
    required this.groupName,
    required this.members,
    required this.memberCount,
  });
}

/// 表格列定义
class _ColDef {
  final String label;
  final String key;
  final double maxWidth;
  const _ColDef(this.label, this.key, this.maxWidth);
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
  List<Map<String, dynamic>> _jsonProjects = []; // 从JSON加载的项目数据
  Map<String, String> _projectFeatures = {}; // 功能详解数据
  bool _loading = true;

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 加载DAO项目数据（教师/管理员添加的）
      final projects = await _dao.getProjects();

      // 加载功能详解数据
      Map<String, String> projectFeatures = {};
      try {
        final featuresStr =
            await rootBundle.loadString('assets/project_features.json');
        final decoded = jsonDecode(featuresStr) as Map<String, dynamic>;
        projectFeatures = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}

      // 同时从JSON加载项目分组数据
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final allStudents =
          decoded.map((e) => Map<String, dynamic>.from(e)).toList();

      // 按仓库分组，生成项目视图
      final Map<String, List<Map<String, dynamic>>> byRepo = {};
      for (final s in allStudents) {
        final repo = s['repo'] as String? ?? '';
        byRepo.putIfAbsent(repo, () => []).add(s);
      }

      final userId = widget.authService.getCurrentUserId();
      List<Map<String, dynamic>> jsonProjects = [];

      for (final entry in byRepo.entries) {
        final members = entry.value;
        final first = members.first;
        final project = first['project'] as String? ?? '未命名项目';
        final repo = entry.key;
        final techStacks = members
            .map((m) => m['techStack'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(' / ');

        // 查找功能详解
        final featureDetail = projectFeatures[project] ?? '';

        jsonProjects.add({
          'name': project,
          'repo': repo,
          'classGroup': first['classGroup'] ?? '',
          'tech_stack': techStacks,
          'member_count': members.length,
          'members': members,
          'status': '开发中',
          'progress': 0.3,
          'feature_detail': featureDetail,
        });
      }

      // 学生：只显示自己所在项目
      if (_isStudent && userId != null) {
        final myStudent = allStudents.firstWhere(
          (s) => s['userId'] == userId,
          orElse: () => <String, dynamic>{},
        );
        if (myStudent.isNotEmpty) {
          final myRepo = myStudent['repo'] as String? ?? '';
          jsonProjects =
              jsonProjects.where((p) => p['repo'] == myRepo).toList();
        }
      }

      // 排序
      jsonProjects
          .sort((a, b) => (a['repo'] as String).compareTo(b['repo'] as String));

      if (mounted) {
        setState(() {
          _projects = projects;
          _jsonProjects = jsonProjects;
          _projectFeatures = projectFeatures;
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
                      labelText: '技术栈', hintText: '如：Flutter + Android'),
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
                  onChanged: (v) => setDialogState(() => selectedGroupId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '状态'),
                  value: selectedStatus,
                  items: ['设计阶段', '开发中', '测试阶段', '已完成']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
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
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
          child: _jsonProjects.isEmpty && _projects.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.assignment_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('暂无项目数据', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // JSON项目数据（来自分组Excel）
                    if (_jsonProjects.isNotEmpty) ...[
                      Text(
                        _isStudent ? '我的项目' : '项目 (${_jsonProjects.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._jsonProjects.map(_buildJsonProjectCard),
                      const SizedBox(height: 16),
                    ],
                    // DAO项目数据（教师手动添加的）
                    if (_projects.isNotEmpty && canEdit) ...[
                      const Text('教师添加的项目',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ..._projects.map((p) => _buildProjectCard(context, p)),
                    ],
                    if (canEdit) const SizedBox(height: 72),
                  ],
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

  Widget _buildJsonProjectCard(Map<String, dynamic> project) {
    final name = project['name'] as String? ?? '';
    final repo = project['repo'] as String? ?? '';
    final techStack = project['tech_stack'] as String? ?? '';
    final memberCount = project['member_count'] as int? ?? 0;
    final members = (project['members'] as List<Map<String, dynamic>>?) ?? [];
    final classGroup = project['classGroup'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple.withValues(alpha: 0.1),
          child: Text('$memberCount',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                  fontSize: 14)),
        ),
        title: Text(name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$repo · $classGroup',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            if (techStack.isNotEmpty)
              Text(techStack,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  overflow: TextOverflow.ellipsis),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('团队成员 ($memberCount人)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                ...members.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.blue.withValues(alpha: 0.1),
                            child: Text(
                              (m['name'] as String?)?.substring(0, 1) ?? '?',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.blue),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(m['name'] as String? ?? '',
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${m['role'] ?? ''} · ${m['techStack'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, Map<String, dynamic> project) {
    final progress = ((project['progress'] as num?) ?? 0).toDouble();
    final status = (project['status'] as String?) ?? '未知';
    final groupName = (project['group_name'] as String?) ?? '未分配';
    final techStack = (project['tech_stack'] as String?) ?? '';
    final description = (project['description'] as String?) ?? '';
    final name = (project['name'] as String?) ?? '';
    final featureDetail = (project['feature_detail'] as String?) ?? '';

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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showProjectDetailDialog(project),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
      ),
    );
  }

  void _showProjectDetailDialog(Map<String, dynamic> project) {
    final name = project['name'] as String? ?? '';
    final repo = project['repo'] as String? ?? '';
    final techStack = project['tech_stack'] as String? ?? '';
    final description = project['description'] as String? ?? '';
    final status = project['status'] as String? ?? '';
    final featureDetail = project['feature_detail'] as String? ?? '';
    final members = project['members'] as List<Map<String, dynamic>>? ?? [];
    final classGroup = project['classGroup'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 650, maxHeight: 750),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder, color: Colors.blue[700], size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 11, color: Colors.green[700])),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('基本信息',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue)),
                        const SizedBox(height: 12),
                        _buildDetailRow('仓库', repo, Icons.cloud),
                        _buildDetailRow('班组', classGroup, Icons.group),
                        if (description.isNotEmpty)
                          _buildDetailRow(
                              '项目描述', description, Icons.description),
                        if (techStack.isNotEmpty)
                          _buildDetailRow('技术栈', techStack, Icons.code),
                        const SizedBox(height: 20),
                        if (featureDetail.isNotEmpty) ...[
                          const Text('功能详解',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue)),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(featureDetail,
                                style:
                                    const TextStyle(fontSize: 12, height: 1.5)),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (members.isNotEmpty) ...[
                          Text('团队成员（共${members.length}人）',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue)),
                          const SizedBox(height: 12),
                          ...members.map((m) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: Colors.blue
                                              .withValues(alpha: 0.2),
                                          child: Text(
                                              (m['name'] as String? ?? '')
                                                      .isNotEmpty
                                                  ? (m['name'] as String)
                                                      .substring(0, 1)
                                                  : '?',
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                              m['name'] as String? ?? '',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500)),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                              m['role'] as String? ?? '',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.orange[700])),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    _buildMemberDetailRow(
                                        '技术栈', m['techStack'] as String? ?? ''),
                                    _buildMemberDetailRow(
                                        '核心职责', m['coreDuty'] as String? ?? ''),
                                    _buildMemberDetailRow(
                                        '特色功能', m['features'] as String? ?? ''),
                                    if ((m['feature_detail'] as String? ?? '')
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      const Text('个人功能详解：',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 2),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.purple
                                              .withValues(alpha: 0.05),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                            m['feature_detail'] as String? ??
                                                '',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                      ),
                                    ],
                                  ],
                                ),
                              )),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberDetailRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('$label: $value',
          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700])),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
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
        return dims
            .map((d) {
              final name = d['name']?.toString() ?? '';
              return {
                'name': name,
                'max': d['max_score'] ?? d['max'] ?? 20,
                'icon': iconMap[name] ?? Icons.star,
              };
            })
            .toList()
            .cast<Map<String, dynamic>>();
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
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('$title ($percent%)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13, color: color)),
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

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      var records = await _dao.getDefenseRecords();

      // 学生：只显示自己所在组的答辩
      if (_isStudent) {
        final userId = widget.authService.getCurrentUserId();
        if (userId != null) {
          records = records.where((d) {
            final memberIds = d['member_ids']?.toString() ?? '';
            return memberIds.contains(userId);
          }).toList();
        }
      }

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
                  onChanged: (v) => setDialogState(() => selectedGroupId = v),
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
                  onChanged: (v) => setDialogState(() => selectedProjectId = v),
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
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (selectedGroupId == null || timeCtrl.text.trim().isEmpty)
                  return;
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                ..._defenseRecords.map((d) => _buildDefenseCard(context, d)),
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
          Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildDefenseCard(BuildContext context, Map<String, dynamic> defense) {
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
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Icon(Icons.location_on, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(location,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
// 报告 Tab — 报告模板中心 + 学生PDF报告提交
// ══════════════════════════════════════════════════════════════════════════════

class _AssessmentReportTab extends StatefulWidget {
  final AuthService authService;
  const _AssessmentReportTab({required this.authService});

  @override
  State<_AssessmentReportTab> createState() => _AssessmentReportTabState();
}

class _AssessmentReportTabState extends State<_AssessmentReportTab> {
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _submissions = [];
  bool _loading = true;
  String? _currentUserId;

  // 考核大作业（合并4种报告）
  static const _reportTypes = ['考核大作业'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _currentUserId = widget.authService.getCurrentUserId();
      await _loadSubmissions();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSubmissions() async {
    try {
      // 学生只看自己的；教师/管理员看所有人的
      final isStudent =
          !widget.authService.isTeacher && !widget.authService.isAdmin;
      final queryUserId = isStudent ? _currentUserId : null;
      final subs = await _dao.getSubmittedReports(userId: queryUserId);
      if (mounted) setState(() => _submissions = subs);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 报告模板中心 ───
          _sectionHeader(primary, Icons.file_copy_outlined, '报告模板中心',
              '选择模板类型，生成考核大作业 Markdown 格式报告框架'),
          const SizedBox(height: 10),
          _buildTemplateCards(primary),

          const SizedBox(height: 24),

          // ─── 提交报告 ───
          _sectionHeader(primary, Icons.upload_file, '提交考核大作业',
              '仅支持 PDF 格式，请上传包含答辩/个人/小组/项目四部分的完整报告'),
          const SizedBox(height: 10),
          _buildUploadArea(primary),

          const SizedBox(height: 24),

          // ─── 已提交列表 ───
          if (_submissions.isNotEmpty) ...[
            _sectionHeader(primary, Icons.checklist, '已提交报告',
                '共 ${_submissions.length} 份'),
            const SizedBox(height: 10),
            _buildSubmissionList(primary),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(
      Color primary, IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: primary)),
                Text(sub,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════ 模板卡片区 ═══════════

  Widget _buildTemplateCards(Color primary) {
    final templates = [
      {
        'title': '通用模板',
        'subtitle': '考核大作业 · 简洁版',
        'icon': Icons.article_outlined,
        'color': Colors.blue,
        'desc': '包含答辩/个人/小组/项目四部分的完整考核大作业框架，适用于所有技术栈和项目选题。',
        'type': 'generic',
      },
      {
        'title': '技术栈定制模板',
        'subtitle': '考核大作业 · 定制版',
        'icon': Icons.build_outlined,
        'color': Colors.orange,
        'desc': '根据你负责的技术栈（Flutter/Android/RN/鸿蒙/小程序/Uniapp）生成针对性的考核大作业模板。',
        'type': 'techstack',
      },
      {
        'title': '详细参考模板',
        'subtitle': '考核大作业 · 完整版',
        'icon': Icons.menu_book_outlined,
        'color': Colors.green,
        'desc': '包含详细的评分标准、格式要求和参考内容示例的完整考核大作业模板，适合首次撰写。',
        'type': 'detailed',
      },
    ];

    return Column(
      children: templates.map((t) {
        final color = t['color'] as Color;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                _onTemplateTap(t['type'] as String, t['title'] as String),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(t['icon'] as IconData, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(t['title'] as String,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(t['subtitle'] as String,
                                style: TextStyle(fontSize: 9, color: color)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(t['desc'] as String,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _onTemplateTap(String type, String title) {
    if (type == 'techstack') {
      _showTechStackPicker();
    } else {
      final md = type == 'generic'
          ? _generateGenericTemplate()
          : _generateDetailedTemplate();
      _showTemplateDialog(title, md);
    }
  }

  void _showTechStackPicker() {
    final stacks = [
      {'name': 'Flutter (Dart)', 'icon': '🎯'},
      {'name': 'Android (Kotlin)', 'icon': '🤖'},
      {'name': 'React Native (JS/TS)', 'icon': '⚛️'},
      {'name': 'HarmonyOS (ArkTS)', 'icon': '🌐'},
      {'name': '微信小程序', 'icon': '💬'},
      {'name': 'Uniapp (Vue.js)', 'icon': '🔧'},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择你负责的技术栈',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('将根据技术栈生成定制化报告模板',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            ...stacks.map((s) => ListTile(
                  leading:
                      Text(s['icon']!, style: const TextStyle(fontSize: 24)),
                  title: Text(s['name']!),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.pop(ctx);
                    final md = _generateTechStackTemplate(s['name']!);
                    _showTemplateDialog('技术栈定制模板 · ${s['name']}', md);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showTemplateDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.description, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 450,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                content,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('模板已复制到剪贴板'), backgroundColor: Colors.green),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制模板'),
          ),
        ],
      ),
    );
  }

  // ═══════════ 上传区域 ═══════════

  Widget _buildUploadArea(Color primary) {
    final type = _reportTypes.first; // '考核大作业'
    final submitted = _submissions
        .any((s) => s['report_type'] == type && s['status'] != '已删除');
    final color = submitted ? Colors.green : primary;
    final icon = submitted ? Icons.check_circle : Icons.upload_file;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _pickAndUploadPdf(type),
        icon: Icon(icon, size: 20, color: color),
        label: Text(
          submitted ? '$type 已提交 ✓' : '上传$type（PDF）',
          style: TextStyle(fontSize: 13, color: color),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPdf(String reportType) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        dialogTitle: '选择 $reportType PDF 文件',
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('无法获取文件路径'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // 检查文件扩展名
      if (!file.name.toLowerCase().endsWith('.pdf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('仅支持 PDF 格式文件'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final userId = _currentUserId ?? 'unknown';
      final userName = widget.authService.currentUser?.realName ?? userId;

      await _dao.submitReport(
        userId: userId,
        studentName: userName,
        reportType: reportType,
        fileName: file.name,
        filePath: file.path!,
      );

      await _loadSubmissions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$reportType 提交成功：${file.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ═══════════ 已提交列表 ═══════════

  Widget _buildSubmissionList(Color primary) {
    return Column(
      children: _submissions.map((s) {
        final type = s['report_type'] as String? ?? '';
        final fileName = s['file_name'] as String? ?? '';
        final status = s['status'] as String? ?? '已提交';
        final score = s['score'] as int?;
        final submitTime = s['submit_time'] as String? ?? '';
        final feedback = s['feedback'] as String?;

        final statusColor = status == '已批阅'
            ? Colors.green
            : status == '已提交'
                ? Colors.blue
                : Colors.grey;
        final typeIcon = type == '考核大作业'
            ? Icons.description
            : type == '答辩报告'
                ? Icons.record_voice_over
                : type == '个人报告'
                    ? Icons.person
                    : type == '小组报告'
                        ? Icons.groups
                        : Icons.folder_open;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: statusColor.withValues(alpha: 0.1),
              radius: 18,
              child: Icon(typeIcon, color: statusColor, size: 18),
            ),
            title: Text(type,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '$fileName · ${submitTime.length >= 10 ? submitTime.substring(0, 10) : submitTime}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status,
                      style: TextStyle(fontSize: 10, color: statusColor)),
                ),
                if (score != null) ...[
                  const SizedBox(width: 6),
                  Text('$score分',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: score >= 60 ? Colors.green : Colors.red)),
                ],
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.picture_as_pdf,
                            size: 14, color: Colors.red),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(fileName,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    if (feedback != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment,
                                size: 14, color: Colors.amber),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('教师反馈：$feedback',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openPdf(s['file_path'] as String?),
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label:
                              const Text('打开', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 4),
                        TextButton.icon(
                          onPressed: () => _confirmDelete(s['id'] as int, type),
                          icon: const Icon(Icons.delete_outline,
                              size: 14, color: Colors.red),
                          label: const Text('删除',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.red)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _openPdf(String? path) async {
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件路径无效')),
      );
      return;
    }
    try {
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmDelete(int id, String type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除已提交的「$type」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _dao.deleteSubmittedReport(id);
              await _loadSubmissions();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('已删除'), backgroundColor: Colors.green),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 模板生成
  // ═══════════════════════════════════════════════════════════════════════════

  /// 通用模板 — 简洁适用所有同学和项目
  String _generateGenericTemplate() {
    return '''# 《移动应用开发》课程考核报告

> **学号**：___________　**姓名**：___________　**班级**：计科22
> **小组**：第___组　**项目名称**：___________
> **负责技术栈**：___________　**提交日期**：___________

---

## 一、答辩报告（40%）

### 1.1 核心技术实现
- 技术栈名称与版本：
- 核心功能模块描述：
- 关键代码片段说明：

### 1.2 架构设计
- 整体架构说明（建议附架构图）：
- 模块划分与职责：
- 跨平台数据交互方案：

### 1.3 创新点
- 技术创新（至少1项）：
- 功能创新：
- 应用价值分析：

### 1.4 答辩问答记录
- 问题1：
  - 回答：
- 问题2：
  - 回答：

---

## 二、个人报告（20%）

### 2.1 技术图表（必须包含3张UML图）

#### 类图
> 【在此插入类图或描述主要类及其关系】

#### 时序图
> 【在此插入时序图或描述关键交互流程】

#### 架构图
> 【在此插入架构图或描述系统分层】

### 2.2 四阶段工作记录

| 阶段 | 时间 | 主要工作 | 产出 |
|------|------|----------|------|
| 项目启动 | 第1-3天 | | |
| 核心开发 | 第4-7天 | | |
| 系统整合 | 第8-12天 | | |
| 测试交付 | 第13-15天 | | |

### 2.3 个人总结与自我评价
- 技术收获：
- 遇到的困难及解决方案：
- 自我评分（满分100）：___分

---

## 三、小组报告（20%）

### 3.1 团队概况

| 成员 | 学号 | 负责技术栈 | 主要贡献 | 贡献占比 |
|------|------|-----------|---------|---------|
| | | | | % |
| | | | | % |
| | | | | % |
| | | | | % |
| | | | | % |
| | | | | % |

### 3.2 四阶段团队协作记录
- **第一阶段**（项目启动）：
- **第二阶段**（核心开发）：
- **第三阶段**（系统整合）：
- **第四阶段**（测试交付）：

### 3.3 团队总结
- 协作亮点：
- 改进建议：

> **全体成员签名确认**：__________ / __________ / __________ / __________ / __________ / __________

---

## 四、项目报告（20%）

### 4.1 项目概述
- 项目名称：
- 项目目标：
- 技术选型概要：

### 4.2 技术架构
- 前端技术栈对比：
- 后端/数据方案（SQLite + Firebase）：
- 跨平台数据同步方案：

### 4.3 功能实现
- 核心功能列表：
- 各平台实现情况：

### 4.4 测试与部署
- 测试方法：
- 测试结果：
- 部署说明：

### 4.5 项目总结
- 达成的课程目标：
- 不足与改进方向：

---

*报告模板由知识图谱教学系统生成*
''';
  }

  /// 技术栈半定制模板
  String _generateTechStackTemplate(String techStack) {
    // 根据技术栈生成定制内容
    String envSetup = '';
    String coreImpl = '';
    String testDeploy = '';
    String classDigram = '';

    if (techStack.contains('Flutter')) {
      envSetup =
          '- Flutter SDK 版本：\n- Dart 版本：\n- 开发IDE：Android Studio / VS Code\n- 模拟器/真机型号：';
      coreImpl = '''- Widget 树结构设计：
- 状态管理方案（Provider/Riverpod/Bloc）：
- 路由管理（GoRouter/Navigator 2.0）：
- 网络请求封装（http/dio）：
- 本地存储（sqflite/shared_preferences）：
- Firebase 集成（auth/firestore/storage）：''';
      testDeploy =
          '- flutter test 单元测试：\n- flutter build apk 打包：\n- flutter build ios 打包（如适用）：';
      classDigram = '> 包含 Widget 类、State 类、Service 类、Model 类及其依赖关系';
    } else if (techStack.contains('Android')) {
      envSetup =
          '- Android Studio 版本：\n- Kotlin 版本：\n- compileSdk / minSdk / targetSdk：\n- 模拟器/真机型号：';
      coreImpl = '''- Activity/Fragment 架构设计：
- ViewModel + LiveData/StateFlow 数据绑定：
- Retrofit + OkHttp 网络请求：
- Room 数据库本地存储：
- Firebase SDK 集成：
- Material Design 3 组件使用：''';
      testDeploy =
          '- JUnit 单元测试：\n- Espresso UI 测试：\n- ./gradlew assembleRelease 打包：';
      classDigram = '> 包含 Activity、ViewModel、Repository、Dao、Entity 及其关系';
    } else if (techStack.contains('React Native')) {
      envSetup =
          '- Node.js 版本：\n- React Native 版本：\n- 开发IDE：VS Code\n- Metro Bundler 配置：';
      coreImpl = '''- 组件架构（函数式组件 + Hooks）：
- 状态管理（Redux/Context/Zustand）：
- React Navigation 路由：
- Axios/Fetch 网络请求：
- AsyncStorage 本地存储：
- Firebase RN SDK 集成：''';
      testDeploy =
          '- Jest 单元测试：\n- npx react-native run-android 构建：\n- npx react-native run-ios 构建（如适用）：';
      classDigram = '> 包含 Screen 组件、Hook、Service、Store 及数据流关系';
    } else if (techStack.contains('HarmonyOS')) {
      envSetup =
          '- DevEco Studio 版本：\n- ArkTS 版本：\n- 目标设备类型（手机/平板/穿戴）：\n- 模拟器/真机型号：';
      coreImpl = '''- ArkUI 声明式布局设计：
- 分布式数据管理：
- 多端自适应布局（手机/平板）：
- 网络请求（@ohos.net.http）：
- 首选项/关系型数据库存储：
- 设备传感器调用：''';
      testDeploy = '- 单元测试框架使用：\n- HAP 打包：\n- 模拟器多端验证：';
      classDigram = '> 包含 Ability、Page、Component、Service 及分布式架构';
    } else if (techStack.contains('微信')) {
      envSetup = '- 微信开发者工具版本：\n- 基础库版本：\n- AppID（测试号/正式）：';
      coreImpl = '''- 页面结构（WXML + WXSS + JS）：
- 数据绑定与事件处理：
- wx.request 网络请求封装：
- 本地缓存（wx.setStorageSync）：
- 云开发/Firebase Web SDK：
- 小程序分包策略：''';
      testDeploy = '- 真机预览与调试：\n- 体验版发布：\n- 审核提交（如适用）：';
      classDigram = '> 包含 App、Page、Component、Service、API 调用关系';
    } else if (techStack.contains('Uniapp')) {
      envSetup = '- HBuilderX 版本：\n- Vue.js 版本（2/3）：\n- uni-app 编译目标：';
      coreImpl = '''- Vue 组件设计（SFC 单文件组件）：
- Vuex/Pinia 状态管理：
- uni.request 网络请求：
- uni 存储 API：
- 条件编译（#ifdef）多端适配：
- Firebase Web SDK 集成：''';
      testDeploy = '- H5 调试：\n- 打包为 Android APK：\n- 打包为微信小程序：';
      classDigram = '> 包含 Page、Component、Store、Service、API 调用关系';
    }

    return '''# 《移动应用开发》课程考核报告 · $techStack

> **学号**：___________　**姓名**：___________　**班级**：计科22
> **小组**：第___组　**项目名称**：___________
> **技术栈**：$techStack　**提交日期**：___________

---

## 一、答辩报告（40%）

### 1.1 开发环境
$envSetup

### 1.2 核心技术实现
$coreImpl

### 1.3 架构设计
- 整体架构图（分层架构）：
  > 【在此插入 $techStack 项目架构图】
- 与其他技术栈的 API 接口设计：
- 跨端数据同步方案（SQLite + Firebase）：

### 1.4 创新点
- 技术创新点（结合 $techStack 特性）：
- AI 工具（TRAE）辅助开发记录：
  - 使用场景1：
  - 使用场景2：

### 1.5 答辩问答
- 必答题1（核心技术深度）：
  - 回答：
- 必答题2（架构设计合理性）：
  - 回答：
- 必答题3（创新点分析）：
  - 回答：
- 抽答题：
  - 回答：

### 1.6 演示材料清单
- [ ] 演示视频（≤10分钟）
- [ ] 现场录屏
- [ ] 演讲文稿
- [ ] 源代码 ZIP
- [ ] 部署文档

---

## 二、个人报告（20%）

### 2.1 技术图表（必须3张，缺少即0分）

#### 类图
$classDigram
```
【在此绘制或粘贴类图】
```

#### 时序图
> 描述 $techStack 中一个核心交互流程（如登录→获取数据→渲染列表）
```
【在此绘制或粘贴时序图】
```

#### 架构图
> $techStack 的分层架构（UI层→业务层→数据层→网络层）
```
【在此绘制或粘贴架构图】
```

### 2.2 四阶段工作记录

#### 第一阶段：项目启动（第1-3天）
- 完成的任务：
- 工时统计：___小时
- 关键产出：

#### 第二阶段：核心开发（第4-7天）
- 完成的功能模块：
- 工时统计：___小时
- 遇到的问题及解决方案：

#### 第三阶段：系统整合（第8-12天）
- API 对接情况：
- 工时统计：___小时
- 跨端兼容性处理：

#### 第四阶段：测试交付（第13-15天）
- 测试方法与结果：
$testDeploy
- 工时统计：___小时

### 2.3 个人总结
- $techStack 技术收获：
- 对比其他技术栈的心得：
- 自我评分（满分100）：___分

---

## 三、小组报告（20%）

### 3.1 团队成员与技术分工

| 成员 | 学号 | 技术栈 | 核心职责 | 贡献占比 |
|------|------|--------|----------|---------|
| | | $techStack | （你的职责） | % |
| | | | | % |
| | | | | % |
| | | | | % |
| | | | | % |
| | | | | % |

### 3.2 团队协作与集成
- Git 协作流程：
- 跨技术栈接口定义（API 规范）：
- 集成测试与联调记录：

### 3.3 四阶段团队进展
| 阶段 | 团队目标 | 完成情况 | 问题与解决 |
|------|----------|---------|-----------|
| 启动 | | | |
| 开发 | | | |
| 整合 | | | |
| 交付 | | | |

### 3.4 团队总结
- 协作亮点：
- 改进建议：

> **全体成员签名确认**

---

## 四、项目报告（20%）

### 4.1 项目概述
- 项目选题：
- 需求分析：
- 技术选型对比表：

| 技术栈 | 负责人 | 语言 | 优势 | 劣势 |
|--------|--------|------|------|------|
| $techStack | （你） | | | |
| | | | | |
| SQLite | 全员共用 | SQL | 离线存储 | 单机 |
| Firebase | 全员共用 | - | 云同步 | 需网络 |

### 4.2 核心功能与 $techStack 实现
- 用户注册/登录：
- 需求发布与匹配：
- 需求完成与反馈：
- 个人中心：

### 4.3 部署说明
- $techStack 构建命令：
- 安装包位置与大小：
- 运行环境要求：

### 4.4 项目总结
- 对应课程目标达成情况：
- 不足与后续改进方向：

---

*报告模板由知识图谱教学系统生成 · $techStack 专版*
''';
  }

  /// 详细参考模板 — 完整指导
  String _generateDetailedTemplate() {
    return '''# 《移动应用开发》课程考核报告（详细参考版）

> ⚠️ **格式要求**：A4纸 · 正文宋体/Times New Roman 小四 · 标题黑体 · 行距1.5倍
> 📋 **提交要求**：4份报告必须全部提交，缺任何一份则期末项目得分为0
> 📄 **最终提交**：转为 PDF 格式上传

---

> **学号**：___________　**姓名**：___________　**班级**：计科22
> **小组**：第___组（共6人）　**项目选题**：[ ] 智慧校园 [ ] 健康运动 [ ] 智能家居 [ ] 新闻资讯
> **负责技术栈**：___________　**提交日期**：___________

---

# 第一部分：答辩报告（占期末50分中的20分 = 40%）

> 📝 **评分维度**：核心技术实现(20分) + 架构设计(30分) + 创新点(40分) + 答辩问答(10分)
> ⏱️ **答辩流程**：项目演示5分钟 → 技术讲解5分钟 → 评委提问3分钟 → 评分记录2分钟

## 1.1 核心技术实现（20分）

> 💡 **评分标准**
> - A(18-20)：技术实现完整，代码质量高，展示清晰
> - B(14-17)：基本完整，有少量不足
> - C(10-13)：部分实现，存在明显问题
> - D/E(<10)：实现不完整或无法运行

### 1.1.1 开发环境配置
- 技术栈名称与版本号：
- SDK/框架版本：
- 开发工具：
- 运行环境（模拟器/真机型号）：

### 1.1.2 核心功能模块
> 请逐个列出你负责实现的功能模块，每个模块包含：功能描述、实现思路、关键代码片段

**模块1：用户认证**
- 功能描述：
- 实现方式：
- 关键代码（不超过20行）：
```
// 在此粘贴核心代码
```

**模块2：业务数据管理**
- 功能描述：
- 实现方式：
- 关键代码：
```
// 在此粘贴核心代码
```

**模块3：___________**
- 功能描述：
- 实现方式：
- 关键代码：

### 1.1.3 运行效果截图
> 至少提供3-5张关键页面截图，标注页面名称

| 页面名称 | 截图 | 功能说明 |
|----------|------|---------|
| 登录页 | 【截图】 | |
| 主页/列表页 | 【截图】 | |
| 详情页 | 【截图】 | |
| 个人中心 | 【截图】 | |

## 1.2 架构设计（30分）

> 💡 **评分标准**
> - A(27-30)：架构合理，模块清晰，跨平台设计完善
> - B(21-26)：架构基本合理
> - C(15-20)：架构较为简单
> - D/E(<15)：缺乏架构设计

### 1.2.1 系统整体架构图
> 【在此插入分层架构图：表现层 → 业务逻辑层 → 数据访问层 → 数据层】
> 建议使用 PlantUML 绘制或手绘后拍照

### 1.2.2 模块划分
| 模块名 | 职责 | 对外接口 | 依赖 |
|--------|------|---------|------|
| | | | |

### 1.2.3 数据库设计
| 表名 | 字段 | 类型 | 说明 |
|------|------|------|------|
| users | id, name, password | | 用户表 |
| | | | |

### 1.2.4 跨平台接口设计
- 统一 API 规范（与其他技术栈成员约定的接口）：
- 数据同步方案（SQLite 本地 + Firebase 云端）：
- 数据格式约定（JSON 结构示例）：

## 1.3 创新点（40分）

> 💡 **评分标准**
> - A(36-40)：原创性强，技术难度高，有实际应用价值
> - B(28-35)：有一定创新
> - C(20-27)：创新有限
> - D/E(<20)：缺乏创新

### 1.3.1 技术创新（至少1项）
- 创新点描述：
- 技术实现难度分析：
- 效果对比（有/无此创新的差异）：

### 1.3.2 功能创新
- 创新功能描述：
- 用户价值分析：

### 1.3.3 AI 辅助开发记录
> 记录使用 TRAE 等 AI 工具的场景和效果
| AI 使用场景 | 输入提示 | AI 输出 | 人工修改 | 效率提升 |
|-------------|---------|---------|---------|---------|
| | | | | |

## 1.4 答辩问答记录（10分）

### 必答题1：核心技术深度（20分基准）
- **问题**：
- **回答**：

### 必答题2：架构设计合理性（30分基准）
- **问题**：
- **回答**：

### 必答题3：创新点分析（40分基准）
- **问题**：
- **回答**：

### 抽答题（10分基准）
- **问题**：
- **回答**：

### 演示材料提交清单
- [ ] 演示视频（MP4，≤10分钟）
- [ ] 现场答辩录屏
- [ ] 演讲文稿/PPT
- [ ] 源代码完整压缩包（ZIP）
- [ ] 部署/安装文档

---

# 第二部分：个人报告（占期末50分中的10分 = 20%）

> ⚠️ **强制要求**：必须包含3张 UML 技术图表（类图 + 时序图 + 架构图），不合规 = 0分

## 2.1 技术图表（30分）

> 💡 **评分标准**
> - A(27-30)：图表完整规范，准确反映系统设计
> - B(21-26)：基本完整
> - C(15-20)：部分缺失
> - D/E(<15)或缺图：0分

### 2.1.1 类图（Class Diagram）
> 展示你负责模块的核心类、属性、方法及类间关系
> 建议工具：PlantUML / draw.io / StarUML

```plantuml
@startuml
' 在此编写类图代码，示例：
class UserService {
  - db: Database
  + login(id, pwd): Future<User?>
  + register(user): Future<bool>
}

class UserModel {
  + userId: String
  + name: String
  + role: String
  + toMap(): Map
}

UserService --> UserModel
@enduml
```

### 2.1.2 时序图（Sequence Diagram）
> 展示一个核心业务流程的对象交互顺序

```plantuml
@startuml
' 在此编写时序图代码，示例：
actor 用户
participant "登录页" as UI
participant "AuthService" as Auth
participant "数据库" as DB

用户 -> UI: 输入学号密码
UI -> Auth: login(id, pwd)
Auth -> DB: query("SELECT * FROM users")
DB --> Auth: 用户记录
Auth --> UI: 登录结果
UI --> 用户: 跳转首页/提示错误
@enduml
```

### 2.1.3 架构图（Architecture Diagram）
> 展示系统整体分层或模块划分

```
【在此绘制或粘贴架构图】
建议结构：
┌─────────────────────────┐
│     表现层 (UI/View)      │
├─────────────────────────┤
│   业务逻辑层 (Service)    │
├─────────────────────────┤
│   数据访问层 (DAO/Repo)   │
├─────────────────────────┤
│   数据层 (SQLite/Firebase)│
└─────────────────────────┘
```

## 2.2 四阶段工作记录（25分）

### 第一阶段：项目启动（第1-3天）
- **个人任务**：
- **完成情况**：
- **工时**：___小时
- **产出清单**：
  - [ ] 需求文档
  - [ ] 环境搭建截图
  - [ ] Hello World 运行截图

### 第二阶段：核心开发（第4-7天）
- **个人任务**：
- **完成情况**：
- **工时**：___小时
- **遇到的问题**：
- **解决方案**：
- **Git 提交记录**（至少列出3条）：

| 日期 | Commit 摘要 | 改动文件数 |
|------|------------|-----------|
| | | |

### 第三阶段：系统整合（第8-12天）
- **个人任务**：
- **API 对接记录**：
- **工时**：___小时
- **跨端兼容性处理**：

### 第四阶段：测试交付（第13-15天）
- **测试方法**：
- **测试结果**：
- **工时**：___小时
- **总工时统计**：___小时

## 2.3 技术深度与质量（25分）
- 代码规范遵循情况：
- 设计模式使用：
- 性能优化措施：
- 安全考虑：

## 2.4 个人总结与自我评价（20分）
- 对移动应用开发技术体系的理解（课程目标1）：
- 跨平台开发能力提升（课程目标2）：
- 技术方案评估与选型能力（课程目标3）：
- 工程实践能力（课程目标4）：
- 自我评分：___分（满分100）
- 对课程的建议：

---

# 第三部分：小组报告（占期末50分中的10分 = 20%）

> ⚠️ **每人必须独立整理**，不得复制粘贴他人内容，雷同即全额扣分

## 3.1 团队概况（30分）

### 成员信息与技术分工表

| 序号 | 姓名 | 学号 | 技术栈 | 核心职责 | 代码量(行) | 贡献占比 |
|------|------|------|--------|----------|-----------|---------|
| 1 | | | | | | % |
| 2 | | | | | | % |
| 3 | | | | | | % |
| 4 | | | | | | % |
| 5 | | | | | | % |
| 6 | | | | | | % |
| **合计** | | | **6种技术栈** | | | **100%** |

## 3.2 贡献准确性（30分）
> ⚠️ 贡献数据必须与个人报告一致，不一致将被扣分

- Git 仓库地址：
- 各成员 Commit 统计：
- 各成员代码行数统计：

## 3.3 四阶段团队协作（25分）

| 阶段 | 时间 | 团队目标 | 完成人员 | 完成情况 | 问题记录 |
|------|------|---------|---------|---------|---------|
| 启动 | 第1-3天 | | | | |
| 开发 | 第4-7天 | | | | |
| 整合 | 第8-12天 | | | | |
| 交付 | 第13-15天 | | | | |

## 3.4 团队总结（15分）
- 协作亮点：
- 使用的协作工具（Git/微信/腾讯文档等）：
- 团队反思与改进建议：

> **全体成员签名确认**（电子签名或手写）：
> 1. __________ 2. __________ 3. __________
> 4. __________ 5. __________ 6. __________

---

# 第四部分：项目报告（占期末50分中的10分 = 20%）

> ⚠️ **每人必须独立编写**，雷同扣分

## 4.1 技术文档（30分）

### 4.1.1 项目基本信息
- 项目名称：
- 项目简介（100字以内）：
- Git 仓库地址：

### 4.1.2 技术栈全览

| 技术栈 | 语言 | 负责人 | 版本 | 用途 |
|--------|------|--------|------|------|
| Android | Kotlin | | | 原生开发 |
| Flutter | Dart | | | 跨平台 |
| React Native | JS/TS | | | 跨平台 |
| HarmonyOS | ArkTS | | | 多端适配 |
| 微信小程序 | WXML+JS | | | 小程序 |
| Uniapp | Vue.js | | | 多端编译 |
| SQLite | SQL | 全员 | | 本地存储（**必选**） |
| Firebase | - | 全员 | | 云同步（**必选**） |

### 4.1.3 系统架构文档
> 包含整体架构图、模块关系图、数据流图

### 4.1.4 API 接口文档
| 接口 | 方法 | 路径 | 参数 | 返回 |
|------|------|------|------|------|
| | | | | |

## 4.2 功能与部署（25分）
- 核心功能清单及完成度：
- 各技术栈运行截图汇总：
- 安装/部署步骤：
- 源代码目录结构说明：

## 4.3 创新与可扩展性（25分）
- 项目创新点总结：
- 技术难点攻克记录：
- 后续扩展方向：

## 4.4 成绩汇总与课程目标对标（20分）

| 课程目标 | 权重 | 对标内容 | 自评达成度 |
|----------|------|---------|-----------|
| 目标1：技术体系认知 | 15% | | % |
| 目标2：跨平台开发能力 | 25% | | % |
| 目标3：技术方案评估 | 30% | | % |
| 目标4：工程实践能力 | 30% | | % |

---

> 📎 **附录建议**：Gitee 仓库结构截图、CI/CD 配置、性能测试报告等

---

*详细参考模板由知识图谱教学系统生成 · 请根据实际情况填写并删除提示文字*
''';
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
  Map<String, dynamic>? _myScore; // 学生个人成绩
  bool _loading = true;

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final ranking = await _dao.getScoreRanking();
      final overview = await _dao.getScoreOverview();

      // 学生：查找自己的成绩
      if (_isStudent) {
        final userId = widget.authService.getCurrentUserId();
        if (userId != null) {
          for (final r in ranking) {
            // 通过成员信息匹配
            final memberIds = r['member_ids'];
            if (memberIds != null && memberIds.toString().contains(userId)) {
              _myScore = r;
              break;
            }
          }
        }
      }

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
          // 学生模式：显示个人成绩摘要
          if (_isStudent) ...[
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
                child: Column(
                  children: [
                    const Text('我的考核成绩',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_myScore != null)
                      Text(
                        '${(_myScore!['total_score'] as num?)?.toInt() ?? 0}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold),
                      )
                    else
                      const Text('暂无成绩',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 18)),
                    if (_myScore != null)
                      Text(
                        '${_myScore!['group_name'] ?? ''} · ${_myScore!['project_name'] ?? ''}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            if (_myScore != null) ...[
              const SizedBox(height: 16),
              _buildDimensionDetailForScore(_myScore!),
            ],
          ],

          // 教师/管理员模式：显示统计概览和排行榜
          if (!_isStudent) ...[
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
                    Container(width: 1, height: 40, color: Colors.white30),
                    _overviewItem('最高分', maxScore, Icons.emoji_events),
                    Container(width: 1, height: 40, color: Colors.white30),
                    _overviewItem('及格率', passRate, Icons.check_circle),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 排行榜
            const Text('成绩排行',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      Text('暂无成绩数据', style: TextStyle(color: Colors.grey[500])),
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

            // 成绩明细说明
            if (_ranking.isNotEmpty) _buildDimensionDetail(),
          ],
        ],
      ),
    );
  }

  Widget _buildDimensionDetail() {
    // Use the top-ranked entry for the dimension detail display
    final top = _ranking.first;
    final functionality = (top['score_functionality'] as num?)?.toInt() ?? 0;
    final techDepth = (top['score_tech_depth'] as num?)?.toInt() ?? 0;
    final integration = (top['score_integration'] as num?)?.toInt() ?? 0;
    final quality = (top['score_quality'] as num?)?.toInt() ?? 0;
    final documentation = (top['score_documentation'] as num?)?.toInt() ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('评分维度明细（${top['group_name'] ?? '第一名'}）',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _buildScoreCard(BuildContext context, Map<String, dynamic> score) {
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor.withValues(alpha: 0.15),
          child: Text('#$rank',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: rankColor, fontSize: 14)),
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
                  fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 学生个人成绩维度详情
  Widget _buildDimensionDetailForScore(Map<String, dynamic> score) {
    final functionality = (score['score_functionality'] as num?)?.toInt() ?? 0;
    final techDepth = (score['score_tech_depth'] as num?)?.toInt() ?? 0;
    final integration = (score['score_integration'] as num?)?.toInt() ?? 0;
    final quality = (score['score_quality'] as num?)?.toInt() ?? 0;
    final documentation = (score['score_documentation'] as num?)?.toInt() ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('评分维度明细',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
}
