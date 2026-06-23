import 'package:flutter/material.dart';
import '../../../data/local/classroom_dao.dart';
import '../../../services/auth_service.dart';
import '../../../core/error_handler.dart';

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  课堂提问 Tab — 多源题库浏览、编辑、发布提问                                 ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class ClassroomQuestionTab extends StatefulWidget {
  final ClassroomDao classroomDao;
  final int? classId;
  final AuthService authService;

  const ClassroomQuestionTab({
    super.key,
    required this.classroomDao,
    this.classId,
    required this.authService,
  });

  @override
  State<ClassroomQuestionTab> createState() => _ClassroomQuestionTabState();
}

class _ClassroomQuestionTabState extends State<ClassroomQuestionTab> {
  List<Map<String, dynamic>> _questions = [];
  Map<String, int> _sourceStats = {};
  List<String> _chapters = [];
  bool _isLoading = true;
  Map<String, dynamic>? _currentQuestion; // 当前正在提问的题目

  // ── 筛选状态 ──
  String? _filterSourceType;
  String? _filterChapter;
  String? _filterDifficulty;
  bool _showAskedOnly = false;

  // ── 来源/难度映射 ──
  static const _sourceLabels = {
    'quiz': '测验试题',
    'courseware': '理论课件',
    'lab': '实验材料',
    'assessment': '考核内容',
  };
  static const _sourceIcons = {
    'quiz': Icons.quiz,
    'courseware': Icons.menu_book,
    'lab': Icons.science,
    'assessment': Icons.assignment,
  };
  static const _sourceColors = {
    'quiz': Colors.blue,
    'courseware': Colors.purple,
    'lab': Colors.teal,
    'assessment': Colors.orange,
  };
  static const _diffLabels = {
    'easy': '简单',
    'medium': '中等',
    'hard': '较难',
  };
  static const _diffColors = {
    'easy': Colors.green,
    'medium': Colors.orange,
    'hard': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didUpdateWidget(covariant ClassroomQuestionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classId != widget.classId) _loadData();
  }

  Future<void> _initData() async {
    final count = await widget.classroomDao.getClassroomQuestionCount();
    if (count == 0) {
      await widget.classroomDao.importFromQuizBank();
      await widget.classroomDao.importFromLabTasks();
      await widget.classroomDao.importFromAssessment();
    }
    // 始终从课程资源导入（courseware 源可能不断增加）
    await widget.classroomDao.importFromCourseware();
    await _loadData();
  }

