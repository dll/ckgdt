import '../models/learning_path_model.dart';
import '../../services/course_context_service.dart';
import 'database_helper.dart';

class LearningPathDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  Future<({String where, List<Object?> args})> _scope({
    String column = 'course_id',
    String? extraWhere,
    List<Object?> extraArgs = const [],
  }) {
    return _courseContext.scopedWhere(
      column: column,
      extraWhere: extraWhere,
      extraArgs: extraArgs,
    );
  }

  /// 基于最近错题反向推导薄弱节点，生成"补强路径"
  /// 返回新建路径的 id，若无错题则返回 -1
  Future<int> generateRemediationPath(String userId) async {
    final db = await _dbHelper.database;

    // 1. 查错题 → 按章节聚合
    final wrongScope = await _scope(
      column: 'w.course_id',
      extraWhere: 'w.user_id = ?',
      extraArgs: [userId],
    );
    final wrongRows = await db.rawQuery('''
      SELECT w.chapter, COUNT(*) as cnt
      FROM wrong_answers w
      WHERE ${wrongScope.where}
      GROUP BY w.chapter
      ORDER BY cnt DESC
      LIMIT 5
    ''', wrongScope.args);

    if (wrongRows.isEmpty) return -1;

    // 2. 收集薄弱章节关联的节点
    final nodeIds = <String>[];
    for (final r in wrongRows) {
      final chapter = r['chapter'] as String? ?? '';
      if (chapter.isEmpty) continue;
      final graphScope = await _scope(
        column: 'g.course_id',
        extraWhere: 'g.title LIKE ?',
        extraArgs: ['%$chapter%'],
      );
      final nodes = await db.rawQuery('''
        SELECT CAST(id AS TEXT) as nid FROM nodes
        WHERE graph_id IN (
          SELECT id FROM graphs g WHERE ${graphScope.where}
        )
        LIMIT 10
      ''', graphScope.args);
      for (final n in nodes) {
        final nid = n['nid'] as String? ?? '';
        if (nid.isNotEmpty && !nodeIds.contains(nid)) nodeIds.add(nid);
      }
    }

    if (nodeIds.isEmpty) return -1;

    // 3. 创建补强路径
    final now = DateTime.now().toIso8601String();
    final pathId = await db.insert('learning_paths', {
      'course_id': await _courseContext.activeCourseId(),
      'user_id': userId,
      'title': '错题补强 ${DateTime.now().toString().substring(0, 10)}',
      'description': '基于错题本自动生成的薄弱知识补强路径',
      'node_ids': nodeIds.join(','),
      'progress': 0,
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    });

    // 4. 写入 path_nodes
    for (int i = 0; i < nodeIds.length; i++) {
      await db.insert('path_nodes', {
        'path_id': pathId,
        'node_id': nodeIds[i],
        'node_title': '薄弱节点 ${i + 1}',
        'sequence': i,
        'is_completed': 0,
      });
    }

    return pathId;
  }

  Future<List<LearningPathModel>> getPathsByUser(String userId) async {
    final db = await _dbHelper.database;
    final scope = await _scope(
      extraWhere: 'user_id = ?',
      extraArgs: [userId],
    );
    final maps = await db.query(
      'learning_paths',
      where: scope.where,
      whereArgs: scope.args,
      orderBy: 'created_at DESC',
    );
    return maps.map((map) {
      final nodeIdsStr = map['node_ids'] as String?;
      final nodeIds =
          nodeIdsStr?.isNotEmpty == true ? nodeIdsStr!.split(',') : <String>[];
      return LearningPathModel.fromMap({...map, 'node_ids': nodeIds});
    }).toList();
  }

  Future<LearningPathModel?> getPath(int pathId) async {
    final db = await _dbHelper.database;
    final scope = await _scope(
      extraWhere: 'id = ?',
      extraArgs: [pathId],
    );
    final maps = await db.query(
      'learning_paths',
      where: scope.where,
      whereArgs: scope.args,
    );
    if (maps.isEmpty) return null;
    final map = maps.first;
    final nodeIdsStr = map['node_ids'] as String?;
    final nodeIds =
        nodeIdsStr?.isNotEmpty == true ? nodeIdsStr!.split(',') : <String>[];
    return LearningPathModel.fromMap({...map, 'node_ids': nodeIds});
  }

  Future<int> createPath(LearningPathModel path) async {
    final db = await _dbHelper.database;
    final map = path.toMap();
    map['course_id'] ??= await _courseContext.activeCourseId();
    return await db.insert('learning_paths', map);
  }

  Future<int> updatePath(LearningPathModel path) async {
    final db = await _dbHelper.database;
    return await db.update(
      'learning_paths',
      path.toMap(),
      where: 'id = ?',
      whereArgs: [path.id],
    );
  }

  Future<int> deletePath(int pathId) async {
    final db = await _dbHelper.database;
    await db.delete('path_nodes', where: 'path_id = ?', whereArgs: [pathId]);
    return await db
        .delete('learning_paths', where: 'id = ?', whereArgs: [pathId]);
  }

  Future<void> updateProgress(int pathId) async {
    final db = await _dbHelper.database;
    final nodes = await db.query(
      'path_nodes',
      where: 'path_id = ?',
      whereArgs: [pathId],
    );
    if (nodes.isEmpty) return;

    final completed = nodes.where((n) => n['is_completed'] == 1).length;
    final progress = completed / nodes.length * 100;

    await db.update(
      'learning_paths',
      {'progress': progress, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [pathId],
    );
  }

  Future<List<PathNodeModel>> getPathNodes(int pathId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'path_nodes',
      where: 'path_id = ?',
      whereArgs: [pathId],
      orderBy: 'sequence ASC',
    );
    return maps.map((map) => PathNodeModel.fromMap(map)).toList();
  }

  Future<int> addPathNode(PathNodeModel node) async {
    final db = await _dbHelper.database;
    return await db.insert('path_nodes', node.toMap());
  }

  Future<int> markNodeCompleted(int nodeId, bool completed) async {
    final db = await _dbHelper.database;
    return await db.update(
      'path_nodes',
      {
        'is_completed': completed ? 1 : 0,
        'completed_at': completed ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [nodeId],
    );
  }

  Future<List<LearningPathModel>> getPresetPaths() async {
    final db = await _dbHelper.database;
    final scope = await _scope(
      extraWhere: 'user_id = ?',
      extraArgs: ['system'],
    );
    final maps = await db.query(
      'learning_paths',
      where: scope.where,
      whereArgs: scope.args,
    );
    return maps.map((map) {
      final nodeIdsStr = map['node_ids'] as String?;
      final nodeIds =
          nodeIdsStr?.isNotEmpty == true ? nodeIdsStr!.split(',') : <String>[];
      return LearningPathModel.fromMap({...map, 'node_ids': nodeIds});
    }).toList();
  }
}
