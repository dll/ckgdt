import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../data/local/survey_dao.dart';
import '../../../data/local/class_dao.dart';
import '../../../services/auth_service.dart';
import 'survey_stats_page.dart';

/// 问卷管理页面 — 教师/管理员专用
/// 功能：问卷列表、创建/编辑/删除问卷、题目管理、发布/关闭、查看统计
class SurveyManagePage extends StatefulWidget {
  const SurveyManagePage({super.key});

  @override
  State<SurveyManagePage> createState() => _SurveyManagePageState();
}

class _SurveyManagePageState extends State<SurveyManagePage> {
  final _surveyDao = SurveyDao();
  final _classDao = ClassDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _surveys = [];
  Map<String, int> _overview = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      await _surveyDao.generateDemoData();
      await _loadData();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e')),
        );
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final surveys = await _surveyDao.getAllSurveys();
      final overview = await _surveyDao.getOverview();
      if (mounted) {
        setState(() {
          _surveys = surveys;
          _overview = overview;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('问卷管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _surveys.isEmpty
                  ? _buildEmptyState(primary)
                  : _buildContent(primary),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSurveyDialog(null),
        backgroundColor: primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(Color primary) {
    return ListView(
      children: [
        _buildOverviewCards(primary),
        const SizedBox(height: 80),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('暂无问卷', style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 12),
              Text('点击右下角按钮创建第一份问卷',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(Color primary) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // ── 概览统计卡片 ──────────────────────────────────────────────
        _buildOverviewCards(primary),
        const SizedBox(height: 8),

        // ── 问卷列表 ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '全部问卷',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_surveys.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        ..._surveys.map((survey) => _buildSurveyTile(survey, primary)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 概览统计卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOverviewCards(Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _overviewCard(
            '总问卷',
            '${_overview['total'] ?? 0}',
            Icons.assignment,
            primary,
          ),
          const SizedBox(width: 8),
          _overviewCard(
            '已发布',
            '${_overview['published'] ?? 0}',
            Icons.publish,
            Colors.green,
          ),
          const SizedBox(width: 8),
          _overviewCard(
            '草稿',
            '${_overview['draft'] ?? 0}',
            Icons.drafts,
            Colors.orange,
          ),
          const SizedBox(width: 8),
          _overviewCard(
            '总回收',
            '${_overview['responses'] ?? 0}',
            Icons.people,
            Colors.teal,
          ),
        ],
      ),
    );
  }

  Widget _overviewCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 问卷 ExpansionTile（含题目列表）
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSurveyTile(Map<String, dynamic> survey, Color primary) {
    final id = survey['id'] as int;
    final title = survey['title'] as String? ?? '未命名';
    final description = survey['description'] as String? ?? '';
    final status = survey['status'] as String? ?? 'draft';
    final totalResponses = survey['total_responses'] as int? ?? 0;
    final createdAt = survey['created_at'] as String? ?? '';
    final deadline = survey['deadline'] as String? ?? '';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'published':
        statusColor = Colors.green;
        statusLabel = '进行中';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'closed':
        statusColor = Colors.red;
        statusLabel = '已关闭';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = '草稿';
        statusIcon = Icons.edit_note;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          title: Text(
            title,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.people_outline,
                      size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 2),
                  Text(
                    '$totalResponses 份回收',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
          children: [
            // 问卷描述
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        description,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),

            // 时间信息
            if (createdAt.isNotEmpty || deadline.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    if (createdAt.isNotEmpty) ...[
                      Icon(Icons.calendar_today,
                          size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        '创建: ${_formatDate(createdAt)}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                    if (deadline.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.timer_outlined,
                          size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        '截止: $deadline',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),

            // 操作按钮行
            _buildSurveyActions(survey, status, primary),
            const Divider(height: 20),

            // 题目列表
            _SurveyQuestionsSection(
              surveyId: id,
              surveyStatus: status,
              surveyDao: _surveyDao,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurveyActions(
      Map<String, dynamic> survey, String status, Color primary) {
    final id = survey['id'] as int;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        // 编辑
        _actionChip(
          icon: Icons.edit,
          label: '编辑',
          color: Colors.blue,
          onTap: () => _showSurveyDialog(survey),
        ),

        // 发布 / 关闭
        if (status == 'draft')
          _actionChip(
            icon: Icons.publish,
            label: '发布',
            color: Colors.green,
            onTap: () => _publishSurvey(id),
          ),
        if (status == 'published')
          _actionChip(
            icon: Icons.close,
            label: '关闭',
            color: Colors.orange,
            onTap: () => _closeSurvey(id),
          ),

        // 统计
        _actionChip(
          icon: Icons.analytics_outlined,
          label: '统计',
          color: Colors.teal,
          onTap: () => _navigateToStats(id),
        ),

        // 删除
        _actionChip(
          icon: Icons.delete_outline,
          label: '删除',
          color: Colors.red,
          onTap: () => _confirmDeleteSurvey(id, survey['title'] ?? ''),
        ),
      ],
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 创建/编辑问卷对话框
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showSurveyDialog(Map<String, dynamic>? existing) async {
    final isNew = existing == null;
    final titleCtrl =
        TextEditingController(text: existing?['title'] as String? ?? '');
    final descCtrl = TextEditingController(
        text: existing?['description'] as String? ?? '');
    final deadlineCtrl =
        TextEditingController(text: existing?['deadline'] as String? ?? '');
    int? selectedClassId = existing?['class_id'] as int?;

    // 加载班级列表
    List<Map<String, dynamic>> classes = [];
    try {
      classes = await _classDao.getAllClasses();
    } catch (_) {}

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isNew ? '创建问卷' : '编辑问卷'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: '问卷标题 *',
                      hintText: '请输入问卷标题',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 描述
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '问卷描述',
                      hintText: '可选，描述问卷目的',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 关联班级
                  DropdownButtonFormField<int?>(
                    value: selectedClassId,
                    decoration: InputDecoration(
                      labelText: '关联班级（可选）',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('不指定班级'),
                      ),
                      ...classes.map((c) => DropdownMenuItem<int?>(
                            value: c['id'] as int,
                            child: Text(
                              c['name'] as String? ?? '未命名',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => selectedClassId = v),
                  ),
                  const SizedBox(height: 12),

                  // 截止时间
                  TextField(
                    controller: deadlineCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '截止时间（可选）',
                      hintText: '点击选择',
                      suffixIcon: const Icon(Icons.calendar_today, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(
                            const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                            const Duration(days: 365)),
                      );
                      if (date != null) {
                        setDialogState(() {
                          deadlineCtrl.text =
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                        });
                      }
                    },
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
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入问卷标题')),
                  );
                  return;
                }

                try {
                  final currentUser =
                      _authService.currentUser;

                  if (isNew) {
                    await _surveyDao.createSurvey(
                      title: title,
                      description:
                          descCtrl.text.trim().isNotEmpty
                              ? descCtrl.text.trim()
                              : null,
                      classId: selectedClassId,
                      creatorId: currentUser?.userId,
                      deadline:
                          deadlineCtrl.text.trim().isNotEmpty
                              ? deadlineCtrl.text.trim()
                              : null,
                    );
                  } else {
                    await _surveyDao.updateSurvey(
                      existing['id'] as int,
                      {
                        'title': title,
                        'description': descCtrl.text.trim(),
                        'class_id': selectedClassId,
                        'deadline': deadlineCtrl.text.trim().isNotEmpty
                            ? deadlineCtrl.text.trim()
                            : null,
                      },
                    );
                  }

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isNew ? '问卷创建成功' : '问卷更新成功'),
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
              child: Text(isNew ? '创建' : '保存'),
            ),
          ],
        ),
      ),
    );

    titleCtrl.dispose();
    descCtrl.dispose();
    deadlineCtrl.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 问卷操作
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _publishSurvey(int surveyId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认发布'),
        content: const Text('发布后学生可以填写此问卷，确定要发布吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child:
                const Text('发布', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _surveyDao.publishSurvey(surveyId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('问卷已发布'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('发布失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _closeSurvey(int surveyId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认关闭'),
        content: const Text('关闭后学生将无法继续填写此问卷，确定要关闭吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('关闭',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _surveyDao.closeSurvey(surveyId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('问卷已关闭'),
              backgroundColor: Colors.orange,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('关闭失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteSurvey(int surveyId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要删除问卷"${title.length > 20 ? '${title.substring(0, 20)}...' : title}"吗？\n\n此操作将同时删除所有题目和回答数据，不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _surveyDao.deleteSurvey(surveyId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('问卷已删除'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  void _navigateToStats(int surveyId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyStatsPage(surveyId: surveyId),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 辅助
  // ─────────────────────────────────────────────────────────────────────────

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate.length > 10 ? isoDate.substring(0, 10) : isoDate;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 题目管理区域（嵌入 ExpansionTile 内部）
// ═══════════════════════════════════════════════════════════════════════════

class _SurveyQuestionsSection extends StatefulWidget {
  final int surveyId;
  final String surveyStatus;
  final SurveyDao surveyDao;

  const _SurveyQuestionsSection({
    required this.surveyId,
    required this.surveyStatus,
    required this.surveyDao,
  });

  @override
  State<_SurveyQuestionsSection> createState() =>
      _SurveyQuestionsSectionState();
}

class _SurveyQuestionsSectionState extends State<_SurveyQuestionsSection> {
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final questions = await widget.surveyDao.getQuestions(widget.surveyId);
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

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Icon(Icons.list_alt, size: 16, color: primary),
            const SizedBox(width: 6),
            Text(
              '题目列表',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
            const Spacer(),
            if (_questions.isNotEmpty)
              Text(
                '${_questions.length} 题',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _showQuestionDialog(null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: primary),
                    const SizedBox(width: 2),
                    Text(
                      '添加题目',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 题目列表
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_questions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '暂无题目，点击上方按钮添加',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ),
          )
        else
          ..._questions.asMap().entries.map(
                (entry) => _buildQuestionItem(entry.key, entry.value, primary),
              ),
      ],
    );
  }

  Widget _buildQuestionItem(
      int index, Map<String, dynamic> question, Color primary) {
    final qText = question['question'] as String? ?? '';
    final qType = question['question_type'] as String? ?? 'single_choice';
    final seq = question['seq'] as int? ?? (index + 1);
    final optionsJson = question['options_json'] as String?;
    final isRequired = (question['is_required'] as int?) == 1;

    String typeLabel;
    Color typeColor;
    IconData typeIcon;
    switch (qType) {
      case 'single_choice':
        typeLabel = '单选';
        typeColor = Colors.blue;
        typeIcon = Icons.radio_button_checked;
        break;
      case 'multi_choice':
        typeLabel = '多选';
        typeColor = Colors.indigo;
        typeIcon = Icons.check_box;
        break;
      case 'rating':
        typeLabel = '评分';
        typeColor = Colors.amber;
        typeIcon = Icons.star;
        break;
      default:
        typeLabel = '文本';
        typeColor = Colors.teal;
        typeIcon = Icons.text_fields;
    }

    // 解析选项
    List<String> options = [];
    if (optionsJson != null && optionsJson.isNotEmpty) {
      try {
        options = List<String>.from(json.decode(optionsJson));
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 序号
              CircleAvatar(
                radius: 12,
                backgroundColor: primary.withValues(alpha: 0.1),
                child: Text(
                  '$seq',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 题目文本
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      qText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(typeIcon, size: 10, color: typeColor),
                              const SizedBox(width: 2),
                              Text(
                                typeLabel,
                                style: TextStyle(
                                    fontSize: 10, color: typeColor),
                              ),
                            ],
                          ),
                        ),
                        if (isRequired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '必答',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.red),
                            ),
                          ),
                        ],
                        if (options.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${options.length}个选项',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[500]),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 操作按钮
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 16, color: Colors.grey[400]),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onSelected: (v) {
                  if (v == 'edit') _showQuestionDialog(question);
                  if (v == 'delete') _confirmDeleteQuestion(question);
                  if (v == 'up' && index > 0) _reorderQuestion(index, -1);
                  if (v == 'down' && index < _questions.length - 1) {
                    _reorderQuestion(index, 1);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('编辑', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  if (index > 0)
                    const PopupMenuItem(
                      value: 'up',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.arrow_upward, size: 16),
                          SizedBox(width: 8),
                          Text('上移', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  if (index < _questions.length - 1)
                    const PopupMenuItem(
                      value: 'down',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.arrow_downward, size: 16),
                          SizedBox(width: 8),
                          Text('下移', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除',
                            style: TextStyle(
                                fontSize: 13, color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 展开选项预览
          if (options.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: options.map((opt) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey[700]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 添加/编辑题目对话框
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showQuestionDialog(Map<String, dynamic>? existing) async {
    final isNew = existing == null;
    final questionCtrl =
        TextEditingController(text: existing?['question'] as String? ?? '');
    String selectedType =
        existing?['question_type'] as String? ?? 'single_choice';
    bool isRequired = (existing?['is_required'] as int?) != 0;
    int seq = existing?['seq'] as int? ?? (_questions.length + 1);

    // 解析已有选项
    List<TextEditingController> optionControllers = [];
    if (existing != null) {
      final optionsJson = existing['options_json'] as String?;
      if (optionsJson != null && optionsJson.isNotEmpty) {
        try {
          final opts = List<String>.from(json.decode(optionsJson));
          for (final opt in opts) {
            optionControllers.add(TextEditingController(text: opt));
          }
        } catch (_) {}
      }
    }
    // 默认至少 2 个选项（选择题）
    if (optionControllers.isEmpty &&
        (selectedType == 'single_choice' ||
            selectedType == 'multi_choice')) {
      optionControllers = [
        TextEditingController(),
        TextEditingController(),
      ];
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final needOptions =
              selectedType == 'single_choice' ||
                  selectedType == 'multi_choice';

          return AlertDialog(
            title: Text(isNew ? '添加题目' : '编辑题目'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 题目内容
                    TextField(
                      controller: questionCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: '题目内容 *',
                        hintText: '请输入题目',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 题型选择
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: '题目类型 *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'single_choice',
                            child: Text('单选题')),
                        DropdownMenuItem(
                            value: 'multi_choice',
                            child: Text('多选题')),
                        DropdownMenuItem(
                            value: 'rating', child: Text('评分题')),
                        DropdownMenuItem(
                            value: 'text', child: Text('文本题')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          selectedType = v;
                          if ((v == 'single_choice' ||
                                  v == 'multi_choice') &&
                              optionControllers.isEmpty) {
                            optionControllers = [
                              TextEditingController(),
                              TextEditingController(),
                            ];
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    // 序号
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '显示序号',
                        hintText: '$seq',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      controller:
                          TextEditingController(text: '$seq'),
                      onChanged: (v) =>
                          seq = int.tryParse(v) ?? seq,
                    ),
                    const SizedBox(height: 12),

                    // 是否必答
                    SwitchListTile(
                      title: const Text('是否必答',
                          style: TextStyle(fontSize: 14)),
                      value: isRequired,
                      onChanged: (v) =>
                          setDialogState(() => isRequired = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),

                    // 选项编辑器（仅选择题）
                    if (needOptions) ...[
                      const Divider(),
                      Row(
                        children: [
                          const Text(
                            '选项列表',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                optionControllers
                                    .add(TextEditingController());
                              });
                            },
                            icon:
                                const Icon(Icons.add, size: 16),
                            label: const Text('添加选项',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize
                                      .shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...optionControllers
                          .asMap()
                          .entries
                          .map((entry) {
                        final optIndex = entry.key;
                        final ctrl = entry.value;
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors
                                    .grey[200],
                                child: Text(
                                  String.fromCharCode(
                                      65 + optIndex),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight:
                                        FontWeight.bold,
                                    color:
                                        Colors.grey[700],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: ctrl,
                                  decoration:
                                      InputDecoration(
                                    hintText:
                                        '选项 ${String.fromCharCode(65 + optIndex)}',
                                    border:
                                        OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                                  8),
                                    ),
                                    contentPadding:
                                        const EdgeInsets
                                            .symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  style:
                                      const TextStyle(
                                          fontSize: 13),
                                ),
                              ),
                              if (optionControllers
                                      .length >
                                  2)
                                IconButton(
                                  icon: Icon(
                                    Icons
                                        .remove_circle_outline,
                                    size: 18,
                                    color:
                                        Colors.red[300],
                                  ),
                                  padding:
                                      EdgeInsets.zero,
                                  constraints:
                                      const BoxConstraints(),
                                  onPressed: () {
                                    setDialogState(() {
                                      optionControllers
                                          .removeAt(
                                              optIndex);
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
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
                  final qText = questionCtrl.text.trim();
                  if (qText.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入题目内容')),
                    );
                    return;
                  }

                  // 收集选项
                  List<String>? options;
                  if (needOptions) {
                    options = optionControllers
                        .map((c) => c.text.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    if (options.length < 2) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('选择题至少需要2个选项')),
                      );
                      return;
                    }
                  }

                  try {
                    if (isNew) {
                      await widget.surveyDao.addQuestion(
                        surveyId: widget.surveyId,
                        question: qText,
                        questionType: selectedType,
                        options: options,
                        isRequired: isRequired,
                        seq: seq,
                      );
                    } else {
                      final data = <String, dynamic>{
                        'question': qText,
                        'question_type': selectedType,
                        'is_required': isRequired ? 1 : 0,
                        'seq': seq,
                        'options_json': options != null
                            ? json.encode(options)
                            : null,
                      };
                      await widget.surveyDao.updateQuestion(
                        existing['id'] as int,
                        data,
                      );
                    }

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              isNew ? '题目添加成功' : '题目更新成功'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadQuestions();
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
          );
        },
      ),
    );

    // 释放控制器
    questionCtrl.dispose();
    for (final c in optionControllers) {
      c.dispose();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 删除题目
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteQuestion(Map<String, dynamic> question) async {
    final qText = question['question'] as String? ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要删除题目"${qText.length > 20 ? '${qText.substring(0, 20)}...' : qText}"吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.surveyDao.deleteQuestion(question['id'] as int);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('题目已删除'),
              backgroundColor: Colors.green,
            ),
          );
          _loadQuestions();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 调整题目顺序
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _reorderQuestion(int currentIndex, int direction) async {
    final targetIndex = currentIndex + direction;
    if (targetIndex < 0 || targetIndex >= _questions.length) return;

    final currentQ = _questions[currentIndex];
    final targetQ = _questions[targetIndex];
    final currentSeq = currentQ['seq'] as int? ?? (currentIndex + 1);
    final targetSeq = targetQ['seq'] as int? ?? (targetIndex + 1);

    try {
      await widget.surveyDao.updateQuestion(
        currentQ['id'] as int,
        {'seq': targetSeq},
      );
      await widget.surveyDao.updateQuestion(
        targetQ['id'] as int,
        {'seq': currentSeq},
      );
      _loadQuestions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('排序失败: $e')),
        );
      }
    }
  }
}
