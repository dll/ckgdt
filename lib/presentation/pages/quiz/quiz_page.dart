import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/wrong_answer_dao.dart';
import '../../../data/models/question_model.dart';
import '../../../data/models/quiz_result_model.dart';
import '../../../services/ai_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/tts_flutter_service.dart';
import '../../widgets/agent_entry_button.dart';
import '../admin/question_manage_page.dart';
import '../analytics/learning_analytics_page.dart';
import '../learning/video_page.dart';
import '../practice/deep_practice_page.dart';
import 'wrong_answers_page.dart';

class QuizPage extends StatefulWidget {
  final bool embedded;

  const QuizPage({super.key, this.embedded = false});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final _quizDao = QuizDao();
  final _wrongAnswerDao = WrongAnswerDao();
  final _authService = AuthService();

  List<String> _chapters = [];
  String? _selectedChapter;
  List<QuestionModel> _questions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _answered = false;
  int _correctCount = 0;
  bool _isLoading = true;
  bool _quizStarted = false;

  // ── 教师数据 ───────────────────────────────────────────────
  Map<String, dynamic> _classOverview = {};
  List<Map<String, dynamic>> _chapterPerformance = [];
  List<Map<String, dynamic>> _recentResults = [];
  List<Map<String, dynamic>> _chapterStats = [];

