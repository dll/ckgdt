import '../models/material_model.dart';
import '../../services/course_context_service.dart';
import 'database_helper.dart';

class MaterialDao {
  final _db = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  Future<int> insert(MaterialModel m) async {
    final db = await _db.database;
    final row = m.toMap();
    row['course_id'] ??= await _courseContext.activeCourseId();
    return db.insert('generated_materials', row);
  }

  Future<List<MaterialModel>> getAll() async {
    final db = await _db.database;
    final scope = await _courseContext.scopedWhere();
    final rows = await db.query(
      'generated_materials',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'created_at DESC',
    );
    return rows.map(MaterialModel.fromMap).toList();
  }

  Future<List<MaterialModel>> getByType(String type) async {
    final db = await _db.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'type = ?',
      extraArgs: [type],
    );
    final rows = await db.query(
      'generated_materials',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'created_at DESC',
    );
    return rows.map(MaterialModel.fromMap).toList();
  }

  Future<List<MaterialModel>> getByChapter(String chapter) async {
    final db = await _db.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere: 'chapter = ?',
      extraArgs: [chapter],
    );
    final rows = await db.query(
      'generated_materials',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'created_at DESC',
    );
    return rows.map(MaterialModel.fromMap).toList();
  }

  Future<int> update(MaterialModel m) async {
    final db = await _db.database;
    final row = m.toMap();
    row['course_id'] ??= await _courseContext.activeCourseId();
    return db
        .update('generated_materials', row, where: 'id = ?', whereArgs: [m.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('generated_materials', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db.database;
    final scope = await _courseContext.scopedWhere();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM generated_materials WHERE ${scope.where}',
      scope.args,
    );
    return result.first['c'] as int? ?? 0;
  }
}
