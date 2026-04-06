import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../../services/course_resource_service.dart';

/// 实验任务 DAO — 任务发布 / 学生提交 / 评分 / 报告
class LabTaskDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ═══════════ 实验任务 CRUD ═══════════

  Future<List<Map<String, dynamic>>> getTasks({String? chapter, String? status}) async {
    final db = await _dbHelper.database;
    String sql = 'SELECT * FROM lab_tasks WHERE 1=1';
    final args = <dynamic>[];
    if (chapter != null) { sql += ' AND chapter = ?'; args.add(chapter); }
    if (status != null) { sql += ' AND status = ?'; args.add(status); }
    sql += ' ORDER BY created_at DESC';
    return db.rawQuery(sql, args);
  }

  Future<Map<String, dynamic>?> getTask(int id) async {
    final db = await _dbHelper.database;
    final list = await db.query('lab_tasks', where: 'id = ?', whereArgs: [id]);
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

  Future<List<Map<String, dynamic>>> getSubmissions({int? taskId, String? userId}) async {
    final db = await _dbHelper.database;
    String sql = '''
      SELECT s.*, t.title as task_title, t.chapter, t.max_score, t.difficulty
      FROM lab_submissions s
      JOIN lab_tasks t ON t.id = s.task_id
      WHERE 1=1
    ''';
    final args = <dynamic>[];
    if (taskId != null) { sql += ' AND s.task_id = ?'; args.add(taskId); }
    if (userId != null) { sql += ' AND s.user_id = ?'; args.add(userId); }
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
      return db.update('lab_submissions', {
        'content': content,
        'file_paths': filePaths,
        'file_names': fileNames,
        'submit_time': now,
        'status': '已提交',
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [existing['id']]);
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

  Future<int> gradeSubmission(int submissionId, {
    required int score,
    String? feedback,
    String? scorerId,
  }) async {
    final db = await _dbHelper.database;
    return db.update('lab_submissions', {
      'score': score,
      'feedback': feedback,
      'scorer_id': scorerId,
      'scored_at': DateTime.now().toIso8601String(),
      'status': '已批改',
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [submissionId]);
  }

  // ═══════════ 统计 ═══════════

  Future<Map<String, dynamic>> getTaskStats(int taskId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as total_submissions,
        SUM(CASE WHEN score IS NOT NULL THEN 1 ELSE 0 END) as graded_count,
        AVG(score) as avg_score,
        MAX(score) as max_score,
        MIN(score) as min_score
      FROM lab_submissions
      WHERE task_id = ?
    ''', [taskId]);
    return result.isNotEmpty ? result.first : {};
  }

  Future<Map<String, dynamic>> getStudentLabStats(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT s.task_id) as submitted_tasks,
        (SELECT COUNT(*) FROM lab_tasks WHERE status = 'active') as total_tasks,
        AVG(s.score) as avg_score,
        SUM(CASE WHEN s.status = '已批改' THEN 1 ELSE 0 END) as graded_count
      FROM lab_submissions s
      WHERE s.user_id = ?
    ''', [userId]);
    return result.isNotEmpty ? result.first : {};
  }

  // ═══════════ 报告模板 ═══════════

  Future<List<Map<String, dynamic>>> getReportTemplates({String? category}) async {
    final db = await _dbHelper.database;
    String sql = 'SELECT * FROM report_templates WHERE 1=1';
    final args = <dynamic>[];
    if (category != null) { sql += ' AND category = ?'; args.add(category); }
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

  Future<List<Map<String, dynamic>>> getStudentReports({String? userId, int? taskId}) async {
    final db = await _dbHelper.database;
    String sql = '''
      SELECT r.*, t.name as template_name, lt.title as task_title
      FROM student_reports r
      LEFT JOIN report_templates t ON t.id = r.template_id
      LEFT JOIN lab_tasks lt ON lt.id = r.task_id
      WHERE 1=1
    ''';
    final args = <dynamic>[];
    if (userId != null) { sql += ' AND r.user_id = ?'; args.add(userId); }
    if (taskId != null) { sql += ' AND r.task_id = ?'; args.add(taskId); }
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
      return db.update('student_reports', data, where: 'id = ?', whereArgs: [id]);
    } else {
      data['created_at'] = now;
      return db.insert('student_reports', data);
    }
  }

  // ═══════════ 互评 ═══════════

  Future<List<Map<String, dynamic>>> getPeerReviews(int submissionId) async {
    final db = await _dbHelper.database;
    return db.query('peer_reviews',
        where: 'submission_id = ?', whereArgs: [submissionId],
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
    return db.insert('peer_reviews', {
      'submission_id': submissionId,
      'reviewer_id': reviewerId,
      'reviewer_name': reviewerName,
      'score': score,
      'comment': comment,
      'reviewed_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ═══════════ 协作消息 ═══════════

  Future<List<Map<String, dynamic>>> getMessages({int? groupId, int? taskId, int limit = 50}) async {
    final db = await _dbHelper.database;
    String sql = 'SELECT * FROM collaboration_messages WHERE 1=1';
    final args = <dynamic>[];
    if (groupId != null) { sql += ' AND group_id = ?'; args.add(groupId); }
    if (taskId != null) { sql += ' AND task_id = ?'; args.add(taskId); }
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
      final count = await db.rawQuery('SELECT COUNT(*) as c FROM lab_tasks');
      if ((count.first['c'] as int? ?? 0) > 0) return;

      // 1. 尝试从 Gitee 远程获取实验任务定义
      bool remoteDone = false;
      try {
        final resource = CourseResourceService();
        final remoteTasks = await resource.getLabTasks();
        if (remoteTasks != null && remoteTasks.isNotEmpty) {
          await _insertTasksFromRemote(db, remoteTasks);
          remoteDone = true;
          debugPrint('LabTaskDao: Loaded ${remoteTasks.length} tasks from Gitee');
        }
      } catch (e) {
        debugPrint('LabTaskDao: Remote load failed: $e');
      }

      // 2. 远程失败 → 用本地硬编码兜底
      if (!remoteDone) {
        debugPrint('LabTaskDao: Falling back to hardcoded tasks');
        await _insertHardcodedTasks(db);
      }

      // 3. 初始化报告模板（同样优先远程）
      await _initReportTemplates(db);
    } catch (e) {
      // 表可能不存在，静默忽略
      debugPrint('LabTaskDao: initDemoDataIfEmpty error: $e');
    }
  }

  /// 从远程 JSON 插入实验任务
  Future<void> _insertTasksFromRemote(
      Database db, List<Map<String, dynamic>> remoteTasks) async {
    final now = DateTime.now().toIso8601String();
    for (final task in remoteTasks) {
      final dueOffset = task['due_days_offset'] as int? ?? 14;
      await db.insert('lab_tasks', {
        'title': task['title'] ?? '',
        'chapter': task['chapter'] ?? '',
        'description': task['description'] ?? '',
        'requirements': task['requirements'] ?? '',
        'deliverables': task['deliverables'] ?? '',
        'difficulty': task['difficulty'] ?? '中等',
        'max_score': task['max_score'] ?? 100,
        'due_date': DateTime.now()
            .add(Duration(days: dueOffset))
            .toIso8601String(),
        'status': 'active',
        'creator_id': '206004',
        'created_at': now,
        'updated_at': now,
      });
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

  /// 硬编码实验任务（离线兜底）
  Future<void> _insertHardcodedTasks(Database db) async {
    final now = DateTime.now().toIso8601String();
      final tasks = [
        {
          'title': '实验一 开发环境搭建',
          'chapter': '第1章',
          'description': '搭建 Android Studio、Flutter、微信开发者工具、DevEco Studio、HBuilderX（Uniapp）、Visual Studio（MAUI）开发环境，各成员根据分工完成对应平台环境配置并成功运行 Hello World 项目。'
              '\n\n【实验学时】2学时 | 【实验类型】验证型 | 【实验要求】必做 | 【对应课程目标】目标1 | 【分组人数】6人/组',
          'requirements': 'AI新范式开发流程：\n'
              '① 需求分析：明确各平台环境依赖与版本要求；\n'
              '② AI辅助编码：使用 TRAE 生成 Hello World 模板代码；\n'
              '③ 测试验证：在模拟器/真机上验证项目运行；\n'
              '④ 部署运维：记录环境配置文档，总结常见问题与解决方案。',
          'deliverables': '各平台Hello World运行截图、环境配置文档、常见问题解决方案、实验报告',
          'difficulty': '简单',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 14)).toIso8601String(),
        },
        {
          'title': '实验二 原生应用开发',
          'chapter': '第2章',
          'description': 'Android方向：使用 Kotlin 实现"智慧校园"登录页面（EditText输入验证、Activity跳转与数据传递）。'
              'iOS方向（演示/模拟器）：使用 SwiftUI 实现登录页面，理解 ViewController 生命周期。'
              '组内每人选择不同平台或技术方案实现同一功能，完成后进行组内技术对比分享。'
              '\n\n【实验学时】4学时 | 【实验类型】验证型 | 【实验要求】必做 | 【对应课程目标】目标1 | 【分组人数】6人/组',
          'requirements': 'AI新范式开发流程：\n'
              '① 需求分析：编写登录功能需求文档（输入验证规则、页面跳转逻辑）；\n'
              '② AI辅助编码：使用 TRAE 生成登录页面骨架代码并手动完善业务逻辑；\n'
              '③ 测试验证：编写输入验证测试用例，验证边界条件；\n'
              '④ 部署运维：打包调试版本，记录平台差异对比报告。',
          'deliverables': '登录页面运行截图及录屏、输入验证测试报告、平台差异对比分析报告、实验报告',
          'difficulty': '中等',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 21)).toIso8601String(),
        },
        {
          'title': '实验三 跨平台应用开发',
          'chapter': '第3章',
          'description': '开发"智慧校园"业务数据列表页（RESTful API 网络数据请求 + JSON 解析 + 下拉刷新），'
              '组内成员分别使用 Flutter（Dart）、React Native（JSX）、Uniapp（Vue）、MAUI（C#）等不同框架实现同一功能需求。'
              '扩展案例：集成设备传感器（如GPS定位、加速度计），体验移动硬件能力调用。'
              '\n\n【实验学时】4学时 | 【实验类型】验证型 | 【实验要求】必做 | 【对应课程目标】目标2 | 【分组人数】6人/组',
          'requirements': 'AI新范式开发流程：\n'
              '① 需求分析：定义列表页数据结构、API接口规范与传感器调用需求；\n'
              '② AI辅助编码：使用 TRAE 生成网络请求与JSON解析代码，辅助生成传感器调用模板；\n'
              '③ 测试验证：模拟API异常响应测试容错能力，验证传感器数据采集准确性；\n'
              '④ 部署运维：多框架性能对比测试，输出框架适用性分析报告。',
          'deliverables': '列表页运行截图及录屏、API交互测试报告、多框架性能对比报告、实验报告',
          'difficulty': '中等',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 28)).toIso8601String(),
        },
        {
          'title': '实验四 微信小程序开发',
          'chapter': '第4章',
          'description': '借助 AI 编程工具辅助开发"智慧校园通知"小程序（列表 + 详情页路由 + 本地存储），'
              '体验 AI 工具在代码生成与调试中的作用。'
              '\n\n【实验学时】4学时 | 【实验类型】验证型 | 【实验要求】必做 | 【对应课程目标】目标2 | 【分组人数】6人/组',
          'requirements': 'AI新范式开发流程：\n'
              '① 需求分析：绘制小程序页面流程图与数据模型；\n'
              '② AI辅助编码：使用 TRAE 生成小程序页面代码与数据绑定逻辑；\n'
              '③ 测试验证：使用微信开发者工具进行真机预览与功能测试；\n'
              '④ 部署运维：体验小程序审核与发布流程（体验版）。',
          'deliverables': '小程序预览码截图、页面流程图、功能测试报告、实验报告',
          'difficulty': '中等',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 35)).toIso8601String(),
        },
        {
          'title': '实验五 鸿蒙多端应用开发',
          'chapter': '第5章',
          'description': '使用 DevEco Studio 开发"智慧天气"应用，实现手机/平板界面自适应布局；'
              '通过模拟器演示分布式数据同步原理。'
              '扩展案例：调用设备传感器（如光线传感器、陀螺仪）实现简单的物联网数据采集与展示场景。'
              '\n\n【实验学时】4学时 | 【实验类型】验证型 | 【实验要求】必做 | 【对应课程目标】目标3 | 【分组人数】6人/组',
          'requirements': 'AI新范式开发流程：\n'
              '① 需求分析：定义天气应用功能需求与多端适配策略，明确传感器数据采集需求；\n'
              '② AI辅助编码：使用 TRAE 辅助生成 ArkUI 页面布局与传感器调用代码；\n'
              '③ 测试验证：在不同设备模拟器上验证UI适配效果与传感器数据准确性；\n'
              '④ 部署运维：编写多端适配与硬件集成技术分析报告。',
          'deliverables': '天气应用运行截图（手机+平板）、多端适配效果对比截图、技术分析报告、实验报告',
          'difficulty': '较难',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 42)).toIso8601String(),
        },
        {
          'title': '实验六 跨平台综合项目实战',
          'chapter': '第6章',
          'description': '团队开发"智慧健康"等业务应用（建议选题涉及传感器或硬件交互场景），'
              '每人负责一个技术栈（Android/Flutter/React Native/Uniapp/MAUI/微信小程序），'
              '使用 Git 进行版本控制与协作，借助 AI 编程工具辅助代码生成与调试。'
              '每组6人，实验中每人选择一个技术栈独立完成对应实验任务，组内进行技术分享与对比分析。'
              '\n\n【实验学时】6学时 | 【实验类型】综合型 | 【实验要求】必做 | 【对应课程目标】目标1-4 | 【分组人数】6人/组',
          'requirements': 'AI新范式开发流程：\n'
              '① 需求分析：团队协作完成项目需求文档与技术选型方案；\n'
              '② AI辅助编码：各成员使用 TRAE 辅助各技术栈端的代码开发；\n'
              '③ 测试验证：制定测试计划，进行功能测试与跨端兼容性测试；\n'
              '④ 部署运维：完成多端应用打包部署，撰写技术选型对比报告与项目总结。',
          'deliverables': '可运行的多端应用安装包、Git仓库地址、技术选型对比报告、答辩PPT、演示视频、项目总结报告',
          'difficulty': '较难',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 56)).toIso8601String(),
        },
      ];

      for (final task in tasks) {
        await db.insert('lab_tasks', {
          ...task,
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
}
