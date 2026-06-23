/// 端到端集成测试：达成度全流程（聚合录入 → 三分项 tab → 班级平均 → 综合达成度）。
///
/// 复现并验证用户报告的 bug：成绩仅以聚合方式录入(achievement_scores)时，
/// 平时/实验/考核三个 tab 读分项表显示"暂无数据"。修复后这三个 getter 会
/// 从聚合表回填分项表，保证三个 tab 都有数据，且综合达成度计算自洽。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart' as xl;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/local/achievement_dao.dart';
import 'package:knowledge_graph_app/presentation/pages/achievement/achievement_shared.dart';
import 'package:knowledge_graph_app/services/achievement/achievement_excel_service.dart';

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
      report_content TEXT,
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
      assessment_items_json TEXT,
      created_at TEXT, updated_at TEXT, UNIQUE(course_name, idx))''');
  await db.execute('''
    CREATE TABLE courses(
      id TEXT PRIMARY KEY, name TEXT, description TEXT, chapter_count INTEGER,
      chapters TEXT, is_active INTEGER, created_at TEXT)''');
  await db.insert('courses', {
    'id': 'mad',
    'name': '移动应用开发',
    'description': '',
    'chapter_count': 6,
    'chapters': '[]',
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00',
  });
  await db.execute('''
    CREATE TABLE users(
      user_id TEXT PRIMARY KEY, real_name TEXT, role TEXT,
      is_active INTEGER DEFAULT 1)''');
  await db.execute('''
    CREATE TABLE classes(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT,
      is_archived INTEGER DEFAULT 0)''');
  await db.execute('''
    CREATE TABLE class_members(
      id INTEGER PRIMARY KEY AUTOINCREMENT, class_id INTEGER,
      user_id TEXT, role TEXT DEFAULT 'student')''');
  await db.execute('''
    CREATE TABLE quiz_results(
      id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, user_id TEXT,
      score INTEGER, num_correct INTEGER, num_total INTEGER,
      chapter TEXT, quiz_timestamp TEXT, completed_at TEXT)''');
  await db.execute('''
    CREATE TABLE learning_records(
      id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, user_id TEXT,
      node_id TEXT, node_title TEXT, study_time TEXT, completed_at TEXT)''');
  await db.execute('''
    CREATE TABLE resource_files(
      id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, file_name TEXT,
      file_type TEXT, source_type TEXT)''');
  await db.execute('''
    CREATE TABLE ai_chat_history(
      id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, role TEXT,
      content TEXT, created_at TEXT, tokens_used INTEGER DEFAULT 0,
      user_id TEXT)''');
  await db.execute('''
    CREATE TABLE hot_video_favorites(
      id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT, video_id INTEGER,
      favorite_time TEXT)''');
  await db.execute('''
    CREATE TABLE lab_tasks(
      id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT, title TEXT,
      chapter TEXT, max_score INTEGER DEFAULT 100, status TEXT DEFAULT 'active')''');
  await db.execute('''
    CREATE TABLE lab_submissions(
      id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER, user_id TEXT,
      status TEXT, score INTEGER, submit_time TEXT)''');
  await db.execute('''
    CREATE TABLE assessment_reports(
      id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER, user_id TEXT,
      title TEXT, content_json TEXT, file_path TEXT, status TEXT,
      submit_time TEXT, score INTEGER, feedback TEXT, review_json TEXT,
      reviewed_at TEXT, reviewer_id TEXT, printed_at TEXT,
      print_count INTEGER DEFAULT 0, print_settings_json TEXT,
      created_at TEXT, updated_at TEXT)''');
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

  test('无实验课程动态成绩模板不生成实验列，并按大纲比例合成达成度', () {
    final objectiveRows = [
      for (var i = 1; i <= 3; i++)
        {
          'idx': i,
          'name': '课程目标$i',
          'indicator': '$i.1',
          'weight': i == 1 ? 0.3 : (i == 2 ? 0.3 : 0.4),
          'full_mark': 100.0,
          'description': '目标$i',
          'pingshi_ratio': 0.4,
          'experiment_ratio': 0.0,
          'exam_ratio': 0.6,
        }
    ];

    final templateBytes = AchievementExcelService.instance.buildGradeTemplate(
      objectiveRows: objectiveRows,
      students: const [
        {'student_id': '2023001', 'student_name': '张三'}
      ],
    );
    final workbook = xl.Excel.decodeBytes(templateBytes);
    final sheet = workbook.tables['成绩录入']!;
    final headers =
        sheet.rows.first.map((cell) => cell?.value?.toString() ?? '').toList();

    expect(headers.any((h) => h.contains('实验')), isFalse,
        reason: '无实验课程的成绩录入模板不能出现实验列');
    expect(headers.where((h) => h.contains('平时成绩')).length, 3);
    expect(headers.where((h) => h.contains('考核成绩')).length, 3);

    for (var c = 2; c < headers.length; c++) {
      final score = headers[c].contains('平时成绩') ? 80.0 : 90.0;
      sheet.updateCell(
        xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1),
        xl.DoubleCellValue(score),
      );
    }

    final filled = workbook.save()!;
    final parsed = AchievementExcelService.instance.parseDynamicGradeTemplate(
      Uint8List.fromList(filled),
      objectiveRows: objectiveRows,
    );
    expect(parsed.length, 1);
    for (var i = 1; i <= 3; i++) {
      expect((parsed.first['obj${i}_achievement'] as num).toDouble(),
          closeTo(0.86, 0.0001));
    }
    expect((parsed.first['obj4_achievement'] as num).toDouble(), 0);
  });

  test('无实验三目标课程不输出实验建议，也不暴露目标4', () async {
    const courseName = '大学英语';
    for (var i = 1; i <= 3; i++) {
      await db.insert('course_objectives', {
        'course_name': courseName,
        'idx': i,
        'name': '课程目标$i',
        'indicator': '$i.1',
        'weight': i == 1 ? 0.3 : (i == 2 ? 0.3 : 0.4),
        'full_mark': 100.0,
        'description': '英语课程目标$i',
        'chapters': '单元$i',
        'assess_content': '平时表现、期末考核',
        'pingshi_ratio': 0.4,
        'experiment_ratio': 0.0,
        'exam_ratio': 0.6,
      });
    }
    final batchId = await dao.addBatch(
      batchName: '英语无实验达成',
      courseName: courseName,
      className: '英语23',
      semester: '2025-2026-2',
      teacherId: 't1',
    );
    await dao.addScore(
      batchId: batchId,
      studentId: '2023001',
      studentName: '张三',
      objective1Score: 86,
      objective2Score: 82,
      objective3Score: 78,
      objective4Score: 0,
      totalScore: 82,
    );

    final avg = await dao.calculateClassAverage(batchId);
    expect(avg.keys, containsAll(['课程目标1', '课程目标2', '课程目标3']));
    expect(avg.containsKey('课程目标4'), isFalse);

    final combined = await dao.calculateCombinedAchievement(batchId);
    expect((combined['experiment'] as Map), isEmpty);

    final suggestions = await dao.generateImprovementSuggestions(batchId);
    expect(suggestions.where((s) => s['objectiveIndex'] != -1).length, 3);
    final suggestionText = suggestions
        .expand((s) => ((s['actions'] as List?) ?? const []).cast<String>())
        .join('\n');
    expect(suggestionText.contains('实验课时'), isFalse);
    expect(suggestionText.contains('实验项目'), isFalse);

    final report = await dao.generateMarkdownReport(batchId);
    expect(report.contains('课程目标4'), isFalse);
  });

  test('聚合录入后，平时/实验/考核三个分项 tab 不再"暂无数据"', () async {
    final batchId = await dao.addBatch(
      batchName: '计科22达成',
      courseName: '移动应用开发',
      className: '计科22',
      semester: '2025-2026-1',
      teacherId: 't1',
    );

    // 模拟"成绩管理"手动录入：仅写聚合表（addScore 路径），不写分项表
    await dao.addScore(
      batchId: batchId,
      studentId: '2022210332',
      studentName: '陈晨',
      objective1Score: 13,
      objective2Score: 22,
      objective3Score: 24,
      objective4Score: 27,
      totalScore: 86,
    );
    await dao.addScore(
      batchId: batchId,
      studentId: '2022210333',
      studentName: '陈创东',
      objective1Score: 12,
      objective2Score: 20,
      objective3Score: 21,
      objective4Score: 24,
      totalScore: 77,
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
    expect(
        () => sortScoresInPlace(pingshi, ScoreSort.totalDesc), returnsNormally);
    expect(
        () => sortScoresInPlace(experiment, ScoreSort.idAsc), returnsNormally);
    expect(() => sortScoresInPlace(exam, ScoreSort.totalAsc), returnsNormally);
    final aggList = await dao.getScoresByBatch(batchId);
    expect(
        () => sortScoresInPlace(aggList, ScoreSort.totalDesc), returnsNormally);
  });

  test('幂等：真实分项导入后，再读不会被聚合回填覆盖', () async {
    final batchId = await dao.addBatch(
      batchName: 'b',
      courseName: '移动应用开发',
      className: '计科22',
      semester: '2025-2026-1',
      teacherId: 't1',
    );
    // 真实分项导入：课堂 90 → 课堂达成度 0.9
    await dao.importComponentsToDatabase(batchId, {
      'pingshi': [
        {
          'student_id': '2022210332',
          'student_name': '陈晨',
          'class_activity_score': 90.0,
          'quiz_homework_score': 80.0,
          'extra_learning_score': 70.0,
        },
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

  test('学校表格48导入：平时目标3为0，实验按7实验模板映射', () async {
    final file = File('data/达成/计科22《移动应用开发》课程达成评价表格48.xlsx');
    expect(await file.exists(), isTrue, reason: '学校达成评价 Excel 模板必须存在');

    final batchId = await dao.addBatch(
      batchName: '计科22模板导入',
      courseName: '移动应用开发',
      className: '计科22',
      semester: '2025-2026-1',
      teacherId: 't1',
    );

    final components = AchievementExcelService.instance
        .parseComponentSheets(await file.readAsBytes());
    expect(components['pingshi'], isNotEmpty);
    expect(components['experiment'], isNotEmpty);
    expect(components['exam'], isNotEmpty);

    await dao.importComponentsToDatabase(batchId, components);

    final pAvg = await dao.calculatePingshiClassAverage(batchId);
    expect(
      pAvg['obj3'],
      closeTo(0, 0.0001),
      reason: '学校模板中课程目标3无平时评价项',
    );

    final experiments = await dao.getExperimentScores(batchId);
    final row = experiments.firstWhere((r) => r['student_id'] == '2022210333');
    final pingshi = await dao.getPingshiScores(batchId);
    final psRow = pingshi.firstWhere((r) => r['student_id'] == '2022210333');
    expect(
      (psRow['class_activity_achievement'] as num).toDouble(),
      closeTo(0.81, 0.0001),
      reason: '平时目标1应读取学校模板 N 列最后得分，而不是 C 列原始小项',
    );
    expect(
      (psRow['quiz_homework_achievement'] as num).toDouble(),
      closeTo(0.85, 0.0001),
      reason: '平时目标2应读取学校模板 Z 列平均分',
    );
    expect(
      (psRow['extra_learning_achievement'] as num).toDouble(),
      closeTo(0.90, 0.0001),
      reason: '平时目标4应读取学校模板 AK 列平均分',
    );
    expect(
      (row['obj3_achievement'] as num).toDouble(),
      closeTo(0.925, 0.0001),
      reason: '实验5=95、实验6=90，应按7实验模板平均支撑目标3',
    );
    expect(
      (row['obj4_achievement'] as num).toDouble(),
      closeTo(0.6, 0.0001),
      reason: '实验7=60，应支撑目标4',
    );
  });

  test('软件23三表数据导入：平时不丢分，6实验模板目标4不为0', () async {
    final file86 = File('data/达成/软件23《移动应用开发》课程达成评价表格86.xlsx');
    final file85 = File('data/达成/软件23《移动应用开发》课程达成评价表格85.xlsx');
    final file = await file86.exists() ? file86 : file85;
    expect(await file.exists(), isTrue, reason: '软件23达成数据文件必须存在');

    final batchId = await dao.addBatch(
      batchName: '软件23三表导入',
      courseName: '移动应用开发',
      className: '软件23',
      semester: '2025-2026-2',
      teacherId: 't1',
    );

    final components = AchievementExcelService.instance
        .parseComponentSheets(await file.readAsBytes());
    expect(components['pingshi']?.length, 85);
    expect(components['experiment']?.length, 85);
    expect(components['exam']?.length, 85);

    await dao.importComponentsToDatabase(batchId, components);

    final pingshi = await dao.getPingshiScores(batchId);
    final psRow = pingshi.firstWhere((r) => r['student_id'] == '2020210158');
    expect(
        (psRow['class_activity_score'] as num).toDouble(), closeTo(71, 0.01));
    expect((psRow['quiz_homework_score'] as num).toDouble(), closeTo(72, 0.01));
    expect(
        (psRow['extra_learning_score'] as num).toDouble(), closeTo(68, 0.01));

    final experiments = await dao.getExperimentScores(batchId);
    final expRow =
        experiments.firstWhere((r) => r['student_id'] == '2020210158');
    expect((expRow['exp7_score'] as num).toDouble(), closeTo(0, 0.01));
    expect(
      (expRow['obj4_achievement'] as num).toDouble(),
      closeTo(0.68, 0.0001),
      reason: '6实验模板中实验6应支撑目标4，不能因为 exp7 为空导出/计算为0',
    );
  });

  test('平台聚合成绩生成三张分项表并排除归档班级学生', () async {
    final activeClass = await db.insert('classes', {
      'name': '软件23',
      'is_archived': 0,
    });
    final archivedClass = await db.insert('classes', {
      'name': '计科22',
      'is_archived': 1,
    });
    await db.insert('users', {
      'user_id': '2023001',
      'real_name': '当前学生',
      'role': 'student',
      'is_active': 1,
    });
    await db.insert('users', {
      'user_id': '2022001',
      'real_name': '归档学生',
      'role': 'student',
      'is_active': 1,
    });
    await db.insert('class_members', {
      'class_id': activeClass,
      'user_id': '2023001',
      'role': 'student',
    });
    await db.insert('class_members', {
      'class_id': archivedClass,
      'user_id': '2022001',
      'role': 'student',
    });

    await db.insert('quiz_results', {
      'course_id': 'mad',
      'user_id': '2023001',
      'score': 90,
      'num_correct': 9,
      'num_total': 10,
      'chapter': '第1章',
      'quiz_timestamp': '2026-06-01T10:00:00',
    });
    await db.insert('quiz_results', {
      'course_id': 'mad',
      'user_id': '2022001',
      'score': 100,
      'num_correct': 10,
      'num_total': 10,
      'chapter': '第1章',
      'quiz_timestamp': '2026-06-01T10:00:00',
    });
    final taskId = await db.insert('lab_tasks', {
      'course_id': 'mad',
      'title': '实验一',
      'chapter': '第1章',
      'max_score': 100,
      'status': 'active',
    });
    await db.insert('lab_submissions', {
      'task_id': taskId,
      'user_id': '2023001',
      'status': '已批改',
      'score': 80,
      'submit_time': '2026-06-02T10:00:00',
    });
    await db.insert('lab_submissions', {
      'task_id': taskId,
      'user_id': '2022001',
      'status': '已批改',
      'score': 100,
      'submit_time': '2026-06-02T10:00:00',
    });
    await db.insert('assessment_reports', {
      'user_id': '2023001',
      'title': '课程考核大作业报告',
      'status': '审核通过',
      'score': 88,
      'submit_time': '2026-06-03T10:00:00',
      'created_at': '2026-06-03T10:00:00',
      'updated_at': '2026-06-03T10:00:00',
    });

    final batchId = await dao.addBatch(
      batchName: '平台聚合',
      courseName: '移动应用开发',
      className: '软件23',
      semester: '2025-2026-2',
      teacherId: 't1',
    );
    final count = await dao.importPlatformAchievementScores(batchId);

    expect(count, 1);
    final pingshi = await dao.getPingshiScores(batchId);
    final experiments = await dao.getExperimentScores(batchId);
    final exams = await dao.getExamScores(batchId);
    final aggregate = await dao.getScores(batchId);

    expect(pingshi.map((r) => r['student_id']), ['2023001']);
    expect(experiments.map((r) => r['student_id']), ['2023001']);
    expect(exams.map((r) => r['student_id']), ['2023001']);
    expect(aggregate.map((r) => r['student_id']), ['2023001']);
    expect((pingshi.single['quiz_homework_score'] as num).toDouble(),
        closeTo(90, 0.001));
    expect((experiments.single['exp1_score'] as num).toDouble(),
        closeTo(80, 0.001));
    expect(
        (exams.single['project_score'] as num).toDouble(), closeTo(88, 0.001));
    expect(
        (exams.single['defense_score'] as num).toDouble(), closeTo(88, 0.001));
  });
}
