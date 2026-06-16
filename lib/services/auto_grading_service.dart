/// 学生提交后的 AI 自动批阅服务
///
/// 三类提交（实验/考核/作品）调用同一入口：
/// - 调对应 Agent 拿评分 JSON
/// - 解析 score / strengths / improvements / dimensions / feedback
/// - 写 grading_results(status='pending') 给教师审核
/// - 给教师发"AI 批阅就绪"通知
/// - 给学生发"AI 已批阅，等待教师复核"通知（如果学生选了"稍后通知"路径）
///
/// 学生选"立即查看 AI 批阅"路径时，UI 直接 await runGrade() 拿返回结果展示，
/// notification 仍然发（学生关掉后还能从通知列表回来看）。
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/init_logger.dart';
import '../data/local/grading_result_dao.dart';
import 'agent/agents/grading_agent.dart';
import 'notification_service.dart';

/// AI 批阅结果（解析后）—— UI 与服务共享
class AiGradingDraft {
  final int score;
  final String feedback;
  final Map<String, dynamic>? dimensions;
  final List<String> strengths;
  final List<String> improvements;
  final bool aiFlag;
  final Map<String, dynamic>? raw;

  const AiGradingDraft({
    required this.score,
    required this.feedback,
    this.dimensions,
    this.strengths = const [],
    this.improvements = const [],
    this.aiFlag = false,
    this.raw,
  });

  bool get isUsable => raw != null;
}

class AutoGradingService {
  AutoGradingService._();
  static final AutoGradingService instance = AutoGradingService._();

  final GradingResultDao _gradingDao = GradingResultDao();
  final NotificationService _notify = NotificationService();

  // ── 实验 ─────────────────────────────────────────────────────────────────

  /// 提交实验报告后调（在 lab_task_dao.submitTask / 实验提交按钮处）
  ///
  /// [returnDraft] 决定"立即等待"还是"后台跑"：
  ///   true  → 调用方 await 结果，可以在 UI 立刻显示 AI 草稿
  ///   false → 调用方一般用 `unawaited(...)` 包，AI 完成后通过通知告诉学生
  Future<AiGradingDraft?> gradeLabSubmission({
    required int submissionId,
    required String studentId,
    required String studentName,
    required int taskId,
    required String taskTitle,
    required String content,
    int maxScore = 100,
    String? requirements,
    bool returnDraft = false,
    bool notifyStudent = true,
  }) async {
    try {
      final agent = GradingAgent();
      final result = await agent.gradeSubmission(
        taskTitle: taskTitle,
        content: content,
        maxScore: maxScore,
        requirements: requirements,
      );
      final draft = await _parseAndSave(
        domain: 'lab',
        targetId: submissionId,
        scorerId: 'system',
        rawText: result,
      );
      if (draft != null && draft.isUsable) {
        await _notify.notifyLabAutoGraded(
          studentId: studentId,
          studentName: studentName,
          taskTitle: taskTitle,
          taskId: taskId,
          score: draft.score,
        );
        if (notifyStudent) {
          await _notify.notifyStudentAiDraftReady(
            studentId: studentId,
            domain: 'lab',
            entityTitle: taskTitle,
            aiScore: draft.score,
          );
        }
      }
      return returnDraft ? draft : null;
    } catch (e, st) {
      InitLogger.error('auto_grade', 'lab grading failed: $e', st);
      return null;
    }
  }

  // ── 考核 ─────────────────────────────────────────────────────────────────

  /// 提交考核报告后调
  Future<AiGradingDraft?> gradeAssessmentReport({
    required int reportId,
    required String studentId,
    required String studentName,
    required String reportType, // 答辩报告 / 个人报告 / 小组报告 / 项目报告
    required String content,
    String? projectName,
    String? groupName,
    bool returnDraft = false,
    bool notifyStudent = true,
  }) async {
    try {
      final agent = GradingAgent();
      final result = await agent.gradeReport(
        reportType: reportType,
        studentName: studentName,
        content: content,
        projectName: projectName,
        groupName: groupName,
      );
      final draft = await _parseAndSave(
        domain: 'assessment',
        targetId: reportId,
        scorerId: 'system',
        rawText: result,
      );
      if (draft != null && draft.isUsable) {
        await _notify.notifyAssessmentAutoGraded(
          studentId: studentId,
          studentName: studentName,
          reportType: reportType,
          score: draft.score,
        );
        if (notifyStudent) {
          await _notify.notifyStudentAiDraftReady(
            studentId: studentId,
            domain: 'assessment',
            entityTitle: reportType,
            aiScore: draft.score,
          );
        }
      }
      return returnDraft ? draft : null;
    } catch (e, st) {
      InitLogger.error('auto_grade', 'assessment grading failed: $e', st);
      return null;
    }
  }

  // ── 作品 ─────────────────────────────────────────────────────────────────

