/// 端到端集成测试：达成度全流程（聚合录入 → 三分项 tab → 班级平均 → 综合达成度）。
///
/// 复现并验证用户报告的 bug：成绩仅以聚合方式录入(achievement_scores)时，
/// 平时/实验/考核三个 tab 读分项表显示"暂无数据"。修复后这三个 getter 会
/// 从聚合表回填分项表，保证三个 tab 都有数据，且综合达成度计算自洽。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/local/achievement_dao.dart';
import 'package:knowledge_graph_app/presentation/pages/achievement/achievement_shared.dart';

Future<Database> _createAchievementDb() async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1),
  );
  await db.execute('''
    CREATE TABLE achievement_batches(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_name TEXT, course_name TEXT, class_name TEXT, semester TEXT,
      teacher_id TEXT, status TEXT DEFAULT 'draft',
      objective_weights_json TEXT, calc_results_json TEXT,
      created_at TEXT, updated_at TEXT)''');
  await db.execute('''
    CREATE TABLE achievement_scores(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL, student_id TEXT NOT NULL, student_name TEXT,
      obj1_score REAL DEFAULT 0, obj1_achievement REAL DEFAULT 0,
      obj2_score REAL DEFAULT 0, obj2_achievement REAL DEFAULT 0,
      obj3_score REAL DEFAULT 0, obj3_achievement REAL DEFAULT 0,
      obj4_score REAL DEFAULT 0, obj4_achievement REAL DEFAULT 0,
      total_score REAL DEFAULT 0, created_at TEXT, updated_at TEXT,
      UNIQUE(batch_id, student_id))''');
  await db.execute('''
    CREATE TABLE achievement_pingshi_scores(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL, student_id TEXT NOT NULL, student_name TEXT,
      class_activity_score REAL DEFAULT 0, class_activity_achievement REAL DEFAULT 0,
      quiz_homework_score REAL DEFAULT 0, quiz_homework_achievement REAL DEFAULT 0,
      extra_learning_score REAL DEFAULT 0, extra_learning_achievement REAL DEFAULT 0,
      total_score REAL DEFAULT 0, created_at TEXT, updated_at TEXT,
      UNIQUE(batch_id, student_id))''');
  await db.execute('''
    CREATE TABLE achievement_experiment_scores(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL, student_id TEXT NOT NULL, student_name TEXT,
      exp1_score REAL DEFAULT 0, exp2_score REAL DEFAULT 0, exp3_score REAL DEFAULT 0,
      exp4_score REAL DEFAULT 0, exp5_score REAL DEFAULT 0, exp6_score REAL DEFAULT 0,
      exp7_score REAL DEFAULT 0,
      obj1_achievement REAL DEFAULT 0, obj2_achievement REAL DEFAULT 0,
      obj3_achievement REAL DEFAULT 0, obj4_achievement REAL DEFAULT 0,
      total_score REAL DEFAULT 0, created_at TEXT, updated_at TEXT,
      UNIQUE(batch_id, student_id))''');
  await db.execute('''
    CREATE TABLE achievement_exam_scores(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL, student_id TEXT NOT NULL, student_name TEXT,
      project_score REAL DEFAULT 0, group_score REAL DEFAULT 0,
      individual_score REAL DEFAULT 0, defense_score REAL DEFAULT 0,
      obj1_achievement REAL DEFAULT 0, obj2_achievement REAL DEFAULT 0,
      obj3_achievement REAL DEFAULT 0, obj4_achievement REAL DEFAULT 0,
      total_score REAL DEFAULT 0, created_at TEXT, updated_at TEXT,
      UNIQUE(batch_id, student_id))''');
  await db.execute('''
    CREATE TABLE course_objectives(
      id INTEGER PRIMARY KEY AUTOINCREMENT, course_name TEXT, idx INTEGER,
      name TEXT, indicator TEXT, weight REAL, full_mark REAL,
      description TEXT, chapters TEXT, assess_content TEXT,
      pingshi_ratio REAL, experiment_ratio REAL, exam_ratio REAL,
      created_at TEXT, updated_at TEXT, UNIQUE(course_name, idx))''');
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AchievementDao dao;

  setUp(() async {
    db = await _createAchievementDb();
    DatabaseHelper.databaseForTest = db;
    dao = AchievementDao();
  });

  tearDown(() async {
    DatabaseHelper.databaseForTest = null;
    await db.close();
  });

  test('聚合录入后，平时/实验/考核三个分项 tab 不再"暂无数据"', () async {
    final batchId = await dao.addBatch(
      batchName: '计科22达成', courseName: '移动应用开发',
      className: '计科22', semester: '2025-2026-1', teacherId: 't1',
    );

    // 模拟"成绩管理"手动录入：仅写聚合表（addScore 路径），不写分项表
    await dao.addScore(
      batchId: batchId, studentId: '2022210332', studentName: '陈晨',
      objective1Score: 13, objective2Score: 22,
      objective3Score: 24, objective4Score: 27, totalScore: 86,
    );
    await dao.addScore(
      batchId: batchId, studentId: '2022210333', studentName: '陈创东',
      objective1Score: 12, objective2Score: 20,
      objective3Score: 21, objective4Score: 24, totalScore: 77,
    );

    // 修复前：分项表为空 → 三个 getter 返回 []（tab 显示"暂无数据"）
    // 修复后：从聚合表回填
    final pingshi = await dao.getPingshiScores(batchId);
    final experiment = await dao.getExperimentScores(batchId);
    final exam = await dao.getExamScores(batchId);

    expect(pingshi.length, 2, reason: '平时 tab 应有 2 行（从聚合回填）');
    expect(experiment.length, 2, reason: '实验 tab 应有 2 行');
    expect(exam.length, 2, reason: '考核 tab 应有 2 行');

    // 回填的达成度应与聚合一致（满分 15/25/30/30）
    final s1 = pingshi.firstWhere((r) => r['student_id'] == '2022210332');
    expect((s1['class_activity_achievement'] as num).toDouble(),
        closeTo(13 / 15, 0.001));

    // 综合达成度链路自洽：班级平均 + 加权
    final combined = await dao.calculateCombinedAchievement(batchId);
    expect(combined['combined'], isA<Map<String, double>>());
    final classAvg = await dao.calculateClassAverage(batchId);
    expect(classAvg['课程目标1'], closeTo((13 / 15 + 12 / 15) / 2, 0.001));

    // 报告链路：重算并落盘批次达成度
    final recalc = await dao.recalculateAndSaveBatch(batchId);
    expect(recalc['weighted'], isNotNull);
    expect(recalc['weighted']! > 0, isTrue);

    // 回归：三个 getter 返回的列表必须可原地排序（修复前 sqflite 只读列表
    // 会抛 "Unsupported operation: read-only"，导致 tab 显示"暂无数据"）。
    expect(() => sortScoresInPlace(pingshi, ScoreSort.totalDesc), returnsNormally);
    expect(() => sortScoresInPlace(experiment, ScoreSort.idAsc), returnsNormally);
    expect(() => sortScoresInPlace(exam, ScoreSort.totalAsc), returnsNormally);
    final aggList = await dao.getScoresByBatch(batchId);
    expect(() => sortScoresInPlace(aggList, ScoreSort.totalDesc), returnsNormally);
  });

  test('幂等：真实分项导入后，再读不会被聚合回填覆盖', () async {
    final batchId = await dao.addBatch(
      batchName: 'b', courseName: '移动应用开发',
      className: '计科22', semester: '2025-2026-1', teacherId: 't1',
    );
    // 真实分项导入：课堂 90 → 课堂达成度 0.9
    await dao.importComponentsToDatabase(batchId, {
      'pingshi': [
        {'student_id': '2022210332', 'student_name': '陈晨',
         'class_activity_score': 90.0, 'quiz_homework_score': 80.0,
         'extra_learning_score': 70.0},
      ],
      'experiment': const [],
      'exam': const [],
    });

    final pingshi = await dao.getPingshiScores(batchId);
    expect(pingshi.length, 1);
    // 应保留真实导入值 0.9，不被聚合回填覆盖
    expect((pingshi.first['class_activity_achievement'] as num).toDouble(),
        closeTo(0.9, 0.001));
  });
}
