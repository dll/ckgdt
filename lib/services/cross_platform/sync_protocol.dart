import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../data/local/database_helper.dart';

/// 同步协议 — 负责全量/增量数据的序列化与反序列化
///
/// 将 SQLite 多表数据打包为 JSON 用于跨设备传输，
/// 支持按用户过滤（学生同步个人数据）和全量导出（教师/管理员）。
class SyncProtocol {
  static const int protocolVersion = 1;

  // ─────────────────────────────────────────────────────────────────────────
  // 导出 — 从本地 DB 收集数据打包为 JSON
  // ─────────────────────────────────────────────────────────────────────────

  /// 导出全量数据（管理员/教师用）
  static Future<Map<String, dynamic>> exportFullData() async {
    final db = await DatabaseHelper.instance.database;
    final tables = <String, List<Map<String, dynamic>>>{};

    for (final table in _syncTables) {
      try {
        final rows = await db.query(table);
        tables[table] = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      } catch (e) {
        debugPrint('SyncProtocol: export $table error: $e');
        tables[table] = [];
      }
    }

    return {
      'version': protocolVersion,
      'type': 'full',
      'timestamp': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  /// 导出指定用户的个人数据（学生用）
  static Future<Map<String, dynamic>> exportUserData(String userId) async {
    final db = await DatabaseHelper.instance.database;
    final tables = <String, List<Map<String, dynamic>>>{};

    // 用户信息
    final user = await db.query('users',
        where: 'user_id = ?', whereArgs: [userId]);
    tables['users'] = user.map((r) => Map<String, dynamic>.from(r)).toList();

    // 测验成绩
    try {
      final quiz = await db.query('quiz_results',
          where: 'user_id = ?', whereArgs: [userId]);
      tables['quiz_results'] =
          quiz.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      tables['quiz_results'] = [];
    }

    // 学习记录
    try {
      final learning = await db.query('learning_records',
          where: 'user_id = ?', whereArgs: [userId]);
      tables['learning_records'] =
          learning.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      tables['learning_records'] = [];
    }

    // 错题本
    try {
      final wrong = await db.query('wrong_answers',
          where: 'user_id = ?', whereArgs: [userId]);
      tables['wrong_answers'] =
          wrong.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      tables['wrong_answers'] = [];
    }

    // 收藏
    try {
      final fav = await db.query('favorites',
          where: 'user_id = ?', whereArgs: [userId]);
      tables['favorites'] =
          fav.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      tables['favorites'] = [];
    }

    // 班级关联
    try {
      final members = await db.query('class_members',
          where: 'user_id = ?', whereArgs: [userId]);
      tables['class_members'] =
          members.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      tables['class_members'] = [];
    }

    // 通知
    try {
      final notifs = await db.rawQuery('''
        SELECT n.* FROM notifications n
        INNER JOIN notification_recipients nr ON n.id = nr.notification_id
        WHERE nr.user_id = ?
      ''', [userId]);
      tables['notifications'] =
          notifs.map((r) => Map<String, dynamic>.from(r)).toList();

      final recipients = await db.query('notification_recipients',
          where: 'user_id = ?', whereArgs: [userId]);
      tables['notification_recipients'] =
          recipients.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      tables['notifications'] = [];
      tables['notification_recipients'] = [];
    }

    return {
      'version': protocolVersion,
      'type': 'user',
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  /// 导出共享/公共数据（知识图谱、题库、课程资源等）
  static Future<Map<String, dynamic>> exportSharedData() async {
    final db = await DatabaseHelper.instance.database;
    final tables = <String, List<Map<String, dynamic>>>{};

    for (final table in _sharedTables) {
      try {
        final rows = await db.query(table);
        tables[table] = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      } catch (e) {
        debugPrint('SyncProtocol: export shared $table error: $e');
      }
    }

    return {
      'version': protocolVersion,
      'type': 'shared',
      'timestamp': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 导入 — 将 JSON 数据写入本地 DB
  // ─────────────────────────────────────────────────────────────────────────

  /// 导入数据（合并模式：INSERT OR REPLACE）
  static Future<Map<String, int>> importData(
      Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    final tables = data['tables'] as Map<String, dynamic>? ?? {};
    final stats = <String, int>{};

    for (final entry in tables.entries) {
      final tableName = entry.key;
      final rows = entry.value as List<dynamic>? ?? [];
      if (rows.isEmpty) continue;

      // 安全校验：只允许已知表名，防止 SQL 注入
      if (!_syncTables.contains(tableName) &&
          !_sharedTables.contains(tableName)) {
        debugPrint('SyncProtocol: skip unknown table: $tableName');
        continue;
      }

      int count = 0;
      try {
        final batch = db.batch();
        for (final row in rows) {
          if (row is! Map<String, dynamic>) continue;
          final (sql, values) = _buildSafeUpsert(tableName, row);
          batch.rawInsert(sql, values);
          count++;
        }
        await batch.commit(noResult: true);
        stats[tableName] = count;
      } catch (e) {
        debugPrint('SyncProtocol: import $tableName error: $e');
        // 逐行插入作为降级方案
        for (final row in rows) {
          if (row is! Map<String, dynamic>) continue;
          try {
            final (sql, values) = _buildSafeUpsert(tableName, row);
            await db.rawInsert(sql, values);
            count++;
          } catch (_) {}
        }
        stats[tableName] = count;
      }
    }

    return stats;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JSON 编解码辅助
  // ─────────────────────────────────────────────────────────────────────────

  /// 将导出数据编码为 JSON 字符串
  static String encode(Map<String, dynamic> data) {
    return jsonEncode(data);
  }

  /// 解码 JSON 字符串为数据 Map
  static Map<String, dynamic>? decode(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      if (data['version'] != protocolVersion) {
        debugPrint('SyncProtocol: version mismatch — '
            'expected $protocolVersion, got ${data['version']}');
      }
      return data;
    } catch (e) {
      debugPrint('SyncProtocol: decode error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 私有方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 构建安全的 INSERT OR REPLACE SQL 和对应的值列表
  /// 过滤非法列名，防止 SQL 注入
  static (String sql, List<dynamic> values) _buildSafeUpsert(
      String table, Map<String, dynamic> row) {
    final colNamePattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    final safeCols = <String>[];
    final safeValues = <dynamic>[];
    for (final entry in row.entries) {
      if (colNamePattern.hasMatch(entry.key)) {
        safeCols.add(entry.key);
        safeValues.add(entry.value);
      }
    }
    final cols = safeCols.join(', ');
    final placeholders = List.filled(safeCols.length, '?').join(', ');
    return ('INSERT OR REPLACE INTO $table ($cols) VALUES ($placeholders)', safeValues);
  }

  /// 需要同步的所有表（全量模式）
  static const List<String> _syncTables = [
    'users',
    'graphs',
    'nodes',
    'edges',
    'questions',
    'quiz_results',
    'learning_records',
    'wrong_answers',
    'favorites',
    'resource_files',
    'classes',
    'class_members',
    'notifications',
    'notification_recipients',
  ];

  /// 公共/共享数据表（所有用户相同）
  static const List<String> _sharedTables = [
    'graphs',
    'nodes',
    'edges',
    'questions',
    'resource_files',
    'classes',
  ];
}
