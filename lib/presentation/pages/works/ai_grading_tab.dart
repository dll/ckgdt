import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/score_audit_dao.dart';
import '../../../data/local/works_dao.dart';
import '../../../data/local/grading_result_dao.dart';
import '../../../data/local/ai_config_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/agent/agents/grading_agent.dart';
import '../../../services/settings_service.dart';

import '../../../core/error_handler.dart';

/// 作品 AI 智能批阅 Tab — 仅教师/管理员可见
///
/// 四区结构（与实验/考核 AI 批阅保持一致风格）：
/// ① 批阅启动
/// ② 批阅结果列表 + 逐个核准
/// ③ 前 20% 优秀 / 后 20% 待改进作品展示
/// ④ 统计图表（成绩分布 / 维度雷达 / 达成度）
class WorksAiGradingTab extends StatefulWidget {
  final AuthService authService;

  const WorksAiGradingTab({super.key, required this.authService});

  @override
  State<WorksAiGradingTab> createState() => _WorksAiGradingTabState();
}

class _WorksAiGradingTabState extends State<WorksAiGradingTab> {
  static const Map<String, int> _workDimensionMax = {
    'functionality': 25,
    'tech_depth': 20,
    'integration': 20,
    'quality': 20,
    'documentation': 15,
  };

  final _gradingAgent = GradingAgent();
  final _worksDao = WorksDao();
  final _gradingDao = GradingResultDao();
  final _aiConfigDao = AiConfigDao();

  // ── 当前大模型名称（显示用）──
  String _modelLabel = '';

  // ── 单份批阅进行中的作品 id（行内 spinner）──
  int? _singleGradingId;

