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
        // Copy from assets
        try {
          debugPrint('=== DatabaseHelper: Trying to load from assets...');
          final data = await rootBundle.load('assets/learning_data.db');
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          
          // Create directory if needed
          await Directory(dbFolder).create(recursive: true);
          await file.writeAsBytes(bytes);
          
          debugPrint('=== DatabaseHelper: Copied database from assets');
        } catch (e) {
          debugPrint('=== DatabaseHelper: Error loading from assets: $e');
          // Create empty database
          db = await openDatabase(dbPath, version: 1, onCreate: _createTables);
          _database = db;
          return db;
        }
      }
      
      db = await openDatabase(dbPath, version: 1);
      debugPrint('=== DatabaseHelper: Database opened successfully');
      
      // Verify tables exist
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      debugPrint('=== DatabaseHelper: Tables in database: ${tables.map((t) => t['name']).toList()}');
      
      // Verify data
      final graphCount = await db.rawQuery('SELECT COUNT(*) as count FROM graphs');
      debugPrint('=== DatabaseHelper: Graphs count: ${graphCount.first}');
      final questionCount = await db.rawQuery('SELECT COUNT(*) as count FROM questions');
      debugPrint('=== DatabaseHelper: Questions count: ${questionCount.first}');
      
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
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM users WHERE role = "student"');
      final count = result.first['count'] as int? ?? 0;
      debugPrint('=== DatabaseHelper: Current students count = $count');
      
      if (count == 0) {
        try {
          final jsonStr = await rootBundle.loadString('assets/students.json');
          final students = json.decode(jsonStr) as List;
          debugPrint('=== DatabaseHelper: Loaded ${students.length} students from JSON');
          
          final batch = db.batch();
          for (final s in students) {
            batch.insert('users', {
              'user_id': s['user_id'],
              'real_name': s['real_name'],
              'role': 'student',
              'is_active': 1,
              'created_at': DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await batch.commit(noResult: true);
          debugPrint('=== DatabaseHelper: Students imported');
        } catch (e) {
          debugPrint('=== DatabaseHelper: Error importing students: $e');
        }
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
    
    // Add admin user
    await db.insert('users', {
      'user_id': '419116',
      'real_name': '管理员',
      'role': 'admin',
      'created_at': DateTime.now().toIso8601String(),
      'is_active': 1,
    });
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