  /// 提交作品后调
  Future<AiGradingDraft?> gradeWork({
    required int workId,
    required String studentId,
    required String studentName,
    required String workTitle,
    required String description,
    String? techStack,
    String? groupName,
    bool returnDraft = false,
    bool notifyStudent = true,
  }) async {
    try {
      final agent = GradingAgent();
      final result = await agent.gradeWork(
        title: workTitle,
        description: description,
        techStack: techStack,
        studentName: studentName,
        groupName: groupName,
      );
      final draft = await _parseAndSave(
        domain: 'works',
        targetId: workId,
        scorerId: 'system',
        rawText: result,
      );
      if (draft != null && draft.isUsable) {
        await _notify.notifyWorkAutoGraded(
          studentId: studentId,
          studentName: studentName,
          workTitle: workTitle,
          workId: workId,
          score: draft.score,
        );
        if (notifyStudent) {
          await _notify.notifyStudentAiDraftReady(
            studentId: studentId,
            domain: 'work',
            entityTitle: workTitle,
            aiScore: draft.score,
          );
        }
      }
      return returnDraft ? draft : null;
    } catch (e, st) {
      InitLogger.error('auto_grade', 'work grading failed: $e', st);
      return null;
    }
  }

  // ── 解析 + 持久化 ────────────────────────────────────────────────────────

  Future<AiGradingDraft?> _parseAndSave({
    required String domain,
    required int targetId,
    required String scorerId,
    required String rawText,
  }) async {
    final parsed = _tryParseGradingJson(rawText);
    if (parsed == null) {
      // 非 JSON 返回，保留原始文本作为 feedback，但不写 grading_results
      // 教师在 ai_grading_tab 里看到的话会用 0 分 + 原文，重新触发即可
      InitLogger.log('auto_grade',
          '$domain target=$targetId: AI returned non-JSON, skipping save');
      return null;
    }

    final score = (parsed['score'] as num?)?.toInt() ??
        (parsed['total_score'] as num?)?.toInt() ??
        0;
    final feedback = _formatGradingFeedback(parsed);
    final dims = parsed['dimensions'] as Map<String, dynamic>? ??
        parsed['scores'] as Map<String, dynamic>?;
    final strengths =
        (parsed['strengths'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final improvements =
        (parsed['improvements'] as List?)?.map((e) => e.toString()).toList() ??
            [];
    final aiFlag = parsed['ai_flag'] == true;

    try {
      await _gradingDao.deletePendingForTarget(domain, targetId);
      await _gradingDao.saveResult(
        domain: domain,
        targetId: targetId,
        scorerId: scorerId,
        rawJson: jsonEncode(parsed),
        score: score.toDouble(),
        feedback: feedback,
        dimensions: dims,
        strengths: strengths,
        improvements: improvements,
        aiFlag: aiFlag,
      );
      debugPrint(
          'AutoGradingService: saved $domain/$targetId (score=$score, pending)');
    } catch (e, st) {
      InitLogger.error(
          'auto_grade', '$domain target=$targetId: saveResult failed: $e', st);
    }

    return AiGradingDraft(
      score: score,
      feedback: feedback,
      dimensions: dims,
      strengths: strengths,
      improvements: improvements,
      aiFlag: aiFlag,
      raw: parsed,
    );
  }

  Map<String, dynamic>? _tryParseGradingJson(String text) {
    final candidates = <String>[];
    final trimmed = text.trim();
    candidates.add(trimmed);
    final fenced =
        RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false)
            .firstMatch(trimmed);
    if (fenced != null) {
      candidates.add(fenced.group(1)!.trim());
    }
    candidates.addAll(_balancedJsonObjects(trimmed));

    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded.containsKey('score') ||
            decoded.containsKey('total_score') ||
            decoded.containsKey('feedback') ||
            decoded.containsKey('summary') ||
            decoded.containsKey('scores') ||
            decoded.containsKey('dimensions')) {
          return decoded;
        }
      } catch (e, st) {
        InitLogger.error(
            'auto_grade', 'parse grading json candidate failed: $e', st);
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

  String _formatGradingFeedback(Map<String, dynamic> parsed) {
    final sb = StringBuffer();
    final summary = parsed['summary'] as String?;
    if (summary != null && summary.isNotEmpty) {
      sb
        ..writeln('【总评】$summary')
        ..writeln();
    }
    final dims = parsed['dimensions'] as Map<String, dynamic>? ??
        parsed['scores'] as Map<String, dynamic>?;
    if (dims != null && dims.isNotEmpty) {
      sb.writeln('【各维度评分】');
      for (final entry in dims.entries) {
        final d = entry.value;
        if (d is Map<String, dynamic>) {
          sb.writeln(
              '  ${entry.key}: ${d['score'] ?? ''}/${d['max'] ?? ''} - ${d['comment'] ?? ''}');
        }
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
      sb
        ..writeln('【详细反馈】')
        ..writeln(feedback);
    }
    final result = sb.toString().trim();
    return result.isNotEmpty ? result : feedback ?? '';
  }
}
