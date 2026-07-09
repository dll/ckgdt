import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';
import '../../services/course_context_service.dart';

/// 教学管理 DAO — 课程大纲 / 教案 / 教学进度
class TeachingDao {
  final _courseContext = CourseContextService();

  /// 获取当前课程过滤条件
  Future<({String where, List<Object?> args})> _courseFilter() async {
    final course = await _courseContext.getActiveCourse();
    final courseId = course.id.trim();
    final courseName = course.name.trim();
    final keys = <String>{
      if (courseName.isNotEmpty) courseName,
      if (courseId.isNotEmpty) courseId,
    }.toList();
    if (keys.isEmpty) return (where: '1 = 0', args: const []);
    return (
      where: 'course_name IN (${List.filled(keys.length, '?').join(', ')})',
      args: keys,
    );
  }

  Future<String> _activeCourseName() async {
    final course = await _courseContext.getActiveCourse();
    final name = course.name.trim();
    return name.isNotEmpty ? name : course.id;
  }

  Future<void> _ensureTeachingColumns() async {
    final db = await DatabaseHelper.instance.database;
    Future<void> addColumn(String table, String column, String ddl) async {
      try {
        await db.rawQuery('SELECT $column FROM $table LIMIT 1');
      } catch (e) {
        swallow(e, tag: 'TeachingDao.ensure.$table.$column');
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN $ddl');
        } catch (e2, st) {
          swallowDebug(e2,
              tag: 'TeachingDao.ensure.add_$table.$column', stack: st);
        }
      }
    }

    await addColumn('lesson_plans', 'course_name', 'course_name TEXT');
    await addColumn(
        'lesson_plans', 'plan_type', "plan_type TEXT DEFAULT 'theory'");
    await addColumn('lesson_plans', 'hours', 'hours INTEGER DEFAULT 2');
    await addColumn('teaching_progress', 'course_name', 'course_name TEXT');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 课程大纲 CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// 获取所有大纲条目（按章节号排序）
  Future<List<Map<String, dynamic>>> getAllSyllabusItems() async {
    final db = await DatabaseHelper.instance.database;
    final filter = await _courseFilter();
    return db.query('syllabus_items',
        where: filter.where,
        whereArgs: filter.args,
        orderBy: 'chapter_number ASC');
  }

