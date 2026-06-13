part of '../assessment_page.dart';

class _DefenseTab extends StatefulWidget {
  final AuthService authService;
  const _DefenseTab({required this.authService});

  @override
  State<_DefenseTab> createState() => _DefenseTabState();
}

class _DefenseTabState extends State<_DefenseTab> {
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _defenseRecords = [];
  Map<int, Map<String, dynamic>> _groupEligibility = {};
  bool _loading = true;

  // 班级选择
  String _selectedClass = 'all';
  List<String> _classNames = [];
  Map<int, String?> _groupClassName = {};

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  List<Map<String, dynamic>> get _filteredRecords {
    if (_selectedClass == 'all') return _defenseRecords;
    return _defenseRecords.where((d) {
      final gid = d['group_id'] as int?;
      final cn = gid != null ? _groupClassName[gid] : null;
      return cn == _selectedClass;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      var records = await _dao.getDefenseRecords();

      // 班级映射：group_id → class_name（通过 class_members 查找）
      final db = await DatabaseHelper.instance.database;
      final classes = await db.query('classes');
      final classNames = classes
          .map((c) => c['name'] as String)
          .where((n) => n.isNotEmpty)
          .toList();
      final groupClassMap = <int, String?>{};
      for (final r in records) {
        final gid = r['group_id'] as int?;
        if (gid == null || groupClassMap.containsKey(gid)) continue;
        try {
          final members = await db.query('class_members',
              where:
                  'user_id IN (SELECT user_id FROM assessment_group_members WHERE group_id = ?)',
              whereArgs: [gid],
              limit: 1);
          if (members.isNotEmpty) {
            final classId = members.first['class_id'] as int?;
            if (classId != null) {
              final cls = await db.query('classes',
                  where: 'id = ?', whereArgs: [classId], limit: 1);
              if (cls.isNotEmpty)
                groupClassMap[gid] = cls.first['name'] as String?;
            }
          }
        } catch (_) {}
      }

      if (_isStudent) {
        final userId = widget.authService.getCurrentUserId();
        if (userId != null) {
          records = records.where((d) {
            final memberIds = d['member_ids']?.toString() ?? '';
            return memberIds.contains(userId);
          }).toList();
        }
      }

      // 加载各组的答辩资格
      final eligibility = <int, Map<String, dynamic>>{};
      for (final r in records) {
        final gid = r['group_id'] as int?;
        if (gid != null && !eligibility.containsKey(gid)) {
          try {
            eligibility[gid] = await _dao.checkGroupDefenseEligibility(gid);
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _defenseRecords = records;
          _groupEligibility = eligibility;
          _classNames = classNames;
          _groupClassName = groupClassMap;
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
                final newId = await _dao.addDefenseRecord(
                  groupId: selectedGroupId!,
                  projectId: selectedProjectId,
                  scheduledTime: timeCtrl.text.trim(),
                  location: locationCtrl.text.trim().isNotEmpty
                      ? locationCtrl.text.trim()
                      : '实验楼A301',
                );
                // 审计：答辩记录创建
                try {
                  await ScoreAuditDao.instance.logChange(
                    tableName: 'defense_records',
                    rowId: newId,
                    field: 'scheduled_time',
                    newValue: timeCtrl.text.trim(),
                    scorerId: widget.authService.getCurrentUserId() ?? '',
                    scorerName: widget.authService.currentUser?.realName,
                    op: 'create',
                  );
                } catch (_) {}
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
              // 答辩资格条件说明
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        Colors.indigo.shade50,
                        Colors.blue.shade50.withValues(alpha: 0.3)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.shield_outlined,
                              size: 18, color: Colors.indigo[700]),
                          const SizedBox(width: 8),
                          Text('答辩资格条件',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo[800])),
                        ]),
                        const SizedBox(height: 10),
                        _buildEligibilityCondition(
                            '①', '所有实验成绩 ≥ 95分', Colors.blue),
                        _buildEligibilityCondition(
                            '②', '过程报告 + 最终报告得分 ≥ 95分', Colors.teal),
                        _buildEligibilityCondition(
                            '③', '报告内容匹配小组技术栈和特色功能', Colors.deepOrange),
                        const SizedBox(height: 8),
                        // 各小组答辩资格状态
                        if (_groupEligibility.isNotEmpty) ...[
                          const Divider(height: 16),
                          ..._groupEligibility.entries.map((e) {
                            final gid = e.key;
                            final info = e.value;
                            final eligible = info['eligible'] == true;
                            final groupName = info['groupName'] ?? '小组#$gid';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                Icon(
                                    eligible
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    size: 16,
                                    color:
                                        eligible ? Colors.green : Colors.red),
                                const SizedBox(width: 6),
                                Text(groupName,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: eligible
                                            ? Colors.green[800]
                                            : Colors.red[800],
                                        fontWeight: FontWeight.w500)),
                                const Spacer(),
                                Text(eligible ? '已达标' : '未达标',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: eligible
                                            ? Colors.green
                                            : Colors.red)),
                              ]),
                            );
                          }),
                        ],
                      ]),
                ),
              ),
              // ── LAN 直播新入口（独立卡片） ──────────────────────────
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        NoirTokens.accent.withValues(alpha: 0.08),
                        NoirTokens.inkDeep
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.wifi_tethering,
                            color: Colors.green, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('答辩直播',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: NoirTokens.paper)),
                            const SizedBox(height: 2),
                            Text('桌面/手机三路流 · 局域网直连 · 无需 Gitee',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: NoirTokens.paper
                                        .withValues(alpha: 0.5))),
                          ],
                        ),
                      ),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _isStudent
                              ? [
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const DefenseBroadcastPage(
                                                    initialRole: 'viewer'))),
                                    icon:
                                        const Icon(Icons.visibility, size: 16),
                                    label: const Text('观看'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      side: BorderSide(
                                          color: Colors.blue
                                              .withValues(alpha: 0.4)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const DefenseBroadcastPage(
                                                    initialRole: 'defender'))),
                                    icon: const Icon(Icons.record_voice_over,
                                        size: 16),
                                    label: const Text('答辩'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Colors.green.withValues(alpha: 0.15),
                                      foregroundColor: Colors.green,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ]
                              : [
                                  FilledButton.tonalIcon(
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const DefenseBroadcastPage(
                                                    initialRole: 'presenter'))),
                                    icon: const Icon(Icons.live_tv, size: 18),
                                    label: const Text('主播'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Colors.green.withValues(alpha: 0.15),
                                      foregroundColor: Colors.green,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const DefenseBroadcastPage(
                                                    initialRole: 'viewer'))),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: NoirTokens.paper
                                          .withValues(alpha: 0.7),
                                      side: BorderSide(
                                          color: NoirTokens.paper
                                              .withValues(alpha: 0.2)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text('观看'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const DefenseBroadcastPage(
                                                    initialRole: 'present'))),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      side: BorderSide(
                                          color: Colors.blue
                                              .withValues(alpha: 0.4)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text('演示'),
                                  ),
                                ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 班级选择器
              Row(
                children: [
                  Icon(Icons.filter_alt, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text('班级筛选：',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        ChoiceChip(
                            label: const Text('全部',
                                style: TextStyle(fontSize: 12)),
                            selected: _selectedClass == 'all',
                            selectedColor:
                                NoirTokens.accent.withValues(alpha: 0.3),
                            onSelected: (_) =>
                                setState(() => _selectedClass = 'all'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        ..._classNames.map((cn) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                  label: Text(cn,
                                      style: const TextStyle(fontSize: 12)),
                                  selected: _selectedClass == cn,
                                  selectedColor:
                                      NoirTokens.accent.withValues(alpha: 0.3),
                                  onSelected: (_) =>
                                      setState(() => _selectedClass = cn),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                            )),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                        color: Colors.indigo.withValues(alpha: 0.5), width: 3),
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
                ..._filteredRecords.map((d) => _buildDefenseCard(context, d)),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(time,
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEligibilityCondition(String num, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6)),
          child: Center(
              child: Text(num,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color))),
        ),
        const SizedBox(width: 8),
        Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ]),
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
                      Icon(Icons.schedule, size: 14, color: Colors.indigo[300]),
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
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700])),
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
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700])),
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
