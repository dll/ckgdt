import 'package:sqflite/sqflite.dart';
import '../../services/course_context_service.dart';
import 'database_helper.dart';

/// DAO for V9 knowledge_concepts & concept_relations tables.
class KnowledgeGraphDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  Future<String?> _activeCourseId() async {
    return _courseContext.activeCourseId();
  }

  Future<({String where, List<Object?> args})> _courseWhere([
    String? extraWhere,
    List<Object?> extraArgs = const [],
  ]) async {
    return _courseContext.scopedWhere(
      extraWhere: extraWhere,
      extraArgs: extraArgs,
    );
  }

  // ── Concepts ──────────────────────────────────────────────────────────────

  /// Insert a knowledge concept. Auto-fills created_at / updated_at.
  Future<int> addConcept(Map<String, dynamic> concept) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final row = Map<String, dynamic>.from(concept);
    final courseId = await _activeCourseId();
    if (courseId != null && courseId.isNotEmpty) {
      row['course_id'] ??= courseId;
    }
    row['created_at'] ??= now;
    row['updated_at'] ??= now;
    return db.insert(
      'knowledge_concepts',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> getAllConcepts() async {
    final db = await _dbHelper.database;
    final scope = await _courseWhere();
    return db.query(
      'knowledge_concepts',
      where: scope.where.isEmpty ? null : scope.where,
      whereArgs: scope.args.isEmpty ? null : scope.args,
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getConceptsByChapter(int chapter) async {
    final db = await _dbHelper.database;
    final scope = await _courseWhere('chapter = ?', [chapter]);
    return db.query(
      'knowledge_concepts',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'id ASC',
    );
  }

  Future<Map<String, dynamic>?> getConceptById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'knowledge_concepts',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> searchConcepts(String query) async {
    final db = await _dbHelper.database;
    final scope = await _courseWhere(
      'concept_name LIKE ? OR keywords LIKE ?',
      ['%$query%', '%$query%'],
    );
    return db.query(
      'knowledge_concepts',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'id ASC',
    );
  }

  Future<int> updateConcept(int id, Map<String, dynamic> data) async {
    final db = await _dbHelper.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update(
      'knowledge_concepts',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteConcept(int id) async {
    final db = await _dbHelper.database;
    // Cascade will clean concept_relations automatically
    return db.delete('knowledge_concepts', where: 'id = ?', whereArgs: [id]);
  }

  // ── Relations ─────────────────────────────────────────────────────────────

  /// Insert a concept relation. Auto-fills created_at.
  Future<int> addRelation(Map<String, dynamic> relation) async {
    final db = await _dbHelper.database;
    final row = Map<String, dynamic>.from(relation);
    final courseId = await _activeCourseId();
    if (courseId != null && courseId.isNotEmpty) {
      row['course_id'] ??= courseId;
    }
    row['created_at'] ??= DateTime.now().toIso8601String();
    return db.insert(
      'concept_relations',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> getRelationsForConcept(
      int conceptId) async {
    final db = await _dbHelper.database;
    final scope = await _courseWhere(
      'source_concept_id = ? OR target_concept_id = ?',
      [conceptId, conceptId],
    );
    return db.query(
      'concept_relations',
      where: scope.where,
      whereArgs: scope.args,
    );
  }

  Future<List<Map<String, dynamic>>> getAllRelations() async {
    final db = await _dbHelper.database;
    final scope = await _courseWhere();
    return db.query(
      'concept_relations',
      where: scope.where.isEmpty ? null : scope.where,
      whereArgs: scope.args.isEmpty ? null : scope.args,
      orderBy: 'id ASC',
    );
  }

  Future<int> deleteRelation(int id) async {
    final db = await _dbHelper.database;
    return db.delete('concept_relations', where: 'id = ?', whereArgs: [id]);
  }

  // ── Statistics ────────────────────────────────────────────────────────────

  Future<int> conceptCount() async {
    final db = await _dbHelper.database;
    final scope = await _courseWhere();
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM knowledge_concepts'
      '${scope.where.isEmpty ? '' : ' WHERE ${scope.where}'}',
      scope.args,
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> relationCount() async {
    final db = await _dbHelper.database;
    final scope = await _courseWhere();
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM concept_relations'
      '${scope.where.isEmpty ? '' : ' WHERE ${scope.where}'}',
      scope.args,
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Returns aggregated statistics for the stats dialog.
  /// Keys: concept_count, relation_count, type_distribution, chapter_distribution
  Future<Map<String, dynamic>> getStats() async {
    final db = await _dbHelper.database;

    final cCount = await conceptCount();
    final rCount = await relationCount();

    // concept_type distribution
    final scope = await _courseWhere();
    final whereSql = scope.where.isEmpty ? '' : 'WHERE ${scope.where}';
    final typeRows = await db.rawQuery(
      'SELECT concept_type, COUNT(*) as cnt FROM knowledge_concepts '
      '$whereSql GROUP BY concept_type',
      scope.args,
    );
    final typeDistribution = <String, int>{};
    for (final row in typeRows) {
      typeDistribution[row['concept_type'] as String? ?? 'concept'] =
          (row['cnt'] as int?) ?? 0;
    }

    // chapter distribution
    final chapterRows = await db.rawQuery(
      'SELECT chapter, COUNT(*) as cnt FROM knowledge_concepts '
      '${scope.where.isEmpty ? 'WHERE' : '$whereSql AND'} chapter IS NOT NULL '
      'GROUP BY chapter',
      scope.args,
    );
    final chapterDistribution = <int, int>{};
    for (final row in chapterRows) {
      chapterDistribution[(row['chapter'] as int?) ?? 0] =
          (row['cnt'] as int?) ?? 0;
    }

    return {
      'concept_count': cCount,
      'relation_count': rCount,
      'type_distribution': typeDistribution,
      'chapter_distribution': chapterDistribution,
    };
  }
}
