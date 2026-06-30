import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'active_student_scope.dart';
import 'database_helper.dart';
import '../../services/course_resource_service.dart';
import '../../services/course_context_service.dart';

/// 实验任务 DAO — 任务发布 / 学生提交 / 评分 / 报告
class LabTaskDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  // ═══════════ 实验任务 CRUD ═══════════

  Future<List<Map<String, dynamic>>> getTasks(
      {String? chapter, String? status}) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere();
    String sql = 'SELECT * FROM lab_tasks WHERE ${scope.where}';
    final args = <dynamic>[...scope.args];
    if (chapter != null) {
      sql += ' AND chapter = ?';
      args.add(chapter);
    }
    if (status != null) {
      sql += ' AND status = ?';
      args.add(status);
    }
    sql += ' ORDER BY created_at DESC';
    return db.rawQuery(sql, args);
  }

  Future<Map<String, dynamic>?> getTask(int id) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'id = ?',
      extraArgs: [id],
    );
    final list = await db.query(
      'lab_tasks',
      where: scope.where,
      whereArgs: scope.args,
    );
    return list.isNotEmpty ? list.first : null;
  }

  Future<int> addTask({
    required String title,
    String? chapter,
    String? description,
    String? requirements,
    String? deliverables,
    String? dueDate,
    String difficulty = '中等',
    int maxScore = 100,
    String? creatorId,
  }) async {
    final db = await _dbHelper.database;
    return db.insert('lab_tasks', {
      'course_id': await _courseContext.activeCourseId(),
      'title': title,
      'chapter': chapter,
      'description': description,
      'requirements': requirements,
      'deliverables': deliverables,
      'due_date': dueDate,
      'difficulty': difficulty,
      'max_score': maxScore,
      'status': 'active',
      'creator_id': creatorId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateTask(int id, Map<String, dynamic> data) async {
    final db = await _dbHelper.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update('lab_tasks', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await _dbHelper.database;
    return db.delete('lab_tasks', where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════ 实验提交 ═══════════

  Future<List<Map<String, dynamic>>> getSubmissions(
      {int? taskId, String? userId}) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(column: 't.course_id');
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    String sql = '''
      SELECT s.*, t.title as task_title, t.chapter, t.max_score, t.difficulty,
             u.real_name
      FROM lab_submissions s
      LEFT JOIN lab_tasks t ON t.id = s.task_id
      LEFT JOIN users u ON u.user_id = s.user_id
      WHERE ${scope.where}
        AND $activeWhere
    ''';
    final args = <dynamic>[...scope.args];
    if (taskId != null) {
      sql += ' AND s.task_id = ?';
      args.add(taskId);
    }
    if (userId != null) {
      sql += ' AND s.user_id = ?';
      args.add(userId);
    }
    sql += ' ORDER BY s.submit_time DESC';
    return db.rawQuery(sql, args);
  }

  Future<Map<String, dynamic>?> getSubmission(int taskId, String userId) async {
    final db = await _dbHelper.database;
    final list = await db.query('lab_submissions',
        where: 'task_id = ? AND user_id = ?', whereArgs: [taskId, userId]);
    return list.isNotEmpty ? list.first : null;
  }

  Future<int> submitTask({
    required int taskId,
    required String userId,
    String? content,
    String? filePaths,
    String? fileNames,
  }) async {
    final db = await _dbHelper.database;
    // Upsert: 已存在则更新，不存在则插入
    final existing = await getSubmission(taskId, userId);
    final now = DateTime.now().toIso8601String();
    if (existing != null) {
      await db.update(
          'lab_submissions',
          {
            'content': content,
            'file_paths': filePaths,
            'file_names': fileNames,
            'submit_time': now,
            'status': '已提交',
            'score': null,
            'feedback': null,
            'scorer_id': null,
            'scored_at': null,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [existing['id']]);
      return existing['id'] as int;
    } else {
      return db.insert('lab_submissions', {
        'task_id': taskId,
        'user_id': userId,
        'content': content,
        'file_paths': filePaths,
        'file_names': fileNames,
        'submit_time': now,
        'status': '已提交',
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  Future<int> gradeSubmission(
    int submissionId, {
    required int score,
    String? feedback,
    String? scorerId,
  }) async {
    final db = await _dbHelper.database;
    return db.update(
        'lab_submissions',
        {
          'score': score,
          'feedback': feedback,
          'scorer_id': scorerId,
          'scored_at': DateTime.now().toIso8601String(),
          'status': '已批改',
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [submissionId]);
  }

  Future<int> returnSubmission(
    int submissionId, {
    required String reason,
    String? reviewerId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    return db.update(
        'lab_submissions',
        {
          'score': null,
          'feedback': reason,
          'scorer_id': reviewerId,
          'scored_at': now,
          'status': '已打回',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [submissionId]);
  }

  Future<int> updateSubmission({
    required int submissionId,
    String? content,
  }) async {
    final db = await _dbHelper.database;
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (content != null) {
      data['content'] = content;
    }
    return db.update('lab_submissions', data,
        where: 'id = ?', whereArgs: [submissionId]);
  }

  Future<int> deleteSubmission(int submissionId) async {
    final db = await _dbHelper.database;
    return db
        .delete('lab_submissions', where: 'id = ?', whereArgs: [submissionId]);
  }

  // ═══════════ 统计 ═══════════

  Future<Map<String, dynamic>> getTaskStats(int taskId) async {
    final db = await _dbHelper.database;
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as total_submissions,
        SUM(CASE WHEN s.score IS NOT NULL THEN 1 ELSE 0 END) as graded_count,
        AVG(s.score) as avg_score,
        MAX(s.score) as max_score,
        MIN(s.score) as min_score
      FROM lab_submissions s
      JOIN users u ON u.user_id = s.user_id
      WHERE s.task_id = ?
        AND $activeWhere
    ''', [taskId]);
    return result.isNotEmpty ? result.first : {};
  }

  Future<Map<String, dynamic>> getStudentLabStats(String userId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(column: 't.course_id');
    final taskScope = await _courseContext.scopedWhere(column: 'lt.course_id');
    final result = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT s.task_id) as submitted_tasks,
        (SELECT COUNT(*) FROM lab_tasks lt WHERE ${taskScope.where} AND status = 'active') as total_tasks,
        AVG(s.score) as avg_score,
        SUM(CASE WHEN s.status = '已批改' THEN 1 ELSE 0 END) as graded_count
      FROM lab_submissions s
      LEFT JOIN lab_tasks t ON t.id = s.task_id
      WHERE s.user_id = ?
        AND ${scope.where}
    ''', [...taskScope.args, userId, ...scope.args]);
    return result.isNotEmpty ? result.first : {};
  }

  /// 获取所有学生所有实验任务的得分详情（教师总览用）
  Future<List<Map<String, dynamic>>> getAllStudentLabScores() async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(column: 't.course_id');
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    return db.rawQuery('''
      SELECT
        s.user_id,
        u.real_name,
        s.task_id,
        t.title AS task_title,
        t.chapter,
        t.max_score,
        s.score,
        s.status,
        s.submit_time
      FROM lab_submissions s
      LEFT JOIN users u ON u.user_id = s.user_id
      LEFT JOIN lab_tasks t ON t.id = s.task_id
      WHERE $activeWhere
        AND ${scope.where}
      ORDER BY u.user_id, t.chapter, t.id
    ''', scope.args);
  }

  /// 获取单个学生所有实验任务得分详情
  Future<List<Map<String, dynamic>>> getStudentLabScoreDetail(
      String userId) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(column: 't.course_id');
    return db.rawQuery('''
      SELECT
        s.task_id,
        t.title AS task_title,
        t.chapter,
        t.max_score,
        s.score,
        s.status,
        s.feedback,
        s.submit_time,
        s.scored_at
      FROM lab_submissions s
      LEFT JOIN lab_tasks t ON t.id = s.task_id
      WHERE s.user_id = ?
        AND ${scope.where}
      ORDER BY t.chapter, t.id
    ''', [userId, ...scope.args]);
  }

  /// 班级实验总览统计（教师用）
  Future<Map<String, dynamic>> getClassLabOverview({int passScore = 60}) async {
    final db = await _dbHelper.database;
    final scope = await _courseContext.scopedWhere(column: 't.course_id');
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    final result = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT s.user_id) as student_count,
        COUNT(DISTINCT s.task_id) as task_count,
        AVG(s.score) as avg_score,
        MAX(s.score) as max_score,
        MIN(CASE WHEN s.score IS NOT NULL THEN s.score END) as min_score,
        SUM(CASE WHEN s.score >= ? THEN 1 ELSE 0 END) as excellent_count,
        SUM(CASE WHEN s.score >= 60 AND s.score < ? THEN 1 ELSE 0 END) as pass_count,
        SUM(CASE WHEN s.score < 60 THEN 1 ELSE 0 END) as fail_count,
        SUM(CASE WHEN s.score IS NULL THEN 1 ELSE 0 END) as ungraded_count
      FROM lab_submissions s
      INNER JOIN users u ON u.user_id = s.user_id
      LEFT JOIN lab_tasks t ON t.id = s.task_id
      WHERE $activeWhere
        AND ${scope.where}
    ''', [passScore, passScore, ...scope.args]);
    final row = result.isNotEmpty ? result.first : {};
    final total = (row['excellent_count'] ?? 0) +
        (row['pass_count'] ?? 0) +
        (row['fail_count'] ?? 0);
    return {
      ...row,
      'total_graded': total,
    };
  }

  // ═══════════ 报告模板 ═══════════

  Future<List<Map<String, dynamic>>> getReportTemplates(
      {String? category}) async {
    final db = await _dbHelper.database;
    String sql = 'SELECT * FROM report_templates WHERE 1=1';
    final args = <dynamic>[];
    if (category != null) {
      sql += ' AND category = ?';
      args.add(category);
    }
    sql += ' ORDER BY is_default DESC, created_at DESC';
    return db.rawQuery(sql, args);
  }

  Future<int> addReportTemplate({
    required String name,
    String category = '实验报告',
    required String sectionsJson,
    String? description,
    String? creatorId,
    bool isDefault = false,
  }) async {
    final db = await _dbHelper.database;
    return db.insert('report_templates', {
      'name': name,
      'category': category,
      'sections_json': sectionsJson,
      'description': description,
      'creator_id': creatorId,
      'is_default': isDefault ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> deleteReportTemplate(int id) async {
    final db = await _dbHelper.database;
    return db.delete('report_templates', where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════ 学生报告 ═══════════

  Future<List<Map<String, dynamic>>> getStudentReports(
      {String? userId, int? taskId, bool onlyWithTask = false}) async {
    final db = await _dbHelper.database;
    String sql = '''
      SELECT r.*, t.name as template_name, lt.title as task_title
      FROM student_reports r
      LEFT JOIN report_templates t ON t.id = r.template_id
      LEFT JOIN lab_tasks lt ON lt.id = r.task_id
      WHERE 1=1
      AND r.template_id IS NOT NULL
    ''';
    if (onlyWithTask) {
      // 只保留 task_id 确实指向 lab_tasks 表的记录（排除考核报告的 assessment_group id）
      sql += ' AND lt.id IS NOT NULL';
    }
    final args = <dynamic>[];
    if (userId != null) {
      sql += ' AND r.user_id = ?';
      args.add(userId);
    }
    if (taskId != null) {
      sql += ' AND r.task_id = ?';
      args.add(taskId);
    }
    sql += ' ORDER BY r.created_at DESC';
    return db.rawQuery(sql, args);
  }

  Future<int> saveReport({
    int? id,
    int? templateId,
    int? taskId,
    required String userId,
    required String title,
    required String contentJson,
    String status = '草稿',
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final data = {
      'template_id': templateId,
      'task_id': taskId,
      'user_id': userId,
      'title': title,
      'content_json': contentJson,
      'status': status,
      'submit_time': status == '已提交' ? now : null,
      'updated_at': now,
    };
    if (id != null) {
      return db
          .update('student_reports', data, where: 'id = ?', whereArgs: [id]);
    } else {
      data['created_at'] = now;
      return db.insert('student_reports', data);
    }
  }

  Future<int> deleteReport(int id) async {
    final db = await _dbHelper.database;
    return db.delete('student_reports', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> gradeReport({
    required int id,
    required int score,
    required String feedback,
  }) async {
    final db = await _dbHelper.database;
    return db.update(
      'student_reports',
      {
        'score': score,
        'feedback': feedback,
        'status': '已批改',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 打回 student_reports 报告：清空分数、写入打回理由、状态置「已打回」。
  Future<int> returnReport({
    required int id,
    required String reason,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    return db.update(
      'student_reports',
      {
        'score': null,
        'feedback': reason,
        'status': '已打回',
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ═══════════ 互评 ═══════════

  Future<List<Map<String, dynamic>>> getPeerReviews(int submissionId) async {
    final db = await _dbHelper.database;
    return db.query('peer_reviews',
        where: 'submission_id = ?',
        whereArgs: [submissionId],
        orderBy: 'reviewed_at DESC');
  }

  Future<int> addPeerReview({
    required int submissionId,
    required String reviewerId,
    String? reviewerName,
    required int score,
    String? comment,
  }) async {
    final db = await _dbHelper.database;
    return db.insert(
        'peer_reviews',
        {
          'submission_id': submissionId,
          'reviewer_id': reviewerId,
          'reviewer_name': reviewerName,
          'score': score,
          'comment': comment,
          'reviewed_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ═══════════ 协作消息 ═══════════

  Future<List<Map<String, dynamic>>> getMessages(
      {int? groupId, int? taskId, int limit = 50}) async {
    final db = await _dbHelper.database;
    String sql = 'SELECT * FROM collaboration_messages WHERE 1=1';
    final args = <dynamic>[];
    if (groupId != null) {
      sql += ' AND group_id = ?';
      args.add(groupId);
    }
    if (taskId != null) {
      sql += ' AND task_id = ?';
      args.add(taskId);
    }
    sql += ' ORDER BY created_at DESC LIMIT ?';
    args.add(limit);
    return db.rawQuery(sql, args);
  }

  Future<int> sendMessage({
    int? groupId,
    int? taskId,
    required String senderId,
    String? senderName,
    required String message,
    String messageType = 'text',
  }) async {
    final db = await _dbHelper.database;
    return db.insert('collaboration_messages', {
      'group_id': groupId,
      'task_id': taskId,
      'sender_id': senderId,
      'sender_name': senderName,
      'message': message,
      'message_type': messageType,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ═══════════ 初始化示例数据（优先远程，兜底硬编码） ═══════════

  Future<void> initDemoDataIfEmpty() async {
    final db = await _dbHelper.database;
    try {
      final scope = await _courseContext.scopedWhere();
      final count = await db.rawQuery(
        'SELECT COUNT(*) as c FROM lab_tasks WHERE ${scope.where}',
        scope.args,
      );
      if ((count.first['c'] as int? ?? 0) > 0) return;

      await _insertGenericTasksForActiveCourse(db);
      await _initReportTemplates(db);
    } catch (e) {
      debugPrint('LabTaskDao: initDemoDataIfEmpty error: $e');
    }
  }

  /// 初始化报告模板（优先远程）
  Future<void> _initReportTemplates(Database db) async {
    final tCount =
        await db.rawQuery('SELECT COUNT(*) as c FROM report_templates');
    if ((tCount.first['c'] as int? ?? 0) > 0) return;

    // 尝试远程
    try {
      final resource = CourseResourceService();
      final remoteTemplates = await resource.getReportTemplates();
      if (remoteTemplates != null && remoteTemplates.isNotEmpty) {
        final now = DateTime.now().toIso8601String();
        for (final t in remoteTemplates) {
          await db.insert('report_templates', {
            'name': t['name'] ?? '',
            'category': t['category'] ?? '',
            'sections_json': jsonEncode(t['sections'] ?? []),
            'description': t['description'] ?? '',
            'creator_id': '206004',
            'is_default': (t['is_default'] == true) ? 1 : 0,
            'created_at': now,
            'updated_at': now,
          });
        }
        debugPrint(
            'LabTaskDao: Loaded ${remoteTemplates.length} templates from Gitee');
        return;
      }
    } catch (e) {
      debugPrint('LabTaskDao: Remote templates load failed: $e');
    }

    // 兜底硬编码
    await _initDefaultReportTemplates(db);
  }

  Future<void> _insertGenericTasksForActiveCourse(Database db) async {
    final course = await _courseContext.getActiveCourse();
    final courseId = course.id;
    final chapters = await _courseContext.chapterTitles();
    final now = DateTime.now().toIso8601String();

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      await db.insert('lab_tasks', {
        'course_id': courseId,
        'title': '实验${i + 1} $chapter实践任务',
        'chapter': chapter,
        'description':
            '围绕《${course.name}》$chapter 设计一次课程实践任务，要求学生完成资料查阅、问题分析、过程记录和结果展示。',
        'requirements': '1. 明确本章核心概念和任务目标；\n'
            '2. 结合课程案例完成分析、设计或验证；\n'
            '3. 保留关键过程证据、截图、数据或文档；\n'
            '4. 说明遇到的问题、解决方法和改进方向。',
        'deliverables': '实验报告、过程记录、结果材料或演示文件',
        'difficulty': i == chapters.length - 1 ? '较难' : '中等',
        'max_score': 100,
        'due_date':
            DateTime.now().add(Duration(days: 14 + i * 7)).toIso8601String(),
        'status': 'active',
        'creator_id': '206004',
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  Future<void> _initDefaultReportTemplates(Database db) async {
    final now = DateTime.now().toIso8601String();

    // 实验报告模板
    await db.insert('report_templates', {
      'name': '标准实验报告模板',
      'category': '实验报告',
      'sections_json': '''[
        {"title":"实验目的","hint":"描述本次实验的目标和学习要求","required":true},
        {"title":"实验环境","hint":"列出开发工具、SDK版本、操作系统等","required":true},
        {"title":"实验步骤","hint":"详细描述实验的操作步骤","required":true},
        {"title":"实验结果","hint":"展示运行结果、截图、数据","required":true},
        {"title":"问题与解决","hint":"记录遇到的问题及解决方法","required":false},
        {"title":"实验总结","hint":"总结本次实验的收获和体会","required":true}
      ]''',
      'description': '适用于各章节实验的标准报告模板',
      'creator_id': '206004',
      'is_default': 1,
      'created_at': now,
      'updated_at': now,
    });

    // 项目开发文档模板
    await db.insert('report_templates', {
      'name': '项目开发文档模板',
      'category': '项目文档',
      'sections_json': '''[
        {"title":"项目概述","hint":"项目名称、目标用户、核心功能","required":true},
        {"title":"需求分析","hint":"功能需求、非功能需求、用户故事","required":true},
        {"title":"系统设计","hint":"架构设计、数据库设计、接口设计","required":true},
        {"title":"技术选型","hint":"框架、语言、第三方库及选型理由","required":true},
        {"title":"核心功能实现","hint":"关键代码说明、算法描述","required":true},
        {"title":"测试记录","hint":"测试用例、测试结果、Bug修复","required":false},
        {"title":"部署说明","hint":"构建步骤、运行环境要求","required":false},
        {"title":"总结与展望","hint":"项目成果、不足之处、改进方向","required":true}
      ]''',
      'description': '适用于综合项目的完整开发文档模板',
      'creator_id': '206004',
      'is_default': 0,
      'created_at': now,
      'updated_at': now,
    });

    // 答辩 PPT 大纲模板
    await db.insert('report_templates', {
      'name': '答辩PPT大纲模板',
      'category': '答辩材料',
      'sections_json': '''[
        {"title":"项目介绍","hint":"项目名称、团队成员、分工","required":true},
        {"title":"需求与设计","hint":"问题背景、解决方案、架构图","required":true},
        {"title":"功能演示","hint":"核心功能截图或录屏说明","required":true},
        {"title":"技术亮点","hint":"创新点、技术难点及解决方案","required":true},
        {"title":"项目总结","hint":"成果展示、数据统计、反思","required":true}
      ]''',
      'description': '适用于项目答辩准备的PPT大纲模板',
      'creator_id': '206004',
      'is_default': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ═══════════ 未提交学生查询 ═══════════

  /// 获取活跃学生总数
  Future<int> getActiveStudentCount() async {
    final db = await _dbHelper.database;
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    final r = await db.rawQuery('''
      SELECT COUNT(*) as c
      FROM users u
      WHERE $activeWhere
    ''');
    return (r.first['c'] as int?) ?? 0;
  }

  /// 获取某任务的未提交学生列表
  Future<List<Map<String, dynamic>>> getUnsubmittedStudents(int taskId) async {
    final db = await _dbHelper.database;
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    return db.rawQuery('''
      SELECT u.user_id, u.real_name
      FROM users u
      WHERE $activeWhere
        AND u.user_id NOT IN (
          SELECT s.user_id FROM lab_submissions s WHERE s.task_id = ?
        )
      ORDER BY u.user_id
    ''', [taskId]);
  }
}
