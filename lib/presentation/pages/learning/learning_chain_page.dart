import 'package:flutter/material.dart';
import '../../../core/constants/chapter_helper.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../quiz/quiz_page.dart';
import 'video_page.dart';
import '../materials/resource_viewer_page.dart';

/// 学习链路页面 — 从知识概念出发，打通 概念理解→视频→课件→测验 的完整学习闭环
class LearningChainPage extends StatefulWidget {
  final int conceptId;
  final String conceptName;
  final int? chapter;
  final String? description;
  final String? keywords;

  const LearningChainPage({
    super.key,
    required this.conceptId,
    required this.conceptName,
    this.chapter,
    this.description,
    this.keywords,
  });

  @override
  State<LearningChainPage> createState() => _LearningChainPageState();
}

class _LearningChainPageState extends State<LearningChainPage>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _recordDao = LearningRecordDao();
  final _courseContext = CourseContextService();

  bool _isLoading = true;

  // 各环节资源统计
  int _videoCount = 0;
  int _pptCount = 0;
  int _pdfCount = 0;
  int _quizCount = 0;
  int _quizDoneCount = 0; // 该章节已完成的测验次数

  // 学习状态
  bool _conceptLearned = false; // 概念已学习
  bool _videoWatched = false; // 视频已观看
  bool _coursewareRead = false; // 课件已阅读
  bool _quizPassed = false; // 测验已通过

  late AnimationController _animCtrl;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _progressAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  String _chapterFilter(int chapter) {
    return ChapterHelper.shortTitle(chapter);
  }

  String _likeClause(String column, int count) {
    return List.filled(count, '$column LIKE ?').join(' OR ');
  }

  Future<int> _countScoped({
    required String table,
    required String extraWhere,
    required List<Object?> extraArgs,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: extraWhere,
      extraArgs: extraArgs,
    );
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $table WHERE ${scope.where}',
      scope.args,
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final user = _authService.currentUser;
      final userId = user?.userId ?? '';
      final ch = widget.chapter;

      _videoCount = 0;
      _pptCount = 0;
      _pdfCount = 0;
      _quizCount = 0;
      _quizDoneCount = 0;
      _videoWatched = false;
      _coursewareRead = false;
      _quizPassed = false;

      if (ch != null) {
        final chapterPatterns = await _courseContext.chapterQueryPatterns(ch);
        final chapterWhere = _likeClause('chapter', chapterPatterns.length);
        final sourceWhere = _likeClause('source', chapterPatterns.length);

        // 统计资源数量
        _videoCount = await _countScoped(
          table: 'resource_files',
          extraWhere: "file_type = 'video' AND ($chapterWhere)",
          extraArgs: chapterPatterns,
        );

        _pptCount = await _countScoped(
          table: 'resource_files',
          extraWhere: "file_type = 'ppt' AND ($chapterWhere)",
          extraArgs: chapterPatterns,
        );

        _pdfCount = await _countScoped(
          table: 'resource_files',
          extraWhere: "file_type = 'pdf' AND ($chapterWhere)",
          extraArgs: chapterPatterns,
        );

        // 查询该章节题目数量
        _quizCount = await _countScoped(
          table: 'questions',
          extraWhere: sourceWhere,
          extraArgs: chapterPatterns,
        );

        // 查询该章节已完成的测验
        if (userId.isNotEmpty) {
          _quizDoneCount = await _countScoped(
            table: 'quiz_results',
            extraWhere: 'user_id = ? AND ($chapterWhere)',
            extraArgs: [userId, ...chapterPatterns],
          );
        }
      }

      // 检查概念学习状态
      if (userId.isNotEmpty) {
        _conceptLearned = await _recordDao.hasLearned(
          userId,
          'c_${widget.conceptId}',
        );

        // 检查是否有该章节相关的学习记录（视频/课件）
        if (ch != null) {
          final videoScope = await _courseContext.scopedWhere(
            extraWhere: 'user_id = ? AND node_id LIKE ?',
            extraArgs: [userId, 'video_ch$ch%'],
          );
          final videoRecords = await db.rawQuery(
            'SELECT COUNT(*) as c FROM learning_records WHERE ${videoScope.where}',
            videoScope.args,
          );
          _videoWatched = ((videoRecords.first['c'] as int?) ?? 0) > 0;

          final coursewareScope = await _courseContext.scopedWhere(
            extraWhere: 'user_id = ? AND (node_id LIKE ? OR node_id LIKE ?)',
            extraArgs: [userId, 'ppt_ch$ch%', 'pdf_ch$ch%'],
          );
          final coursewareRecords = await db.rawQuery(
            'SELECT COUNT(*) as c FROM learning_records WHERE ${coursewareScope.where}',
            coursewareScope.args,
          );
          _coursewareRead = ((coursewareRecords.first['c'] as int?) ?? 0) > 0;

          _quizPassed = _quizDoneCount > 0;
        }
      }

      setState(() => _isLoading = false);
      _animCtrl.forward();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// 记录概念学习
  Future<void> _markConceptLearned() async {
    final user = _authService.currentUser;
    if (user == null) return;
    try {
      await _recordDao.addRecord(
        userId: user.userId,
        nodeId: 'c_${widget.conceptId}',
        nodeTitle: widget.conceptName,
      );
      setState(() => _conceptLearned = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已标记「${widget.conceptName}」为已学习'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {}
  }

  int get _completedSteps {
    int count = 0;
    if (_conceptLearned) count++;
    if (_videoWatched) count++;
    if (_coursewareRead) count++;
    if (_quizPassed) count++;
    return count;
  }

  double get _overallProgress => _completedSteps / 4.0;

  @override
  Widget build(BuildContext context) {
    final ch = widget.chapter;
    final chColor = ch != null
        ? (ChapterHelper.chapterColors[ch] ??
            Theme.of(context).colorScheme.primary)
        : Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习链路'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 概念信息卡片 ──
                  _buildConceptCard(chColor),
                  const SizedBox(height: 20),

                  // ── 总进度条 ──
                  _buildProgressOverview(chColor),
                  const SizedBox(height: 24),

                  // ── 学习链路步骤 ──
                  const Text(
                    '学习步骤',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStepTimeline(chColor),
                ],
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 概念信息卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildConceptCard(Color chColor) {
    final ch = widget.chapter;
    final icon = ch != null
        ? (ChapterHelper.chapterIcons[ch] ?? Icons.school)
        : Icons.school;
    final logos =
        ch != null ? (ChapterHelper.chapterLogos[ch] ?? []) : <String>[];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [chColor, chColor.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.conceptName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ch != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          ChapterHelper.fullTitle(ch),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (widget.description != null &&
                widget.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                widget.description!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (logos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: logos.map((logo) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      logo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 总进度概览
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProgressOverview(Color chColor) {
    return AnimatedBuilder(
      animation: _progressAnim,
      builder: (context, child) {
        final progress = _overallProgress * _progressAnim.value;
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.trending_up, color: chColor, size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      '学习进度',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: chColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: chColor.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(chColor),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_completedSteps / 4 个环节已完成',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 学习步骤 Timeline
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStepTimeline(Color chColor) {
    final steps = [
      _StepData(
        title: '概念理解',
        subtitle: '学习「${widget.conceptName}」的核心概念',
        icon: Icons.lightbulb,
        isCompleted: _conceptLearned,
        resourceInfo: widget.description != null ? '有概念描述' : '基础概念',
        action: _conceptLearned ? null : _markConceptLearned,
        actionLabel: '标记已学习',
      ),
      _StepData(
        title: '视频学习',
        subtitle: widget.chapter != null
            ? '${ChapterHelper.shortTitle(widget.chapter!)} 相关视频'
            : '观看教学视频',
        icon: Icons.play_circle,
        isCompleted: _videoWatched,
        resourceInfo: '$_videoCount 个视频',
        action: _videoCount > 0 ? () => _navigateToVideo() : null,
        actionLabel: '去学习',
      ),
      _StepData(
        title: '课件阅读',
        subtitle: widget.chapter != null
            ? '${ChapterHelper.shortTitle(widget.chapter!)} PPT/PDF 课件'
            : '阅读课件资料',
        icon: Icons.menu_book,
        isCompleted: _coursewareRead,
        resourceInfo: '$_pptCount 个PPT · $_pdfCount 个PDF',
        action:
            (_pptCount + _pdfCount) > 0 ? () => _navigateToCourseware() : null,
        actionLabel: '去阅读',
      ),
      _StepData(
        title: '章节测验',
        subtitle: widget.chapter != null
            ? '${ChapterHelper.shortTitle(widget.chapter!)} 章节测验'
            : '完成章节测验',
        icon: Icons.quiz,
        isCompleted: _quizPassed,
        resourceInfo: '$_quizCount 道题 · 已测$_quizDoneCount次',
        action: _quizCount > 0 ? () => _navigateToQuiz() : null,
        actionLabel: '去测验',
      ),
    ];

    return Column(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isLast = index == steps.length - 1;
        return _buildStepItem(step, index, isLast, chColor);
      }),
    );
  }

  Widget _buildStepItem(_StepData step, int index, bool isLast, Color chColor) {
    final isActive = index <= _completedSteps;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：圆点 + 连接线
          SizedBox(
            width: 48,
            child: Column(
              children: [
                // 圆点
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: step.isCompleted
                        ? Colors.green
                        : isActive
                            ? chColor
                            : Colors.grey.shade300,
                    shape: BoxShape.circle,
                    boxShadow: step.isCompleted || isActive
                        ? [
                            BoxShadow(
                              color: (step.isCompleted ? Colors.green : chColor)
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    step.isCompleted ? Icons.check : step.icon,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                // 连接线
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            step.isCompleted
                                ? Colors.green
                                : isActive
                                    ? chColor
                                    : Colors.grey.shade300,
                            index + 1 <= _completedSteps
                                ? Colors.green
                                : Colors.grey.shade300,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧卡片
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: step.isCompleted
                    ? const BorderSide(color: Colors.green, width: 1.5)
                    : isActive
                        ? BorderSide(
                            color: chColor.withValues(alpha: 0.3),
                            width: 1,
                          )
                        : BorderSide.none,
              ),
              elevation: isActive ? 2 : 0.5,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        Text(
                          '${index + 1}. ${step.title}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: step.isCompleted
                                ? Colors.green.shade700
                                : isActive
                                    ? Colors.black87
                                    : Colors.grey,
                          ),
                        ),
                        const Spacer(),
                        if (step.isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '已完成',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 副标题
                    Text(
                      step.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 资源信息
                    Text(
                      step.resourceInfo,
                      style: TextStyle(
                        fontSize: 12,
                        color: chColor.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // 操作按钮
                    if (step.action != null && !step.isCompleted) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: step.action,
                          icon: Icon(step.icon, size: 16),
                          label: Text(step.actionLabel),
                          style: FilledButton.styleFrom(
                            backgroundColor: chColor,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 导航方法
  // ─────────────────────────────────────────────────────────────────────────

  void _navigateToVideo() {
    if (widget.chapter == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoListPage(
          filterChapter: _chapterFilter(widget.chapter!),
        ),
      ),
    ).then((_) => _loadData());
  }

  void _navigateToCourseware() {
    if (widget.chapter == null) return;
    final chFilter = _chapterFilter(widget.chapter!);
    // 同时显示 PPT 和 PDF，用 TabBar 切换
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResourceViewerPage(
          fileType: 'all',
          filterChapter: chFilter,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _navigateToQuiz() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QuizPage(),
      ),
    ).then((_) => _loadData());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 辅助数据类
// ─────────────────────────────────────────────────────────────────────────────

class _StepData {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isCompleted;
  final String resourceInfo;
  final VoidCallback? action;
  final String actionLabel;

  const _StepData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isCompleted,
    required this.resourceInfo,
    this.action,
    this.actionLabel = '去学习',
  });
}
