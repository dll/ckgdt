import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

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

  // ═══════════ 初始化示例数据 ═══════════

  Future<void> initDemoDataIfEmpty() async {
    final db = await _dbHelper.database;
    try {
      final count = await db.rawQuery('SELECT COUNT(*) as c FROM lab_tasks');
      if ((count.first['c'] as int? ?? 0) > 0) return;

      final now = DateTime.now().toIso8601String();
      final tasks = [
        {
          'title': '实验一：Flutter 开发环境搭建与 Hello World',
          'chapter': '第1章',
          'description': '搭建 Flutter 开发环境，创建第一个 Flutter 应用并运行在模拟器上。',
          'requirements': '1. 安装 Flutter SDK 和 Android Studio\n2. 配置环境变量\n3. 创建 Flutter 项目\n4. 修改首页显示个人信息\n5. 在模拟器或真机上运行',
          'deliverables': '运行截图、项目源码压缩包、实验报告',
          'difficulty': '简单',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 14)).toIso8601String(),
        },
        {
          'title': '实验二：Android 原生 Activity 与布局',
          'chapter': '第2章',
          'description': '使用 Android Studio 创建原生应用，掌握 Activity 生命周期和常用布局。',
          'requirements': '1. 创建多个 Activity 并实现跳转\n2. 使用 LinearLayout 和 ConstraintLayout\n3. 实现一个简单的登录界面\n4. 使用 Intent 传递数据',
          'deliverables': 'APK文件、源码、实验报告',
          'difficulty': '中等',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 21)).toIso8601String(),
        },
        {
          'title': '实验三：Flutter 状态管理与网络请求',
          'chapter': '第3章',
          'description': '学习 Flutter 状态管理方案，实现一个带网络请求的应用。',
          'requirements': '1. 使用 StatefulWidget 管理状态\n2. 实现列表页和详情页\n3. 使用 http 包发起网络请求\n4. 解析 JSON 数据并展示\n5. 添加下拉刷新和加载更多',
          'deliverables': '运行截图、源码、实验报告、演示视频(可选)',
          'difficulty': '中等',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 28)).toIso8601String(),
        },
        {
          'title': '实验四：微信小程序开发',
          'chapter': '第4章',
          'description': '使用微信开发者工具创建小程序，实现基本的页面导航和数据绑定。',
          'requirements': '1. 注册小程序账号（测试号）\n2. 创建至少 3 个页面\n3. 实现 tabBar 底部导航\n4. 使用 wx:for 渲染列表\n5. 实现本地存储功能',
          'deliverables': '小程序预览码截图、源码、实验报告',
          'difficulty': '中等',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 35)).toIso8601String(),
        },
        {
          'title': '实验五：HarmonyOS 应用开发',
          'chapter': '第5章',
          'description': '使用 DevEco Studio 创建 HarmonyOS 应用，掌握 ArkUI 开发。',
          'requirements': '1. 安装 DevEco Studio\n2. 创建 HarmonyOS 项目\n3. 使用 ArkTS 编写 UI\n4. 实现页面路由\n5. 使用 Preferences 存储数据',
          'deliverables': '运行截图、源码、实验报告',
          'difficulty': '较难',
          'max_score': 100,
          'due_date': DateTime.now().add(const Duration(days: 42)).toIso8601String(),
        },
        {
          'title': '综合实验：跨平台移动应用开发',
          'chapter': '第6章',
          'description': '综合运用所学技术，自选主题开发一个完整的移动应用。',
          'requirements': '1. 选择至少一种跨平台框架（Flutter/RN/小程序）\n2. 完成需求分析和设计文档\n3. 实现至少 5 个功能页面\n4. 包含数据持久化\n5. 进行组内答辩展示',
          'deliverables': 'APK/安装包、源码、设计文档、答辩PPT、演示视频',
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

      // 插入默认报告模板
      await _initDefaultReportTemplates(db);
    } catch (e) {
      // 表可能不存在，静默忽略
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