  /// 获取单个大纲条目
  Future<Map<String, dynamic>?> getSyllabusItem(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list =
        await db.query('syllabus_items', where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 新增大纲条目
  Future<int> addSyllabusItem(Map<String, dynamic> item) async {
    final db = await DatabaseHelper.instance.database;
    item['course_name'] ??= await _activeCourseName();
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
    final filter = await _courseFilter();
    Future<int> count([String? status]) async {
      final where =
          status == null ? filter.where : '${filter.where} AND status = ?';
      final args = status == null ? filter.args : [...filter.args, status];
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM syllabus_items WHERE $where',
        args,
      );
      return (rows.first['c'] as int?) ?? 0;
    }

    return {
      'total': await count(),
      'planned': await count('planned'),
      'in_progress': await count('in_progress'),
      'completed': await count('completed'),
    };
  }

  /// 初始化默认大纲（从当前课程动态生成）
  Future<void> initDefaultSyllabus(
      {String? courseId, String? courseName}) async {
    final db = await DatabaseHelper.instance.database;
    courseId ??= await _resolveActiveCourseId(db);
    courseName ??= await _resolveActiveCourseName(db, courseId);

    final count = await db.rawQuery(
      'SELECT COUNT(*) as c FROM syllabus_items WHERE course_name IN (?, ?)',
      [courseName, courseId],
    );
    if (((count.first['c'] as int?) ?? 0) > 0) return;

    final chapters = await _getCourseChapters(db, courseId);

    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (var i = 0; i < chapters.length; i++) {
      final chapterNo = i + 1;
      batch.insert(
          'syllabus_items',
          {
            'course_name': courseName,
            'chapter_number': chapterNo,
            'title': chapters[i],
            'hours': chapterNo == chapters.length ? 16 : 8,
            'week_start': (chapterNo - 1) * 2 + 1,
            'week_end': chapterNo == chapters.length
                ? chapterNo * 2 + 4
                : chapterNo * 2,
            'status': 'planned',
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// 初始化默认教案（从当前课程动态生成）
  Future<void> initDefaultLessonPlans({String? courseName}) async {
    final db = await DatabaseHelper.instance.database;

    await _ensureTeachingColumns();

    final courseResult =
        await db.rawQuery('SELECT * FROM courses WHERE is_active = 1 LIMIT 1');
    if (courseResult.isEmpty) return;

    final courseId = courseResult.first['id'] as String;
    courseName ??= await _resolveActiveCourseName(db, courseId);
    final count = await db.rawQuery(
      'SELECT COUNT(*) as c FROM lesson_plans WHERE course_name IN (?, ?)',
      [courseName, courseId],
    );
    if (((count.first['c'] as int?) ?? 0) > 0) return;
    final chapters = await _getCourseChapters(db, courseId);

    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    for (var i = 0; i < chapters.length; i++) {
      final chapterNo = i + 1;
      final chapterTitle = chapters[i];

      batch.insert(
          'lesson_plans',
          {
            'course_name': courseName,
            'chapter': chapterNo,
            'title': '第${_toChineseNumber(chapterNo)}章 $chapterTitle(1)',
            'objectives': '掌握$chapterTitle核心知识（上）',
            'key_points': '$chapterTitle基础概念与技术要点',
            'difficult_points': '$chapterTitle重难点分析',
            'content': '讲授$chapterTitle第一部分',
            'homework': '$chapterTitle相关实践练习（上）',
            'plan_type': 'theory',
            'status': 'ready',
            'ai_generated': 0,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      batch.insert(
          'lesson_plans',
          {
            'course_name': courseName,
            'chapter': chapterNo,
            'title': '第${_toChineseNumber(chapterNo)}章 $chapterTitle(2)',
            'objectives': '掌握$chapterTitle核心知识（下）',
            'key_points': '$chapterTitle进阶技术与综合应用',
            'difficult_points': '$chapterTitle进阶难点解析',
            'content': '讲授$chapterTitle第二部分',
            'homework': '$chapterTitle相关实践练习（下）',
            'plan_type': 'theory',
            'status': 'ready',
            'ai_generated': 0,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      batch.insert(
          'lesson_plans',
          {
            'course_name': courseName,
            'chapter': chapterNo,
            'title': '第${_toChineseNumber(chapterNo)}章 $chapterTitle 实验',
            'objectives': '实践$chapterTitle的核心技术',
            'key_points': '$chapterTitle实践操作要点',
            'difficult_points': '$chapterTitle实践中的常见问题',
            'content': '$chapterTitle实验实践',
            'homework': '提交$chapterTitle实验报告',
            'hours': chapterNo == chapters.length ? 6 : 4,
            'plan_type': 'experiment',
            'status': 'ready',
            'ai_generated': 0,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 动态课程辅助方法
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _resolveActiveCourseId(Database db) async {
    final result =
        await db.rawQuery('SELECT id FROM courses WHERE is_active = 1 LIMIT 1');
    if (result.isNotEmpty) return result.first['id'] as String;
    return 'default';
  }

  Future<String> _resolveActiveCourseName(Database db, String courseId) async {
    final result =
        await db.rawQuery('SELECT name FROM courses WHERE id = ?', [courseId]);
    if (result.isNotEmpty) return result.first['name'] as String? ?? '当前课程';
    return '当前课程';
  }

  Future<List<String>> _getCourseChapters(Database db, String courseId) async {
    final result = await db
        .rawQuery('SELECT chapters FROM courses WHERE id = ?', [courseId]);
    if (result.isNotEmpty) {
      final chaptersJson = result.first['chapters'] as String?;
      if (chaptersJson != null && chaptersJson.isNotEmpty) {
        final list = List<String>.from(
          (jsonDecode(chaptersJson) as List).map((e) => e.toString()),
        );
        if (list.isNotEmpty) return list;
      }
    }
    final chapterCount = await _getChapterCount(db, courseId);
    return List.generate(chapterCount, (i) => '第${i + 1}章');
  }

  Future<int> _getChapterCount(Database db, String courseId) async {
    final result = await db
        .rawQuery('SELECT chapter_count FROM courses WHERE id = ?', [courseId]);
    if (result.isNotEmpty) return (result.first['chapter_count'] as int?) ?? 1;
    return 1;
  }

  String _toChineseNumber(int n) {
    const digits = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (n <= 10) return digits[n];
    return '十${digits[n - 10]}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 教案 CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// 获取所有教案（按章节排序）
  Future<List<Map<String, dynamic>>> getAllLessonPlans() async {
    final db = await DatabaseHelper.instance.database;
    await _ensureTeachingColumns();
    final filter = await _courseFilter();
    return db.query('lesson_plans',
        where: filter.where,
        whereArgs: filter.args,
        orderBy: 'chapter ASC, id ASC');
  }

  /// 按章节获取教案
  Future<List<Map<String, dynamic>>> getLessonPlansByChapter(
      int chapter) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureTeachingColumns();
    final filter = await _courseFilter();
    return db.query('lesson_plans',
        where: 'chapter = ? AND ${filter.where}',
        whereArgs: [chapter, ...filter.args],
        orderBy: 'id ASC');
  }

  /// 获取单个教案
  Future<Map<String, dynamic>?> getLessonPlan(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list =
        await db.query('lesson_plans', where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 新增教案
  Future<int> addLessonPlan(Map<String, dynamic> plan) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureTeachingColumns();
    plan['course_name'] ??= await _activeCourseName();
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
    await _ensureTeachingColumns();
    final filter = await _courseFilter();
    Future<int> count({String? status, bool? aiGenerated}) async {
      final parts = [filter.where];
      final args = <Object?>[...filter.args];
      if (status != null) {
        parts.add('status = ?');
        args.add(status);
      }
      if (aiGenerated != null) {
        parts.add('ai_generated = ?');
        args.add(aiGenerated ? 1 : 0);
      }
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM lesson_plans WHERE ${parts.join(' AND ')}',
        args,
      );
      return (rows.first['c'] as int?) ?? 0;
    }

    return {
      'total': await count(),
      'draft': await count(status: 'draft'),
      'ready': await count(status: 'ready'),
      'used': await count(status: 'used'),
      'ai_generated': await count(aiGenerated: true),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 教学进度 CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// 获取所有教学进度（按计划日期排序）
  Future<List<Map<String, dynamic>>> getAllTeachingProgress() async {
    final db = await DatabaseHelper.instance.database;
    await _ensureTeachingColumns();
    final filter = await _courseFilter();
    return db.query('teaching_progress',
        where: filter.where,
        whereArgs: filter.args,
        orderBy: 'chapter ASC, planned_date ASC');
  }

  /// 按班级获取教学进度
  Future<List<Map<String, dynamic>>> getProgressByClass(int classId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureTeachingColumns();
    final filter = await _courseFilter();
    return db.query('teaching_progress',
        where: 'class_id = ? AND ${filter.where}',
        whereArgs: [classId, ...filter.args],
        orderBy: 'chapter ASC, planned_date ASC');
  }

  /// 获取单个进度记录
  Future<Map<String, dynamic>?> getTeachingProgressItem(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list =
        await db.query('teaching_progress', where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 新增教学进度
  Future<int> addTeachingProgress(Map<String, dynamic> progress) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureTeachingColumns();
    progress['course_name'] ??= await _activeCourseName();
    progress['created_at'] = DateTime.now().toIso8601String();
    progress['updated_at'] = DateTime.now().toIso8601String();
    return db.insert('teaching_progress', progress);
  }

  /// 更新教学进度
  Future<int> updateTeachingProgress(
      int id, Map<String, dynamic> progress) async {
    final db = await DatabaseHelper.instance.database;
    progress['updated_at'] = DateTime.now().toIso8601String();
    return db.update('teaching_progress', progress,
        where: 'id = ?', whereArgs: [id]);
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
    await _ensureTeachingColumns();
    final filter = await _courseFilter();
    Future<int> count([String? status]) async {
      final where =
          status == null ? filter.where : '${filter.where} AND status = ?';
      final args = status == null ? filter.args : [...filter.args, status];
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM teaching_progress WHERE $where',
        args,
      );
      return (rows.first['c'] as int?) ?? 0;
    }

    final totalCount = await count();
    final completedCount = await count('completed');
    return {
      'total': totalCount,
      'planned': await count('planned'),
      'in_progress': await count('in_progress'),
      'completed': completedCount,
      'progress_rate': totalCount > 0
          ? (completedCount / totalCount * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  /// 根据大纲自动生成教学进度计划
  Future<int> generateProgressFromSyllabus(
      {int? classId, String? teacherId}) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureTeachingColumns();
    final items = await getAllSyllabusItems();
    if (items.isEmpty) return 0;

    int count = 0;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    final courseName = await _activeCourseName();
    for (final item in items) {
      final chNum = item['chapter_number'] as int;
      final weekStart = item['week_start'] as int? ?? chNum * 2;
      batch.insert('teaching_progress', {
        'course_name': courseName,
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
  String _weekToDate(int week, {DateTime? semesterStart}) {
    semesterStart ??= DateTime(2026, 3, 2);
    final targetDate = semesterStart.add(Duration(days: (week - 1) * 7));
    return '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
  }
}
