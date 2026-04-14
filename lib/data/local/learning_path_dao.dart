import '../models/learning_path_model.dart';
import 'database_helper.dart';

class LearningPathDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<LearningPathModel>> getPathsByUser(String userId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'learning_paths',
      where: 'user_id = ?',
      whereArgs: [userId],
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
    final maps = await db.query(
      'learning_paths',
      where: 'id = ?',
      whereArgs: [pathId],
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
    return await db.insert('learning_paths', path.toMap());
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
    final maps = await db.query(
      'learning_paths',
      where: 'user_id = ?',
      whereArgs: ['system'],
    );
    return maps.map((map) {
      final nodeIdsStr = map['node_ids'] as String?;
      final nodeIds =
          nodeIdsStr?.isNotEmpty == true ? nodeIdsStr!.split(',') : <String>[];
      return LearningPathModel.fromMap({...map, 'node_ids': nodeIds});
    }).toList();
  }
}
