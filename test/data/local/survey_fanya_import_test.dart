import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/local/achievement_dao.dart';
import 'package:knowledge_graph_app/data/local/database_helper.dart';
import 'package:knowledge_graph_app/data/local/survey_dao.dart';

import '../../helpers/test_db.dart';

void main() {
  setupTestSqflite();

  late dynamic db;

  setUp(() async {
    db = await openInMemoryDb();
    DatabaseHelper.databaseForTest = db;
    await db.execute('''
      CREATE TABLE surveys(
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
    await db.execute('''
      CREATE TABLE survey_questions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        survey_id INTEGER NOT NULL,
        question TEXT NOT NULL,
        question_type TEXT DEFAULT 'single_choice',
        options_json TEXT,
        is_required INTEGER DEFAULT 1,
        seq INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE survey_responses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        survey_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        answers_json TEXT,
        submitted_at TEXT,
        UNIQUE(survey_id, user_id)
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.databaseForTest = null;
  });

  test('导入泛雅投票问卷统计详情并按 1-5 量表参与满意度统计', () async {
    final surveyDao = SurveyDao();
    final achievementDao = AchievementDao();
    final surveyId = await surveyDao.createSurvey(
      title: '《移动应用开发》课程目标支撑毕业要求达成度调查问卷',
    );
    await surveyDao.publishSurvey(surveyId);
    await surveyDao.addQuestion(
      surveyId: surveyId,
      question: '通过课程学习，您认为"课程目标1（1.1）"的达成程度如何？',
      options: const [
        '5 - 完全符合',
        '4 - 比较符合',
        '3 - 一般符合',
        '2 - 不太符合',
        '1 - 完全不符合',
      ],
      seq: 1,
    );

    final excel = xl.Excel.createExcel();
    for (final name in excel.tables.keys.toList()) {
      excel.delete(name);
    }
    final sheet = excel['课程目标支撑毕业要求达成度调查问卷'];
    xl.TextCellValue t(String value) => xl.TextCellValue(value);
    sheet.appendRow([t('课程目标支撑毕业要求达成度调查问卷')]);
    sheet.appendRow([t('发起人：刘东良 已交：2人')]);
    sheet.appendRow([
      t('学号/工号'),
      t('学生姓名'),
      t('学校'),
      t('院系'),
      t('专业'),
      t('班级'),
      t('提交时间'),
      t('[单选题]1、通过课程学习，您认为"课程目标1（1.1）"的达成程度如何？ A.1 - 完全不符合B.2 - 不太符合C.3 - 一般符合D.4 - 比较符合E.5 - 完全符合null.'),
    ]);
    sheet.appendRow([
      t('2023001'),
      t('张三'),
      t('学校'),
      t('学院'),
      t('软件工程'),
      t('软件23'),
      t('2026-07-09 10:00'),
      t('E'),
    ]);
    sheet.appendRow([
      t('2023002'),
      t('李四'),
      t('学校'),
      t('学院'),
      t('软件工程'),
      t('软件23'),
      t('2026-07-09 10:01'),
      t('D'),
    ]);

    final imported =
        await surveyDao.importFanyaResponses(surveyId, excel.save()!);

    expect(imported, 2);
    expect(await surveyDao.getQuestions(surveyId), hasLength(1),
        reason: '按题号匹配已有题目，不能重复新增泛雅题目');
    final summary = await achievementDao.getSurveySatisfactionSummary();
    expect(summary['hasSurveyData'], isTrue);
    expect(summary['totalResponses'], 2);
    expect(summary['overallSatisfaction'], closeTo(0.9, 0.0001));
  });
}
