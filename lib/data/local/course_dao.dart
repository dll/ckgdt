import '../models/course_model.dart';
import 'database_helper.dart';

/// 课程数据访问对象
class CourseDao {
  /// 获取所有课程
  Future<List<CourseModel>> getAllCourses() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('courses', orderBy: 'created_at ASC');
    return maps.map((m) => CourseModel.fromMap(m)).toList();
  }

  /// 获取当前激活的课程
  Future<CourseModel?> getActiveCourse() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'courses',
      where: 'is_active = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return CourseModel.fromMap(maps.first);
  }

  /// 获取单个课程
  Future<CourseModel?> getCourse(String id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'courses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return CourseModel.fromMap(maps.first);
  }

  /// 添加课程
  Future<void> addCourse(CourseModel course) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('courses', course.toMap());
  }

  /// 更新课程
  Future<void> updateCourse(CourseModel course) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'courses',
      course.toMap(),
      where: 'id = ?',
      whereArgs: [course.id],
    );
  }

  /// 切换激活课程（先取消全部激活，再激活指定课程）
  Future<void> setActiveCourse(String courseId) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.update('courses', {'is_active': 0});
      await txn.update(
        'courses',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [courseId],
      );
    });
  }

  /// 删除课程（不能删除激活中的课程）
  Future<bool> deleteCourse(String courseId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'courses',
      where: 'id = ? AND is_active = ?',
      whereArgs: [courseId, 1],
    );
    if (maps.isNotEmpty) return false; // 不能删除激活课程
    await db.delete('courses', where: 'id = ?', whereArgs: [courseId]);
    return true;
  }

  /// 获取课程数量
  Future<int> getCourseCount() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM courses');
    return result.first['cnt'] as int? ?? 0;
  }
}
