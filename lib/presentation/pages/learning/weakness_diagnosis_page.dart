import 'package:flutter/material.dart';
import '../../../data/local/wrong_answer_dao.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/ai_service.dart';
import '../../widgets/markdown_bubble.dart';

class WeaknessDiagnosisPage extends StatefulWidget {
  /// 如果为 null，则分析当前登录用户；教师可传入学生 userId
  final String? targetUserId;

  const WeaknessDiagnosisPage({super.key, this.targetUserId});

  @override
  State<WeaknessDiagnosisPage> createState() => _WeaknessDiagnosisPageState();
}

class _WeaknessDiagnosisPageState extends State<WeaknessDiagnosisPage> {
  final _wrongAnswerDao = WrongAnswerDao();
  final _quizDao = QuizDao();
  final _learningRecordDao = LearningRecordDao();
  final _authService = AuthService();
  final _aiService = AiService();

  bool _isLoading = true;
  bool _isDiagnosing = false;
  String? _diagnosisResult;
  String? _diagnosisProvider;
  String? _diagnosisModel;
  bool _diagnosisExpanded = true;

  // ── 概览数据 ──────────────────────────────────────────────────────────
  int _totalWrongCount = 0;
  String _worstChapter = '—';
  double _masteryPercent = 100.0;
  int _quizAttempts = 0;

  // ── 章节分析数据 ──────────────────────────────────────────────────────
  List<_ChapterAnalysis> _chapterAnalyses = [];

  // ── 原始数据（供 AI 诊断使用） ────────────────────────────────────────
  // ignore: unused_field
  List<Map<String, dynamic>> _rawWrongAnswers = [];
  Map<String, dynamic> _quizSummary = {};
  Map<String, dynamic> _learningStats = {};