  Future<void> _loadData() async {
    try {
      final questions = await widget.classroomDao.getClassroomQuestions(
        sourceType: _filterSourceType,
        chapter: _filterChapter,
        difficulty: _filterDifficulty,
        isAsked: _showAskedOnly ? true : null,
      );
      final stats = await widget.classroomDao.getQuestionSourceStats();
      final chapters = await widget.classroomDao.getQuestionChapters();
      if (mounted) {
        setState(() {
          _questions = questions;
          _sourceStats = stats;
          _chapters = chapters;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              // ── 来源统计 ──
              _buildSourceStats(primary),
              const SizedBox(height: 12),

              // ── 筛选栏 ──
              _buildFilterBar(primary),
              const SizedBox(height: 12),

              // ── 当前提问 ──
              if (_currentQuestion != null) ...[
                _buildCurrentQuestion(primary),
                const SizedBox(height: 12),
              ],

              // ── 题目列表 ──
              if (_questions.isEmpty)
                _buildEmpty()
              else
                ..._questions.map((q) => _buildQuestionCard(q, primary)),
            ],
          ),
        ),

        // ── FAB: 添加题目 + 重新导入 ──
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'import',
                onPressed: _reimport,
                tooltip: '重新导入题库',
                backgroundColor: Colors.grey[200],
                child: Icon(Icons.sync, color: Colors.grey[700], size: 20),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'add',
                onPressed: () => _showAddDialog(context),
                tooltip: '手动添加题目',
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  来源统计
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSourceStats(Color primary) {
    final total = _sourceStats.values.fold(0, (a, b) => a + b);
    return Row(
      children: [
        _sourceChip('全部', total, Icons.list_alt, primary, null),
        const SizedBox(width: 6),
        ..._sourceLabels.entries.map((e) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _sourceChip(
                _sourceLabels[e.key]!,
                _sourceStats[e.key] ?? 0,
                _sourceIcons[e.key]!,
                _sourceColors[e.key]!,
                e.key,
              ),
            )),
      ],
    );
  }

  Widget _sourceChip(
      String label, int count, IconData icon, Color color, String? type) {
    final isActive = _filterSourceType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _filterSourceType = type);
          _loadData();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.15)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(color: color.withValues(alpha: 0.5))
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text('$count',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: TextStyle(fontSize: 9, color: color),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  筛选栏
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFilterBar(Color primary) {
    return Row(
      children: [
        // 章节
        Expanded(
          child: _dropdown<String?>(
            value: _filterChapter,
            hint: '章节',
            icon: Icons.book,
            items: [
              const DropdownMenuItem(value: null, child: Text('全部章节')),
              ..._chapters.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)))),
            ],
            onChanged: (v) {
              setState(() => _filterChapter = v);
              _loadData();
            },
          ),
        ),
        const SizedBox(width: 8),
        // 难度
        Expanded(
          child: _dropdown<String?>(
            value: _filterDifficulty,
            hint: '难度',
            icon: Icons.signal_cellular_alt,
            items: [
              const DropdownMenuItem(value: null, child: Text('全部难度')),
              ..._diffLabels.entries.map((e) => DropdownMenuItem(
                  value: e.key, child: Text(e.value))),
            ],
            onChanged: (v) {
              setState(() => _filterDifficulty = v);
              _loadData();
            },
          ),
        ),
        const SizedBox(width: 8),
        // 已提问开关
        FilterChip(
          label: Text('已提问', style: TextStyle(fontSize: 11,
              color: _showAskedOnly ? primary : Colors.grey)),
          selected: _showAskedOnly,
          onSelected: (v) {
            setState(() => _showAskedOnly = v);
            _loadData();
          },
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: Icon(icon, size: 16),
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  当前提问（教师正在课堂上问的题目）
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCurrentQuestion(Color primary) {
    final q = _currentQuestion!;

    return Card(
      color: primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primary.withValues(alpha: 0.3), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over, color: primary, size: 20),
                const SizedBox(width: 8),
                Text('当前提问',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _currentQuestion = null),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('结束', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 来源/难度标签
            _buildBadgeRow(q),
            const SizedBox(height: 8),
            // 题目文本
            Text(q['question'] as String? ?? '',
                style: const TextStyle(fontSize: 15, height: 1.5)),
            // 选项（如果是选择题）
            if (q['question_type'] == 'choice') ...[
              const SizedBox(height: 10),
              _buildOptions(q, showAnswer: false),
            ],
            // 参考答案（仅教师可见）
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.visibility, size: 14,
                          color: Colors.green[700]),
                      const SizedBox(width: 4),
                      Text('参考答案（仅教师可见）',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q['reference_answer'] as String? ?? '暂无参考答案',
                    style: TextStyle(
                        fontSize: 13, color: Colors.green[800], height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  题目卡片
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildQuestionCard(Map<String, dynamic> q, Color primary) {
    final sourceType = q['source_type'] as String? ?? 'quiz';
    final color = _sourceColors[sourceType] ?? Colors.blue;
    final isAsked = q['asked_at'] != null;
    final questionText = q['question'] as String? ?? '';
    final isChoice = q['question_type'] == 'choice';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: color.withValues(alpha: 0.6), width: 3),
          ),
        ),
        child: InkWell(
          onTap: () => _showQuestionDetail(context, q),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标签行
                _buildBadgeRow(q),
                const SizedBox(height: 6),
                // 题目文本
                Text(
                  questionText.length > 120
                      ? '${questionText.substring(0, 120)}...'
                      : questionText,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isAsked ? Colors.grey[600] : Colors.black87,
                    decoration: isAsked ? TextDecoration.lineThrough : null,
                  ),
                ),
                // 选项摘要
                if (isChoice) ...[
                  const SizedBox(height: 6),
                  _buildOptionsPreview(q),
                ],
                const SizedBox(height: 8),
                // 操作按钮
                Row(
                  children: [
                    if (isAsked)
                      Text(
                        '已提问 ${_formatTime(q['asked_at'] as String?)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    const Spacer(),
                    _actionButton('编辑', Icons.edit_outlined, Colors.blue,
                        () => _showEditDialog(context, q)),
                    const SizedBox(width: 6),
                    if (!isAsked)
                      _actionButton('发布提问', Icons.campaign, primary,
                          () => _confirmPublish(context, q))
                    else
                      _actionButton('撤回', Icons.undo, Colors.grey,
                          () => _unmarkAsked(q)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeRow(Map<String, dynamic> q) {
    final sourceType = q['source_type'] as String? ?? 'quiz';
    final difficulty = q['difficulty'] as String? ?? 'medium';
    final chapter = q['chapter'] as String? ?? '';
    final sColor = _sourceColors[sourceType] ?? Colors.blue;
    final dColor = _diffColors[difficulty] ?? Colors.orange;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _badge(_sourceLabels[sourceType] ?? sourceType,
            _sourceIcons[sourceType] ?? Icons.help, sColor),
        _badge(_diffLabels[difficulty] ?? difficulty, null, dColor),
        if (chapter.isNotEmpty)
          _badge(chapter, Icons.bookmark_border, Colors.grey),
      ],
    );
  }

  Widget _badge(String label, IconData? icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildOptionsPreview(Map<String, dynamic> q) {
    final answerIdx = (q['answer_index'] as int?) ?? -1;
    final opts = [
      q['option_a'] as String? ?? '',
      q['option_b'] as String? ?? '',
      q['option_c'] as String? ?? '',
      q['option_d'] as String? ?? '',
    ];
    return Column(
      children: List.generate(4, (i) {
        if (opts[i].isEmpty) return const SizedBox.shrink();
        final letter = String.fromCharCode(65 + i);
        final isAnswer = i == answerIdx;
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isAnswer
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Text(letter,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isAnswer ? Colors.green : Colors.grey)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  opts[i],
                  style: TextStyle(
                    fontSize: 11,
                    color: isAnswer ? Colors.green[700] : Colors.grey[700],
                    fontWeight: isAnswer ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildOptions(Map<String, dynamic> q, {bool showAnswer = true}) {
    final answerIdx = (q['answer_index'] as int?) ?? -1;
    final opts = [
      q['option_a'] as String? ?? '',
      q['option_b'] as String? ?? '',
      q['option_c'] as String? ?? '',
      q['option_d'] as String? ?? '',
    ];
    return Column(
      children: List.generate(4, (i) {
        if (opts[i].isEmpty) return const SizedBox.shrink();
        final letter = String.fromCharCode(65 + i);
        final isAnswer = showAnswer && i == answerIdx;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isAnswer
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border: isAnswer
                ? Border.all(color: Colors.green.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isAnswer
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(letter,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isAnswer ? Colors.green : Colors.grey[600])),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(opts[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: isAnswer ? Colors.green[800] : Colors.black87,
                      fontWeight:
                          isAnswer ? FontWeight.w600 : FontWeight.normal,
                    )),
              ),
              if (isAnswer)
                Icon(Icons.check_circle, size: 16, color: Colors.green[600]),
            ],
          ),
        );
      }),
    );
  }

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.quiz_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('暂无匹配的题目', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          const Text('尝试调整筛选条件或添加新题目',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  题目详情弹窗
  // ══════════════════════════════════════════════════════════════════════════

  void _showQuestionDetail(BuildContext context, Map<String, dynamic> q) {
    final isChoice = q['question_type'] == 'choice';
    final refAnswer = q['reference_answer'] as String? ?? '';
    final isAsked = q['asked_at'] != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // 拖动指示器
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 标签
            _buildBadgeRow(q),
            const SizedBox(height: 12),
            // 题目
            Text(q['question'] as String? ?? '',
                style:
                    const TextStyle(fontSize: 16, height: 1.6)),
            // 选项
            if (isChoice) ...[
              const SizedBox(height: 14),
              _buildOptions(q),
            ],
            // 参考答案
            if (refAnswer.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 16, color: Colors.green[700]),
                        const SizedBox(width: 6),
                        Text('参考答案',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700])),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(refAnswer,
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.green[800],
                            height: 1.5)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditDialog(context, q);
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('编辑'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isAsked
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _confirmPublish(context, q);
                          },
                    icon: Icon(
                        isAsked ? Icons.check : Icons.campaign, size: 16),
                    label: Text(isAsked ? '已提问' : '发布提问'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  发布提问确认
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _confirmPublish(
      BuildContext context, Map<String, dynamic> q) async {
    final primary = Theme.of(context).colorScheme.primary;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.campaign, color: primary, size: 22),
            const SizedBox(width: 8),
            const Text('确认发布提问', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBadgeRow(q),
              const SizedBox(height: 10),
              Text(q['question'] as String? ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.5)),
              if (q['question_type'] == 'choice') ...[
                const SizedBox(height: 10),
                _buildOptionsPreview(q),
              ],
              const Divider(height: 20),
              Text('发布后将作为当前课堂提问展示。',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认发布')),
        ],
      ),
    );

    if (confirmed == true) {
      final id = q['id'] as int;
      await widget.classroomDao.markQuestionAsked(id, classId: widget.classId);

      // 同步发送到课堂消息
      final user = widget.authService.currentUser;
      if (user != null) {
        final questionText = q['question'] as String? ?? '';
        final isChoice = q['question_type'] == 'choice';
        String msgContent = '📋 课堂提问：\n$questionText';
        if (isChoice) {
          final opts = ['A', 'B', 'C', 'D'];
          for (int i = 0; i < 4; i++) {
            final opt = q['option_${String.fromCharCode(97 + i)}'] as String? ?? '';
            if (opt.isNotEmpty) msgContent += '\n${opts[i]}. $opt';
          }
        }
        await widget.classroomDao.sendMessage(
          classId: widget.classId,
          senderId: user.userId,
          senderName: user.realName ?? user.userId,
          senderRole: user.role,
          content: msgContent,
          messageType: 'question',
        );
      }

      setState(() {
        _currentQuestion = Map<String, dynamic>.from(q);
        _currentQuestion!['asked_at'] = DateTime.now().toIso8601String();
      });
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('题目已发布到课堂'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _unmarkAsked(Map<String, dynamic> q) async {
    final id = q['id'] as int;
    await widget.classroomDao.unmarkQuestionAsked(id);
    await _loadData();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  编辑题目弹窗
  // ══════════════════════════════════════════════════════════════════════════

  void _showEditDialog(BuildContext context, Map<String, dynamic> q) {
    final questionCtrl =
        TextEditingController(text: q['question'] as String? ?? '');
    final optACtrl =
        TextEditingController(text: q['option_a'] as String? ?? '');
    final optBCtrl =
        TextEditingController(text: q['option_b'] as String? ?? '');
    final optCCtrl =
        TextEditingController(text: q['option_c'] as String? ?? '');
    final optDCtrl =
        TextEditingController(text: q['option_d'] as String? ?? '');
    final refCtrl =
        TextEditingController(text: q['reference_answer'] as String? ?? '');
    int answerIdx = (q['answer_index'] as int?) ?? -1;
    String questionType = q['question_type'] as String? ?? 'open';
    String difficulty = q['difficulty'] as String? ?? 'medium';
    String chapter = q['chapter'] as String? ?? '';
    String sourceType = q['source_type'] as String? ?? 'quiz';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑题目', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 来源 + 难度
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(value: sourceType,
                          decoration: const InputDecoration(
                            labelText: '来源',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: _sourceLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value,
                                    style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => sourceType = v!),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(value: difficulty,
                          decoration: const InputDecoration(
                            labelText: '难度',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: _diffLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value,
                                    style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => difficulty = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 章节
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '章节',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: chapter),
                    onChanged: (v) => chapter = v,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  // 题型切换
                  Row(
                    children: [
                      const Text('题型：', style: TextStyle(fontSize: 13)),
                      ChoiceChip(
                        label: const Text('选择题',
                            style: TextStyle(fontSize: 12)),
                        selected: questionType == 'choice',
                        onSelected: (v) {
                          if (v) setDialogState(() => questionType = 'choice');
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('开放题',
                            style: TextStyle(fontSize: 12)),
                        selected: questionType == 'open',
                        onSelected: (v) {
                          if (v) {
                            setDialogState(() {
                              questionType = 'open';
                              answerIdx = -1;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 题目
                  TextField(
                    controller: questionCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '题目内容',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  // 选择题选项
                  if (questionType == 'choice') ...[
                    const SizedBox(height: 10),
                    ...List.generate(4, (i) {
                      final ctrl = [optACtrl, optBCtrl, optCCtrl, optDCtrl][i];
                      final letter = String.fromCharCode(65 + i);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Radio<int>(
                              value: i,
                              groupValue: answerIdx,
                              onChanged: (v) =>
                                  setDialogState(() => answerIdx = v!),
                              visualDensity: VisualDensity.compact,
                            ),
                            Text('$letter.',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                decoration: InputDecoration(
                                  hintText: '选项$letter',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  border: const OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 10),
                  // 参考答案
                  TextField(
                    controller: refCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '参考答案',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'source_type': sourceType,
                  'chapter': chapter,
                  'difficulty': difficulty,
                  'question': questionCtrl.text.trim(),
                  'question_type': questionType,
                  'answer_index': answerIdx,
                  'reference_answer': refCtrl.text.trim(),
                };
                if (questionType == 'choice') {
                  data['option_a'] = optACtrl.text.trim();
                  data['option_b'] = optBCtrl.text.trim();
                  data['option_c'] = optCCtrl.text.trim();
                  data['option_d'] = optDCtrl.text.trim();
                  // 自动更新参考答案
                  if (answerIdx >= 0) {
                    final opts = [
                      optACtrl.text.trim(), optBCtrl.text.trim(),
                      optCCtrl.text.trim(), optDCtrl.text.trim(),
                    ];
                    final letter = String.fromCharCode(65 + answerIdx);
                    data['reference_answer'] =
                        '$letter. ${opts[answerIdx]}';
                  }
                }
                await widget.classroomDao
                    .updateClassroomQuestion(q['id'] as int, data);
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadData();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  添加新题目弹窗
  // ══════════════════════════════════════════════════════════════════════════

  void _showAddDialog(BuildContext context) {
    final questionCtrl = TextEditingController();
    final optACtrl = TextEditingController();
    final optBCtrl = TextEditingController();
    final optCCtrl = TextEditingController();
    final optDCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    int answerIdx = -1;
    String questionType = 'open';
    String difficulty = 'medium';
    String sourceType = 'courseware';
    String chapter = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加题目', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 来源 + 难度
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(value: sourceType,
                          decoration: const InputDecoration(
                            labelText: '来源',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: _sourceLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value,
                                    style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => sourceType = v!),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(value: difficulty,
                          decoration: const InputDecoration(
                            labelText: '难度',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: _diffLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value,
                                    style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => difficulty = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 章节
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '章节（如：第1章）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => chapter = v,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  // 题型
                  Row(
                    children: [
                      const Text('题型：', style: TextStyle(fontSize: 13)),
                      ChoiceChip(
                        label: const Text('选择题',
                            style: TextStyle(fontSize: 12)),
                        selected: questionType == 'choice',
                        onSelected: (v) {
                          if (v) setDialogState(() => questionType = 'choice');
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('开放题',
                            style: TextStyle(fontSize: 12)),
                        selected: questionType == 'open',
                        onSelected: (v) {
                          if (v) setDialogState(() => questionType = 'open');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 题目
                  TextField(
                    controller: questionCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '题目内容',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  // 选项
                  if (questionType == 'choice') ...[
                    const SizedBox(height: 10),
                    ...List.generate(4, (i) {
                      final ctrl = [optACtrl, optBCtrl, optCCtrl, optDCtrl][i];
                      final letter = String.fromCharCode(65 + i);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Radio<int>(
                              value: i,
                              groupValue: answerIdx,
                              onChanged: (v) =>
                                  setDialogState(() => answerIdx = v!),
                              visualDensity: VisualDensity.compact,
                            ),
                            Text('$letter.',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                decoration: InputDecoration(
                                  hintText: '选项$letter',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  border: const OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 10),
                  // 参考答案
                  TextField(
                    controller: refCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '参考答案',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final text = questionCtrl.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入题目内容')),
                  );
                  return;
                }
                String? refAnswer = refCtrl.text.trim();
                if (questionType == 'choice' && answerIdx >= 0) {
                  final opts = [
                    optACtrl.text.trim(), optBCtrl.text.trim(),
                    optCCtrl.text.trim(), optDCtrl.text.trim(),
                  ];
                  final letter = String.fromCharCode(65 + answerIdx);
                  refAnswer = '$letter. ${opts[answerIdx]}';
                }
                await widget.classroomDao.addClassroomQuestion(
                  sourceType: sourceType,
                  chapter: chapter.isNotEmpty ? chapter : null,
                  difficulty: difficulty,
                  question: text,
                  optionA: questionType == 'choice'
                      ? optACtrl.text.trim()
                      : null,
                  optionB: questionType == 'choice'
                      ? optBCtrl.text.trim()
                      : null,
                  optionC: questionType == 'choice'
                      ? optCCtrl.text.trim()
                      : null,
                  optionD: questionType == 'choice'
                      ? optDCtrl.text.trim()
                      : null,
                  answerIndex: answerIdx,
                  referenceAnswer:
                      refAnswer.isNotEmpty ? refAnswer : null,
                  questionType: questionType,
                  createdBy:
                      widget.authService.getCurrentUserId(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('题目已添加'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  重新导入题库
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _reimport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新导入题库', style: TextStyle(fontSize: 16)),
        content: const Text('从测验试题、实验任务和考核项目中导入新题目。\n已有题目不会重复导入。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入')),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final quiz = await widget.classroomDao.importFromQuizBank();
      final lab = await widget.classroomDao.importFromLabTasks();
      final assess = await widget.classroomDao.importFromAssessment();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入完成：试题 +$quiz，实验 +$lab，考核 +$assess'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  工具方法
  // ══════════════════════════════════════════════════════════════════════════

  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e, st) {
      swallowDebug(e, tag: 'classroom_question_tab._formatTime', stack: st);
      return '';
    }
  }
}

