import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../data/local/homework_dao.dart';
import '../../../services/auth_service.dart';
import '../../../data/models/homework_model.dart';
import '../../../services/ai_service.dart';

/// 作业详情/提交页
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
      // 填充已有答案
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
                if (index == 0) return _buildHeader(theme);
                return _buildItem(theme, _items[index - 1]);
              },
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
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
                _tag(Icons.score, '总分 ${widget.homework.totalScore}'),
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
    // 查看该题的提交记录
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
            // 题目头部
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
            // 题目内容
            Text(item.question,
                style: const TextStyle(fontSize: 14, height: 1.5)),
            // 目标映射
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
            // 答案区域
            if (widget.isTeacher) ...[
              // 教师端：显示参考答案和学生提交
              _buildTeacherView(theme, item, sub),
            ] else ...[
              // 学生端：输入答案
              _buildStudentView(theme, item, sub, hasSubmitted, isGraded),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentView(ThemeData theme, HomeworkItemModel item,
      HomeworkSubmissionModel? sub, bool hasSubmitted, bool isGraded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasSubmitted || !isGraded) ...[
          TextField(
            controller: _answerControllers[item.id],
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '请输入你的答案...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ] else ...[
          // 显示已提交答案
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
        ],
      ],
    );
  }

  Widget _buildTeacherView(
      ThemeData theme, HomeworkItemModel item, HomeworkSubmissionModel? sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 参考答案
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
                  onChanged: (v) {
                    // 保存到临时变量
                  },
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: TextEditingController(
                          text: sub.score?.toString() ?? ''),
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
            ],
          ),
        ] else ...[
          Text('暂无提交',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ],
    );
  }

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

      // AI 批阅
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

  Future<void> _aiGradeAll() async {
    final submissions = await _dao.getSubmissions(widget.homework.id, _userId);
    for (final sub in submissions) {
      if (sub.status != 'submitted') continue;
      final item = _items.where((i) => i.id == sub.itemId).firstOrNull;
      if (item == null) continue;

      try {
        final prompt = '''你是一位严谨的教师，请批阅以下作业。

题目：${item.question}
类型：${item.typeLabel}
${item.referenceAnswer != null ? '参考答案：${item.referenceAnswer}' : ''}
学生答案：${sub.answerText ?? '(未填写)'}

满分 ${item.maxScore} 分。请：
1. 给出得分（0-${item.maxScore}）
2. 简要评语（优点+改进建议，100字以内）

返回 JSON：{"score": 分数, "comment": "评语"}''';

        final response = await _ai.chat([
          {'role': 'user', 'content': prompt}
        ]);
        final data = _parseJson(response);
        if (data != null) {
          final score = (data['score'] as num?)?.toInt() ?? 0;
          final comment = data['comment'] as String? ?? '';
          await _dao.updateAiGrade(sub.id, score, comment);
        }
      } catch (e) {
        // AI 批阅失败，保留 submitted 状态
      }
    }
    // 同步作业分数到达成度计算
    try {
      await _dao.syncToAchievementScores(widget.homework.courseId);
    } catch (_) {}
  }

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
    // 尝试提取 JSON 对象
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
