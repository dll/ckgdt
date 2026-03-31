import 'package:flutter/foundation.dart';
import '../models/graph_model.dart';
import '../models/node_model.dart';
import '../models/edge_model.dart';
import 'database_helper.dart';

class GraphDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<GraphModel>> getAllGraphs() async {
    final db = await _dbHelper.database;
    debugPrint('=== GraphDao: Querying graphs...');
    final maps = await db.query('graphs');
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
  Future<Map<String, Map<String, int>>> getGraphStats(List<String> graphIds) async {
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
}
