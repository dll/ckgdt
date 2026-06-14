import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/graph_model.dart';
import '../models/node_model.dart';
import '../models/edge_model.dart';
import '../../services/course_context_service.dart';
import 'database_helper.dart';

class GraphDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  Future<List<GraphModel>> getAllGraphs() async {
    final db = await _dbHelper.database;
    debugPrint('=== GraphDao: Querying graphs...');
    final scope = await _courseContext.scopedWhere();
    final maps = await db.query(
      'graphs',
      where: scope.where,
      whereArgs: scope.args,
    );
    debugPrint('=== GraphDao: Got ${maps.length} maps');
    if (maps.isNotEmpty) {
      debugPrint('=== GraphDao: First record: ${maps.first}');
    }
    return maps.map((map) => GraphModel.fromMap(map)).toList();
  }

  Future<GraphModel?> getGraph(String graphId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'graphs',
      where: 'id = ?',
      whereArgs: [graphId],
    );
    if (maps.isNotEmpty) {
      return GraphModel.fromMap(maps.first);
    }
    return null;
  }

  Future<List<NodeModel>> getNodes(String graphId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'nodes',
      where: 'graph_id = ?',
      whereArgs: [graphId],
    );
    return maps.map((map) => NodeModel.fromMap(map)).toList();
  }

  Future<List<EdgeModel>> getEdges(String graphId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'edges',
      where: 'graph_id = ?',
      whereArgs: [graphId],
    );
    return maps.map((map) => EdgeModel.fromMap(map)).toList();
  }

  Future<NodeModel?> getNode(String nodeId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'nodes',
      where: 'id = ?',
      whereArgs: [nodeId],
    );
    if (maps.isNotEmpty) {
      return NodeModel.fromMap(maps.first);
    }
    return null;
  }

  /// 获取图谱的节点数
  Future<int> getNodeCount(String graphId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM nodes WHERE graph_id = ?',
      [graphId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// 获取图谱的边数
  Future<int> getEdgeCount(String graphId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM edges WHERE graph_id = ?',
      [graphId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// 批量获取多个图谱的统计数据
  Future<Map<String, Map<String, int>>> getGraphStats(
      List<String> graphIds) async {
    final db = await _dbHelper.database;
    final stats = <String, Map<String, int>>{};
    for (final gid in graphIds) {
      final nodeResult = await db.rawQuery(
          'SELECT COUNT(*) as c FROM nodes WHERE graph_id = ?', [gid]);
      final edgeResult = await db.rawQuery(
          'SELECT COUNT(*) as c FROM edges WHERE graph_id = ?', [gid]);
      stats[gid] = {
        'nodes': (nodeResult.first['c'] as int?) ?? 0,
        'edges': (edgeResult.first['c'] as int?) ?? 0,
      };
    }
    return stats;
  }

  /// 删除指定图谱及其所有节点和边
  Future<void> deleteGraph(String graphId) async {
    final db = await _dbHelper.database;
    await db.delete('edges', where: 'graph_id = ?', whereArgs: [graphId]);
    await db.delete('nodes', where: 'graph_id = ?', whereArgs: [graphId]);
    await db.delete('graphs', where: 'id = ?', whereArgs: [graphId]);
  }

  // ── 写入方法 ──────────────────────────────────────────────────────────

  /// 创建新图谱，返回插入行 ID
  Future<int> createGraph(GraphModel graph) async {
    final db = await _dbHelper.database;
    final row = graph.toMap();
    row['course_id'] ??= await _courseContext.activeCourseId();
    return await db.insert('graphs', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 更新图谱元数据（标题、类型、布局）
  Future<void> updateGraph(GraphModel graph) async {
    final db = await _dbHelper.database;
    await db.update('graphs', graph.toMap(),
        where: 'id = ?', whereArgs: [graph.id]);
  }

  /// 插入节点
  Future<void> insertNode(NodeModel node) async {
    final db = await _dbHelper.database;
    await db.insert('nodes', node.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 批量插入节点
  Future<void> insertNodes(List<NodeModel> nodes) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final node in nodes) {
      batch.insert('nodes', node.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 更新节点
  Future<void> updateNode(NodeModel node) async {
    final db = await _dbHelper.database;
    await db
        .update('nodes', node.toMap(), where: 'id = ?', whereArgs: [node.id]);
  }

  /// 删除节点
  Future<void> deleteNode(String nodeId) async {
    final db = await _dbHelper.database;
    await db.delete('edges',
        where: 'source_id = ? OR target_id = ?', whereArgs: [nodeId, nodeId]);
    await db.delete('nodes', where: 'id = ?', whereArgs: [nodeId]);
  }

  /// 插入边
  Future<void> insertEdge(EdgeModel edge) async {
    final db = await _dbHelper.database;
    await db.insert('edges', edge.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 批量插入边
  Future<void> insertEdges(List<EdgeModel> edges) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final edge in edges) {
      batch.insert('edges', edge.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 更新边
  Future<void> updateEdge(EdgeModel edge) async {
    final db = await _dbHelper.database;
    await db
        .update('edges', edge.toMap(), where: 'id = ?', whereArgs: [edge.id]);
  }

  /// 删除边
  Future<void> deleteEdge(String edgeId) async {
    final db = await _dbHelper.database;
    await db.delete('edges', where: 'id = ?', whereArgs: [edgeId]);
  }
}
