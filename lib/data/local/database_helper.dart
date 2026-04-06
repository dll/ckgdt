import 'dart:convert';
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
      if (kIsWeb) {
        return await _initDBWeb();
      } else {
        return await _initDBNative();
      }
    } catch (e) {
      debugPrint('=== DatabaseHelper: ERROR = $e');
      rethrow;
    }
  }

  /// Web 平台数据库初始化
  /// 使用 sqflite_common_ffi_web，数据存储在 IndexedDB 中
  Future<Database> _initDBWeb() async {
    const dbName = 'knowledge_graph.db';

    debugPrint('=== DatabaseHelper [Web]: Initializing database...');

    // 检查数据库是否已存在（IndexedDB 中）
    final exists = await databaseFactory.databaseExists(dbName);
    debugPrint('=== DatabaseHelper [Web]: Database exists = $exists');

    if (!exists) {
      // 尝试从 assets 加载预置数据库
      try {
        debugPrint('=== DatabaseHelper [Web]: Loading database from assets...');
        final data = await rootBundle.load('assets/learning_data.db');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await databaseFactory.writeDatabaseBytes(dbName, bytes);
        debugPrint('=== DatabaseHelper [Web]: Loaded database from assets (${bytes.length} bytes)');
      } catch (e) {
        debugPrint('=== DatabaseHelper [Web]: Failed to load from assets: $e');
        // 将在 openDatabase 的 onCreate 中创建空表
      }
    }

    final db = await openDatabase(
      dbName,
      version: 10,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
    debugPrint('=== DatabaseHelper [Web]: Database opened successfully');

    // 验证表和数据
    try {
      final tables = await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name']).toList();
      debugPrint('=== DatabaseHelper [Web]: Tables: $tableNames');

      // 检查关键表数据是否存在
      bool needsDataImport = false;

      // 检查 graphs 表
      if (tableNames.contains('graphs')) {
        final graphCount = await db.rawQuery('SELECT COUNT(*) as c FROM graphs');
        final count = (graphCount.first['c'] as int?) ?? 0;
        debugPrint('=== DatabaseHelper [Web]: Graphs count: $count');
        if (count == 0) needsDataImport = true;
      } else {
        needsDataImport = true;
      }

      // 检查 questions 表
      if (tableNames.contains('questions')) {
        final qCount = await db.rawQuery('SELECT COUNT(*) as c FROM questions');
        final count = (qCount.first['c'] as int?) ?? 0;
        debugPrint('=== DatabaseHelper [Web]: Questions count: $count');
        if (count == 0) needsDataImport = true;
      } else {
        needsDataImport = true;
      }

      if (needsDataImport) {
        debugPrint('=== DatabaseHelper [Web]: Data is empty, trying to reimport from assets...');
        // 关闭现有数据库，删除后重新尝试导入
        await db.close();
        await databaseFactory.deleteDatabase(dbName);

        try {
          final data = await rootBundle.load('assets/learning_data.db');
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await databaseFactory.writeDatabaseBytes(dbName, bytes);
          debugPrint('=== DatabaseHelper [Web]: Reimported from assets (${bytes.length} bytes)');
        } catch (e) {
          debugPrint('=== DatabaseHelper [Web]: Reimport failed: $e');
        }

        // 重新打开
        final db2 = await openDatabase(
          dbName,
          version: 9,
          onCreate: _createTables,
          onUpgrade: _onUpgrade,
        );

        // 确保新表存在
        await _ensureAllTables(db2);
        await _importStudents(db2);

        // 最终验证
        try {
          final gc = await db2.rawQuery('SELECT COUNT(*) as c FROM graphs');
          final qc = await db2.rawQuery('SELECT COUNT(*) as c FROM questions');
          debugPrint('=== DatabaseHelper [Web]: After reimport - Graphs: ${gc.first['c']}, Questions: ${qc.first['c']}');
        } catch (_) {}

        return db2;
      }
    } catch (e) {
      debugPrint('=== DatabaseHelper [Web]: Verification warning: $e');
    }

    // 导入学生数据
    await _importStudents(db);

    return db;
  }

  /// 原生平台数据库初始化（Android/iOS/Windows/macOS/Linux）
  Future<Database> _initDBNative() async {
    // 延迟导入 dart:io（仅在原生平台使用）
    final dbFolder = await getDatabasesPath();
    final dbPath = p.join(dbFolder, 'knowledge_graph.db');

    debugPrint('=== DatabaseHelper: Checking path: $dbPath');

    // 使用 databaseFactory 检查文件是否存在
    final exists = await databaseFactory.databaseExists(dbPath);
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
        // 使用 writeDatabaseBytes 代替 File 操作，保持平台兼容性
        await databaseFactory.writeDatabaseBytes(dbPath, bytes);
        debugPrint('=== DatabaseHelper: Copied database from assets');
      } catch (e) {
        debugPrint('=== DatabaseHelper: Failed to copy from assets: $e');
        // Create empty database
        db = await openDatabase(
          dbPath,
          version: 9,
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
      version: 10,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
    debugPrint('=== DatabaseHelper: Database opened successfully');

    // 补齐 seed DB 可能缺少的列（seed 版本为 0 时 onCreate 无法通过
    // CREATE TABLE IF NOT EXISTS 添加新列到已有表）
    await _ensureUsersColumns(db);
    await _ensureResourceFileColumns(db);

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
    await _createNewTablesV4(db);
    await _createNewTablesV5(db);
    await _createNewTablesV6(db);
    await _createNewTablesV7(db);
    await _createNewTablesV8(db);
    await _createNewTablesV9(db);
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
    if (oldVersion < 4) {
      await _createNewTablesV4(db);
    }
    if (oldVersion < 5) {
      await _createNewTablesV5(db);
    }
    if (oldVersion < 6) {
      await _createNewTablesV6(db);
    }
    if (oldVersion < 7) {
      await _createNewTablesV7(db);
    }
    if (oldVersion < 8) {
      await _createNewTablesV8(db);
    }
    if (oldVersion < 9) {
      await _createNewTablesV9(db);
    }
    if (oldVersion < 10) {
      await _createNewTablesV10(db);
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
    await _createNewTablesV4(db);
    await _createNewTablesV5(db);
    await _createNewTablesV6(db);
    await _createNewTablesV7(db);
    await _createNewTablesV8(db);
    await _createNewTablesV9(db);
    await _createNewTablesV10(db);
  }

  /// 补齐 users 表可能缺少的列（V10: repository_url）
  Future<void> _ensureUsersColumns(Database db) async {
    try {
      await db.rawQuery('SELECT repository_url FROM users LIMIT 1');
    } catch (_) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN repository_url TEXT');
        debugPrint('=== DatabaseHelper: Added repository_url column to users');
      } catch (_) {}
    }
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

  /// V4 新增: 考核管理 + 作品管理 表
  Future<void> _createNewTablesV4(Database db) async {
    // ── 考核：分组 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assessment_groups(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        leader TEXT,
        member_ids TEXT,
        member_names TEXT,
        project_name TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 考核：项目立项 ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assessment_projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER,
        name TEXT NOT NULL,
        description TEXT,
        tech_stack TEXT,
        status TEXT DEFAULT '设计阶段',
        progress REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (group_id) REFERENCES assessment_groups(id) ON DELETE SET NULL
      )
    ''');

    // ── 考核：项目评分 ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        group_id INTEGER,
        scorer_id TEXT,
        score_functionality INTEGER DEFAULT 0,
        score_tech_depth INTEGER DEFAULT 0,
        score_integration INTEGER DEFAULT 0,
        score_quality INTEGER DEFAULT 0,
        score_documentation INTEGER DEFAULT 0,
        total_score INTEGER DEFAULT 0,
        comment TEXT,
        scored_at TEXT,
        FOREIGN KEY (project_id) REFERENCES assessment_projects(id) ON DELETE CASCADE
      )
    ''');

    // ── 考核：答辩记录 ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS defense_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        project_id INTEGER,
        scheduled_time TEXT,
        location TEXT,
        duration_minutes INTEGER DEFAULT 15,
        status TEXT DEFAULT '待答辩',
        notes TEXT,
        created_at TEXT,
        FOREIGN KEY (group_id) REFERENCES assessment_groups(id) ON DELETE CASCADE
      )
    ''');

    // ── 作品管理：学生作品 ──────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_works(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        tech_stack TEXT,
        work_type TEXT DEFAULT '综合项目',
        group_name TEXT,
        leader_name TEXT,
        user_id TEXT,
        file_path TEXT,
        file_size TEXT,
        status TEXT DEFAULT '待提交',
        submit_time TEXT,
        tags TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 作品管理：作品评分 ──────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_id INTEGER NOT NULL,
        scorer_id TEXT,
        scorer_name TEXT,
        score_functionality INTEGER DEFAULT 0,
        score_tech_depth INTEGER DEFAULT 0,
        score_integration INTEGER DEFAULT 0,
        score_quality INTEGER DEFAULT 0,
        score_documentation INTEGER DEFAULT 0,
        total_score INTEGER DEFAULT 0,
        comment TEXT,
        scored_at TEXT,
        FOREIGN KEY (work_id) REFERENCES student_works(id) ON DELETE CASCADE
      )
    ''');
  }

  /// V5 新增: 班级管理 + 问卷调查 表
  Future<void> _createNewTablesV5(Database db) async {
    // ── 班级表 ──────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS classes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        semester TEXT,
        teacher_id TEXT,
        teacher_name TEXT,
        description TEXT,
        student_count INTEGER DEFAULT 0,
        is_archived INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 班级成员表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        role TEXT DEFAULT 'student',
        joined_at TEXT,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
        UNIQUE(class_id, user_id)
      )
    ''');

    // ── 问卷调查表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS surveys(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        class_id INTEGER,
        creator_id TEXT,
        status TEXT DEFAULT 'draft',
        total_responses INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        deadline TEXT
      )
    ''');

    // ── 问卷题目表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS survey_questions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        survey_id INTEGER NOT NULL,
        question TEXT NOT NULL,
        question_type TEXT DEFAULT 'single_choice',
        options_json TEXT,
        is_required INTEGER DEFAULT 1,
        seq INTEGER DEFAULT 0,
        FOREIGN KEY (survey_id) REFERENCES surveys(id) ON DELETE CASCADE
      )
    ''');

    // ── 问卷回答表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS survey_responses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        survey_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        answers_json TEXT,
        submitted_at TEXT,
        FOREIGN KEY (survey_id) REFERENCES surveys(id) ON DELETE CASCADE,
        UNIQUE(survey_id, user_id)
      )
    ''');
  }

  /// V6 新增: 教学管理（大纲+教案+教学进度）表
  Future<void> _createNewTablesV6(Database db) async {
    // ── 课程大纲表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS syllabus_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_name TEXT DEFAULT '移动应用开发',
        chapter_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        objectives TEXT,
        hours INTEGER DEFAULT 2,
        week_start INTEGER,
        week_end INTEGER,
        resources_json TEXT,
        status TEXT DEFAULT 'planned',
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 教案表 ──────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lesson_plans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter INTEGER NOT NULL,
        title TEXT NOT NULL,
        objectives TEXT,
        key_points TEXT,
        difficult_points TEXT,
        content TEXT,
        activities TEXT,
        homework TEXT,
        reflection TEXT,
        resources_json TEXT,
        ai_generated INTEGER DEFAULT 0,
        status TEXT DEFAULT 'draft',
        teacher_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 教学进度表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teaching_progress(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        chapter INTEGER NOT NULL,
        topic TEXT,
        planned_date TEXT,
        actual_date TEXT,
        status TEXT DEFAULT 'planned',
        notes TEXT,
        attendance INTEGER DEFAULT 0,
        homework_completion REAL DEFAULT 0,
        teacher_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE SET NULL
      )
    ''');
  }

  /// V7 新增: 实验任务 + 实验提交 + 报告模板 表
  Future<void> _createNewTablesV7(Database db) async {
    // ── 实验任务表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        chapter TEXT,
        description TEXT,
        requirements TEXT,
        deliverables TEXT,
        due_date TEXT,
        difficulty TEXT DEFAULT '中等',
        max_score INTEGER DEFAULT 100,
        status TEXT DEFAULT 'active',
        creator_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 实验提交表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_submissions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        content TEXT,
        file_paths TEXT,
        file_names TEXT,
        submit_time TEXT,
        status TEXT DEFAULT '已提交',
        score INTEGER,
        feedback TEXT,
        scorer_id TEXT,
        scored_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (task_id) REFERENCES lab_tasks(id) ON DELETE CASCADE
      )
    ''');

    // ── 报告模板表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT DEFAULT '实验报告',
        sections_json TEXT,
        description TEXT,
        creator_id TEXT,
        is_default INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 学生报告表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_reports(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id INTEGER,
        task_id INTEGER,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content_json TEXT,
        status TEXT DEFAULT '草稿',
        submit_time TEXT,
        score INTEGER,
        feedback TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (template_id) REFERENCES report_templates(id) ON DELETE SET NULL,
        FOREIGN KEY (task_id) REFERENCES lab_tasks(id) ON DELETE SET NULL
      )
    ''');

    // ── 协作消息表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS collaboration_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER,
        task_id INTEGER,
        sender_id TEXT NOT NULL,
        sender_name TEXT,
        message TEXT NOT NULL,
        message_type TEXT DEFAULT 'text',
        created_at TEXT
      )
    ''');

    // ── 互评记录表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS peer_reviews(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        submission_id INTEGER NOT NULL,
        reviewer_id TEXT NOT NULL,
        reviewer_name TEXT,
        score INTEGER,
        comment TEXT,
        reviewed_at TEXT,
        FOREIGN KEY (submission_id) REFERENCES lab_submissions(id) ON DELETE CASCADE,
        UNIQUE(submission_id, reviewer_id)
      )
    ''');
  }

  /// V8 新增: 课程达成度相关表
  Future<void> _createNewTablesV8(Database db) async {
    // ── 达成度评价批次表 ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievement_batches(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_name TEXT NOT NULL,
        course_name TEXT DEFAULT '移动应用开发',
        class_name TEXT DEFAULT '软件23',
        semester TEXT,
        teacher_id TEXT,
        objective_weights_json TEXT DEFAULT '{"目标1":0.15,"目标2":0.25,"目标3":0.30,"目标4":0.30}',
        assessment_weights_json TEXT DEFAULT '{"平时":0.20,"实验":0.30,"期末":0.50}',
        status TEXT DEFAULT 'draft',
        report_content TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 学生达成度分数表 ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievement_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        student_id TEXT NOT NULL,
        student_name TEXT,
        obj1_score REAL DEFAULT 0,
        obj1_achievement REAL DEFAULT 0,
        obj2_score REAL DEFAULT 0,
        obj2_achievement REAL DEFAULT 0,
        obj3_score REAL DEFAULT 0,
        obj3_achievement REAL DEFAULT 0,
        obj4_score REAL DEFAULT 0,
        obj4_achievement REAL DEFAULT 0,
        total_score REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (batch_id) REFERENCES achievement_batches(id) ON DELETE CASCADE,
        UNIQUE(batch_id, student_id)
      )
    ''');

    // ── 资源关联表（视频/PPT/PDF ↔ 大纲章节）──────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_chapter_mapping(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resource_id INTEGER,
        resource_type TEXT,
        chapter_number INTEGER NOT NULL,
        chapter_title TEXT,
        match_confidence REAL DEFAULT 1.0,
        created_at TEXT,
        FOREIGN KEY (resource_id) REFERENCES resource_files(id) ON DELETE CASCADE
      )
    ''');
  }

  /// V9 新增: 真正的知识图谱 — 知识概念 + 语义关系
  Future<void> _createNewTablesV9(Database db) async {
    // ── 知识概念表（独立于文档结构的纯知识概念节点）──────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_concepts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        concept_name TEXT NOT NULL,
        concept_type TEXT DEFAULT 'concept',
        chapter INTEGER,
        description TEXT,
        importance TEXT DEFAULT 'important',
        keywords TEXT,
        source_node_ids TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 概念间语义关系表 ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS concept_relations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_concept_id INTEGER NOT NULL,
        target_concept_id INTEGER NOT NULL,
        relation_type TEXT NOT NULL,
        relation_label TEXT,
        weight REAL DEFAULT 1.0,
        bidirectional INTEGER DEFAULT 0,
        description TEXT,
        ai_generated INTEGER DEFAULT 0,
        confidence REAL DEFAULT 1.0,
        created_at TEXT,
        FOREIGN KEY (source_concept_id) REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
        FOREIGN KEY (target_concept_id) REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
        UNIQUE(source_concept_id, target_concept_id, relation_type)
      )
    ''');
  }

  /// V10 新增: 用户表添加 repository_url 字段（Gitee 仓库地址）
  Future<void> _createNewTablesV10(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE users ADD COLUMN repository_url TEXT',
      );
    } catch (e) {
      // 列可能已存在（IF NOT EXISTS 不适用于 ALTER TABLE）
      debugPrint('V10: repository_url column may already exist: $e');
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
