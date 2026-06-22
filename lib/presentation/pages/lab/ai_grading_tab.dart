import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:convert';
import '../../../data/local/lab_task_dao.dart';
import '../../../data/local/grading_result_dao.dart';
import '../../../data/local/ai_config_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/agent/agents/grading_agent.dart';
import '../../../services/settings_service.dart';
import 'lab_tasks_page.dart';
import '../../../core/error_handler.dart';

/// 实验 AI 智能批阅 Tab — 仅教师/管理员可见
///
/// 四区结构：
/// ① 任务选择 + 批阅启动
/// ② 批阅结果列表 + 逐个核准
/// ③ 前 20% 优秀 / 后 20% 待改进报告展示
/// ④ 统计图表（成绩分布柱状图 / 维度雷达图 / 趋势折线图 / 达成度进度条）
class LabAiGradingTab extends StatefulWidget {
  final LabTaskDao labTaskDao;
  final AuthService authService;

  const LabAiGradingTab({
    super.key,
    required this.labTaskDao,
    required this.authService,
  });

  @override
  State<LabAiGradingTab> createState() => _LabAiGradingTabState();
}

class _LabAiGradingTabState extends State<LabAiGradingTab> {
  final _gradingAgent = GradingAgent();
  final _gradingDao = GradingResultDao();
  final _aiConfigDao = AiConfigDao();

  // ── 当前大模型名称（显示用）──
  String _modelLabel = '';

  // ── 单份批阅进行中的提交 id（行内 spinner）──
  int? _singleGradingId;

  // ── 任务数据 ──
  List<Map<String, dynamic>> _tasks = [];
  int? _selectedTaskId;
  Map<String, dynamic>? _selectedTask;

  // ── 提交数据 ──
  List<Map<String, dynamic>> _submissions = [];
  int _totalStudents = 0;

  // ── AI 批阅结果（内存暂存，核准前不写 DB）──
  // key: submission id → grading result map
  final Map<int, _GradingResult> _gradingResults = {};
  final Set<int> _approvedIds = {}; // 已核准的 submission id
  bool _isBatchGrading = false;
  int _gradingProgress = 0;
  int _gradingTotal = 0;
  String _gradingStatus = '';

  /// 增强批阅模式：用 OrchestratorAgent 串联 safety → lab_grading → ethics 三 Agent。
  /// 适合疑似 AI 代写 / 涉敏内容批阅；常规批阅保持关闭以省 token。
  bool _enhancedMode = false;

  // ── 复选框 ──
  final Set<int> _selectedForApproval = {};

  @override
  void initState() {
    super.initState();
    _loadModelLabel();
    _loadTasks();
  }

