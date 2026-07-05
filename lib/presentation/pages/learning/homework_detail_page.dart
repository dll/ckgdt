import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/local/homework_dao.dart';
import '../../../services/auth_service.dart';
import '../../../data/models/homework_model.dart';
import '../../../services/ai_service.dart';

/// 作业详情/提交页 — 学生端支持粘贴/清空/AI批阅/保存MD/重新提交
class HomeworkDetailPage extends StatefulWidget {
  final HomeworkModel homework;
  final bool isTeacher;
  const HomeworkDetailPage({
    super.key,
    required this.homework,
    this.isTeacher = false,
  });

  @override
  State<HomeworkDetailPage> createState() => _HomeworkDetailPageState();
}

class _HomeworkDetailPageState extends State<HomeworkDetailPage> {
  final HomeworkDao _dao = HomeworkDao();
  final AiService _ai = AiService();
  List<HomeworkItemModel> _items = [];
  List<HomeworkSubmissionModel> _submissions = [];
  final Map<int, TextEditingController> _answerControllers = {};
  final Map<int, bool> _showAnswer = {};
  bool _loading = true;
  bool _submitting = false;
  bool _aiGrading = false;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _answerControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final user = AuthService().currentUser;
      _userId = user?.userId ?? '';
      _items = await _dao.getItems(widget.homework.id);
      _submissions = await _dao.getSubmissions(widget.homework.id, _userId);
      for (final item in _items) {
        _answerControllers[item.id] = TextEditingController();
        _showAnswer[item.id] = false;
      }
      for (final sub in _submissions) {
        if (_answerControllers.containsKey(sub.itemId)) {
          _answerControllers[sub.itemId]!.text = sub.answerText ?? '';
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalScore = _submissions
        .where((s) => s.score != null)
        .fold<int>(0, (sum, s) => sum + (s.score ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.homework.title),
        elevation: 0,
        actions: [
          if (!widget.isTeacher && !_submitting)
            TextButton.icon(
              onPressed: _submitAll,
              icon: const Icon(Icons.send, size: 18),
              label: const Text('提交'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _buildHeader(theme, totalScore);
                return _buildItem(theme, _items[index - 1]);
              },
            ),
    );
  }

  Widget _buildHeader(ThemeData theme, int totalScore) {
    final maxScore = _items.fold<int>(0, (sum, i) => sum + i.maxScore);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.homework.chapterTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                _tag(Icons.track_changes,
                    '目标: ${widget.homework.courseObjective}'),
                const SizedBox(width: 12),
                _tag(Icons.score, '已得 $totalScore / $maxScore 分'),
                const SizedBox(width: 12),
                _tag(Icons.list_alt, '${_items.length} 题'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildItem(ThemeData theme, HomeworkItemModel item) {
    final sub = _submissions.where((s) => s.itemId == item.id).firstOrNull;
    final hasSubmitted = sub != null;
    final isGraded =
        sub?.status == 'ai_graded' || sub?.status == 'teacher_reviewed';

    final typeColor = {
          'basic': Colors.blue,
          'practice': Colors.green,
          'thinking': Colors.orange,
        }[item.type] ??
        Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(item.typeLabel,
                      style: TextStyle(
                          fontSize: 11,
                          color: typeColor,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text('第 ${item.itemIndex} 题',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const Spacer(),
                Text('${item.maxScore} 分',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.question,
                style: const TextStyle(fontSize: 14, height: 1.5)),
            if (item.objectiveMapping.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: item.objectiveMapping.map((om) {
                  return Chip(
                    label: Text(
                        '目标${om.objectiveId}: ${(om.contribution * 100).toInt()}%',
                        style: const TextStyle(fontSize: 10)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            if (widget.isTeacher)
              _buildTeacherView(theme, item, sub)
            else
              _buildStudentView(theme, item, sub, hasSubmitted, isGraded),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentView(ThemeData theme, HomeworkItemModel item,
      HomeworkSubmissionModel? sub, bool hasSubmitted, bool isGraded) {
    final controller = _answerControllers[item.id];
    final isEditable = !hasSubmitted || !isGraded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEditable) ...[
          // ── 工具栏 ──────────────────────────────────────────
          _buildToolbar(theme, item, controller),
          const SizedBox(height: 6),
          // ── 答案输入 ──────────────────────────────────────
          TextField(
            controller: controller,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: '请输入你的答案...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 8),
          // ── 单题 AI 批阅 ────────────────────────────────────
          if (hasSubmitted)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _aiGrading ? null : () => _aiGradeOne(item),
                icon: _aiGrading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.smart_toy, size: 18),
                label: Text(_aiGrading ? '批阅中...' : 'AI 批阅'),
              ),
            ),
        ] else ...[
          // ── 已提交答案展示 ────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
            ),
            child: Text(sub?.answerText ?? '',
                style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 8),
          // AI 评语
          if (sub?.aiComment != null && sub!.aiComment!.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.smart_toy, size: 16, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text('AI 评语',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade600,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (sub?.score != null)
                  Text('得分: ${sub!.score}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade600,
                          fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(sub!.aiComment!, style: const TextStyle(fontSize: 13)),
          ],
          // 教师评语
          if (sub?.teacherComment != null &&
              sub!.teacherComment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.orange.shade600),
                const SizedBox(width: 4),
                Text('教师评语',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade600,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(sub!.teacherComment!, style: const TextStyle(fontSize: 13)),
          ],
          // ── 重新提交按钮 ────────────────────────────────
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _resubmit(item),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新提交'),
            ),
          ),
        ],
      ],
    );
  }

  /// 答案工具栏：粘贴 / 清空 / AI批阅 / 保存MD
  Widget _buildToolbar(
      ThemeData theme, HomeworkItemModel item, TextEditingController? ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _toolBtn(
            icon: Icons.content_paste,
            label: '粘贴',
            onTap: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null && ctrl != null) {
                ctrl.text = data!.text!;
                ctrl.selection =
                    TextSelection.collapsed(offset: ctrl.text.length);
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已粘贴')));
                }
              }
            },
          ),
          _toolDivider(),
          _toolBtn(
            icon: Icons.clear_all,
            label: '清空',
            onTap: () {
              if (ctrl != null && ctrl.text.isNotEmpty) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确认清空'),
                    content: const Text('清空后无法恢复，确定清空？'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () {
                            ctrl.clear();
                            Navigator.pop(ctx);
                          },
                          child: const Text('确定',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
              }
            },
          ),
          _toolDivider(),
          _toolBtn(
            icon: Icons.smart_toy,
            label: 'AI批阅',
            onTap: _aiGrading ? null : () => _aiGradeOne(item),
          ),
          _toolDivider(),
          _toolBtn(
            icon: Icons.save_alt,
            label: '保存MD',
            onTap: () => _saveAsMarkdown(item),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: enabled ? Colors.blue.shade600 : Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: enabled ? Colors.blue.shade600 : Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _toolDivider() =>
      Container(width: 1, height: 16, color: Colors.grey.shade300);

  Widget _buildTeacherView(
      ThemeData theme, HomeworkItemModel item, HomeworkSubmissionModel? sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.referenceAnswer != null) ...[
          InkWell(
            onTap: () {
              setState(() {
                _showAnswer[item.id] = !(_showAnswer[item.id] ?? false);
              });
            },
            child: Row(
              children: [
                Icon(Icons.visibility, size: 16, color: Colors.indigo.shade600),
                const SizedBox(width: 4),
                Text(_showAnswer[item.id] == true ? '隐藏参考答案' : '查看参考答案',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.indigo.shade600,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (_showAnswer[item.id] == true) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(item.referenceAnswer!,
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ],
        if (sub != null) ...[
          const Divider(height: 20),
          Text('学生答案',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(sub.answerText ?? '(未填写)',
                style: const TextStyle(fontSize: 13)),
          ),
          if (sub.aiComment != null) ...[
            const SizedBox(height: 6),
            Text('AI 评语: ${sub.aiComment}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      TextEditingController(text: sub.teacherComment ?? ''),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: '教师评语...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller:
                      TextEditingController(text: sub.score?.toString() ?? ''),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '分数',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(8),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Text('暂无提交',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ],
    );
  }

  // ── 提交全部 ──────────────────────────────────────────────────────────────
  Future<void> _submitAll() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      int submitted = 0;
      for (final item in _items) {
        final answer = _answerControllers[item.id]?.text.trim() ?? '';
        if (answer.isEmpty) continue;

        final sub = HomeworkSubmissionModel(
          id: 0,
          homeworkId: widget.homework.id,
          itemId: item.id,
          userId: _userId,
          answerText: answer,
          status: 'submitted',
          submittedAt: DateTime.now(),
        );
        await _dao.submit(sub);
        submitted++;
      }

      if (submitted == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('请至少回答一道题')));
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('提交成功，正在 AI 批阅...')));
      }
      await _aiGradeAll();
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('批阅完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('提交失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── AI 批阅全部 ──────────────────────────────────────────────────────────
  Future<void> _aiGradeAll() async {
    final submissions = await _dao.getSubmissions(widget.homework.id, _userId);
    for (final sub in submissions) {
      if (sub.status != 'submitted') continue;
      final item = _items.where((i) => i.id == sub.itemId).firstOrNull;
      if (item == null) continue;

      try {
        final prompt = _buildGradePrompt(item, sub.answerText);
        final response = await _ai.chat([
          {'role': 'user', 'content': prompt}
        ]);
        final data = _parseJson(response);
        if (data != null) {
          final score = (data['score'] as num?)?.toInt() ?? 0;
          final comment = data['comment'] as String? ?? '';
          await _dao.updateAiGrade(sub.id, score, comment);
        }
      } catch (_) {}
    }
    try {
      await _dao.syncToAchievementScores(widget.homework.courseId);
    } catch (_) {}
  }

  // ── AI 批阅单题 ──────────────────────────────────────────────────────────
  Future<void> _aiGradeOne(HomeworkItemModel item) async {
    if (_aiGrading) return;
    final answer = _answerControllers[item.id]?.text.trim() ?? '';
    if (answer.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先输入答案')));
      }
      return;
    }

    setState(() => _aiGrading = true);
    try {
      // 先保存
      final sub = HomeworkSubmissionModel(
        id: 0,
        homeworkId: widget.homework.id,
        itemId: item.id,
        userId: _userId,
        answerText: answer,
        status: 'submitted',
        submittedAt: DateTime.now(),
      );
      await _dao.submit(sub);

      final prompt = _buildGradePrompt(item, answer);
      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);

      // 重新获取提交记录
      final subs = await _dao.getSubmissions(widget.homework.id, _userId);
      final savedSub = subs.where((s) => s.itemId == item.id).firstOrNull;
      if (savedSub != null && data != null) {
        final score = (data['score'] as num?)?.toInt() ?? 0;
        final comment = data['comment'] as String? ?? '';
        await _dao.updateAiGrade(savedSub.id, score, comment);
      }

      await _loadData();
      if (mounted) {
        final score = data != null ? (data['score'] as num?)?.toInt() : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(score != null ? '批阅完成，得分: $score' : '批阅完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('批阅失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _aiGrading = false);
    }
  }

  String _buildGradePrompt(HomeworkItemModel item, String? answer) {
    return '''你是一位严谨的教师，请批阅以下作业。

题目：${item.question}
类型：${item.typeLabel}
${item.referenceAnswer != null ? '参考答案：${item.referenceAnswer}' : ''}
学生答案：${answer ?? '(未填写)'}

满分 ${item.maxScore} 分。请：
1. 给出得分（0-${item.maxScore}）
2. 简要评语（优点+改进建议，100字以内）

返回 JSON：{"score": 分数, "comment": "评语"}''';
  }

  // ── 保存为 Markdown ──────────────────────────────────────────────────────
  Future<void> _saveAsMarkdown(HomeworkItemModel item) async {
    final answer = _answerControllers[item.id]?.text.trim() ?? '';
    if (answer.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('答案为空，无法保存')));
      }
      return;
    }

    final md = '''# ${widget.homework.title} - 第${item.itemIndex}题

**题目**: ${item.question}
**类型**: ${item.typeLabel}
**目标**: ${item.objectiveMapping.map((om) => '目标${om.objectiveId}(${(om.contribution * 100).toInt()}%)').join(', ')}

---

$answer
''';

    // 复制到剪贴板
    await Clipboard.setData(ClipboardData(text: md));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制为 Markdown 格式到剪贴板')));
    }
  }

  // ── 重新提交 ──────────────────────────────────────────────────────────────
  Future<void> _resubmit(HomeworkItemModel item) async {
    final sub = _submissions.where((s) => s.itemId == item.id).firstOrNull;
    if (sub == null) return;

    // 清空控制器，让编辑区变为可编辑
    _answerControllers[item.id]?.clear();
    _submissions.removeWhere((s) => s.itemId == item.id);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请重新输入答案后点击提交')));
    }
  }

  // ── JSON 解析 ────────────────────────────────────────────────────────────
  dynamic _parseJson(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(text);
    if (match != null) {
      try {
        return _safeDecode(match.group(1)!);
      } catch (_) {}
    }
    try {
      return _safeDecode(text);
    } catch (_) {}
    return null;
  }

  dynamic _safeDecode(String s) {
    final objStart = s.indexOf('{');
    final objEnd = s.lastIndexOf('}');
    if (objStart >= 0 && objEnd > objStart) {
      return _doDecode(s.substring(objStart, objEnd + 1));
    }
    return _doDecode(s);
  }

  dynamic _doDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}
