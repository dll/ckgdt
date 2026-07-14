import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart' as xl;
import '../../core/error_handler.dart';
import 'database_helper.dart';
import '../../services/course_context_service.dart';

double _asDouble(Object? value, [double fallback = 0.0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// 问卷调查 DAO — 问卷 CRUD、题目管理、回答统计
class SurveyDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // 问卷 CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取所有问卷
  Future<List<Map<String, dynamic>>> getAllSurveys() async {
    final db = await _dbHelper.database;
    await _purgeLegacyLearningHabitSurvey(db);
    return await db.query('surveys', orderBy: 'created_at DESC');
  }

  /// 获取指定状态的问卷
  Future<List<Map<String, dynamic>>> getSurveysByStatus(String status) async {
    final db = await _dbHelper.database;
    await _purgeLegacyLearningHabitSurvey(db);
    return await db.query('surveys',
        where: 'status = ?', whereArgs: [status], orderBy: 'created_at DESC');
  }

  Future<void> _purgeLegacyLearningHabitSurvey(dynamic db) async {
    try {
      final rows = await db.query(
        'surveys',
        columns: ['id'],
        where: 'title = ?',
        whereArgs: ['学生学习习惯调查'],
      );
      for (final row in rows) {
        final id = row['id'] as int;
        await db.delete('survey_responses',
            where: 'survey_id = ?', whereArgs: [id]);
        await db.delete('survey_questions',
            where: 'survey_id = ?', whereArgs: [id]);
        await db.delete('surveys', where: 'id = ?', whereArgs: [id]);
      }
    } catch (e) {
      debugPrint('SurveyDao: purge legacy learning habit survey failed: $e');
    }
  }

  /// 获取单个问卷
  Future<Map<String, dynamic>?> getSurvey(int surveyId) async {
    final db = await _dbHelper.database;
    final result =
        await db.query('surveys', where: 'id = ?', whereArgs: [surveyId]);
    return result.isNotEmpty ? result.first : null;
  }

  /// 创建问卷
  Future<int> createSurvey({
    required String title,
    String? description,
    int? classId,
    String? creatorId,
    String? deadline,
  }) async {
    final db = await _dbHelper.database;
    return await db.insert('surveys', {
      'title': title,
      'description': description,
      'class_id': classId,
      'creator_id': creatorId,
      'status': 'draft',
      'total_responses': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'deadline': deadline,
    });
  }

  /// 更新问卷
  Future<bool> updateSurvey(int surveyId, Map<String, dynamic> data) async {
    final db = await _dbHelper.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    final count = await db
        .update('surveys', data, where: 'id = ?', whereArgs: [surveyId]);
    return count > 0;
  }

  /// 删除问卷（级联删除题目和回答）
  Future<bool> deleteSurvey(int surveyId) async {
    final db = await _dbHelper.database;
    await db.delete('survey_responses',
        where: 'survey_id = ?', whereArgs: [surveyId]);
    await db.delete('survey_questions',
        where: 'survey_id = ?', whereArgs: [surveyId]);
    final count =
        await db.delete('surveys', where: 'id = ?', whereArgs: [surveyId]);
    return count > 0;
  }

  /// 发布问卷
  Future<bool> publishSurvey(int surveyId) async {
    return await updateSurvey(surveyId, {'status': 'published'});
  }

  /// 关闭问卷
  Future<bool> closeSurvey(int surveyId) async {
    return await updateSurvey(surveyId, {'status': 'closed'});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 题目管理
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取问卷的所有题目
  Future<List<Map<String, dynamic>>> getQuestions(int surveyId) async {
    final db = await _dbHelper.database;
    return await db.query('survey_questions',
        where: 'survey_id = ?', whereArgs: [surveyId], orderBy: 'seq ASC');
  }

  /// 添加题目
  Future<int> addQuestion({
    required int surveyId,
    required String question,
    String questionType = 'single_choice',
    List<String>? options,
    bool isRequired = true,
    int seq = 0,
  }) async {
    final db = await _dbHelper.database;
    return await db.insert('survey_questions', {
      'survey_id': surveyId,
      'question': question,
      'question_type': questionType,
      'options_json': options != null ? json.encode(options) : null,
      'is_required': isRequired ? 1 : 0,
      'seq': seq,
    });
  }

  /// 更新题目
  Future<bool> updateQuestion(int questionId, Map<String, dynamic> data) async {
    final db = await _dbHelper.database;
    final count = await db.update('survey_questions', data,
        where: 'id = ?', whereArgs: [questionId]);
    return count > 0;
  }

  /// 删除题目
  Future<bool> deleteQuestion(int questionId) async {
    final db = await _dbHelper.database;
    final count = await db
        .delete('survey_questions', where: 'id = ?', whereArgs: [questionId]);
    return count > 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 大纲出题
  // ─────────────────────────────────────────────────────────────────────────

  /// 从课程大纲（course_objectives + syllabus_items）自动生成问卷题目
  /// 每项课程目标生成：满意度 + 自我达成评分 + 建议
  /// 每章节生成：掌握程度 + 改进建议
  Future<int> generateSyllabusSurvey({
    required String title,
    String? description,
    String? creatorId,
  }) async {
    final db = await _dbHelper.database;
    final courseName = await CourseContextService().activeCourseName();

    // 读取课程目标
    final objectives = await db.query('course_objectives',
        columns: ['idx', 'name', 'description', 'indicator'],
        where: 'course_name = ?',
        whereArgs: [courseName],
        orderBy: 'idx ASC');
    // 读取章节
    final chapters = await db.query('syllabus_items',
        columns: ['chapter_number', 'title', 'description'],
        orderBy: 'chapter_number ASC');

    // 创建问卷
    final surveyId = await createSurvey(
      title: title,
      description: description ?? '根据《$courseName》课程大纲自动生成的课程目标达成度调查问卷',
      creatorId: creatorId,
    );

    int seq = 0;

    // 1. 课程目标相关题目
    for (final obj in objectives) {
      final idx = obj['idx'] as int? ?? 0;
      final name = obj['name'] as String? ?? '课程目标$idx';
      final indicator = obj['indicator'] as String? ?? '';
      final label = indicator.isNotEmpty ? '$name（$indicator）' : name;

      seq++;
      await addQuestion(
        surveyId: surveyId,
        question: '通过课程学习，您认为"$label"的达成程度如何？',
        questionType: 'single_choice',
        options: ['5 - 完全符合', '4 - 比较符合', '3 - 一般符合', '2 - 不太符合', '1 - 完全不符合'],
        seq: seq,
      );

      seq++;
      await addQuestion(
        surveyId: surveyId,
        question: '您对"$label"的教学有何建议？',
        questionType: 'text',
        isRequired: false,
        seq: seq,
      );
    }

    // 2. 章节掌握度
    if (chapters.isNotEmpty) {
      seq++;
      final chapterOptions = chapters.map((c) {
        final num = c['chapter_number'] as int? ?? 0;
        final title = c['title'] as String? ?? '';
        return '第${num}章 $title';
      }).toList();
      // 限制选项数量
      final opts = chapterOptions.length > 10
          ? chapterOptions.sublist(0, 10)
          : chapterOptions;
      if (opts.isNotEmpty) {
        await addQuestion(
          surveyId: surveyId,
          question: '您认为哪些章节掌握较好？（可多选）',
          questionType: 'multi_choice',
          options: opts,
          seq: seq,
        );
      }
    }

    // 3. 总体评价
    seq++;
    await addQuestion(
      surveyId: surveyId,
      question: '您对课程整体教学质量的评价？',
      questionType: 'rating',
      seq: seq,
    );

    seq++;
    await addQuestion(
      surveyId: surveyId,
      question: '您认为本课程在哪些方面需要改进？',
      questionType: 'text',
      isRequired: false,
      seq: seq,
    );

    return surveyId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Excel 导入导出
  // ─────────────────────────────────────────────────────────────────────────

  /// 导出问卷模板（题目设计）到 Excel
  Future<List<int>> exportSurveyDesign(int surveyId) async {
    final questions = await getQuestions(surveyId);
    final wb = xl.Excel.createExcel();
    final sheet = wb['问卷设计'];

    // 标题行
    sheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = xl.TextCellValue('题号');
    sheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
        .value = xl.TextCellValue('题目');
    sheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0))
        .value = xl.TextCellValue('题型');
    sheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0))
        .value = xl.TextCellValue('选项（|分隔）');
    sheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0))
        .value = xl.TextCellValue('必填');

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final r = i + 1;
      final optionsJson = q['options_json'] as String?;
      final options = optionsJson != null
          ? (List<String>.from(json.decode(optionsJson))).join('|')
          : '';
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = xl.IntCellValue(i + 1);
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = xl.TextCellValue(q['question'] as String? ?? '');
      sheet
              .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
              .value =
          xl.TextCellValue(q['question_type'] as String? ?? 'single_choice');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = xl.TextCellValue(options);
      sheet
              .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
              .value =
          xl.TextCellValue((q['is_required'] as int?) == 1 ? '是' : '否');
    }

    sheet.setColumnWidth(0, 8.0);
    sheet.setColumnWidth(1, 40.0);
    sheet.setColumnWidth(2, 12.0);
    sheet.setColumnWidth(3, 50.0);
    sheet.setColumnWidth(4, 8.0);

    return wb.save()!;
  }

  /// 从 Excel 导入问卷设计（覆盖原有题目）
  Future<int> importSurveyDesign(int surveyId, List<int> bytes) async {
    final wb = xl.Excel.decodeBytes(bytes);
    final sheet = wb.tables.values.first;
    if (sheet.rows.length < 2) return 0;

    // 删除原有题目
    final db = await _dbHelper.database;
    await db.delete('survey_questions',
        where: 'survey_id = ?', whereArgs: [surveyId]);

    int imported = 0;
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final questionStr = _cellStr(row, 1);
      if (questionStr.isEmpty) continue;

      final type =
          _cellStr(row, 2).isNotEmpty ? _cellStr(row, 2) : 'single_choice';
      final optionsStr = _cellStr(row, 3);
      final options =
          optionsStr.isNotEmpty ? optionsStr.split('|') : <String>[];
      final isRequired = _cellStr(row, 4) == '是';

      await addQuestion(
        surveyId: surveyId,
        question: questionStr,
        questionType: type,
        options: options.isNotEmpty ? options : null,
        isRequired: isRequired,
        seq: imported + 1,
      );
      imported++;
    }

    return imported;
  }

  /// 导出问卷回答数据到 Excel
  Future<List<int>> exportSurveyData(int surveyId) async {
    final questions = await getQuestions(surveyId);
    final responses = await getResponses(surveyId);
    final wb = xl.Excel.createExcel();
    final sheet = wb['问卷数据'];

    // 标题行：学号 | 姓名 | 题1 | 题2 | ...
    sheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = xl.TextCellValue('学号');
    sheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
        .value = xl.TextCellValue('姓名');
    for (int i = 0; i < questions.length; i++) {
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: i + 2, rowIndex: 0))
          .value = xl.TextCellValue(questions[i]['question'] as String? ?? '');
    }

    for (int r = 0; r < responses.length; r++) {
      final resp = responses[r];
      final answersJson = resp['answers_json'] as String?;
      final answers = answersJson != null
          ? json.decode(answersJson) as Map<String, dynamic>
          : <String, dynamic>{};

      final row = r + 1;
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xl.TextCellValue(resp['user_id'] as String? ?? '');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = xl.TextCellValue(resp['real_name'] as String? ?? '');

      for (int qi = 0; qi < questions.length; qi++) {
        final qId = questions[qi]['id'].toString();
        final answer = answers[qId];
        final display =
            answer is List ? answer.join(', ') : (answer?.toString() ?? '');
        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: qi + 2, rowIndex: row))
            .value = xl.TextCellValue(display);
      }
    }

    sheet.setColumnWidth(0, 14.0);
    sheet.setColumnWidth(1, 12.0);
    for (int i = 0; i < questions.length; i++) {
      sheet.setColumnWidth(i + 2, 30.0);
    }

    return wb.save()!;
  }

  /// 导入泛雅平台“投票问卷统计详情”Excel。
  ///
  /// 兼容格式：
  /// 第 1 行问卷标题，第 2 行发起人/已交人数，第 3 行字段：
  /// 学号/工号、学生姓名、学校、院系、专业、班级、提交时间、[单选题]...
  /// 数据行答案通常为 A/B/C/D/E，对应 1-5 量表。
  Future<int> importFanyaResponses(int surveyId, List<int> bytes) async {
    final wb = xl.Excel.decodeBytes(bytes);
    if (wb.tables.isEmpty) return 0;

    xl.Sheet? sheet;
    var headerRow = -1;
    for (final candidate in wb.tables.values) {
      for (var i = 0; i < candidate.rows.length && i < 12; i++) {
        final cells =
            candidate.rows[i].map((c) => c?.value?.toString() ?? '').toList();
        if (cells.any((c) => c.contains('学号')) &&
            cells.any((c) => c.contains('[单选题]'))) {
          sheet = candidate;
          headerRow = i;
          break;
        }
      }
      if (sheet != null) break;
    }
    if (sheet == null || sheet.rows.length <= headerRow + 1) {
      return 0;
    }

    final headers =
        sheet.rows[headerRow].map((c) => c?.value?.toString() ?? '').toList();
    final questions = await getQuestions(surveyId);
    final questionByText = <String, Map<String, dynamic>>{
      for (final q in questions)
        _normalizeQuestion(q['question']?.toString() ?? ''): q
    };
    final questionBySeq = <int, Map<String, dynamic>>{
      for (final q in questions) _asInt(q['seq']): q
    }..removeWhere((key, value) => key <= 0);
    final columnToQuestionId = <int, int>{};
    final columnToOptions = <int, List<String>>{};

    for (var c = 0; c < headers.length; c++) {
      if (!headers[c].contains('[单选题]')) continue;
      final questionText = _cleanFanyaQuestion(headers[c]);
      if (questionText.isEmpty) continue;
      final key = _normalizeQuestion(questionText);
      final seq = _fanyaQuestionSeq(headers[c]);
      var q = questionByText[key] ?? questionBySeq[seq];
      if (q == null) {
        final qid = await addQuestion(
          surveyId: surveyId,
          question: questionText,
          questionType: 'single_choice',
          options: const [
            '5 - 完全符合',
            '4 - 比较符合',
            '3 - 一般符合',
            '2 - 不太符合',
            '1 - 完全不符合'
          ],
          seq: questions.length + columnToQuestionId.length + 1,
        );
        q = {
          'id': qid,
          'options_json': jsonEncode(const [
            '5 - 完全符合',
            '4 - 比较符合',
            '3 - 一般符合',
            '2 - 不太符合',
            '1 - 完全不符合'
          ])
        };
      }
      columnToQuestionId[c] = q['id'] as int;
      final optionsJson = q['options_json']?.toString();
      columnToOptions[c] = optionsJson == null || optionsJson.isEmpty
          ? const []
          : List<String>.from(jsonDecode(optionsJson));
    }
    if (columnToQuestionId.isEmpty) return 0;

    final db = await _dbHelper.database;
    var imported = 0;
    for (var r = headerRow + 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final userId = _cellStr(row, 0);
      if (userId.isEmpty || userId.contains('合计') || userId.contains('平均')) {
        continue;
      }
      final answers = <String, dynamic>{};
      for (final entry in columnToQuestionId.entries) {
        final raw = _cellStr(row, entry.key);
        if (raw.isEmpty) continue;
        answers[entry.value.toString()] =
            _mapFanyaAnswer(raw, columnToOptions[entry.key] ?? const []);
      }
      if (answers.isEmpty) continue;
      await db.delete(
        'survey_responses',
        where: 'survey_id = ? AND user_id = ?',
        whereArgs: [surveyId, userId],
      );
      await db.insert('survey_responses', {
        'survey_id': surveyId,
        'user_id': userId,
        'answers_json': jsonEncode(answers),
        'submitted_at': _cellStr(row, 6).isNotEmpty
            ? _cellStr(row, 6)
            : DateTime.now().toIso8601String(),
      });
      imported++;
    }
    await updateSurvey(surveyId, {'total_responses': imported});
    return imported;
  }

  String _cleanFanyaQuestion(String header) {
    var text = header
        .replaceAll(RegExp(r'^\[单选题\]\s*'), '')
        .replaceAll(RegExp(r'\s*A\.1\s*-\s*完全不符合[\s\S]*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    text = text.replaceFirst(RegExp(r'^\d+[、.．]\s*'), '').trim();
    return text;
  }

  int _fanyaQuestionSeq(String header) {
    final match = RegExp(r'^\[单选题\]\s*(\d+)[、.．]?').firstMatch(header);
    return match == null ? 0 : int.tryParse(match.group(1) ?? '') ?? 0;
  }

  String _normalizeQuestion(String text) => text
      .replaceAll(RegExp(r'^\d+[、.．]\s*'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('，', ',')
      .replaceAll('。', '')
      .trim();

  String _mapFanyaAnswer(String raw, List<String> options) {
    final text = raw.trim().toUpperCase();
    final score = switch (text) {
      'E' => 5,
      'D' => 4,
      'C' => 3,
      'B' => 2,
      'A' => 1,
      _ => int.tryParse(text) ?? 0,
    };
    if (score > 0) {
      final matched = options.firstWhere(
        (o) => o.trim().startsWith('$score') || o.contains('$score -'),
        orElse: () => '',
      );
      if (matched.isNotEmpty) return matched;
      return '$score';
    }
    return raw;
  }

  String _cellStr(List<xl.Data?> row, int col) {
    if (col >= row.length) return '';
    final cell = row[col];
    if (cell == null) return '';
    return cell.value?.toString().trim() ?? '';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 回答管理
  // ─────────────────────────────────────────────────────────────────────────

  /// 提交问卷回答
  Future<bool> submitResponse({
    required int surveyId,
    required String userId,
    required Map<String, dynamic> answers,
  }) async {
    final db = await _dbHelper.database;
    try {
      await db.insert('survey_responses', {
        'survey_id': surveyId,
        'user_id': userId,
        'answers_json': json.encode(answers),
        'submitted_at': DateTime.now().toIso8601String(),
      });
      // 更新回收数
      final countResult = await db.rawQuery(
          'SELECT COUNT(*) as c FROM survey_responses WHERE survey_id = ?',
          [surveyId]);
      final total = (countResult.first['c'] as int?) ?? 0;
      await updateSurvey(surveyId, {'total_responses': total});
      return true;
    } catch (e) {
      debugPrint('SurveyDao.submitResponse error: $e');
      return false;
    }
  }

  /// 获取问卷的所有回答
  Future<List<Map<String, dynamic>>> getResponses(int surveyId) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT sr.*, u.real_name
      FROM survey_responses sr
      LEFT JOIN users u ON sr.user_id = u.user_id
      WHERE sr.survey_id = ?
      ORDER BY sr.submitted_at DESC
    ''', [surveyId]);
  }

  /// 检查用户是否已回答
  Future<bool> hasResponded(int surveyId, String userId) async {
    final db = await _dbHelper.database;
    final result = await db.query('survey_responses',
        where: 'survey_id = ? AND user_id = ?', whereArgs: [surveyId, userId]);
    return result.isNotEmpty;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 统计分析
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取问卷统计数据
  Future<Map<String, dynamic>> getSurveyStats(int surveyId) async {
    final survey = await getSurvey(surveyId);
    final questions = await getQuestions(surveyId);
    final responses = await getResponses(surveyId);

    // 按题目统计回答分布
    final questionStats = <Map<String, dynamic>>[];

    for (final q in questions) {
      final qId = q['id'].toString();
      final qType = q['question_type'] as String? ?? 'single_choice';
      final optionsJson = q['options_json'] as String?;
      final options = optionsJson != null
          ? List<String>.from(json.decode(optionsJson))
          : <String>[];

      if (qType == 'single_choice' || qType == 'multi_choice') {
        // 统计每个选项的选择次数
        final optionCounts = <String, int>{};
        for (final opt in options) {
          optionCounts[opt] = 0;
        }

        for (final resp in responses) {
          final answersJson = resp['answers_json'] as String?;
          if (answersJson == null) continue;
          final answers = json.decode(answersJson) as Map<String, dynamic>;
          final answer = answers[qId];
          if (answer is String) {
            optionCounts[answer] = (optionCounts[answer] ?? 0) + 1;
          } else if (answer is List) {
            for (final a in answer) {
              optionCounts[a.toString()] =
                  (optionCounts[a.toString()] ?? 0) + 1;
            }
          }
        }

        questionStats.add({
          'question': q['question'],
          'type': qType,
          'options': options,
          'counts': optionCounts,
          'total': responses.length,
        });
      } else if (qType == 'rating') {
        // 评分题统计
        double sum = 0;
        int count = 0;
        final distribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
        for (final resp in responses) {
          final answersJson = resp['answers_json'] as String?;
          if (answersJson == null) continue;
          final answers = json.decode(answersJson) as Map<String, dynamic>;
          final answer = answers[qId];
          if (answer != null) {
            final val = int.tryParse(answer.toString()) ?? 0;
            if (val > 0) {
              sum += val;
              count++;
              distribution[val] = (distribution[val] ?? 0) + 1;
            }
          }
        }
        questionStats.add({
          'question': q['question'],
          'type': qType,
          'average': count > 0 ? (sum / count) : 0,
          'distribution': distribution,
          'total': responses.length,
        });
      } else {
        // 文本题 — 收集所有回答
        final textAnswers = <String>[];
        for (final resp in responses) {
          final answersJson = resp['answers_json'] as String?;
          if (answersJson == null) continue;
          final answers = json.decode(answersJson) as Map<String, dynamic>;
          final answer = answers[qId];
          if (answer != null && answer.toString().isNotEmpty) {
            textAnswers.add(answer.toString());
          }
        }
        questionStats.add({
          'question': q['question'],
          'type': qType,
          'answers': textAnswers,
          'total': responses.length,
        });
      }
    }

    return {
      'survey': survey,
      'total_questions': questions.length,
      'total_responses': responses.length,
      'question_stats': questionStats,
    };
  }

  /// 生成文本报告
  Future<String> generateReport(int surveyId) async {
    final stats = await getSurveyStats(surveyId);
    final survey = stats['survey'] as Map<String, dynamic>?;
    final buf = StringBuffer();

    buf.writeln('=' * 60);
    buf.writeln('问卷调查统计报告');
    buf.writeln('=' * 60);
    buf.writeln('');
    buf.writeln('问卷标题：${survey?['title'] ?? '未知'}');
    buf.writeln('问卷描述：${survey?['description'] ?? '无'}');
    buf.writeln('发布时间：${survey?['created_at'] ?? '未知'}');
    buf.writeln('回收数量：${stats['total_responses']} 份');
    buf.writeln('题目数量：${stats['total_questions']} 题');
    buf.writeln('');
    buf.writeln('-' * 60);
    buf.writeln('各题统计');
    buf.writeln('-' * 60);

    final questionStats =
        stats['question_stats'] as List<Map<String, dynamic>>? ?? [];
    for (int i = 0; i < questionStats.length; i++) {
      final qs = questionStats[i];
      buf.writeln('');
      buf.writeln('第 ${i + 1} 题：${qs['question']}');
      buf.writeln('  题型：${_typeLabel(qs['type'] as String)}');

      if (qs['type'] == 'single_choice' || qs['type'] == 'multi_choice') {
        final counts = qs['counts'] as Map<String, int>? ?? {};
        final total = (qs['total'] as int?) ?? 1;
        for (final entry in counts.entries) {
          final pct =
              total > 0 ? (entry.value / total * 100).toStringAsFixed(1) : '0';
          buf.writeln('    ${entry.key}：${entry.value} 人（$pct%）');
        }
      } else if (qs['type'] == 'rating') {
        final avg = _asDouble(qs['average']);
        buf.writeln('  平均评分：${avg.toStringAsFixed(2)} / 5.0');
        final dist = qs['distribution'] as Map<int, int>? ?? {};
        for (int s = 5; s >= 1; s--) {
          buf.writeln('    $s 星：${dist[s] ?? 0} 人');
        }
      } else {
        final answers = qs['answers'] as List<String>? ?? [];
        buf.writeln('  收集到 ${answers.length} 条文本回答');
        for (int j = 0; j < answers.length && j < 10; j++) {
          buf.writeln('    - ${answers[j]}');
        }
        if (answers.length > 10) {
          buf.writeln('    ... 共 ${answers.length} 条');
        }
      }
    }

    buf.writeln('');
    buf.writeln('=' * 60);
    buf.writeln('报告生成时间：${DateTime.now().toIso8601String()}');

    return buf.toString();
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'single_choice':
        return '单选题';
      case 'multi_choice':
        return '多选题';
      case 'rating':
        return '评分题';
      case 'text':
        return '文本题';
      default:
        return type;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 全局统计
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取问卷系统概览
  Future<Map<String, int>> getOverview() async {
    final db = await _dbHelper.database;
    final total = await db.rawQuery('SELECT COUNT(*) as c FROM surveys');
    final published = await db.rawQuery(
        "SELECT COUNT(*) as c FROM surveys WHERE status = 'published'");
    final draft = await db
        .rawQuery("SELECT COUNT(*) as c FROM surveys WHERE status = 'draft'");
    final closed = await db
        .rawQuery("SELECT COUNT(*) as c FROM surveys WHERE status = 'closed'");
    final responses =
        await db.rawQuery('SELECT COUNT(*) as c FROM survey_responses');
    return {
      'total': (total.first['c'] as int?) ?? 0,
      'published': (published.first['c'] as int?) ?? 0,
      'draft': (draft.first['c'] as int?) ?? 0,
      'closed': (closed.first['c'] as int?) ?? 0,
      'responses': (responses.first['c'] as int?) ?? 0,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 示例数据
  // ─────────────────────────────────────────────────────────────────────────

  /// 从课程资源包自动导入问卷数据。
  ///
  /// 检查 `data/{courseId}/达成/` 目录下是否有 Fanya 格式的问卷 Excel，
  /// 如果有且当前没有已发布的问卷数据，则自动创建问卷并导入回答。
  /// 返回导入的回答数，0 表示无需导入或导入失败。
  Future<int> autoImportFromCoursePackage(String courseId) async {
    final db = await _dbHelper.database;

    // 1. 检查当前课程是否已有问卷且有回答（按课程名模糊匹配）
    final courseName = await CourseContextService().activeCourseName();
    final existing = await db.rawQuery(
      "SELECT id FROM surveys WHERE title LIKE ? AND status IN ('published','closed') LIMIT 1",
      ['%$courseName%'],
    );
    if (existing.isNotEmpty) {
      final surveyId = existing.first['id'];
      final respCount = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM survey_responses WHERE survey_id = ?',
        [surveyId],
      );
      if (((respCount.first['c'] as int?) ?? 0) > 0) return 0;
    }

    // 2. 查找课程资源包中的问卷 Excel（复用 AchievementTemplateAssets 的路径搜索逻辑）
    final surveyFile = await _findSurveyExcelForCourse(courseId);
    if (surveyFile == null) return 0;

    // 3. 读取 Excel 文件
    final bytes = await surveyFile.readAsBytes();
    final wb = xl.Excel.decodeBytes(bytes);
    if (wb.tables.isEmpty) return 0;

    // 4. 查找 Fanya 格式的 sheet
    xl.Sheet? sheet;
    var headerRow = -1;
    for (final candidate in wb.tables.values) {
      for (var i = 0; i < candidate.rows.length && i < 12; i++) {
        final cells =
            candidate.rows[i].map((c) => c?.value?.toString() ?? '').toList();
        if (cells.any((c) => c.contains('学号')) &&
            cells.any((c) => c.contains('[单选题]'))) {
          sheet = candidate;
          headerRow = i;
          break;
        }
      }
      if (sheet != null) break;
    }
    if (sheet == null || sheet.rows.length <= headerRow + 1) return 0;

    // 5. 创建问卷
    final displayCourseName =
        courseName.isEmpty ? (courseId.isEmpty ? '当前课程' : courseId) : courseName;
    final sid = await createSurvey(
      title: '《$displayCourseName》课程目标支撑毕业要求达成度调查问卷',
      description: '请根据《$displayCourseName》课程学习中的实际收获，评价课程目标对毕业要求的支撑效果。',
      creatorId: '419116',
    );

    // 6. 导入回答（复用 importFanyaResponses 逻辑）
    final imported = await importFanyaResponses(sid, bytes);

    // 7. 如果导入成功，确保问卷已发布
    if (imported > 0) {
      await publishSurvey(sid);
      debugPrint(
          'SurveyDao: 从课程资源包自动导入 $imported 条问卷回答 sid=$sid');
    }

    return imported;
  }

  /// 查找课程资源包中的问卷 Excel 文件
  Future<File?> _findSurveyExcelForCourse(String courseId) async {
    try {
      // 复用 AchievementTemplateAssets.courseOnlyRoots() 的路径搜索逻辑
      final roots = <String>[];
      void addRoot(String path) {
        if (!roots.contains(path)) roots.add(path);
      }

      addRoot('data/$courseId/达成');
      addRoot('${Directory.current.path}/data/$courseId/达成');
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        var dir = File(Platform.resolvedExecutable).parent;
        for (var i = 0; i < 6; i++) {
          addRoot('${dir.path}/data/$courseId/达成');
          final parent = dir.parent;
          if (parent.path == dir.path) break;
          dir = parent;
        }
      }

      for (final root in roots) {
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is! File) continue;
          final name = entity.path.toLowerCase();
          if ((name.contains('问卷') || name.contains('survey')) &&
              (name.endsWith('.xlsx') || name.endsWith('.xls'))) {
            return entity;
          }
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SurveyDao._findSurveyExcelForCourse', stack: st);
    }
    return null;
  }

  /// 生成示例问卷数据
  Future<void> generateDemoData() async {
    final db = await _dbHelper.database;
    await _purgeLegacyLearningHabitSurvey(db);
    final courseName = await CourseContextService().activeCourseName();
    final existing = await db.query(
      'surveys',
      where: 'title LIKE ?',
      whereArgs: ['%课程目标支撑毕业要求达成度调查问卷%'],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final displayCourseName = courseName.isEmpty ? '当前课程' : courseName;

    // 创建课程目标支撑毕业要求达成度调查问卷。题目来自当前课程目标，
    // 兼容泛雅导出的 A-E / 1-5 量表统计。
    final sid1 = await createSurvey(
      title: '《$displayCourseName》课程目标支撑毕业要求达成度调查问卷',
      description: '请根据《$displayCourseName》课程学习中的实际收获，评价课程目标对毕业要求的支撑效果。',
      creatorId: '419116',
    );

    final objectives = await db.query(
      'course_objectives',
      columns: ['idx', 'name', 'description', 'indicator'],
      where: 'course_name = ?',
      whereArgs: [displayCourseName],
      orderBy: 'idx ASC',
    );
    var seq = 0;
    final options = [
      '5 - 完全符合',
      '4 - 比较符合',
      '3 - 一般符合',
      '2 - 不太符合',
      '1 - 完全不符合'
    ];
    if (objectives.isEmpty) {
      await addQuestion(
          surveyId: sid1,
          question: '整体来看，本课程学习让我达到课程目标并支撑相关毕业要求。',
          questionType: 'single_choice',
          options: options,
          seq: ++seq);
    } else {
      for (final obj in objectives) {
        final idx = obj['idx'] as int? ?? seq + 1;
        final desc =
            (obj['description'] ?? obj['name'] ?? '课程目标$idx').toString();
        final indicator = (obj['indicator'] ?? '').toString();
        await addQuestion(
            surveyId: sid1,
            question:
                '通过课程学习，我能够达成课程目标$idx${indicator.isNotEmpty ? '（支撑毕业要求$indicator）' : ''}：$desc',
            questionType: 'single_choice',
            options: options,
            seq: ++seq);
      }
    }
    await addQuestion(
        surveyId: sid1,
        question: '您对本课程目标达成、教学内容、实践任务或评价方式的改进建议',
        questionType: 'text',
        isRequired: false,
        seq: ++seq);
    await publishSurvey(sid1);

    debugPrint('SurveyDao: 已生成课程目标支撑毕业要求达成度调查问卷 sid=$sid1');
  }
}
