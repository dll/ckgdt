import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';

/// 问卷调查 DAO — 问卷 CRUD、题目管理、回答统计
class SurveyDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // 问卷 CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取所有问卷
  Future<List<Map<String, dynamic>>> getAllSurveys() async {
    final db = await _dbHelper.database;
    return await db.query('surveys', orderBy: 'created_at DESC');
  }

  /// 获取指定状态的问卷
  Future<List<Map<String, dynamic>>> getSurveysByStatus(String status) async {
    final db = await _dbHelper.database;
    return await db.query('surveys',
        where: 'status = ?', whereArgs: [status], orderBy: 'created_at DESC');
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
    final count = await db.update('surveys', data,
        where: 'id = ?', whereArgs: [surveyId]);
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
    final count = await db.delete('survey_questions',
        where: 'id = ?', whereArgs: [questionId]);
    return count > 0;
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
        where: 'survey_id = ? AND user_id = ?',
        whereArgs: [surveyId, userId]);
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
      final options =
          optionsJson != null ? List<String>.from(json.decode(optionsJson)) : <String>[];

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
        final avg = qs['average'] as double? ?? 0;
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
    final draft = await db.rawQuery(
        "SELECT COUNT(*) as c FROM surveys WHERE status = 'draft'");
    final closed = await db.rawQuery(
        "SELECT COUNT(*) as c FROM surveys WHERE status = 'closed'");
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

  /// 生成示例问卷数据
  Future<void> generateDemoData() async {
    final db = await _dbHelper.database;
    final count = await db.rawQuery('SELECT COUNT(*) as c FROM surveys');
    if (((count.first['c'] as int?) ?? 0) > 0) return;

    // 创建示例问卷1：课程满意度
    final sid1 = await createSurvey(
      title: '《移动应用开发》课程满意度调查',
      description: '请对本学期《移动应用开发》课程各方面进行评价，帮助我们改进教学质量。',
      creatorId: '419116',
    );
    await addQuestion(
        surveyId: sid1,
        question: '您对课程整体教学质量的评价？',
        questionType: 'single_choice',
        options: ['非常满意', '满意', '一般', '不太满意', '不满意'],
        seq: 1);
    await addQuestion(
        surveyId: sid1,
        question: '您认为课程中哪些内容最有用？（可多选）',
        questionType: 'multi_choice',
        options: ['Flutter开发', 'Android原生', 'React Native', '小程序开发', 'HarmonyOS', '综合实践'],
        seq: 2);
    await addQuestion(
        surveyId: sid1,
        question: '请为课程教学打分',
        questionType: 'rating',
        seq: 3);
    await addQuestion(
        surveyId: sid1,
        question: '您对课程改进的建议',
        questionType: 'text',
        isRequired: false,
        seq: 4);
    await publishSurvey(sid1);

    // 模拟一些回答
    final students = await db.query('users',
        where: 'role = ?', whereArgs: ['student'], limit: 8);
    final satisfactionOpts = ['非常满意', '满意', '一般', '不太满意'];
    final contentOpts = [
      ['Flutter开发', 'Android原生'],
      ['Flutter开发', '小程序开发', '综合实践'],
      ['React Native', 'HarmonyOS'],
      ['Flutter开发', '综合实践'],
    ];
    final ratings = ['5', '4', '4', '3', '5', '4', '5', '3'];
    final suggestions = [
      '希望增加更多实践项目',
      '课程内容丰富，建议增加视频教程',
      '',
      '建议加入鸿蒙开发实战',
      '非常好的课程！',
      '',
      '希望增加代码review环节',
      '建议增加分组协作项目',
    ];

    for (int i = 0; i < students.length; i++) {
      final uid = students[i]['user_id'] as String;
      final questions = await getQuestions(sid1);
      final answers = <String, dynamic>{};
      answers[questions[0]['id'].toString()] =
          satisfactionOpts[i % satisfactionOpts.length];
      answers[questions[1]['id'].toString()] =
          contentOpts[i % contentOpts.length];
      answers[questions[2]['id'].toString()] = ratings[i % ratings.length];
      if (suggestions[i % suggestions.length].isNotEmpty) {
        answers[questions[3]['id'].toString()] =
            suggestions[i % suggestions.length];
      }
      await submitResponse(surveyId: sid1, userId: uid, answers: answers);
    }

    // 创建示例问卷2：学习习惯调查（草稿）
    final sid2 = await createSurvey(
      title: '学生学习习惯调查',
      description: '了解学生的学习方式和习惯，优化教学方法。',
      creatorId: '419116',
    );
    await addQuestion(
        surveyId: sid2,
        question: '您每周用于本课程学习的时间？',
        questionType: 'single_choice',
        options: ['少于2小时', '2-5小时', '5-10小时', '10小时以上'],
        seq: 1);
    await addQuestion(
        surveyId: sid2,
        question: '您更喜欢哪种学习方式？',
        questionType: 'single_choice',
        options: ['观看视频', '阅读文档', '动手实践', '小组讨论'],
        seq: 2);
    await addQuestion(
        surveyId: sid2,
        question: '您在学习中遇到的主要困难',
        questionType: 'text',
        seq: 3);

    debugPrint('SurveyDao: 示例数据生成完成 — sid1=$sid1 (已发布+8回答), sid2=$sid2 (草稿)');
  }
}