  Future<void> _loadModelLabel() async {
    try {
      final cfg = await _aiConfigDao.getConfig();
      if (mounted) {
        setState(() => _modelLabel = '${cfg.providerLabel} · ${cfg.model}');
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LabAiGrading.loadModelLabel', stack: st);
    }
  }

  Future<void> _loadTasks() async {
    final tasks = await widget.labTaskDao.getTasks();
    final total = await widget.labTaskDao.getActiveStudentCount();
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _totalStudents = total;
      });
    }
  }

  Future<void> _loadSubmissions() async {
    if (_selectedTaskId == null) return;
    final subs =
        await widget.labTaskDao.getSubmissions(taskId: _selectedTaskId);
    // 加载已有的批改结果
    _approvedIds.clear();
    for (final s in subs) {
      final sid = s['id'] as int;
      if (s['score'] != null && s['status'] == '已批改') {
        _approvedIds.add(sid);
        _gradingResults[sid] = _GradingResult(
          score: (s['score'] as num).toInt(),
          feedback: (s['feedback'] as String?) ?? '',
          dimensions: null,
          strengths: [],
          improvements: [],
          aiFlag: false,
          raw: null,
        );
      }
    }
    // 从 grading_results 恢复待审核的 AI 批阅结果
    try {
      final pending = await _gradingDao.getPendingResults('lab');
      for (final p in pending) {
        final tid = p['target_id'] as int;
        if (!_approvedIds.contains(tid) && !_gradingResults.containsKey(tid)) {
          Map<String, dynamic>? dims;
          try {
            dims = jsonDecode(p['dimensions'] as String? ?? '');
          } catch (e, st) {
            swallowDebug(e, tag: 'LabAiGrading.dims', stack: st);
          }
          List<String> strengths = [];
          try {
            strengths = (jsonDecode(p['strengths'] as String? ?? '[]') as List)
                .cast<String>();
          } catch (e, st) {
            swallowDebug(e, tag: 'LabAiGrading.strengths', stack: st);
          }
          List<String> improvements = [];
          try {
            improvements =
                (jsonDecode(p['improvements'] as String? ?? '[]') as List)
                    .cast<String>();
          } catch (e, st) {
            swallowDebug(e, tag: 'LabAiGrading.improvements', stack: st);
          }
          _gradingResults[tid] = _GradingResult(
            score: (p['score'] as num?)?.toInt() ?? 0,
            feedback: (p['feedback'] as String?) ?? '',
            dimensions: dims,
            strengths: strengths,
            improvements: improvements,
            aiFlag: (p['ai_flag'] as int?) == 1,
            raw: null,
          );
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LabAiGrading.loadSubs', stack: st);
    }
    if (mounted) setState(() => _submissions = subs);
  }

  void _onTaskSelected(int? taskId) {
    if (taskId == null) return;
    final task = _tasks.firstWhere((t) => t['id'] == taskId);
    setState(() {
      _selectedTaskId = taskId;
      _selectedTask = task;
      _gradingResults.clear();
      _approvedIds.clear();
      _selectedForApproval.clear();
    });
    _loadSubmissions();
  }

  // ═══════════ AI 批量批阅 ═══════════

  Future<void> _startBatchGrading() async {
    if (!await SettingsService.isTeacherAiGradingEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('教师 AI 批阅已关闭，请在「系统设置 → 教师 AI 批阅」中开启后再使用。'),
          ),
        );
      }
      return;
    }
    final ungradedSubs = _submissions
        .where((s) =>
            s['score'] == null && !_gradingResults.containsKey(s['id'] as int))
        .toList();

    if (ungradedSubs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有需要批阅的提交')),
        );
      }
      return;
    }

    setState(() {
      _isBatchGrading = true;
      _gradingProgress = 0;
      _gradingTotal = ungradedSubs.length;
      _gradingStatus = '正在批阅...';
    });

    for (int i = 0; i < ungradedSubs.length; i++) {
      if (!_isBatchGrading) break; // 用户取消

      final sub = ungradedSubs[i];
      final userName = (sub['user_id'] as String?) ?? '未知';

      setState(() {
        _gradingProgress = i;
        _gradingStatus = '正在批阅 ${i + 1}/$_gradingTotal: $userName';
      });

      await _gradeOne(sub);

      if (mounted) setState(() {});
    }

    if (mounted) {
      setState(() {
        _isBatchGrading = false;
        _gradingProgress = _gradingTotal;
        _gradingStatus = '批阅完成';
      });
    }
  }

  /// 批阅单份实验提交：PDF 兜底 → AI（标准/增强）→ 解析 → 存内存 → 持久化。
  ///
  /// 批量与单份批阅共用此方法。已核准的提交不再覆盖其持久化结果。
  Future<void> _gradeOne(Map<String, dynamic> sub) async {
    final sid = sub['id'] as int;
    final content = (sub['content'] as String?) ?? '';
    final filePaths = (sub['file_paths'] as String?) ?? '';
    final fileNames = (sub['file_names'] as String?) ?? '';
    final taskTitle =
        (sub['task_title'] as String?) ?? _selectedTask?['title'] ?? '';
    final requirements = _selectedTask?['requirements'] as String?;

    try {
      // 兜底：从 PDF 提取正文（旧提交只存了文件名）
      final prepared = await prepareGradingContent(
        rawContent: content,
        filePaths: filePaths,
        fileNames: fileNames,
      );
      if (!prepared.hasBody) {
        _gradingResults[sid] = _GradingResult(
          score: 0,
          feedback: '无法读取报告正文：PDF 文件未同步到本机或损坏，需手动批改',
          dimensions: null,
          strengths: [],
          improvements: [],
          aiFlag: false,
          raw: null,
        );
      } else {
        // 增强模式 → Orchestrator 链路（safety → grading → ethics）
        // 标准模式 → 单 Agent 直接批阅
        String result;
        String? ethicsAdvice;
        String? safetyNote;
        String? chainId;
        if (_enhancedMode) {
          final orchResult =
              await _gradingAgent.gradeSubmissionWithOrchestrator(
            taskTitle: taskTitle,
            content: prepared.content,
            maxScore: (sub['max_score'] as int?) ?? 100,
            requirements: requirements,
          );
          result = orchResult.gradingJson;
          ethicsAdvice = orchResult.ethicsAdvice;
          safetyNote = orchResult.safetyNote;
          chainId = orchResult.chainId;
        } else {
          result = await _gradingAgent.gradeSubmission(
            taskTitle: taskTitle,
            content: prepared.content,
            maxScore: (sub['max_score'] as int?) ?? 100,
            requirements: requirements,
          );
        }

        final parsed = tryParseGradingJson(result);
        if (parsed != null) {
          final score = (parsed['score'] as num?)?.toInt() ?? 0;
          var feedback = formatGradingFeedback(parsed);
          // 增强模式：把 ethics + safety 摘要附加到反馈尾部，写入 grading_results
          if (_enhancedMode) {
            final extra = StringBuffer();
            if (safetyNote != null && safetyNote.trim().isNotEmpty) {
              extra.writeln('\n---\n## 🛡 安全审查\n$safetyNote');
            }
            if (ethicsAdvice != null && ethicsAdvice.trim().isNotEmpty) {
              extra.writeln('\n---\n## ⚖️ 学术伦理建议\n$ethicsAdvice');
            }
            if (chainId != null) {
              extra.writeln('\n_调用链: ${chainId}_');
            }
            if (extra.isNotEmpty) feedback = '$feedback${extra.toString()}';
          }
          final dims = parsed['dimensions'] as Map<String, dynamic>?;
          final strengths =
              (parsed['strengths'] as List?)?.map((e) => e.toString()).toList() ??
                  [];
          final improvements = (parsed['improvements'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final aiFlag = parsed['ai_flag'] == true;

          _gradingResults[sid] = _GradingResult(
            score: score,
            feedback: feedback,
            dimensions: dims,
            strengths: strengths,
            improvements: improvements,
            aiFlag: aiFlag,
            raw: parsed,
          );
        } else {
          // AI 返回了非 JSON，用原始文本作为反馈
          _gradingResults[sid] = _GradingResult(
            score: 0,
            feedback: result,
            dimensions: null,
            strengths: [],
            improvements: [],
            aiFlag: false,
            raw: null,
          );
        }
      }
    } catch (e) {
      _gradingResults[sid] = _GradingResult(
        score: 0,
        feedback: '批阅失败: $e',
        dimensions: null,
        strengths: [],
        improvements: [],
        aiFlag: false,
        raw: null,
      );
    }

    // 持久化（已核准的不覆盖）
    if (!_approvedIds.contains(sid)) {
      final r = _gradingResults[sid]!;
      await _gradingDao.deletePendingForTarget('lab', sid);
      await _gradingDao.saveResult(
        domain: 'lab',
        targetId: sid,
        scorerId: widget.authService.getCurrentUserId() ?? '',
        rawJson: r.raw != null ? jsonEncode(r.raw) : null,
        score: r.score.toDouble(),
        feedback: r.feedback,
        dimensions: r.dimensions,
        strengths: r.strengths,
        improvements: r.improvements,
        aiFlag: r.aiFlag,
      );
    }
  }

  /// 单份 AI 批阅（行内触发）。带教师 AI 批阅总开关检查 + 行内 spinner。
  /// 沿用当前 _enhancedMode 开关（标准/增强链路）。
  Future<void> _gradeSingle(Map<String, dynamic> sub) async {
    if (!await SettingsService.isTeacherAiGradingEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('教师 AI 批阅已关闭，请在「系统设置 → 教师 AI 批阅」中开启后再使用。'),
          ),
        );
      }
      return;
    }
    final sid = sub['id'] as int;
    setState(() => _singleGradingId = sid);
    await _gradeOne(sub);
    if (mounted) setState(() => _singleGradingId = null);
  }

  // ═══════════ 核准操作 ═══════════

  Future<void> _approveOne(int submissionId) async {
    final result = _gradingResults[submissionId];
    if (result == null) return;

    await widget.labTaskDao.gradeSubmission(
      submissionId,
      score: result.score,
      feedback: result.feedback,
      scorerId: widget.authService.getCurrentUserId(),
    );

    // 更新 grading_results 状态
    try {
      final pending =
          await _gradingDao.getPendingResults('lab', targetId: submissionId);
      for (final p in pending) {
        await _gradingDao.approveResult(
            p['id'] as int, widget.authService.getCurrentUserId() ?? '');
      }
    } catch (e) {
      swallow(e, tag: 'LabAiGrading.approveStatus');
    }

    // 通知学生 + 触发同步（让学生端尽快看到分数）
    try {
      final sub = _submissions.firstWhere(
        (s) => (s['id'] as int?) == submissionId,
        orElse: () => <String, dynamic>{},
      );
      final studentId = sub['user_id'] as String?;
      if (studentId != null && studentId.isNotEmpty) {
        await NotificationService().notifyLabGradeApproved(
          studentId: studentId,
          taskTitle: _selectedTask?['title'] as String? ?? '实验',
          score: result.score,
        );
        unawaited(SyncService().uploadStudentData(studentId));
      }
    } catch (e) {
      swallow(e, tag: 'LabAiGrading.notifySync');
    }

    setState(() {
      _approvedIds.add(submissionId);
      _selectedForApproval.remove(submissionId);
    });
  }

  Future<void> _approveBatch() async {
    for (final sid in _selectedForApproval.toList()) {
      if (!_approvedIds.contains(sid)) {
        await _approveOne(sid);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已核准 ${_selectedForApproval.length} 份')),
      );
      _selectedForApproval.clear();
      setState(() {});
    }
  }

  // ═══════════ 调整分数 ══════════

  void _showAdjustDialog(int submissionId, Map<String, dynamic> sub) {
    final result = _gradingResults[submissionId];
    if (result == null) return;

    int adjustedScore = result.score;
    final feedbackCtrl = TextEditingController(text: result.feedback);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit_note, size: 20),
              const SizedBox(width: 8),
              Text('调整批阅 — ${sub['user_id'] ?? ''}',
                  style: const TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 学生提交内容预览
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (sub['content'] as String?)
                              ?.substring(
                                  0,
                                  ((sub['content'] as String?)?.length ?? 0) >
                                          300
                                      ? 300
                                      : (sub['content'] as String?)?.length ??
                                          0)
                              .toString() ??
                          '无内容',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 分数调整
                  Text('分数: $adjustedScore',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Slider(
                    value: adjustedScore.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$adjustedScore',
                    onChanged: (v) =>
                        setDialogState(() => adjustedScore = v.round()),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [0, 60, 70, 80, 85, 90, 95, 100]
                        .map((v) => ActionChip(
                              label: Text('$v'),
                              onPressed: () =>
                                  setDialogState(() => adjustedScore = v),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  // 反馈编辑
                  TextField(
                    controller: feedbackCtrl,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: '批阅反馈',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                _gradingResults[submissionId] = _GradingResult(
                  score: adjustedScore,
                  feedback: feedbackCtrl.text,
                  dimensions: result.dimensions,
                  strengths: result.strengths,
                  improvements: result.improvements,
                  aiFlag: result.aiFlag,
                  raw: result.raw,
                );
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('保存调整'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════ 查看详情 ══════════

  void _showDetailDialog(int submissionId, Map<String, dynamic> sub) {
    final result = _gradingResults[submissionId];
    if (result == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.aiFlag ? Icons.warning : Icons.grading,
              color: result.aiFlag ? Colors.orange : Colors.blue,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text('批阅详情 — ${sub['user_id'] ?? ''}',
                style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 分数卡
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: _scoreColor(result.score).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              _scoreColor(result.score).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Text('${result.score}',
                            style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: _scoreColor(result.score))),
                        Text(_scoreLabel(result.score),
                            style: TextStyle(
                                fontSize: 14,
                                color: _scoreColor(result.score))),
                      ],
                    ),
                  ),
                ),
                if (result.aiFlag) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange, size: 18),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text('AI 检测到此报告可能为 AI 生成，已扣分',
                              style: TextStyle(
                                  color: Colors.orange, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // 维度评分
                if (result.dimensions != null) ...[
                  const Text('各维度评分',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...result.dimensions!.entries.map((e) {
                    final d = e.value as Map<String, dynamic>? ?? {};
                    final dimScore = (d['score'] as num?)?.toDouble() ?? 0;
                    final dimMax = (d['max'] as num?)?.toDouble() ?? 1;
                    final comment = d['comment'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(_dimLabel(e.key),
                                      style: const TextStyle(fontSize: 13))),
                              Text('${dimScore.toInt()}/${dimMax.toInt()}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _scoreColor(
                                          (dimScore / dimMax * 100).toInt()))),
                            ],
                          ),
                          const SizedBox(height: 2),
                          LinearProgressIndicator(
                            value: dimMax > 0 ? dimScore / dimMax : 0,
                            backgroundColor: Colors.grey.withValues(alpha: 0.2),
                            color:
                                _scoreColor((dimScore / dimMax * 100).toInt()),
                          ),
                          if (comment.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(comment,
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[600])),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
                // 优点
                if (result.strengths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('优点',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ...result.strengths.map((s) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('✓ ',
                                style: TextStyle(
                                    color: Colors.green, fontSize: 13)),
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      )),
                ],
                // 改进建议
                if (result.improvements.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('改进建议',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ...result.improvements.map((s) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('→ ',
                                style: TextStyle(
                                    color: Colors.orange, fontSize: 13)),
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  // ═══════════ 辅助函数 ═══════════

  Color _scoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 75) return Colors.blue;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _scoreLabel(int score) {
    if (score >= 90) return '优秀';
    if (score >= 80) return '良好';
    if (score >= 70) return '中等';
    if (score >= 60) return '及格';
    return '不及格';
  }

  String _dimLabel(String key) {
    const labels = {
      'completion': '实验完成度',
      'code_quality': '代码质量',
      'report_quality': '报告质量',
      'problem_analysis': '问题分析',
      'innovation': '创新性',
    };
    return labels[key] ?? key;
  }

  // ═══════════ 构建 UI ═══════════

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadTasks();
        if (_selectedTaskId != null) await _loadSubmissions();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── ① 任务选择 + 批阅启动 ──
          _buildTaskSelector(primary),
          const SizedBox(height: 12),

          // ── ② 批阅结果列表 + 核准 ──
          if (_selectedTaskId != null) _buildGradingList(primary),

          // ── ③ 优差报告展示 ──
          if (_hasGradedResults) ...[
            const SizedBox(height: 16),
            _buildTopBottomReports(primary),
          ],

          // ── ④ 统计图表 ──
          if (_hasGradedResults) ...[
            const SizedBox(height: 16),
            _buildStatisticsCharts(primary),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  bool get _hasGradedResults =>
      _gradingResults.values.where((r) => r.score > 0).length >= 2;

  // ═══════════ ① 任务选择器 ═══════════

  Widget _buildTaskSelector(Color primary) {
    final submitted = _submissions.where((s) => s['content'] != null).length;
    final graded = _approvedIds.length;
    final pendingAi =
        _gradingResults.keys.where((id) => !_approvedIds.contains(id)).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: primary, size: 20),
                const SizedBox(width: 8),
                const Text('AI 智能批阅',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_modelLabel.isNotEmpty) _modelBadge(primary),
              ],
            ),
            const SizedBox(height: 12),
            // 任务下拉选择
            DropdownButtonFormField<int>(
              initialValue: _selectedTaskId,
              decoration: const InputDecoration(
                labelText: '选择实验任务',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _tasks
                  .map((t) => DropdownMenuItem<int>(
                        value: t['id'] as int,
                        child: Text(t['title'] as String? ?? '未命名',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _isBatchGrading ? null : _onTaskSelected,
            ),
            if (_selectedTaskId != null) ...[
              const SizedBox(height: 10),
              // 统计信息
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _statChip('已提交', '$submitted/$_totalStudents', Colors.blue),
                  _statChip('已核准', '$graded', Colors.green),
                  _statChip('待核准', '$pendingAi', Colors.orange),
                  _statChip(
                      '未批阅', '${submitted - graded - pendingAi}', Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
              // 批阅按钮 + 进度
              if (_isBatchGrading) ...[
                LinearProgressIndicator(
                  value:
                      _gradingTotal > 0 ? _gradingProgress / _gradingTotal : 0,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(_gradingStatus,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _isBatchGrading = false),
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text('停止'),
                    ),
                  ],
                ),
              ] else
                Column(
                  children: [
                    // 增强模式开关 — Orchestrator 串联 safety + grading + ethics
                    Row(
                      children: [
                        Switch(
                          value: _enhancedMode,
                          onChanged: (v) => setState(() => _enhancedMode = v),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Tooltip(
                            message: '开启后每份报告会经过：\n'
                                '🛡 内容安全审查 → 📝 主批阅 → ⚖️ 学术伦理建议\n'
                                '更严谨但 Token 消耗约 3 倍，建议疑似 AI 代写时启用',
                            child: Row(
                              children: [
                                Icon(
                                  _enhancedMode
                                      ? Icons.shield
                                      : Icons.shield_outlined,
                                  size: 16,
                                  color: _enhancedMode ? primary : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _enhancedMode ? '增强批阅（3 Agent 链路）' : '标准批阅',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _enhancedMode
                                          ? primary
                                          : Colors.grey[700],
                                      fontWeight: _enhancedMode
                                          ? FontWeight.w600
                                          : FontWeight.normal),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _startBatchGrading,
                        icon: Icon(
                            _enhancedMode
                                ? Icons.auto_awesome_motion
                                : Icons.auto_awesome,
                            size: 18),
                        label:
                            Text(_enhancedMode ? '开始增强 AI 批阅' : '开始批量 AI 批阅'),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modelBadge(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined, size: 13, color: primary),
          const SizedBox(width: 4),
          Text(_modelLabel,
              style: TextStyle(
                  fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label $value',
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ═══════════ ② 批阅结果列表 ═══════════

  Widget _buildGradingList(Color primary) {
    if (_submissions.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('暂无提交数据', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    // 按分数排序：未批阅在前，已批阅按分数排
    final sortedSubs = List<Map<String, dynamic>>.from(_submissions);
    sortedSubs.sort((a, b) {
      final aResult = _gradingResults[a['id'] as int];
      final bResult = _gradingResults[b['id'] as int];
      final aApproved = _approvedIds.contains(a['id'] as int);
      final bApproved = _approvedIds.contains(b['id'] as int);
      // 已核准的排后面
      if (aApproved != bApproved) return aApproved ? 1 : -1;
      // 有结果的排前面
      if ((aResult != null) != (bResult != null)) {
        return aResult != null ? -1 : 1;
      }
      // 都有结果的按分数排序
      if (aResult != null && bResult != null) {
        return bResult.score.compareTo(aResult.score);
      }
      return 0;
    });

    final unapprovedWithResults =
        _gradingResults.keys.where((id) => !_approvedIds.contains(id)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('批阅结果 / 核准',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                if (unapprovedWithResults.isNotEmpty) ...[
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedForApproval.length ==
                            unapprovedWithResults.length) {
                          _selectedForApproval.clear();
                        } else {
                          _selectedForApproval
                            ..clear()
                            ..addAll(unapprovedWithResults);
                        }
                      });
                    },
                    child: Text(
                      _selectedForApproval.length ==
                              unapprovedWithResults.length
                          ? '取消全选'
                          : '全选待核准',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _selectedForApproval.isEmpty ? null : _approveBatch,
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: Text('批量核准(${_selectedForApproval.length})',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
            const Divider(height: 12),
            ...sortedSubs.map((sub) {
              final sid = sub['id'] as int;
              final result = _gradingResults[sid];
              final isApproved = _approvedIds.contains(sid);
              final userId = sub['user_id'] as String? ?? '';

              return _buildGradingItem(
                  sub, sid, result, isApproved, userId, primary);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildGradingItem(
    Map<String, dynamic> sub,
    int sid,
    _GradingResult? result,
    bool isApproved,
    String userId,
    Color primary,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isApproved
            ? Colors.green.withValues(alpha: 0.05)
            : result != null
                ? (result.aiFlag
                    ? Colors.orange.withValues(alpha: 0.08)
                    : Colors.blue.withValues(alpha: 0.05))
                : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: isApproved
            ? null
            : (result != null
                ? Checkbox(
                    value: _selectedForApproval.contains(sid),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedForApproval.add(sid);
                        } else {
                          _selectedForApproval.remove(sid);
                        }
                      });
                    },
                  )
                : const SizedBox(width: 40)),
        title: Row(
          children: [
            Text(userId,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (result != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _scoreColor(result.score).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${result.score}分',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _scoreColor(result.score))),
              ),
            const SizedBox(width: 6),
            if (result != null)
              Text(_scoreLabel(result.score),
                  style: TextStyle(
                      fontSize: 11, color: _scoreColor(result.score))),
            if (result?.aiFlag == true) ...[
              const SizedBox(width: 4),
              const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
            ],
            if (isApproved) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('已核准',
                    style: TextStyle(fontSize: 10, color: Colors.green)),
              ),
            ],
          ],
        ),
        subtitle: result != null
            ? Text(
                result.feedback.length > 200
                    ? '${result.feedback.substring(0, 200)}...'
                    : result.feedback,
                style: const TextStyle(fontSize: 11),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                sub['content'] != null ? '等待批阅' : '未提交',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
        trailing: _buildTrailing(sub, sid, result, isApproved, primary),
      ),
    );
  }

  Widget? _buildTrailing(
    Map<String, dynamic> sub,
    int sid,
    _GradingResult? result,
    bool isApproved,
    Color primary,
  ) {
    if (result != null && !isApproved) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.visibility, size: 18),
            tooltip: '查看详情',
            onPressed: () => _showDetailDialog(sid, sub),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: '调整',
            onPressed: () => _showAdjustDialog(sid, sub),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            tooltip: '核准',
            color: Colors.green,
            onPressed: () => _approveOne(sid),
          ),
        ],
      );
    }
    if (isApproved) {
      return IconButton(
        icon: const Icon(Icons.visibility, size: 18),
        tooltip: '查看详情',
        onPressed: () => _showDetailDialog(sid, sub),
      );
    }
    if (sub['content'] == null) return null;
    if (_singleGradingId == sid) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return IconButton(
      icon: const Icon(Icons.auto_awesome, size: 18),
      tooltip: 'AI 批阅此份',
      color: primary,
      onPressed: (_isBatchGrading || _singleGradingId != null)
          ? null
          : () => _gradeSingle(sub),
    );
  }

  // ═══════════ ③ 优差报告展示 ═══════════

  Widget _buildTopBottomReports(Color primary) {
    // 收集所有有分数的结果
    final scored = <_ScoredEntry>[];
    for (final sub in _submissions) {
      final sid = sub['id'] as int;
      final result = _gradingResults[sid];
      if (result != null && result.score > 0) {
        scored.add(_ScoredEntry(
          userId: sub['user_id'] as String? ?? '',
          score: result.score,
          strengths: result.strengths,
          improvements: result.improvements,
          feedback: result.feedback,
        ));
      }
    }

    if (scored.length < 5) return const SizedBox.shrink();

    scored.sort((a, b) => b.score.compareTo(a.score));
    final topCount = (scored.length * 0.2).ceil().clamp(1, scored.length);
    final bottomCount = (scored.length * 0.2).ceil().clamp(1, scored.length);
    final topEntries = scored.take(topCount).toList();
    final bottomEntries = scored.reversed.take(bottomCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.insights, size: 18),
            const SizedBox(width: 8),
            const Text('优差报告展示',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('前后各 20%',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 8),
        // 优秀报告
        _buildReportSection(
          title: '优秀报告 (前$topCount名)',
          icon: Icons.emoji_events,
          color: Colors.green,
          entries: topEntries,
          showStrengths: true,
        ),
        const SizedBox(height: 8),
        // 待改进报告
        _buildReportSection(
          title: '待改进报告 (后$bottomCount名)',
          icon: Icons.trending_down,
          color: Colors.red,
          entries: bottomEntries,
          showStrengths: false,
        ),
      ],
    );
  }

  Widget _buildReportSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<_ScoredEntry> entries,
    required bool showStrengths,
  }) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(title,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        initiallyExpanded: true,
        children: entries.map((e) {
          final items = showStrengths ? e.strengths : e.improvements;
          return ListTile(
            dense: true,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _scoreColor(e.score).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('${e.score}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _scoreColor(e.score))),
              ),
            ),
            title: Text(e.userId,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (items.isNotEmpty)
                  ...items.take(3).map((s) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(showStrengths ? '✓ ' : '→ ',
                                style: TextStyle(
                                    color: showStrengths
                                        ? Colors.green
                                        : Colors.orange,
                                    fontSize: 12)),
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ))
                else
                  Text(
                      e.feedback.length > 200
                          ? '${e.feedback.substring(0, 200)}...'
                          : e.feedback,
                      style: const TextStyle(fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════ ④ 统计图表 ═══════════

  Widget _buildStatisticsCharts(Color primary) {
    // 收集数据
    final scores = <int>[];
    final dimTotals = <String, List<double>>{};

    for (final sub in _submissions) {
      final sid = sub['id'] as int;
      final result = _gradingResults[sid];
      if (result != null && result.score > 0) {
        scores.add(result.score);
        if (result.dimensions != null) {
          for (final e in result.dimensions!.entries) {
            final d = e.value as Map<String, dynamic>? ?? {};
            final dimScore = (d['score'] as num?)?.toDouble() ?? 0;
            final dimMax = (d['max'] as num?)?.toDouble() ?? 1;
            dimTotals.putIfAbsent(e.key, () => []).add(dimScore / dimMax);
          }
        }
      }
    }

    if (scores.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.bar_chart, size: 18),
            SizedBox(width: 8),
            Text('统计分析',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        // 成绩分布柱状图 + 维度雷达图
        SizedBox(
          height: 240,
          child: Row(
            children: [
              Expanded(child: _buildDistributionChart(scores, primary)),
              const SizedBox(width: 8),
              Expanded(child: _buildRadarChart(dimTotals, primary)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 趋势折线图 + 达成度进度条
        SizedBox(
          height: 240,
          child: Row(
            children: [
              Expanded(child: _buildTrendChart(primary)),
              const SizedBox(width: 8),
              Expanded(child: _buildAchievementProgress(scores, primary)),
            ],
          ),
        ),
      ],
    );
  }

  // ── 成绩分布柱状图 ──

  Widget _buildDistributionChart(List<int> scores, Color primary) {
    // 分段统计
    int excellent = 0, good = 0, medium = 0, pass = 0, fail = 0;
    for (final s in scores) {
      if (s >= 90) {
        excellent++;
      } else if (s >= 80) {
        good++;
      } else if (s >= 70) {
        medium++;
      } else if (s >= 60) {
        pass++;
      } else {
        fail++;
      }
    }

    final data = [fail, pass, medium, good, excellent];
    final labels = ['不及格', '及格', '中等', '良好', '优秀'];
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.blue,
      Colors.green,
    ];
    final maxVal = data
        .reduce((a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('成绩分布',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal + 1,
                  barGroups: List.generate(5, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: data[i].toDouble(),
                          color: colors[i],
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ],
                      showingTooltipIndicators: data[i] > 0 ? [0] : [],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(labels[v.toInt()],
                              style: const TextStyle(fontSize: 10)),
                        ),
                      ),
                    ),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, gi, rod, ri) {
                        return BarTooltipItem(
                          '${rod.toY.toInt()}人',
                          const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 维度雷达图 ──

  Widget _buildRadarChart(Map<String, List<double>> dimTotals, Color primary) {
    if (dimTotals.isEmpty) {
      return const Card(
        child:
            Center(child: Text('暂无维度数据', style: TextStyle(color: Colors.grey))),
      );
    }

    // 计算每个维度的平均达成率
    final keys = dimTotals.keys.toList();
    final avgRates = keys.map((k) {
      final list = dimTotals[k]!;
      return list.reduce((a, b) => a + b) / list.length;
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('维度分析',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  tickCount: 4,
                  ticksTextStyle: const TextStyle(fontSize: 0),
                  tickBorderData:
                      BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  gridBorderData:
                      BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  radarBorderData: const BorderSide(color: Colors.transparent),
                  getTitle: (index, _) {
                    if (index >= keys.length) {
                      return const RadarChartTitle(text: '');
                    }
                    return RadarChartTitle(
                      text: _dimLabel(keys[index]),
                      angle: 0,
                    );
                  },
                  dataSets: [
                    RadarDataSet(
                      dataEntries: avgRates
                          .map((r) => RadarEntry(value: r * 100))
                          .toList(),
                      fillColor: primary.withValues(alpha: 0.2),
                      borderColor: primary,
                      borderWidth: 2,
                      entryRadius: 3,
                    ),
                  ],
                  titlePositionPercentageOffset: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 趋势折线图 ──

  Widget _buildTrendChart(Color primary) {
    // 按实验任务顺序收集平均分
    final taskAvgs = <String, double>{};
    final taskOrder = <String>[];

    for (final task in _tasks) {
      final tid = task['id'] as int;
      final title = (task['title'] as String?) ?? 'T$tid';
      final taskSubs = _submissions.where((s) => s['task_id'] == tid);
      final taskScores = <int>[];
      for (final s in taskSubs) {
        final sid = s['id'] as int;
        final result = _gradingResults[sid];
        if (result != null && result.score > 0) {
          taskScores.add(result.score);
        }
      }
      if (taskScores.isNotEmpty) {
        taskAvgs[title] =
            taskScores.reduce((a, b) => a + b) / taskScores.length;
        taskOrder.add(title);
      }
    }

    if (taskAvgs.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('趋势分析',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              Expanded(
                child: Center(
                    child: Text('至少需要批阅2个实验的数据',
                        style: TextStyle(color: Colors.grey))),
              ),
            ],
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < taskOrder.length; i++) {
      spots.add(FlSpot(i.toDouble(), taskAvgs[taskOrder[i]]!));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('趋势分析',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= taskOrder.length) {
                            return const SizedBox.shrink();
                          }
                          final label = taskOrder[idx];
                          // 截取短标签
                          final short =
                              label.length > 4 ? label.substring(0, 4) : label;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(short,
                                style: const TextStyle(fontSize: 9)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}',
                            style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 20,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 达成度进度条 ──

  Widget _buildAchievementProgress(List<int> scores, Color primary) {
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    final passRate = scores.where((s) => s >= 60).length / scores.length * 100;
    final excellentRate =
        scores.where((s) => s >= 90).length / scores.length * 100;

    // 课程目标达成度
    final objectives = [
      _AchievementItem('平均分达成', avg, 75, '目标: 平均分≥75'),
      _AchievementItem('及格率', passRate, 90, '目标: 及格率≥90%'),
      _AchievementItem('优秀率', excellentRate, 20, '目标: 优秀率≥20%'),
      _AchievementItem(
          '提交率', _submissions.length / _totalStudents * 100, 95, '目标: 提交率≥95%'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('达成度分析',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: objectives.map((obj) {
                  final rate = (obj.value / obj.target).clamp(0.0, 1.5);
                  final achieved = obj.value >= obj.target;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              achieved
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 14,
                              color: achieved ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(obj.label,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            Text(
                              '${obj.value.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: achieved ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Stack(
                          children: [
                            LinearProgressIndicator(
                              value: rate.clamp(0.0, 1.0),
                              backgroundColor:
                                  Colors.grey.withValues(alpha: 0.2),
                              color: achieved ? Colors.green : Colors.orange,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(obj.hint,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[500])),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════ 数据模型 ═══════════

class _GradingResult {
  int score;
  String feedback;
  Map<String, dynamic>? dimensions;
  List<String> strengths;
  List<String> improvements;
  bool aiFlag;
  Map<String, dynamic>? raw;

  _GradingResult({
    required this.score,
    required this.feedback,
    this.dimensions,
    required this.strengths,
    required this.improvements,
    required this.aiFlag,
    this.raw,
  });
}

class _ScoredEntry {
  final String userId;
  final int score;
  final List<String> strengths;
  final List<String> improvements;
  final String feedback;

  _ScoredEntry({
    required this.userId,
    required this.score,
    required this.strengths,
    required this.improvements,
    required this.feedback,
  });
}

class _AchievementItem {
  final String label;
  final double value;
  final double target;
  final String hint;

  _AchievementItem(this.label, this.value, this.target, this.hint);
}