  String get _userId =>
      widget.targetUserId ?? _authService.getCurrentUserId() ?? '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ════════════════════════════════════════════════════════════════════════
  //  数据加载
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    if (_userId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      // 并行加载多个数据源
      final results = await Future.wait([
        _wrongAnswerDao.getWrongAnswers(_userId),
        _quizDao.getQuizResults(_userId),
        _quizDao.getQuizSummary(_userId),
        _learningRecordDao.getStatistics(_userId),
      ]);

      final wrongAnswers = results[0] as List<Map<String, dynamic>>;
      final quizResults = results[1] as List;
      final quizSummary = results[2] as Map<String, dynamic>;
      final learningStats = results[3] as Map<String, dynamic>;

      // ── 按章节分组错题 ─────────────────────────────────────────────
      final chapterWrongMap = <String, List<Map<String, dynamic>>>{};
      for (final wrong in wrongAnswers) {
        final chapter = (wrong['chapter'] as String?) ?? '未分类';
        chapterWrongMap.putIfAbsent(chapter, () => []).add(wrong);
      }

      // ── 按章节统计测验数据 ──────────────────────────────────────────
      final chapterQuizMap = <String, _ChapterQuizStats>{};
      for (final r in quizResults) {
        final map = r is Map<String, dynamic> ? r : (r as dynamic).toMap() as Map<String, dynamic>;
        final chapter = (map['chapter'] as String?) ?? '综合测验';
        final stats = chapterQuizMap.putIfAbsent(
            chapter, () => _ChapterQuizStats());
        stats.totalCorrect += (map['num_correct'] as int?) ?? 0;
        stats.totalQuestions += (map['num_total'] as int?) ?? 0;
        stats.attempts += 1;
      }

      // ── 构建章节分析列表 ───────────────────────────────────────────
      final allChapters = <String>{
        ...chapterWrongMap.keys,
        ...chapterQuizMap.keys,
      };

      final analyses = <_ChapterAnalysis>[];
      for (final chapter in allChapters) {
        final wrongs = chapterWrongMap[chapter] ?? [];
        final quizStats = chapterQuizMap[chapter];
        final totalQ = quizStats?.totalQuestions ?? 0;
        final totalC = quizStats?.totalCorrect ?? 0;
        final errorRate = totalQ > 0 ? (totalQ - totalC) / totalQ : 0.0;

        // 找出最常错（times 最高）的题目
        final sortedWrongs = List<Map<String, dynamic>>.from(wrongs)
          ..sort((a, b) =>
              ((b['times'] as int?) ?? 1).compareTo((a['times'] as int?) ?? 1));
        final topMistakes = sortedWrongs.take(3).toList();

        analyses.add(_ChapterAnalysis(
          chapter: chapter,
          wrongCount: wrongs.length,
          errorRate: errorRate,
          mastery: 1.0 - errorRate,
          quizAttempts: quizStats?.attempts ?? 0,
          topMistakes: topMistakes,
        ));
      }

      // 按错题数量降序排列
      analyses.sort((a, b) => b.wrongCount.compareTo(a.wrongCount));

      // ── 计算概览指标 ───────────────────────────────────────────────
      final totalWrong = wrongAnswers.length;
      final worstChapter = analyses.isNotEmpty ? analyses.first.chapter : '—';
      final totalQuestions =
          (quizSummary['total_questions'] as num?)?.toInt() ?? 0;
      final totalCorrect =
          (quizSummary['total_correct'] as num?)?.toInt() ?? 0;
      final mastery =
          totalQuestions > 0 ? (totalCorrect / totalQuestions) * 100 : 100.0;
      final attempts =
          (quizSummary['total_count'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      setState(() {
        _rawWrongAnswers = wrongAnswers;
        _quizSummary = quizSummary;
        _learningStats = learningStats;
        _totalWrongCount = totalWrong;
        _worstChapter = worstChapter;
        _masteryPercent = mastery;
        _quizAttempts = attempts;
        _chapterAnalyses = analyses;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据加载失败: $e')),
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  AI 智能诊断
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _runDiagnosis() async {
    if (_isDiagnosing) return;
    setState(() {
      _isDiagnosing = true;
      _diagnosisResult = null;
      _diagnosisProvider = null;
      _diagnosisModel = null;
    });

    try {
      final result = await _tryAiDiagnosis();
      if (!mounted) return;
      setState(() {
        _diagnosisResult = result.content;
        _diagnosisProvider = result.provider;
        _diagnosisModel = result.model;
        _diagnosisExpanded = true;
        _isDiagnosing = false;
      });
    } catch (_) {
      // AI 不可用，使用本地算法
      final fallback = _localDiagnosis();
      if (!mounted) return;
      setState(() {
        _diagnosisResult = fallback;
        _diagnosisProvider = null;
        _diagnosisModel = null;
        _diagnosisExpanded = true;
        _isDiagnosing = false;
      });
    }
  }

  /// 尝试调用 AI 进行诊断；如果 AI 未配置或失败则抛出异常
  Future<AiChatResult> _tryAiDiagnosis() async {
    // 构建数据摘要发送给 AI
    final wrongSummary = StringBuffer();
    for (final analysis in _chapterAnalyses) {
      wrongSummary.writeln(
          '- ${analysis.chapter}：${analysis.wrongCount} 道错题，'
          '错误率 ${(analysis.errorRate * 100).toStringAsFixed(1)}%');
      for (final m in analysis.topMistakes) {
        final q = m['question'] ?? '';
        final times = m['times'] ?? 1;
        wrongSummary.writeln('  * 错 $times 次: $q');
      }
    }

    final totalRecords = _learningStats['total_records'] ?? 0;
    final uniqueNodes = _learningStats['unique_nodes'] ?? 0;
    final avgScore =
        (_quizSummary['avg_score'] as num?)?.toStringAsFixed(1) ?? '0';

    final dataPrompt = '''
以下是学生的学习数据：

【测验概况】
- 测验次数：$_quizAttempts
- 平均分：$avgScore
- 掌握率：${_masteryPercent.toStringAsFixed(1)}%

【学习记录】
- 总学习记录：$totalRecords
- 已学习节点：$uniqueNodes

【各章节错题分析】
$wrongSummary

请根据以上数据：
1. 分析学生的知识薄弱点（按严重程度排序）
2. 找出反复出错的知识点模式
3. 给出具体的学习建议和复习策略
4. 推荐优先学习的章节顺序

请用中文回答，条理清晰，使用编号列表。
''';

    return await _aiService.chatWithMeta(
      [
        {'role': 'user', 'content': dataPrompt},
      ],
      systemPrompt: '你是一位经验丰富的移动应用开发课程教师，擅长分析学生的学习数据，'
          '找出知识薄弱环节并提供有针对性的学习建议。请根据数据给出专业分析。',
    );
  }

  /// 本地离线诊断算法（AI 不可用时的 fallback）
  String _localDiagnosis() {
    final buffer = StringBuffer();
    buffer.writeln('【本地诊断报告】');
    buffer.writeln('（未配置 AI 服务，使用本地分析算法）\n');

    if (_chapterAnalyses.isEmpty) {
      buffer.writeln('暂无错题数据，无法进行薄弱点诊断。');
      buffer.writeln('建议先完成各章节测验，积累学习数据后再进行诊断。');
      return buffer.toString();
    }

    // 1. 按错误数量排序的薄弱章节
    buffer.writeln('一、知识薄弱点排序\n');
    for (var i = 0; i < _chapterAnalyses.length; i++) {
      final a = _chapterAnalyses[i];
      final severity = a.errorRate > 0.5
          ? '严重'
          : a.errorRate > 0.3
              ? '中等'
              : '轻微';
      buffer.writeln(
          '${i + 1}. ${a.chapter}（$severity）'
          '— 错题 ${a.wrongCount} 道，'
          '错误率 ${(a.errorRate * 100).toStringAsFixed(1)}%');
    }

    // 2. 高频错题
    buffer.writeln('\n二、高频重复错题\n');
    final allMistakes = <Map<String, dynamic>>[];
    for (final a in _chapterAnalyses) {
      allMistakes.addAll(a.topMistakes);
    }
    allMistakes
        .sort((a, b) => ((b['times'] as int?) ?? 1).compareTo((a['times'] as int?) ?? 1));
    final topRepeated = allMistakes.take(5);
    if (topRepeated.isEmpty) {
      buffer.writeln('暂无重复错题数据。');
    } else {
      for (final m in topRepeated) {
        final q = (m['question'] as String?) ?? '';
        final displayQ = q.length > 50 ? '${q.substring(0, 50)}...' : q;
        buffer.writeln('- 错 ${m['times'] ?? 1} 次：$displayQ');
      }
    }

    // 3. 学习建议
    buffer.writeln('\n三、学习建议\n');
    final severeChapters =
        _chapterAnalyses.where((a) => a.errorRate > 0.5).toList();
    final moderateChapters = _chapterAnalyses
        .where((a) => a.errorRate > 0.3 && a.errorRate <= 0.5)
        .toList();

    if (severeChapters.isNotEmpty) {
      for (final c in severeChapters) {
        buffer.writeln('- 建议重点复习「${c.chapter}」的相关知识点，'
            '该章节错误率高达 ${(c.errorRate * 100).toStringAsFixed(0)}%');
      }
    }
    if (moderateChapters.isNotEmpty) {
      for (final c in moderateChapters) {
        buffer.writeln('- 建议加强巩固「${c.chapter}」的核心概念，'
            '错误率为 ${(c.errorRate * 100).toStringAsFixed(0)}%');
      }
    }

    if (topRepeated.isNotEmpty) {
      buffer.writeln('- 建议针对高频错题进行专项练习，避免同类错误反复出现');
    }

    if (_quizAttempts < 3) {
      buffer.writeln('- 测验次数较少（$_quizAttempts 次），建议增加测验频次以更准确评估掌握情况');
    }

    final totalRecords = _learningStats['total_records'] ?? 0;
    if ((totalRecords as int) < 5) {
      buffer.writeln('- 学习记录较少，建议通过知识图谱系统学习更多知识节点');
    }

    // 4. 推荐复习顺序
    buffer.writeln('\n四、推荐复习顺序\n');
    for (var i = 0; i < _chapterAnalyses.length; i++) {
      buffer.writeln('${i + 1}. ${_chapterAnalyses[i].chapter}');
    }

    return buffer.toString();
  }

  // ════════════════════════════════════════════════════════════════════════
  //  UI 构建
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isViewingOther = widget.targetUserId != null &&
        widget.targetUserId != _authService.getCurrentUserId();

    return Scaffold(
      appBar: AppBar(
        title: Text(isViewingOther
            ? '学生薄弱点诊断 ($_userId)'
            : '知识薄弱点诊断'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新数据',
              onPressed: _loadData,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOverviewCards(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('章节分析', Icons.analytics),
                    const SizedBox(height: 12),
                    _buildChapterAnalysisList(),
                    const SizedBox(height: 24),
                    _buildDiagnosisSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ── 概览卡片 ─────────────────────────────────────────────────────────

  Widget _buildOverviewCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildOverviewCard(
                title: '错题总数',
                value: '$_totalWrongCount',
                icon: Icons.error_outline,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildOverviewCard(
                title: '最薄弱章节',
                value: _worstChapter.length > 6
                    ? '${_worstChapter.substring(0, 6)}...'
                    : _worstChapter,
                icon: Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildOverviewCard(
                title: '掌握率',
                value: '${_masteryPercent.toStringAsFixed(1)}%',
                icon: Icons.check_circle_outline,
                color: _masteryPercent >= 70 ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildOverviewCard(
                title: '测验次数',
                value: '$_quizAttempts',
                icon: Icons.quiz_outlined,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOverviewCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 段落标题 ─────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ── 章节分析列表 ─────────────────────────────────────────────────────

  Widget _buildChapterAnalysisList() {
    if (_chapterAnalyses.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.emoji_events, size: 48, color: Colors.amber),
                SizedBox(height: 12),
                Text(
                  '暂无错题数据',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                SizedBox(height: 4),
                Text(
                  '完成章节测验后即可查看薄弱点分析',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: _chapterAnalyses.map((analysis) {
        return _buildChapterCard(analysis);
      }).toList(),
    );
  }

  Widget _buildChapterCard(_ChapterAnalysis analysis) {
    final primary = Theme.of(context).colorScheme.primary;
    final errorColor = analysis.errorRate > 0.5
        ? Colors.red
        : analysis.errorRate > 0.3
            ? Colors.orange
            : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: errorColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '${analysis.wrongCount}',
              style: TextStyle(
                color: errorColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        title: Text(
          analysis.chapter,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '错误率 ${(analysis.errorRate * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, color: errorColor),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '测验 ${analysis.quizAttempts} 次',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 掌握度进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: analysis.mastery.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    analysis.mastery >= 0.7
                        ? Colors.green
                        : analysis.mastery >= 0.5
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '掌握度 ${(analysis.mastery * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        children: [
          if (analysis.topMistakes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 4),
                  Text(
                    '常见错题',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...analysis.topMistakes.map((m) {
                    final question = (m['question'] as String?) ?? '';
                    final times = (m['times'] as int?) ?? 1;
                    final userAnswer = (m['user_answer'] as String?) ?? '';
                    final correctAnswer =
                        (m['correct_answer'] as String?) ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    question,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '错$times次',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (userAnswer.isNotEmpty ||
                                correctAnswer.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (userAnswer.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        '你的答案: $userAnswer',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (correctAnswer.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        '正确答案: $correctAnswer',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                '该章节暂无详细错题记录',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  // ── AI 诊断区域 ──────────────────────────────────────────────────────

  Widget _buildDiagnosisSection() {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('智能诊断', Icons.psychology),
        const SizedBox(height: 12),

        // 诊断按钮
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isDiagnosing ? null : _runDiagnosis,
            icon: _isDiagnosing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_isDiagnosing ? '正在分析中...' : 'AI 智能诊断'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        if (_isDiagnosing) ...[
          const SizedBox(height: 16),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    '正在分析学习数据...',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '综合错题、测验成绩和学习记录进行诊断',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],

        // 诊断结果
        if (_diagnosisResult != null && !_isDiagnosing) ...[
          const SizedBox(height: 16),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // 结果标题栏
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primary.withValues(alpha: 0.1),
                        primary.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _diagnosisExpanded = !_diagnosisExpanded;
                      });
                    },
                    child: Row(
                      children: [
                        Icon(Icons.assignment, color: primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '诊断报告',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ),
                        Icon(
                          _diagnosisExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: primary,
                        ),
                      ],
                    ),
                  ),
                ),
                // 结果内容
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: _diagnosisExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MarkdownBubble(
                      content: _diagnosisResult!,
                      provider: _diagnosisProvider,
                      model: _diagnosisModel,
                    ),
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

}

// ══════════════════════════════════════════════════════════════════════════
//  辅助数据类
// ══════════════════════════════════════════════════════════════════════════

class _ChapterAnalysis {
  final String chapter;
  final int wrongCount;
  final double errorRate;
  final double mastery;
  final int quizAttempts;
  final List<Map<String, dynamic>> topMistakes;

  const _ChapterAnalysis({
    required this.chapter,
    required this.wrongCount,
    required this.errorRate,
    required this.mastery,
    required this.quizAttempts,
    required this.topMistakes,
  });
}

class _ChapterQuizStats {
  int totalCorrect = 0;
  int totalQuestions = 0;
  int attempts = 0;
}
