import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/course_context_service.dart';

class DataExportPage extends StatefulWidget {
  const DataExportPage({super.key});

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  final _courseContext = CourseContextService();

  // Summary counts
  int _totalStudents = 0;
  int _totalQuizAttempts = 0;
  int _totalLearningRecords = 0;
  int _totalWorks = 0;
  bool _isSummaryLoading = true;

  // Per-report loading state
  final Map<String, bool> _reportLoading = {};

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isSummaryLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      final studentCount = await db.rawQuery(
        "SELECT COUNT(*) as c FROM users WHERE role = 'student'",
      );
      final quizScope = await _courseContext.scopedWhere();
      final learningScope = await _courseContext.scopedWhere();
      final quizCount = await db.rawQuery(
        'SELECT COUNT(*) as c FROM quiz_results WHERE ${quizScope.where}',
        quizScope.args,
      );
      final learningCount = await db.rawQuery(
        'SELECT COUNT(*) as c FROM learning_records WHERE ${learningScope.where}',
        learningScope.args,
      );
      final workScope = await _courseContext.scopedWhere();
      final workCount = await db.rawQuery(
        'SELECT COUNT(*) as c FROM student_works WHERE ${workScope.where}',
        workScope.args,
      );

      if (!mounted) return;
      setState(() {
        _totalStudents = (studentCount.first['c'] as int?) ?? 0;
        _totalQuizAttempts = (quizCount.first['c'] as int?) ?? 0;
        _totalLearningRecords = (learningCount.first['c'] as int?) ?? 0;
        _totalWorks = (workCount.first['c'] as int?) ?? 0;
        _isSummaryLoading = false;
      });
    } catch (e) {
      debugPrint('加载统计摘要失败: $e');
      if (!mounted) return;
      setState(() => _isSummaryLoading = false);
    }
  }

  // ── Report template definitions ──────────────────────────────────────────

  List<_ReportTemplate> get _reportTemplates => [
        _ReportTemplate(
          key: 'grade_summary',
          icon: Icons.assessment_outlined,
          title: '班级成绩总表',
          description: '导出全部学生的测验成绩，按平均分排序，包含各章节得分明细。',
          color: const Color(0xFF1677FF),
          generator: _generateGradeSummary,
        ),
        _ReportTemplate(
          key: 'learning_alert',
          icon: Icons.warning_amber_rounded,
          title: '学情预警报告',
          description: '筛选低分学生和长期未学习的学生，生成预警名单。',
          color: const Color(0xFFe17055),
          generator: _generateLearningAlert,
        ),
        _ReportTemplate(
          key: 'chapter_mastery',
          icon: Icons.bar_chart_rounded,
          title: '章节掌握度分析',
          description: '统计各章节全体学生的正确率，发现教学薄弱环节。',
          color: const Color(0xFF00b894),
          generator: _generateChapterMastery,
        ),
        _ReportTemplate(
          key: 'work_scores',
          icon: Icons.work_outline_rounded,
          title: '作品评分汇总',
          description: '汇总所有学生作品及评分，按总分排序。',
          color: const Color(0xFF6c5ce7),
          generator: _generateWorkScores,
        ),
        _ReportTemplate(
          key: 'comprehensive',
          icon: Icons.summarize_outlined,
          title: '教学效果综合报告',
          description: '整合成绩、学情、章节掌握度和作品评分，生成完整教学分析报告。',
          color: const Color(0xFFfdcb6e),
          generator: _generateComprehensiveReport,
        ),
      ];

  // ── Report generators ────────────────────────────────────────────────────

  Future<String> _generateGradeSummary() async {
    final db = await DatabaseHelper.instance.database;
    final quizScope = await _courseContext.scopedWhere(column: 'qr.course_id');

    // Get per-student average scores, sorted descending
    final results = await db.rawQuery('''
      SELECT
        qr.user_id,
        COALESCE(u.real_name, qr.user_id) AS name,
        COUNT(*) AS attempts,
        ROUND(AVG(qr.score), 1) AS avg_score,
        MAX(qr.score) AS max_score,
        MIN(qr.score) AS min_score,
        SUM(qr.num_correct) AS total_correct,
        SUM(qr.num_total) AS total_questions
      FROM quiz_results qr
      LEFT JOIN users u ON qr.user_id = u.user_id
      WHERE ${quizScope.where}
      GROUP BY qr.user_id
      ORDER BY avg_score DESC
    ''', quizScope.args);

    if (results.isEmpty) {
      return '暂无测验成绩数据。';
    }

    final buf = StringBuffer();
    buf.writeln('班级成绩总表');
    buf.writeln('${'=' * 72}');
    buf.writeln(
      _padRow(['排名', '学号', '姓名', '次数', '平均分', '最高分', '最低分', '正确率'],
          [4, 12, 10, 4, 8, 8, 8, 8]),
    );
    buf.writeln('${'-' * 72}');

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final totalCorrect = (r['total_correct'] as num?) ?? 0;
      final totalQuestions = (r['total_questions'] as num?) ?? 0;
      final accuracy = totalQuestions > 0
          ? '${(totalCorrect / totalQuestions * 100).toStringAsFixed(1)}%'
          : 'N/A';

      buf.writeln(
        _padRow([
          '${i + 1}',
          '${r['user_id']}',
          '${r['name']}',
          '${r['attempts']}',
          '${r['avg_score']}',
          '${r['max_score']}',
          '${r['min_score']}',
          accuracy,
        ], [
          4,
          12,
          10,
          4,
          8,
          8,
          8,
          8
        ]),
      );
    }

    buf.writeln('${'-' * 72}');
    buf.writeln('共 ${results.length} 名学生参加测验');

    // Per-chapter breakdown
    final chapterScope = await _courseContext.scopedWhere(
      extraWhere: "chapter IS NOT NULL AND chapter != ''",
    );
    final chapterResults = await db.rawQuery('''
      SELECT
        chapter,
        COUNT(DISTINCT user_id) AS student_count,
        COUNT(*) AS attempt_count,
        ROUND(AVG(score), 1) AS avg_score,
        SUM(num_correct) AS total_correct,
        SUM(num_total) AS total_questions
      FROM quiz_results
      WHERE ${chapterScope.where}
      GROUP BY chapter
      ORDER BY chapter
    ''', chapterScope.args);

    if (chapterResults.isNotEmpty) {
      buf.writeln('');
      buf.writeln('各章节成绩概览');
      buf.writeln('${'=' * 60}');
      buf.writeln(
        _padRow(['章节', '参与人数', '测验次数', '平均分', '正确率'], [16, 10, 10, 10, 10]),
      );
      buf.writeln('${'-' * 60}');

      for (final r in chapterResults) {
        final totalCorrect = (r['total_correct'] as num?) ?? 0;
        final totalQuestions = (r['total_questions'] as num?) ?? 0;
        final accuracy = totalQuestions > 0
            ? '${(totalCorrect / totalQuestions * 100).toStringAsFixed(1)}%'
            : 'N/A';
        buf.writeln(
          _padRow([
            '${r['chapter']}',
            '${r['student_count']}',
            '${r['attempt_count']}',
            '${r['avg_score']}',
            accuracy,
          ], [
            16,
            10,
            10,
            10,
            10
          ]),
        );
      }
    }

    return buf.toString();
  }

  Future<String> _generateLearningAlert() async {
    final db = await DatabaseHelper.instance.database;
    final lowScoreScope = await _courseContext.scopedWhere(
      column: 'qr.course_id',
    );

    final buf = StringBuffer();
    buf.writeln('学情预警报告');
    buf.writeln('${'=' * 72}');

    // 1. Students with low average score (< 60)
    final lowScoreStudents = await db.rawQuery('''
      SELECT
        qr.user_id,
        COALESCE(u.real_name, qr.user_id) AS name,
        COUNT(*) AS attempts,
        ROUND(AVG(qr.score), 1) AS avg_score,
        SUM(qr.num_correct) AS total_correct,
        SUM(qr.num_total) AS total_questions
      FROM quiz_results qr
      LEFT JOIN users u ON qr.user_id = u.user_id
      WHERE ${lowScoreScope.where}
      GROUP BY qr.user_id
      HAVING avg_score < 60
      ORDER BY avg_score ASC
    ''', lowScoreScope.args);

    buf.writeln('');
    buf.writeln('一、成绩预警（平均分 < 60）');
    buf.writeln('${'-' * 60}');

    if (lowScoreStudents.isEmpty) {
      buf.writeln('  无预警学生，所有学生平均分均达标。');
    } else {
      buf.writeln(
        _padRow(['学号', '姓名', '测验次数', '平均分', '正确率'], [12, 10, 10, 10, 10]),
      );
      buf.writeln('${'-' * 60}');
      for (final r in lowScoreStudents) {
        final totalCorrect = (r['total_correct'] as num?) ?? 0;
        final totalQuestions = (r['total_questions'] as num?) ?? 0;
        final accuracy = totalQuestions > 0
            ? '${(totalCorrect / totalQuestions * 100).toStringAsFixed(1)}%'
            : 'N/A';
        buf.writeln(
          _padRow([
            '${r['user_id']}',
            '${r['name']}',
            '${r['attempts']}',
            '${r['avg_score']}',
            accuracy,
          ], [
            12,
            10,
            10,
            10,
            10
          ]),
        );
      }
      buf.writeln('  共 ${lowScoreStudents.length} 名学生成绩预警');
    }

    // 2. Students with many wrong answers
    final wrongScope = await _courseContext.scopedWhere(
      column: 'wa.course_id',
    );
    final highWrongStudents = await db.rawQuery('''
      SELECT
        wa.user_id,
        COALESCE(u.real_name, wa.user_id) AS name,
        COUNT(*) AS wrong_count,
        SUM(wa.times) AS total_wrong_times
      FROM wrong_answers wa
      LEFT JOIN users u ON wa.user_id = u.user_id
      WHERE ${wrongScope.where}
      GROUP BY wa.user_id
      HAVING total_wrong_times >= 5
      ORDER BY total_wrong_times DESC
    ''', wrongScope.args);

    buf.writeln('');
    buf.writeln('二、错题频次预警（累计错误 ≥ 5 次）');
    buf.writeln('${'-' * 50}');

    if (highWrongStudents.isEmpty) {
      buf.writeln('  无预警学生。');
    } else {
      buf.writeln(
        _padRow(['学号', '姓名', '错题数', '累计错误次数'], [12, 10, 10, 14]),
      );
      buf.writeln('${'-' * 50}');
      for (final r in highWrongStudents) {
        buf.writeln(
          _padRow([
            '${r['user_id']}',
            '${r['name']}',
            '${r['wrong_count']}',
            '${r['total_wrong_times']}',
          ], [
            12,
            10,
            10,
            14
          ]),
        );
      }
    }

    // 3. Inactive students (registered but no quiz or learning records)
    final inactiveQuizScope = await _courseContext.scopedWhere();
    final inactiveLearningScope = await _courseContext.scopedWhere();
    final inactiveStudents = await db.rawQuery('''
      SELECT
        u.user_id,
        COALESCE(u.real_name, u.user_id) AS name
      FROM users u
      WHERE u.role = 'student' AND u.is_active = 1
        AND u.user_id NOT IN (
          SELECT DISTINCT user_id FROM quiz_results
          WHERE ${inactiveQuizScope.where}
        )
        AND u.user_id NOT IN (
          SELECT DISTINCT user_id FROM learning_records
          WHERE ${inactiveLearningScope.where}
        )
      ORDER BY u.user_id
    ''', [...inactiveQuizScope.args, ...inactiveLearningScope.args]);

    buf.writeln('');
    buf.writeln('三、零活跃预警（无测验记录且无学习记录）');
    buf.writeln('${'-' * 40}');

    if (inactiveStudents.isEmpty) {
      buf.writeln('  所有学生均有学习活动记录。');
    } else {
      buf.writeln(_padRow(['学号', '姓名'], [12, 14]));
      buf.writeln('${'-' * 40}');
      for (final r in inactiveStudents) {
        buf.writeln(
          _padRow(['${r['user_id']}', '${r['name']}'], [12, 14]),
        );
      }
      buf.writeln('  共 ${inactiveStudents.length} 名学生零活跃');
    }

    return buf.toString();
  }

  Future<String> _generateChapterMastery() async {
    final db = await DatabaseHelper.instance.database;
    final quizScope = await _courseContext.scopedWhere(
      extraWhere: "chapter IS NOT NULL AND chapter != ''",
    );

    final buf = StringBuffer();
    buf.writeln('章节掌握度分析');
    buf.writeln('${'=' * 72}');

    // Overall chapter stats from quiz_results
    final chapterStats = await db.rawQuery('''
      SELECT
        chapter,
        COUNT(DISTINCT user_id) AS student_count,
        COUNT(*) AS attempt_count,
        SUM(num_correct) AS total_correct,
        SUM(num_total) AS total_questions,
        ROUND(AVG(score), 1) AS avg_score,
        MAX(score) AS max_score,
        MIN(score) AS min_score
      FROM quiz_results
      WHERE ${quizScope.where}
      GROUP BY chapter
      ORDER BY chapter
    ''', quizScope.args);

    if (chapterStats.isEmpty) {
      buf.writeln('暂无按章节分类的测验数据。');
      return buf.toString();
    }

    buf.writeln(
      _padRow(['章节', '人次', '平均分', '最高', '最低', '正确率', '掌握等级'],
          [16, 6, 8, 6, 6, 10, 10]),
    );
    buf.writeln('${'-' * 72}');

    for (final r in chapterStats) {
      final totalCorrect = (r['total_correct'] as num?) ?? 0;
      final totalQuestions = (r['total_questions'] as num?) ?? 0;
      final accuracyVal =
          totalQuestions > 0 ? (totalCorrect / totalQuestions * 100) : 0.0;
      final accuracy = '${accuracyVal.toStringAsFixed(1)}%';
      final level = _getMasteryLevel(accuracyVal);

      buf.writeln(
        _padRow([
          '${r['chapter']}',
          '${r['attempt_count']}',
          '${r['avg_score']}',
          '${r['max_score']}',
          '${r['min_score']}',
          accuracy,
          level,
        ], [
          16,
          6,
          8,
          6,
          6,
          10,
          10
        ]),
      );
    }

    buf.writeln('${'-' * 72}');
    buf.writeln('');
    buf.writeln('掌握等级标准: 优秀(≥90%) | 良好(≥75%) | 中等(≥60%) | 待加强(<60%)');

    // Per-chapter wrong answer hotspots
    final wrongScope = await _courseContext.scopedWhere(
      column: 'wa.course_id',
      extraWhere: "wa.chapter IS NOT NULL AND wa.chapter != ''",
    );
    final wrongHotspots = await db.rawQuery('''
      SELECT
        wa.chapter,
        wa.question,
        SUM(wa.times) AS total_times,
        COUNT(DISTINCT wa.user_id) AS affected_students
      FROM wrong_answers wa
      WHERE ${wrongScope.where}
      GROUP BY wa.chapter, wa.question_id
      HAVING total_times >= 2
      ORDER BY total_times DESC
      LIMIT 10
    ''', wrongScope.args);

    if (wrongHotspots.isNotEmpty) {
      buf.writeln('');
      buf.writeln('高频错题 TOP 10');
      buf.writeln('${'=' * 72}');

      for (var i = 0; i < wrongHotspots.length; i++) {
        final r = wrongHotspots[i];
        final question = '${r['question'] ?? ''}';
        final displayQuestion =
            question.length > 40 ? '${question.substring(0, 40)}...' : question;
        buf.writeln(
          '  ${i + 1}. [${r['chapter']}] $displayQuestion',
        );
        buf.writeln(
          '     错误人数: ${r['affected_students']}  累计错误: ${r['total_times']} 次',
        );
      }
    }

    return buf.toString();
  }

  Future<String> _generateWorkScores() async {
    final db = await DatabaseHelper.instance.database;
    final workScope = await _courseContext.scopedWhere(column: 'sw.course_id');

    final buf = StringBuffer();
    buf.writeln('作品评分汇总');
    buf.writeln('${'=' * 80}');

    final works = await db.rawQuery('''
      SELECT
        sw.id AS work_id,
        sw.title,
        sw.work_type,
        sw.group_name,
        sw.leader_name,
        sw.status,
        COALESCE(u.real_name, sw.user_id, '未知') AS student_name,
        ws_agg.avg_total AS avg_total_score,
        ws_agg.avg_func AS avg_func_score,
        ws_agg.avg_tech AS avg_tech_score,
        ws_agg.avg_integ AS avg_integ_score,
        ws_agg.avg_qual AS avg_qual_score,
        ws_agg.avg_doc AS avg_doc_score,
        ws_agg.score_count
      FROM student_works sw
      LEFT JOIN users u ON sw.user_id = u.user_id
      LEFT JOIN (
        SELECT
          work_id,
          COUNT(*) AS score_count,
          ROUND(AVG(total_score), 1) AS avg_total,
          ROUND(AVG(score_functionality), 1) AS avg_func,
          ROUND(AVG(score_tech_depth), 1) AS avg_tech,
          ROUND(AVG(score_integration), 1) AS avg_integ,
          ROUND(AVG(score_quality), 1) AS avg_qual,
          ROUND(AVG(score_documentation), 1) AS avg_doc
        FROM work_scores
        GROUP BY work_id
      ) ws_agg ON sw.id = ws_agg.work_id
      WHERE ${workScope.where}
      ORDER BY ws_agg.avg_total DESC, sw.title ASC
    ''', workScope.args);

    if (works.isEmpty) {
      buf.writeln('暂无学生作品数据。');
      return buf.toString();
    }

    // Summary table
    buf.writeln(
      _padRow(['序号', '作品名称', '类型', '提交者/组长', '评分次数', '平均总分', '状态'],
          [4, 18, 10, 12, 8, 10, 8]),
    );
    buf.writeln('${'-' * 80}');

    for (var i = 0; i < works.length; i++) {
      final r = works[i];
      final title = '${r['title']}';
      final displayTitle =
          title.length > 16 ? '${title.substring(0, 14)}..' : title;
      final submitter = '${r['leader_name'] ?? r['student_name']}';
      final displaySubmitter =
          submitter.length > 10 ? '${submitter.substring(0, 8)}..' : submitter;

      buf.writeln(
        _padRow([
          '${i + 1}',
          displayTitle,
          '${r['work_type'] ?? '-'}',
          displaySubmitter,
          '${r['score_count'] ?? 0}',
          '${r['avg_total_score'] ?? '未评'}',
          '${r['status'] ?? '-'}',
        ], [
          4,
          18,
          10,
          12,
          8,
          10,
          8
        ]),
      );
    }

    // Detailed score breakdown for scored works
    final scoredWorks = works
        .where((w) =>
            (w['score_count'] as int?) != null && (w['score_count'] as int) > 0)
        .toList();

    if (scoredWorks.isNotEmpty) {
      buf.writeln('');
      buf.writeln('评分维度明细');
      buf.writeln('${'=' * 80}');
      buf.writeln(
        _padRow(['作品', '功能性', '技术深度', '集成度', '质量', '文档', '总分'],
            [18, 10, 10, 10, 10, 10, 10]),
      );
      buf.writeln('${'-' * 80}');

      for (final r in scoredWorks) {
        final title = '${r['title']}';
        final displayTitle =
            title.length > 16 ? '${title.substring(0, 14)}..' : title;
        buf.writeln(
          _padRow([
            displayTitle,
            '${r['avg_func_score'] ?? '-'}',
            '${r['avg_tech_score'] ?? '-'}',
            '${r['avg_integ_score'] ?? '-'}',
            '${r['avg_qual_score'] ?? '-'}',
            '${r['avg_doc_score'] ?? '-'}',
            '${r['avg_total_score'] ?? '-'}',
          ], [
            18,
            10,
            10,
            10,
            10,
            10,
            10
          ]),
        );
      }
    }

    buf.writeln('${'-' * 80}');
    buf.writeln('共 ${works.length} 个作品，其中 ${scoredWorks.length} 个已评分');

    return buf.toString();
  }

  Future<String> _generateComprehensiveReport() async {
    final buf = StringBuffer();
    final now = DateTime.now();
    final courseName = await _courseContext.activeCourseName();
    final timestamp =
        '${now.year}-${_pad2(now.month)}-${_pad2(now.day)} ${_pad2(now.hour)}:${_pad2(now.minute)}';

    buf.writeln('╔${'═' * 68}╗');
    buf.writeln('║${_center('《$courseName》课程教学效果综合报告', 68)}║');
    buf.writeln('║${_center('生成时间: $timestamp', 68)}║');
    buf.writeln('╚${'═' * 68}╝');
    buf.writeln('');

    // Section 1: Overview
    final db = await DatabaseHelper.instance.database;
    final quizScope = await _courseContext.scopedWhere();
    final learningScope = await _courseContext.scopedWhere();

    final studentCount = await db.rawQuery(
      "SELECT COUNT(*) as c FROM users WHERE role = 'student' AND is_active = 1",
    );
    final quizCount = await db.rawQuery(
      'SELECT COUNT(*) as c FROM quiz_results WHERE ${quizScope.where}',
      quizScope.args,
    );
    final learningCount = await db.rawQuery(
      'SELECT COUNT(*) as c FROM learning_records WHERE ${learningScope.where}',
      learningScope.args,
    );
    final workScope = await _courseContext.scopedWhere();
    final workCount = await db.rawQuery(
      'SELECT COUNT(*) as c FROM student_works WHERE ${workScope.where}',
      workScope.args,
    );
    final avgScore = await db.rawQuery(
      'SELECT ROUND(AVG(score), 1) as avg FROM quiz_results WHERE ${quizScope.where}',
      quizScope.args,
    );

    final students = (studentCount.first['c'] as int?) ?? 0;
    final quizzes = (quizCount.first['c'] as int?) ?? 0;
    final learnings = (learningCount.first['c'] as int?) ?? 0;
    final worksNum = (workCount.first['c'] as int?) ?? 0;
    final overallAvg = avgScore.first['avg'] ?? 'N/A';

    buf.writeln('一、总体概况');
    buf.writeln('${'─' * 40}');
    buf.writeln('  在册学生数:     $students 人');
    buf.writeln('  测验总次数:     $quizzes 次');
    buf.writeln('  学习记录总数:   $learnings 条');
    buf.writeln('  提交作品数:     $worksNum 个');
    buf.writeln('  全班平均分:     $overallAvg 分');
    buf.writeln('');

    // Section 2: Grade summary (abbreviated)
    buf.writeln('二、班级成绩概况');
    buf.writeln('${'─' * 40}');

    try {
      final gradeReport = await _generateGradeSummary();
      // Extract just the main table (skip the first 2 header lines since we have our own)
      final lines = gradeReport.split('\n');
      if (lines.length > 2) {
        for (var i = 2; i < lines.length; i++) {
          buf.writeln(lines[i]);
        }
      }
    } catch (e) {
      buf.writeln('  成绩数据加载失败: $e');
    }
    buf.writeln('');

    // Section 3: Learning alerts (abbreviated)
    buf.writeln('三、学情预警');
    buf.writeln('${'─' * 40}');

    try {
      final alertReport = await _generateLearningAlert();
      final lines = alertReport.split('\n');
      if (lines.length > 2) {
        for (var i = 2; i < lines.length; i++) {
          buf.writeln(lines[i]);
        }
      }
    } catch (e) {
      buf.writeln('  学情数据加载失败: $e');
    }
    buf.writeln('');

    // Section 4: Chapter mastery
    buf.writeln('四、章节掌握度');
    buf.writeln('${'─' * 40}');

    try {
      final masteryReport = await _generateChapterMastery();
      final lines = masteryReport.split('\n');
      if (lines.length > 2) {
        for (var i = 2; i < lines.length; i++) {
          buf.writeln(lines[i]);
        }
      }
    } catch (e) {
      buf.writeln('  章节数据加载失败: $e');
    }
    buf.writeln('');

    // Section 5: Work scores
    buf.writeln('五、作品评分');
    buf.writeln('${'─' * 40}');

    try {
      final workReport = await _generateWorkScores();
      final lines = workReport.split('\n');
      if (lines.length > 2) {
        for (var i = 2; i < lines.length; i++) {
          buf.writeln(lines[i]);
        }
      }
    } catch (e) {
      buf.writeln('  作品数据加载失败: $e');
    }

    buf.writeln('');
    buf.writeln('${'═' * 70}');
    buf.writeln('报告结束 — 生成于 $timestamp');

    return buf.toString();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _getMasteryLevel(double accuracy) {
    if (accuracy >= 90) return '优秀 ★★★';
    if (accuracy >= 75) return '良好 ★★';
    if (accuracy >= 60) return '中等 ★';
    return '待加强';
  }

  /// Pad each cell to a fixed width (supports CJK characters which are double-width).
  String _padRow(List<String> cells, List<int> widths) {
    final buf = StringBuffer();
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final width = i < widths.length ? widths[i] : 10;
      final displayLen = _displayLength(cell);
      final padding = (width - displayLen).clamp(0, width);
      buf.write(cell);
      buf.write(' ' * padding);
    }
    return buf.toString();
  }

  /// Calculate display length considering CJK characters as width 2.
  int _displayLength(String s) {
    int len = 0;
    for (final rune in s.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF ||
          rune >= 0x3000 && rune <= 0x303F ||
          rune >= 0xFF00 && rune <= 0xFFEF ||
          rune >= 0x2E80 && rune <= 0x2FDF ||
          rune >= 0x3400 && rune <= 0x4DBF) {
        len += 2;
      } else {
        len += 1;
      }
    }
    return len;
  }

  /// Center text within a given width.
  String _center(String text, int width) {
    final displayLen = _displayLength(text);
    final totalPadding = (width - displayLen).clamp(0, width);
    final left = totalPadding ~/ 2;
    final right = totalPadding - left;
    return '${' ' * left}$text${' ' * right}';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');

  // ── Report generation entry point ────────────────────────────────────────

  Future<void> _onGenerateReport(_ReportTemplate template) async {
    setState(() => _reportLoading[template.key] = true);

    try {
      final content = await template.generator();
      if (!mounted) return;

      setState(() => _reportLoading[template.key] = false);

      _showReportPreview(template.title, content);
    } catch (e) {
      debugPrint('生成报告失败 [${template.key}]: $e');
      if (!mounted) return;

      setState(() => _reportLoading[template.key] = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('生成报告失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Report preview bottom sheet ──────────────────────────────────────────

  void _showReportPreview(String title, String content) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${_pad2(now.month)}-${_pad2(now.day)} ${_pad2(now.hour)}:${_pad2(now.minute)}:${_pad2(now.second)}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '生成时间: $timestamp',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('报告已复制到剪贴板'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Report content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('教学数据导出'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新统计',
            onPressed: _loadSummary,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Summary cards
            _buildSummarySection(theme),
            const SizedBox(height: 24),
            // Report templates header
            Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  '报告模板',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '选择模板一键生成报告，支持复制到剪贴板',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            // Report template cards
            ..._reportTemplates
                .map((template) => _buildReportCard(theme, template)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(ThemeData theme) {
    if (_isSummaryLoading) {
      return SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    return Row(
      children: [
        _buildSummaryCard(
          icon: Icons.people_outline,
          label: '学生总数',
          value: '$_totalStudents',
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        _buildSummaryCard(
          icon: Icons.quiz_outlined,
          label: '测验次数',
          value: '$_totalQuizAttempts',
          color: const Color(0xFF00b894),
        ),
        const SizedBox(width: 8),
        _buildSummaryCard(
          icon: Icons.menu_book_outlined,
          label: '学习记录',
          value: '$_totalLearningRecords',
          color: const Color(0xFFe17055),
        ),
        const SizedBox(width: 8),
        _buildSummaryCard(
          icon: Icons.work_outline,
          label: '作品数',
          value: '$_totalWorks',
          color: const Color(0xFF6c5ce7),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              color.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(ThemeData theme, _ReportTemplate template) {
    final isLoading = _reportLoading[template.key] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 1,
      child: InkWell(
        onTap: isLoading ? null : () => _onGenerateReport(template),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: template.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  template.icon,
                  color: template.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Title + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Generate button
              isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: template.color,
                      ),
                    )
                  : OutlinedButton(
                      onPressed: () => _onGenerateReport(template),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: template.color,
                        side: BorderSide(
                          color: template.color.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        '生成报告',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Report template model ────────────────────────────────────────────────────

class _ReportTemplate {
  final String key;
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final Future<String> Function() generator;

  const _ReportTemplate({
    required this.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.generator,
  });
}
