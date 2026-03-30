import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../data/models/graph_model.dart';
import '../data/models/node_model.dart';
import '../data/models/edge_model.dart';
import '../data/models/question_model.dart';
import '../data/local/database_helper.dart';

class DataMigrationService {
  /// 从外部SQLite数据库导入数据
  static Future<bool> importFromExternalDB(String sourceDBPath) async {
    try {
      final sourceDB = await openDatabase(sourceDBPath);
      
      // 获取图谱数据
      final graphs = await sourceDB.query('graphs');
      final nodes = await sourceDB.query('nodes');
      final edges = await sourceDB.query('edges');
      final questions = await sourceDB.query('questions');
      final users = await sourceDB.query('users');
      
      // 写入目标数据库
      final targetDB = await DatabaseHelper.instance.database;
      
      await targetDB.transaction((txn) async {
        // 导入图谱
        for (final graph in graphs) {
          await txn.insert('graphs', {
            'id': graph['id'],
            'title': graph['title'],
            'graph_type': graph['graph_type'],
            'layout': graph['layout'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        
        // 导入节点
        for (final node in nodes) {
          await txn.insert('nodes', {
            'id': node['id'],
            'graph_id': node['graph_id'],
            'title': node['title'],
            'content': node['content'],
            'node_type': node['node_type'],
            'level': node['level'],
            'x': node['x'],
            'y': node['y'],
            'color': node['color'],
            'parent_id': node['parent_id'],
            'visible': node['visible'],
            'metadata_json': node['metadata_json'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        
        // 导入边
        for (final edge in edges) {
          await txn.insert('edges', {
            'id': edge['id'],
            'graph_id': edge['graph_id'],
            'source_id': edge['source_id'],
            'target_id': edge['target_id'],
            'edge_type': edge['edge_type'],
            'label': edge['label'],
            'weight': edge['weight'],
            'color': edge['color'],
            'width': edge['width'],
            'style': edge['style'],
            'visible': edge['visible'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        
        // 导入题目
        for (final q in questions) {
          await txn.insert('questions', {
            'source': q['source'],
            'question': q['question'],
            'option_a': q['option_a'],
            'option_b': q['option_b'],
            'option_c': q['option_c'],
            'option_d': q['option_d'],
            'answer_index': q['answer_index'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        
        // 导入用户
        for (final user in users) {
          await txn.insert('users', {
            'user_id': user['user_id'],
            'real_name': user['real_name'],
            'machine_code': user['machine_code'],
            'role': user['role'],
            'created_at': user['created_at'],
            'last_login': user['last_login'],
            'is_active': user['is_active'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      
      await sourceDB.close();
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// 导出数据到JSON文件
  static Future<String?> exportToJSON() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      final graphs = await db.query('graphs');
      final nodes = await db.query('nodes');
      final edges = await db.query('edges');
      final questions = await db.query('questions');
      final users = await db.query('users');
      
      final data = {
        'export_time': DateTime.now().toIso8601String(),
        'version': '1.0.0',
        'graphs': graphs,
        'nodes': nodes,
        'edges': edges,
        'questions': questions,
        'users': users,
      };
      
      return jsonEncode(data);
    } catch (e) {
      return null;
    }
  }
  
  /// 从JSON导入数据
  static Future<bool> importFromJSON(String jsonString) async {
    try {
      final data = jsonDecode(jsonString);
      final db = await DatabaseHelper.instance.database;
      
      await db.transaction((txn) async {
        // 导入图谱
        if (data['graphs'] != null) {
          for (final graph in data['graphs']) {
            await txn.insert('graphs', Map<String, dynamic>.from(graph), 
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        
        // 导入节点
        if (data['nodes'] != null) {
          for (final node in data['nodes']) {
            await txn.insert('nodes', Map<String, dynamic>.from(node),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        
        // 导入边
        if (data['edges'] != null) {
          for (final edge in data['edges']) {
            await txn.insert('edges', Map<String, dynamic>.from(edge),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        
        // 导入题目
        if (data['questions'] != null) {
          for (final q in data['questions']) {
            await txn.insert('questions', Map<String, dynamic>.from(q),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });
      
      return true;
    } catch (e) {
      return false;
    }
  }
}
