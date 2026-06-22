import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/assessment_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/grading_result_dao.dart';
import '../../../data/local/ai_config_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/agent/agents/grading_agent.dart';
import '../../../services/pdf_text_service.dart';
import '../../../services/settings_service.dart';
import '../../../core/error_handler.dart';

/// 考核 AI 智能批阅 Tab — 仅教师/管理员可见
///
/// 四区结构：
/// ① 报告类型选择 + 批阅启动
/// ② 批阅结果列表 + 逐个核准
/// ③ 前 20% 优秀 / 后 20% 待改进报告展示
/// ④ 统计图表（成绩分布 / 维度雷达 / 达成度）
class AssessmentAiGradingTab extends StatefulWidget {
  final AuthService authService;

  const AssessmentAiGradingTab({super.key, required this.authService});

  @override
  State<AssessmentAiGradingTab> createState() => _AssessmentAiGradingTabState();
}

class _AssessmentAiGradingTabState extends State<AssessmentAiGradingTab> {
  final _gradingAgent = GradingAgent();
  final _assessmentDao = AssessmentDao();
  final _gradingDao = GradingResultDao();
  final _aiConfigDao = AiConfigDao();

  // ── 当前大模型名称（显示用）──
  String _modelLabel = '';

  // ── 单份批阅进行中的报告 id（行内 spinner）──
  int? _singleGradingId;

  // ── 报告数据 ──
  List<Map<String, dynamic>> _reports = [];
  String _selectedReportType = '全部';
  final _reportTypes = ['全部', '答辩报告', '个人报告', '小组报告', '项目报告'];

  // ── AI 批阅结果 ──
  final Map<int, _GradingResult> _gradingResults = {};
  final Set<int> _approvedIds = {};
  bool _isBatchGrading = false;
  int _gradingProgress = 0;
  int _gradingTotal = 0;
  String _gradingStatus = '';

  // ── 复选框 ──
  final Set<int> _selectedForApproval = {};

  @override
  void initState() {
    super.initState();
    _loadModelLabel();
    _loadReports();
  }

