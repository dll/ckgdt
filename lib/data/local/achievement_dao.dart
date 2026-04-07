import 'dart:convert';
import 'dart:math' show sqrt;
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// 课程达成度 DAO — 达成度批次管理、成绩录入、计算、报告生成
class AchievementDao {
  // ═══════════════════════════════════════════════════════════════════════
  // 批次 CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// 获取所有批次（含学生人数子查询）
  Future<List<Map<String, dynamic>>> getAllBatches() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT ab.*,
        (SELECT COUNT(*) FROM achievement_scores WHERE batch_id = ab.id) AS student_count
      FROM achievement_batches ab
      ORDER BY ab.created_at DESC
    ''');
  }

  /// 获取单个批次
  Future<Map<String, dynamic>?> getBatch(int id) async {
    final db = await DatabaseHelper.instance.database;
    final list = await db.query('achievement_batches',
        where: 'id = ?', whereArgs: [id]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 创建批次
  Future<int> createBatch(Map<String, dynamic> batch) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    batch['created_at'] = now;
    batch['updated_at'] = now;
    return db.insert('achievement_batches', batch);
  }

  /// 更新批次
  Future<int> updateBatch(int id, Map<String, dynamic> batch) async {
    final db = await DatabaseHelper.instance.database;
    batch['updated_at'] = DateTime.now().toIso8601String();
    return db.update('achievement_batches', batch,
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除批次（级联删除分数）
  Future<int> deleteBatch(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('achievement_scores',
        where: 'batch_id = ?', whereArgs: [id]);
    return db.delete('achievement_batches',
        where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 学生成绩 CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// 获取批次内所有学生成绩
  Future<List<Map<String, dynamic>>> getScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('achievement_scores',
        where: 'batch_id = ?',
        whereArgs: [batchId],
        orderBy: 'student_id ASC');
  }

  /// 添加学生成绩
  Future<int> insertScore(Map<String, dynamic> score) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    score['created_at'] = now;
    score['updated_at'] = now;
    return db.insert('achievement_scores', score,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 批量添加学生成绩
  Future<int> batchAddScores(int batchId, List<Map<String, dynamic>> scores) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final score in scores) {
      score['batch_id'] = batchId;
      score['created_at'] = now;
      score['updated_at'] = now;
      batch.insert('achievement_scores', score,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final results = await batch.commit(noResult: false);
    return results.length;
  }

  /// 更新学生成绩
  Future<int> updateScore(int id, Map<String, dynamic> score) async {
    final db = await DatabaseHelper.instance.database;
    score['updated_at'] = DateTime.now().toIso8601String();
    return db.update('achievement_scores', score,
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除学生成绩
  Future<int> deleteScore(int id) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('achievement_scores', where: 'id = ?', whereArgs: [id]);
  }

  /// 清空批次成绩
  Future<int> clearScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('achievement_scores',
        where: 'batch_id = ?', whereArgs: [batchId]);
  }

  /// 获取批次内学生数量
  Future<int> getScoreCount(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as c FROM achievement_scores WHERE batch_id = ?',
        [batchId]);
    return (result.first['c'] as int?) ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 达成度计算（移植自 Python course_achievement_gui.py）
  // ═══════════════════════════════════════════════════════════════════════

  /// 计算批次的班级平均达成度
  Future<Map<String, double>> calculateClassAverage(int batchId) async {
    final scores = await getScores(batchId);
    if (scores.isEmpty) return {};

    double sum1 = 0, sum2 = 0, sum3 = 0, sum4 = 0, sumTotal = 0;
    for (final s in scores) {
      sum1 += (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
      sum2 += (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
      sum3 += (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
      sum4 += (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
      sumTotal += (s['total_score'] as num?)?.toDouble() ?? 0;
    }

    final n = scores.length.toDouble();
    return {
      '课程目标1': sum1 / n,
      '课程目标2': sum2 / n,
      '课程目标3': sum3 / n,
      '课程目标4': sum4 / n,
      '总评': sumTotal / n / 100,
    };
  }

  /// 计算加权总达成度
  double calculateWeightedAchievement(
      Map<String, double> avgAchievements,
      Map<String, double> objectiveWeights) {
    double weighted = 0;
    for (final entry in objectiveWeights.entries) {
      final key = entry.key;
      weighted += (avgAchievements[key] ?? 0) * entry.value;
    }
    return weighted;
  }

  /// 获取学生统计数据（最大/最小/标准差）
  Future<Map<String, Map<String, double>>> getStudentStats(int batchId) async {
    final scores = await getScores(batchId);
    if (scores.isEmpty) return {};

    final obj1 = scores.map((s) => (s['obj1_achievement'] as num?)?.toDouble() ?? 0).toList();
    final obj2 = scores.map((s) => (s['obj2_achievement'] as num?)?.toDouble() ?? 0).toList();
    final obj3 = scores.map((s) => (s['obj3_achievement'] as num?)?.toDouble() ?? 0).toList();
    final obj4 = scores.map((s) => (s['obj4_achievement'] as num?)?.toDouble() ?? 0).toList();

    return {
      '课程目标1': _calcStats(obj1),
      '课程目标2': _calcStats(obj2),
      '课程目标3': _calcStats(obj3),
      '课程目标4': _calcStats(obj4),
    };
  }

  Map<String, double> _calcStats(List<double> values) {
    if (values.isEmpty) return {'mean': 0, 'max': 0, 'min': 0, 'std': 0};
    final n = values.length;
    final mean = values.reduce((a, b) => a + b) / n;
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
    final std = sqrt(variance);
    return {'mean': mean, 'max': max, 'min': min, 'std': std};
  }

  /// 获取达成度等级
  String getAchievementLevel(double achievement) {
    if (achievement >= 0.85) return '优秀 (≥0.85)';
    if (achievement >= 0.70) return '良好 (0.70-0.84)';
    if (achievement >= 0.60) return '中等 (0.60-0.69)';
    return '未达成 (<0.60)';
  }

  /// 生成 Markdown 报告
  Future<String> generateMarkdownReport(int batchId) async {
    final batch = await getBatch(batchId);
    if (batch == null) return '批次不存在';

    final courseName = batch['course_name'] ?? '移动应用开发';
    final className = batch['class_name'] ?? '软件23';
    final scores = await getScores(batchId);
    final avgAchievements = await calculateClassAverage(batchId);
    final stats = await getStudentStats(batchId);

    // 解析权重
    Map<String, double> objWeights;
    try {
      final weightsJson = batch['objective_weights_json'] as String? ?? '{}';
      final parsed = jsonDecode(weightsJson) as Map<String, dynamic>;
      objWeights = {
        '课程目标1': (parsed['目标1'] as num?)?.toDouble() ?? 0.15,
        '课程目标2': (parsed['目标2'] as num?)?.toDouble() ?? 0.25,
        '课程目标3': (parsed['目标3'] as num?)?.toDouble() ?? 0.30,
        '课程目标4': (parsed['目标4'] as num?)?.toDouble() ?? 0.30,
      };
    } catch (_) {
      objWeights = {'课程目标1': 0.15, '课程目标2': 0.25, '课程目标3': 0.30, '课程目标4': 0.30};
    }

    final weighted = calculateWeightedAchievement(avgAchievements, objWeights);
    final level = getAchievementLevel(weighted);

    final now = DateTime.now();
    final dateStr = '${now.year}年${now.month}月${now.day}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final buf = StringBuffer();
    buf.writeln('# $className《$courseName》课程达成度报告');
    buf.writeln();
    buf.writeln('**生成时间：** $dateStr');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 一、课程目标达成情况');
    buf.writeln();
    buf.writeln('### 1. 班级平均达成度');
    buf.writeln();
    buf.writeln('| 课程目标 | 达成度 | 权重 | 加权贡献 |');
    buf.writeln('|---------|-------|------|---------|');

    for (int i = 1; i <= 4; i++) {
      final key = '课程目标$i';
      final ach = avgAchievements[key] ?? 0;
      final w = objWeights[key] ?? 0;
      buf.writeln('| $key | ${ach.toStringAsFixed(4)} | ${w.toStringAsFixed(2)} | ${(ach * w).toStringAsFixed(4)} |');
    }
    buf.writeln('| **加权总达成度** | **${weighted.toStringAsFixed(4)}** | **1.00** | **${weighted.toStringAsFixed(4)}** |');
    buf.writeln();
    buf.writeln('### 2. 学生个体达成情况');
    buf.writeln();
    buf.writeln('共有 **${scores.length}** 名学生参与评价。');
    buf.writeln();
    buf.writeln('#### 学生达成度统计');
    buf.writeln();
    buf.writeln('| 统计指标 | 课程目标1 | 课程目标2 | 课程目标3 | 课程目标4 |');
    buf.writeln('|---------|----------|----------|----------|----------|');

    for (final metric in ['mean', 'max', 'min', 'std']) {
      final label = {'mean': '平均值', 'max': '最大值', 'min': '最小值', 'std': '标准差'}[metric]!;
      buf.write('| $label ');
      for (int i = 1; i <= 4; i++) {
        final key = '课程目标$i';
        final val = stats[key]?[metric] ?? 0;
        buf.write('| ${val.toStringAsFixed(4)} ');
      }
      buf.writeln('|');
    }

    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 二、达成度分析');
    buf.writeln();

    for (int i = 1; i <= 4; i++) {
      final key = '课程目标$i';
      final ach = avgAchievements[key] ?? 0;
      final performance = ach >= 0.7 ? '良好' : '一般';
      buf.writeln('#### ${key}分析');
      buf.writeln('**达成度：** ${ach.toStringAsFixed(4)}');
      buf.writeln();
      buf.writeln('从达成度结果可以看出，学生在$key方面表现$performance。');
      buf.writeln();
    }

    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 三、结论');
    buf.writeln();
    buf.writeln('通过本次课程达成度评价，我们可以看到：');
    buf.writeln();
    buf.writeln('1. **整体表现**：学生在${courseName}课程的学习中取得了一定的成果，加权总达成度为${weighted.toStringAsFixed(4)}。');
    buf.writeln();
    buf.writeln('2. **达成度等级**：$level');
    buf.writeln();
    buf.writeln('3. **改进方向**：通过持续的教学改进，我们相信学生的能力将得到进一步提升。');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('**报告生成完成**');

    final report = buf.toString();

    // 保存报告到批次
    await updateBatch(batchId, {'report_content': report, 'status': 'completed'});

    return report;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 演示数据生成
  // ═══════════════════════════════════════════════════════════════════════

  /// 生成演示数据（模拟30名学生的达成度数据）
  Future<int> generateDemoData({String? teacherId}) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    // 创建批次
    final batchId = await db.insert('achievement_batches', {
      'batch_name': '2025-2026学年第二学期达成度评价',
      'course_name': '移动应用开发',
      'class_name': '软件23',
      'semester': '2025-2026-2',
      'teacher_id': teacherId ?? '206004',
      'objective_weights_json': '{"目标1":0.15,"目标2":0.25,"目标3":0.30,"目标4":0.30}',
      'assessment_weights_json': '{"平时":0.20,"实验":0.30,"期末":0.50}',
      'status': 'draft',
      'created_at': now,
      'updated_at': now,
    });

    // 从 users 表读取学生
    final students = await db.query('users',
        where: "role = 'student' AND is_active = 1",
        orderBy: 'user_id ASC',
        limit: 50);

    if (students.isEmpty) {
      // 使用模拟数据
      final simStudents = List.generate(30, (i) => <String, String>{
        'student_id': '2023${(i + 1).toString().padLeft(4, '0')}',
        'student_name': '学生${i + 1}',
      });
      return _insertDemoScores(db, batchId, simStudents, now);
    }

    final stuData = students.map((s) => <String, String>{
      'student_id': s['user_id'] as String? ?? '',
      'student_name': s['real_name'] as String? ?? s['user_id'] as String? ?? '',
    }).toList();

    return _insertDemoScores(db, batchId, stuData, now);
  }

  Future<int> _insertDemoScores(Database db, int batchId,
      List<Map<String, String>> students, String now) async {
    final batch = db.batch();
    int seed = 42;
    for (final stu in students) {
      // 伪随机生成达成度 0.55~0.95
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final obj1Ach = 0.55 + (seed % 40) / 100;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final obj2Ach = 0.55 + (seed % 40) / 100;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final obj3Ach = 0.55 + (seed % 40) / 100;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final obj4Ach = 0.55 + (seed % 40) / 100;

      final totalScore = obj1Ach * 15 + obj2Ach * 25 + obj3Ach * 30 + obj4Ach * 30;

      batch.insert('achievement_scores', {
        'batch_id': batchId,
        'student_id': stu['student_id'],
        'student_name': stu['student_name'],
        'obj1_score': (obj1Ach * 15).toDouble(),
        'obj1_achievement': obj1Ach,
        'obj2_score': (obj2Ach * 25).toDouble(),
        'obj2_achievement': obj2Ach,
        'obj3_score': (obj3Ach * 30).toDouble(),
        'obj3_achievement': obj3Ach,
        'obj4_score': (obj4Ach * 30).toDouble(),
        'obj4_achievement': obj4Ach,
        'total_score': totalScore,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    return students.length;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 页面适配方法（别名 & 便捷方法）
  // ═══════════════════════════════════════════════════════════════════════

  /// getBatches — 别名，等价于 getAllBatches()
  Future<List<Map<String, dynamic>>> getBatches() => getAllBatches();

  /// getScoresByBatch — 别名，等价于 getScores(batchId)
  Future<List<Map<String, dynamic>>> getScoresByBatch(int batchId) =>
      getScores(batchId);

  /// addBatch — 命名参数便捷方法
  Future<int> addBatch({
    required String batchName,
    String courseName = '移动应用开发',
    String className = '软件23',
    String semester = '',
    String teacherId = '',
  }) {
    return createBatch({
      'batch_name': batchName,
      'course_name': courseName,
      'class_name': className,
      'semester': semester,
      'teacher_id': teacherId,
      'status': 'draft',
    });
  }

  /// addScore — 命名参数便捷方法（计算达成度后插入）
  Future<int> addScore({
    required int batchId,
    required String studentId,
    required String studentName,
    required double objective1Score,
    required double objective2Score,
    required double objective3Score,
    required double objective4Score,
    required double totalScore,
  }) {
    // 按满分 15/25/30/30 计算达成度
    return insertScore({
      'batch_id': batchId,
      'student_id': studentId,
      'student_name': studentName,
      'obj1_score': objective1Score,
      'obj1_achievement': (objective1Score / 15).clamp(0.0, 1.0),
      'obj2_score': objective2Score,
      'obj2_achievement': (objective2Score / 25).clamp(0.0, 1.0),
      'obj3_score': objective3Score,
      'obj3_achievement': (objective3Score / 30).clamp(0.0, 1.0),
      'obj4_score': objective4Score,
      'obj4_achievement': (objective4Score / 30).clamp(0.0, 1.0),
      'total_score': totalScore,
    });
  }

  /// initDemoDataIfEmpty — 仅当无批次时生成演示数据
  Future<void> initDemoDataIfEmpty() async {
    final batches = await getAllBatches();
    if (batches.isEmpty) {
      await generateDemoData();
    }
  }

  /// updateBatchStatus — 更新批次状态
  Future<int> updateBatchStatus(int batchId, String status) {
    return updateBatch(batchId, {'status': status});
  }

  /// saveCalculationResults — 将计算后的达成度保存到批次
  Future<void> saveCalculationResults({
    required int batchId,
    required double objective1Achievement,
    required double objective2Achievement,
    required double objective3Achievement,
    required double objective4Achievement,
    required double weightedAchievement,
  }) async {
    final results = {
      'objective1_achievement': objective1Achievement,
      'objective2_achievement': objective2Achievement,
      'objective3_achievement': objective3Achievement,
      'objective4_achievement': objective4Achievement,
      'weighted_achievement': weightedAchievement,
    };
    await updateBatch(batchId, {
      'calc_results_json': jsonEncode(results),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// getCalculationResults — 从批次读取已保存的计算结果
  Future<Map<String, dynamic>?> getCalculationResults(int batchId) async {
    final batch = await getBatch(batchId);
    if (batch == null) return null;
    final json = batch['calc_results_json'] as String?;
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// generateDemoScores — 为已有批次生成演示成绩
  Future<int> generateDemoScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    // 先清空已有成绩
    await clearScores(batchId);

    // 从 users 表读取学生
    final students = await db.query('users',
        where: "role = 'student' AND is_active = 1",
        orderBy: 'user_id ASC',
        limit: 50);

    List<Map<String, String>> stuData;
    if (students.isEmpty) {
      stuData = List.generate(30, (i) => <String, String>{
        'student_id': '2023${(i + 1).toString().padLeft(4, '0')}',
        'student_name': '学生${i + 1}',
      });
    } else {
      stuData = students.map((s) => <String, String>{
        'student_id': s['user_id'] as String? ?? '',
        'student_name': s['real_name'] as String? ?? s['user_id'] as String? ?? '',
      }).toList();
    }

    return _insertDemoScores(db, batchId, stuData, now);
  }

  /// generateScoresFromQuizResults — 从测验成绩自动计算达成度
  Future<int> generateScoresFromQuizResults(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    // 先清空已有成绩
    await clearScores(batchId);

    // 获取所有学生的测验成绩汇总
    final quizData = await db.rawQuery(
      'SELECT user_id, COUNT(*) as quiz_count, AVG(score) as avg_score, '
      'SUM(num_correct) as total_correct, SUM(num_total) as total_questions '
      'FROM quiz_results GROUP BY user_id ORDER BY user_id'
    );

    if (quizData.isEmpty) {
      throw Exception('没有测验成绩数据，请先让学生完成章节测验，或使用「批量录入」生成演示数据');
    }

    final batchOp = db.batch();
    for (final q in quizData) {
      final userId = q['user_id'] as String? ?? '';
      final avgScore = (q['avg_score'] as num?)?.toDouble() ?? 0;
      final totalCorrect = (q['total_correct'] as num?)?.toDouble() ?? 0;
      final totalQuestions = (q['total_questions'] as num?)?.toDouble() ?? 1;
      final correctRate = totalCorrect / totalQuestions;

      // 查找用户真名
      final userRows = await db.query('users',
          where: 'user_id = ?', whereArgs: [userId], limit: 1);
      final userName = userRows.isNotEmpty
          ? (userRows.first['real_name'] as String? ?? userId)
          : userId;

      // 映射到四个课程目标
      final obj1Score = avgScore * 0.15;
      final obj2Score = correctRate * 25;
      final obj3Score = avgScore * 0.30;
      final obj4Score = correctRate * 30;
      final totalScore = obj1Score + obj2Score + obj3Score + obj4Score;

      batchOp.insert('achievement_scores', {
        'batch_id': batchId,
        'student_id': userId,
        'student_name': userName,
        'obj1_score': obj1Score,
        'obj1_achievement': (obj1Score / 15).clamp(0.0, 1.0),
        'obj2_score': obj2Score,
        'obj2_achievement': (obj2Score / 25).clamp(0.0, 1.0),
        'obj3_score': obj3Score,
        'obj3_achievement': (obj3Score / 30).clamp(0.0, 1.0),
        'obj4_score': obj4Score,
        'obj4_achievement': (obj4Score / 30).clamp(0.0, 1.0),
        'total_score': totalScore,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batchOp.commit(noResult: true);
    return quizData.length;
  }


  // ═══════════════════════════════════════════════════════════════════════
  // 资源关联
  // ═══════════════════════════════════════════════════════════════════════

  /// 获取章节关联的资源
  Future<List<Map<String, dynamic>>> getResourcesForChapter(int chapterNumber) async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT r.*, m.match_confidence
      FROM resource_chapter_mapping m
      JOIN resource_files r ON m.resource_id = r.id
      WHERE m.chapter_number = ?
      ORDER BY r.file_type, r.file_name
    ''', [chapterNumber]);
  }

  /// 自动建立资源-章节关联（基于关键词匹配）
  Future<int> autoMapResources() async {
    final db = await DatabaseHelper.instance.database;
    final resources = await db.query('resource_files');

    // 章节关键词映射
    final chapterKeywords = {
      1: ['技术体系', '移动应用', '全景', '概述', '第一章', '开发环境'],
      2: ['原生开发', 'Android', 'iOS', 'Kotlin', 'Swift', '第二章'],
      3: ['跨平台', 'Flutter', 'React Native', 'Uniapp', 'MAUI', '混合开发', '第三章'],
      4: ['小程序', '微信', 'WXML', 'WXSS', 'Taro', '第四章'],
      5: ['鸿蒙', 'HarmonyOS', 'ArkUI', 'ArkTS', '分布式', '多端', '第五章'],
      6: ['综合', '实践', '项目', 'Git', '团队', '第六章'],
    };

    int count = 0;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    for (final res in resources) {
      final fileName = (res['file_name'] as String? ?? '').toLowerCase();
      final filePath = (res['file_path'] as String? ?? '').toLowerCase();
      final desc = (res['description'] as String? ?? '').toLowerCase();
      final combined = '$fileName $filePath $desc';

      for (final entry in chapterKeywords.entries) {
        final chapter = entry.key;
        final keywords = entry.value;

        double confidence = 0;
        int matchCount = 0;
        for (final kw in keywords) {
          if (combined.contains(kw.toLowerCase())) {
            matchCount++;
          }
        }

        if (matchCount > 0) {
          confidence = matchCount / keywords.length;
          if (confidence >= 0.15) {
            batch.insert('resource_chapter_mapping', {
              'resource_id': res['id'],
              'resource_type': res['file_type'],
              'chapter_number': chapter,
              'chapter_title': '第${chapter}章',
              'match_confidence': confidence,
              'created_at': now,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            count++;
          }
        }
      }
    }
    await batch.commit(noResult: true);
    return count;
  }
}
