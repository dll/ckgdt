import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/services/node_achievement_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _createDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE achievement_batches(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_name TEXT,
      course_name TEXT,
      status TEXT,
      created_at TEXT,
      updated_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE achievement_scores(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL,
      student_id TEXT NOT NULL,
      student_name TEXT,
      obj1_achievement REAL DEFAULT 0,
      obj2_achievement REAL DEFAULT 0,
      obj3_achievement REAL DEFAULT 0,
      obj4_achievement REAL DEFAULT 0,
      UNIQUE(batch_id, student_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE course_objectives(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      course_name TEXT NOT NULL,
      idx INTEGER NOT NULL,
      chapters TEXT,
      description TEXT,
      assess_content TEXT,
      experiments TEXT,
      UNIQUE(course_name, idx)
    )
  ''');
  await db.execute('''
    CREATE TABLE knowledge_concepts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      concept_name TEXT NOT NULL,
      chapter INTEGER,
      description TEXT,
      keywords TEXT
    )
  ''');
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late NodeAchievementService service;

  setUp(() async {
    db = await _createDb();
    DatabaseHelper.databaseForTest = db;
    service = NodeAchievementService();
  });

  tearDown(() async {
    DatabaseHelper.databaseForTest = null;
    await db.close();
  });

  test('syncFromAchievementScores maps students, objectives and concepts',
      () async {
    final now = DateTime.now().toIso8601String();
    final batchId = await db.insert('achievement_batches', {
      'batch_name': '计科22达成',
      'course_name': '移动应用开发',
      'status': 'completed',
      'created_at': now,
      'updated_at': now,
    });

    for (final row in [
      {'idx': 1, 'chapters': '第1章 + 第2章'},
      {'idx': 2, 'chapters': '第3章 + 第4章'},
      {'idx': 3, 'chapters': '第5章'},
      {'idx': 4, 'chapters': '第6章'},
    ]) {
      await db.insert('course_objectives', {
        'course_name': '移动应用开发',
        ...row,
      });
    }

    for (final row in [
      {'id': 101, 'concept_name': '移动应用技术体系', 'chapter': 1},
      {'id': 102, 'concept_name': 'Flutter 跨平台开发', 'chapter': 3},
      {'id': 103, 'concept_name': 'HarmonyOS 多端开发', 'chapter': 5},
      {'id': 104, 'concept_name': '综合开发实践', 'chapter': 6},
    ]) {
      await db.insert('knowledge_concepts', row);
    }

    await db.insert('achievement_scores', {
      'batch_id': batchId,
      'student_id': 's1',
      'student_name': '学生1',
      'obj1_achievement': 0.9,
      'obj2_achievement': 0.7,
      'obj3_achievement': 0.5,
      'obj4_achievement': 0.2,
    });
    await db.insert('achievement_scores', {
      'batch_id': batchId,
      'student_id': 's2',
      'student_name': '学生2',
      'obj1_achievement': 0.8,
      'obj2_achievement': 0.6,
      'obj3_achievement': 1.0,
      'obj4_achievement': 0.4,
    });

    final concepts = await db.query('knowledge_concepts', orderBy: 'id ASC');
    final synced = await service.syncFromAchievementScores(concepts: concepts);

    expect(synced, 8);

    final s1Heatmap = await service.getHeatmap(userId: 's1');
    expect(s1Heatmap[101], closeTo(90, 0.001));
    expect(s1Heatmap[102], closeTo(70, 0.001));
    expect(s1Heatmap[103], closeTo(50, 0.001));
    expect(s1Heatmap[104], closeTo(20, 0.001));

    final classHeatmap = await service.getHeatmap();
    expect(classHeatmap[101], closeTo(85, 0.001));
    expect(classHeatmap[102], closeTo(65, 0.001));
    expect(classHeatmap[103], closeTo(75, 0.001));
    expect(classHeatmap[104], closeTo(30, 0.001));
  });
}
