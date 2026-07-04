import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';
import '../models/homework_model.dart';

/// 作业数据访问层
class HomeworkDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 获取数据库实例
  Future<Database> get _db => _dbHelper.database;

  /// 创建作业
  Future<int> createHomework(HomeworkModel hw) async {
    final db = await _db;
    return await db.insert('homeworks', hw.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取课程的所有作业
  Future<List<HomeworkModel>> getHomeworks(String courseId) async {
    final db = await _db;
    final rows = await db.query(
      'homeworks',
      where: 'course_id = ?',
      whereArgs: [courseId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => HomeworkModel.fromMap(r)).toList();
  }

  /// 获取单个作业
  Future<HomeworkModel?> getHomework(int id) async {
    final db = await _db;
    final rows = await db.query('homeworks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return HomeworkModel.fromMap(rows.first);
  }

  /// 更新作业状态
  Future<void> updateStatus(int id, String status) async {
    final db = await _db;
    await db.update('homeworks', {'status': status},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除作业
  Future<void> deleteHomework(int id) async {
    final db = await _db;
    await db.delete('homework_submissions', where: 'homework_id = ?', whereArgs: [id]);
    await db.delete('homework_items', where: 'homework_id = ?', whereArgs: [id]);
    await db.delete('homeworks', where: 'id = ?', whereArgs: [id]);
  }

  /// ── 题目 ──────────────────────────────────────────────────────────────────

  /// 批量插入题目
  Future<void> insertItems(int homeworkId, List<HomeworkItemModel> items) async {
    final db = await _db;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      await db.insert('homework_items', {
        'homework_id': homeworkId,
        'item_index': i + 1,
        'type': item.type,
        'type_label': item.typeLabel,
        'question': item.question,
        'reference_answer': item.referenceAnswer,
        'max_score': item.maxScore,
        'objective_mapping': jsonEncode(item.objectiveMapping.map((e) => e.toMap()).toList()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// 获取作业的所有题目
  Future<List<HomeworkItemModel>> getItems(int homeworkId) async {
    final db = await _db;
    final rows = await db.query(
      'homework_items',
      where: 'homework_id = ?',
      whereArgs: [homeworkId],
      orderBy: 'item_index',
    );
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      // 解析 objective_mapping JSON
      final omRaw = m['objective_mapping'] as String?;
      if (omRaw != null && omRaw.isNotEmpty) {
        try {
          m['objective_mapping'] = jsonDecode(omRaw);
        } catch (_) {
          m['objective_mapping'] = [];
        }
      }
      return HomeworkItemModel.fromMap(m);
    }).toList();
  }

  /// ── 提交 ──────────────────────────────────────────────────────────────────

  /// 提交作业
  Future<int> submit(HomeworkSubmissionModel sub) async {
    final db = await _db;
    // 检查是否已提交（同一题目只提交一次）
    final existing = await db.query(
      'homework_submissions',
      where: 'homework_id = ? AND item_id = ? AND user_id = ?',
      whereArgs: [sub.homeworkId, sub.itemId, sub.userId],
    );
    if (existing.isNotEmpty) {
      // 更新已有提交
      await db.update(
        'homework_submissions',
        sub.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return existing.first['id'] as int;
    }
    return await db.insert('homework_submissions', sub.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取学生某次作业的所有提交
  Future<List<HomeworkSubmissionModel>> getSubmissions(
      int homeworkId, String userId) async {
    final db = await _db;
    final rows = await db.query(
      'homework_submissions',
      where: 'homework_id = ? AND user_id = ?',
      whereArgs: [homeworkId, userId],
      orderBy: 'item_id',
    );
    return rows.map((r) => HomeworkSubmissionModel.fromMap(r)).toList();
  }

  /// 获取某次作业所有学生的提交
  Future<List<HomeworkSubmissionModel>> getAllSubmissions(int homeworkId) async {
    final db = await _db;
    final rows = await db.query(
      'homework_submissions',
      where: 'homework_id = ?',
      whereArgs: [homeworkId],
      orderBy: 'user_id, item_id',
    );
    return rows.map((r) => HomeworkSubmissionModel.fromMap(r)).toList();
  }

  /// AI 批阅后更新分数和评语
  Future<void> updateAiGrade(int submissionId, int score, String comment) async {
    final db = await _db;
    await db.update(
      'homework_submissions',
      {
        'score': score,
        'ai_comment': comment,
        'status': 'ai_graded',
        'graded_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [submissionId],
    );
  }

  /// 教师审核后更新评语
  Future<void> updateTeacherReview(
      int submissionId, int? score, String comment) async {
    final db = await _db;
    final updates = <String, dynamic>{
      'teacher_comment': comment,
      'status': 'teacher_reviewed',
      'graded_at': DateTime.now().toIso8601String(),
    };
    if (score != null) updates['score'] = score;
    await db.update('homework_submissions', updates,
        where: 'id = ?', whereArgs: [submissionId]);
  }

  /// 获取学生某次作业的总分
  Future<int> getStudentScore(int homeworkId, String userId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(score), 0) as total FROM homework_submissions '
      'WHERE homework_id = ? AND user_id = ? AND score IS NOT NULL',
      [homeworkId, userId],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// 获取某次作业的提交统计
  Future<Map<String, int>> getSubmissionStats(int homeworkId) async {
    final db = await _db;
    final total = await db.rawQuery(
      'SELECT COUNT(DISTINCT user_id) as cnt FROM homework_submissions WHERE homework_id = ?',
      [homeworkId],
    );
    final graded = await db.rawQuery(
      'SELECT COUNT(DISTINCT user_id) as cnt FROM homework_submissions WHERE homework_id = ? AND status = ?',
      [homeworkId, 'teacher_reviewed'],
    );
    return {
      'total': (total.first['cnt'] as int?) ?? 0,
      'graded': (graded.first['cnt'] as int?) ?? 0,
    };
  }

  /// ── 达成度计算 ──────────────────────────────────────────────────────────────

  /// 获取学生某课程所有作业的平均分（用于达成度计算）
  /// 返回 0-100 分值
  Future<double> getStudentHomeworkAverage(String courseId, String userId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT AVG(hs.score) as avg_score
      FROM homework_submissions hs
      JOIN homeworks hw ON hw.id = hs.homework_id
      WHERE hw.course_id = ? AND hs.user_id = ? AND hs.score IS NOT NULL
    ''', [courseId, userId]);
    return (result.first['avg_score'] as num?)?.toDouble() ?? 0.0;
  }

  /// 获取学生各章节作业分数（用于目标贡献度计算）
  /// 返回 Map<chapter, averageScore>
  Future<Map<String, double>> getStudentHomeworkByChapter(
      String courseId, String userId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT hw.chapter, AVG(hs.score) as avg_score
      FROM homework_submissions hs
      JOIN homeworks hw ON hw.id = hs.homework_id
      WHERE hw.course_id = ? AND hs.user_id = ? AND hs.score IS NOT NULL
      GROUP BY hw.chapter
    ''', [courseId, userId]);
    final map = <String, double>{};
    for (final row in result) {
      final chapter = row['chapter'] as String? ?? '';
      final avg = (row['avg_score'] as num?)?.toDouble() ?? 0.0;
      if (chapter.isNotEmpty) map[chapter] = avg;
    }
    return map;
  }

  /// 获取全班作业平均分（用于班级达成度报告）
  Future<Map<String, double>> getClassHomeworkAverages(String courseId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT hw.chapter, AVG(hs.score) as avg_score, COUNT(DISTINCT hs.user_id) as student_count
      FROM homework_submissions hs
      JOIN homeworks hw ON hw.id = hs.homework_id
      WHERE hw.course_id = ? AND hs.score IS NOT NULL
      GROUP BY hw.chapter
    ''', [courseId]);
    final map = <String, double>{};
    for (final row in result) {
      final chapter = row['chapter'] as String? ?? '';
      final avg = (row['avg_score'] as num?)?.toDouble() ?? 0.0;
      if (chapter.isNotEmpty) map[chapter] = avg;
    }
    return map;
  }

  /// 导入作业数据到 achievement_pingshi_scores 表（兼容旧达成度系统）
  Future<void> syncToAchievementScores(String courseId) async {
    final db = await _db;
    // 获取所有有提交的学生
    final students = await db.rawQuery('''
      SELECT DISTINCT hs.user_id
      FROM homework_submissions hs
      JOIN homeworks hw ON hw.id = hs.homework_id
      WHERE hw.course_id = ? AND hs.score IS NOT NULL
    ''', [courseId]);

    for (final student in students) {
      final userId = student['user_id'] as String;
      final avg = await getStudentHomeworkAverage(courseId, userId);
      // 写入 achievement_pingshi_scores（type=homework）
      await db.rawInsert('''
        INSERT OR REPLACE INTO achievement_pingshi_scores (user_id, type, score, updated_at)
        VALUES (?, 'homework', ?, ?)
      ''', [userId, avg.round(), DateTime.now().toIso8601String()]);
    }
  }

  /// ── 从 JSON 导入 ──────────────────────────────────────────────────────────

  /// 从 homework.json 导入作业到数据库
  Future<int> importFromJson(String courseId, String jsonContent) async {
    final db = await _db;
    final List<dynamic> homeworkList = jsonDecode(jsonContent);
    int count = 0;

    for (final hw in homeworkList) {
      final homework = HomeworkModel(
        id: 0, // 自增
        courseId: courseId,
        title: '${hw['chapter_title'] ?? ''}作业',
        description: '',
        chapter: hw['chapter'] ?? '',
        chapterTitle: hw['chapter_title'] ?? '',
        courseObjective: hw['course_objective'] ?? '',
        totalScore: 300,
        status: 'published',
        createdAt: DateTime.now(),
      );
      final hwId = await createHomework(homework);

      final items = (hw['items'] as List?) ?? [];
      final itemModels = items.map((item) {
        final om = (item['objective_mapping'] as List?)
                ?.map((e) => ObjectiveMapping.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [];
        return HomeworkItemModel(
          id: 0,
          homeworkId: hwId,
          itemIndex: 0,
          type: item['type_code'] ?? 'basic',
          typeLabel: item['type'] ?? '基础题',
          question: item['question'] ?? '',
          referenceAnswer: item['reference_answer'],
          maxScore: item['max_score'] ?? 100,
          objectiveMapping: om,
        );
      }).toList();
      await insertItems(hwId, itemModels);
      count++;
    }
    return count;
  }
}