  Future<void> _loadModelLabel() async {
    try {
      final cfg = await _aiConfigDao.getConfig();
      if (mounted) {
        setState(() => _modelLabel = '${cfg.providerLabel} · ${cfg.model}');
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AssessmentAiGrading.loadModelLabel', stack: st);
    }
  }

  Future<void> _loadReports() async {
    final reports = await _assessmentDao.getSubmittedReports();
    // 加载已批改的
    _approvedIds.clear();
    for (final r in reports) {
      final rid = r['id'] as int;
      if (r['score'] != null) {
        _approvedIds.add(rid);
        _gradingResults[rid] = _GradingResult(
          score: (r['score'] as num).toInt(),
          feedback: (r['feedback'] as String?) ?? '',
          dimensions: null,
          strengths: [],
          improvements: [],
        );
      }
    }
    // 从 grading_results 恢复待审核的 AI 批阅结果
    try {
      final pending = await _gradingDao.getPendingResults('assessment');
      for (final p in pending) {
        final tid = p['target_id'] as int;
        if (!_approvedIds.contains(tid) && !_gradingResults.containsKey(tid)) {
          Map<String, dynamic>? dims;
          try {
            dims = jsonDecode(p['dimensions'] as String? ?? '');
          } catch (e, st) {
            swallowDebug(e, tag: 'AiGradingTab.dims', stack: st);
          }
          List<String> strengths = [];
          try {
            strengths = (jsonDecode(p['strengths'] as String? ?? '[]') as List)
                .cast<String>();
          } catch (e, st) {
            swallowDebug(e, tag: 'AiGradingTab.strengths', stack: st);
          }
          List<String> improvements = [];
          try {
            improvements =
                (jsonDecode(p['improvements'] as String? ?? '[]') as List)
                    .cast<String>();
          } catch (e, st) {
            swallowDebug(e, tag: 'AiGradingTab.improvements', stack: st);
          }
          _gradingResults[tid] = _GradingResult(
            score: (p['score'] as num?)?.toInt() ?? 0,
            feedback: (p['feedback'] as String?) ?? '',
            dimensions: dims,
            strengths: strengths,
            improvements: improvements,
          );
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AiGradingTab', stack: st);
    }
    if (mounted) setState(() => _reports = reports);
  }

  List<Map<String, dynamic>> get _filteredReports {
    if (_selectedReportType == '全部') return _reports;
    return _reports
        .where((r) => (r['title'] as String?) == _selectedReportType)
        .toList();
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
    final ungraded = _filteredReports
        .where((r) =>
            r['score'] == null && !_gradingResults.containsKey(r['id'] as int))
        .toList();

    if (ungraded.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有需要批阅的报告')),
        );
      }
      return;
    }

    setState(() {
      _isBatchGrading = true;
      _gradingProgress = 0;
      _gradingTotal = ungraded.length;
      _gradingStatus = '正在批阅...';
    });

    for (int i = 0; i < ungraded.length; i++) {
      if (!_isBatchGrading) break;

      final report = ungraded[i];
      final userId = (report['user_id'] as String?) ?? '';

      setState(() {
        _gradingProgress = i;
        _gradingStatus = '正在批阅 ${i + 1}/$_gradingTotal: $userId';
      });

      await _gradeOne(report);

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

  /// 批阅单份报告：调用 AI → 解析 → 存内存 → 持久化为待审核结果。
  ///
  /// 批量与单份批阅共用此方法。已核准的报告不再覆盖其持久化结果。
  Future<void> _gradeOne(Map<String, dynamic> report) async {
    final rid = report['id'] as int;
    final reportType = (report['title'] as String?) ?? '考核报告';
    final userId = (report['user_id'] as String?) ?? '';
    final content = await _reportContentForGrading(report);

    try {
      final result = await _gradingAgent.gradeReport(
        reportType: reportType,
        studentName: userId,
        content: content.isNotEmpty ? content : '（学生提交了报告文件：$reportType）',
      );

      final parsed = _tryParseJson(result);
      if (parsed != null) {
        final score = (parsed['total_score'] as num?)?.toInt() ??
            (parsed['score'] as num?)?.toInt() ??
            0;
        final dims = parsed['scores'] as Map<String, dynamic>?;
        final strengths =
            (parsed['strengths'] as List?)?.map((e) => e.toString()).toList() ??
                [];
        final improvements = (parsed['improvements'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final feedback = _formatFeedback(parsed);

        _gradingResults[rid] = _GradingResult(
          score: score,
          feedback: feedback,
          dimensions: dims,
          strengths: strengths,
          improvements: improvements,
        );
      } else {
        _gradingResults[rid] = _GradingResult(
          score: 0,
          feedback: result,
          dimensions: null,
          strengths: [],
          improvements: [],
        );
      }
    } catch (e) {
      _gradingResults[rid] = _GradingResult(
        score: 0,
        feedback: '批阅失败: $e',
        dimensions: null,
        strengths: [],
        improvements: [],
      );
    }

    // 持久化（已核准的不覆盖）
    if (!_approvedIds.contains(rid)) {
      final r = _gradingResults[rid]!;
      await _gradingDao.deletePendingForTarget('assessment', rid);
      await _gradingDao.saveResult(
        domain: 'assessment',
        targetId: rid,
        scorerId: widget.authService.getCurrentUserId() ?? '',
        rawJson: null,
        score: r.score.toDouble(),
        feedback: r.feedback,
        dimensions: r.dimensions,
        strengths: r.strengths,
        improvements: r.improvements,
        aiFlag: false,
      );
    }
  }

  /// 单份 AI 批阅（行内触发）。带教师 AI 批阅总开关检查 + 行内 spinner。
  Future<void> _gradeSingle(Map<String, dynamic> report) async {
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
    final rid = report['id'] as int;
    setState(() => _singleGradingId = rid);
    await _gradeOne(report);
    if (mounted) setState(() => _singleGradingId = null);
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (match == null) return null;
      final map = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      if (map.containsKey('total_score') ||
          map.containsKey('score') ||
          map.containsKey('feedback')) {
        return map;
      }
      return null;
    } catch (e, st) {
      swallowDebug(e, tag: 'AiGradingTab.parseJson', stack: st);
      return null;
    }
  }

  Future<String> _reportContentForGrading(Map<String, dynamic> report) async {
    final filePath = (report['file_path'] as String?) ?? '';
    if (filePath.isNotEmpty && File(filePath).existsSync()) {
      try {
        final extracted =
            await PdfTextService.extractFromFile(filePath, maxChars: 8000);
        if (extracted != null && extracted.trim().isNotEmpty) {
          return extracted;
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'AssessmentAiGrading.extractPdf', stack: st);
      }
    }
    return (report['content_json'] as String?) ?? '';
  }

  String _formatFeedback(Map<String, dynamic> parsed) {
    final sb = StringBuffer();
    final summary = parsed['summary'] as String?;
    if (summary != null && summary.isNotEmpty) {
      sb.writeln('【总评】$summary\n');
    }
    final basis = parsed['basis'] as List?;
    if (basis != null && basis.isNotEmpty) {
      sb.writeln('【评分依据】');
      for (final s in basis) {
        sb.writeln('  - $s');
      }
      sb.writeln();
    }
    final scores = parsed['scores'] as Map<String, dynamic>?;
    if (scores != null) {
      sb.writeln('【各维度评分】');
      for (final e in scores.entries) {
        final d = e.value as Map<String, dynamic>? ?? {};
        sb.writeln(
            '  ${_dimLabel(e.key)}: ${d['score'] ?? ''}/${d['max'] ?? ''} — ${d['comment'] ?? ''}');
      }
      sb.writeln();
    }
    final strengths = parsed['strengths'] as List?;
    if (strengths != null && strengths.isNotEmpty) {
      sb.writeln('【优点】');
      for (final s in strengths) {
        sb.writeln('  - $s');
      }
      sb.writeln();
    }
    final improvements = parsed['improvements'] as List?;
    if (improvements != null && improvements.isNotEmpty) {
      sb.writeln('【改进建议】');
      for (final s in improvements) {
        sb.writeln('  - $s');
      }
      sb.writeln();
    }
    final feedback = parsed['feedback'] as String?;
    if (feedback != null && feedback.isNotEmpty) {
      sb.writeln('【详细反馈】\n$feedback');
    }
    final result = sb.toString().trim();
    return result.isNotEmpty ? result : (parsed['feedback'] as String? ?? '');
  }

  // ═══════════ 核准操作 ═══════════

  Future<void> _approveOne(int reportId) async {
    final result = _gradingResults[reportId];
    if (result == null) return;

    final db = await DatabaseHelper.instance.database;
    // 拿学生 ID + 报告类型，给后面的通知用
    String? studentId;
    String? reportType;
    try {
      final row = await db.query(
        'assessment_reports',
        columns: ['user_id', 'title'],
        where: 'id = ?',
        whereArgs: [reportId],
        limit: 1,
      );
      if (row.isNotEmpty) {
        studentId = row.first['user_id'] as String?;
        reportType = row.first['title'] as String? ?? '考核报告';
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AiGradingTab', stack: st);
    }

    await db.update(
      'assessment_reports',
      {
        'score': result.score,
        'feedback': result.feedback,
        'status': '已批改',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [reportId],
    );

    // 更新 grading_results 状态
    try {
      final pending =
          await _gradingDao.getPendingResults('assessment', targetId: reportId);
      for (final p in pending) {
        await _gradingDao.approveResult(
            p['id'] as int, widget.authService.getCurrentUserId() ?? '');
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AiGradingTab', stack: st);
    }

    // 通知学生：教师已复核
    if (studentId != null && studentId.isNotEmpty) {
      try {
        await NotificationService().notifyAssessmentGradeApproved(
          studentId: studentId,
          reportType: reportType ?? '考核报告',
          score: result.score,
        );
      } catch (e, st) {
        swallowDebug(e, tag: 'AiGradingTab', stack: st);
      }
    }

    setState(() {
      _approvedIds.add(reportId);
      _selectedForApproval.remove(reportId);
    });
  }

  Future<void> _approveBatch() async {
    for (final rid in _selectedForApproval.toList()) {
      if (!_approvedIds.contains(rid)) await _approveOne(rid);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已核准 ${_selectedForApproval.length} 份')),
      );
      _selectedForApproval.clear();
      setState(() {});
    }
  }

  // ═══════════ 调整分数 ═══════════

  void _showAdjustDialog(int reportId, Map<String, dynamic> report) {
    final result = _gradingResults[reportId];
    if (result == null) return;

    int adjustedScore = result.score;
    final feedbackCtrl = TextEditingController(text: result.feedback);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.edit_note, size: 20),
            const SizedBox(width: 8),
            Text('调整批阅 — ${report['user_id'] ?? ''}',
                style: const TextStyle(fontSize: 16)),
          ]),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('报告类型: ${report['title'] ?? ''}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 12),
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
                _gradingResults[reportId] = _GradingResult(
                  score: adjustedScore,
                  feedback: feedbackCtrl.text,
                  dimensions: result.dimensions,
                  strengths: result.strengths,
                  improvements: result.improvements,
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

  // ═══════════ 辅助函数 ═══════════

  Color _scoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 75) return Colors.blue;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _dimLabel(String key) {
    const labels = {
      'functionality': '功能完整性',
      'tech_depth': '技术深度',
      'integration': '跨框架整合',
      'quality': '性能与质量',
      'documentation': '文档与协作',
    };
    return labels[key] ?? key;
  }

  // ═══════════ 构建 UI ═══════════

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: () async => _loadReports(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSelector(primary),
          const SizedBox(height: 12),
          _buildGradingList(primary),
          if (_hasGradedResults) ...[
            const SizedBox(height: 16),
            _buildTopBottomReports(primary),
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

  // ═══════════ ① 选择器 ═══════════

  Widget _buildSelector(Color primary) {
    final filtered = _filteredReports;
    final ungraded = filtered.where((r) => r['score'] == null).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.auto_awesome, color: primary, size: 20),
              const SizedBox(width: 8),
              const Text('考核报告 AI 批阅',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_modelLabel.isNotEmpty) _modelBadge(primary),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _reportTypes
                  .map((t) => ChoiceChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        selected: _selectedReportType == t,
                        onSelected: (_) =>
                            setState(() => _selectedReportType = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _statChip('总报告', '${filtered.length}', Colors.blue),
                _statChip('未批阅', '$ungraded', Colors.orange),
                _statChip(
                    '已核准',
                    '${filtered.where((r) => _approvedIds.contains(r['id'])).length}',
                    Colors.green),
              ],
            ),
            const SizedBox(height: 10),
            if (_isBatchGrading) ...[
              LinearProgressIndicator(
                value: _gradingTotal > 0 ? _gradingProgress / _gradingTotal : 0,
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text(_gradingStatus,
                        style: const TextStyle(fontSize: 12))),
                TextButton.icon(
                  onPressed: () => setState(() => _isBatchGrading = false),
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止'),
                ),
              ]),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startBatchGrading,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('开始批量AI批阅'),
                ),
              ),
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
    final filtered = _filteredReports;
    if (filtered.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('暂无报告数据', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    final unapprovedWithResults = _gradingResults.keys
        .where((id) =>
            !_approvedIds.contains(id) && filtered.any((r) => r['id'] == id))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
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
                    _selectedForApproval.length == unapprovedWithResults.length
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
            ]),
            const Divider(height: 12),
            ...filtered.map((report) {
              final rid = report['id'] as int;
              final result = _gradingResults[rid];
              final isApproved = _approvedIds.contains(rid);
              final userId = report['user_id'] as String? ?? '';
              final reportType = report['title'] as String? ?? '';

              return _buildGradingItem(
                  report, rid, result, isApproved, userId, reportType, primary);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildGradingItem(
    Map<String, dynamic> report,
    int rid,
    _GradingResult? result,
    bool isApproved,
    String userId,
    String reportType,
    Color primary,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isApproved
            ? Colors.green.withValues(alpha: 0.05)
            : result != null
                ? Colors.blue.withValues(alpha: 0.05)
                : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: isApproved
            ? null
            : (result != null
                ? Checkbox(
                    value: _selectedForApproval.contains(rid),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedForApproval.add(rid);
                        } else {
                          _selectedForApproval.remove(rid);
                        }
                      });
                    },
                  )
                : const SizedBox(width: 40)),
        title: Row(children: [
          Text(userId,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(reportType,
                style: TextStyle(fontSize: 10, color: primary)),
          ),
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
        ]),
        subtitle: result != null
            ? Text(
                result.feedback.length > 200
                    ? '${result.feedback.substring(0, 200)}...'
                    : result.feedback,
                style: const TextStyle(fontSize: 11),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: _buildTrailing(report, rid, result, isApproved, primary),
      ),
    );
  }

  Widget? _buildTrailing(
    Map<String, dynamic> report,
    int rid,
    _GradingResult? result,
    bool isApproved,
    Color primary,
  ) {
    if (result != null && !isApproved) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: '调整',
            onPressed: () => _showAdjustDialog(rid, report),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            tooltip: '核准',
            color: Colors.green,
            onPressed: () => _approveOne(rid),
          ),
        ],
      );
    }
    if (isApproved) return null;
    if (_singleGradingId == rid) {
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
          : () => _gradeSingle(report),
    );
  }

  // ═══════════ ③ 优差报告展示 ═══════════

  Widget _buildTopBottomReports(Color primary) {
    final scored = <_ScoredEntry>[];
    for (final r in _filteredReports) {
      final rid = r['id'] as int;
      final result = _gradingResults[rid];
      if (result != null && result.score > 0) {
        scored.add(_ScoredEntry(
          userId: r['user_id'] as String? ?? '',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.insights, size: 18),
          const SizedBox(width: 8),
          const Text('优差报告展示',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('前后各 20%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
        const SizedBox(height: 8),
        _buildReportSection(
          title: '优秀报告 (前$topCount名)',
          icon: Icons.emoji_events,
          color: Colors.green,
          entries: scored.take(topCount).toList(),
          showStrengths: true,
        ),
        const SizedBox(height: 8),
        _buildReportSection(
          title: '待改进报告 (后$bottomCount名)',
          icon: Icons.trending_down,
          color: Colors.red,
          entries: scored.reversed.take(bottomCount).toList(),
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
        children: entries
            .map((e) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        _scoreColor(e.score).withValues(alpha: 0.15),
                    child: Text('${e.score}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _scoreColor(e.score))),
                  ),
                  title: Text(e.userId, style: const TextStyle(fontSize: 13)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (showStrengths ? e.strengths : e.improvements)
                        .take(3)
                        .map((s) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(showStrengths ? '✓ ' : '→ ',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: showStrengths
                                              ? Colors.green
                                              : Colors.orange)),
                                  Expanded(
                                      child: Text(s,
                                          style:
                                              const TextStyle(fontSize: 12))),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ═══════════ ④ 统计图表 ═══════════

  Widget _buildStatisticsCharts(Color primary) {
    final scores = <int>[];
    final dimTotals = <String, List<double>>{};

    for (final r in _filteredReports) {
      final rid = r['id'] as int;
      final result = _gradingResults[rid];
      if (result != null && result.score > 0) {
        scores.add(result.score);
        if (result.dimensions != null) {
          for (final e in result.dimensions!.entries) {
            final d = e.value as Map<String, dynamic>? ?? {};
            final s = (d['score'] as num?)?.toDouble() ?? 0;
            final m = (d['max'] as num?)?.toDouble() ?? 1;
            dimTotals.putIfAbsent(e.key, () => []).add(s / m);
          }
        }
      }
    }

    if (scores.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.bar_chart, size: 18),
          SizedBox(width: 8),
          Text('统计分析',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: Row(children: [
            Expanded(child: _buildDistributionChart(scores, primary)),
            const SizedBox(width: 8),
            Expanded(child: _buildRadarChart(dimTotals, primary)),
          ]),
        ),
        const SizedBox(height: 8),
        _buildAchievementProgress(scores, primary),
      ],
    );
  }

  Widget _buildDistributionChart(List<int> scores, Color primary) {
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
      Colors.green
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
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal + 1,
                barGroups: List.generate(
                    5,
                    (i) => BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: data[i].toDouble(),
                              color: colors[i],
                              width: 22,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            )
                          ],
                          showingTooltipIndicators: data[i] > 0 ? [0] : [],
                        )),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(labels[v.toInt()],
                          style: const TextStyle(fontSize: 10)),
                    ),
                  )),
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
                  getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                    '${rod.toY.toInt()}人',
                    const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                )),
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarChart(Map<String, List<double>> dimTotals, Color primary) {
    if (dimTotals.isEmpty) {
      return const Card(
          child: Center(
              child: Text('暂无维度数据', style: TextStyle(color: Colors.grey))));
    }

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
              child: RadarChart(RadarChartData(
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
                      text: _dimLabel(keys[index]), angle: 0);
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
                  )
                ],
                titlePositionPercentageOffset: 0.2,
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementProgress(List<int> scores, Color primary) {
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    final passRate = scores.where((s) => s >= 60).length / scores.length * 100;
    final excellentRate =
        scores.where((s) => s >= 90).length / scores.length * 100;

    final objectives = [
      ('平均分达成', avg, 75.0, '目标: 平均分≥75'),
      ('及格率', passRate, 90.0, '目标: 及格率≥90%'),
      ('优秀率', excellentRate, 20.0, '目标: 优秀率≥20%'),
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
            ...objectives.map((obj) {
              final achieved = obj.$2 >= obj.$3;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                          achieved
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 14,
                          color: achieved ? Colors.green : Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(obj.$1,
                              style: const TextStyle(fontSize: 12))),
                      Text('${obj.$2.toStringAsFixed(1)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: achieved ? Colors.green : Colors.orange)),
                    ]),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (obj.$2 / obj.$3).clamp(0.0, 1.0),
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      color: achieved ? Colors.green : Colors.orange,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(obj.$4,
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[500])),
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

// ═══════════ 数据模型 ═══════════

class _GradingResult {
  int score;
  String feedback;
  Map<String, dynamic>? dimensions;
  List<String> strengths;
  List<String> improvements;

  _GradingResult({
    required this.score,
    required this.feedback,
    this.dimensions,
    required this.strengths,
    required this.improvements,
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
