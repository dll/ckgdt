import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';

// 条件导入：Web 用 stub，原生用 native
import 'data_service_stub.dart'
    if (dart.library.io) 'data_service_native.dart' as impl;

class DataService {
  /// 导出数据库到JSON文件
  static Future<String?> exportToJSON() async {
    if (kIsWeb) return null; // Web 平台不支持文件导出
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

      final jsonString = jsonEncode(data);
      return await impl.saveJsonToFile(jsonString);
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
        if (data['graphs'] != null) {
          for (final graph in data['graphs']) {
            await txn.insert('graphs', Map<String, dynamic>.from(graph),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        if (data['nodes'] != null) {
          for (final node in data['nodes']) {
            await txn.insert('nodes', Map<String, dynamic>.from(node),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        if (data['edges'] != null) {
          for (final edge in data['edges']) {
            await txn.insert('edges', Map<String, dynamic>.from(edge),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        if (data['questions'] != null) {
          for (final q in data['questions']) {
            await txn.insert('questions', Map<String, dynamic>.from(q),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        if (data['users'] != null) {
          for (final user in data['users']) {
            await txn.insert('users', Map<String, dynamic>.from(user),
              conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取数据库路径
  static Future<String> getDBPath() async {
    return await impl.getNativeDBPath();
  }

  /// 复制数据库文件
  static Future<bool> copyDBTo(String destPath) async {
    if (kIsWeb) return false;
    return await impl.copyDBFile(destPath);
  }
}
