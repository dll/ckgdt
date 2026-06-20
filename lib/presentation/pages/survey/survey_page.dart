import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../data/local/survey_dao.dart';
import '../../../services/auth_service.dart';

/// 学生问卷调查页面 — 展示已发布的问卷，支持填写和提交
class SurveyPage extends StatefulWidget {
  const SurveyPage({super.key});

  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  final _surveyDao = SurveyDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _surveys = [];
  Set<int> _completedSurveyIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 初始化示例数据（首次）
      await _surveyDao.generateDemoData();

      final published = await _surveyDao.getSurveysByStatus('published');
      final userId = _authService.currentUser?.userId ?? '';

      // 检查哪些已回答
      final completed = <int>{};
      for (final s in published) {
        final sid = s['id'] as int;
        if (await _surveyDao.hasResponded(sid, userId)) {
          completed.add(sid);
        }
      }

      if (mounted) {
        setState(() {
          _surveys = published;
          _completedSurveyIds = completed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final pending = _surveys.where((s) => !_completedSurveyIds.contains(s['id'])).length;
    final done = _completedSurveyIds.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('问卷调查'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _surveys.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 统计卡片
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            primary.withValues(alpha: 0.08),
                            primary.withValues(alpha: 0.03),
                          ]),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.poll, color: primary, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('问卷调查',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: primary)),
                                  const SizedBox(height: 4),
                                  Text(
                                    pending > 0
                                        ? '有 $pending 份问卷等待填写'
                                        : '所有问卷已完成',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: pending > 0
                                            ? Colors.orange
                                            : Colors.green),
                                  ),
                                ],
                              ),
                            ),
                            _statBadge('待填', pending, Colors.orange),
                            const SizedBox(width: 8),
                            _statBadge('已完成', done, Colors.green),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 问卷列表
                      ..._surveys.map((s) => _buildSurveyCard(s)),
                    ],
                  ),
                ),
    );
  }

  Widget _statBadge(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('$count',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.poll_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('暂无可填写的问卷',
              style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('问卷发布后将在此显示',
              style: TextStyle(fontSize: 14, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildSurveyCard(Map<String, dynamic> survey) {
    final sid = survey['id'] as int;
    final isCompleted = _completedSurveyIds.contains(sid);
    final title = survey['title'] as String? ?? '未命名问卷';
    final desc = survey['description'] as String? ?? '';
    final deadline = survey['deadline'] as String?;
    final responses = survey['total_responses'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isCompleted ? null : () => _openSurvey(survey),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isCompleted ? '已完成' : '待填写',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCompleted ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text('$responses 人已填',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(desc,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
              if (deadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text('截止：${deadline.substring(0, 10)}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ],
              if (!isCompleted) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openSurvey(survey),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('填写问卷'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSurvey(Map<String, dynamic> survey) async {
    final sid = survey['id'] as int;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _SurveyFillPage(surveyId: sid, survey: survey),
      ),
    );
    if (result == true) {
      _loadData(); // 刷新完成状态
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 问卷填写页面
// ══════════════════════════════════════════════════════════════════════════════

class _SurveyFillPage extends StatefulWidget {
  final int surveyId;
  final Map<String, dynamic> survey;

  const _SurveyFillPage({required this.surveyId, required this.survey});

  @override
  State<_SurveyFillPage> createState() => _SurveyFillPageState();
}

class _SurveyFillPageState extends State<_SurveyFillPage> {
  final _surveyDao = SurveyDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _questions = [];
  final Map<String, dynamic> _answers = {}; // questionId → answer
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await _surveyDao.getQuestions(widget.surveyId);
      if (mounted) {
        setState(() {
          _questions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    // 验证必填项
    for (final q in _questions) {
      final qId = q['id'].toString();
      final isRequired = (q['is_required'] as int? ?? 1) == 1;
      if (isRequired && !_answers.containsKey(qId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请完成第 ${q['seq'] ?? ''} 题：${q['question']}'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final userId = _authService.currentUser?.userId ?? '';
      final success = await _surveyDao.submitResponse(
        surveyId: widget.surveyId,
        userId: userId,
        answers: _answers,
      );

      if (!mounted) return;

      if (success) {
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('提交失败，请重试'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交出错：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            const Text('提交成功',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('感谢您参与问卷调查！',
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
              },
              child: const Text('返回'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final title = widget.survey['title'] as String? ?? '问卷';
    final desc = widget.survey['description'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 问卷说明
                if (desc.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: primary.withValues(alpha: 0.05),
                    child: Text(desc,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                  ),

                // 题目列表
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) =>
                        _buildQuestion(_questions[index], index),
                  ),
                ),

                // 提交按钮
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send),
                        label: Text(_isSubmitting ? '提交中...' : '提交问卷'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildQuestion(Map<String, dynamic> q, int index) {
    final qId = q['id'].toString();
    final question = q['question'] as String? ?? '';
    final qType = q['question_type'] as String? ?? 'single_choice';
    final isRequired = (q['is_required'] as int? ?? 1) == 1;
    final optionsJson = q['options_json'] as String?;
    final options = optionsJson != null
        ? List<String>.from(json.decode(optionsJson))
        : <String>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 题号 + 题目
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${index + 1}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).colorScheme.primary)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          text: question,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87),
                          children: [
                            if (isRequired)
                              const TextSpan(
                                text: ' *',
                                style:
                                    TextStyle(color: Colors.red, fontSize: 16),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _questionTypeLabel(qType),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 答题区域
            if (qType == 'single_choice')
              _buildSingleChoice(qId, options)
            else if (qType == 'multi_choice')
              _buildMultiChoice(qId, options)
            else if (qType == 'rating')
              _buildRating(qId)
            else
              _buildTextInput(qId),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleChoice(String qId, List<String> options) {
    final selected = _answers[qId] as String?;
    return Column(
      children: options.map((opt) {
        final isSelected = selected == opt;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => setState(() => _answers[qId] = opt),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(opt,
                          style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.black87))),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultiChoice(String qId, List<String> options) {
    final selected = (_answers[qId] as List<String>?) ?? [];
    return Column(
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () {
              setState(() {
                final list = List<String>.from(selected);
                if (isSelected) {
                  list.remove(opt);
                } else {
                  list.add(opt);
                }
                _answers[qId] = list;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(opt,
                          style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.black87))),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRating(String qId) {
    final current = int.tryParse(_answers[qId]?.toString() ?? '') ?? 0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final star = i + 1;
            final isActive = star <= current;
            return GestureDetector(
              onTap: () =>
                  setState(() => _answers[qId] = star.toString()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  isActive ? Icons.star : Icons.star_border,
                  size: 40,
                  color: isActive ? Colors.amber : Colors.grey.shade300,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          current > 0 ? '$current / 5 分' : '请点击星星评分',
          style: TextStyle(
            fontSize: 13,
            color: current > 0 ? Colors.amber.shade700 : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildTextInput(String qId) {
    return TextField(
      maxLines: 3,
      decoration: InputDecoration(
        hintText: '请输入您的回答...',
        hintStyle: TextStyle(color: Colors.grey.shade400),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
      ),
      onChanged: (value) => _answers[qId] = value,
    );
  }

  String _questionTypeLabel(String type) {
    switch (type) {
      case 'single_choice':
        return '单选题';
      case 'multi_choice':
        return '多选题（可选多个）';
      case 'rating':
        return '评分题（1-5分）';
      case 'text':
        return '文本题';
      default:
        return type;
    }
  }
}
