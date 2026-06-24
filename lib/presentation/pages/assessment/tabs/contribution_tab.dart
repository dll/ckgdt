part of '../assessment_page.dart';

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
    } catch (e, st) {
      swallowDebug(e, tag: 'contribution_tab._loadData', stack: st);
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

    const green = Colors.green;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: green.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: green.withOpacity(0.10)),
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
                  color: green.withOpacity(0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: [
              if (_isStudent)
                const Tab(icon: Icon(Icons.dashboard, size: 18), text: '我的贡献')
              else
                const Tab(icon: Icon(Icons.rate_review, size: 18), text: '评分'),
              if (_isStudent)
                const Tab(icon: Icon(Icons.rate_review, size: 18), text: '评分'),
              const Tab(icon: Icon(Icons.people, size: 18), text: '小组贡献'),
              const Tab(icon: Icon(Icons.analytics, size: 18), text: '项目贡献'),
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
              scoreColor.withOpacity(0.1),
              scoreColor.withOpacity(0.03),
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
              Colors.indigo.withOpacity(0.04),
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
                    color: Colors.indigo.withOpacity(0.1),
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
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
                    color: typeColor.withOpacity(0.1),
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
                    color: Colors.grey.withOpacity(0.1),
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
              Colors.green.withOpacity(0.08),
              Colors.teal.withOpacity(0.03),
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
                    color: Colors.green.withOpacity(0.12),
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
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _miniStat('学生总数', '$totalStudents', Icons.person, Colors.blue),
                  Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.15)),
                  _miniStat('已覆盖', '$scoredStudents', Icons.check_circle, Colors.green),
                  Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.15)),
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
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.blue.withOpacity(0.15),
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
                ? color.withOpacity(0.1)
                : Colors.grey.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: done
                  ? color.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.15),
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
                      color: Colors.green.withOpacity(0.08),
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
                  final newId = await _dao.submitContributionScore(
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
                  // 审计：贡献度评分录入
                  try {
                    final total =
                        codeVal + docVal + teamVal + initVal + qualVal;
                    await ScoreAuditDao.instance.logChange(
                      tableName: 'contribution_scores',
                      rowId: newId,
                      field: 'total',
                      newValue: total.toString(),
                      scorerId: userId,
                      scorerName: userName,
                      op: 'create',
                    );
                  } catch (e) { swallowDebug(e, tag: 'contribution_tab'); }
                  // 通知教师
                  NotificationService().notifyContributionScore(
                    scorerId: userId,
                    scorerName: userName,
                    targetName: targetName,
                    dimension: dimLabel,
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
              inactiveTrackColor: color.withOpacity(0.15),
              overlayColor: color.withOpacity(0.1),
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
        color: Colors.grey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: Colors.indigo.withOpacity(0.5), width: 3),
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
                color: Colors.grey.withOpacity(0.06),
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

