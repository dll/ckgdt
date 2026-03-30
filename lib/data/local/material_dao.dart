import '../models/material_model.dart';
import 'database_helper.dart';

class MaterialDao {
  final _db = DatabaseHelper.instance;

  Future<int> insert(MaterialModel m) async {
    final db = await _db.database;
    return db.insert('generated_materials', m.toMap());
  }

  Future<List<MaterialModel>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('generated_materials', orderBy: 'created_at DESC');
    return rows.map(MaterialModel.fromMap).toList();
  }

  Future<List<MaterialModel>> getByType(String type) async {
    final db = await _db.database;
    final rows = await db.query('generated_materials',
        where: 'type = ?', whereArgs: [type], orderBy: 'created_at DESC');
    return rows.map(MaterialModel.fromMap).toList();
  }

  Future<List<MaterialModel>> getByChapter(String chapter) async {
    final db = await _db.database;
    final rows = await db.query('generated_materials',
        where: 'chapter = ?', whereArgs: [chapter], orderBy: 'created_at DESC');
    return rows.map(MaterialModel.fromMap).toList();
  }

  Future<int> update(MaterialModel m) async {
    final db = await _db.database;
    return db.update('generated_materials', m.toMap(),
        where: 'id = ?', whereArgs: [m.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('generated_materials', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM generated_materials');
    return result.first['c'] as int? ?? 0;
  }
}
