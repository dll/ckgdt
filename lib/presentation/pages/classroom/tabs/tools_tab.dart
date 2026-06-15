part of '../classroom_page.dart';

class _ClassroomToolsTab extends StatefulWidget {
  final ClassroomDao classroomDao;
  final int? classId;
  final AuthService authService;

  const _ClassroomToolsTab({
    required this.classroomDao,
    this.classId,
    required this.authService,
  });

  @override
  State<_ClassroomToolsTab> createState() => _ClassroomToolsTabState();
}

class _ClassroomToolsTabState extends State<_ClassroomToolsTab> {
  final _classroomDao = ClassroomDao();

  // ── 分层点名 ──
  List<Map<String, dynamic>> _highStudents = [];
  List<Map<String, dynamic>> _midStudents = [];
  List<Map<String, dynamic>> _lowStudents = [];
  String _selectedDifficulty = 'medium'; // hard / medium / easy
  Map<String, dynamic>? _pickedStudent;
  bool _isRolling = false;
  Timer? _rollTimer;
  int _rollCount = 0;
  int? _currentSessionId;
  bool _showResult = false; // 是否已选中学生待评判
  List<Map<String, dynamic>> _scoreboard = [];
  bool _studentsLoaded = false;

  // ── 快速投票 ──
  final _pollQuestionCtrl = TextEditingController();
  List<String> _pollOptions = ['选项A', '选项B'];
  Map<String, int> _pollResults = {};
  bool _pollActive = false;
  String? _pollQuestion;

  // ── 倒计时 ──
  Timer? _countdownTimer;
  int _timerSeconds = 300; // 5分钟
  int _remainingSeconds = 0;
  bool _timerRunning = false;
  final _customTimerController = TextEditingController();
  final _timerFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    _countdownTimer?.cancel();
    _pollQuestionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      final tiers = await _classroomDao.classifyStudentsByPerformance(
        classId: widget.classId,
      );
      final scores = await _classroomDao.getRollCallScoreboard(
        classId: widget.classId,
      );
      if (mounted) {
        setState(() {
          _highStudents = tiers['high'] ?? [];
          _midStudents = tiers['mid'] ?? [];
          _lowStudents = tiers['low'] ?? [];
          _scoreboard = scores;
          _studentsLoaded = true;
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ClassroomTools._loadScoreboard', stack: st);
    }
  }

  // ── 分层点名逻辑 ──

  /// 得分规则
  static const _scoreRules = {
    'hard': {'correct': 5.0, 'wrong': -1.0},
    'medium': {'correct': 3.0, 'wrong': -2.0},
    'easy': {'correct': 1.0, 'wrong': -3.0},
  };

  /// 难度对应的学生池
  List<Map<String, dynamic>> get _targetPool {
    switch (_selectedDifficulty) {
      case 'hard':
        return _highStudents;
      case 'easy':
        return _lowStudents;
      default:
        return _midStudents;
    }
  }

  /// 所有学生（用于滚动动画）
  List<Map<String, dynamic>> get _allStudents => [
        ..._highStudents,
        ..._midStudents,
        ..._lowStudents,
      ];

  String _difficultyLabel(String d) {
    switch (d) {
      case 'hard':
        return '难';
      case 'easy':
        return '易';
      default:
        return '中';
    }
  }

  Color _difficultyColor(String d) {
    switch (d) {
      case 'hard':
        return Colors.red;
      case 'easy':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  void _startRoll() {
    final pool = _targetPool;
    if (pool.isEmpty && _allStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有学生数据')),
      );
      return;
    }

    // 如果对应层级为空，从全部学生中随机选
    final effectivePool = pool.isNotEmpty ? pool : _allStudents;

    setState(() {
      _isRolling = true;
      _rollCount = 0;
      _pickedStudent = null;
      _showResult = false;
    });

    final random = Random();
    _rollTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      _rollCount++;
      final all = _allStudents;
      if (all.isEmpty) {
        timer.cancel();
        return;
      }
      final idx = random.nextInt(all.length);
      setState(() => _pickedStudent = all[idx]);

      if (_rollCount > 20 + random.nextInt(15)) {
        timer.cancel();
        // 最终选定的学生从目标池中随机选
        final finalIdx = random.nextInt(effectivePool.length);
        setState(() {
          _pickedStudent = effectivePool[finalIdx];
          _isRolling = false;
          _showResult = true;
        });
      }
    });
  }

