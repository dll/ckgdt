import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import '../data/local/class_dao.dart';

/// 默认班级管理 — 集中管理当前用户默认显示班级
/// 所有页面通过此服务获取"应该显示的班级"，而非各自取 classes.first
class DefaultClassService {
  DefaultClassService._();
  static final DefaultClassService instance = DefaultClassService._();

  final _classDao = ClassDao();

  /// 获取默认班级 ID（从 current_session 读取）
  Future<int?> getDefaultClassId() async {
    final db = await DatabaseHelper.instance.database;
    try {
      final rows = await db.rawQuery('SELECT default_class_id FROM current_session WHERE id = 1');
      if (rows.isNotEmpty && rows.first['default_class_id'] != null) {
        return rows.first['default_class_id'] as int;
      }
    } catch (e) {
      // default_class_id 列在 V26 前不存在，探测失败可忽略
      swallow(e, tag: 'DefaultClassService.getDefaultClassId');
    }
    return null;
  }

  /// 设置默认班级 ID
  Future<void> setDefaultClassId(int classId) async {
    final db = await DatabaseHelper.instance.database;
    await db.rawUpdate(
      'UPDATE current_session SET default_class_id = ? WHERE id = 1',
      [classId],
    );
  }

  /// 获取默认班级信息
  Future<Map<String, dynamic>?> getDefaultClass() async {
    final classId = await getDefaultClassId();
    if (classId == null) return null;
    final classes = await _classDao.getActiveClasses();
    try {
      return classes.firstWhere((c) => c['id'] == classId);
    } catch (e) {
      // 默认班级 id 不在活跃班级中（已归档/被删），返回 null
      swallow(e, tag: 'DefaultClassService.getDefaultClass');
      return null;
    }
  }

  /// 获取所有活跃班级（供选择切换用）
  Future<List<Map<String, dynamic>>> getAvailableClasses() async {
    return _classDao.getActiveClasses();
  }

  /// 确保班级数据已初始化，并设置默认班级
  Future<void> ensureDefaultClass() async {
    await _classDao.generateDemoData();

    final existing = await getDefaultClassId();
    if (existing != null) return;

    final active = await _classDao.getActiveClasses();
    if (active.isEmpty) {
      await _classDao.generateDemoData();
      final refreshed = await _classDao.getActiveClasses();
      if (refreshed.isNotEmpty) {
        await setDefaultClassId(refreshed.first['id'] as int);
      }
      return;
    }

    // 取第一个活跃班级作为默认
    await setDefaultClassId(active.first['id'] as int);
  }

  /// 获取默认班级下的学生列表
  Future<List<dynamic>> getDefaultClassStudents() async {
    final classId = await getDefaultClassId();
    if (classId == null) return [];
    return _classDao.getClassStudents(classId);
  }
}
