import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../core/init_logger.dart';
import '../../core/error_handler.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// 启动期 DB 初始化的失败摘要 — UI 可以读出来弹"数据库初始化异常"提示。
  /// null = 一切正常；非空 = 学生看到测验空白时应该向管理员报这条字符串。
  static String? lastInitError;

  DatabaseHelper._init();

  /// 仅供单元/集成测试注入内存库，绕过种子 DB 拷贝与启动迁移。
  @visibleForTesting
  static set databaseForTest(Database? db) => _database = db;

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
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await databaseFactory.writeDatabaseBytes(dbName, bytes);
        debugPrint(
            '=== DatabaseHelper [Web]: Loaded database from assets (${bytes.length} bytes)');
      } catch (e) {
        debugPrint('=== DatabaseHelper [Web]: Failed to load from assets: $e');
        // 将在 openDatabase 的 onCreate 中创建空表
      }
    }

    final db = await openDatabase(
      dbName,
      version: 30,
      singleInstance: true, // 启用单例模式
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
        final graphCount =
            await db.rawQuery('SELECT COUNT(*) as c FROM graphs');
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
        debugPrint(
            '=== DatabaseHelper [Web]: Data is empty, trying to reimport from assets...');
        // 关闭现有数据库，删除后重新尝试导入
        await db.close();
        await databaseFactory.deleteDatabase(dbName);

        try {
          final data = await rootBundle.load('assets/learning_data.db');
          final bytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await databaseFactory.writeDatabaseBytes(dbName, bytes);
          debugPrint(
              '=== DatabaseHelper [Web]: Reimported from assets (${bytes.length} bytes)');
        } catch (e) {
          debugPrint('=== DatabaseHelper [Web]: Reimport failed: $e');
        }

        // 重新打开（版本号必须与主初始化一致）
        final db2 = await openDatabase(
          dbName,
          version: 30,
          singleInstance: true, // 启用单例模式
          onCreate: _createTables,
          onUpgrade: _onUpgrade,
        );

        // 确保新表存在
        await _ensureAllTables(db2);
        await _importStudents(db2);
        await _importTeacherRoster(db2);

        // 最终验证
        try {
          final gc = await db2.rawQuery('SELECT COUNT(*) as c FROM graphs');
          final qc = await db2.rawQuery('SELECT COUNT(*) as c FROM questions');
          debugPrint(
              '=== DatabaseHelper [Web]: After reimport - Graphs: ${gc.first['c']}, Questions: ${qc.first['c']}');
        } catch (e, st) {
          swallowDebug(e, tag: 'DatabaseHelper.verifyWeb', stack: st);
        }

        return db2;
      }
    } catch (e) {
      debugPrint('=== DatabaseHelper [Web]: Verification warning: $e');
    }

    // 补齐缺失的表和列（防御：正常路径未经过 _ensureAllTables）
    await _ensureAllTables(db);
    await _importStudents(db);
    await _importTeacherRoster(db);

    return db;
  }

  /// 原生平台数据库初始化（Android/iOS/Windows/macOS/Linux）
  Future<Database> _initDBNative() async {
    final dbFolder = await getDatabasesPath();
    final dbPath = p.join(dbFolder, 'knowledge_graph.db');

    InitLogger.log('db', 'native init dbFolder=$dbFolder dbPath=$dbPath');

    final exists = await databaseFactory.databaseExists(dbPath);
    InitLogger.log('db', 'databaseExists = $exists');

    // ── 第一步：如果 DB 不存在，从 assets 复制种子 DB ──
    // 种子 DB 的 user_version 已设为 20，匹配 openDatabase version 参数，
    // 这样 sqflite 不会触发 onCreate/onUpgrade，数据原封不动保留。
    if (!exists) {
      try {
        InitLogger.log('db', 'copying seed DB from assets');
        final data = await rootBundle.load('assets/learning_data.db');
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

        // 确保目标目录存在（Windows FFI 不会自动创建）
        final dir = Directory(dbFolder);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        try {
          await databaseFactory.writeDatabaseBytes(dbPath, bytes);
        } catch (writeErr, st) {
          InitLogger.error(
              'db',
              'writeDatabaseBytes failed, fallback to direct file copy: $writeErr',
              st);
          // FFI 写入失败时回退到直接文件复制
          await File(dbPath).writeAsBytes(bytes);
        }
        InitLogger.log('db', 'seed DB copied (${bytes.length} bytes)');
      } catch (e, st) {
        // 关键失败 — 一定要让 UI 看到
        lastInitError = 'seed-copy-failed: $e';
        InitLogger.error('db', 'failed to copy seed DB: $e', st);
      }
    }

    // ── 第二步：打开数据库 ──
    Database db;
    db = await openDatabase(
      dbPath,
      version: 30,
      singleInstance: true, // 启用单例模式，防止多实例同时访问
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
    debugPrint('=== DatabaseHelper: Database opened successfully');

    // ── 第三步：补齐种子 DB 中缺少的表和列 ──
    await _ensureUsersColumns(db);
    await _ensureResourceFileColumns(db);
    await _ensureAllTables(db);

    // ── 第四步：验证关键数据 + 自动修复 ──
    await _verifyAndRepairSeedData(db);

    // Import students if needed
    await _importStudents(db);
    await _importTeacherRoster(db);

    return db;
  }

  /// 验证关键种子数据（questions/graphs/nodes/edges）是否存在，
  /// 如果为空则尝试从 asset DB 导入。
  ///
  /// **健康阈值**：questions < 30 / graphs < 5 都触发修复（种子分别是 52 / 23）。
  /// 这是为了对抗 onUpgrade 误删 / 跨设备同步异常。
  Future<void> _verifyAndRepairSeedData(Database db) async {
    try {
      final qc = await db.rawQuery('SELECT COUNT(*) as c FROM questions');
      final gc = await db.rawQuery('SELECT COUNT(*) as c FROM graphs');
      final qCount = (qc.first['c'] as int?) ?? 0;
      final gCount = (gc.first['c'] as int?) ?? 0;
      InitLogger.log('db', 'seed-check questions=$qCount graphs=$gCount');

      // 题目阈值：种子 52 道，< 30 视为异常（容忍少量删除 / 同步差异）
      // 图谱阈值：种子 23 个，< 20 视为异常（学生反馈 graphs=7 也通过了旧阈值 5
      // 但缺了 16 个图谱 → 知识图谱页大量空白；提到 20 让 _onUpgrade 误删触发修复）
      if (qCount >= 30 && gCount >= 20) return;

      InitLogger.log(
          'db', 'seed below threshold (Q<30 or G<20) — importing via SQL');
      await _importSeedDataViaSql(db);

      // 最终验证 — 修复后还是空就明确告诉 UI
      final qc2 = await db.rawQuery('SELECT COUNT(*) as c FROM questions');
      final gc2 = await db.rawQuery('SELECT COUNT(*) as c FROM graphs');
      final q2 = (qc2.first['c'] as int?) ?? 0;
      final g2 = (gc2.first['c'] as int?) ?? 0;
      InitLogger.log('db', 'after repair questions=$q2 graphs=$g2');
      if (q2 < 30 || g2 < 20) {
        lastInitError =
            'seed-repair-incomplete: questions=$q2 graphs=$g2 (expected ≥30/≥20)';
        InitLogger.log('db', lastInitError!);
      }
    } catch (e, st) {
      lastInitError = 'seed-verify-failed: $e';
      InitLogger.error('db', 'seed verify/repair error: $e', st);
    }
  }

  /// SQL 级别从 asset DB 导入种子数据（graphs/nodes/edges/questions/resource_files）
  /// 当 writeDatabaseBytes 整体复制失败时，作为健壮的回退方案：
  /// 先将 asset 写入临时文件，打开为只读连接，再逐表 INSERT 到主库。
  /// 强制从 assets 重新导入种子题库 / 图谱（UI 兜底入口）。
  /// 用户在 QuizPage 看到"暂无题目"且觉得不对时可以点这个修复。
  /// 不影响成绩 / 错题 / 学生自己的数据，只补 questions/graphs/nodes/edges/resource_files。
  Future<bool> forceReimportSeed() async {
    try {
      final db = await database;
      InitLogger.log('db', 'forceReimportSeed invoked from UI');
      await _importSeedDataViaSql(db);
      final qc = await db.rawQuery('SELECT COUNT(*) as c FROM questions');
      final gc = await db.rawQuery('SELECT COUNT(*) as c FROM graphs');
      final q = (qc.first['c'] as int?) ?? 0;
      final g = (gc.first['c'] as int?) ?? 0;
      InitLogger.log('db', 'after force-reimport questions=$q graphs=$g');
      if (q >= 30 && g >= 20) {
        lastInitError = null;
        return true;
      }
      lastInitError = 'force-reimport-incomplete: q=$q g=$g';
      return false;
    } catch (e, st) {
      lastInitError = 'force-reimport-failed: $e';
      InitLogger.error('db', 'forceReimportSeed failed: $e', st);
      return false;
    }
  }

  Future<void> _importSeedDataViaSql(Database db) async {
    try {
      InitLogger.log('db', 'SQL-level seed import starting');
      final data = await rootBundle.load('assets/learning_data.db');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      // 写入临时路径（目录已由 openDatabase 创建，不会再因目录缺失而失败）
      final dbFolder = await getDatabasesPath();
      final tempPath = p.join(dbFolder, '_seed_import_temp.db');

      try {
        await databaseFactory.writeDatabaseBytes(tempPath, bytes);
      } catch (e, st) {
        InitLogger.error('db',
            'temp writeDatabaseBytes failed, trying direct write: $e', st);
        try {
          await File(tempPath).writeAsBytes(bytes);
        } catch (e2, st2) {
          lastInitError = 'seed-temp-write-failed: $e2';
          InitLogger.error('db', 'temp seed write also failed: $e2', st2);
          return;
        }
      }

      Database seedDb;
      try {
        seedDb = await openReadOnlyDatabase(tempPath);
      } catch (e, st) {
        InitLogger.error(
            'db', 'openReadOnlyDatabase failed, trying openDatabase: $e', st);
        // FFI 后端可能不支持 openReadOnlyDatabase，回退到普通 open
        seedDb = await openDatabase(tempPath, readOnly: true);
      }

      // ── 导入 questions（schema 完全匹配，直接 insert）──
      await _importTableSafe(seedDb, db, 'questions');

      // ── 导入 graphs ──
      await _importTableSafe(seedDb, db, 'graphs');

      // ── 导入 nodes ──
      await _importTableSafe(seedDb, db, 'nodes');

      // ── 导入 edges ──
      await _importTableSafe(seedDb, db, 'edges');

      // ── 导入 resource_files（schema 可能不同，只导入匹配的列）──
      await _importTableSafe(seedDb, db, 'resource_files');

      await seedDb.close();

      // 清理临时文件
      try {
        await databaseFactory.deleteDatabase(tempPath);
      } catch (e) {
        swallow(e, tag: 'DatabaseHelper.cleanTemp');
      }

      InitLogger.log('db', 'SQL-level seed import completed');
    } catch (e, st) {
      lastInitError = 'seed-sql-import-failed: $e';
      InitLogger.error('db', 'SQL-level seed import failed: $e', st);
    }
  }

  /// 安全导入单张表：自动处理列名不匹配的情况
  Future<void> _importTableSafe(
      Database seedDb, Database targetDb, String table) async {
    try {
      final rows = await seedDb.query(table);
      if (rows.isEmpty) return;

      // 获取目标表的列名
      final targetCols = await targetDb.rawQuery('PRAGMA table_info($table)');
      final targetColNames = targetCols.map((c) => c['name'] as String).toSet();

      final batch = targetDb.batch();
      for (final row in rows) {
        // 只保留目标表中存在的列
        final filtered = <String, Object?>{};
        for (final entry in row.entries) {
          if (targetColNames.contains(entry.key)) {
            filtered[entry.key] = entry.value;
          }
        }
        if (targetColNames.contains('course_id') &&
            _isDefaultSeedCourseTable(table) &&
            ((filtered['course_id']?.toString().trim().isEmpty) ?? true)) {
          filtered['course_id'] = 'mad';
        }
        if (filtered.isNotEmpty) {
          batch.insert(table, filtered,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      await batch.commit(noResult: true);
      InitLogger.log('db', 'imported ${rows.length} rows into $table');
    } catch (e, st) {
      InitLogger.error('db', '$table import error: $e', st);
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
                'role': s['role'] ?? 'student',
                'is_active': s['is_active'] ?? 1,
                'created_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
        debugPrint(
            '=== DatabaseHelper: Students import completed (new entries merged)');

        // ── reconcile：按 students.json 校正已存在行的 is_active / real_name ──
        // ConflictAlgorithm.ignore 不会更新已存在行，导致旧库/同步里被错置成
        // is_active=1 的归档学生（计科22）永远纠不回来。这里逐行对账修正。
        await _reconcileStudents(db, students);
      } catch (e, st) {
        InitLogger.error('db', 'importing students failed: $e', st);
      }
    } catch (e, st) {
      InitLogger.error('db', 'checking students failed: $e', st);
    }
  }

  Future<void> _importTeacherRoster(Database db) async {
    try {
      final bytes = await _loadTeacherRosterBytes();
      if (bytes == null || bytes.isEmpty) {
        InitLogger.log(
            'db', 'teacher roster not found, keep existing teachers');
        return;
      }

      final excel = xl.Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return;

      var imported = 0;
      final now = DateTime.now().toIso8601String();
      final batch = db.batch();

      for (final sheet in excel.tables.values) {
        var idCol = -1;
        var nameCol = -1;
        var roleCol = -1;
        var headerRow = -1;

        for (var r = 0; r < sheet.rows.length && r < 20; r++) {
          final cells = sheet.rows[r].map(_excelText).toList();
          for (var c = 0; c < cells.length; c++) {
            final text = cells[c];
            if (text.contains('工号') || text.contains('账号')) idCol = c;
            if (text == '姓名' || text.contains('教师姓名')) nameCol = c;
            if (text.contains('角色') || text.contains('权限')) roleCol = c;
          }
          if (idCol >= 0 && nameCol >= 0) {
            headerRow = r;
            break;
          }
        }

        if (headerRow < 0) continue;
        for (var r = headerRow + 1; r < sheet.rows.length; r++) {
          final row = sheet.rows[r];
          final userId = _normalizeRosterUserId(_cellAt(row, idCol));
          final realName = _cellAt(row, nameCol).trim();
          final roleText = roleCol >= 0 ? _cellAt(row, roleCol) : '';
          if (userId.isEmpty || realName.isEmpty) continue;
          if (!RegExp(r'^\d{3,}$').hasMatch(userId)) continue;

          final role = roleText.contains('管理') ? 'admin' : 'teacher';
          final existing = await db.query(
            'users',
            columns: ['user_id'],
            where: 'user_id = ?',
            whereArgs: [userId],
            limit: 1,
          );
          final values = {
            'user_id': userId,
            'real_name': realName,
            'role': role,
            'is_active': 1,
            'created_at': now,
          };
          if (existing.isEmpty) {
            batch.insert('users', values,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            batch.update(
              'users',
              {
                'real_name': realName,
                'role': role,
                'is_active': 1,
              },
              where: 'user_id = ?',
              whereArgs: [userId],
            );
          }
          imported++;
        }
      }

      if (imported > 0) {
        await batch.commit(noResult: true);
      }
      InitLogger.log('db', 'teacher roster imported/updated=$imported');
    } catch (e, st) {
      InitLogger.error('db', 'importing teacher roster failed: $e', st);
    }
  }

  Future<Uint8List?> _loadTeacherRosterBytes() async {
    const relative = ['data', '用户', '管理员教师名单.xlsx'];
    final candidates = <String>{
      p.joinAll(relative),
      p.joinAll([Directory.current.path, ...relative]),
      p.joinAll([p.dirname(Platform.resolvedExecutable), ...relative]),
    };

    for (final path in candidates) {
      try {
        final file = File(path);
        if (await file.exists()) {
          InitLogger.log('db', 'loading teacher roster from $path');
          return Uint8List.fromList(await file.readAsBytes());
        }
      } catch (e) {
        swallow(e, tag: 'DatabaseHelper.teacherRosterFile');
      }
    }

    try {
      final data = await rootBundle.load('data/用户/管理员教师名单.xlsx');
      InitLogger.log('db', 'loading teacher roster from bundled asset');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.teacherRosterAsset');
      return null;
    }
  }

  static String _cellAt(List<xl.Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return _excelText(row[index]);
  }

  static String _excelText(xl.Data? cell) {
    final raw = cell?.value?.toString().trim() ?? '';
    if (raw.endsWith('.0')) {
      return raw.substring(0, raw.length - 2);
    }
    return raw;
  }

  static String _normalizeRosterUserId(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (value.endsWith('.0')) value = value.substring(0, value.length - 2);
    return value;
  }

  /// 按 students.json 名单对账已存在的 users 行（幂等）：
  /// 1. 校正 is_active / real_name（仅当与名单不一致时更新）；
  /// 2. 删除 `student_` 前缀幽灵行（覆盖 DB 已是最新 version、不再触发 onUpgrade 的场景）。
  Future<void> _reconcileStudents(Database db, List<dynamic> students) async {
    try {
      var fixed = 0;
      final batch = db.batch();
      for (final s in students) {
        final uid = s['user_id'] as String?;
        if (uid == null) continue;
        final desiredActive = (s['is_active'] as int?) ?? 1;
        final name = s['real_name'];
        final existing = await db.query('users',
            columns: ['is_active', 'real_name'],
            where: 'user_id = ?',
            whereArgs: [uid],
            limit: 1);
        if (existing.isEmpty) continue;
        final curActive = existing.first['is_active'] as int?;
        final curName = existing.first['real_name'] as String?;
        if (curActive != desiredActive || (name != null && curName != name)) {
          batch.update('users', {'is_active': desiredActive, 'real_name': name},
              where: 'user_id = ?', whereArgs: [uid]);
          fixed++;
        }
      }
      await batch.commit(noResult: true);

      // 双保险清幽灵（与 V27 迁移重复无害）
      final ghostCm = await db.rawDelete(
          "DELETE FROM class_members WHERE user_id LIKE 'student\\_%' ESCAPE '\\'");
      final ghostU = await db.rawDelete(
          "DELETE FROM users WHERE user_id LIKE 'student\\_%' ESCAPE '\\'");
      InitLogger.log('db',
          'reconcile students: fixed=$fixed ghost_users=$ghostU ghost_members=$ghostCm');
    } catch (e, st) {
      swallowDebug(e, tag: 'DatabaseHelper.reconcileStudents', stack: st);
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
        course_id TEXT,
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
        course_id TEXT,
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
        course_id TEXT,
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
        course_id TEXT,
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
        course_id TEXT,
        user_id TEXT NOT NULL,
        question_id INTEGER NOT NULL,
        question TEXT,
        user_answer TEXT,
        correct_answer TEXT,
        chapter TEXT,
        times INTEGER DEFAULT 1,
        wrong_time TEXT,
        last_wrong_time TEXT,
        explanation TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        user_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_title TEXT,
        favorite_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
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
    await _createNewTablesV10(db);
    await _createNewTablesV11(db);
    await _createNewTablesV12(db);
    await _migrateToV13(db);
    await _migrateToV14(db);
    await _migrateToV15(db);
    await _migrateToV16(db);
    await _migrateToV17(db);
    await _migrateToV18(db);
    await _migrateToV19(db);
    await _migrateToV20(db);
    await _migrateToV21(db);
    await _migrateToV22(db);
    await _migrateToV23(db);
    await _ensureResourceFileColumns(db);

    // Add admin user (ignore if already exists from asset DB)
    await db.insert(
        'users',
        {
          'user_id': '419116',
          'real_name': '刘老师',
          'role': 'admin',
          'created_at': DateTime.now().toIso8601String(),
          'is_active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    // Add teacher users (ignore if already exists)
    for (final t in [
      {'user_id': '206004', 'real_name': '刘东良', 'role': 'teacher'},
      {'user_id': '203014', 'real_name': '徐志红', 'role': 'teacher'},
      {'user_id': '203045', 'real_name': '黄晓玲', 'role': 'teacher'},
    ]) {
      await db.insert(
          'users',
          {
            ...t,
            'created_at': DateTime.now().toIso8601String(),
            'is_active': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 测试学生账号（ignore if already exists）
    await db.insert(
        'users',
        {
          'user_id': '2023211985',
          'real_name': '测试学生',
          'role': 'student',
          'created_at': DateTime.now().toIso8601String(),
          'is_active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    // 插入默认 AI 配置（DeepSeek），用户无需手动填写 API Key
    await db.insert(
        'ai_configs',
        {
          'id': 1,
          'provider': 'deepseek',
          'api_key': 'sk-717ef9146311424daa2fbead8ed4682b',
          'model': 'deepseek-v4-pro',
          'base_url': 'https://api.deepseek.com',
          'temperature': 0.7,
          'max_tokens': 2048,
          'timeout': 60,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint(
        '=== DatabaseHelper: Upgrading from v$oldVersion to v$newVersion');
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
    if (oldVersion < 11) {
      await _createNewTablesV11(db);
    }
    if (oldVersion < 12) {
      await _createNewTablesV12(db);
    }
    if (oldVersion < 13) {
      await _migrateToV13(db);
    }
    if (oldVersion < 14) {
      await _migrateToV14(db);
    }
    if (oldVersion < 15) {
      await _migrateToV15(db);
    }
    if (oldVersion < 16) {
      await _migrateToV16(db);
    }
    if (oldVersion < 17) {
      await _migrateToV17(db);
    }
    if (oldVersion < 18) {
      await _migrateToV18(db);
    }
    if (oldVersion < 19) {
      await _migrateToV19(db);
    }
    if (oldVersion < 20) {
      await _migrateToV20(db);
    }
    if (oldVersion < 21) {
      await _migrateToV21(db);
    }
    if (oldVersion < 22) {
      await _migrateToV22(db);
    }
    if (oldVersion < 23) {
      await _migrateToV23(db);
    }
    if (oldVersion < 24) {
      await _migrateToV24(db);
    }
    if (oldVersion < 25) {
      await _migrateToV25(db);
    }
    if (oldVersion < 26) {
      await _migrateToV26(db);
    }
    if (oldVersion < 27) {
      await _migrateToV27(db);
    }
    if (oldVersion < 28) {
      await _migrateToV28(db);
    }
    if (oldVersion < 29) {
      await _migrateToV29(db);
    }
    if (oldVersion < 30) {
      await _migrateToV30(db);
    }
    // 确保从 asset 复制的旧 DB 中缺失的表被创建（IF NOT EXISTS 安全）
    await _ensureAllTables(db);
  }

  /// 确保所有核心表存在（适用于从 asset 复制的旧版 DB 升级场景）
  Future<void> _ensureAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wrong_answers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        user_id TEXT NOT NULL,
        question_id INTEGER NOT NULL,
        question TEXT,
        user_answer TEXT,
        correct_answer TEXT,
        chapter TEXT,
        times INTEGER DEFAULT 1,
        wrong_time TEXT,
        last_wrong_time TEXT,
        explanation TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        user_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_title TEXT,
        favorite_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
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
    await _createNewTablesV11(db);
    await _createNewTablesV12(db);
    await _migrateToV13(db);
    await _migrateToV14(db);
    await _migrateToV15(db);
    await _migrateToV16(db);
    await _migrateToV17(db);
    await _migrateToV18(db);
    await _migrateToV19(db);
    await _migrateToV20(db);
    await _migrateToV21(db);
    await _migrateToV22(db);
    await _migrateToV23(db);
    await _migrateToV24(db);
    await _migrateToV26(db);
    await _migrateToV28(db);
    await _migrateToV29(db);
    await _migrateToV30(db);
    await _ensureAchievementColumns(db);
    await _ensureCourseObjectivesColumns(db);
  }

  /// 补齐 achievement_batches 表可能缺少的 calc_results_json 列
  Future<void> _ensureAchievementColumns(Database db) async {
    try {
      await db.rawQuery(
          'SELECT calc_results_json FROM achievement_batches LIMIT 1');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.ensureAchievement');
      try {
        await db.execute(
            'ALTER TABLE achievement_batches ADD COLUMN calc_results_json TEXT');
        debugPrint(
            '=== DatabaseHelper: Added calc_results_json column to achievement_batches');
      } catch (e2) {
        swallow(e2, tag: 'DatabaseHelper.alterAchievement');
      }
    }
  }

  /// 补齐 course_objectives 表可能缺少的 AI 解析列
  Future<void> _ensureCourseObjectivesColumns(Database db) async {
    for (final col in [
      'experiments',
      'pingshi_standard',
      'experiment_standard',
      'assessment_items_json',
    ]) {
      try {
        await db.rawQuery('SELECT $col FROM course_objectives LIMIT 1');
      } catch (_) {
        try {
          await db
              .execute('ALTER TABLE course_objectives ADD COLUMN $col TEXT');
        } catch (e2) {
          swallow(e2, tag: 'DatabaseHelper.alterCourseObjectives.$col');
        }
      }
    }
  }

  /// 补齐 users 表可能缺少的列（V10: repository_url）
  Future<void> _ensureUsersColumns(Database db) async {
    try {
      await db.rawQuery('SELECT repository_url FROM users LIMIT 1');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.ensureUsers');
      try {
        await db.execute('ALTER TABLE users ADD COLUMN repository_url TEXT');
        debugPrint('=== DatabaseHelper: Added repository_url column to users');
      } catch (e2) {
        swallow(e2, tag: 'DatabaseHelper.alterUsers');
      }
    }
  }

  /// 补齐 resource_files 表可能缺少的列
  Future<void> _ensureResourceFileColumns(Database db) async {
    try {
      await db.rawQuery('SELECT course_id FROM resource_files LIMIT 1');
    } catch (e) {
      try {
        await db
            .execute('ALTER TABLE resource_files ADD COLUMN course_id TEXT');
        debugPrint(
            '=== DatabaseHelper: Added course_id column to resource_files');
      } catch (e2) {
        swallow(e2, tag: 'DatabaseHelper.alterResourceCourseId');
      }
    }

    try {
      await db.rawQuery('SELECT chapter FROM resource_files LIMIT 1');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.ensureResChapter');
      try {
        await db.execute('ALTER TABLE resource_files ADD COLUMN chapter TEXT');
        debugPrint(
            '=== DatabaseHelper: Added chapter column to resource_files');
      } catch (e2) {
        swallow(e2, tag: 'DatabaseHelper.alterResChapter');
      }
    }
    try {
      await db.rawQuery('SELECT description FROM resource_files LIMIT 1');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.ensureResDesc');
      try {
        await db
            .execute('ALTER TABLE resource_files ADD COLUMN description TEXT');
        debugPrint(
            '=== DatabaseHelper: Added description column to resource_files');
      } catch (e2) {
        swallow(e2, tag: 'DatabaseHelper.alterResDesc');
      }
    }
    try {
      await db.rawQuery('SELECT source_type FROM resource_files LIMIT 1');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.ensureResSourceType');
      try {
        await db.execute(
            "ALTER TABLE resource_files ADD COLUMN source_type TEXT DEFAULT 'preset'");
        debugPrint(
            '=== DatabaseHelper: Added source_type column to resource_files');
      } catch (e2) {
        swallow(e2, tag: 'DatabaseHelper.alterResSourceType');
      }
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
        course_id TEXT,
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

    // ── 成绩录入审计日志 ──────────────────────────────────────
    // 任何成绩字段的录入/修改都写一行；只追加不改写。
    // 教师改分必填 reason，方便事后追责（CLAUDE.md "可查看可修改可审计"）。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS score_audit_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        row_id INTEGER NOT NULL,
        field TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        reason TEXT,
        scorer_id TEXT NOT NULL,
        scorer_name TEXT,
        op TEXT NOT NULL DEFAULT 'update',
        changed_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_table_row '
        'ON score_audit_log(table_name, row_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_scorer '
        'ON score_audit_log(scorer_id)');

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

    // ── 教学归档文档表 ──────────────────────────
    // V25 新增 review_json / reviewed_at / origin_doc_id 列：审核流水线持久化
    await db.execute('''
      CREATE TABLE IF NOT EXISTS archive_documents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        document_type TEXT NOT NULL,
        period TEXT NOT NULL,
        course_id TEXT,
        course_type TEXT,
        status TEXT DEFAULT 'draft',
        content TEXT,
        file_path TEXT,
        is_generated INTEGER DEFAULT 0,
        review_json TEXT DEFAULT '',
        reviewed_at TEXT DEFAULT '',
        origin_doc_id INTEGER,
        created_at TEXT,
        updated_at TEXT
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
        course_id TEXT,
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
        file_path TEXT,
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
        calc_results_json TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── 课程目标定义表（权威源：从课程大纲导入提取）──────────────
    // 权重/满分/指标点的单一来源；达成批次创建时可从此同步快照。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_objectives(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_name TEXT NOT NULL DEFAULT '移动应用开发',
        idx INTEGER NOT NULL,
        name TEXT,
        indicator TEXT,
        weight REAL DEFAULT 0,
        full_mark REAL DEFAULT 0,
        pingshi_ratio REAL DEFAULT 0.20,
        experiment_ratio REAL DEFAULT 0.30,
        exam_ratio REAL DEFAULT 0.50,
        chapters TEXT,
        description TEXT,
        assess_content TEXT,
        experiments TEXT,
        pingshi_standard TEXT,
        experiment_standard TEXT,
        assessment_items_json TEXT,
        created_at TEXT,
        updated_at TEXT,
        UNIQUE(course_name, idx)
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
        course_id TEXT,
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
        course_id TEXT,
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

  /// V11 新增: 平时/实验/期末 三类评价分项成绩表
  Future<void> _createNewTablesV11(Database db) async {
    // ── 平时成绩分项表 ──────────────────────────────────────────
    // 课堂表现→目标1, 期间测验→目标2, 课外学习→目标4
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievement_pingshi_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        student_id TEXT NOT NULL,
        student_name TEXT,
        class_activity_score REAL DEFAULT 0,
        class_activity_achievement REAL DEFAULT 0,
        quiz_homework_score REAL DEFAULT 0,
        quiz_homework_achievement REAL DEFAULT 0,
        extra_learning_score REAL DEFAULT 0,
        extra_learning_achievement REAL DEFAULT 0,
        total_score REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (batch_id) REFERENCES achievement_batches(id) ON DELETE CASCADE,
        UNIQUE(batch_id, student_id)
      )
    ''');

    // ── 实验成绩分项表 ──────────────────────────────────────────
    // 实验1-2→目标1, 实验3-4→目标2, 实验5-6→目标3, 实验7→目标4
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievement_experiment_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        student_id TEXT NOT NULL,
        student_name TEXT,
        exp1_score REAL DEFAULT 0,
        exp2_score REAL DEFAULT 0,
        exp3_score REAL DEFAULT 0,
        exp4_score REAL DEFAULT 0,
        exp5_score REAL DEFAULT 0,
        exp6_score REAL DEFAULT 0,
        exp7_score REAL DEFAULT 0,
        obj1_achievement REAL DEFAULT 0,
        obj2_achievement REAL DEFAULT 0,
        obj3_achievement REAL DEFAULT 0,
        obj4_achievement REAL DEFAULT 0,
        total_score REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (batch_id) REFERENCES achievement_batches(id) ON DELETE CASCADE,
        UNIQUE(batch_id, student_id)
      )
    ''');

    // ── 期末考核成绩分项表 ──────────────────────────────────────
    // 项目30%→目标1, 小组20%→目标2, 个人20%→目标3, 答辩30%→目标4
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievement_exam_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        student_id TEXT NOT NULL,
        student_name TEXT,
        project_score REAL DEFAULT 0,
        group_score REAL DEFAULT 0,
        individual_score REAL DEFAULT 0,
        defense_score REAL DEFAULT 0,
        obj1_achievement REAL DEFAULT 0,
        obj2_achievement REAL DEFAULT 0,
        obj3_achievement REAL DEFAULT 0,
        obj4_achievement REAL DEFAULT 0,
        total_score REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (batch_id) REFERENCES achievement_batches(id) ON DELETE CASCADE,
        UNIQUE(batch_id, student_id)
      )
    ''');

    // ── 贡献度评分表 ──────────────────────────────────────────
    // 支持自评/组员互评/教师评分，从个人/小组/项目三个维度评估
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contribution_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_user_id TEXT NOT NULL,
        target_user_name TEXT,
        scorer_user_id TEXT NOT NULL,
        scorer_user_name TEXT,
        scorer_type TEXT NOT NULL DEFAULT 'peer',
        repo TEXT,
        dimension TEXT NOT NULL DEFAULT 'individual',
        code_contribution INTEGER DEFAULT 0,
        doc_contribution INTEGER DEFAULT 0,
        teamwork_score INTEGER DEFAULT 0,
        initiative_score INTEGER DEFAULT 0,
        quality_score INTEGER DEFAULT 0,
        overall_score INTEGER DEFAULT 0,
        comment TEXT,
        scored_at TEXT,
        UNIQUE(target_user_id, scorer_user_id, dimension)
      )
    ''');
  }

  // V12 新增: 问题反馈表
  Future<void> _createNewTablesV12(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feedback(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
        user_id TEXT NOT NULL,
        user_name TEXT,
        user_role TEXT,
        page_name TEXT,
        content TEXT NOT NULL,
        suggestion TEXT,
        screenshot_path TEXT,
        status TEXT DEFAULT 'pending',
        admin_reply TEXT,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
  }

  // ── V13 迁移：密码系统 + 通知系统 ──────────────────────────────────────
  Future<void> _migrateToV13(Database db) async {
    // 密码支持
    try {
      await db.execute('ALTER TABLE users ADD COLUMN password_hash TEXT');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v13PasswordHash');
    }

    // 通知表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'manual',
        creator_id TEXT,
        target_type TEXT NOT NULL DEFAULT 'all',
        target_id TEXT,
        related_entity_type TEXT,
        related_entity_id TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_recipients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        read_at TEXT,
        FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE,
        UNIQUE(notification_id, user_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notif_recip_user
      ON notification_recipients(user_id, is_read)
    ''');

    // ── agent_call_logs：Agent LLM 调用审计日志 ─────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_call_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        agent_id TEXT NOT NULL,
        agent_name TEXT NOT NULL,
        user_id TEXT,
        session_id TEXT,
        chain_id TEXT,
        chain_step INTEGER,
        prompt_summary TEXT,
        response_summary TEXT,
        duration_ms INTEGER,
        prompt_chars INTEGER,
        response_chars INTEGER,
        provider TEXT,
        model TEXT,
        error TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agent_call_logs_agent
      ON agent_call_logs(agent_id, created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agent_call_logs_user
      ON agent_call_logs(user_id, created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agent_call_logs_chain
      ON agent_call_logs(chain_id, chain_step)
    ''');
    // 老版本表迁移 — 缺 chain_id/chain_step 列时补齐（字段顺序无所谓）
    try {
      final cols = await db.rawQuery('PRAGMA table_info(agent_call_logs)');
      final names = cols.map((r) => r['name'] as String).toSet();
      if (!names.contains('chain_id')) {
        await db
            .execute('ALTER TABLE agent_call_logs ADD COLUMN chain_id TEXT');
      }
      if (!names.contains('chain_step')) {
        await db.execute(
            'ALTER TABLE agent_call_logs ADD COLUMN chain_step INTEGER');
      }
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v13AgentCallLogs');
    }

    // ── class_qa：班级问答广场 ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_qa(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_role TEXT NOT NULL,
        class_id TEXT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        visibility TEXT NOT NULL DEFAULT 'class',
        status TEXT NOT NULL DEFAULT 'open',
        accepted_reply_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_class_qa_status
      ON class_qa(class_id, status, updated_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_qa_replies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        qa_id INTEGER NOT NULL,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_role TEXT NOT NULL,
        body TEXT NOT NULL,
        is_teacher INTEGER NOT NULL DEFAULT 0,
        likes INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (qa_id) REFERENCES class_qa(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_class_qa_replies_qa
      ON class_qa_replies(qa_id, created_at ASC)
    ''');

    // ── rag_embeddings：向量化 RAG（纯 Dart 余弦相似度版） ───────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rag_embeddings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id TEXT NOT NULL,
        chunk_id TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding BLOB NOT NULL,
        dim INTEGER NOT NULL,
        meta TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rag_embeddings_doc
      ON rag_embeddings(doc_id, dim)
    ''');
  }

  // ── V14 迁移：AI 配置扩展 + 聊天历史 ──────────────────────────────────────
  Future<void> _migrateToV14(Database db) async {
    // 为 ai_configs 表添加新列
    try {
      await db.execute(
          'ALTER TABLE ai_configs ADD COLUMN temperature REAL DEFAULT 0.7');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v14Temperature');
    }
    try {
      await db.execute(
          'ALTER TABLE ai_configs ADD COLUMN max_tokens INTEGER DEFAULT 2048');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v14MaxTokens');
    }
    try {
      await db.execute(
          'ALTER TABLE ai_configs ADD COLUMN timeout INTEGER DEFAULT 60');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v14Timeout');
    }

    // 创建 AI 聊天历史表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_chat_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        agent_id TEXT,
        skill_id TEXT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        tokens_used INTEGER DEFAULT 0,
        starred INTEGER DEFAULT 0,
        title TEXT
      )
    ''');

    // 如果 ai_configs 为空，插入默认 DeepSeek 配置
    final existing =
        await db.query('ai_configs', where: 'id = ?', whereArgs: [1]);
    if (existing.isEmpty) {
      await db.insert(
          'ai_configs',
          {
            'id': 1,
            'provider': 'deepseek',
            'api_key': 'sk-717ef9146311424daa2fbead8ed4682b',
            'model': 'deepseek-v4-pro',
            'base_url': 'https://api.deepseek.com',
            'temperature': 0.7,
            'max_tokens': 2048,
            'timeout': 60,
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 确保 V22 Token 列存在（防御：_ensureAllTables 可能跳过 _onUpgrade）
    await _migrateToV22(db);
    await _migrateToV23(db);
  }

  Future<void> _migrateToV15(Database db) async {
    // 创建课程表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS courses(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        chapter_count INTEGER DEFAULT 6,
        chapters TEXT,
        is_active INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 插入默认课程（移动应用开发）
    final existing =
        await db.query('courses', where: 'id = ?', whereArgs: ['mad']);
    if (existing.isEmpty) {
      await db.insert(
          'courses',
          {
            'id': 'mad',
            'name': '移动应用开发',
            'description': '涵盖 Android、iOS、Flutter、小程序、HarmonyOS 等移动应用开发技术',
            'chapter_count': 6,
            'chapters':
                '["移动应用开发技术体系全景","Android 与 iOS 原生开发基础","Flutter、React Native 等混合开发技术","微信小程序开发流程","华为 HarmonyOS 多端应用开发","综合开发实践"]',
            'is_active': 1,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// V16: ai_chat_history 新增 starred / title 列
  Future<void> _migrateToV16(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE ai_chat_history ADD COLUMN starred INTEGER DEFAULT 0',
      );
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v16Starred');
    }
    try {
      await db.execute(
        'ALTER TABLE ai_chat_history ADD COLUMN title TEXT',
      );
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v16Title');
    }
  }

  Future<void> _migrateToV17(Database db) async {
    // 错题 AI 解释字段
    try {
      await db.execute(
        'ALTER TABLE wrong_answers ADD COLUMN explanation TEXT',
      );
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v17Explanation');
    }
  }

  Future<void> _migrateToV18(Database db) async {
    // student_reports 增加 file_path 列（考核报告 PDF 路径）
    try {
      await db.execute(
        'ALTER TABLE student_reports ADD COLUMN file_path TEXT',
      );
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v18FilePath');
    }
  }

  Future<void> _migrateToV19(Database db) async {
    // 教师申请审核表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teacher_applications(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        applicant_id TEXT NOT NULL,
        applicant_name TEXT,
        work_id TEXT NOT NULL,
        school TEXT,
        reason TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        reviewer_id TEXT,
        review_comment TEXT,
        reviewed_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateToV20(Database db) async {
    // ── 字段扩展（try/catch 防重复 ALTER）──
    final alters = [
      'ALTER TABLE lab_tasks ADD COLUMN related_node_ids TEXT',
      'ALTER TABLE lab_submissions ADD COLUMN ai_suspicion REAL DEFAULT 0',
      'ALTER TABLE lab_submissions ADD COLUMN ai_evidence TEXT',
      'ALTER TABLE lab_submissions ADD COLUMN teacher_confirmed INTEGER DEFAULT 0',
      'ALTER TABLE student_works ADD COLUMN related_node_ids TEXT',
      'ALTER TABLE student_works ADD COLUMN ai_suspicion REAL DEFAULT 0',
      'ALTER TABLE student_works ADD COLUMN teacher_confirmed INTEGER DEFAULT 0',
      'ALTER TABLE project_scores ADD COLUMN teacher_confirmed INTEGER DEFAULT 0',
      'ALTER TABLE questions ADD COLUMN node_id INTEGER',
    ];
    for (final sql in alters) {
      try {
        await db.execute(sql);
      } catch (e) {
        swallow(e, tag: 'DatabaseHelper.v20AlterLoop');
      }
    }

    // ── 新表：数字孪生快照（保留历史用于趋势对比）──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS twin_snapshots(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        role TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        generated_at TEXT NOT NULL
      )
    ''');
    // 迁移：若旧表有 UNIQUE(user_id) 约束则无需删除，改为追加模式
    // 为查询性能添加索引
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_twin_snap_user ON twin_snapshots(user_id, generated_at DESC)');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v20TwinIndex');
    }

    // ── 新表：作品同行评审 ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_peer_reviews(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_id INTEGER NOT NULL,
        reviewer_id TEXT NOT NULL,
        score INTEGER NOT NULL,
        comment TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(work_id, reviewer_id)
      )
    ''');

    // ── 新表：抄袭/AI 特征检测记录 ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS plagiarism_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_type TEXT NOT NULL,
        source_id INTEGER NOT NULL,
        similarity_max REAL,
        similar_with TEXT,
        ai_likelihood REAL,
        detected_at TEXT NOT NULL
      )
    ''');

    // ── 新表：节点级达成度（物化聚合）──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS node_achievement(
        user_id TEXT NOT NULL,
        node_id INTEGER NOT NULL,
        quiz_score REAL,
        lab_score REAL,
        work_score REAL,
        overall REAL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(user_id, node_id)
      )
    ''');
  }

  Future<void> _migrateToV21(Database db) async {
    // ── 热门视频 ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hot_videos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        platform TEXT NOT NULL,
        video_url TEXT NOT NULL,
        title TEXT NOT NULL,
        thumbnail_url TEXT,
        description TEXT,
        view_count TEXT,
        duration TEXT,
        source TEXT,
        publish_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // ── 热门视频收藏（用户维度）──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hot_video_favorites(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        video_id INTEGER NOT NULL,
        favorite_time TEXT NOT NULL,
        FOREIGN KEY (video_id) REFERENCES hot_videos(id) ON DELETE CASCADE,
        UNIQUE(user_id, video_id)
      )
    ''');
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_hot_videos_platform ON hot_videos(platform)');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v21IdxPlatform');
    }
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_hot_video_fav_user ON hot_video_favorites(user_id)');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v21IdxFavUser');
    }

    // 预置推荐视频种子数据（替换旧的系统种子，确保URL始终为最新验证版本）
    await db.delete('hot_videos', where: "user_id = ?", whereArgs: ['system']);
    {
      final now = DateTime.now().toIso8601String();
      final seeds = [
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1BFCsBrEy7',
          '【2025重置版】一小时从零基础到精通Flutter基础入门教程',
          '技术UP主',
          '54集系统教程：Dart语法→Widget→路由→动画→项目实战，2025年全新录制',
          '25万',
          '10:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1Qb421Y7SV',
          '《2025 Flutter实战开发》从环境搭建到打包发布',
          'Flutter实战派',
          '33集完整实战：Dio网络请求、Provider状态管理、路由封装、登录注册、WebView',
          '18万',
          '8:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1Cyx7ziE3v',
          'Jetpack Compose 构建Android应用（2025最新版）',
          'Android开发者',
          'Kotlin+Jetpack Compose声明式UI开发，从零构建完整Android应用',
          '12万',
          '6:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1Sa4y1Z7B1',
          '黑马程序员HarmonyOS4+NEXT星河版入门到企业级实战教程',
          '黑马程序员',
          '50节课覆盖ArkTS语法、ArkUI组件、状态管理、动画、网络、数据库、实战案例',
          '42万',
          '20:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV12gYxz7Ews',
          '【提供真实接口】2026 React Native + Expo 零基础到项目实战教程',
          '长乐未央',
          '68+集全栈教程：Expo Router、登录认证、视频播放器、iOS 26适配、打包上架',
          '8万',
          '15:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1834y1676P',
          '黑马程序员微信小程序从基础到发布全流程（含uni-app多端部署）',
          '黑马程序员',
          '422万播放：小程序基础→组件→API→云开发→企业级商城实战→uni-app多端部署',
          '422万',
          '30:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1Bp4y1379L',
          '黑马程序员uniapp小兔鲜儿微信小程序项目（Vue3+TS+Pinia+uni-app）',
          '黑马程序员',
          '最新技术栈：Vue3+TypeScript+Pinia+uni-app开发电商全流程',
          '15万',
          '12:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1S4411E7LY',
          'Flutter从入门到精通全套（Dart+Flutter 3.x+GetX+仿小米商城）',
          'IT营大地老师',
          '全网最全Flutter教程之一：Dart基础+Widget+GetX状态管理+真实API项目实战',
          '35万',
          '40:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1er421G7TV',
          '鸿蒙NEXT教程：ArkTS/ArkUI全套 零基础入门到项目实战',
          '鸿蒙开发讲师',
          'ArkTS基础+ArkUI组件+3个实战项目，零基础也能学会鸿蒙开发',
          '20万',
          '16:00:00'
        ],
        [
          'system',
          'bilibili',
          'https://www.bilibili.com/video/BV1CG4tzAEc6',
          'Flutter从零开始开发旅游APP（135集实战）',
          'Flutter旅游实战',
          '135集大体量：Dart语法→网络请求→混合开发→AI语音搜索→打包发布',
          '22万',
          '30:00:00'
        ],
      ];
      for (final s in seeds) {
        await db.insert('hot_videos', {
          'user_id': s[0],
          'platform': s[1],
          'video_url': s[2],
          'title': s[3],
          'source': s[4],
          'description': s[5],
          'view_count': s[6],
          'duration': s[7],
          'created_at': now,
        });
      }
    }
  }

  /// V22: ai_chat_history 新增 prompt_tokens / completion_tokens / provider / model 列
  Future<void> _migrateToV22(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE ai_chat_history ADD COLUMN prompt_tokens INTEGER DEFAULT 0');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v22PromptTokens');
    }
    try {
      await db.execute(
          'ALTER TABLE ai_chat_history ADD COLUMN completion_tokens INTEGER DEFAULT 0');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v22CompletionTokens');
    }
    try {
      await db.execute('ALTER TABLE ai_chat_history ADD COLUMN provider TEXT');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v22Provider');
    }
    try {
      await db.execute('ALTER TABLE ai_chat_history ADD COLUMN model TEXT');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v22Model');
    }
  }

  /// V25: archive_documents 新增 review_json + status 流转列（commit 4 审核流水线）
  Future<void> _migrateToV25(Database db) async {
    try {
      await db.execute(
          "ALTER TABLE archive_documents ADD COLUMN review_json TEXT DEFAULT ''");
    } catch (e) {
      swallow(e, tag: 'V25.add_review_json'); // 列已存在是常态，吞掉
    }
    try {
      await db.execute(
          "ALTER TABLE archive_documents ADD COLUMN reviewed_at TEXT DEFAULT ''");
    } catch (e) {
      swallow(e, tag: 'V25.add_reviewed_at');
    }
    // origin_doc_id：审核表所属的源文档 ID（如 syllabus_review 指向源 syllabus 的 ID）
    // 让我们能查询"教学大纲 #5 对应的审核表是哪份"。
    try {
      await db.execute(
          'ALTER TABLE archive_documents ADD COLUMN origin_doc_id INTEGER');
    } catch (e) {
      swallow(e, tag: 'V25.add_origin_doc_id');
    }
  }

  /// V26: current_session 增加 default_class_id（默认班级）
  Future<void> _migrateToV26(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE current_session ADD COLUMN default_class_id INTEGER');
    } catch (e) {
      swallow(e, tag: 'V26.add_default_class_id');
    }
  }

  /// V27: 清理种子库残留的 49 行 `student_` 前缀幽灵学生。
  ///
  /// 这些行是已归档「计科22」队列的重复副本，却被标记为 is_active=1，
  /// 能穿过所有 is_active 过滤，导致答辩名单等处混入归档学生。
  /// 真实登录/导入/同步流程从不创建 `student_` 前缀的 user_id，故可安全删除。
  Future<void> _migrateToV27(Database db) async {
    try {
      final cm = await db.rawDelete(
          "DELETE FROM class_members WHERE user_id LIKE 'student\\_%' ESCAPE '\\'");
      final u = await db.rawDelete(
          "DELETE FROM users WHERE user_id LIKE 'student\\_%' ESCAPE '\\'");
      InitLogger.log('db', 'V27 purge ghost: users=$u class_members=$cm');
    } catch (e, st) {
      swallowDebug(e, tag: 'V27.purge_ghost', stack: st);
    }
  }

  /// V28: archive_documents 绑定统一课程 ID，归档资料不再靠考试/考查类型识别。
  Future<void> _migrateToV28(Database db) async {
    try {
      await db
          .execute('ALTER TABLE archive_documents ADD COLUMN course_id TEXT');
    } catch (e) {
      swallow(e, tag: 'V28.add_archive_course_id');
    }
    try {
      await db.execute('''
        UPDATE archive_documents
        SET course_id = (SELECT id FROM courses WHERE is_active = 1 LIMIT 1)
        WHERE course_id IS NULL OR course_id = ''
      ''');
    } catch (e, st) {
      swallowDebug(e, tag: 'V28.backfill_archive_course_id', stack: st);
    }
  }

  bool _isDefaultSeedCourseTable(String table) {
    return const {
      'graphs',
      'questions',
      'resource_files',
      'generated_materials',
      'puml_files',
    }.contains(table);
  }

  /// V29: 知识概念图谱绑定统一课程 ID。
  ///
  /// 平台从单一《移动应用开发》扩展为多课程后，`knowledge_concepts` 不能再
  /// 全局共用。旧种子数据回填到当前激活课程；后续新课程会按 course_id 隔离。
  Future<void> _migrateToV29(Database db) async {
    try {
      await db
          .execute('ALTER TABLE knowledge_concepts ADD COLUMN course_id TEXT');
    } catch (e) {
      swallow(e, tag: 'V29.add_concept_course_id');
    }
    try {
      await db
          .execute('ALTER TABLE concept_relations ADD COLUMN course_id TEXT');
    } catch (e) {
      swallow(e, tag: 'V29.add_relation_course_id');
    }
    try {
      await db.execute('''
        UPDATE knowledge_concepts
        SET course_id = (SELECT id FROM courses WHERE is_active = 1 LIMIT 1)
        WHERE course_id IS NULL OR course_id = ''
      ''');
    } catch (e, st) {
      swallowDebug(e, tag: 'V29.backfill_concept_course_id', stack: st);
    }
    try {
      await db.execute('''
        UPDATE concept_relations
        SET course_id = (
          SELECT kc.course_id
          FROM knowledge_concepts kc
          WHERE kc.id = concept_relations.source_concept_id
          LIMIT 1
        )
        WHERE course_id IS NULL OR course_id = ''
      ''');
    } catch (e, st) {
      swallowDebug(e, tag: 'V29.backfill_relation_course_id', stack: st);
    }
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_knowledge_concepts_course ON knowledge_concepts(course_id, chapter)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_concept_relations_course ON concept_relations(course_id)');
    } catch (e) {
      swallow(e, tag: 'V29.index_course_graph');
    }
  }

  /// V30: 平台化课程作用域。
  ///
  /// 题库、学习记录、错题、收藏、资源、实验、生成课件和文档式图谱都绑定课程。
  /// 可识别的历史数据按课程回填；无法识别的旧种子数据归入默认 `mad`。
  Future<void> _migrateToV30(Database db) async {
    for (final table in const [
      'graphs',
      'questions',
      'quiz_results',
      'learning_records',
      'wrong_answers',
      'favorites',
      'resource_files',
      'lab_tasks',
      'generated_materials',
      'puml_files',
      'student_works',
      'learning_paths',
    ]) {
      await _addTextColumnIfMissing(db, table, 'course_id', 'V30.$table');
    }

    await _backfillGraphsByCourseId(db);
    await _backfillCourseTablesByKnownChapters(db);
    await _backfillResourcesByCourseName(db);

    for (final table in const [
      'graphs',
      'questions',
      'quiz_results',
      'learning_records',
      'wrong_answers',
      'favorites',
      'resource_files',
      'lab_tasks',
      'generated_materials',
      'puml_files',
      'student_works',
      'learning_paths',
    ]) {
      await _backfillDefaultCourseId(db, table);
    }

    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_graphs_course ON graphs(course_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_questions_course_source ON questions(course_id, source)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_quiz_results_course_user ON quiz_results(course_id, user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_learning_records_course_user ON learning_records(course_id, user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_wrong_answers_course_user ON wrong_answers(course_id, user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_favorites_course_user ON favorites(course_id, user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_resource_files_course_chapter ON resource_files(course_id, chapter)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_lab_tasks_course ON lab_tasks(course_id, chapter)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_generated_materials_course ON generated_materials(course_id, chapter)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_puml_files_course ON puml_files(course_id, chapter)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_student_works_course_user ON student_works(course_id, user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_learning_paths_course_user ON learning_paths(course_id, user_id)');
    } catch (e) {
      swallow(e, tag: 'V30.index_course_scope');
    }
  }

  Future<void> _addTextColumnIfMissing(
    Database db,
    String table,
    String column,
    String tag,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
    } catch (e) {
      swallow(e, tag: '$tag.add_$column');
    }
  }

  Future<void> _backfillDefaultCourseId(Database db, String table) async {
    try {
      await db.execute('''
        UPDATE $table
        SET course_id = 'mad'
        WHERE course_id IS NULL OR course_id = ''
      ''');
    } catch (e, st) {
      swallowDebug(e, tag: 'V30.backfill_default_$table', stack: st);
    }
  }

  Future<void> _backfillGraphsByCourseId(Database db) async {
    try {
      await db.execute('''
        UPDATE graphs
        SET course_id = (
          SELECT c.id FROM courses c WHERE graphs.id = 'g_' || c.id LIMIT 1
        )
        WHERE course_id IS NULL OR course_id = ''
      ''');
    } catch (e, st) {
      swallowDebug(e, tag: 'V30.backfill_graphs_by_course_id', stack: st);
    }
  }

  Future<void> _backfillResourcesByCourseName(Database db) async {
    try {
      final courses = await db.query('courses');
      for (final course in courses) {
        final id = course['id']?.toString() ?? '';
        final name = course['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        await db.update(
          'resource_files',
          {'course_id': id},
          where:
              "(course_id IS NULL OR course_id = '') AND (description LIKE ? OR file_name LIKE ?)",
          whereArgs: ['$name - %', '%$name%'],
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'V30.backfill_resources_by_name', stack: st);
    }
  }

  Future<void> _backfillCourseTablesByKnownChapters(Database db) async {
    try {
      final courses = await db.query('courses');
      for (final course in courses) {
        final courseId = course['id']?.toString() ?? '';
        if (courseId.isEmpty) continue;
        final chapters = _parseCourseChaptersForMigration(course);
        for (var i = 0; i < chapters.length; i++) {
          final chapterNo = i + 1;
          final variants = <String>{
            chapters[i],
            _formatChapterForMigration(chapters[i], chapterNo),
            if (courseId == 'mad') '第$chapterNo章',
          }..removeWhere((s) => s.trim().isEmpty);

          for (final source in variants) {
            await _backfillByTextMatch(
              db,
              table: 'questions',
              column: 'source',
              courseId: courseId,
              value: source,
            );
            await _backfillByTextMatch(
              db,
              table: 'quiz_results',
              column: 'chapter',
              courseId: courseId,
              value: source,
            );
            await _backfillByTextMatch(
              db,
              table: 'generated_materials',
              column: 'chapter',
              courseId: courseId,
              value: source,
            );
            await _backfillByTextMatch(
              db,
              table: 'puml_files',
              column: 'chapter',
              courseId: courseId,
              value: source,
            );
            await _backfillByTextMatch(
              db,
              table: 'lab_tasks',
              column: 'chapter',
              courseId: courseId,
              value: source,
            );
            await _backfillByTextMatch(
              db,
              table: 'resource_files',
              column: 'chapter',
              courseId: courseId,
              value: source,
            );
          }
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'V30.backfill_by_chapters', stack: st);
    }
  }

  Future<void> _backfillByTextMatch(
    Database db, {
    required String table,
    required String column,
    required String courseId,
    required String value,
  }) async {
    try {
      await db.update(
        table,
        {'course_id': courseId},
        where: "(course_id IS NULL OR course_id = '') AND $column = ?",
        whereArgs: [value],
      );
    } catch (e) {
      swallow(e, tag: 'V30.backfill_${table}_$column');
    }
  }

  List<String> _parseCourseChaptersForMigration(Map<String, Object?> course) {
    final raw = course['chapters']?.toString().trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final chapters = decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (chapters.isNotEmpty) return chapters;
        }
      } catch (_) {
        final chapters = raw
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (chapters.isNotEmpty) return chapters;
      }
    }
    final count = (course['chapter_count'] as int?) ?? 6;
    return List.generate(count, (i) => '第${i + 1}章');
  }

  String _formatChapterForMigration(String raw, int index) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '第$index章';
    if (RegExp(r'^第\s*[一二三四五六七八九十百\d]+\s*章').hasMatch(trimmed)) {
      return trimmed;
    }
    return '第$index章 $trimmed';
  }

  /// V24: ai_chat_history 性能索引（Token 统计查询用）
  Future<void> _migrateToV24(Database db) async {
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_role_date ON ai_chat_history(role, created_at DESC)');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v24IdxRoleDate');
    }
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_role_user ON ai_chat_history(role, user_id)');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v24IdxRoleUser');
    }
  }

  /// V23: ai_chat_history 新增 user_id 列 + grading_results 表
  Future<void> _migrateToV23(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE ai_chat_history ADD COLUMN user_id TEXT DEFAULT \'\'');
    } catch (e) {
      swallow(e, tag: 'DatabaseHelper.v23UserId');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grading_results(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        domain TEXT NOT NULL,
        target_id INTEGER NOT NULL,
        scorer_id TEXT NOT NULL,
        model_provider TEXT,
        model_name TEXT,
        raw_json TEXT,
        score REAL,
        feedback TEXT,
        dimensions TEXT,
        strengths TEXT,
        improvements TEXT,
        ai_flag INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending',
        created_at TEXT,
        approved_at TEXT,
        approved_by TEXT
      )
    ''');
  }

  Future<void> _createNewTablesV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS learning_paths(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT,
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
        course_id TEXT,
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
        course_id TEXT,
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
        model TEXT DEFAULT 'deepseek-v4-pro',
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
