import 'database_helper.dart';

/// 教学管理 DAO — 课程大纲 / 教案 / 教学进度
class TeachingDao {
  // ═══════════════════════════════════════════════════════════════════════════
  // 课程大纲 CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// 获取所有大纲条目（按章节号排序）
  Future<List<Map<String, dynamic>>> getAllSyllabusItems() async {
    final db = await DatabaseHelper.instance.database;
    return db.query('syllabus_items', orderBy: 'chapter_number ASC');
  }

  /// 获取单个大纲条目
  Future<Map<String, dynamic>?> getSyllabusItem(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list = await db.query('syllabus_items', where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 新增大纲条目
  Future<int> addSyllabusItem(Map<String, dynamic> item) async {
    final db = await DatabaseHelper.instance.database;
    item['created_at'] = DateTime.now().toIso8601String();
    item['updated_at'] = DateTime.now().toIso8601String();
    return db.insert('syllabus_items', item);
  }

  /// 更新大纲条目
  Future<int> updateSyllabusItem(int id, Map<String, dynamic> item) async {
    final db = await DatabaseHelper.instance.database;
    item['updated_at'] = DateTime.now().toIso8601String();
    return db.update('syllabus_items', item, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除大纲条目
  Future<int> deleteSyllabusItem(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('syllabus_items', where: 'id = ?', whereArgs: [id]);
  }

  /// 更新大纲状态
  Future<int> updateSyllabusStatus(int id, String status) async {
    final db = await DatabaseHelper.instance.database;
    return db.update(
      'syllabus_items',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取大纲统计
  Future<Map<String, int>> getSyllabusStats() async {
    final db = await DatabaseHelper.instance.database;
    final total = await db.rawQuery('SELECT COUNT(*) as c FROM syllabus_items');
    final planned = await db.rawQuery(
        "SELECT COUNT(*) as c FROM syllabus_items WHERE status='planned'");
    final inProgress = await db.rawQuery(
        "SELECT COUNT(*) as c FROM syllabus_items WHERE status='in_progress'");
    final completed = await db.rawQuery(
        "SELECT COUNT(*) as c FROM syllabus_items WHERE status='completed'");
    return {
      'total': (total.first['c'] as int?) ?? 0,
      'planned': (planned.first['c'] as int?) ?? 0,
      'in_progress': (inProgress.first['c'] as int?) ?? 0,
      'completed': (completed.first['c'] as int?) ?? 0,
    };
  }

  /// 初始化默认大纲（6章）
  Future<void> initDefaultSyllabus() async {
    final db = await DatabaseHelper.instance.database;
    final count = await db.rawQuery('SELECT COUNT(*) as c FROM syllabus_items');
    if (((count.first['c'] as int?) ?? 0) > 0) return;

    final chapters = [
      {
        'chapter_number': 1,
        'title': '移动应用开发技术体系',
        'description': '移动应用分类（原生/混合/小程序/多端）、主流开发平台对比、技术选型方法论、AI编程工具在移动开发中的应用',
        'objectives': '目标1：掌握移动应用开发技术体系及主流平台特性，理解技术选型逻辑',
        'hours': 8,
        'week_start': 1,
        'week_end': 2,
      },
      {
        'chapter_number': 2,
        'title': '原生开发基础',
        'description': 'Android开发（Kotlin语言基础、Activity生命周期、UI控件与Logcat调试）；iOS开发概述（ViewController架构、SwiftUI基础）',
        'objectives': '目标1：掌握Android/iOS原生开发环境搭建与基础编程',
        'hours': 8,
        'week_start': 3,
        'week_end': 4,
      },
      {
        'chapter_number': 3,
        'title': '跨平台应用开发',
        'description': 'Flutter框架（Dart语法、Widget组件）、React Native（JSX语法）、Uniapp（Vue语法）、MAUI（C#跨平台）；后端交互（RESTful API、JSON解析）',
        'objectives': '目标2：运用跨平台开发框架，结合AI编程工具与后端API交互，设计实现跨平台应用',
        'hours': 8,
        'week_start': 5,
        'week_end': 6,
      },
      {
        'chapter_number': 4,
        'title': '微信小程序开发',
        'description': 'MINA框架、WXML/WXSS语法、生命周期与页面路由、小程序云开发、Taro跨平台框架',
        'objectives': '目标2：掌握小程序开发技术，具备需求建模与创新应用能力',
        'hours': 8,
        'week_start': 7,
        'week_end': 8,
      },
      {
        'chapter_number': 5,
        'title': '鸿蒙多端应用开发',
        'description': 'HarmonyOS NEXT架构、ArkUI框架（ArkTS声明式UI）、多端部署与自适应布局、分布式能力与物联网扩展',
        'objectives': '目标3：调研对比多端开发方案，分析不同技术栈优劣，具备技术方案评估与选型能力',
        'hours': 8,
        'week_start': 9,
        'week_end': 10,
      },
      {
        'chapter_number': 6,
        'title': '综合开发实践',
        'description': '项目架构设计（MVP/MVVM模式）、数据存储方案、Git版本控制、性能优化、AI工具深度应用、代码重构与测试',
        'objectives': '目标4：遵循软件工程规范，使用现代开发工具完成应用测试与优化，具备工程实践能力',
        'hours': 16,
        'week_start': 11,
        'week_end': 16,
      },
    ];

    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final ch in chapters) {
      batch.insert('syllabus_items', {
        ...ch,
        'course_name': '移动应用开发',
        'status': 'planned',
        'created_at': now,
        'updated_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 初始化默认教案（理论12讲 + 实验6个）
  Future<void> initDefaultLessonPlans() async {
    final db = await DatabaseHelper.instance.database;

    // Ensure plan_type and hours columns exist
    try {
      await db.rawQuery('SELECT plan_type FROM lesson_plans LIMIT 1');
    } catch (_) {
      try { await db.execute('ALTER TABLE lesson_plans ADD COLUMN plan_type TEXT DEFAULT \'theory\''); } catch (_) {}
    }
    try {
      await db.rawQuery('SELECT hours FROM lesson_plans LIMIT 1');
    } catch (_) {
      try { await db.execute('ALTER TABLE lesson_plans ADD COLUMN hours INTEGER DEFAULT 2'); } catch (_) {}
    }

    final count = await db.rawQuery('SELECT COUNT(*) as c FROM lesson_plans');
    if (((count.first['c'] as int?) ?? 0) > 0) return;

    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    // 理论教案 12 讲（每章2讲）
    final theoryLessons = [
      {'chapter': 1, 'title': '第一章 移动应用开发技术体系(1)', 'objectives': '移动应用分类：原生应用、混合应用、小程序、多端应用；主流开发平台对比', 'key_points': '移动应用分类标准；Android/iOS/小程序/鸿蒙平台特性', 'difficult_points': '技术选型方法论', 'content': '介绍移动应用开发的技术全景，对比各平台特点', 'homework': '调研主流移动应用开发平台'},
      {'chapter': 1, 'title': '第一章 移动应用开发技术体系(2)', 'objectives': '技术选型方法论；跨平台技术路线对比；AI编程工具应用', 'key_points': '跨平台技术路线；AI辅助编程', 'difficult_points': '技术选型决策', 'content': '深入分析跨平台技术路线，介绍AI编程工具', 'homework': '完成开发环境搭建报告'},
      {'chapter': 2, 'title': '第二章 原生开发基础(1)', 'objectives': 'Android开发：Kotlin语言基础、Activity生命周期、UI控件与Logcat调试', 'key_points': 'Kotlin语法基础；Activity生命周期', 'difficult_points': 'Activity状态管理', 'content': 'Android Studio开发环境，Kotlin语言入门', 'homework': 'Android登录页面实现'},
      {'chapter': 2, 'title': '第二章 原生开发基础(2)', 'objectives': 'iOS开发概述；ViewController架构；SwiftUI基础', 'key_points': 'ViewController架构；SwiftUI声明式语法', 'difficult_points': 'iOS与Android开发模式对比', 'content': 'iOS开发基础，Xcode使用，SwiftUI入门', 'homework': 'iOS登录页面实现'},
      {'chapter': 3, 'title': '第三章 跨平台应用开发(1)', 'objectives': 'Flutter框架：Dart语法、Widget组件；React Native：JSX语法；Uniapp：Vue语法；MAUI：C#跨平台', 'key_points': 'Flutter Widget组件体系；Dart语言核心语法', 'difficult_points': '声明式UI与命令式UI的思维转换', 'content': '四大跨平台框架对比教学', 'homework': '跨平台列表页实现'},
      {'chapter': 3, 'title': '第三章 跨平台应用开发(2)', 'objectives': '后端交互：RESTful API、JSON解析；移动硬件能力调用', 'key_points': 'HTTP请求与JSON解析；移动设备API调用', 'difficult_points': '异步编程与状态管理', 'content': '后端API交互，硬件能力调用，AI辅助开发', 'homework': 'API交互功能实现'},
      {'chapter': 4, 'title': '第四章 微信小程序开发(1)', 'objectives': 'MINA框架、WXML/WXSS语法、生命周期与页面路由', 'key_points': '小程序框架结构；WXML模板语法', 'difficult_points': '小程序与Web开发的差异', 'content': '微信小程序开发基础，开发者工具使用', 'homework': '小程序列表页实现'},
      {'chapter': 4, 'title': '第四章 微信小程序开发(2)', 'objectives': '小程序云开发；Taro跨平台框架；AI工具辅助', 'key_points': '云开发数据库与存储；Taro多端适配', 'difficult_points': '云函数与数据安全', 'content': '小程序云开发，跨平台适配', 'homework': '小程序完整功能实现'},
      {'chapter': 5, 'title': '第五章 鸿蒙多端应用开发(1)', 'objectives': 'HarmonyOS NEXT架构；ArkUI框架：ArkTS声明式UI；多端部署', 'key_points': 'ArkTS语法；ArkUI组件', 'difficult_points': '鸿蒙与Android开发思维差异', 'content': '鸿蒙开发环境搭建，ArkTS语言入门', 'homework': '鸿蒙应用页面实现'},
      {'chapter': 5, 'title': '第五章 鸿蒙多端应用开发(2)', 'objectives': '分布式能力原理；物联网扩展；传感器数据采集', 'key_points': '分布式软总线；设备协同', 'difficult_points': '分布式数据管理', 'content': '鸿蒙分布式能力，多端适配实战', 'homework': '鸿蒙多端适配实现'},
      {'chapter': 6, 'title': '第六章 综合开发实践(1)', 'objectives': '项目架构设计（MVP/MVVM模式）；数据存储方案；Git版本控制', 'key_points': 'MVVM架构模式；Git基本操作', 'difficult_points': '架构设计决策', 'content': '项目架构设计，Git团队协作', 'homework': '项目需求文档撰写'},
      {'chapter': 6, 'title': '第六章 综合开发实践(2)', 'objectives': '性能优化；代码审查；AI工具深度应用；项目测试', 'key_points': '性能优化策略；代码审查规范', 'difficult_points': '性能瓶颈分析', 'content': '项目优化，AI辅助，测试与调试', 'homework': '项目核心功能开发'},
    ];

    for (final lesson in theoryLessons) {
      batch.insert('lesson_plans', {
        ...lesson,
        'plan_type': 'theory',
        'status': 'ready',
        'ai_generated': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    // 实验教案 6 个
    final experimentLessons = [
      {'chapter': 1, 'title': '实验一 开发环境搭建', 'objectives': '搭建Android/iOS/Flutter等开发环境', 'key_points': '各平台SDK安装与配置', 'difficult_points': '环境兼容性问题排查', 'content': '完成至少一个移动开发平台的环境搭建，运行Hello World程序', 'homework': '提交环境搭建截图与报告', 'hours': 2},
      {'chapter': 2, 'title': '实验二 原生应用开发', 'objectives': '开发Android/iOS原生应用', 'key_points': 'Activity/ViewController使用；UI布局', 'difficult_points': '原生API调用与调试', 'content': '实现登录页面（含输入验证、页面跳转）', 'homework': '提交完整项目代码', 'hours': 4},
      {'chapter': 3, 'title': '实验三 跨平台应用开发', 'objectives': '使用跨平台框架开发应用', 'key_points': '框架组件使用；API交互', 'difficult_points': '平台差异适配', 'content': '使用Flutter/RN/Uniapp/MAUI之一实现列表+详情功能', 'homework': '提交项目代码与技术对比报告', 'hours': 4},
      {'chapter': 4, 'title': '实验四 微信小程序开发', 'objectives': '开发微信小程序', 'key_points': '小程序组件与云开发', 'difficult_points': '小程序审核与发布流程', 'content': '实现一个完整的微信小程序（含云数据库）', 'homework': '提交小程序代码与功能演示', 'hours': 4},
      {'chapter': 5, 'title': '实验五 鸿蒙多端应用开发', 'objectives': '开发鸿蒙多端应用', 'key_points': 'ArkUI组件；多端适配', 'difficult_points': '分布式能力开发', 'content': '使用DevEco Studio开发鸿蒙应用', 'homework': '提交鸿蒙应用与多端适配报告', 'hours': 4},
      {'chapter': 6, 'title': '实验六 跨平台综合项目实战', 'objectives': '团队协作完成综合项目', 'key_points': 'Git协作；项目管理；功能集成', 'difficult_points': '团队分工与代码合并', 'content': '6人一组，每人选择一个技术栈，完成综合项目开发', 'homework': '提交团队项目代码、文档与演示视频', 'hours': 6},
    ];

    for (final lesson in experimentLessons) {
      batch.insert('lesson_plans', {
        ...lesson,
        'plan_type': 'experiment',
        'status': 'ready',
        'ai_generated': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    await batch.commit(noResult: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 教案 CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// 获取所有教案（按章节排序）
  Future<List<Map<String, dynamic>>> getAllLessonPlans() async {
    final db = await DatabaseHelper.instance.database;
    return db.query('lesson_plans', orderBy: 'chapter ASC, id ASC');
  }

  /// 按章节获取教案
  Future<List<Map<String, dynamic>>> getLessonPlansByChapter(int chapter) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('lesson_plans',
        where: 'chapter = ?', whereArgs: [chapter], orderBy: 'id ASC');
  }

  /// 获取单个教案
  Future<Map<String, dynamic>?> getLessonPlan(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list = await db.query('lesson_plans', where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 新增教案
  Future<int> addLessonPlan(Map<String, dynamic> plan) async {
    final db = await DatabaseHelper.instance.database;
    plan['created_at'] = DateTime.now().toIso8601String();
    plan['updated_at'] = DateTime.now().toIso8601String();
    return db.insert('lesson_plans', plan);
  }

  /// 更新教案
  Future<int> updateLessonPlan(int id, Map<String, dynamic> plan) async {
    final db = await DatabaseHelper.instance.database;
    plan['updated_at'] = DateTime.now().toIso8601String();
    return db.update('lesson_plans', plan, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除教案
  Future<int> deleteLessonPlan(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('lesson_plans', where: 'id = ?', whereArgs: [id]);
  }

  /// 更新教案状态
  Future<int> updateLessonPlanStatus(int id, String status) async {
    final db = await DatabaseHelper.instance.database;
    return db.update(
      'lesson_plans',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取教案统计
  Future<Map<String, int>> getLessonPlanStats() async {
    final db = await DatabaseHelper.instance.database;
    final total = await db.rawQuery('SELECT COUNT(*) as c FROM lesson_plans');
    final draft = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lesson_plans WHERE status='draft'");
    final ready = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lesson_plans WHERE status='ready'");
    final used = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lesson_plans WHERE status='used'");
    final aiCount = await db.rawQuery(
        "SELECT COUNT(*) as c FROM lesson_plans WHERE ai_generated=1");
    return {
      'total': (total.first['c'] as int?) ?? 0,
      'draft': (draft.first['c'] as int?) ?? 0,
      'ready': (ready.first['c'] as int?) ?? 0,
      'used': (used.first['c'] as int?) ?? 0,
      'ai_generated': (aiCount.first['c'] as int?) ?? 0,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 教学进度 CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// 获取所有教学进度（按计划日期排序）
  Future<List<Map<String, dynamic>>> getAllTeachingProgress() async {
    final db = await DatabaseHelper.instance.database;
    return db.query('teaching_progress', orderBy: 'chapter ASC, planned_date ASC');
  }

  /// 按班级获取教学进度
  Future<List<Map<String, dynamic>>> getProgressByClass(int classId) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('teaching_progress',
        where: 'class_id = ?',
        whereArgs: [classId],
        orderBy: 'chapter ASC, planned_date ASC');
  }

  /// 获取单个进度记录
  Future<Map<String, dynamic>?> getTeachingProgressItem(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list = await db.query('teaching_progress', where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 新增教学进度
  Future<int> addTeachingProgress(Map<String, dynamic> progress) async {
    final db = await DatabaseHelper.instance.database;
    progress['created_at'] = DateTime.now().toIso8601String();
    progress['updated_at'] = DateTime.now().toIso8601String();
    return db.insert('teaching_progress', progress);
  }

  /// 更新教学进度
  Future<int> updateTeachingProgress(int id, Map<String, dynamic> progress) async {
    final db = await DatabaseHelper.instance.database;
    progress['updated_at'] = DateTime.now().toIso8601String();
    return db.update('teaching_progress', progress, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除教学进度
  Future<int> deleteTeachingProgress(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('teaching_progress', where: 'id = ?', whereArgs: [id]);
  }

  /// 更新进度状态（含实际日期）
  Future<int> markProgressCompleted(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.update(
      'teaching_progress',
      {
        'status': 'completed',
        'actual_date': DateTime.now().toIso8601String().split('T').first,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取教学进度统计
  Future<Map<String, dynamic>> getProgressStats() async {
    final db = await DatabaseHelper.instance.database;
    final total = await db.rawQuery('SELECT COUNT(*) as c FROM teaching_progress');
    final planned = await db.rawQuery(
        "SELECT COUNT(*) as c FROM teaching_progress WHERE status='planned'");
    final inProgress = await db.rawQuery(
        "SELECT COUNT(*) as c FROM teaching_progress WHERE status='in_progress'");
    final completed = await db.rawQuery(
        "SELECT COUNT(*) as c FROM teaching_progress WHERE status='completed'");
    final totalCount = (total.first['c'] as int?) ?? 0;
    final completedCount = (completed.first['c'] as int?) ?? 0;
    return {
      'total': totalCount,
      'planned': (planned.first['c'] as int?) ?? 0,
      'in_progress': (inProgress.first['c'] as int?) ?? 0,
      'completed': completedCount,
      'progress_rate': totalCount > 0
          ? (completedCount / totalCount * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  /// 根据大纲自动生成教学进度计划
  Future<int> generateProgressFromSyllabus({int? classId, String? teacherId}) async {
    final db = await DatabaseHelper.instance.database;
    final items = await getAllSyllabusItems();
    if (items.isEmpty) return 0;

    int count = 0;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final item in items) {
      final chNum = item['chapter_number'] as int;
      final weekStart = item['week_start'] as int? ?? chNum * 2;
      batch.insert('teaching_progress', {
        'class_id': classId,
        'chapter': chNum,
        'topic': item['title'],
        'planned_date': _weekToDate(weekStart),
        'status': 'planned',
        'teacher_id': teacherId,
        'created_at': now,
        'updated_at': now,
      });
      count++;
    }
    await batch.commit(noResult: true);
    return count;
  }

  /// 将教学周转换为大致日期（以学期第1周为基准）
  String _weekToDate(int week) {
    // 春季学期从3月2日开始 (2025-2026学年第二学期)
    final semesterStart = DateTime(2026, 3, 2);
    final targetDate = semesterStart.add(Duration(days: (week - 1) * 7));
    return '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
  }
}