  bool get _isTeacherOrAdmin =>
      _authService.isTeacher || _authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadChapters();
    if (_isTeacherOrAdmin) {
      _loadTeacherData();
    }
  }

  Future<void> _loadChapters() async {
    setState(() => _isLoading = true);
    try {
      final chapters = await _quizDao.getChapters();
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTeacherData() async {
    try {
      final overview = await _quizDao.getClassQuizOverview();
      final chPerf = await _quizDao.getChapterQuizPerformance();
      final recent = await _quizDao.getRecentAllResults(limit: 20);
      final chStats = await _quizDao.getChapterStats();
      if (mounted) {
        setState(() {
          _classOverview = overview;
          _chapterPerformance = chPerf;
          _recentResults = recent;
          _chapterStats = chStats;
        });
      }
    } catch (_) {}
  }

  Future<void> _startQuiz(String chapter) async {
    setState(() {
      _selectedChapter = chapter;
      _isLoading = true;
    });

    try {
      final questions = await _quizDao.getQuestionsByChapter(chapter);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _quizStarted = true;
        _currentIndex = 0;
        _correctCount = 0;
        _selectedAnswer = null;
        _answered = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _submitAnswer() {
    if (_selectedAnswer == null) return;

    final currentQuestion = _questions[_currentIndex];
    final isCorrect = _selectedAnswer == currentQuestion.answerIndex;

    if (!isCorrect) {
      _recordWrongAnswer(currentQuestion);
    }

    setState(() {
      _answered = true;
      if (isCorrect) _correctCount++;
    });
  }

  Future<void> _recordWrongAnswer(QuestionModel question) async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final options = question.options;
        final userAnswerText =
            _selectedAnswer != null && _selectedAnswer! < options.length
                ? options[_selectedAnswer!]
                : '';
        final correctAnswerText = question.correctAnswer;
        final recordId = await _wrongAnswerDao.addWrongAnswer(
          userId: user.userId,
          questionId: question.id ?? 0,
          question: question.question,
          userAnswer: userAnswerText,
          correctAnswer: correctAnswerText,
          chapter: _selectedChapter ?? '',
        );
        // 异步生成 AI 解释（不阻塞答题流程）
        _generateExplanation(
          recordId: recordId,
          questionText: question.question,
          userAnswer: userAnswerText,
          correctAnswer: correctAnswerText,
          chapter: _selectedChapter ?? '',
        );
      }
    } catch (e) {
      // 忽略错误
    }
  }

  /// 后台异步生成错题 AI 解释
  Future<void> _generateExplanation({
    required int recordId,
    required String questionText,
    required String userAnswer,
    required String correctAnswer,
    required String chapter,
  }) async {
    try {
      final aiService = AiService();

      final prompt =
          '题目：$questionText\n学生答案：$userAnswer\n正确答案：$correctAnswer\n章节：$chapter\n\n'
          '请用 2-3 句话简明解释为什么正确答案是对的，以及学生答案错在哪里。'
          '语言要通俗易懂，适合大学生阅读。不要重复题目内容。';

      final explanation = await aiService.chat(
        [{'role': 'user', 'content': prompt}],
        systemPrompt: '你是一位移动应用开发课程的教学助手，专门为学生解释测验错题。回答要简洁精准。',
      );

      if (explanation.isNotEmpty) {
        await _wrongAnswerDao.updateExplanation(recordId, explanation);
      }
    } catch (_) {
      // AI 解释是增值功能，失败不影响主流程
    }
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _answered = false;
      });
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final user = _authService.currentUser;
    if (user == null) return;

    final result = QuizResultModel(
      userId: user.userId,
      quizTimestamp: DateTime.now().toIso8601String(),
      score: ((_correctCount / _questions.length) * 100).round(),
      numCorrect: _correctCount,
      numTotal: _questions.length,
      chapter: _selectedChapter,
      completedAt: DateTime.now().toIso8601String(),
    );

    await _quizDao.saveQuizResult(result);

    // 语音播报测验结果
    final wrongCount = _questions.length - _correctCount;
    final voiceText = wrongCount == 0
        ? '恭喜你，全部答对！得分${result.score}分。'
        : '测验完成，得分${result.score}分，答对${_correctCount}题，答错${wrongCount}题。'
            '错题已自动收录到错题本并生成解析。';
    TtsFlutterService.instance.speak(voiceText);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('测验完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _correctCount > _questions.length / 2
                    ? Icons.celebration
                    : Icons.sentiment_neutral,
                size: 64,
                color: _correctCount > _questions.length / 2
                    ? Colors.green
                    : Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                '得分: ${result.score}分',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text('正确: $_correctCount / ${_questions.length}'),
              if (wrongCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '错题已收录并生成 AI 解析',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '继续学习',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (_correctCount < _questions.length)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _quizStarted = false;
                    _questions = [];
                  });
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WrongAnswersPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.error_outline, size: 18),
                label: const Text('复习错题'),
              ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _quizStarted = false;
                  _questions = [];
                });
                TtsFlutterService.instance.speak('正在进入深度实践，巩固所学知识');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DeepPracticePage(),
                  ),
                );
              },
              icon: const Icon(Icons.fitness_center, size: 18),
              label: const Text('深入实践'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _quizStarted = false;
                  _questions = [];
                });
                TtsFlutterService.instance.speak('正在打开扩展视频，拓宽知识面');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoListPage(
                      filterChapter: _selectedChapter,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('扩展视频'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _quizStarted = false;
                  _questions = [];
                });
              },
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_quizStarted && _questions.isNotEmpty) {
      // 如果在答题中，显示答题视图（不论角色）
      body = _buildQuizView();
    } else if (_isTeacherOrAdmin) {
      // 教师/管理员 → 教学管理仪表板
      body = _buildTeacherDashboard();
    } else {
      // 学生 → 章节选择
      body = _buildChapterSelection();
    }

    // 嵌入在 Tab 中时直接返回内容，独立页面时包裹 Scaffold
    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('章节测验'),
        actions: const [AgentEntryButton(agentId: 'quiz')],
      ),
      body: body,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 教师仪表板
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTeacherDashboard() {
    final primary = Theme.of(context).colorScheme.primary;
    final gradient = AppGradientTheme.of(context);

    final studentCount =
        (_classOverview['student_count'] as num?)?.toInt() ?? 0;
    final avgScore =
        (_classOverview['avg_score'] as num?)?.toDouble() ?? 0.0;
    final passRate =
        (_classOverview['pass_rate'] as num?)?.toDouble() ?? 0.0;

    // 题库统计
    int totalQuestions = 0;
    for (final s in _chapterStats) {
      totalQuestions += (s['count'] as num?)?.toInt() ?? 0;
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadChapters();
        await _loadTeacherData();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 渐变头部卡片 ──────────────────────────────────────
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: gradient.linearGradient,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.quiz,
                              size: 28, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '测验管理中心',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '出题 · 成绩统计 · 学情分析',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 四个统计数值
                    Row(
                      children: [
                        _buildHeaderStat('题库总量', '$totalQuestions'),
                        _buildHeaderStat('参加人数', '$studentCount'),
                        _buildHeaderStat(
                          '平均分',
                          avgScore.toStringAsFixed(1),
                        ),
                        _buildHeaderStat(
                          '及格率',
                          '${passRate.toStringAsFixed(0)}%',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── 快捷操作按钮 ──────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.edit_note,
                    label: '题库管理',
                    color: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const QuestionManagePage()),
                    ).then((_) => _loadTeacherData()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.analytics,
                    label: '学情分析',
                    color: Colors.green,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LearningAnalyticsPage()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.play_arrow,
                    label: '体验测验',
                    color: primary,
                    onTap: () {
                      if (_chapters.isNotEmpty) {
                        _showChapterPickerForTeacher();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('暂无测验题目')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 各章节测验情况 ────────────────────────────────────
            _buildSectionTitle('各章节测验情况', Icons.bar_chart),
            const SizedBox(height: 8),

            if (_chapterPerformance.isEmpty && _chapterStats.isEmpty)
              _buildEmptyHint('暂无测验数据')
            else
              ..._buildChapterCards(),

            const SizedBox(height: 24),

            // ── 最近测验记录 ──────────────────────────────────────
            _buildSectionTitle('最近测验记录', Icons.history),
            const SizedBox(height: 8),

            if (_recentResults.isEmpty)
              _buildEmptyHint('暂无学生测验记录')
            else
              ..._recentResults.take(10).map(_buildRecentResultTile),

            if (_recentResults.length > 10)
              Center(
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LearningAnalyticsPage()),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('查看全部'),
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 20, color: primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildEmptyHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  List<Widget> _buildChapterCards() {
    // 合并题库统计和测验成绩数据
    // chapterStats: [{source, count}]
    // chapterPerformance: [{chapter, attempt_count, student_count, avg_score, pass_rate, max_score, min_score}]

    final perfMap = <String, Map<String, dynamic>>{};
    for (final p in _chapterPerformance) {
      final ch = p['chapter'] as String? ?? '';
      if (ch.isNotEmpty) perfMap[ch] = p;
    }

    // 收集所有章节（题库中有题的 + 有成绩的）
    final allChapters = <String>{};
    for (final s in _chapterStats) {
      final src = s['source'] as String? ?? '';
      if (src.isNotEmpty) allChapters.add(src);
    }
    for (final ch in perfMap.keys) {
      allChapters.add(ch);
    }

    final chapterList = allChapters.toList()..sort();

    // 题目数 map
    final questionCountMap = <String, int>{};
    for (final s in _chapterStats) {
      final src = s['source'] as String? ?? '';
      questionCountMap[src] = (s['count'] as num?)?.toInt() ?? 0;
    }

    return chapterList.map((chapter) {
      final qCount = questionCountMap[chapter] ?? 0;
      final perf = perfMap[chapter];
      final hasPerf = perf != null;
      final avgScore =
          hasPerf ? (perf['avg_score'] as num?)?.toDouble() ?? 0.0 : 0.0;
      final passRate =
          hasPerf ? (perf['pass_rate'] as num?)?.toDouble() ?? 0.0 : 0.0;
      final attempts =
          hasPerf ? (perf['attempt_count'] as num?)?.toInt() ?? 0 : 0;
      final students =
          hasPerf ? (perf['student_count'] as num?)?.toInt() ?? 0 : 0;
      final maxScore =
          hasPerf ? (perf['max_score'] as num?)?.toInt() ?? 0 : 0;
      final minScore =
          hasPerf ? (perf['min_score'] as num?)?.toInt() ?? 0 : 0;

      // 平均分对应颜色
      Color scoreColor;
      if (!hasPerf) {
        scoreColor = Colors.grey;
      } else if (avgScore >= 80) {
        scoreColor = Colors.green;
      } else if (avgScore >= 60) {
        scoreColor = Colors.orange;
      } else {
        scoreColor = Colors.red;
      }

      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 章节名
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      chapter,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$qCount 题',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              if (hasPerf) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMiniStat(
                        '平均分', avgScore.toStringAsFixed(1), scoreColor),
                    _buildMiniStat(
                        '及格率', '${passRate.toStringAsFixed(0)}%',
                        passRate >= 60 ? Colors.green : Colors.red),
                    _buildMiniStat('参加', '$students人', Colors.blue),
                    _buildMiniStat('测验', '$attempts次', Colors.purple),
                  ],
                ),
                const SizedBox(height: 8),
                // 分数范围条
                Row(
                  children: [
                    Text('最低 $minScore分',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    const Spacer(),
                    Text('最高 $maxScore分',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: avgScore / 100,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation(scoreColor),
                    minHeight: 6,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  '暂无学生测验数据',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRecentResultTile(Map<String, dynamic> result) {
    final userId = result['user_id'] as String? ?? '';
    final realName = result['real_name'] as String?;
    final displayName = (realName != null && realName.isNotEmpty)
        ? realName
        : userId;
    final score = (result['score'] as num?)?.toInt() ?? 0;
    final chapter = result['chapter'] as String? ?? '未知章节';
    final numCorrect = (result['num_correct'] as num?)?.toInt() ?? 0;
    final numTotal = (result['num_total'] as num?)?.toInt() ?? 0;
    final timestamp = result['quiz_timestamp'] as String? ??
        result['completed_at'] as String? ??
        '';

    // 格式化时间
    String timeStr = '';
    if (timestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(timestamp);
        timeStr =
            '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        timeStr = timestamp;
      }
    }

    Color scoreColor;
    if (score >= 80) {
      scoreColor = Colors.green;
    } else if (score >= 60) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scoreColor.withValues(alpha: 0.15),
          child: Text(
            '$score',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: scoreColor,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '$chapter · $numCorrect/$numTotal · $timeStr',
          style: const TextStyle(fontSize: 12),
        ),
        dense: true,
      ),
    );
  }

  /// 教师选择章节体验测验
  void _showChapterPickerForTeacher() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择章节体验测验',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '以教师身份体验学生的测验流程',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ..._chapters.map((chapter) => ListTile(
                  leading: const Icon(Icons.quiz, color: Colors.orange),
                  title: Text(chapter),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () {
                    Navigator.pop(context);
                    _startQuiz(chapter);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 学生：章节选择
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChapterSelection() {
    if (_chapters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '暂无测验题目',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadChapters,
              child: const Text('刷新'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '选择测验章节',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ..._chapters.map((chapter) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.quiz, color: Colors.white),
                ),
                title: Text(chapter),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => _startQuiz(chapter),
              ),
            )),
        const SizedBox(height: 24),
        // 错题本按钮
        Card(
          color: Colors.red[50],
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red,
              child: const Icon(Icons.error, color: Colors.white),
            ),
            title: const Text('错题本'),
            subtitle: const Text('查看和复习做错的题目'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WrongAnswersPage()),
              );
            },
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 共用：答题视图
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildQuizView() {
    final question = _questions[_currentIndex];

    return Column(
      children: [
        // 进度条
        LinearProgressIndicator(
          value: (_currentIndex + 1) / _questions.length,
          backgroundColor: Colors.grey[200],
          valueColor:
              AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '第 ${_currentIndex + 1} / ${_questions.length} 题',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const Spacer(),
                    if (_isTeacherOrAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '教师体验模式',
                          style: TextStyle(fontSize: 11, color: Colors.blue),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  question.question,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                ...List.generate(4, (index) {
                  final options = question.options;
                  final isSelected = _selectedAnswer == index;
                  final isCorrect = index == question.answerIndex;

                  Color? bgColor;
                  Color? borderColor;

                  if (_answered) {
                    if (isCorrect) {
                      bgColor = Colors.green[100];
                      borderColor = Colors.green;
                    } else if (isSelected && !isCorrect) {
                      bgColor = Colors.red[100];
                      borderColor = Colors.red;
                    }
                  } else if (isSelected) {
                    bgColor = Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3);
                    borderColor = Theme.of(context).colorScheme.primary;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: _answered
                          ? null
                          : () {
                              setState(() => _selectedAnswer = index);
                            },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: bgColor,
                          border: Border.all(
                            color: borderColor ?? Colors.grey[300]!,
                            width:
                                isSelected || (_answered && isCorrect) ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: borderColor ?? Colors.grey,
                                ),
                                color: isSelected ? borderColor : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(options[index])),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // 底部按钮
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 返回按钮（退出测验）
              if (_isTeacherOrAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _quizStarted = false;
                        _questions = [];
                      });
                    },
                    child: const Text('退出'),
                  ),
                ),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _answered
                        ? _nextQuestion
                        : (_selectedAnswer != null ? _submitAnswer : null),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_answered
                        ? (_currentIndex < _questions.length - 1
                            ? '下一题'
                            : '完成测验')
                        : '提交答案'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
