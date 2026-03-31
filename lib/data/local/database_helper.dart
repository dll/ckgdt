import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    try {
      final dbFolder = await getDatabasesPath();
      final dbPath = p.join(dbFolder, 'knowledge_graph.db');

      debugPrint('=== DatabaseHelper: Checking path: $dbPath');

      // Check if database file exists
      final file = File(dbPath);
      final exists = await file.exists();
      debugPrint('=== DatabaseHelper: Database exists = $exists');

      Database db;

      if (!exists) {
        // Try to copy from assets first
        try {
          debugPrint(
              '=== DatabaseHelper: Trying to copy database from assets...');
          final data = await rootBundle.load('assets/learning_data.db');
          final bytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await Directory(dbFolder).create(recursive: true);
          await file.writeAsBytes(bytes);
          debugPrint('=== DatabaseHelper: Copied database from assets');
        } catch (e) {
          debugPrint('=== DatabaseHelper: Failed to copy from assets: $e');
          // Create empty database
          db = await openDatabase(
            dbPath,
            version: 3,
            onCreate: _createTables,
            onUpgrade: _onUpgrade,
          );
          _database = db;
          debugPrint('=== DatabaseHelper: Created new empty database');
          return db;
        }
      }

      db = await openDatabase(
        dbPath,
        version: 3,
        onCreate: _createTables,
        onUpgrade: _onUpgrade,
      );
      debugPrint('=== DatabaseHelper: Database opened successfully');

      // Verify tables exist
      try {
        final tables = await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
        debugPrint(
            '=== DatabaseHelper: Tables in database: ${tables.map((t) => t['name']).toList()}');

        // Verify data
        final graphCount =
            await db.rawQuery('SELECT COUNT(*) as count FROM graphs');
        debugPrint('=== DatabaseHelper: Graphs count: ${graphCount.first}');
        final questionCount =
            await db.rawQuery('SELECT COUNT(*) as count FROM questions');
        debugPrint('=== DatabaseHelper: Questions count: ${questionCount.first}');
      } catch (e) {
        debugPrint('=== DatabaseHelper: Verification warning: $e');
      }

      // Import students if needed
      await _importStudents(db);

      return db;
    } catch (e) {
      debugPrint('=== DatabaseHelper: ERROR = $e');
      rethrow;
    }
  }

  Future<void> _importStudents(Database db) async {
    try {
      // 始终尝试导入 students.json（使用 conflictAlgorithm.ignore 安全合并）
      try {
        final jsonStr = await rootBundle.loadString('assets/students.json');
        final students = json.decode(jsonStr) as List;
        debugPrint(
            '=== DatabaseHelper: Loading ${students.length} students from JSON');

        final batch = db.batch();
        for (final s in students) {
          batch.insert(
              'users',
              {
                'user_id': s['user_id'],
                'real_name': s['real_name'],
                'role': 'student',
                'is_active': 1,
                'created_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
        debugPrint('=== DatabaseHelper: Students import completed (new entries merged)');
      } catch (e) {
        debugPrint('=== DatabaseHelper: Error importing students: $e');
      }
    } catch (e) {
      debugPrint('=== DatabaseHelper: Error checking students: $e');
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users(
        user_id TEXT PRIMARY KEY,
        real_name TEXT,
        machine_code TEXT,
        role TEXT DEFAULT 'student',
        created_at TEXT,
        last_login TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS current_session(
        id INTEGER PRIMARY KEY CHECK(id=1),
        user_id TEXT,
        machine_code TEXT,
        login_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS graphs(
        id TEXT PRIMARY KEY,
        title TEXT,
        graph_type TEXT,
        layout TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS nodes(
        id TEXT PRIMARY KEY,
        graph_id TEXT,
        title TEXT,
        content TEXT,
        node_type TEXT,
        level INTEGER,
        x REAL,
        y REAL,
        color TEXT,
        parent_id TEXT,
        visible INTEGER,
        metadata_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS edges(
        id TEXT PRIMARY KEY,
        graph_id TEXT,
        source_id TEXT,
        target_id TEXT,
        edge_type TEXT,
        label TEXT,
        weight REAL,
        color TEXT,
        width REAL,
        style TEXT,
        visible INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS questions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT,
        question TEXT,
        option_a TEXT,
        option_b TEXT,
        option_c TEXT,
        option_d TEXT,
        answer_index INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_results(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        quiz_timestamp TEXT,
        score INTEGER,
        num_correct INTEGER,
        num_total INTEGER,
        chapter TEXT,
        quiz_type TEXT,
        completed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS learning_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_title TEXT NOT NULL,
        study_time TEXT,
        completed_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wrong_answers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        question_id INTEGER NOT NULL,
        question TEXT,
        user_answer TEXT,
        correct_answer TEXT,
        chapter TEXT,
        times INTEGER DEFAULT 1,
        wrong_time TEXT,
        last_wrong_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_title TEXT,
        favorite_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT,
        file_path TEXT,
        file_type TEXT,
        chapter TEXT,
        description TEXT
      )
    ''');

    await _createNewTablesV2(db);
    await _createNewTablesV3(db);

    // 修复 asset DB 中旧表缺少的列
    await _ensureResourceFileColumns(db);

    // Add admin user (ignore if already exists from asset DB)
    await db.insert('users', {
      'user_id': '419116',
      'real_name': '管理员',
      'role': 'admin',
      'created_at': DateTime.now().toIso8601String(),
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // Add teacher user - 刘老师 (ignore if already exists)
    await db.insert('users', {
      'user_id': '206004',
      'real_name': '刘老师',
      'role': 'teacher',
      'created_at': DateTime.now().toIso8601String(),
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('=== DatabaseHelper: Upgrading from v$oldVersion to v$newVersion');
    if (oldVersion < 2) {
      await _createNewTablesV2(db);
    }
    if (oldVersion < 3) {
      await _createNewTablesV3(db);
    }
    // 确保从 asset 复制的旧 DB 中缺失的表被创建（IF NOT EXISTS 安全）
    await _ensureAllTables(db);
  }

  /// 确保所有核心表存在（适用于从 asset 复制的旧版 DB 升级场景）
  Future<void> _ensureAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wrong_answers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        question_id INTEGER NOT NULL,
        question TEXT,
        user_answer TEXT,
        correct_answer TEXT,
        chapter TEXT,
        times INTEGER DEFAULT 1,
        wrong_time TEXT,
        last_wrong_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_title TEXT,
        favorite_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT,
        file_path TEXT,
        file_type TEXT,
        chapter TEXT,
        description TEXT
      )
    ''');

    // 如果 resource_files 表已存在但缺少 chapter/description 列，补上
    await _ensureResourceFileColumns(db);

    await _createNewTablesV2(db);
    await _createNewTablesV3(db);
  }

  /// 补齐 resource_files 表可能缺少的列
  Future<void> _ensureResourceFileColumns(Database db) async {
    try {
      await db.rawQuery('SELECT chapter FROM resource_files LIMIT 1');
    } catch (_) {
      try {
        await db.execute('ALTER TABLE resource_files ADD COLUMN chapter TEXT');
        debugPrint('=== DatabaseHelper: Added chapter column to resource_files');
      } catch (_) {}
    }
    try {
      await db.rawQuery('SELECT description FROM resource_files LIMIT 1');
    } catch (_) {
      try {
        await db.execute('ALTER TABLE resource_files ADD COLUMN description TEXT');
        debugPrint('=== DatabaseHelper: Added description column to resource_files');
      } catch (_) {}
    }
  }

  Future<void> _createNewTablesV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS learning_paths(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        node_ids TEXT,
        progress REAL DEFAULT 0,
        status TEXT DEFAULT 'active',
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS path_nodes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path_id INTEGER NOT NULL,
        node_id TEXT NOT NULL,
        node_title TEXT,
        sequence INTEGER,
        is_completed INTEGER DEFAULT 0,
        completed_at TEXT,
        FOREIGN KEY (path_id) REFERENCES learning_paths(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS graph_analysis(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        graph_id TEXT NOT NULL,
        analysis_type TEXT NOT NULL,
        result_json TEXT,
        created_at TEXT
      )
    ''');
  }

  Future<void> _createNewTablesV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS generated_materials(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        file_path TEXT,
        content TEXT,
        chapter TEXT,
        created_at TEXT,
        size INTEGER DEFAULT 0,
        thumbnail_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS puml_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        file_path TEXT,
        rendered_url TEXT,
        diagram_type TEXT DEFAULT 'class',
        chapter TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_configs(
        id INTEGER PRIMARY KEY CHECK(id=1),
        provider TEXT DEFAULT 'deepseek',
        api_key TEXT,
        model TEXT DEFAULT 'deepseek-chat',
        base_url TEXT,
        updated_at TEXT
      )
    ''');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
