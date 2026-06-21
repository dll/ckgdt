part of '../assessment_page.dart';

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
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            padding: const EdgeInsets.all(10),
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
                        fontSize: 14,
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
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_myInfo!['repo']} · ${_myInfo!['techStack']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: _GroupDimension.values
                .map((d) => Tab(
                      icon: Icon(d.icon, size: 18),
                      text: d.label,
                    ))
                .toList(),
          ),
        ),
        // 统计行
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
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
        const SizedBox(width: 6),
        _statCard('总人数', '$totalMembers', Icons.people, Colors.green),
        const SizedBox(width: 6),
        _statCard('人均', avg.toStringAsFixed(1), Icons.person, Colors.orange),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.06),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(_GroupEntry group, int index) {
    final color = _currentDim.color;
    final subtitle = _buildSubtitle(group);
    final userId = widget.authService.getCurrentUserId();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                    fontWeight: FontWeight.w700, fontSize: 15)),
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
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
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
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
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
        if (coreDuty.isNotEmpty) {
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
        }
        if (features.isNotEmpty) {
          widgets.add(_infoLine(Icons.auto_awesome, '功能', features));
        }
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
        if (coreDuty.isNotEmpty) {
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
        }
      case _GroupDimension.role:
        // 角色维度：显示项目 + 核心职责
        widgets.add(_infoLine(
            Icons.science, '项目', m['project'] as String? ?? ''));
        if (coreDuty.isNotEmpty) {
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
        }
      case _GroupDimension.techStack:
        // 技术栈维度：显示项目 + 特色功能
        widgets.add(_infoLine(
            Icons.science, '项目', m['project'] as String? ?? ''));
        if (features.isNotEmpty) {
          widgets.add(_infoLine(Icons.auto_awesome, '功能', features));
        }
      case _GroupDimension.features:
        // 特色功能维度：显示项目 + 角色 + 核心职责
        widgets.add(_infoLine(
            Icons.science, '项目', m['project'] as String? ?? ''));
        widgets.add(
            _infoLine(Icons.engineering, '角色', m['role'] as String? ?? ''));
        if (coreDuty.isNotEmpty) {
          widgets.add(_infoLine(Icons.work_outline, '职责', coreDuty));
        }
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
      const _ColDef('学号', 'userId', 100),
      const _ColDef('姓名', 'name', 70),
    ];
    switch (_currentDim) {
      case _GroupDimension.repo:
        return [
          ...base,
          const _ColDef('班组', 'classGroup', 60),
          const _ColDef('角色', 'role', 140),
          const _ColDef('特色功能', 'features', 350),
        ];
      case _GroupDimension.classGroup:
        return [
          ...base,
          const _ColDef('仓库', 'repo', 100),
          const _ColDef('项目', 'project', 160),
          const _ColDef('角色', 'role', 140),
        ];
      case _GroupDimension.project:
        return [
          ...base,
          const _ColDef('仓库', 'repo', 100),
          const _ColDef('角色', 'role', 140),
          const _ColDef('技术栈', 'techStack', 140),
        ];
      case _GroupDimension.role:
        return [
          ...base,
          const _ColDef('仓库', 'repo', 100),
          const _ColDef('技术栈', 'techStack', 140),
          const _ColDef('特色功能', 'features', 350),
        ];
      case _GroupDimension.techStack:
        return [
          ...base,
          const _ColDef('仓库', 'repo', 100),
          const _ColDef('角色', 'role', 140),
          const _ColDef('特色功能', 'features', 350),
        ];
      case _GroupDimension.features:
        return [
          ...base,
          const _ColDef('仓库', 'repo', 100),
          const _ColDef('项目', 'project', 160),
          const _ColDef('角色', 'role', 140),
          const _ColDef('技术栈', 'techStack', 140),
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

