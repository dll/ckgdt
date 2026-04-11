import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/constants/app_theme.dart';
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

  bool get _isStudent => !_authService.isTeacher && !_authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _initDemoData();
  }

  Future<void> _initDemoData() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final students =
          decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      await _assessmentDao.syncGroupsFromStudentData(students);
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
    final gradient = AppGradientTheme.of(context);

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: gradient.linearGradient,
            boxShadow: [
              BoxShadow(
                color: gradient.gradientStart.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.assessment,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '课程考核工作台',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isStudent
                                ? '聚焦项目、贡献、报告与答辩，完成课程考核闭环。'
                                : '统一管理分组、评分、答辩、报告与成绩，形成完整考核流程。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.88),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildHeaderRoleBadge(),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _AssessmentTopStat(
                        label: '分组', value: '5类', icon: Icons.groups),
                    _AssessmentTopStat(
                        label: '项目', value: '多视图', icon: Icons.assignment),
                    _AssessmentTopStat(
                        label: '贡献', value: '3维度', icon: Icons.star_rate),
                    _AssessmentTopStat(
                        label: '答辩', value: '流程化', icon: Icons.record_voice_over),
                    _AssessmentTopStat(
                        label: '报告', value: '4份', icon: Icons.summarize),
                    _AssessmentTopStat(
                        label: '成绩', value: '排行', icon: Icons.leaderboard),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: primary.withValues(alpha: 0.12)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            dividerColor: Colors.transparent,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
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

  Widget _buildHeaderRoleBadge() {
    final label = _authService.isAdmin
        ? '管理员视角'
        : _authService.isTeacher
            ? '教师视角'
            : '学生视角';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 顶部统计小组件
// ══════════════════════════════════════════════════════════════════════════════

class _AssessmentTopStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _AssessmentTopStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Text(
            '$label $value',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
  techStack('技术栈', 'techStack', Icons.code, Colors.indigo),
  features('特色功能', 'features', Icons.auto_awesome, Colors.deepOrange);

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

    if (dim == _GroupDimension.features) {
      // 特色功能维度：按逗号分隔的 features 字段拆分，一人可属多组
      for (final s in _allStudents) {
        final featuresStr = (s['features'] as String?)?.trim() ?? '';
        if (featuresStr.isEmpty) continue;
        final featureList = featuresStr
            .split(RegExp(r'[,、，]'))
            .map((f) => f.trim())
            .where((f) => f.isNotEmpty);
        for (final f in featureList) {
          grouped.putIfAbsent(f, () => []).add(s);
        }
      }
    } else {
      for (final s in _allStudents) {
        final key = (s[dim.jsonKey] as String?)?.trim() ?? '未分配';
        grouped.putIfAbsent(key, () => []).add(s);
      }
    }

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
        // 学生：显示个人信息卡片（精简版）
        if (_isStudent && _myInfo != null && _myInfo!.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.withValues(alpha: 0.08),
                  Colors.purple.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue.withValues(alpha: 0.2),
                  child: Text(
                    (_myInfo!['name'] as String? ?? '').isNotEmpty
                        ? (_myInfo!['name'] as String).substring(0, 1)
                        : '?',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_myInfo!['name']} · ${_myInfo!['role']}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_myInfo!['repo']} · ${_myInfo!['techStack']}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                : _currentDim == _GroupDimension.features
                    ? _buildFeaturesView(groups)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: groups.length,
                        itemBuilder: (ctx, i) =>
                            _buildGroupCard(groups[i], i),
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
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.08),
                color.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
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
    final subtitle = _buildSubtitle(group);
    final userId = widget.authService.getCurrentUserId();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color, width: 4),
            ),
          ),
          child: ExpansionTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text('${group.memberCount}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 15)),
              ),
            ),
            title: Text(group.groupName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _isStudent
                ? _buildStudentMemberCards(group.members, userId)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('成员列表 (${group.memberCount}人)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      _buildMemberTable(group.members),
                    ],
                  ),
          ),
          ],
          ),
        ),
      ),
    );
  }

  /// 学生视图：卡片式成员列表（根据维度显示不同重点信息）
  Widget _buildStudentMemberCards(
      List<Map<String, dynamic>> members, String? userId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: members.map((m) {
        final name = m['name'] as String? ?? '';
        final isMe = m['userId'] == userId;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.orange.withValues(alpha: 0.06)
                : Colors.grey.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isMe
                  ? Colors.orange.withValues(alpha: 0.25)
                  : Colors.grey.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：头像 + 姓名 + 标签
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: isMe
                        ? Colors.orange.withValues(alpha: 0.2)
                        : _currentDim.color.withValues(alpha: 0.15),
                    child: Text(
                      name.isNotEmpty ? name.substring(0, 1) : '?',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isMe
                              ? Colors.orange[800]
                              : _currentDim.color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('我',
                          style: TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const Spacer(),
                  // 维度相关的标签
                  _buildDimBadge(m),
                ],
              ),
              const SizedBox(height: 8),
              // 根据维度显示不同的重点信息（避免重复）
              ..._buildDimSpecificInfo(m),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 维度标签
  Widget _buildDimBadge(Map<String, dynamic> m) {
    String text;
    Color badgeColor;
    switch (_currentDim) {
      case _GroupDimension.repo:
        text = m['role'] as String? ?? '';
        badgeColor = Colors.orange;
      case _GroupDimension.classGroup:
        text = m['repo'] as String? ?? '';
        badgeColor = Colors.blue;
      case _GroupDimension.project:
        text = m['techStack'] as String? ?? '';
        badgeColor = Colors.indigo;
      case _GroupDimension.role:
        text = m['techStack'] as String? ?? '';
        badgeColor = Colors.indigo;
      case _GroupDimension.techStack:
        text = m['role'] as String? ?? '';
        badgeColor = Colors.orange;
      case _GroupDimension.features:
        text = m['techStack'] as String? ?? '';
        badgeColor = Colors.indigo;
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, color: badgeColor, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis),
    );
  }

  /// 根据维度显示不同的重点信息
  List<Widget> _buildDimSpecificInfo(Map<String, dynamic> m) {
    final widgets = <Widget>[];
    final coreDuty = m['coreDuty'] as String? ?? '';
    final features = m['features'] as String? ?? '';

    switch (_currentDim) {
      case _GroupDimension.repo:
        // 仓库维度：显示核心职责 + 特色功能
        if (coreDuty.isNotEmpty)
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
        if (features.isNotEmpty)
          widgets.add(_infoLine(Icons.auto_awesome, '功能', features));
      case _GroupDimension.classGroup:
        // 班组维度：显示项目 + 角色
        widgets.add(_infoLine(
            Icons.science, '项目', m['project'] as String? ?? ''));
        widgets.add(
            _infoLine(Icons.engineering, '角色', m['role'] as String? ?? ''));
      case _GroupDimension.project:
        // 项目维度：显示角色 + 核心职责
        widgets.add(
            _infoLine(Icons.engineering, '角色', m['role'] as String? ?? ''));
        if (coreDuty.isNotEmpty)
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
      case _GroupDimension.role:
        // 角色维度：显示项目 + 核心职责
        widgets.add(_infoLine(
            Icons.science, '项目', m['project'] as String? ?? ''));
        if (coreDuty.isNotEmpty)
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
      case _GroupDimension.techStack:
        // 技术栈维度：显示项目 + 特色功能
        widgets.add(_infoLine(
            Icons.science, '项目', m['project'] as String? ?? ''));
        if (features.isNotEmpty)
          widgets.add(_infoLine(Icons.auto_awesome, '功能', features));
      case _GroupDimension.features:
        // 特色功能维度：显示项目 + 角色 + 核心职责
        widgets.add(_infoLine(
            Icons.science, '项目', m['project'] as String? ?? ''));
        widgets.add(
            _infoLine(Icons.engineering, '角色', m['role'] as String? ?? ''));
        if (coreDuty.isNotEmpty)
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
    }
    return widgets;
  }

  Widget _infoLine(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// 特色功能维度：专用视图（功能卡片 + 关联成员）
  Widget _buildFeaturesView(List<_GroupEntry> groups) {
    final userId = widget.authService.getCurrentUserId();
    // 加载功能详解数据
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: groups.length,
      itemBuilder: (ctx, i) {
        final group = groups[i];
        final featureName = group.groupName;

        // 从成员的 feature_detail 中提取该功能的详细描述
        String? detailDesc;
        for (final m in group.members) {
          final fd = m['feature_detail'] as String? ?? '';
          final regex = RegExp('【${RegExp.escape(featureName)}】([^【]*)');
          final match = regex.firstMatch(fd);
          if (match != null) {
            detailDesc = match.group(1)?.trim();
            break;
          }
        }

        // 涉及的项目
        final projects = group.members
            .map((m) => m['project'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 功能名称
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 18, color: Colors.deepOrange[400]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(featureName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange[700])),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${group.memberCount}人',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.deepOrange[600],
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                // 功能描述
                if (detailDesc != null && detailDesc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.deepOrange.withValues(alpha: 0.12)),
                    ),
                    child: Text(detailDesc,
                        style: const TextStyle(fontSize: 12, height: 1.5)),
                  ),
                ],
                // 涉及项目
                if (projects.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: projects
                        .map((p) => Chip(
                              label: Text(p,
                                  style: const TextStyle(fontSize: 10)),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              backgroundColor:
                                  Colors.purple.withValues(alpha: 0.08),
                              side: BorderSide(
                                  color:
                                      Colors.purple.withValues(alpha: 0.15)),
                            ))
                        .toList(),
                  ),
                ],
                // 关联成员
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: group.members.map((m) {
                    final name = m['name'] as String? ?? '';
                    final isMe = m['userId'] == userId;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Colors.orange.withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isMe
                              ? Colors.orange.withValues(alpha: 0.3)
                              : Colors.grey.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      isMe ? FontWeight.bold : FontWeight.normal,
                                  color: isMe
                                      ? Colors.orange[800]
                                      : null)),
                          if (isMe) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.person,
                                size: 12, color: Colors.orange[700]),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buildSubtitle(_GroupEntry group) {
    switch (_currentDim) {
      case _GroupDimension.repo:
        final projects = group.members
            .map((m) => m['project'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toSet();
        return '${group.memberCount}人 · ${projects.join(', ')}';
      case _GroupDimension.classGroup:
        final repos = group.members
            .map((m) => m['repo'] as String? ?? '')
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        return '${group.memberCount}人 · ${repos.length}个仓库';
      case _GroupDimension.project:
        final repos = group.members
            .map((m) => m['repo'] as String? ?? '')
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        return '${group.memberCount}人 · ${repos.join(', ')}';
      case _GroupDimension.role:
        final stacks = group.members
            .map((m) => m['techStack'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toSet();
        return '${group.memberCount}人 · ${stacks.length}种技术栈';
      case _GroupDimension.techStack:
        final roles = group.members
            .map((m) => m['role'] as String? ?? '')
            .where((r) => r.isNotEmpty)
            .toSet();
        return '${group.memberCount}人 · ${roles.join(', ')}';
      case _GroupDimension.features:
        // 显示涉及的项目
        final projects = group.members
            .map((m) => m['project'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toSet();
        return '${group.memberCount}人 · ${projects.length}个项目';
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
        ];
      case _GroupDimension.techStack:
        return [
          ...base,
          _ColDef('仓库', 'repo', 100),
          _ColDef('角色', 'role', 140),
          _ColDef('特色功能', 'features', 350),
        ];
      case _GroupDimension.features:
        return [
          ...base,
          _ColDef('仓库', 'repo', 100),
          _ColDef('项目', 'project', 160),
          _ColDef('角色', 'role', 140),
          _ColDef('技术栈', 'techStack', 140),
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

    // 学生视图：显示详细的项目信息页
    if (_isStudent && _jsonProjects.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: _buildStudentProjectDetail(_jsonProjects.first),
      );
    }

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
                        '项目 (${_jsonProjects.length})',
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

  /// 学生视图：完整的项目详情页
  Widget _buildStudentProjectDetail(Map<String, dynamic> project) {
    final name = project['name'] as String? ?? '';
    final repo = project['repo'] as String? ?? '';
    final techStack = project['tech_stack'] as String? ?? '';
    final memberCount = project['member_count'] as int? ?? 0;
    final members = (project['members'] as List<Map<String, dynamic>>?) ?? [];
    final classGroup = project['classGroup'] as String? ?? '';
    final featureDetail = project['feature_detail'] as String? ?? '';
    final userId = widget.authService.getCurrentUserId();

    // 找到当前学生的个人信息
    final myInfo = members.firstWhere(
      (m) => m['userId'] == userId,
      orElse: () => <String, dynamic>{},
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 项目概览卡片 ──
        _buildDetailCard(
          icon: Icons.folder_special,
          iconColor: Colors.blue,
          title: '项目概览',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildDetailRow('仓库名称', repo, Icons.source),
              _buildDetailRow('所属班组', classGroup, Icons.class_),
              _buildDetailRow('技术栈', techStack, Icons.code),
              _buildDetailRow('团队规模', '$memberCount 人', Icons.groups),
              _buildDetailRow('项目状态', '开发中', Icons.trending_up),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── 项目功能详解 ──
        if (featureDetail.isNotEmpty) ...[
          _buildDetailCard(
            icon: Icons.auto_awesome,
            iconColor: Colors.purple,
            title: '项目功能详解',
            child: _buildFeatureDetailContent(featureDetail),
          ),
          const SizedBox(height: 12),
        ],

        // ── 我的职责（当前学生） ──
        if (myInfo.isNotEmpty) ...[
          _buildDetailCard(
            icon: Icons.person,
            iconColor: Colors.orange,
            title: '我的职责',
            child: _buildMyRoleContent(myInfo),
          ),
          const SizedBox(height: 12),
        ],

        // ── 我的功能详解 ──
        if (myInfo.isNotEmpty &&
            (myInfo['feature_detail'] as String? ?? '').isNotEmpty) ...[
          _buildDetailCard(
            icon: Icons.extension,
            iconColor: Colors.teal,
            title: '我的功能详解',
            child:
                _buildFeatureDetailContent(myInfo['feature_detail'] as String),
          ),
          const SizedBox(height: 12),
        ],

        // ── 团队成员 ──
        _buildDetailCard(
          icon: Icons.people,
          iconColor: Colors.indigo,
          title: '团队成员（$memberCount 人）',
          child: Column(
            children: members
                .map((m) => _buildTeamMemberTile(m, isMe: m['userId'] == userId))
                .toList(),
          ),
        ),

        // ── 备注信息 ──
        if (myInfo.isNotEmpty &&
            (myInfo['remark'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildDetailCard(
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            title: '备注',
            child: Text(myInfo['remark'] as String? ?? '',
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  /// 通用详情卡片容器
  Widget _buildDetailCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: iconColor)),
              ],
            ),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  /// 功能详解内容：按【】分段显示
  Widget _buildFeatureDetailContent(String detail) {
    // 按【】拆分为独立功能块
    final regex = RegExp(r'【(.+?)】([^【]*)');
    final matches = regex.allMatches(detail);
    if (matches.isEmpty) {
      return Text(detail, style: const TextStyle(fontSize: 13, height: 1.6));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: matches.map((m) {
        final featureName = m.group(1) ?? '';
        final featureDesc = (m.group(2) ?? '').trim();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purple.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.star, size: 14, color: Colors.purple[400]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(featureName,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple[700])),
                  ),
                ],
              ),
              if (featureDesc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(featureDesc,
                    style: const TextStyle(fontSize: 12, height: 1.5)),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 我的职责内容
  Widget _buildMyRoleContent(Map<String, dynamic> info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelValue('姓名', info['name'] as String? ?? ''),
        _buildLabelValue('学号', info['userId'] as String? ?? ''),
        _buildLabelValue('角色', info['role'] as String? ?? ''),
        _buildLabelValue('技术栈', info['techStack'] as String? ?? ''),
        _buildLabelValue('核心职责', info['coreDuty'] as String? ?? ''),
        _buildLabelValue('特色功能', info['features'] as String? ?? ''),
      ],
    );
  }

  /// 标签-值行
  Widget _buildLabelValue(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text('$label',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// 团队成员展开卡片
  Widget _buildTeamMemberTile(Map<String, dynamic> m, {bool isMe = false}) {
    final name = m['name'] as String? ?? '';
    final role = m['role'] as String? ?? '';
    final techStack = m['techStack'] as String? ?? '';
    final coreDuty = m['coreDuty'] as String? ?? '';
    final features = m['features'] as String? ?? '';
    final featureDetail = m['feature_detail'] as String? ?? '';
    final userId = m['userId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.orange.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: isMe
                ? Colors.orange.withValues(alpha: 0.2)
                : Colors.blue.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name.substring(0, 1) : '?',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.orange[800] : Colors.blue[700]),
            ),
          ),
          title: Row(
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (isMe) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('我',
                      style: TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          subtitle: Text('$role · $techStack',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          children: [
            if (userId.isNotEmpty)
              _buildLabelValue('学号', userId),
            _buildLabelValue('核心职责', coreDuty),
            _buildLabelValue('特色功能', features),
            if (featureDetail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('功能详解',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple[600])),
              const SizedBox(height: 6),
              _buildFeatureDetailContent(featureDetail),
            ],
          ],
        ),
      ),
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
          constraints: BoxConstraints(maxWidth: 700, maxHeight: 800),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                        _buildSectionTitle('项目基本信息'),
                        _buildInfoRow('仓库', repo),
                        _buildInfoRow('班组', classGroup),
                        if (description.isNotEmpty)
                          _buildInfoRow('项目描述', description),
                        if (techStack.isNotEmpty)
                          _buildInfoRow('技术栈', techStack),
                        const SizedBox(height: 16),
                        if (featureDetail.isNotEmpty) ...[
                          _buildSectionTitle('功能详解'),
                          _buildContentBox(featureDetail),
                          const SizedBox(height: 16),
                        ],
                        if (members.isNotEmpty) ...[
                          _buildSectionTitle('团队成员（${members.length}人）'),
                          const SizedBox(height: 12),
                          ...members.map((m) => _buildMemberCard(m)),
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

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.blue[100]!)),
      ),
      child: Text(title,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.blue[700])),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildContentBox(String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Text(content, style: const TextStyle(fontSize: 12, height: 1.6)),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                child: Text(
                    (m['name'] as String? ?? '').isNotEmpty
                        ? (m['name'] as String).substring(0, 1)
                        : '?',
                    style: TextStyle(fontSize: 14, color: Colors.blue[700])),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['name'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('学号: ${m['userId'] ?? ''}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(m['role'] as String? ?? '',
                    style: TextStyle(fontSize: 11, color: Colors.orange[800])),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildMemberRow('签名', m['signature'] as String? ?? ''),
          _buildMemberRow('仓库', m['repo'] as String? ?? ''),
          _buildMemberRow('技术栈', m['techStack'] as String? ?? ''),
          _buildMemberRow('核心职责', m['coreDuty'] as String? ?? ''),
          _buildMemberRow('特色功能', m['features'] as String? ?? ''),
          if ((m['feature_detail'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('个人功能详解：',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.purple)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(m['feature_detail'] as String? ?? '',
                  style: const TextStyle(fontSize: 11, height: 1.5)),
            ),
          ],
          if ((m['remark'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildMemberRow('备注', m['remark'] as String? ?? ''),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            TextSpan(text: value, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
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
// 贡献评分 Tab — 自评 / 组员互评 / 教师评分，个人/小组/项目三维度
// ══════════════════════════════════════════════════════════════════════════════

class _ContributionTab extends StatefulWidget {
  final AuthService authService;
  const _ContributionTab({required this.authService});

  @override
  State<_ContributionTab> createState() => _ContributionTabState();
}

class _ContributionTabState extends State<_ContributionTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _teamMembers = [];
  List<Map<String, dynamic>> _visibleStudents = [];
  List<Map<String, dynamic>> _visibleScores = [];
  Map<String, dynamic>? _myInfo;
  Map<String, double> _mySummary = {};
  List<Map<String, dynamic>> _myScores = [];
  List<Map<String, dynamic>> _givenScores = [];
  List<Map<String, dynamic>> _teamScores = [];
  bool _loading = true;

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;
  bool get _isTeacherView => !_isStudent;

  @override
  void initState() {
    super.initState();
    _subTabController =
        TabController(length: _isStudent ? 4 : 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _allStudents =
          decoded.map((e) => Map<String, dynamic>.from(e)).toList();

      final userId = widget.authService.getCurrentUserId();

      if (_isStudent && userId != null) {
        _myInfo = _allStudents.firstWhere(
          (s) => s['userId'] == userId,
          orElse: () => <String, dynamic>{},
        );
        if (_myInfo != null && _myInfo!.isNotEmpty) {
          final myRepo = _myInfo!['repo'] as String? ?? '';
          _teamMembers = _allStudents.where((s) => s['repo'] == myRepo).toList();
          _visibleStudents = _teamMembers;
        }

        _mySummary = await _dao.getContributionSummary(userId);
        _myScores = await _dao.getContributionScoresForUser(userId);
        _givenScores = await _dao.getContributionScoresByScorer(userId);
        if (_myInfo != null && _myInfo!.isNotEmpty) {
          _teamScores = await _dao.getContributionScoresByRepo(
              _myInfo!['repo'] as String? ?? '');
          _visibleScores = _teamScores;
        }
      } else {
        _visibleStudents = _allStudents;
        _visibleScores = await _loadAllVisibleScores();
        _givenScores = userId != null
            ? await _dao.getContributionScoresByScorer(userId)
            : [];
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadAllVisibleScores() async {
    final allScores = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final student in _allStudents) {
      final uid = student['userId'] as String? ?? '';
      final scores = await _dao.getContributionScoresForUser(uid);
      for (final score in scores) {
        final id = (score['id'] ?? '').toString();
        if (id.isNotEmpty && seen.add(id)) {
          allScores.add(score);
        }
      }
    }
    return allScores;
  }

  List<Map<String, dynamic>> _scoresForRepo(String repo) {
    return _visibleScores.where((s) => (s['repo'] as String? ?? '') == repo).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final green = Colors.green;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: green.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: green.withValues(alpha: 0.10)),
          ),
          child: TabBar(
            controller: _subTabController,
            isScrollable: true,
            labelColor: green[700],
            unselectedLabelColor: Colors.grey,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: green.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            tabs: [
              if (_isStudent)
                const Tab(icon: Icon(Icons.dashboard, size: 16), text: '我的贡献')
              else
                const Tab(icon: Icon(Icons.rate_review, size: 16), text: '评分'),
              if (_isStudent)
                const Tab(icon: Icon(Icons.rate_review, size: 16), text: '评分'),
              const Tab(icon: Icon(Icons.people, size: 16), text: '小组贡献'),
              const Tab(icon: Icon(Icons.analytics, size: 16), text: '项目贡献'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              if (_isStudent) _buildMyContribution() else _buildScoringPanel(),
              if (_isStudent) _buildScoringPanel(),
              _buildGroupContribution(),
              _buildProjectContribution(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 1: 我的贡献（学生专属） ────────────────────────────────
  Widget _buildMyContribution() {
    final totalReviews = (_mySummary['totalReviews'] ?? 0).toInt();
    final overall = _mySummary['overall'] ?? 0;

    // 按评价来源分组
    final selfScores =
        _myScores.where((s) => s['scorer_type'] == 'self').toList();
    final peerScores =
        _myScores.where((s) => s['scorer_type'] == 'peer').toList();
    final teacherScores =
        _myScores.where((s) => s['scorer_type'] == 'teacher').toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isWide) ...[
                // 桌面宽屏: 三列分析面板
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildOverallScoreCard(overall, totalReviews)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildRadarCard()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildScoreSourceCard(selfScores, peerScores, teacherScores)),
                    ],
                  ),
                ),
              ] else ...[
                // 移动端: 纵向排列
                _buildOverallScoreCard(overall, totalReviews),
                const SizedBox(height: 12),
                _buildRadarCard(),
                const SizedBox(height: 12),
                _buildScoreSourceCard(selfScores, peerScores, teacherScores),
              ],
              const SizedBox(height: 12),

              // 评价详情列表
              if (_myScores.isNotEmpty) ...[
                _sectionHeader('评价详情', Icons.format_list_bulleted),
                const SizedBox(height: 8),
                ..._myScores.map(_buildScoreDetailCard),
              ] else
                _emptyHint('暂无收到的评价，请等待组员和教师评分'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverallScoreCard(double overall, int totalReviews) {
    final Color scoreColor;
    final String level;
    if (overall >= 90) {
      scoreColor = Colors.green;
      level = '优秀';
    } else if (overall >= 75) {
      scoreColor = Colors.blue;
      level = '良好';
    } else if (overall >= 60) {
      scoreColor = Colors.orange;
      level = '合格';
    } else {
      scoreColor = Colors.red;
      level = totalReviews > 0 ? '待提升' : '待评价';
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              scoreColor.withValues(alpha: 0.1),
              scoreColor.withValues(alpha: 0.03),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // 分数环
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: totalReviews > 0 ? overall / 100 : 0,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(scoreColor),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        totalReviews > 0 ? overall.toStringAsFixed(0) : '--',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: scoreColor),
                      ),
                      Text(level,
                          style: TextStyle(fontSize: 10, color: scoreColor)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('综合贡献度',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: scoreColor)),
                  const SizedBox(height: 4),
                  Text('共 $totalReviews 条评价',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(height: 8),
                  if (_myInfo != null) ...[
                    Text(
                      '${_myInfo!['project'] ?? ''} · ${_myInfo!['role'] ?? ''}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarCard() {
    final dims = [
      {'label': '代码贡献', 'value': _mySummary['code'] ?? 0, 'icon': Icons.code, 'color': Colors.blue},
      {'label': '文档贡献', 'value': _mySummary['doc'] ?? 0, 'icon': Icons.description, 'color': Colors.orange},
      {'label': '团队协作', 'value': _mySummary['teamwork'] ?? 0, 'icon': Icons.groups, 'color': Colors.green},
      {'label': '主动性', 'value': _mySummary['initiative'] ?? 0, 'icon': Icons.trending_up, 'color': Colors.purple},
      {'label': '质量', 'value': _mySummary['quality'] ?? 0, 'icon': Icons.verified, 'color': Colors.teal},
    ];
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.indigo.withValues(alpha: 0.04),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.radar, size: 16, color: Colors.indigo[400]),
                ),
                const SizedBox(width: 8),
                const Text('五维评估',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            ...dims.map((d) {
              final val = (d['value'] as double);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(d['icon'] as IconData,
                        size: 16, color: d['color'] as Color),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: Text(d['label'] as String,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: val / 20,
                          minHeight: 10,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              AlwaysStoppedAnimation(d['color'] as Color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text('${val.toStringAsFixed(0)}/20',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: d['color'] as Color)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreSourceCard(
    List<Map<String, dynamic>> self,
    List<Map<String, dynamic>> peer,
    List<Map<String, dynamic>> teacher,
  ) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('评价来源',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                _sourceChip('自评', self.length, Colors.blue, Icons.person),
                const SizedBox(width: 10),
                _sourceChip('互评', peer.length, Colors.green, Icons.people),
                const SizedBox(width: 10),
                _sourceChip(
                    '师评', teacher.length, Colors.purple, Icons.school),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceChip(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text('$count',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreDetailCard(Map<String, dynamic> score) {
    final scorerName = score['scorer_user_name'] as String? ?? '匿名';
    final scorerType = score['scorer_type'] as String? ?? '';
    final dimension = score['dimension'] as String? ?? '';
    final overall = (score['overall_score'] as num?)?.toInt() ?? 0;
    final comment = score['comment'] as String? ?? '';
    final time = score['scored_at'] as String? ?? '';

    final typeLabel = switch (scorerType) {
      'self' => '自评',
      'peer' => '互评',
      'teacher' => '师评',
      _ => scorerType,
    };
    final typeColor = switch (scorerType) {
      'self' => Colors.blue,
      'peer' => Colors.green,
      'teacher' => Colors.purple,
      _ => Colors.grey,
    };
    final dimLabel = switch (dimension) {
      'individual' => '个人',
      'group' => '小组',
      'project' => '项目',
      _ => dimension,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(typeLabel,
                      style: TextStyle(
                          fontSize: 10,
                          color: typeColor,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(dimLabel,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                Text(scorerName,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('$overall分',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: typeColor)),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(comment,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(time.length > 16 ? time.substring(0, 16) : time,
                  style: TextStyle(fontSize: 10, color: Colors.grey[400])),
            ],
          ],
        ),
      ),
    );
  }

  // ── Tab 2: 评分面板 ────────────────────────────────────────
  Widget _buildScoringPanel() {
    final userId = widget.authService.getCurrentUserId() ?? '';
    final scorerType = _isStudent ? 'peer' : 'teacher';
    final rateTargets = _isStudent
        ? _teamMembers.where((m) => m['userId'] != userId).toList()
        : _visibleStudents;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isTeacherView) ...[
            _buildTeacherScoringIntro(),
            const SizedBox(height: 16),
          ],

          // 自评入口
          if (_isStudent && _myInfo != null && _myInfo!.isNotEmpty) ...[
            _sectionHeader('自我评价', Icons.person),
            const SizedBox(height: 8),
            _buildRateTargetCard(
              _myInfo!,
              scorerType: 'self',
              isMe: true,
            ),
            const SizedBox(height: 16),
          ],

          if (rateTargets.isNotEmpty) ...[
            _sectionHeader(
              _isStudent ? '组员互评 (${rateTargets.length}人)' : '教师评分（全班 ${rateTargets.length} 人）',
              _isStudent ? Icons.people : Icons.school,
            ),
            const SizedBox(height: 8),
            ...rateTargets.map((m) => _buildRateTargetCard(
                  m,
                  scorerType: scorerType,
                )),
          ] else
            _emptyHint(_isStudent ? '暂无可评分的组员' : '暂无可评分的学生'),

          if (_givenScores.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('已提交的评分 (${_givenScores.length})', Icons.check_circle),
            const SizedBox(height: 8),
            ..._givenScores.map(_buildScoreDetailCard),
          ],
        ],
      ),
    );
  }

  Widget _buildTeacherScoringIntro() {
    final totalStudents = _visibleStudents.length;
    final teacherScores =
        _visibleScores.where((s) => s['scorer_type'] == 'teacher').length;
    final scoredStudents = _visibleScores
        .where((s) => s['scorer_type'] == 'teacher')
        .map((s) => s['target_user_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.green.withValues(alpha: 0.08),
              Colors.teal.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.school, color: Colors.green[700], size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('教师评分工作台',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800])),
                      const SizedBox(height: 2),
                      Text(
                        '个人/小组/项目三维度评分，进入学生贡献度统计',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _miniStat('学生总数', '$totalStudents', Icons.person, Colors.blue),
                  Container(width: 1, height: 30, color: Colors.grey.withValues(alpha: 0.15)),
                  _miniStat('已覆盖', '$scoredStudents', Icons.check_circle, Colors.green),
                  Container(width: 1, height: 30, color: Colors.grey.withValues(alpha: 0.15)),
                  _miniStat('评分条数', '$teacherScores', Icons.rate_review, Colors.orange),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateTargetCard(
    Map<String, dynamic> member, {
    required String scorerType,
    bool isMe = false,
  }) {
    final name = member['name'] as String? ?? '';
    final role = member['role'] as String? ?? '';
    final targetId = member['userId'] as String? ?? '';

    // 检查各维度是否已评
    final hasIndividual = _givenScores.any((s) =>
        s['target_user_id'] == targetId && s['dimension'] == 'individual');
    final hasGroup = _givenScores.any((s) =>
        s['target_user_id'] == targetId && s['dimension'] == 'group');
    final hasProject = _givenScores.any((s) =>
        s['target_user_id'] == targetId && s['dimension'] == 'project');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isMe
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.blue.withValues(alpha: 0.15),
                  child: Text(
                    name.isNotEmpty ? name.substring(0, 1) : '?',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isMe ? Colors.orange[800] : Colors.blue[700]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('自评',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      Text(role,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 三个维度评分按钮
            Row(
              children: [
                _dimRateButton(
                  '个人', Icons.person, Colors.blue, hasIndividual,
                  () => _showRatingDialog(member, 'individual', scorerType),
                ),
                const SizedBox(width: 8),
                _dimRateButton(
                  '小组', Icons.group, Colors.green, hasGroup,
                  () => _showRatingDialog(member, 'group', scorerType),
                ),
                const SizedBox(width: 8),
                _dimRateButton(
                  '项目', Icons.folder_special, Colors.orange, hasProject,
                  () => _showRatingDialog(member, 'project', scorerType),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dimRateButton(
    String label, IconData icon, Color color, bool done, VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: done
                ? color.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: done
                  ? color.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            children: [
              Icon(
                done ? Icons.check_circle : icon,
                size: 18,
                color: done ? color : Colors.grey,
              ),
              const SizedBox(height: 2),
              Text(
                done ? '$label ✓' : label,
                style: TextStyle(
                  fontSize: 10,
                  color: done ? color : Colors.grey[600],
                  fontWeight: done ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 评分对话框
  void _showRatingDialog(
    Map<String, dynamic> target,
    String dimension,
    String scorerType,
  ) {
    final targetName = target['name'] as String? ?? '';
    final targetId = target['userId'] as String? ?? '';
    final dimLabel = switch (dimension) {
      'individual' => '个人贡献',
      'group' => '小组贡献',
      'project' => '项目贡献',
      _ => dimension,
    };

    // 评分维度说明
    final dimHints = switch (dimension) {
      'individual' => {
        'code': '个人代码编写量与质量',
        'doc': '个人报告、README撰写',
        'teamwork': '与组员沟通协调能力',
        'initiative': '主动承担任务、解决问题',
        'quality': '代码规范、测试覆盖',
      },
      'group' => {
        'code': '对小组代码仓库的贡献',
        'doc': '小组文档的参与度',
        'teamwork': '推动小组进展的作用',
        'initiative': '组内任务分配与执行力',
        'quality': '整体交付质量贡献',
      },
      'project' => {
        'code': '对项目核心功能的实现',
        'doc': '项目架构文档与设计',
        'teamwork': '跨模块协作能力',
        'initiative': '提出创新方案与改进',
        'quality': '项目整体质量保障',
      },
      _ => <String, String>{},
    };

    int codeVal = 15, docVal = 15, teamVal = 15, initVal = 15, qualVal = 15;
    final commentCtrl = TextEditingController();

    // 查看是否已有评分
    final existing = _givenScores.where((s) =>
        s['target_user_id'] == targetId && s['dimension'] == dimension);
    if (existing.isNotEmpty) {
      final e = existing.first;
      codeVal = (e['code_contribution'] as num?)?.toInt() ?? 15;
      docVal = (e['doc_contribution'] as num?)?.toInt() ?? 15;
      teamVal = (e['teamwork_score'] as num?)?.toInt() ?? 15;
      initVal = (e['initiative_score'] as num?)?.toInt() ?? 15;
      qualVal = (e['quality_score'] as num?)?.toInt() ?? 15;
      commentCtrl.text = e['comment'] as String? ?? '';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total = codeVal + docVal + teamVal + initVal + qualVal;
          return AlertDialog(
            title: Text('评价 $targetName · $dimLabel',
                style: const TextStyle(fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 总分指示
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('总分: ',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[600])),
                        Text('$total',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: total >= 75
                                    ? Colors.green
                                    : total >= 50
                                        ? Colors.orange
                                        : Colors.red)),
                        Text(' / 100',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 五个维度滑块
                  _buildSlider('代码贡献', dimHints['code'] ?? '', codeVal,
                      Colors.blue, (v) {
                    setDialogState(() => codeVal = v.round());
                  }),
                  _buildSlider('文档贡献', dimHints['doc'] ?? '', docVal,
                      Colors.orange, (v) {
                    setDialogState(() => docVal = v.round());
                  }),
                  _buildSlider('团队协作', dimHints['teamwork'] ?? '', teamVal,
                      Colors.green, (v) {
                    setDialogState(() => teamVal = v.round());
                  }),
                  _buildSlider('主动性', dimHints['initiative'] ?? '', initVal,
                      Colors.purple, (v) {
                    setDialogState(() => initVal = v.round());
                  }),
                  _buildSlider('质量', dimHints['quality'] ?? '', qualVal,
                      Colors.teal, (v) {
                    setDialogState(() => qualVal = v.round());
                  }),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentCtrl,
                    decoration: const InputDecoration(
                      labelText: '评语（可选）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton.icon(
                onPressed: () async {
                  final userId =
                      widget.authService.getCurrentUserId() ?? '';
                  final userName = widget.authService.currentUser?.realName ??
                      _myInfo?['name'] as String? ?? '';
                  await _dao.submitContributionScore(
                    targetUserId: targetId,
                    targetUserName: targetName,
                    scorerUserId: userId,
                    scorerUserName: userName,
                    scorerType: scorerType,
                    repo: _myInfo?['repo'] as String?,
                    dimension: dimension,
                    codeContribution: codeVal,
                    docContribution: docVal,
                    teamworkScore: teamVal,
                    initiativeScore: initVal,
                    qualityScore: qualVal,
                    comment: commentCtrl.text.trim().isNotEmpty
                        ? commentCtrl.text.trim()
                        : null,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('已提交对 $targetName 的 $dimLabel 评价')),
                    );
                  }
                },
                icon: const Icon(Icons.check, size: 16),
                label: const Text('提交'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSlider(
    String label, String hint, int value, Color color, ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('$value/20',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          if (hint.isNotEmpty)
            Text(hint,
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
              overlayColor: color.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 20,
              divisions: 20,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 3: 小组贡献 ────────────────────────────────────────
  Widget _buildGroupContribution() {
    final repoGroups = <String, List<Map<String, dynamic>>>{};
    for (final student in _visibleStudents) {
      final repo = student['repo'] as String? ?? '未分组项目';
      repoGroups.putIfAbsent(repo, () => []).add(student);
    }

    if (repoGroups.isEmpty) {
      return _emptyHint(_isStudent ? '暂无小组成员数据' : '暂无可统计的小组数据');
    }

    final userId = widget.authService.getCurrentUserId() ?? '';
    final entries = repoGroups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(_isStudent ? '小组成员贡献度排行' : '各小组贡献概览', Icons.leaderboard),
          const SizedBox(height: 8),
          ...entries.map((entry) {
            final repo = entry.key;
            final members = entry.value;
            final repoScores = _scoresForRepo(repo);
            final rankedMembers = members.map((member) {
              final uid = member['userId'] as String? ?? '';
              final scores = repoScores.where((s) => s['target_user_id'] == uid).toList();
              final avgScore = scores.isEmpty
                  ? 0.0
                  : scores.fold<double>(
                          0,
                          (sum, s) =>
                              sum + ((s['overall_score'] as num?)?.toDouble() ?? 0)) /
                      scores.length;
              return {
                ...member,
                'avg_score': avgScore,
                'review_count': scores.length,
              };
            }).toList()
              ..sort((a, b) => (b['avg_score'] as double)
                  .compareTo(a['avg_score'] as double));

            final groupAverage = rankedMembers.isEmpty
                ? 0.0
                : rankedMembers.fold<double>(
                        0, (sum, m) => sum + (m['avg_score'] as double)) /
                    rankedMembers.length;
            final topMember = rankedMembers.isNotEmpty
                ? rankedMembers.first['name'] as String? ?? '-'
                : '-';
            final projectName = members.first['project'] as String? ?? '未命名项目';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.group_work, color: Colors.green[700], size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            projectName,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '${groupAverage.toStringAsFixed(0)}分',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: groupAverage >= 75
                                ? Colors.green
                                : groupAverage >= 50
                                    ? Colors.orange
                                    : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '仓库：$repo',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _miniStat('成员', '${members.length}人', Icons.groups, Colors.blue),
                        _miniStat('评分', '${repoScores.length}条', Icons.rate_review,
                            Colors.orange),
                        _miniStat('最高', topMember, Icons.emoji_events,
                            Colors.amber[700]!),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...rankedMembers.asMap().entries.map((memberEntry) {
                      final rank = memberEntry.key + 1;
                      final m = memberEntry.value;
                      final name = m['name'] as String? ?? '';
                      final role = m['role'] as String? ?? '';
                      final avgScore = m['avg_score'] as double;
                      final reviewCount = m['review_count'] as int;
                      final isMe = m['userId'] == userId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '$rank',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: rank == 1
                                      ? Colors.amber[800]
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                isMe ? '$name（我） · $role' : '$name · $role',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight:
                                      isMe ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              reviewCount > 0
                                  ? '${avgScore.toStringAsFixed(0)}分'
                                  : '--',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: reviewCount > 0
                                    ? (avgScore >= 75
                                        ? Colors.green
                                        : avgScore >= 50
                                            ? Colors.orange
                                            : Colors.grey)
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Tab 4: 项目贡献 ────────────────────────────────────────
  Widget _buildProjectContribution() {
    final repoGroups = <String, List<Map<String, dynamic>>>{};
    for (final student in _visibleStudents) {
      final repo = student['repo'] as String? ?? '未分组项目';
      repoGroups.putIfAbsent(repo, () => []).add(student);
    }

    if (repoGroups.isEmpty) {
      return _emptyHint(_isStudent ? '暂无项目数据' : '暂无可统计的项目数据');
    }

    final userId = widget.authService.getCurrentUserId() ?? '';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: repoGroups.entries.map((entry) {
          final repo = entry.key;
          final members = entry.value;
          final projectName = members.first['project'] as String? ?? '未命名项目';
          final projectDimScores = _scoresForRepo(repo)
              .where((s) => s['dimension'] == 'project')
              .toList();
          final groupDimScores = _scoresForRepo(repo)
              .where((s) => s['dimension'] == 'group')
              .toList();
          final teacherScores = _scoresForRepo(repo)
              .where((s) => s['scorer_type'] == 'teacher')
              .length;
          final peerScores = _scoresForRepo(repo)
              .where((s) => s['scorer_type'] == 'peer')
              .length;
          final selfScores = _scoresForRepo(repo)
              .where((s) => s['scorer_type'] == 'self')
              .length;

          Map<String, List<Map<String, dynamic>>> byTarget(
              List<Map<String, dynamic>> scores) {
            final result = <String, List<Map<String, dynamic>>>{};
            for (final s in scores) {
              final tid = s['target_user_id'] as String? ?? '';
              result.putIfAbsent(tid, () => []).add(s);
            }
            return result;
          }

          final projectByTarget = byTarget(projectDimScores);
          final groupByTarget = byTarget(groupDimScores);
          final projectAvg = projectDimScores.isEmpty
              ? 0.0
              : projectDimScores.fold<double>(
                      0,
                      (sum, s) =>
                          sum + ((s['overall_score'] as num?)?.toDouble() ?? 0)) /
                  projectDimScores.length;

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_special,
                          size: 20, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(projectName,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700])),
                      ),
                      Text(
                        projectAvg > 0 ? '${projectAvg.toStringAsFixed(0)}分' : '--',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: projectAvg >= 75
                              ? Colors.green
                              : projectAvg >= 50
                                  ? Colors.orange
                                  : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('仓库：$repo',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _miniStat('成员', '${members.length}人', Icons.groups, Colors.blue),
                      _miniStat('项目评', '${projectDimScores.length}条', Icons.star_rate,
                          Colors.orange),
                      _miniStat('小组评', '${groupDimScores.length}条', Icons.group_work,
                          Colors.green),
                      _miniStat('师评', '$teacherScores', Icons.school, Colors.purple),
                      _miniStat('互评', '$peerScores', Icons.people, Colors.teal),
                      _miniStat('自评', '$selfScores', Icons.person, Colors.indigo),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _sectionHeader('项目维度贡献', Icons.folder_special),
                  const SizedBox(height: 8),
                  if (projectByTarget.isEmpty)
                    _emptyHint('暂无项目维度评分')
                  else
                    ...members.map((m) {
                      final uid = m['userId'] as String? ?? '';
                      final name = m['name'] as String? ?? '';
                      final scores = projectByTarget[uid] ?? [];
                      final avg = scores.isEmpty
                          ? 0.0
                          : scores.fold<double>(
                                  0,
                                  (sum, s) =>
                                      sum +
                                      ((s['overall_score'] as num?)?.toDouble() ??
                                          0)) /
                              scores.length;
                      return _memberContribBar(
                          name, avg, scores.length, Colors.orange, uid == userId);
                    }),
                  const SizedBox(height: 14),
                  _sectionHeader('小组维度贡献', Icons.group_work),
                  const SizedBox(height: 8),
                  if (groupByTarget.isEmpty)
                    _emptyHint('暂无小组维度评分')
                  else
                    ...members.map((m) {
                      final uid = m['userId'] as String? ?? '';
                      final name = m['name'] as String? ?? '';
                      final scores = groupByTarget[uid] ?? [];
                      final avg = scores.isEmpty
                          ? 0.0
                          : scores.fold<double>(
                                  0,
                                  (sum, s) =>
                                      sum +
                                      ((s['overall_score'] as num?)?.toDouble() ??
                                          0)) /
                              scores.length;
                      return _memberContribBar(
                          name, avg, scores.length, Colors.green, uid == userId);
                    }),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _memberContribBar(
    String name, double avg, int count, Color color, bool isMe,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Row(
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
                if (isMe) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.person, size: 10, color: Colors.orange[700]),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: count > 0 ? avg / 100 : 0,
                minHeight: 14,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                    count > 0 ? color : Colors.grey[300]!),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              count > 0 ? '${avg.toStringAsFixed(0)}分' : '--',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: count > 0 ? color : Colors.grey),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text('$label $value',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: Colors.indigo.withValues(alpha: 0.5), width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.indigo[400]),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
        ],
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
            ),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ],
        ),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade50,
                        Colors.orange.shade50.withValues(alpha: 0.3),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.info_outline,
                                color: Colors.amber[800], size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text('答辩流程（15分钟/组）',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.amber[900])),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _flowStep('1', '项目演示', '5分钟', Colors.blue),
                      _flowStep('2', '技术讲解', '5分钟', Colors.green),
                      _flowStep('3', '评委提问', '3分钟', Colors.orange),
                      _flowStep('4', '评分记录', '2分钟', Colors.purple),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(color: Colors.indigo.withValues(alpha: 0.5), width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_note, size: 17, color: Colors.indigo[400]),
                    const SizedBox(width: 8),
                    Text('答辩安排 (${_defenseRecords.length})',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800])),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_defenseRecords.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(Icons.event_busy,
                              size: 48, color: Colors.grey[300]),
                        ),
                        const SizedBox(height: 12),
                        Text('暂无答辩安排',
                            style: TextStyle(color: Colors.grey[400])),
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
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(num,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(time,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefenseCard(BuildContext context, Map<String, dynamic> defense) {
    final groupName = (defense['group_name'] as String?) ?? '未知小组';
    final projectName = (defense['project_name'] as String?) ?? '未指定项目';
    final scheduledTime = (defense['scheduled_time'] as String?) ?? '';
    final location = (defense['location'] as String?) ?? '待定';
    final status = (defense['status'] as String?) ?? '待答辩';
    final duration = (defense['duration_minutes'] as int?) ?? 15;

    final statusColor = switch (status) {
      '已完成' => Colors.green,
      '进行中' => Colors.blue,
      _ => Colors.amber,
    };
    final statusIcon = switch (status) {
      '已完成' => Icons.check_circle,
      '进行中' => Icons.play_circle_filled,
      _ => Icons.schedule,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: statusColor, width: 4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.record_voice_over,
                          color: Colors.indigo, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(groupName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(projectName,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 13, color: statusColor),
                          const SizedBox(width: 4),
                          Text(status,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 14, color: Colors.indigo[300]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(scheduledTime,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700]),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                          width: 1,
                          height: 16,
                          color: Colors.grey.withValues(alpha: 0.2)),
                      const SizedBox(width: 8),
                      Icon(Icons.location_on,
                          size: 14, color: Colors.indigo[300]),
                      const SizedBox(width: 4),
                      Text(location,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                      const SizedBox(width: 8),
                      Container(
                          width: 1,
                          height: 16,
                          color: Colors.grey.withValues(alpha: 0.2)),
                      const SizedBox(width: 8),
                      Icon(Icons.timer_outlined,
                          size: 14, color: Colors.indigo[300]),
                      const SizedBox(width: 4),
                      Text('${duration}min',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 报告 Tab — 4周过程性报告 + 4份考核报告 → 整合为考核大作业
// ══════════════════════════════════════════════════════════════════════════════

class _AssessmentReportTab extends StatefulWidget {
  final AuthService authService;
  const _AssessmentReportTab({required this.authService});

  @override
  State<_AssessmentReportTab> createState() => _AssessmentReportTabState();
}

class _AssessmentReportTabState extends State<_AssessmentReportTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _submissions = [];
  bool _loading = true;
  String? _currentUserId;

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
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
      final queryUserId = _isStudent ? _currentUserId : null;
      final subs = await _dao.getSubmittedReports(userId: queryUserId);
      if (mounted) setState(() => _submissions = subs);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final indigo = Colors.indigo;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: indigo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: indigo.withValues(alpha: 0.10)),
          ),
          child: TabBar(
            controller: _subTabController,
            labelColor: indigo[700],
            unselectedLabelColor: Colors.grey,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: indigo.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            tabs: const [
              Tab(icon: Icon(Icons.timeline, size: 16), text: '过程报告'),
              Tab(icon: Icon(Icons.assignment, size: 16), text: '考核报告'),
              Tab(icon: Icon(Icons.upload_file, size: 16), text: '提交'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _buildProcessReports(),
              _buildAssessmentReports(),
              _buildSubmissionPanel(),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab1: 4周过程性报告（时间线 + 每周要求）
  // ══════════════════════════════════════════════════════════
  Widget _buildProcessReports() {
    final weeks = [
      {
        'week': '第一周',
        'title': '项目启动',
        'period': '第1-3天',
        'color': Colors.blue,
        'icon': Icons.rocket_launch,
        'tasks': [
          '组建6人团队，确定技术栈分工',
          '完成项目选题与需求分析',
          '设计系统架构（前端/后端/数据库）',
          '搭建各平台开发环境',
          '建立Git仓库，制定分支策略',
          '确定编码规范与协作流程',
        ],
        'deliverables': [
          '团队信息表（成员/技术栈/职责）',
          '需求分析文档（功能需求 + 非功能需求）',
          '系统架构设计图',
          '技术选型对比分析',
          '开发计划与里程碑',
        ],
        'focus': '重点: 分工明确、架构合理、环境就绪',
      },
      {
        'week': '第二周',
        'title': '核心开发',
        'period': '第4-7天',
        'color': Colors.green,
        'icon': Icons.code,
        'tasks': [
          '各平台基础功能开发（UI框架搭建）',
          '实现核心业务逻辑',
          '完成数据库设计与接口开发',
          '各平台独立功能测试',
          'AI功能集成（GLM/DeepSeek/讯飞）',
          '代码审查与质量控制',
        ],
        'deliverables': [
          '各平台开发进度表（功能数/完成率/代码行数）',
          '核心功能截图/录屏',
          '遇到的技术难点与解决方案',
          '代码质量报告（覆盖率/规范检查）',
        ],
        'focus': '重点: 功能实现、代码质量、进度把控',
      },
      {
        'week': '第三周',
        'title': '系统整合',
        'period': '第8-12天',
        'color': Colors.orange,
        'icon': Icons.merge_type,
        'tasks': [
          '跨平台数据同步架构实现',
          'API统一对接与联调',
          '性能优化（启动/渲染/网络/内存）',
          '跨平台UI一致性调整',
          '集成测试与Bug修复',
          '用户体验优化',
        ],
        'deliverables': [
          '整合测试报告（同步成功率/API响应/一致性）',
          '性能测试数据对比表',
          '已修复Bug列表',
          '跨平台兼容性矩阵',
        ],
        'focus': '重点: 数据同步、性能指标、整合质量',
      },
      {
        'week': '第四周',
        'title': '测试交付',
        'period': '第13-15天',
        'color': Colors.purple,
        'icon': Icons.verified,
        'tasks': [
          '全面功能测试（回归测试矩阵）',
          '性能验收测试',
          '安全审计与漏洞修复',
          '编写部署文档与用户手册',
          '准备答辩材料（PPT/视频/录音）',
          '最终版本发布与打包',
        ],
        'deliverables': [
          '功能测试矩阵（通过率/覆盖率）',
          '性能验收数据',
          '部署文档与安装包',
          '答辩PPT/视频演示',
          '项目总结与反思',
        ],
        'focus': '重点: 测试充分、文档完整、答辩准备',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 总览卡片
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  Colors.indigo.withValues(alpha: 0.08),
                  Colors.purple.withValues(alpha: 0.04),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 20, color: Colors.indigo[700]),
                    const SizedBox(width: 8),
                    Text('四周考核流程',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo[700])),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '15天完成项目开发与考核。每周提交过程性报告，记录进展。四份过程报告整合为最终考核大作业的支撑材料。',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 四周时间线
        ...weeks.asMap().entries.map((entry) {
          final i = entry.key;
          final w = entry.value;
          return _buildWeekCard(w, isLast: i == 3);
        }),
      ],
    );
  }

  Widget _buildWeekCard(Map<String, dynamic> w, {bool isLast = false}) {
    final color = w['color'] as Color;
    final tasks = w['tasks'] as List<String>;
    final deliverables = w['deliverables'] as List<String>;
    final focus = w['focus'] as String;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 时间线指示器
        SizedBox(
          width: 30,
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(w['icon'] as IconData, size: 14, color: Colors.white),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 200,
                  color: color.withValues(alpha: 0.3),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 卡片
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: color, width: 3),
                  ),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${w['week']}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: color)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${w['title']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  subtitle: Text('${w['period']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              children: [
                // 主要任务
                _reportSubHeader('主要任务', Icons.checklist, color),
                const SizedBox(height: 4),
                ...tasks.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 14, color: color.withValues(alpha: 0.6)),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(t,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    )),
                const SizedBox(height: 10),
                // 交付物
                _reportSubHeader('交付物', Icons.inventory, Colors.orange),
                const SizedBox(height: 4),
                ...deliverables.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.description,
                              size: 14, color: Colors.orange.withValues(alpha: 0.6)),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(d,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                // 重点提示
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Text(focus,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
              ],
            ),
          ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportSubHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(title,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab2: 4份考核报告要求
  // ══════════════════════════════════════════════════════════
  Widget _buildAssessmentReports() {
    final reports = [
      {
        'num': '1',
        'title': '答辩报告',
        'subtitle': '演示答辩 · 占大作业25%',
        'color': Colors.red,
        'icon': Icons.record_voice_over,
        'requirements': [
          '回答三个必答题（核心技术20分+架构设计30分+创新点40分）',
          '回答一个随机题（10分）',
          '提交视频演示（≤10分钟）',
          '答辩现场实时录音 + 录音转文本',
          '提交个人源码压缩包和部署说明',
        ],
        'keyContent': [
          '项目概述与分工说明',
          '核心技术实现方案（必答题1）',
          '系统架构设计图与说明（必答题2）',
          '创新点与技术亮点展示（必答题3）',
          '现场演示与录音记录',
        ],
        'tips': '答辩前3天提交初稿，答辩当天提交最终版。录音和转录文本必须一致。',
      },
      {
        'num': '2',
        'title': '个人报告',
        'subtitle': '个人贡献总结 · 占大作业25%',
        'color': Colors.blue,
        'icon': Icons.person,
        'requirements': [
          '系统核心类图（UML Class Diagram）— 必须',
          '核心功能顺序图（UML Sequence Diagram）— 必须',
          '系统架构图（Architecture Diagram）— 必须',
          '个人代码贡献统计（提交次数/代码行数）',
          '技术难点与解决方案记录',
        ],
        'keyContent': [
          '个人基本信息与技术栈',
          '个人负责模块的详细实现',
          '3种必须的UML/架构图（图表不规范=0分）',
          '个人代码贡献量化数据',
          '学习收获与技术成长总结',
        ],
        'tips': '图表必须规范（PlantUML/EA/StarUML），必须与个人负责模块相关，图表不规范则此报告0分。',
      },
      {
        'num': '3',
        'title': '小组报告',
        'subtitle': '团队协作总结 · 占大作业25%',
        'color': Colors.green,
        'icon': Icons.groups,
        'requirements': [
          '每位成员独立整合完成（禁止复制他人报告）',
          '个人贡献度与个人报告保持一致',
          '团队数据由全体成员共同确认',
          '包含团队协作流程与沟通记录',
          '禁止修改他人个人贡献数据',
        ],
        'keyContent': [
          '小组基本信息与成员分工表',
          '团队协作流程（Git工作流/代码审查/会议）',
          '成员贡献度矩阵（自评+互评）',
          '团队问题与解决方案',
          '团队协作反思与改进',
        ],
        'tips': '每人独立提交，内容相同但需独立整合。个人贡献部分必须与个人报告数据一致。',
      },
      {
        'num': '4',
        'title': '项目报告',
        'subtitle': '技术文档 · 占大作业25%',
        'color': Colors.orange,
        'icon': Icons.folder_special,
        'requirements': [
          '每位成员独立整合完成',
          '技术栈描述与实际开发一致',
          '包含完整的技术架构文档',
          '测试报告与性能数据',
          '部署文档与用户手册',
        ],
        'keyContent': [
          '项目基本信息（名称/类型/周期/版本）',
          '技术栈详解（≥5种技术栈对比分析）',
          '系统架构设计（分层/模块/数据流）',
          '核心功能实现详解',
          '测试报告（功能测试+性能测试+安全审计）',
          '项目总结与未来展望',
        ],
        'tips': '技术文档必须真实准确，与实际代码一致。推荐包含部署步骤截图。',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 警告卡片
        Card(
          color: Colors.red.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber, size: 18, color: Colors.red),
                    const SizedBox(width: 6),
                    Text('重要提示',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700])),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• 四份报告必须全部提交，缺一不可\n'
                  '• 缺少任何一份报告，大作业成绩为0分（占总成绩50%）\n'
                  '• 迟交任何一份报告，按缺交处理\n'
                  '• 建议顺序：答辩 → 个人 → 小组 → 项目',
                  style: TextStyle(fontSize: 12, color: Colors.red[600], height: 1.6),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 四份报告
        ...reports.map((r) => _buildReportRequirementCard(r)),
      ],
    );
  }

  Widget _buildReportRequirementCard(Map<String, dynamic> r) {
    final color = r['color'] as Color;
    final requirements = r['requirements'] as List<String>;
    final keyContent = r['keyContent'] as List<String>;
    final tips = r['tips'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color, width: 4),
            ),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Center(
                child: Text(r['num'] as String,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: color)),
              ),
            ),
            title: Text(r['title'] as String,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            subtitle: Text(r['subtitle'] as String,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        children: [
          // 基本要求
          _reportSubHeader('基本要求', Icons.rule, color),
          const SizedBox(height: 6),
          ...requirements.map((req) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_box_outlined,
                        size: 14, color: color.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(req,
                            style: const TextStyle(fontSize: 12))),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          // 核心内容
          _reportSubHeader('核心内容（每项都要写）', Icons.edit_note, Colors.indigo),
          const SizedBox(height: 6),
          ...keyContent.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text('${e.key + 1}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[700])),
                      ),
                    ),
                    Expanded(
                        child: Text(e.value,
                            style: const TextStyle(fontSize: 12))),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          // 提示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb, size: 14, color: Colors.amber[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(tips,
                      style: TextStyle(
                          fontSize: 11, color: Colors.amber[800], height: 1.4)),
                ),
              ],
            ),
          ),
          ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab3: 提交面板（上传4份PDF）
  // ══════════════════════════════════════════════════════════
  Widget _buildSubmissionPanel() {
    final reportTypes = [
      {'key': '答辩报告', 'icon': Icons.record_voice_over, 'color': Colors.red, 'num': '1'},
      {'key': '个人报告', 'icon': Icons.person, 'color': Colors.blue, 'num': '2'},
      {'key': '小组报告', 'icon': Icons.groups, 'color': Colors.green, 'num': '3'},
      {'key': '项目报告', 'icon': Icons.folder_special, 'color': Colors.orange, 'num': '4'},
    ];

    return RefreshIndicator(
      onRefresh: () async {
        await _loadSubmissions();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 提交进度
          _buildSubmitProgress(reportTypes),
          const SizedBox(height: 16),

          // 各报告上传卡片
          ...reportTypes.map((rt) {
            final key = rt['key'] as String;
            final submitted = _submissions
                .where((s) =>
                    (s['title'] as String?)?.contains(key) == true)
                .toList();
            return _buildUploadCard(rt, submitted);
          }),

          // 已提交的报告列表
          if (_submissions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.history, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text('提交记录 (${_submissions.length})',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700])),
              ],
            ),
            const SizedBox(height: 8),
            ..._submissions.map((s) => _buildSubmissionItem(s)),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitProgress(List<Map<String, dynamic>> reportTypes) {
    int submitted = 0;
    for (final rt in reportTypes) {
      final key = rt['key'] as String;
      if (_submissions.any(
          (s) => (s['title'] as String?)?.contains(key) == true)) {
        submitted++;
      }
    }

    final progress = submitted / 4;
    final progressColor = submitted == 4
        ? Colors.green
        : submitted >= 2
            ? Colors.orange
            : Colors.red;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.assignment_turned_in,
                    size: 20, color: progressColor),
                const SizedBox(width: 8),
                Text('提交进度',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: progressColor)),
                const Spacer(),
                Text('$submitted / 4',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: progressColor)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(progressColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: reportTypes.map((rt) {
                final key = rt['key'] as String;
                final done = _submissions.any(
                    (s) => (s['title'] as String?)?.contains(key) == true);
                final color = rt['color'] as Color;
                return Expanded(
                  child: Column(
                    children: [
                      Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                        color: done ? color : Colors.grey[300],
                      ),
                      const SizedBox(height: 2),
                      Text(key.replaceAll('报告', ''),
                          style: TextStyle(
                              fontSize: 9,
                              color: done ? color : Colors.grey[400])),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard(
      Map<String, dynamic> rt, List<Map<String, dynamic>> submitted) {
    final key = rt['key'] as String;
    final color = rt['color'] as Color;
    final done = submitted.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: done
            ? BorderSide(color: color.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: done
                  ? color.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              child: Icon(
                done ? Icons.check : rt['icon'] as IconData,
                size: 20,
                color: done ? color : Colors.grey,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('报告${rt['num']}：$key',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: done ? color : null)),
                  Text(done
                      ? '已提交 · ${(submitted.first['submit_time'] as String? ?? '').length > 16 ? (submitted.first['submit_time'] as String).substring(0, 16) : submitted.first['submit_time'] ?? ''}'
                      : '未提交',
                      style: TextStyle(
                          fontSize: 11,
                          color: done ? Colors.grey[500] : Colors.red[300])),
                ],
              ),
            ),
            if (_isStudent)
              FilledButton.icon(
                onPressed: () => _pickAndUploadPdf(key),
                style: FilledButton.styleFrom(
                  backgroundColor: done ? color : null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                icon: Icon(done ? Icons.refresh : Icons.upload_file, size: 16),
                label: Text(done ? '重新提交' : '上传PDF',
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPdf(String reportType) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final userId = _currentUserId ?? '';
      final userName =
          widget.authService.currentUser?.realName ?? userId;

      await _dao.submitReport(
        userId: userId,
        studentName: userName,
        reportType: reportType,
        fileName: file.name,
        filePath: file.path ?? '',
      );

      await _loadSubmissions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$reportType 已提交: ${file.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    }
  }

  Widget _buildSubmissionItem(Map<String, dynamic> s) {
    final title = s['title'] as String? ?? '';
    final time = s['submit_time'] as String? ?? s['created_at'] as String? ?? '';
    final status = s['status'] as String? ?? '已提交';
    final content = s['content_json'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.picture_as_pdf, color: Colors.red[400], size: 24),
        title: Text(title, style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          '${time.length > 16 ? time.substring(0, 16) : time} · $status'
          '${content.isNotEmpty ? ' · $content' : ''}',
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
        trailing: _isStudent
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () async {
                  final id = s['id'] as int?;
                  if (id != null) {
                    await _dao.deleteSubmittedReport(id);
                    await _loadSubmissions();
                  }
                },
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: status == '已批改'
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(status,
                    style: TextStyle(
                        fontSize: 10,
                        color: status == '已批改' ? Colors.green : Colors.blue)),
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
                  borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [primary, primary.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.school,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 20),
                        const SizedBox(width: 8),
                        const Text('我的考核成绩',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_myScore != null) ...[
                      Text(
                        '${(_myScore!['total_score'] as num?)?.toInt() ?? 0}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            height: 1.1),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_myScore!['group_name'] ?? ''} · ${_myScore!['project_name'] ?? ''}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ] else
                      Column(
                        children: [
                          Icon(Icons.pending_outlined,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 36),
                          const SizedBox(height: 8),
                          const Text('暂无成绩',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16)),
                        ],
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
                  borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [primary, primary.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _overviewItem('平均分', avgScore, Icons.analytics),
                    Container(width: 1, height: 44, color: Colors.white24),
                    _overviewItem('最高分', maxScore, Icons.emoji_events),
                    Container(width: 1, height: 44, color: Colors.white24),
                    _overviewItem('及格率', passRate, Icons.check_circle),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 排行榜
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: Colors.indigo.withValues(alpha: 0.5), width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.leaderboard, size: 17, color: Colors.indigo[400]),
                  const SizedBox(width: 8),
                  Text('成绩排行 (${_ranking.length})',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800])),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (_ranking.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.leaderboard_outlined,
                            size: 48, color: Colors.grey[300]),
                      ),
                      const SizedBox(height: 12),
                      Text('暂无成绩数据', style: TextStyle(color: Colors.grey[400])),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.indigo.withValues(alpha: 0.04),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bar_chart, size: 16, color: Colors.indigo[400]),
                ),
                const SizedBox(width: 8),
                Text('评分维度明细（${top['group_name'] ?? '第一名'}）',
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 14),
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
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75), fontSize: 11)),
      ],
    );
  }

  Widget _buildScoreCard(BuildContext context, Map<String, dynamic> score) {
    final rank = score['rank'] as int;
    final totalScore = score['score'] as int;
    final rankColor = rank == 1
        ? Colors.amber[700]!
        : rank == 2
            ? Colors.grey.shade500
            : rank == 3
                ? Colors.brown.shade400
                : Colors.grey;
    final rankIcon = rank <= 3 ? Icons.emoji_events : null;

    final scoreColor = totalScore >= 90
        ? Colors.green
        : totalScore >= 80
            ? Colors.blue
            : totalScore >= 60
                ? Colors.orange
                : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: rank <= 3 ? 3 : 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: rank <= 3
              ? LinearGradient(
                  colors: [
                    rankColor.withValues(alpha: 0.06),
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: rank <= 3
                    ? Border.all(color: rankColor.withValues(alpha: 0.3))
                    : null,
              ),
              child: Center(
                child: rankIcon != null
                    ? Icon(rankIcon, color: rankColor, size: 22)
                    : Text('#$rank',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                            fontSize: 14)),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(score['group'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(score['project'] as String,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            // Score
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$totalScore',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scoreColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dimensionBar(String name, int score, int max, Color color) {
    final ratio = max > 0 ? score / max : 0.0;
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
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('$score/$max',
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.indigo.withValues(alpha: 0.04),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bar_chart, size: 16, color: Colors.indigo[400]),
                ),
                const SizedBox(width: 8),
                const Text('评分维度明细',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 14),
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
