import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../core/error_handler.dart';
import '../data/local/lab_task_dao.dart';
import '../data/local/assessment_dao.dart';
import '../data/local/works_dao.dart';
import 'default_class_service.dart';

class ScoreExportService {
  ScoreExportService._();
  static final ScoreExportService instance = ScoreExportService._();

  final _labTaskDao = LabTaskDao();
  final _assessmentDao = AssessmentDao();
  final _worksDao = WorksDao();

  /// 实验成绩按默认班级收窄（行级含 user_id，可过滤）。
  /// 默认班级未设/为空时原样返回（与各成绩页 filterByDefaultClass 约定一致）。
  /// 考核(项目/小组维度)、作品(student_name 维度)无 per-student user_id，
  /// 不做班级过滤——强行映射会破坏跨班项目组语义。
  Future<List<Map<String, dynamic>>> _filterLabByClass(
      List<Map<String, dynamic>> rows) {
    return DefaultClassService.instance
        .filterByDefaultClass(rows, (r) => (r['user_id'] as String?) ?? '');
  }

  // ══════════════════════════════════════════════════════════
  //  实验成绩导出
  // ══════════════════════════════════════════════════════════

  Future<String?> exportLabScores() async {
    if (kIsWeb) return null;
    try {
      final data = await _filterLabByClass(
          await _labTaskDao.getAllStudentLabScores());
      if (data.isEmpty) return null;

      final buf = StringBuffer();
      buf.writeln('学号,姓名,章节,实验任务,满分,得分,状态,提交时间');

      for (final row in data) {
        final userId = _csvCell(row['user_id']);
        final name = _csvCell(row['real_name']);
        final chapter = _csvCell(row['chapter']);
        final taskTitle = _csvCell(row['task_title']);
        final maxScore = row['max_score']?.toString() ?? '';
        final score = row['score']?.toString() ?? '';
        final status = _csvCell(row['status']);
        final submitTime = _csvCell(row['submit_time']);
        buf.writeln('$userId,$name,$chapter,$taskTitle,$maxScore,$score,$status,$submitTime');
      }

      return await _saveToFile(buf.toString(), '实验成绩');
    } catch (e, st) {
      swallowDebug(e, tag: 'ScoreExportService.exportLabScores', stack: st);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getLabScoresForPreview() async {
    try {
      return await _filterLabByClass(
          await _labTaskDao.getAllStudentLabScores());
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ScoreExportService.getLabScoresForPreview', stack: st);
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════
  //  考核成绩导出
  // ══════════════════════════════════════════════════════════

  Future<String?> exportAssessmentScores() async {
    if (kIsWeb) return null;
    try {
      final data = await _assessmentDao.getScoreRanking();
      if (data.isEmpty) return null;

      final buf = StringBuffer();
      buf.writeln('小组,项目,功能完整性(25),技术深度(20),跨框架整合(25),性能质量(15),文档协作(15),总分,评语,评分时间');

      for (final row in data) {
        final group = _csvCell(row['group_name']);
        final project = _csvCell(row['project_name']);
        final functionality = row['score_functionality']?.toString() ?? '';
        final techDepth = row['score_tech_depth']?.toString() ?? '';
        final integration = row['score_integration']?.toString() ?? '';
        final quality = row['score_quality']?.toString() ?? '';
        final documentation = row['score_documentation']?.toString() ?? '';
        final total = row['total_score']?.toString() ?? '';
        final comment = _csvCell(row['comment']);
        final scoredAt = _csvCell(row['scored_at']);
        buf.writeln('$group,$project,$functionality,$techDepth,$integration,$quality,$documentation,$total,$comment,$scoredAt');
      }

      return await _saveToFile(buf.toString(), '考核成绩');
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ScoreExportService.exportAssessmentScores', stack: st);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAssessmentScoresForPreview() async {
    try {
      return await _assessmentDao.getScoreRanking();
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ScoreExportService.getAssessmentScoresForPreview', stack: st);
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════
  //  作品成绩导出
  // ══════════════════════════════════════════════════════════

  Future<String?> exportWorkScores() async {
    if (kIsWeb) return null;
    try {
      final data = await _worksDao.getScoreRecords();
      if (data.isEmpty) return null;

      final buf = StringBuffer();
      buf.writeln('学生姓名,仓库,作品名称,作品类型,功能完整性(25),技术深度(20),跨框架整合(25),性能质量(15),文档协作(15),总分,评语,评分人,评分时间');

      for (final row in data) {
        final studentName = _csvCell(row['student_name']);
        final repo = _csvCell(row['repo']);
        final workTitle = _csvCell(row['work_title']);
        final workType = _csvCell(row['work_type']);
        final functionality = row['score_functionality']?.toString() ?? '';
        final techDepth = row['score_tech_depth']?.toString() ?? '';
        final integration = row['score_integration']?.toString() ?? '';
        final quality = row['score_quality']?.toString() ?? '';
        final documentation = row['score_documentation']?.toString() ?? '';
        final total = row['total_score']?.toString() ?? '';
        final comment = _csvCell(row['comment']);
        final scorerName = _csvCell(row['scorer_name']);
        final scoredAt = _csvCell(row['scored_at']);
        buf.writeln('$studentName,$repo,$workTitle,$workType,$functionality,$techDepth,$integration,$quality,$documentation,$total,$comment,$scorerName,$scoredAt');
      }

      return await _saveToFile(buf.toString(), '作品成绩');
    } catch (e, st) {
      swallowDebug(e, tag: 'ScoreExportService.exportWorkScores', stack: st);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getWorkScoresForPreview() async {
    try {
      return await _worksDao.getScoreRecords();
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ScoreExportService.getWorkScoresForPreview', stack: st);
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════
  //  工具方法
  // ══════════════════════════════════════════════════════════

  String _csvCell(dynamic value) {
    if (value == null || value.toString().isEmpty) return '';
    var s = value.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      s = s.replaceAll('"', '""');
      return '"$s"';
    }
    return s;
  }

  Future<String?> _saveToFile(String content, String prefix) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = '${prefix}_$timestamp.csv';
      final file = File('${dir.path}/$fileName');
      // Write UTF-8 BOM first so Excel on Windows opens Chinese chars correctly
      await file.writeAsBytes(
        [0xEF, 0xBB, 0xBF, ...const Utf8Encoder().convert(content)],
      );
      return file.path;
    } catch (e, st) {
      swallowDebug(e, tag: 'ScoreExportService._saveToFile', stack: st);
      return null;
    }
  }
}
