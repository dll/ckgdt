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
}
