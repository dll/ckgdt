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
      buf.writeln('| $key | ${ach.toStringAsFixed(2)} | ${w.toStringAsFixed(2)} | ${(ach * w).toStringAsFixed(2)} |');
    }
    buf.writeln('| **加权总达成度** | **${weighted.toStringAsFixed(2)}** | **1.00** | **${weighted.toStringAsFixed(2)}** |');
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
        buf.write('| ${val.toStringAsFixed(2)} ');
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
      buf.writeln('**达成度：** ${ach.toStringAsFixed(2)}');
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
    buf.writeln('1. **整体表现**：学生在${courseName}课程的学习中取得了一定的成果，加权总达成度为${weighted.toStringAsFixed(2)}。');
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

  // ═══════════════════════════════════════════════════════════════════════
  // 问卷满意度集成 — 将问卷调查结果整合到达成度报告
  // ═══════════════════════════════════════════════════════════════════════

  /// 获取满意度调查汇总（用于达成度报告整合）
  /// 返回: {surveys: [...], overallSatisfaction: 0.0~1.0, totalResponses: N, questionStats: [...]}
  Future<Map<String, dynamic>> getSurveySatisfactionSummary() async {
    final db = await DatabaseHelper.instance.database;

    try {
      // 获取所有已发布/关闭的问卷
      final surveys = await db.query('surveys',
          where: "status IN ('published', 'closed')",
          orderBy: 'created_at DESC');

      if (surveys.isEmpty) {
        return {
          'surveys': <Map<String, dynamic>>[],
          'overallSatisfaction': 0.0,
          'totalResponses': 0,
          'questionStats': <Map<String, dynamic>>[],
          'hasSurveyData': false,
        };
      }

      int totalResponses = 0;
      double satisfactionSum = 0;
      int satisfactionCount = 0;
      final allQuestionStats = <Map<String, dynamic>>[];

      for (final survey in surveys) {
        final surveyId = survey['id'] as int;
        final responses = await db.query('survey_responses',
            where: 'survey_id = ?', whereArgs: [surveyId]);
        totalResponses += responses.length;

        // 获取题目
        final questions = await db.query('survey_questions',
            where: 'survey_id = ?',
            whereArgs: [surveyId],
            orderBy: 'seq ASC');

        for (final q in questions) {
          final qId = q['id'].toString();
          final qType = q['question_type'] as String? ?? 'single_choice';
          final optionsJson = q['options_json'] as String?;
          final options = optionsJson != null
              ? List<String>.from(jsonDecode(optionsJson))
              : <String>[];

          if (qType == 'rating') {
            // 评分题直接计算满意度
            double sum = 0;
            int count = 0;
            for (final resp in responses) {
              final answersJson = resp['answers_json'] as String?;
              if (answersJson == null) continue;
              final answers =
                  jsonDecode(answersJson) as Map<String, dynamic>;
              final answer = answers[qId];
              if (answer != null) {
                final val = int.tryParse(answer.toString()) ?? 0;
                if (val > 0) {
                  sum += val;
                  count++;
                }
              }
            }
            if (count > 0) {
              satisfactionSum += sum / count / 5.0; // 归一化到0~1
              satisfactionCount++;
            }
            allQuestionStats.add({
              'question': q['question'],
              'type': 'rating',
              'average': count > 0 ? sum / count : 0,
              'count': count,
              'surveyTitle': survey['title'],
            });
          } else if (qType == 'single_choice' && options.isNotEmpty) {
            // 单选题 — 统计各选项
            final optionCounts = <String, int>{};
            for (final opt in options) {
              optionCounts[opt] = 0;
            }
            for (final resp in responses) {
              final answersJson = resp['answers_json'] as String?;
              if (answersJson == null) continue;
              final answers =
                  jsonDecode(answersJson) as Map<String, dynamic>;
              final answer = answers[qId];
              if (answer is String) {
                optionCounts[answer] = (optionCounts[answer] ?? 0) + 1;
              }
            }

            // 如果选项包含满意度关键词，计算满意度指数
            final satisfactionKeywords = ['非常满意', '满意'];
            int satisfiedCount = 0;
            int totalCount = 0;
            for (final entry in optionCounts.entries) {
              totalCount += entry.value;
              if (satisfactionKeywords
                  .any((k) => entry.key.contains(k))) {
                satisfiedCount += entry.value;
              }
            }
            if (totalCount > 0 &&
                options.any((o) => o.contains('满意'))) {
              satisfactionSum += satisfiedCount / totalCount;
              satisfactionCount++;
            }

            allQuestionStats.add({
              'question': q['question'],
              'type': 'single_choice',
              'options': options,
              'counts': optionCounts,
              'total': responses.length,
              'surveyTitle': survey['title'],
            });
          } else if (qType == 'text') {
            // 文本题收集文本
            final textAnswers = <String>[];
            for (final resp in responses) {
              final answersJson = resp['answers_json'] as String?;
              if (answersJson == null) continue;
              final answers =
                  jsonDecode(answersJson) as Map<String, dynamic>;
              final answer = answers[qId];
              if (answer != null && answer.toString().isNotEmpty) {
                textAnswers.add(answer.toString());
              }
            }
            allQuestionStats.add({
              'question': q['question'],
              'type': 'text',
              'answers': textAnswers,
              'surveyTitle': survey['title'],
            });
          }
        }
      }

      final overallSatisfaction =
          satisfactionCount > 0 ? satisfactionSum / satisfactionCount : 0.0;

      return {
        'surveys': surveys,
        'overallSatisfaction': overallSatisfaction,
        'totalResponses': totalResponses,
        'questionStats': allQuestionStats,
        'hasSurveyData': true,
      };
    } catch (e) {
      return {
        'surveys': <Map<String, dynamic>>[],
        'overallSatisfaction': 0.0,
        'totalResponses': 0,
        'questionStats': <Map<String, dynamic>>[],
        'hasSurveyData': false,
        'error': e.toString(),
      };
    }
  }

  /// 生成持续改进建议（基于达成度分析）
  Future<List<Map<String, dynamic>>> generateImprovementSuggestions(
      int batchId) async {
    final scores = await getScores(batchId);
    if (scores.isEmpty) return [];

    const fullMarks = [15.0, 25.0, 30.0, 30.0];
    const objectiveChapters = [
      '第1章 + 第2章',
      '第3章 + 第4章',
      '第5章',
      '第6章',
    ];
    const objectiveTopics = [
      ['移动应用开发技术体系', '原生/混合/跨平台技术', 'Android原生开发', 'iOS开发基础'],
      ['Flutter框架', 'React Native', '小程序开发', 'AI编程工具'],
      ['HarmonyOS多端开发', '跨设备适配', '技术方案评估', 'ArkUI/ArkTS'],
      ['Git版本控制', '软件工程规范', '应用测试与优化', '综合开发实践'],
    ];

    // 计算每个目标的平均达成度
    final objAchievements = List<double>.generate(4, (i) {
      final values = scores.map<double>((s) {
        return (s['obj${i + 1}_score'] ?? 0).toDouble();
      }).toList();
      final mean = values.reduce((a, b) => a + b) / values.length;
      return (mean / fullMarks[i]).clamp(0.0, 1.0);
    });

    // 统计低于60%的学生数
    final lowCountPerObj = List<int>.generate(4, (i) {
      return scores.where((s) {
        final ach = (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
        return ach < 0.6;
      }).length;
    });

    // 获取知识图谱节点数
    final db = await DatabaseHelper.instance.database;
    int graphNodeCount = 0;
    try {
      final nodeResult =
          await db.rawQuery('SELECT COUNT(*) as c FROM nodes');
      graphNodeCount = (nodeResult.first['c'] as int?) ?? 0;
    } catch (_) {}

    // 获取测验题数
    int quizQuestionCount = 0;
    try {
      final quizResult =
          await db.rawQuery('SELECT COUNT(*) as c FROM questions');
      quizQuestionCount = (quizResult.first['c'] as int?) ?? 0;
    } catch (_) {}

    // 每章测验题数
    final chapterQuizCounts = <int, int>{};
    try {
      final chapterStats = await db.rawQuery(
          'SELECT source, COUNT(*) as c FROM questions GROUP BY source');
      for (final row in chapterStats) {
        final source = row['source'] as String? ?? '';
        // 尝试从source中提取章节号
        final match = RegExp(r'(\d+)').firstMatch(source);
        if (match != null) {
          final ch = int.tryParse(match.group(1)!) ?? 0;
          chapterQuizCounts[ch] = (row['c'] as int?) ?? 0;
        }
      }
    } catch (_) {}

    final suggestions = <Map<String, dynamic>>[];

    for (int i = 0; i < 4; i++) {
      final ach = objAchievements[i];
      final level = getAchievementLevel(ach);
      final lowCount = lowCountPerObj[i];
      final topics = objectiveTopics[i];
      final chapters = objectiveChapters[i];
      final actions = <String>[];

      if (ach < 0.60) {
        // 未达成 — 重点改进
        actions.addAll([
          '在知识图谱中增加${topics.join("、")}相关节点，丰富知识结构',
          '增加$chapters相关课时（建议增加2-4学时）',
          '增设${topics.first}和${topics.last}的章节测验和练习题',
          '增加$chapters的实验项目，强化动手能力',
          '对$lowCount名未达标学生制定一对一帮扶计划',
          '组织$chapters相关的技术专题工作坊',
        ]);
      } else if (ach < 0.70) {
        // 中等 — 有提升空间
        actions.addAll([
          '补充${topics.first}和${topics[1]}相关的知识图谱节点',
          '适当增加$chapters的课时（建议增加1-2学时）',
          '针对$chapters新增综合性测验，提高应用能力',
          '对$lowCount名未达标学生安排额外练习',
          '增加${topics.last}的案例教学内容',
        ]);
      } else if (ach < 0.85) {
        // 良好 — 巩固提高
        actions.addAll([
          '在知识图谱中补充${topics.first}的进阶节点',
          '增加$chapters的拓展阅读和实践项目',
          '保持现有$chapters教学节奏，适当提高考核难度',
        ]);
      } else {
        // 优秀 — 保持水平
        actions.addAll([
          '保持现有教学方案，持续更新$chapters教学内容',
          '鼓励优秀学生参与${topics.first}的教学辅助工作',
        ]);
      }

      suggestions.add({
        'objectiveIndex': i,
        'objectiveName': '课程目标${i + 1}',
        'achievement': ach,
        'level': level,
        'lowStudentCount': lowCount,
        'totalStudents': scores.length,
        'chapters': chapters,
        'topics': topics,
        'actions': actions,
      });
    }

    // 添加整体建议
    double weighted = 0;
    for (int i = 0; i < 4; i++) {
      weighted += objAchievements[i] * _kDefaultWeightsForSuggestion[i];
    }

    suggestions.add({
      'objectiveIndex': -1,
      'objectiveName': '整体教学改进',
      'achievement': weighted,
      'level': getAchievementLevel(weighted),
      'graphNodeCount': graphNodeCount,
      'quizQuestionCount': quizQuestionCount,
      'chapterQuizCounts': chapterQuizCounts,
      'totalStudents': scores.length,
      'actions': _buildOverallSuggestions(
          weighted, graphNodeCount, quizQuestionCount),
    });

    return suggestions;
  }

  static const _kDefaultWeightsForSuggestion = [0.15, 0.25, 0.30, 0.30];

  List<String> _buildOverallSuggestions(
      double weighted, int graphNodes, int quizCount) {
    final suggestions = <String>[];

    if (graphNodes < 50) {
      suggestions.add('当前知识图谱仅有$graphNodes个节点，建议扩展至60+个以覆盖完整知识体系');
    } else {
      suggestions.add('知识图谱已有$graphNodes个节点，建议持续更新以跟踪技术发展');
    }

    if (quizCount < 60) {
      suggestions.add('当前测验题库仅有$quizCount道题，建议扩充至100+道以覆盖所有知识点');
    }

    if (weighted < 0.7) {
      suggestions.addAll([
        '加权总达成度偏低，建议调整考核比例（增加平时过程性考核权重）',
        '增加实验课时占比，从30%提升至35%~40%',
        '引入阶段性小测验，及时发现学习困难学生',
      ]);
    } else {
      suggestions.addAll([
        '保持现有考核体系框架，在细节上持续优化',
        '定期更新教学案例，保持内容时效性',
      ]);
    }

    suggestions.add('每学期末开展课程满意度调查，建立教学质量持续反馈机制');

    return suggestions;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 三类评价分项成绩 — 平时 / 实验 / 期末
  // ═══════════════════════════════════════════════════════════════════════

  // ── 平时成绩 ─────────────────────────────────────────────────────────
  /// 课堂表现→目标1, 期间测验→目标2, 课外学习→目标4; 目标3无平时成绩

  Future<List<Map<String, dynamic>>> getPingshiScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('achievement_pingshi_scores',
        where: 'batch_id = ?', whereArgs: [batchId], orderBy: 'student_id ASC');
  }

  Future<int> insertPingshiScore(Map<String, dynamic> score) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    score['created_at'] = now;
    score['updated_at'] = now;
    return db.insert('achievement_pingshi_scores', score,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> clearPingshiScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('achievement_pingshi_scores',
        where: 'batch_id = ?', whereArgs: [batchId]);
  }

  /// 计算平时成绩的分项达成度
  /// 课堂表现(20%) → 目标1达成度 = score/100
  /// 期间测验(30%) → 目标2达成度 = score/100
  /// 课外学习(50%) → 目标4达成度 = score/100
  /// 总评 = 课堂×0.2 + 测验×0.3 + 课外×0.5
  Map<String, double> calculatePingshiAchievement(Map<String, dynamic> score) {
    final classScore = (score['class_activity_score'] as num?)?.toDouble() ?? 0;
    final quizScore = (score['quiz_homework_score'] as num?)?.toDouble() ?? 0;
    final extraScore = (score['extra_learning_score'] as num?)?.toDouble() ?? 0;

    final obj1Ach = (classScore / 100).clamp(0.0, 1.0);
    final obj2Ach = (quizScore / 100).clamp(0.0, 1.0);
    final obj4Ach = (extraScore / 100).clamp(0.0, 1.0);
    final total = classScore * 0.2 + quizScore * 0.3 + extraScore * 0.5;

    return {
      'obj1_achievement': obj1Ach,  // 课堂表现→目标1
      'obj2_achievement': obj2Ach,  // 期间测验→目标2
      'obj3_achievement': 0.0,      // 平时无目标3
      'obj4_achievement': obj4Ach,  // 课外学习→目标4
      'total_score': total,
    };
  }

  /// 计算平时成绩的班级平均达成度
  Future<Map<String, double>> calculatePingshiClassAverage(int batchId) async {
    final scores = await getPingshiScores(batchId);
    if (scores.isEmpty) return {'obj1': 0, 'obj2': 0, 'obj3': 0, 'obj4': 0};
    final n = scores.length.toDouble();
    double s1 = 0, s2 = 0, s4 = 0;
    for (final s in scores) {
      s1 += (s['class_activity_achievement'] as num?)?.toDouble() ?? 0;
      s2 += (s['quiz_homework_achievement'] as num?)?.toDouble() ?? 0;
      s4 += (s['extra_learning_achievement'] as num?)?.toDouble() ?? 0;
    }
    return {'obj1': s1 / n, 'obj2': s2 / n, 'obj3': 0.0, 'obj4': s4 / n};
  }

  /// 生成平时演示数据
  Future<int> generatePingshiDemoScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await clearPingshiScores(batchId);

    final students = await db.query('users',
        where: "role = 'student' AND is_active = 1",
        orderBy: 'user_id ASC', limit: 50);

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

    final batch = db.batch();
    int seed = 123;
    for (final stu in stuData) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final classScore = 55.0 + (seed % 45); // 55-99
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final quizScore = 50.0 + (seed % 50); // 50-99
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final extraScore = 50.0 + (seed % 50); // 50-99

      final ach = calculatePingshiAchievement({
        'class_activity_score': classScore,
        'quiz_homework_score': quizScore,
        'extra_learning_score': extraScore,
      });

      batch.insert('achievement_pingshi_scores', {
        'batch_id': batchId,
        'student_id': stu['student_id'],
        'student_name': stu['student_name'],
        'class_activity_score': classScore,
        'class_activity_achievement': ach['obj1_achievement'],
        'quiz_homework_score': quizScore,
        'quiz_homework_achievement': ach['obj2_achievement'],
        'extra_learning_score': extraScore,
        'extra_learning_achievement': ach['obj4_achievement'],
        'total_score': ach['total_score'],
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    return stuData.length;
  }

  // ── 实验成绩 ─────────────────────────────────────────────────────────
  /// 实验1-2→目标1, 实验3-4→目标2, 实验5-6→目标3, 实验7→目标4

  Future<List<Map<String, dynamic>>> getExperimentScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('achievement_experiment_scores',
        where: 'batch_id = ?', whereArgs: [batchId], orderBy: 'student_id ASC');
  }

  Future<int> insertExperimentScore(Map<String, dynamic> score) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    score['created_at'] = now;
    score['updated_at'] = now;
    return db.insert('achievement_experiment_scores', score,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> clearExperimentScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('achievement_experiment_scores',
        where: 'batch_id = ?', whereArgs: [batchId]);
  }

  /// 计算实验成绩的分项达成度
  /// 实验1-2平均/100→目标1, 实验3-4平均/100→目标2,
  /// 实验5-6平均/100→目标3, 实验7/100→目标4
  /// 总评 = 七次实验平均分
  Map<String, double> calculateExperimentAchievement(Map<String, dynamic> score) {
    final e1 = (score['exp1_score'] as num?)?.toDouble() ?? 0;
    final e2 = (score['exp2_score'] as num?)?.toDouble() ?? 0;
    final e3 = (score['exp3_score'] as num?)?.toDouble() ?? 0;
    final e4 = (score['exp4_score'] as num?)?.toDouble() ?? 0;
    final e5 = (score['exp5_score'] as num?)?.toDouble() ?? 0;
    final e6 = (score['exp6_score'] as num?)?.toDouble() ?? 0;
    final e7 = (score['exp7_score'] as num?)?.toDouble() ?? 0;

    final obj1Ach = ((e1 + e2) / 2 / 100).clamp(0.0, 1.0);
    final obj2Ach = ((e3 + e4) / 2 / 100).clamp(0.0, 1.0);
    final obj3Ach = ((e5 + e6) / 2 / 100).clamp(0.0, 1.0);
    final obj4Ach = (e7 / 100).clamp(0.0, 1.0);
    final total = (e1 + e2 + e3 + e4 + e5 + e6 + e7) / 7;

    return {
      'obj1_achievement': obj1Ach,
      'obj2_achievement': obj2Ach,
      'obj3_achievement': obj3Ach,
      'obj4_achievement': obj4Ach,
      'total_score': total,
    };
  }

  /// 计算实验成绩的班级平均达成度
  Future<Map<String, double>> calculateExperimentClassAverage(int batchId) async {
    final scores = await getExperimentScores(batchId);
    if (scores.isEmpty) return {'obj1': 0, 'obj2': 0, 'obj3': 0, 'obj4': 0};
    final n = scores.length.toDouble();
    double s1 = 0, s2 = 0, s3 = 0, s4 = 0;
    for (final s in scores) {
      s1 += (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
      s2 += (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
      s3 += (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
      s4 += (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
    }
    return {'obj1': s1 / n, 'obj2': s2 / n, 'obj3': s3 / n, 'obj4': s4 / n};
  }

  /// 生成实验演示数据
  Future<int> generateExperimentDemoScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await clearExperimentScores(batchId);

    final students = await db.query('users',
        where: "role = 'student' AND is_active = 1",
        orderBy: 'user_id ASC', limit: 50);

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

    final batch = db.batch();
    int seed = 456;
    for (final stu in stuData) {
      final expScores = <double>[];
      for (int j = 0; j < 7; j++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        expScores.add(50.0 + (seed % 50)); // 50-99
      }

      final ach = calculateExperimentAchievement({
        'exp1_score': expScores[0],
        'exp2_score': expScores[1],
        'exp3_score': expScores[2],
        'exp4_score': expScores[3],
        'exp5_score': expScores[4],
        'exp6_score': expScores[5],
        'exp7_score': expScores[6],
      });

      batch.insert('achievement_experiment_scores', {
        'batch_id': batchId,
        'student_id': stu['student_id'],
        'student_name': stu['student_name'],
        'exp1_score': expScores[0],
        'exp2_score': expScores[1],
        'exp3_score': expScores[2],
        'exp4_score': expScores[3],
        'exp5_score': expScores[4],
        'exp6_score': expScores[5],
        'exp7_score': expScores[6],
        'obj1_achievement': ach['obj1_achievement'],
        'obj2_achievement': ach['obj2_achievement'],
        'obj3_achievement': ach['obj3_achievement'],
        'obj4_achievement': ach['obj4_achievement'],
        'total_score': ach['total_score'],
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    return stuData.length;
  }

  // ── 期末考核成绩 ──────────────────────────────────────────────────────
  /// 项目30%→目标1, 小组20%→目标2, 个人20%→目标3, 答辩30%→目标4

  Future<List<Map<String, dynamic>>> getExamScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('achievement_exam_scores',
        where: 'batch_id = ?', whereArgs: [batchId], orderBy: 'student_id ASC');
  }

  Future<int> insertExamScore(Map<String, dynamic> score) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    score['created_at'] = now;
    score['updated_at'] = now;
    return db.insert('achievement_exam_scores', score,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> clearExamScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('achievement_exam_scores',
        where: 'batch_id = ?', whereArgs: [batchId]);
  }

  /// 计算期末考核的分项达成度
  /// 项目/100→目标1, 小组/100→目标2, 个人/100→目标3, 答辩/100→目标4
  /// 总评 = 项目×0.3 + 小组×0.2 + 个人×0.2 + 答辩×0.3
  Map<String, double> calculateExamAchievement(Map<String, dynamic> score) {
    final project = (score['project_score'] as num?)?.toDouble() ?? 0;
    final group = (score['group_score'] as num?)?.toDouble() ?? 0;
    final individual = (score['individual_score'] as num?)?.toDouble() ?? 0;
    final defense = (score['defense_score'] as num?)?.toDouble() ?? 0;

    final obj1Ach = (project / 100).clamp(0.0, 1.0);
    final obj2Ach = (group / 100).clamp(0.0, 1.0);
    final obj3Ach = (individual / 100).clamp(0.0, 1.0);
    final obj4Ach = (defense / 100).clamp(0.0, 1.0);
    final total = project * 0.3 + group * 0.2 + individual * 0.2 + defense * 0.3;

    return {
      'obj1_achievement': obj1Ach,
      'obj2_achievement': obj2Ach,
      'obj3_achievement': obj3Ach,
      'obj4_achievement': obj4Ach,
      'total_score': total,
    };
  }

  /// 计算期末考核的班级平均达成度
  Future<Map<String, double>> calculateExamClassAverage(int batchId) async {
    final scores = await getExamScores(batchId);
    if (scores.isEmpty) return {'obj1': 0, 'obj2': 0, 'obj3': 0, 'obj4': 0};
    final n = scores.length.toDouble();
    double s1 = 0, s2 = 0, s3 = 0, s4 = 0;
    for (final s in scores) {
      s1 += (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
      s2 += (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
      s3 += (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
      s4 += (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
    }
    return {'obj1': s1 / n, 'obj2': s2 / n, 'obj3': s3 / n, 'obj4': s4 / n};
  }

  /// 生成期末考核演示数据
  Future<int> generateExamDemoScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await clearExamScores(batchId);

    final students = await db.query('users',
        where: "role = 'student' AND is_active = 1",
        orderBy: 'user_id ASC', limit: 50);

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

    final batch = db.batch();
    int seed = 789;
    for (final stu in stuData) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final project = 50.0 + (seed % 50);
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final group = 50.0 + (seed % 50);
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final individual = 50.0 + (seed % 50);
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final defense = 50.0 + (seed % 50);

      final ach = calculateExamAchievement({
        'project_score': project,
        'group_score': group,
        'individual_score': individual,
        'defense_score': defense,
      });

      batch.insert('achievement_exam_scores', {
        'batch_id': batchId,
        'student_id': stu['student_id'],
        'student_name': stu['student_name'],
        'project_score': project,
        'group_score': group,
        'individual_score': individual,
        'defense_score': defense,
        'obj1_achievement': ach['obj1_achievement'],
        'obj2_achievement': ach['obj2_achievement'],
        'obj3_achievement': ach['obj3_achievement'],
        'obj4_achievement': ach['obj4_achievement'],
        'total_score': ach['total_score'],
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    return stuData.length;
  }

  // ── 综合达成度计算（三类评价加权汇总）──────────────────────────────
  /// 综合达成度 = 平时×0.2 + 实验×0.3 + 期末×0.5
  Future<Map<String, dynamic>> calculateCombinedAchievement(int batchId) async {
    final pingshi = await calculatePingshiClassAverage(batchId);
    final experiment = await calculateExperimentClassAverage(batchId);
    final exam = await calculateExamClassAverage(batchId);

    const pWeight = 0.2;
    const eWeight = 0.3;
    const xWeight = 0.5;

    final combined = <String, double>{};
    for (int i = 1; i <= 4; i++) {
      final key = 'obj$i';
      combined[key] = (pingshi[key] ?? 0) * pWeight +
          (experiment[key] ?? 0) * eWeight +
          (exam[key] ?? 0) * xWeight;
    }

    return {
      'pingshi': pingshi,
      'experiment': experiment,
      'exam': exam,
      'combined': combined,
      'weights': {'平时': pWeight, '实验': eWeight, '期末': xWeight},
    };
  }
}
