import 'database_helper.dart';
import '../models/archive_document_model.dart';
import '../../core/error_handler.dart';

class ArchiveDao {
  Future<List<ArchiveDocument>> getDocuments({
    String? period,
    String? courseType,
    String? documentType,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final where = <String>[];
    final args = <dynamic>[];
    if (period != null) { where.add('period = ?'); args.add(period); }
    if (courseType != null) { where.add('course_type = ?'); args.add(courseType); }
    if (documentType != null) { where.add('document_type = ?'); args.add(documentType); }
    final rows = await db.query('archive_documents',
        where: where.isNotEmpty ? where.join(' AND ') : null,
        whereArgs: args.isNotEmpty ? args : null,
        orderBy: 'created_at DESC');
    return rows.map((r) => ArchiveDocument.fromMap(r)).toList();
  }

  Future<ArchiveDocument?> getDocumentById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('archive_documents', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? ArchiveDocument.fromMap(rows.first) : null;
  }

  Future<int> saveDocument(ArchiveDocument doc) async {
    final db = await DatabaseHelper.instance.database;
    if (doc.id != null) {
      await db.update('archive_documents', doc.toMap(),
          where: 'id = ?', whereArgs: [doc.id]);
      return doc.id!;
    }
    return db.insert('archive_documents', doc.toMap());
  }

  Future<void> deleteDocument(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('archive_documents', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> loadSourceData(String table) async {
    final db = await DatabaseHelper.instance.database;
    try {
      return await db.query(table, limit: 100);
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveDao.loadSourceData($table)', stack: st);
      return [];
    }
  }

  Future<int> archiveCount(String period) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as c FROM archive_documents WHERE period = ? AND status = 'archived'",
        [period]);
    return (result.first['c'] as int?) ?? 0;
  }

  /// V25：按 originDocId 查询关联的审核表（如教学大纲 #5 对应的大纲合理性审核表）。
  /// 返回所有指向该源文档的审核表（一般每个 docType 唯一，但理论上可能有多份）。
  Future<List<ArchiveDocument>> getAuditDocsForOrigin(int originDocId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'archive_documents',
      where: 'origin_doc_id = ?',
      whereArgs: [originDocId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => ArchiveDocument.fromMap(r)).toList();
  }
}
