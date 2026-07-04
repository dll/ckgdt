import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import 'course_context_service.dart';
import 'course_data_service.dart';

/// 从 data/{courseId}/ 动态导入教学资源（视频脚本、课件）
class CkgdtResourceImporter {
  static final CkgdtResourceImporter instance = CkgdtResourceImporter._();
  CkgdtResourceImporter._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  /// 导入当前课程的教学资源
  Future<int> importCkgdtResources() async {
    final db = await _dbHelper.database;
    final course = await _courseContext.getActiveCourse();
    final courseId = course.id;

    final pkg = await CourseDataService.instance.getPackage(courseId);
    if (pkg.videoFiles.isEmpty && pkg.pptFiles.isEmpty) {
      debugPrint('=== CkgdtResourceImporter: No resources found for $courseId');
      return 0;
    }

    // 删除旧数据
    await db.delete('resource_files', where: 'course_id = ?', whereArgs: [courseId]);

    int totalImported = 0;

    // 导入视频脚本
    for (final vf in pkg.videoFiles) {
      try {
        final chapter = _chapterLabel(vf.chapterNumber);
        await db.insert('resource_files', {
          'course_id': courseId,
          'file_name': '$chapter ${vf.title.isNotEmpty ? vf.title : vf.fileName}',
          'file_path': vf.path,
          'file_type': 'video',
          'chapter': chapter,
          'description': vf.title.isNotEmpty ? vf.title : '$chapter 视频脚本',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        totalImported++;
      } catch (e, st) {
        swallowDebug(e, tag: 'CkgdtResourceImporter.video', stack: st);
      }
    }

    // 导入课件
    for (final pf in pkg.pptFiles) {
      try {
        final chapter = _chapterLabel(pf.chapterNumber);
        await db.insert('resource_files', {
          'course_id': courseId,
          'file_name': '$chapter ${pf.title.isNotEmpty ? pf.title : pf.fileName}',
          'file_path': pf.path,
          'file_type': 'ppt',
          'chapter': chapter,
          'description': pf.title.isNotEmpty ? pf.title : '$chapter 课件',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        totalImported++;
      } catch (e, st) {
        swallowDebug(e, tag: 'CkgdtResourceImporter.ppt', stack: st);
      }
    }

    debugPrint('=== CkgdtResourceImporter: Total imported $totalImported resources for $courseId');
    return totalImported;
  }

  String _chapterLabel(int num) => '第$num章';
}