  /// 评判回答结果
  Future<void> _judgeAnswer(bool isCorrect) async {
    if (_pickedStudent == null) return;

    final userId = _pickedStudent!['user_id'] as String;
    final userName = _pickedStudent!['real_name'] as String? ?? userId;
    final rules = _scoreRules[_selectedDifficulty]!;
    final delta = isCorrect ? rules['correct']! : rules['wrong']!;

    // 确定学生所属层级
    String tier = 'mid';
    if (_highStudents.any((s) => s['user_id'] == userId))
      tier = 'high';
    else if (_lowStudents.any((s) => s['user_id'] == userId)) tier = 'low';

    // 确保有会话
    _currentSessionId ??= await _classroomDao.createRollCallSession(
      classId: widget.classId,
      createdBy: widget.authService.getCurrentUserId() ?? '',
    );

    await _classroomDao.addRollCallRecord(
      sessionId: _currentSessionId!,
      userId: userId,
      userName: userName,
      difficulty: _selectedDifficulty,
      tier: tier,
      isCorrect: isCorrect,
      scoreDelta: delta,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCorrect
                ? '$userName 回答正确！+${delta.toStringAsFixed(0)} 分'
                : '$userName 回答错误，${delta.toStringAsFixed(0)} 分',
          ),
          backgroundColor: isCorrect ? Colors.green : Colors.red[400],
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() => _showResult = false);
      // 刷新排行
      final scores =
          await _classroomDao.getRollCallScoreboard(classId: widget.classId);
      if (mounted)
        setState(() {
          _scoreboard = scores;
        });
    }
  }

  // ── 投票逻辑 ──

  void _startPoll() {
    final question = _pollQuestionCtrl.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入投票问题')),
      );
      return;
    }

    setState(() {
      _pollQuestion = question;
      _pollActive = true;
      _pollResults = {for (var opt in _pollOptions) opt: 0};
    });
  }

  void _vote(String option) {
    setState(() {
      _pollResults[option] = (_pollResults[option] ?? 0) + 1;
    });
  }

  void _endPoll() {
    setState(() => _pollActive = false);
  }

  void _resetPoll() {
    setState(() {
      _pollActive = false;
      _pollQuestion = null;
      _pollResults.clear();
      _pollQuestionCtrl.clear();
      _pollOptions = ['选项A', '选项B'];
    });
  }

  // ── 倒计时逻辑 ──

  void _startCountdown() {
    setState(() {
      _remainingSeconds = _timerSeconds;
      _timerRunning = true;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        setState(() => _timerRunning = false);
        // 时间到提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏰ 时间到！'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  void _pauseCountdown() {
    _countdownTimer?.cancel();
    setState(() => _timerRunning = false);
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _timerRunning = false;
      _remainingSeconds = 0;
    });
  }

  void _applyCustomTimer(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0 && parsed <= 180) {
      setState(() => _timerSeconds = parsed * 60);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请输入1~180之间的整数分钟'), backgroundColor: Colors.orange),
      );
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. 分层点名 ──
          _buildToolCard(
            title: '分层点名',
            icon: Icons.person_search,
            color: Colors.orange,
            isDark: isDark,
            child: Column(
              children: [
                // 难度选择
                Row(
                  children: [
                    const Text('题目难度：',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    ...['hard', 'medium', 'easy'].map((d) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_difficultyLabel(d),
                                style: const TextStyle(fontSize: 12)),
                            selected: _selectedDifficulty == d,
                            selectedColor:
                                _difficultyColor(d).withValues(alpha: 0.2),
                            onSelected: _isRolling || _showResult
                                ? null
                                : (v) {
                                    if (v)
                                      setState(() => _selectedDifficulty = d);
                                  },
                          ),
                        )),
                  ],
                ),
                const SizedBox(height: 4),
                // 得分规则提示
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _difficultyColor(_selectedDifficulty)
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_difficultyLabel(_selectedDifficulty)}题 → '
                    '${_selectedDifficulty == "hard" ? "优等生" : _selectedDifficulty == "easy" ? "待提升" : "中等生"}  |  '
                    '答对 +${_scoreRules[_selectedDifficulty]!["correct"]!.toStringAsFixed(0)}  '
                    '答错 ${_scoreRules[_selectedDifficulty]!["wrong"]!.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: _difficultyColor(_selectedDifficulty)),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
                // 学生层级人数
                if (_studentsLoaded)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildTierChip('优', _highStudents.length, Colors.red),
                      _buildTierChip('中', _midStudents.length, Colors.orange),
                      _buildTierChip('差', _lowStudents.length, Colors.green),
                    ],
                  ),
                const SizedBox(height: 10),
                // 显示区域
                Container(
                  width: double.infinity,
                  height: 100,
                  decoration: BoxDecoration(
                    color: _isRolling
                        ? Colors.orange.withValues(alpha: 0.1)
                        : _showResult
                            ? _difficultyColor(_selectedDifficulty)
                                .withValues(alpha: 0.08)
                            : (isDark ? Colors.grey[850] : Colors.grey[50]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isRolling
                          ? Colors.orange
                          : _showResult
                              ? _difficultyColor(_selectedDifficulty)
                              : Colors.grey.withValues(alpha: 0.2),
                      width: _isRolling || _showResult ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 100),
                    child: _pickedStudent != null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _pickedStudent!['real_name'] as String? ?? '',
                                key: ValueKey(_pickedStudent!['user_id']),
                                style: TextStyle(
                                  fontSize: _isRolling ? 28 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: !_isRolling
                                      ? _difficultyColor(_selectedDifficulty)
                                      : (isDark
                                          ? Colors.white60
                                          : Colors.black54),
                                ),
                              ),
                              if (_showResult) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${_pickedStudent!["user_id"]}  |  '
                                  '均分 ${(_pickedStudent!["avg_score"] as double).toStringAsFixed(1)}',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                              ],
                            ],
                          )
                        : Text('点击开始',
                            style: TextStyle(
                                fontSize: 20,
                                color:
                                    isDark ? Colors.white60 : Colors.black38)),
                  ),
                ),
                const SizedBox(height: 10),
                // 操作按钮
                if (_showResult)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _judgeAnswer(true),
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(
                            '正确 +${_scoreRules[_selectedDifficulty]!["correct"]!.toStringAsFixed(0)}'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => _judgeAnswer(false),
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(
                            '错误 ${_scoreRules[_selectedDifficulty]!["wrong"]!.toStringAsFixed(0)}'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red[400]),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => setState(() => _showResult = false),
                        child: const Text('跳过', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _isRolling ? null : _startRoll,
                        icon: Icon(
                            _isRolling ? Icons.hourglass_top : Icons.shuffle,
                            size: 18),
                        label: Text(_isRolling ? '选择中...' : '开始点名'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '目标池 ${_targetPool.length} 人 / 共 ${_allStudents.length} 人',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 1.5 点名排行榜 ──
          if (_scoreboard.isNotEmpty)
            _buildToolCard(
              title: '点名得分排行',
              icon: Icons.leaderboard,
              color: Colors.purple,
              isDark: isDark,
              child: Column(
                children: [
                  ..._scoreboard.take(10).toList().asMap().entries.map((e) {
                    final i = e.key;
                    final s = e.value;
                    final score = (s['total_score'] as num?)?.toDouble() ?? 0;
                    final calls = (s['call_count'] as int?) ?? 0;
                    final correct = (s['correct_count'] as int?) ?? 0;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: i < 3
                            ? [
                                Colors.amber,
                                Colors.grey[400]!,
                                Colors.brown[300]!
                              ][i]
                            : Colors.grey[200],
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: i < 3 ? Colors.white : Colors.black54)),
                      ),
                      title: Text(s['user_name'] as String? ?? '',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text('$calls 次点名, $correct 次正确',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                      trailing: Text(
                        '${score >= 0 ? "+" : ""}${score.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: score >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          if (_scoreboard.isNotEmpty) const SizedBox(height: 16),

          // ── 2. 快速投票 ──
          _buildToolCard(
            title: '快速投票',
            icon: Icons.poll,
            color: Colors.blue,
            isDark: isDark,
            child: _pollActive ? _buildPollResults() : _buildPollSetup(),
          ),
          const SizedBox(height: 16),

          // ── 3. 倒计时器 ──
          _buildToolCard(
            title: '倒计时器',
            icon: Icons.timer,
            color: Colors.red,
            isDark: isDark,
            child: _buildCountdown(primary, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTierChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text('$label $count人',
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildToolCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
    required Widget child,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: color)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  // ── 投票设置界面 ──

  Widget _buildPollSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _pollQuestionCtrl,
          decoration: InputDecoration(
            hintText: '输入投票问题...',
            hintStyle: const TextStyle(fontSize: 13),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        ...List.generate(
            _pollOptions.length,
            (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${String.fromCharCode(65 + i)}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: '选项${String.fromCharCode(65 + i)}',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          style: const TextStyle(fontSize: 12),
                          controller:
                              TextEditingController(text: _pollOptions[i]),
                          onChanged: (v) => _pollOptions[i] = v,
                        ),
                      ),
                      if (_pollOptions.length > 2)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () =>
                              setState(() => _pollOptions.removeAt(i)),
                        ),
                    ],
                  ),
                )),
        Row(
          children: [
            if (_pollOptions.length < 6)
              TextButton.icon(
                onPressed: () => setState(() => _pollOptions
                    .add('选项${String.fromCharCode(65 + _pollOptions.length)}')),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加选项', style: TextStyle(fontSize: 12)),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _startPoll,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('开始投票', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  // ── 投票结果界面 ──

  Widget _buildPollResults() {
    final totalVotes = _pollResults.values.fold(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_pollQuestion ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        ..._pollResults.entries.map((e) {
          final pct = totalVotes > 0 ? e.value / totalVotes : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: _pollActive ? () => _vote(e.key) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 6,
                              backgroundColor:
                                  Colors.grey.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation(
                                  Colors.blue.withValues(alpha: 0.7)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${e.value}票 (${(pct * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700])),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('总票数：$totalVotes',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const Spacer(),
            if (_pollActive)
              FilledButton.tonal(
                onPressed: _endPoll,
                child: const Text('结束投票', style: TextStyle(fontSize: 12)),
              ),
            if (!_pollActive)
              OutlinedButton(
                onPressed: _resetPoll,
                child: const Text('新建投票', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }

  // ── 倒计时界面 ──

  Widget _buildCountdown(Color primary, bool isDark) {
    return Column(
      children: [
        // 时间设置
        if (!_timerRunning && _remainingSeconds == 0) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [1, 2, 3, 5, 10, 15, 20, 30]
                .map((m) => ChoiceChip(
                      label:
                          Text('${m}分钟', style: const TextStyle(fontSize: 12)),
                      selected: _timerSeconds == m * 60,
                      onSelected: (v) => setState(() => _timerSeconds = m * 60),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          // 自定义时间输入 + 语音输入
          Form(
            key: _timerFormKey,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _customTimerController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '自定义分钟',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.graphic_eq,
                            size: 18, color: Colors.grey[600]),
                        tooltip: '语音输入',
                        onPressed: () async {
                          final text = await showDialog<String>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _VoiceTimerDialog(),
                          );
                          if (text != null && text.isNotEmpty) {
                            _customTimerController.text = text;
                          }
                        },
                      ),
                    ),
                    onFieldSubmitted: (v) => _applyCustomTimer(v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () =>
                      _applyCustomTimer(_customTimerController.text),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('确认', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 倒计时显示
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: _timerRunning
                ? (_remainingSeconds <= 30
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.05))
                : (isDark ? Colors.grey[850] : Colors.grey[50]),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            _remainingSeconds > 0
                ? _formatTime(_remainingSeconds)
                : _formatTime(_timerSeconds),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: _timerRunning
                  ? (_remainingSeconds <= 30 ? Colors.red : primary)
                  : Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 控制按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_timerRunning && _remainingSeconds == 0)
              FilledButton.icon(
                onPressed: _startCountdown,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('开始'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            if (_timerRunning) ...[
              FilledButton.tonal(
                onPressed: _pauseCountdown,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause, size: 18),
                    SizedBox(width: 4),
                    Text('暂停'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _resetCountdown,
                child: const Text('重置'),
              ),
            ],
            if (!_timerRunning && _remainingSeconds > 0) ...[
              FilledButton.icon(
                onPressed: _startCountdown,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('继续'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _resetCountdown,
                child: const Text('重置'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  语音倒计时输入对话框                                                       ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class _VoiceTimerDialog extends StatefulWidget {
  const _VoiceTimerDialog();
  @override
  State<_VoiceTimerDialog> createState() => _VoiceTimerDialogState();
}

class _VoiceTimerDialogState extends State<_VoiceTimerDialog> {
  final _idCtrl = TextEditingController();
  final _voice = VoiceService();
  bool _listening = false;
  String _heard = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _voice.onResult = (text) {
      if (!mounted) return;
      setState(() => _heard = text);
    };
    _voice.onComplete = (finalText) {
      if (!mounted) return;
      final mins = _parseMinutes(finalText);
      setState(() {
        _heard = finalText;
        if (mins != null) _idCtrl.text = '$mins';
      });
    };
    _voice.onError = (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _listening = false;
      });
    };
    _voice.onStateChanged = (listening) {
      if (!mounted) return;
      setState(() => _listening = listening);
    };
  }

  @override
  void dispose() {
    _voice.stopListening();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _voice.stopListening();
      return;
    }
    if (!await VoiceService.isConfigured()) {
      if (mounted) setState(() => _error = '语音未配置（讯飞密钥）或被禁用，请手动输入');
      return;
    }
    setState(() {
      _error = null;
      _heard = '';
    });
    await _voice.startListening();
  }

  /// 从识别文本里解析分钟数：支持阿拉伯数字与常见中文数字（一~二十）。
  int? _parseMinutes(String text) {
    final digit = RegExp(r'(\d+)').firstMatch(text);
    if (digit != null) return int.tryParse(digit.group(1)!);
    const cn = {
      '零': 0,
      '一': 1,
      '两': 2,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
    };
    // 处理"十五""二十""三十"等
    if (text.contains('十')) {
      final idx = text.indexOf('十');
      final tens = idx > 0 ? (cn[text[idx - 1]] ?? 1) : 1;
      final ones = idx + 1 < text.length ? (cn[text[idx + 1]] ?? 0) : 0;
      return tens * 10 + ones;
    }
    for (final e in cn.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.graphic_eq, size: 20),
          SizedBox(width: 8),
          Text('语音设置倒计时'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('点击麦克风说出分钟数（如"五分钟""十五分钟"），也可手动输入',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          IconButton.filled(
            onPressed: _toggleListen,
            iconSize: 36,
            style: IconButton.styleFrom(
              backgroundColor: _listening ? Colors.red : primary,
            ),
            icon: Icon(_listening ? Icons.stop : Icons.mic),
          ),
          const SizedBox(height: 8),
          if (_listening)
            const Text('正在聆听…',
                style: TextStyle(fontSize: 12, color: Colors.red)),
          if (_heard.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('识别：$_heard',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: Colors.orange)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
              hintText: '分钟数',
              prefixIcon: Icon(Icons.timer_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await _voice.stopListening();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            await _voice.stopListening();
            if (context.mounted) Navigator.pop(context, _idCtrl.text.trim());
          },
          child: const Text('确认'),
        ),
      ],
    );
  }
}
