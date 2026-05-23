part of '../assessment_page.dart';

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
  // ignore: unused_field
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
                  ],
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

