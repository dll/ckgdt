import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/local/database_helper.dart';
import 'ai_service.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

/// 抄袭 / AI 特征检测服务
class PlagiarismService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ══════════════════════════════════════════════════════════════════
  // Jaccard 相似度（3-gram 字符集）
  // ══════════════════════════════════════════════════════════════════

  /// 计算两段文本的 3-gram Jaccard 相似度 → 0-1
  double jaccard(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final gramsA = _ngrams(a, 3);
    final gramsB = _ngrams(b, 3);
    if (gramsA.isEmpty || gramsB.isEmpty) return 0;
    final intersection = gramsA.intersection(gramsB).length;
    final union = gramsA.union(gramsB).length;
    return union > 0 ? intersection / union : 0;
  }

  Set<String> _ngrams(String text, int n) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length < n) return {cleaned};
    final grams = <String>{};
    for (int i = 0; i <= cleaned.length - n; i++) {
      grams.add(cleaned.substring(i, i + n));
    }
    return grams;
  }

  // ══════════════════════════════════════════════════════════════════
  // 扫描实验提交
  // ══════════════════════════════════════════════════════════════════

  /// 扫描某次实验提交与同任务其他提交的相似度
  Future<PlagiarismResult> scanLabSubmission(int submissionId) async {
    final db = await _dbHelper.database;

    // 获取当前提交
    final rows = await db.query(
      'lab_submissions',
      where: 'id = ?',
      whereArgs: [submissionId],
    );
    if (rows.isEmpty) return PlagiarismResult.empty();

    final current = rows.first;
    final content = (current['content'] as String?) ?? '';
    final taskId = current['task_id'] as int?;
    final userId = current['user_id'] as String?;

    if (content.length < 20 || taskId == null) {
      return PlagiarismResult.empty();
    }

    // 获取同任务的其他提交
    final others = await db.query(
      'lab_submissions',
      where: 'task_id = ? AND user_id != ? AND content IS NOT NULL',
      whereArgs: [taskId, userId],
    );

    double maxSim = 0;
    final similarities = <Map<String, dynamic>>[];

    for (final other in others) {
      final otherContent = (other['content'] as String?) ?? '';
      if (otherContent.length < 20) continue;
      final sim = jaccard(content, otherContent);
      if (sim > 0.3) {
        similarities.add({
          'id': other['id'],
          'user_id': other['user_id'],
          'score': (sim * 100).round(),
        });
      }
      maxSim = max(maxSim, sim);
    }

    return PlagiarismResult(
      similarityMax: maxSim,
      similarWith: similarities,
      aiLikelihood: 0, // 单独调用 aiLikelihood()
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // AI 特征检测
  // ══════════════════════════════════════════════════════════════════

  /// 检测文本的 AI 生成概率 → 0-1
  Future<double> detectAiLikelihood(String content) async {
    if (content.length < 50) return 0;

    try {
      final aiService = AiService();
      final response = await aiService.chat([
        {
          'role': 'user',
          'content': '''分析以下文本是否疑似 AI 生成。
仅回复一个 JSON：{"ai_likelihood": 0.0到1.0的数值, "evidence": ["原因1", "原因2"]}

文本：
${content.substring(0, min(content.length, 800))}''',
        }
      ]);

      final json = jsonDecode(
          response.replaceAll(RegExp(r'```json\s*'), '').replaceAll('```', ''));
      return (json['ai_likelihood'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      debugPrint('AI likelihood detection error: $e');
      return 0;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 综合扫描并存储
  // ══════════════════════════════════════════════════════════════════

  /// 扫描并写入 plagiarism_records + 回写 source 的 ai_suspicion
  Future<void> scanAndStore({
    required String sourceType,
    required int sourceId,
  }) async {
    final db = await _dbHelper.database;

    try {
      String content = '';
      if (sourceType == 'lab_submission') {
        final rows = await db.query('lab_submissions',
            where: 'id = ?', whereArgs: [sourceId]);
        if (rows.isNotEmpty) content = (rows.first['content'] as String?) ?? '';
      } else if (sourceType == 'student_work') {
        final rows = await db.query('student_works',
            where: 'id = ?', whereArgs: [sourceId]);
        if (rows.isNotEmpty) {
          content = (rows.first['description'] as String?) ?? '';
        }
      }

      if (content.length < 30) return;

      // 相似度扫描（仅实验提交）
      double simMax = 0;
      List<Map<String, dynamic>> simWith = [];

      if (sourceType == 'lab_submission') {
        final result = await scanLabSubmission(sourceId);
        simMax = result.similarityMax;
        simWith = result.similarWith;
      }

      // AI 特征检测
      final aiLik = await detectAiLikelihood(content);

      // 写入检测记录
      await db.insert('plagiarism_records', {
        'source_type': sourceType,
        'source_id': sourceId,
        'similarity_max': simMax,
        'similar_with': jsonEncode(simWith),
        'ai_likelihood': aiLik,
        'detected_at': DateTime.now().toIso8601String(),
      });

      // 回写 ai_suspicion
      final suspicion = max(simMax, aiLik);
      final table =
          sourceType == 'lab_submission' ? 'lab_submissions' : 'student_works';
      await db.update(
        table,
        {
          'ai_suspicion': suspicion,
          'ai_evidence':
              '相似度:${(simMax * 100).toStringAsFixed(0)}% AI概率:${(aiLik * 100).toStringAsFixed(0)}%',
        },
        where: 'id = ?',
        whereArgs: [sourceId],
      );
    } catch (e) {
      debugPrint('PlagiarismService.scanAndStore error: $e');
    }
  }

  /// 列出 AI 可疑提交（ai_suspicion > threshold）
  Future<List<Map<String, dynamic>>> listSuspicious({
    double threshold = 0.7,
  }) async {
    final db = await _dbHelper.database;
    final results = <Map<String, dynamic>>[];

    try {
      final labRows = await db.rawQuery(
        'SELECT id, user_id, task_id, ai_suspicion, ai_evidence FROM lab_submissions WHERE ai_suspicion > ?',
        [threshold],
      );
      for (final r in labRows) {
        results.add({...r, 'source_type': 'lab_submission'});
      }

      final workRows = await db.rawQuery(
        'SELECT id, user_id, ai_suspicion FROM student_works WHERE ai_suspicion > ?',
        [threshold],
      );
      for (final r in workRows) {
        results.add({...r, 'source_type': 'student_work'});
      }
    } catch (e) { swallowDebug(e, tag: 'plagiarism_service'); }

    return results;
  }
}

/// 检测结果
class PlagiarismResult {
  final double similarityMax;
  final List<Map<String, dynamic>> similarWith;
  final double aiLikelihood;

  const PlagiarismResult({
    required this.similarityMax,
    required this.similarWith,
    required this.aiLikelihood,
  });

  factory PlagiarismResult.empty() => const PlagiarismResult(
        similarityMax: 0,
        similarWith: [],
        aiLikelihood: 0,
      );
}
