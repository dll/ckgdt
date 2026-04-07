import 'package:flutter/material.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/models/question_model.dart';
import '../../../services/auth_service.dart';
import '../../../core/constants/role_guard.dart';

/// 题库管理页面 — 教师/管理员专用
/// 功能：题目列表、按章节筛选、添加/编辑/删除题目、章节统计
class QuestionManagePage extends StatefulWidget {
  const QuestionManagePage({super.key});

  @override
  State<QuestionManagePage> createState() => _QuestionManagePageState();
}

class _QuestionManagePageState extends State<QuestionManagePage> {
  final _quizDao = QuizDao();
  final _authService = AuthService();

  List<QuestionModel> _questions = [];
  List<String> _chapters = [];
  List<Map<String, dynamic>> _chapterStats = [];
  String _selectedChapter = '全部';
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final chapters = await _quizDao.getChapters();
      final stats = await _quizDao.getChapterStats();

      List<QuestionModel> questions;
      if (_selectedChapter == '全部') {
        questions = await _quizDao.getAllQuestions();
      } else {
        questions = await _quizDao.getQuestionsByChapter(_selectedChapter);
      }

      if (mounted) {
        setState(() {
          _chapters = chapters;
          _chapterStats = stats;
          _questions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<QuestionModel> get _filteredQuestions {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _questions;
    return _questions
        .where((q) =>
            q.question.toLowerCase().contains(query) ||
            (q.source ?? '').toLowerCase().contains(query))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 权限守卫：仅教师/管理员可访问
    final role = _authService.currentUser?.role ?? 'student';
    if (!RoleGuard.canManageQuestions(role)) {
      return Scaffold(
        appBar: AppBar(title: const Text('题库管理')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('无权限访问', style: TextStyle(fontSize: 18, color: Colors.grey)),
              SizedBox(height: 8),
              Text('仅教师和管理员可管理题库', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final primary = Theme.of(context).colorScheme.primary;
    final filtered = _filteredQuestions;
    final totalCount =
        _chapterStats.fold<int>(0, (sum, s) => sum + ((s['count'] as int?) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('题库管理'),
        actions: [
          // 批量操作
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'stats') _showStatsDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'stats',
                child: ListTile(
                  leading: Icon(Icons.analytics),
                  title: Text('章节统计'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 统计概览 ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _statChip('总题数', '$totalCount', Icons.quiz, primary),
                const SizedBox(width: 10),
                _statChip(
                    '章节数', '${_chapters.length}', Icons.book, Colors.teal),
                const SizedBox(width: 10),
                _statChip(
                    '当前筛选',
                    '${filtered.length}',
                    Icons.filter_list,
                    Colors.orange),
              ],
            ),
          ),

          // ── 搜索栏 ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索题目内容...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),

          // ── 章节筛选 ──────────────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: ['全部', ..._chapters].map((label) {
                final selected = _selectedChapter == label;
                // 获取该章节题目数
                int chapterCount = totalCount;
                if (label != '全部') {
                  final stat = _chapterStats.where(
                      (s) => s['source'] == label);
                  chapterCount = stat.isNotEmpty
                      ? ((stat.first['count'] as int?) ?? 0)
                      : 0;
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      label == '全部'
                          ? '全部 ($totalCount)'
                          : '$label ($chapterCount)',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedChapter = label);
                      _loadData();
                    },
                    showCheckmark: false,
                    selectedColor: primary.withValues(alpha: 0.15),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),

          // ── 题目列表 ──────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.quiz, size: 56, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('没有题目',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) =>
                              _buildQuestionCard(context, filtered[i], i + 1),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _statChip(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(label,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 题目卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildQuestionCard(
      BuildContext context, QuestionModel q, int index) {
    final optionLabels = ['A', 'B', 'C', 'D'];
    final correctLabel = optionLabels[q.answerIndex];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showQuestionDetail(q),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    child: Text('$index',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(q.question,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  // 操作按钮
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 18, color: Colors.grey[400]),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'edit') _showEditDialog(context, q);
                      if (v == 'delete') _confirmDelete(q);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 章节 + 正确答案
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(q.source ?? '未分类',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.teal)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('正确答案: $correctLabel',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.green)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 题目详情弹窗
  // ─────────────────────────────────────────────────────────────────────────

  void _showQuestionDetail(QuestionModel q) {
    final optionLabels = ['A', 'B', 'C', 'D'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽手柄
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
            // 章节
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(q.source ?? '未分类',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.teal,
                      fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 12),
            // 题目
            Text(q.question,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            // 选项
            ...List.generate(4, (i) {
              final isCorrect = i == q.answerIndex;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCorrect
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.grey[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          isCorrect ? Colors.green : Colors.grey[300],
                      child: Text(optionLabels[i],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  isCorrect ? Colors.white : Colors.grey[600])),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(q.options[i],
                          style: TextStyle(
                              fontSize: 14,
                              color:
                                  isCorrect ? Colors.green[800] : null)),
                    ),
                    if (isCorrect)
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 20),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditDialog(context, q);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('编辑'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDelete(q);
                    },
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label:
                        const Text('删除', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 添加/编辑题目对话框
  // ─────────────────────────────────────────────────────────────────────────

  void _showEditDialog(BuildContext context, QuestionModel? existing) {
    final isNew = existing == null;
    final questionCtrl = TextEditingController(text: existing?.question ?? '');
    final optACtrl = TextEditingController(text: existing?.optionA ?? '');
    final optBCtrl = TextEditingController(text: existing?.optionB ?? '');
    final optCCtrl = TextEditingController(text: existing?.optionC ?? '');
    final optDCtrl = TextEditingController(text: existing?.optionD ?? '');
    final sourceCtrl =
        TextEditingController(text: existing?.source ?? '');
    int selectedAnswer = existing?.answerIndex ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isNew ? '添加题目' : '编辑题目'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 章节
                  TextField(
                    controller: sourceCtrl,
                    decoration: InputDecoration(
                      labelText: '所属章节 *',
                      hintText: '如: 第1章-移动应用开发技术体系全景',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 题目
                  TextField(
                    controller: questionCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '题目内容 *',
                      hintText: '请输入题目',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 选项 A
                  TextField(
                    controller: optACtrl,
                    decoration: InputDecoration(
                      labelText: '选项 A *',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 选项 B
                  TextField(
                    controller: optBCtrl,
                    decoration: InputDecoration(
                      labelText: '选项 B *',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 选项 C
                  TextField(
                    controller: optCCtrl,
                    decoration: InputDecoration(
                      labelText: '选项 C *',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 选项 D
                  TextField(
                    controller: optDCtrl,
                    decoration: InputDecoration(
                      labelText: '选项 D *',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 正确答案
                  DropdownButtonFormField<int>(
                    value: selectedAnswer,
                    decoration: InputDecoration(
                      labelText: '正确答案 *',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('A')),
                      const DropdownMenuItem(value: 1, child: Text('B')),
                      const DropdownMenuItem(value: 2, child: Text('C')),
                      const DropdownMenuItem(value: 3, child: Text('D')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => selectedAnswer = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                // 验证
                if (sourceCtrl.text.trim().isEmpty ||
                    questionCtrl.text.trim().isEmpty ||
                    optACtrl.text.trim().isEmpty ||
                    optBCtrl.text.trim().isEmpty ||
                    optCCtrl.text.trim().isEmpty ||
                    optDCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请填写所有必填字段')),
                  );
                  return;
                }

                final model = QuestionModel(
                  source: sourceCtrl.text.trim(),
                  question: questionCtrl.text.trim(),
                  optionA: optACtrl.text.trim(),
                  optionB: optBCtrl.text.trim(),
                  optionC: optCCtrl.text.trim(),
                  optionD: optDCtrl.text.trim(),
                  answerIndex: selectedAnswer,
                );

                try {
                  if (isNew) {
                    await _quizDao.addQuestion(model);
                  } else {
                    await _quizDao.updateQuestion(existing.id!, model);
                  }
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isNew ? '题目添加成功' : '题目更新成功'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadData();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('操作失败: $e')),
                    );
                  }
                }
              },
              child: Text(isNew ? '添加' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 删除确认
  // ─────────────────────────────────────────────────────────────────────────

  void _confirmDelete(QuestionModel q) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除题目"${q.question.length > 30 ? '${q.question.substring(0, 30)}...' : q.question}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _quizDao.deleteQuestion(q.id!);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('题目已删除'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadData();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e')),
                  );
                }
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 章节统计弹窗
  // ─────────────────────────────────────────────────────────────────────────

  void _showStatsDialog() {
    final primary = Theme.of(context).colorScheme.primary;
    final totalCount = _chapterStats.fold<int>(
        0, (sum, s) => sum + ((s['count'] as int?) ?? 0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text('题库章节统计',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primary)),
            const SizedBox(height: 4),
            Text('共 $totalCount 道题目，覆盖 ${_chapterStats.length} 个章节',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 16),
            ..._chapterStats.map((stat) {
              final source = stat['source'] as String? ?? '未分类';
              final count = (stat['count'] as int?) ?? 0;
              final ratio = totalCount > 0 ? count / totalCount : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(source,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('$count 题 (${(ratio * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(primary),
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
  }
}
