import 'package:sqflite/sqflite.dart';
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
        'title': '移动应用开发技术体系全景',
        'description': '介绍移动应用开发的技术全景，包括原生、混合、跨平台开发模式',
        'objectives': '了解移动开发技术栈；掌握各平台特点；理解技术选型策略',
        'hours': 4,
        'week_start': 1,
        'week_end': 2,
      },
      {
        'chapter_number': 2,
        'title': 'Android 与 iOS 原生开发基础',
        'description': 'Android Studio + Kotlin/Java 开发，Xcode + Swift 开发基础',
        'objectives': '掌握 Android 开发环境搭建；理解 Activity/Fragment 生命周期；了解 iOS 开发基础',
        'hours': 6,
        'week_start': 3,
        'week_end': 5,
      },
      {
        'chapter_number': 3,
        'title': 'Flutter、React Native 等混合开发技术',
        'description': 'Flutter Dart 语言、Widget 体系、状态管理；React Native 简介',
        'objectives': '掌握 Flutter 开发基础；理解 Widget 树与状态管理；能创建跨平台应用',
        'hours': 8,
        'week_start': 6,
        'week_end': 9,
      },
      {
        'chapter_number': 4,
        'title': '微信小程序开发流程',
        'description': 'WXML/WXSS/JS 语法、组件化、云开发基础',
        'objectives': '掌握小程序开发工具链；理解小程序架构；能独立开发小程序',
        'hours': 4,
        'week_start': 10,
        'week_end': 11,
      },
      {
        'chapter_number': 5,
        'title': '华为 HarmonyOS 多端应用开发',
        'description': 'ArkTS/ArkUI 开发、分布式能力、多设备协同',
        'objectives': '了解鸿蒙开发生态；掌握 ArkTS 基础语法；理解分布式架构',
        'hours': 4,
        'week_start': 12,
        'week_end': 13,
      },
      {
        'chapter_number': 6,
        'title': '综合开发实践',
        'description': '团队协作、项目管理、综合应用开发与作品展示',
        'objectives': '综合运用所学技术；完成团队项目；掌握项目管理方法',
        'hours': 6,
        'week_start': 14,
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
    // 假设学期从 9月1日开始（秋季学期）
    final now = DateTime.now();
    final year = now.month >= 8 ? now.year : now.year;
    final semesterStart = DateTime(year, 9, 1);
    final targetDate = semesterStart.add(Duration(days: (week - 1) * 7));
    return '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
  }
}