  // ── 作品数据 ──
  List<Map<String, dynamic>> _works = [];

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
    _loadWorks();
  }

  Future<void> _loadModelLabel() async {
    try {
      final cfg = await _aiConfigDao.getConfig();
      if (mounted) {
        setState(() => _modelLabel = '${cfg.providerLabel} · ${cfg.model}');
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksAiGrading.loadModelLabel', stack: st);
    }
  }

  Future<void> _loadWorks() async {
    await _worksDao.repairSubmissionState();
    final works = await _worksDao.getWorks();
    // 过滤出已提交的
    final submitted = works
        .where((w) =>
            WorksDao.isSubmittedStatus(w['status'] as String?) ||
            WorksDao.hasVideoReference(w))
        .toList();
    // 标记已批改的
    _approvedIds.clear();
    for (final w in submitted) {
      final wid = w['id'] as int;
      if (w['score'] != null) {
        _approvedIds.add(wid);
        _gradingResults[wid] = _GradingResult(
          score: (w['score'] as num).toInt(),
          feedback: '',
          dimensions: null,
          strengths: [],
          improvements: [],
        );
      }
    }
    // 从 grading_results 恢复待审核的 AI 批阅结果
    try {
      final pending = await _gradingDao.getPendingResults('works');
      for (final p in pending) {
        final tid = p['target_id'] as int;
        if (!_approvedIds.contains(tid) && !_gradingResults.containsKey(tid)) {
          final restored = await _restorePendingResult(p);
          if (restored != null) _gradingResults[tid] = restored;
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksAiGrading.loadSubs', stack: st);
    }
    if (mounted) setState(() => _works = submitted);
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
    final ungraded = _works
        .where((w) =>
            w['score'] == null && !_gradingResults.containsKey(w['id'] as int))
        .toList();

    if (ungraded.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有需要批阅的作品')),
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

      final work = ungraded[i];
      final studentName = (work['student_name'] as String?) ??
          (work['user_id'] as String?) ??
          '';

      setState(() {
        _gradingProgress = i;
        _gradingStatus = '正在批阅 ${i + 1}/$_gradingTotal: $studentName';
      });

      await _gradeOne(work);

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

  /// 批阅单份作品：调用 AI → 解析 → 存内存 → 持久化为待审核结果。
  ///
  /// 批量与单份批阅共用此方法。已核准的作品不再覆盖其持久化结果。
  Future<void> _gradeOne(Map<String, dynamic> work) async {
    final wid = work['id'] as int;
    final title = (work['title'] as String?) ?? '未命名作品';
    final desc = (work['description'] as String?) ?? '';
    final techStack = (work['tech_stack'] as String?) ?? '';
    final studentName =
        (work['student_name'] as String?) ?? (work['user_id'] as String?) ?? '';
    final groupName = (work['group_name'] as String?) ?? '';

    try {
      // 综合批阅版（读视频帧 + 加载考核材料）。
      final videoUrl = work['video_url'] as String?;
      final videoPath = work['file_path'] as String?;
      final compRes = await _gradingAgent.gradeWorkComprehensive(
        title: title,
        description: desc,
        techStack: techStack,
        studentName: studentName,
        groupName: groupName.isNotEmpty ? groupName : null,
        videoPath: videoPath,
        videoUrl: videoUrl,
        frameCount: 5,
      );
      final result = compRes.content;
      final parsed = _tryParseJson(result);
      if (parsed != null) {
        _gradingResults[wid] = _resultFromParsedJson(parsed);
      } else {
        _gradingResults[wid] = _GradingResult(
          score: 0,
          feedback: result,
          dimensions: null,
          strengths: [],
          improvements: [],
        );
      }
    } catch (e) {
      _gradingResults[wid] = _GradingResult(
        score: 0,
        feedback: '批阅失败: $e',
        dimensions: null,
        strengths: [],
        improvements: [],
      );
    }

    // 持久化（已核准的不覆盖）
    if (!_approvedIds.contains(wid)) {
      final r = _gradingResults[wid]!;
      await _gradingDao.deletePendingForTarget('works', wid);
      await _gradingDao.saveResult(
        domain: 'works',
        targetId: wid,
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
  Future<void> _gradeSingle(Map<String, dynamic> work) async {
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
    final wid = work['id'] as int;
    setState(() => _singleGradingId = wid);
    await _gradeOne(work);
    if (mounted) setState(() => _singleGradingId = null);
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    final candidates = <String>[];
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    candidates.add(trimmed);
    final fenced =
        RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false)
            .firstMatch(trimmed);
    if (fenced != null) candidates.add(fenced.group(1)!.trim());
    candidates.addAll(_balancedJsonObjects(trimmed));

    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded.containsKey('total_score') ||
            decoded.containsKey('score') ||
            decoded.containsKey('feedback') ||
            decoded.containsKey('summary') ||
            decoded.containsKey('scores') ||
            decoded.containsKey('dimensions')) {
          return decoded;
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'WorksAiGrading.parseJson', stack: st);
      }
    }
    return null;
  }

  List<String> _balancedJsonObjects(String text) {
    final objects = <String>[];
    var start = -1;
    var depth = 0;
    var inString = false;
    var escaping = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (escaping) {
        escaping = false;
        continue;
      }
      if (ch == '\\') {
        escaping = inString;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (ch == '}' && depth > 0) {
        depth--;
        if (depth == 0 && start >= 0) {
          objects.add(text.substring(start, i + 1));
          start = -1;
        }
      }
    }
    return objects;
  }

  _GradingResult _resultFromParsedJson(Map<String, dynamic> parsed) {
    final score = _clampedScore(
      _numValue(parsed['total_score']) ?? _numValue(parsed['score']),
    );
    final dims = _asStringDynamicMap(parsed['dimensions']) ??
        _asStringDynamicMap(parsed['scores']);
    return _GradingResult(
      score: score,
      feedback: _formatFeedback(parsed),
      dimensions: dims,
      strengths:
          (parsed['strengths'] as List?)?.map((e) => e.toString()).toList() ??
              [],
      improvements: (parsed['improvements'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Future<_GradingResult?> _restorePendingResult(
      Map<String, dynamic> pending) async {
    final rawJson = (pending['raw_json'] as String?)?.trim() ?? '';
    final feedback = (pending['feedback'] as String?) ?? '';
    final parsed = _tryParseJson(rawJson.isNotEmpty ? rawJson : feedback);

    if (parsed != null) {
      final normalized = _resultFromParsedJson(parsed);
      final needsPersist =
          _clampedScore(_numValue(pending['score'])) != normalized.score ||
              feedback.trim().startsWith('{') ||
              rawJson.isEmpty ||
              (pending['dimensions'] as String?) == null;
      if (needsPersist) {
        try {
          await _gradingDao.updateDraftResult(
            id: pending['id'] as int,
            rawJson: jsonEncode(parsed),
            score: normalized.score.toDouble(),
            feedback: normalized.feedback,
            dimensions: normalized.dimensions,
            strengths: normalized.strengths,
            improvements: normalized.improvements,
            aiFlag: parsed['ai_flag'] == true,
          );
        } catch (e, st) {
          swallowDebug(e, tag: 'WorksAiGrading.normalizePending', stack: st);
        }
      }
      return normalized;
    }

    return _GradingResult(
      score: _clampedScore(pending['score'] as num?),
      feedback: feedback,
      dimensions: _decodeJsonMap(pending['dimensions'] as String?),
      strengths: _decodeStringList(pending['strengths'] as String?),
      improvements: _decodeStringList(pending['improvements'] as String?),
    );
  }

  Map<String, dynamic>? _decodeJsonMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return _asStringDynamicMap(decoded);
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksAiGrading.decodeJsonMap', stack: st);
      return null;
    }
  }

  List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.map((e) => e.toString()).toList() : [];
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksAiGrading.decodeStringList', stack: st);
      return [];
    }
  }

  Map<String, dynamic>? _asStringDynamicMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  int _clampedScore(num? value, [int max = 100]) {
    if (value == null) return 0;
    return value.round().clamp(0, max).toInt();
  }

  num? _numValue(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.trim());
    return null;
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
    final scores = _asStringDynamicMap(parsed['scores']) ??
        _asStringDynamicMap(parsed['dimensions']);
    if (scores != null) {
      sb.writeln('【各维度评分】');
      for (final e in scores.entries) {
        final d = _asStringDynamicMap(e.value) ?? {};
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

  Future<void> _approveOne(int workId) async {
    final result = _gradingResults[workId];
    if (result == null) return;

    final normalizedDimensions = _normalizedDimensionsForResult(result);
    result.dimensions = normalizedDimensions;
    final scores = _dimensionScoresForResult(result);
    final func = scores['functionality'] ?? 0;
    final tech = scores['tech_depth'] ?? 0;
    final integ = scores['integration'] ?? 0;
    final qual = scores['quality'] ?? 0;
    final doc = scores['documentation'] ?? 0;
    final approvedTotal = func + tech + integ + qual + doc;
    result.score = approvedTotal;

    await _worksDao.scoreWork(
      workId: workId,
      scorerId: widget.authService.getCurrentUserId(),
      scorerName: widget.authService.currentUser?.realName ?? '教师',
      scorerRole: widget.authService.currentUser?.role ?? 'teacher',
      functionality: func,
      techDepth: tech,
      integration: integ,
      quality: qual,
      documentation: doc,
      comment: result.feedback,
    );
    // 审计 — AI 自动评分（reason 标 'AI 批阅'，便于事后区分人工 vs AI）
    try {
      await ScoreAuditDao.instance.logChange(
        tableName: 'work_scores',
        rowId: workId,
        field: 'total',
        newValue: approvedTotal.toString(),
        reason: 'AI 批阅',
        scorerId: widget.authService.getCurrentUserId() ?? '',
        scorerName: widget.authService.currentUser?.realName ?? '教师',
        op: 'create',
      );
    } catch (e) {
      swallow(e, tag: 'WorksAiGrading.auditLog');
    }

    // 更新 grading_results 状态
    try {
      final pending =
          await _gradingDao.getPendingResults('works', targetId: workId);
      for (final p in pending) {
        await _gradingDao.updateDraftResult(
          id: p['id'] as int,
          rawJson: '',
          score: approvedTotal.toDouble(),
          feedback: result.feedback,
          dimensions: normalizedDimensions,
          strengths: result.strengths,
          improvements: result.improvements,
          aiFlag: false,
        );
        await _gradingDao.approveResult(
            p['id'] as int, widget.authService.getCurrentUserId() ?? '');
      }
    } catch (e) {
      swallow(e, tag: 'WorksAiGrading.approveStatus');
    }

    // 通知学生：作品批阅已完成
    try {
      final work = await _worksDao.getWork(workId);
      if (work != null) {
        final studentId = work['user_id'] as String?;
        final workTitle = work['title'] as String? ?? '作品';
        if (studentId != null && studentId.isNotEmpty) {
          await NotificationService().notifyWorkGradeApproved(
            studentId: studentId,
            workTitle: workTitle,
            score: result.score,
          );
          unawaited(SyncService().uploadStudentData(studentId));
        }
      }
    } catch (e) {
      swallow(e, tag: 'WorksAiGrading.notify');
    }

    setState(() {
      _approvedIds.add(workId);
      _selectedForApproval.remove(workId);
    });
  }

  Future<void> _approveBatch() async {
    for (final wid in _selectedForApproval.toList()) {
      if (!_approvedIds.contains(wid)) await _approveOne(wid);
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

  void _showAdjustDialog(int workId, Map<String, dynamic> work) {
    final result = _gradingResults[workId];
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
            Expanded(
              child: Text(
                  '调整批阅 — ${work['student_name'] ?? work['user_id'] ?? ''}',
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('作品: ${work['title'] ?? ''}',
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
              onPressed: () async {
                final updated = _GradingResult(
                  score: adjustedScore,
                  feedback: feedbackCtrl.text,
                  dimensions: result.dimensions,
                  strengths: result.strengths,
                  improvements: result.improvements,
                );
                updated.dimensions = _normalizedDimensionsForResult(updated);
                _gradingResults[workId] = updated;
                try {
                  final pending = await _gradingDao.getPendingResults(
                    'works',
                    targetId: workId,
                  );
                  for (final p in pending) {
                    await _gradingDao.updateDraftResult(
                      id: p['id'] as int,
                      rawJson: '',
                      score: adjustedScore.toDouble(),
                      feedback: updated.feedback,
                      dimensions: updated.dimensions,
                      strengths: updated.strengths,
                      improvements: updated.improvements,
                      aiFlag: false,
                    );
                  }
                } catch (e, st) {
                  swallowDebug(e, tag: 'WorksAiGrading.adjustDraft', stack: st);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
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

  Map<String, dynamic> _normalizedDimensionsForResult(_GradingResult result) {
    final scores = _dimensionScoresForResult(result);
    final normalized = <String, dynamic>{};
    for (final entry in _workDimensionMax.entries) {
      final comment = _dimensionComment(result.dimensions?[entry.key]);
      normalized[entry.key] = {
        'score': scores[entry.key] ?? 0,
        'max': entry.value,
        if (comment.isNotEmpty) 'comment': comment,
      };
    }
    return normalized;
  }

  Map<String, int> _dimensionScoresForResult(_GradingResult result) {
    final targetScore = _clampedScore(result.score);
    final baseScores = <String, int>{};
    var hasDimensionScore = false;

    for (final entry in _workDimensionMax.entries) {
      final value = _dimensionNumericScore(result.dimensions?[entry.key]);
      if (value != null) hasDimensionScore = true;
      baseScores[entry.key] = _clampedScore(value, entry.value);
    }

    final baseTotal = baseScores.values.fold<int>(0, (sum, v) => sum + v);
    if (hasDimensionScore && baseTotal == targetScore) {
      return baseScores;
    }

    final weights = <String, int>{};
    for (final entry in _workDimensionMax.entries) {
      final score = baseScores[entry.key] ?? 0;
      weights[entry.key] =
          hasDimensionScore && baseTotal > 0 ? score : entry.value;
    }
    return _apportionDimensionScores(weights, targetScore);
  }

  Map<String, int> _apportionDimensionScores(
    Map<String, int> weights,
    int targetScore,
  ) {
    final target = _clampedScore(targetScore);
    final scores = <String, int>{};
    if (target == 0) {
      for (final key in _workDimensionMax.keys) {
        scores[key] = 0;
      }
      return scores;
    }

    final effectiveWeights = <String, int>{};
    for (final entry in _workDimensionMax.entries) {
      effectiveWeights[entry.key] =
          (weights[entry.key] ?? 0).clamp(0, entry.value).toInt();
    }
    var weightTotal = effectiveWeights.values.fold<int>(0, (sum, v) => sum + v);
    if (weightTotal <= 0) {
      effectiveWeights
        ..clear()
        ..addAll(_workDimensionMax);
      weightTotal = effectiveWeights.values.fold<int>(0, (sum, v) => sum + v);
    }

    final fractions = <String, double>{};
    for (final entry in _workDimensionMax.entries) {
      final raw = target * (effectiveWeights[entry.key] ?? 0) / weightTotal;
      fractions[entry.key] = raw - raw.floor();
      scores[entry.key] = raw.floor().clamp(0, entry.value).toInt();
    }

    var diff = target - scores.values.fold<int>(0, (sum, v) => sum + v);
    while (diff > 0) {
      final candidates = _workDimensionMax.keys
          .where((key) => (scores[key] ?? 0) < (_workDimensionMax[key] ?? 0))
          .toList()
        ..sort((a, b) {
          final fractionCompare =
              (fractions[b] ?? 0).compareTo(fractions[a] ?? 0);
          if (fractionCompare != 0) return fractionCompare;
          final capA = (_workDimensionMax[a] ?? 0) - (scores[a] ?? 0);
          final capB = (_workDimensionMax[b] ?? 0) - (scores[b] ?? 0);
          return capB.compareTo(capA);
        });
      if (candidates.isEmpty) break;
      for (final key in candidates) {
        if (diff <= 0) break;
        scores[key] = (scores[key] ?? 0) + 1;
        diff--;
      }
    }

    while (diff < 0) {
      final candidates = _workDimensionMax.keys
          .where((key) => (scores[key] ?? 0) > 0)
          .toList()
        ..sort((a, b) => (fractions[a] ?? 0).compareTo(fractions[b] ?? 0));
      if (candidates.isEmpty) break;
      for (final key in candidates) {
        if (diff >= 0) break;
        scores[key] = (scores[key] ?? 0) - 1;
        diff++;
      }
    }

    return scores;
  }

  num? _dimensionNumericScore(Object? raw) {
    return _numValue(raw) ?? _numValue(_asStringDynamicMap(raw)?['score']);
  }

  String _dimensionComment(Object? raw) {
    final comment = _asStringDynamicMap(raw)?['comment']?.toString().trim();
    return comment ?? '';
  }

  // ═══════════ 构建 UI ═══════════

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: () async => _loadWorks(),
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
    final ungraded = _works.where((w) => w['score'] == null).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.auto_awesome, color: primary, size: 20),
              const SizedBox(width: 8),
              const Text('作品 AI 批阅',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_modelLabel.isNotEmpty) _modelBadge(primary),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _statChip('已提交', '${_works.length}', Colors.blue),
                _statChip('未批阅', '$ungraded', Colors.orange),
                _statChip('已核准', '${_approvedIds.length}', Colors.green),
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
    if (_works.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('暂无作品数据', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    final unapprovedWithResults =
        _gradingResults.keys.where((id) => !_approvedIds.contains(id)).toList();

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
            ..._works.map((work) {
              final wid = work['id'] as int;
              final result = _gradingResults[wid];
              final isApproved = _approvedIds.contains(wid);
              final name = (work['student_name'] as String?) ??
                  (work['user_id'] as String?) ??
                  '';
              final title = (work['title'] as String?) ?? '';

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
                              value: _selectedForApproval.contains(wid),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedForApproval.add(wid);
                                  } else {
                                    _selectedForApproval.remove(wid);
                                  }
                                });
                              },
                            )
                          : const SizedBox(width: 40)),
                  title: Row(children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(title,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (result != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              _scoreColor(result.score).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${result.score}分',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _scoreColor(result.score))),
                      ),
                    ],
                    if (isApproved) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('已核准',
                            style:
                                TextStyle(fontSize: 10, color: Colors.green)),
                      ),
                    ],
                  ]),
                  trailing:
                      _buildTrailing(work, wid, result, isApproved, primary),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget? _buildTrailing(Map<String, dynamic> work, int wid,
      _GradingResult? result, bool isApproved, Color primary) {
    if (result != null && !isApproved) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: '调整',
            onPressed: () => _showAdjustDialog(wid, work),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            tooltip: '核准',
            color: Colors.green,
            onPressed: () => _approveOne(wid),
          ),
        ],
      );
    }
    if (isApproved) return null;
    if (_singleGradingId == wid) {
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
          : () => _gradeSingle(work),
    );
  }

  // ═══════════ ③ 优差报告展示 ═══════════

  Widget _buildTopBottomReports(Color primary) {
    final scored = <_ScoredEntry>[];
    for (final w in _works) {
      final wid = w['id'] as int;
      final result = _gradingResults[wid];
      if (result != null && result.score > 0) {
        scored.add(_ScoredEntry(
          name:
              (w['student_name'] as String?) ?? (w['user_id'] as String?) ?? '',
          title: (w['title'] as String?) ?? '',
          score: result.score,
          strengths: result.strengths,
          improvements: result.improvements,
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
          const Text('优差作品展示',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('前后各 20%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
        const SizedBox(height: 8),
        _buildReportSection(
          title: '优秀作品 (前$topCount名)',
          icon: Icons.emoji_events,
          color: Colors.green,
          entries: scored.take(topCount).toList(),
          showStrengths: true,
        ),
        const SizedBox(height: 8),
        _buildReportSection(
          title: '待改进作品 (后$bottomCount名)',
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
                  title: Text('${e.name} — ${e.title}',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
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

    for (final w in _works) {
      final wid = w['id'] as int;
      final result = _gradingResults[wid];
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
  final String name;
  final String title;
  final int score;
  final List<String> strengths;
  final List<String> improvements;

  _ScoredEntry({
    required this.name,
    required this.title,
    required this.score,
    required this.strengths,
    required this.improvements,
  });
}
