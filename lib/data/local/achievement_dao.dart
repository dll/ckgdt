import 'dart:convert';
import 'dart:math' show sqrt;
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../../core/error_handler.dart';
import '../../services/course_context_service.dart';

/// 课程达成度 DAO — 达成度批次管理、成绩录入、计算、报告生成
class AchievementDao {
  final CourseContextService _courseContext = CourseContextService();

  /// 4 个课程目标满分（与大纲第六节、AchievementConfig.defaults 一致）。
  /// DAO 属数据层，不能依赖 presentation 层的 AchievementConfig，故在此独立维护；
  /// 两处数值必须同步（大纲权威值 15/25/30/30）。
  static const List<double> _kFullMarks = [15.0, 25.0, 30.0, 30.0];

  // ═══════════════════════════════════════════════════════════════════════
  // 课程目标定义（course_objectives，权威源来自大纲导入）
  // ═══════════════════════════════════════════════════════════════════════

  /// 读取某课程的目标定义行（按 idx 升序）。无则返回空列表。
  Future<List<Map<String, dynamic>>> getCourseObjectives(
      [String courseName = '移动应用开发']) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('course_objectives',
        where: 'course_name = ?', whereArgs: [courseName], orderBy: 'idx ASC');
  }

  /// 覆盖写入某课程的目标定义（先删后插，保证与大纲一致）。
  /// [objectives] 每项含 idx/name/indicator/weight/full_mark/
  /// pingshi_ratio/experiment_ratio/exam_ratio/chapters/description/assess_content。
  Future<void> saveCourseObjectives(
      String courseName, List<Map<String, dynamic>> objectives) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('course_objectives',
          where: 'course_name = ?', whereArgs: [courseName]);
      for (final o in objectives) {
        await txn.insert('course_objectives', {
          'course_name': courseName,
          'idx': o['idx'],
          'name': o['name'],
          'indicator': o['indicator'],
          'weight': o['weight'],
          'full_mark': o['full_mark'],
          'pingshi_ratio': o['pingshi_ratio'] ?? 0,
          'experiment_ratio': o['experiment_ratio'] ?? 0,
          'exam_ratio': o['exam_ratio'] ?? 0,
          'chapters': o['chapters'],
          'description': o['description'],
          'assess_content': o['assess_content'],
          'experiments': o['experiments'],
          'pingshi_standard': o['pingshi_standard'],
          'experiment_standard': o['experiment_standard'],
          'assessment_items_json': o['assessment_items_json'],
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  }

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
    final list =
        await db.query('achievement_batches', where: 'id = ?', whereArgs: [id]);
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
    return db
        .update('achievement_batches', batch, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除批次（级联删除分数）
  Future<int> deleteBatch(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db
        .delete('achievement_scores', where: 'batch_id = ?', whereArgs: [id]);
    return db.delete('achievement_batches', where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 学生成绩 CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// 获取批次内所有学生成绩
  Future<List<Map<String, dynamic>>> getScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    // .toList() 把 sqflite 只读的 QueryResultSet 转成可变 List，
    // 否则调用方 sortScoresInPlace() 原地排序会抛 "Unsupported operation: read-only"。
    return (await db.query('achievement_scores',
            where: 'batch_id = ?',
            whereArgs: [batchId],
            orderBy: 'student_id ASC'))
        .toList();
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
  Future<int> batchAddScores(
      int batchId, List<Map<String, dynamic>> scores) async {
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
    return db
        .update('achievement_scores', score, where: 'id = ?', whereArgs: [id]);
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
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final activeIndexes = [
      for (var i = 0; i < 4; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0))
          i
    ];
    if (activeIndexes.isEmpty) activeIndexes.addAll([0, 1, 2, 3]);

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
      if (activeIndexes.contains(0)) '课程目标1': sum1 / n,
      if (activeIndexes.contains(1)) '课程目标2': sum2 / n,
      if (activeIndexes.contains(2)) '课程目标3': sum3 / n,
      if (activeIndexes.contains(3)) '课程目标4': sum4 / n,
      '总评': sumTotal / n / 100,
    };
  }

  /// 计算加权总达成度
  double calculateWeightedAchievement(Map<String, double> avgAchievements,
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
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final activeIndexes = [
      for (var i = 0; i < 4; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0))
          i
    ];
    if (activeIndexes.isEmpty) activeIndexes.addAll([0, 1, 2, 3]);

    final obj1 = scores
        .map((s) => (s['obj1_achievement'] as num?)?.toDouble() ?? 0)
        .toList();
    final obj2 = scores
        .map((s) => (s['obj2_achievement'] as num?)?.toDouble() ?? 0)
        .toList();
    final obj3 = scores
        .map((s) => (s['obj3_achievement'] as num?)?.toDouble() ?? 0)
        .toList();
    final obj4 = scores
        .map((s) => (s['obj4_achievement'] as num?)?.toDouble() ?? 0)
        .toList();

    return {
      if (activeIndexes.contains(0)) '课程目标1': _calcStats(obj1),
      if (activeIndexes.contains(1)) '课程目标2': _calcStats(obj2),
      if (activeIndexes.contains(2)) '课程目标3': _calcStats(obj3),
      if (activeIndexes.contains(3)) '课程目标4': _calcStats(obj4),
    };
  }

  Map<String, double> _calcStats(List<double> values) {
    if (values.isEmpty) return {'mean': 0, 'max': 0, 'min': 0, 'std': 0};
    final n = values.length;
    final mean = values.reduce((a, b) => a + b) / n;
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
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
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final objectiveRows = await getCourseObjectives(courseName.toString());
    final objectiveByIdx = <int, Map<String, dynamic>>{
      for (final row in objectiveRows)
        if (((row['idx'] as num?)?.toInt() ?? 0) > 0)
          (row['idx'] as num).toInt(): row
    };
    final activeIndexes = [
      for (var i = 0; i < 4; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0))
          i
    ];
    if (activeIndexes.isEmpty) activeIndexes.addAll([0, 1, 2, 3]);

    String objectiveName(int index) {
      final row = objectiveByIdx[index + 1];
      final name = row?['name']?.toString().trim() ?? '';
      return name.isNotEmpty ? name : '课程目标${index + 1}';
    }

    String objectiveDesc(int index) {
      final row = objectiveByIdx[index + 1];
      final desc = row?['description']?.toString().trim() ?? '';
      return desc.isNotEmpty ? desc : objectiveName(index);
    }

    var weighted = 0.0;
    var weightSum = 0.0;
    for (final i in activeIndexes) {
      final key = '课程目标${i + 1}';
      final weight = i < weights.length ? weights[i] : 0.0;
      weighted += (avgAchievements[key] ?? 0) * weight;
      weightSum += weight;
    }
    if (weightSum > 0 && (weightSum - 1.0).abs() > 0.0001) {
      weighted /= weightSum;
    }
    final level = getAchievementLevel(weighted);

    final now = DateTime.now();
    final dateStr =
        '${now.year}年${now.month}月${now.day}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

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

    for (final i in activeIndexes) {
      final key = '课程目标${i + 1}';
      final ach = avgAchievements[key] ?? 0;
      final w = i < weights.length ? weights[i] : 0.0;
      buf.writeln(
          '| ${objectiveName(i)} | ${ach.toStringAsFixed(2)} | ${w.toStringAsFixed(2)} | ${(ach * w).toStringAsFixed(2)} |');
    }
    buf.writeln(
        '| **加权总达成度** | **${weighted.toStringAsFixed(2)}** | **1.00** | **${weighted.toStringAsFixed(2)}** |');
    buf.writeln();
    buf.writeln('### 2. 学生个体达成情况');
    buf.writeln();
    buf.writeln('共有 **${scores.length}** 名学生参与评价。');
    buf.writeln();
    buf.writeln('#### 学生达成度统计');
    buf.writeln();
    buf.writeln('| 统计指标 | ${activeIndexes.map(objectiveName).join(' | ')} |');
    buf.writeln(
        '|---------|${activeIndexes.map((_) => '----------').join('|')}|');

    for (final metric in ['mean', 'max', 'min', 'std']) {
      final label =
          {'mean': '平均值', 'max': '最大值', 'min': '最小值', 'std': '标准差'}[metric]!;
      buf.write('| $label ');
      for (final i in activeIndexes) {
        final key = '课程目标${i + 1}';
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

    for (final i in activeIndexes) {
      final key = '课程目标${i + 1}';
      final ach = avgAchievements[key] ?? 0;
      final performance = ach >= 0.7 ? '良好' : '一般';
      buf.writeln('#### ${objectiveName(i)}分析');
      buf.writeln('**达成度：** ${ach.toStringAsFixed(2)}');
      buf.writeln();
      buf.writeln('从达成度结果可以看出，学生在“${objectiveDesc(i)}”方面表现$performance。');
      buf.writeln();
    }

    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 三、结论');
    buf.writeln();
    buf.writeln('通过本次课程达成度评价，我们可以看到：');
    buf.writeln();
    buf.writeln(
        '1. **整体表现**：学生在${courseName}课程的学习中取得了一定的成果，加权总达成度为${weighted.toStringAsFixed(2)}。');
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
    await updateBatch(
        batchId, {'report_content': report, 'status': 'completed'});

    return report;
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
  }) async {
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    double achievement(double score, double fullMark) =>
        fullMark > 0 ? (score / fullMark).clamp(0.0, 1.0) : 0.0;
    return insertScore({
      'batch_id': batchId,
      'student_id': studentId,
      'student_name': studentName,
      'obj1_score': objective1Score,
      'obj1_achievement': achievement(objective1Score, fullMarks[0]),
      'obj2_score': objective2Score,
      'obj2_achievement': achievement(objective2Score, fullMarks[1]),
      'obj3_score': objective3Score,
      'obj3_achievement': achievement(objective3Score, fullMarks[2]),
      'obj4_score': objective4Score,
      'obj4_achievement': achievement(objective4Score, fullMarks[3]),
      'total_score': totalScore,
    });
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
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.parseCalcResults', stack: st);
      return null;
    }
  }

  /// 解析批次应使用的 4 个课程目标权重。
  /// 优先级：course_objectives 表（大纲导入）> 批次 objective_weights_json 快照 > 默认。
  Future<List<double>> resolveObjectiveWeights(int batchId) async {
    const fallback = [0.15, 0.25, 0.30, 0.30];
    try {
      final batch = await getBatch(batchId);
      // 1. course_objectives（大纲权威源）
      final courseName = batch?['course_name'] as String? ?? '移动应用开发';
      final objs = await getCourseObjectives(courseName);
      if (objs.isNotEmpty) {
        final w = List<double>.filled(4, 0);
        for (final o in objs) {
          final idx = (o['idx'] as num?)?.toInt() ?? 0;
          final weight = (o['weight'] as num?)?.toDouble() ?? 0;
          if (idx >= 1 && idx <= 4 && weight > 0) {
            w[idx - 1] = weight;
          }
        }
        if (w.any((x) => x > 0)) return w;
      }
      // 2. 批次快照
      final json = batch?['objective_weights_json'] as String?;
      if (json != null && json.isNotEmpty) {
        final m = jsonDecode(json) as Map<String, dynamic>;
        final w = [
          (m['目标1'] as num?)?.toDouble() ?? fallback[0],
          (m['目标2'] as num?)?.toDouble() ?? fallback[1],
          (m['目标3'] as num?)?.toDouble() ?? fallback[2],
          (m['目标4'] as num?)?.toDouble() ?? fallback[3],
        ];
        if (w.every((x) => x > 0)) return w;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.resolveObjectiveWeights', stack: st);
    }
    return fallback;
  }

  /// 解析批次应使用的 4 个课程目标满分。
  /// 优先级：course_objectives 表（大纲导入）> 默认满分。
  Future<List<double>> resolveObjectiveFullMarks(int batchId) async {
    try {
      final batch = await getBatch(batchId);
      final courseName = batch?['course_name'] as String? ?? '移动应用开发';
      final objs = await getCourseObjectives(courseName);
      if (objs.isNotEmpty) {
        final marks = List<double>.filled(4, 0);
        var hasMark = false;
        for (final o in objs) {
          final idx = (o['idx'] as num?)?.toInt() ?? 0;
          final mark = (o['full_mark'] as num?)?.toDouble() ?? 0;
          if (idx >= 1 && idx <= 4 && mark > 0) {
            marks[idx - 1] = mark;
            hasMark = true;
          }
        }
        if (hasMark) return marks;
      }
    } catch (e, st) {
      swallowDebug(e,
          tag: 'AchievementDao.resolveObjectiveFullMarks', stack: st);
    }
    return _kFullMarks;
  }

  /// 解析每个课程目标的考核环节比例。
  ///
  /// 老逻辑固定为 平时0.2/实验0.3/期末0.5，导致没有实验的课程会把
  /// 实验缺失按 0 分计入。这里以 course_objectives 中的大纲对照表为准：
  /// - 实验比例为 0 时，不参与该目标合成；
  /// - “课程设计/项目/综合/答辩”等终结性评价在解析层归入 exam；
  /// - 比例之和不为 1 时做归一化，避免人工录入 20/30/50 或小数误差。
  Future<List<Map<String, double>>> resolveObjectiveAssessmentWeights(
      int batchId) async {
    final fallback = List<Map<String, double>>.generate(
      4,
      (_) => {'pingshi': 0.20, 'experiment': 0.30, 'exam': 0.50},
    );
    try {
      final batch = await getBatch(batchId);
      final courseName = batch?['course_name'] as String? ?? '移动应用开发';
      final objs = await getCourseObjectives(courseName);
      if (objs.isEmpty) return fallback;

      final result = List<Map<String, double>>.generate(
        4,
        (_) => {'pingshi': 0, 'experiment': 0, 'exam': 0},
      );
      for (final o in objs) {
        final idx = (o['idx'] as num?)?.toInt() ?? 0;
        if (idx < 1 || idx > 4) continue;
        result[idx - 1] = _normalizeAssessmentWeights({
          'pingshi': (o['pingshi_ratio'] as num?)?.toDouble() ?? 0,
          'experiment': (o['experiment_ratio'] as num?)?.toDouble() ?? 0,
          'exam': (o['exam_ratio'] as num?)?.toDouble() ?? 0,
        });
      }
      return result;
    } catch (e, st) {
      swallowDebug(e,
          tag: 'AchievementDao.resolveObjectiveAssessmentWeights', stack: st);
      return fallback;
    }
  }

  Map<String, double> _normalizeAssessmentWeights(Map<String, double> raw) {
    var p = raw['pingshi'] ?? 0;
    var e = raw['experiment'] ?? 0;
    var x = raw['exam'] ?? 0;
    if (p > 1 || e > 1 || x > 1) {
      p = p / 100;
      e = e / 100;
      x = x / 100;
    }
    final sum = p + e + x;
    if (sum <= 0) return {'pingshi': 0, 'experiment': 0, 'exam': 1};
    return {
      'pingshi': p / sum,
      'experiment': e / sum,
      'exam': x / sum,
    };
  }

  /// 从已导入的 achievement_scores 计算班级达成度并保存到批次。
  /// 供「导入成绩后自动计算」与「报告生成」复用，保证两处算法一致。
  /// 返回 {课程目标1..4, weighted}；批次无成绩返回空 Map。
  Future<Map<String, double>> recalculateAndSaveBatch(int batchId) async {
    final avg = await calculateClassAverage(batchId);
    if (avg.isEmpty) return {};
    final weights = await resolveObjectiveWeights(batchId);
    double weighted = 0;
    for (int i = 1; i <= 4; i++) {
      weighted += (avg['课程目标$i'] ?? 0) * weights[i - 1];
    }
    await saveCalculationResults(
      batchId: batchId,
      objective1Achievement: avg['课程目标1'] ?? 0,
      objective2Achievement: avg['课程目标2'] ?? 0,
      objective3Achievement: avg['课程目标3'] ?? 0,
      objective4Achievement: avg['课程目标4'] ?? 0,
      weightedAchievement: weighted,
    );
    await updateBatchStatus(batchId, 'completed');
    return {...avg, 'weighted': weighted};
  }

  /// 导入课程成绩模板的三张明细表（平时/实验/期末）到三张分项表，
  /// 并按大纲对照表中的环节权重合成 achievement_scores 总表，
  /// 最后重算批次达成度。返回导入的学生数。
  ///
  /// [components] 来自 AchievementExcelService.parseComponentSheets：
  /// {pingshi: [...], experiment: [...], exam: [...]}。
  /// 三表按 student_id 求并集；缺某环节的学生该环节按 0 计。
  Future<int> importComponentsToDatabase(
      int batchId, Map<String, List<Map<String, dynamic>>> components) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    final pingshi = components['pingshi'] ?? const [];
    final experiment = components['experiment'] ?? const [];
    final exam = components['exam'] ?? const [];

    // 按学号索引三环节，求并集
    Map<String, Map<String, dynamic>> byId(List<Map<String, dynamic>> rows) => {
          for (final r in rows)
            if ((r['student_id'] as String?)?.isNotEmpty ?? false)
              r['student_id'] as String: r
        };
    final pMap = byId(pingshi), eMap = byId(experiment), xMap = byId(exam);
    final allIds = <String>{...pMap.keys, ...eMap.keys, ...xMap.keys};
    if (allIds.isEmpty) return 0;

    final envWeights = await resolveObjectiveAssessmentWeights(batchId);
    final fm = await resolveObjectiveFullMarks(batchId);
    int count = 0;

    await db.transaction((txn) async {
      // 清空该批次三分项表 + 总表
      for (final t in [
        'achievement_pingshi_scores',
        'achievement_experiment_scores',
        'achievement_exam_scores',
        'achievement_scores',
      ]) {
        await txn.delete(t, where: 'batch_id = ?', whereArgs: [batchId]);
      }

      for (final sid in allIds) {
        final p = pMap[sid], e = eMap[sid], x = xMap[sid];
        final name = (p?['student_name'] ??
            e?['student_name'] ??
            x?['student_name'] ??
            '') as String;

        // 平时分项达成度
        final pAch = p != null ? calculatePingshiAchievement(p) : null;
        if (p != null) {
          await txn.insert(
              'achievement_pingshi_scores',
              {
                'batch_id': batchId,
                'student_id': sid,
                'student_name': name,
                'class_activity_score': p['class_activity_score'] ?? 0,
                'class_activity_achievement': pAch!['obj1_achievement'],
                'quiz_homework_score': p['quiz_homework_score'] ?? 0,
                'quiz_homework_achievement': pAch['obj2_achievement'],
                'extra_learning_score': p['extra_learning_score'] ?? 0,
                'extra_learning_achievement': pAch['obj4_achievement'],
                'total_score': pAch['total_score'],
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 实验分项达成度
        final eAch = e != null ? calculateExperimentAchievement(e) : null;
        if (e != null) {
          await txn.insert(
              'achievement_experiment_scores',
              {
                'batch_id': batchId,
                'student_id': sid,
                'student_name': name,
                'exp1_score': e['exp1_score'] ?? 0,
                'exp2_score': e['exp2_score'] ?? 0,
                'exp3_score': e['exp3_score'] ?? 0,
                'exp4_score': e['exp4_score'] ?? 0,
                'exp5_score': e['exp5_score'] ?? 0,
                'exp6_score': e['exp6_score'] ?? 0,
                'exp7_score': e['exp7_score'] ?? 0,
                'obj1_achievement': eAch!['obj1_achievement'],
                'obj2_achievement': eAch['obj2_achievement'],
                'obj3_achievement': eAch['obj3_achievement'],
                'obj4_achievement': eAch['obj4_achievement'],
                'total_score': eAch['total_score'],
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 期末分项达成度
        final xAch = x != null ? calculateExamAchievement(x) : null;
        if (x != null) {
          await txn.insert(
              'achievement_exam_scores',
              {
                'batch_id': batchId,
                'student_id': sid,
                'student_name': name,
                'project_score': x['project_score'] ?? 0,
                'group_score': x['group_score'] ?? 0,
                'individual_score': x['individual_score'] ?? 0,
                'defense_score': x['defense_score'] ?? 0,
                'obj1_achievement': xAch!['obj1_achievement'],
                'obj2_achievement': xAch['obj2_achievement'],
                'obj3_achievement': xAch['obj3_achievement'],
                'obj4_achievement': xAch['obj4_achievement'],
                'total_score': xAch['total_score'],
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 合成总表：目标i达成度 = Σ(环节i达成度 × 大纲环节比例)。
        // 无实验课程的 experiment_ratio 为 0，不会因为缺实验表被扣分。
        final objAch = List<double>.generate(4, (k) {
          final key = 'obj${k + 1}_achievement';
          final pv = pAch?[key] ?? 0;
          final ev = eAch?[key] ?? 0;
          final xv = xAch?[key] ?? 0;
          final w = envWeights[k];
          return (pv * (w['pingshi'] ?? 0) +
                  ev * (w['experiment'] ?? 0) +
                  xv * (w['exam'] ?? 0))
              .clamp(0.0, 1.0);
        });
        await txn.insert(
            'achievement_scores',
            {
              'batch_id': batchId,
              'student_id': sid,
              'student_name': name,
              'obj1_score': objAch[0] * fm[0],
              'obj1_achievement': objAch[0],
              'obj2_score': objAch[1] * fm[1],
              'obj2_achievement': objAch[1],
              'obj3_score': objAch[2] * fm[2],
              'obj3_achievement': objAch[2],
              'obj4_score': objAch[3] * fm[3],
              'obj4_achievement': objAch[3],
              'total_score': objAch[0] * fm[0] +
                  objAch[1] * fm[1] +
                  objAch[2] * fm[2] +
                  objAch[3] * fm[3],
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
    });

    await recalculateAndSaveBatch(batchId);
    return count;
  }

  /// 从本系统已有数据自动获取各环节成绩，返回与 parseComponentSheets 同结构的
  /// {pingshi, experiment, exam}，供与导入数据对比合并。
  /// - 平时：quiz_results 按学生平均分 → 期间测验项(其余环节项缺省0)
  /// - 实验：lab_submissions 按实验序(lab_tasks.id 升序)映射 exp1..N，归一百分制
  /// - 期末：系统暂无对应数据源，返回空

  /// generateScoresFromQuizResults — 从测验成绩自动计算达成度
  Future<int> generateScoresFromQuizResults(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    // 先清空已有成绩
    await clearScores(batchId);

    // 以全体活跃学生为基准，LEFT JOIN 测验成绩：
    // 没有测验数据的学生也建行（成绩按 0 计），使批次覆盖完整名单而非仅做过测验的人。
    final quizScope = await _courseContext.scopedWhere();
    final rows = await db.rawQuery('''
      SELECT u.user_id, u.real_name,
        q.avg_score, q.total_correct, q.total_questions
      FROM users u
      LEFT JOIN (
        SELECT user_id, AVG(score) AS avg_score,
          SUM(num_correct) AS total_correct, SUM(num_total) AS total_questions
        FROM quiz_results
        WHERE ${quizScope.where}
        GROUP BY user_id
      ) q ON q.user_id = u.user_id
      WHERE u.role = 'student' AND u.is_active = 1
      ORDER BY u.user_id
    ''', quizScope.args);

    if (rows.isEmpty) {
      throw Exception('没有活跃学生，请先在班级管理中添加学生');
    }

    final batchOp = db.batch();
    for (final r in rows) {
      final userId = r['user_id'] as String? ?? '';
      if (userId.isEmpty) continue;
      final userName = (r['real_name'] as String?) ?? userId;
      final avgScore = (r['avg_score'] as num?)?.toDouble() ?? 0;
      final totalQuestions = (r['total_questions'] as num?)?.toDouble() ?? 0;
      final totalCorrect = (r['total_correct'] as num?)?.toDouble() ?? 0;
      final correctRate =
          totalQuestions > 0 ? totalCorrect / totalQuestions : 0.0;

      // 映射到四个课程目标
      final obj1Score = avgScore * 0.15;
      final obj2Score = correctRate * 25;
      final obj3Score = avgScore * 0.30;
      final obj4Score = correctRate * 30;
      final totalScore = obj1Score + obj2Score + obj3Score + obj4Score;

      batchOp.insert(
          'achievement_scores',
          {
            'batch_id': batchId,
            'student_id': userId,
            'student_name': userName,
            'obj1_score': obj1Score,
            'obj1_achievement': (obj1Score / _kFullMarks[0]).clamp(0.0, 1.0),
            'obj2_score': obj2Score,
            'obj2_achievement': (obj2Score / _kFullMarks[1]).clamp(0.0, 1.0),
            'obj3_score': obj3Score,
            'obj3_achievement': (obj3Score / _kFullMarks[2]).clamp(0.0, 1.0),
            'obj4_score': obj4Score,
            'obj4_achievement': (obj4Score / _kFullMarks[3]).clamp(0.0, 1.0),
            'total_score': totalScore,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batchOp.commit(noResult: true);
    return rows.length;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 资源关联
  // ═══════════════════════════════════════════════════════════════════════

  /// 获取章节关联的资源
  Future<List<Map<String, dynamic>>> getResourcesForChapter(
      int chapterNumber) async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere(
      column: 'r.course_id',
      extraWhere: 'm.chapter_number = ?',
      extraArgs: [chapterNumber],
    );
    return db.rawQuery('''
      SELECT r.*, m.match_confidence
      FROM resource_chapter_mapping m
      JOIN resource_files r ON m.resource_id = r.id
      WHERE ${scope.where}
      ORDER BY r.file_type, r.file_name
    ''', scope.args);
  }

  /// 自动建立资源-章节关联（基于关键词匹配）
  Future<int> autoMapResources() async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere();
    final resources = await db.query(
      'resource_files',
      where: scope.where,
      whereArgs: scope.args,
    );

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
            batch.insert(
                'resource_chapter_mapping',
                {
                  'resource_id': res['id'],
                  'resource_type': res['file_type'],
                  'chapter_number': chapter,
                  'chapter_title': '第${chapter}章',
                  'match_confidence': confidence,
                  'created_at': now,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
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
            where: 'survey_id = ?', whereArgs: [surveyId], orderBy: 'seq ASC');

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
              final answers = jsonDecode(answersJson) as Map<String, dynamic>;
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
              final answers = jsonDecode(answersJson) as Map<String, dynamic>;
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
              if (satisfactionKeywords.any((k) => entry.key.contains(k))) {
                satisfiedCount += entry.value;
              }
            }
            if (totalCount > 0 && options.any((o) => o.contains('满意'))) {
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
              final answers = jsonDecode(answersJson) as Map<String, dynamic>;
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

    final batch = await getBatch(batchId);
    final courseName = batch?['course_name']?.toString() ?? '移动应用开发';
    final objectives = await getCourseObjectives(courseName);
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final envWeights = await resolveObjectiveAssessmentWeights(batchId);
    final objectiveByIdx = <int, Map<String, dynamic>>{
      for (final row in objectives)
        if (((row['idx'] as num?)?.toInt() ?? 0) > 0)
          (row['idx'] as num).toInt(): row
    };
    final activeIndexes = [
      for (var i = 0; i < 4; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0))
          i
    ];
    if (activeIndexes.isEmpty) activeIndexes.addAll([0, 1, 2, 3]);

    String objectiveName(int index) {
      final name = objectiveByIdx[index + 1]?['name']?.toString().trim() ?? '';
      return name.isNotEmpty ? name : '课程目标${index + 1}';
    }

    String objectiveChapters(int index) {
      final chapters =
          objectiveByIdx[index + 1]?['chapters']?.toString().trim() ?? '';
      return chapters.isNotEmpty ? chapters : '课程目标${index + 1}相关内容';
    }

    List<String> objectiveTopics(int index) {
      final desc =
          objectiveByIdx[index + 1]?['description']?.toString().trim() ??
              objectiveName(index);
      final parts = desc
          .split(RegExp(r'[、，,；;。]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(4)
          .toList();
      return parts.isEmpty ? [objectiveName(index)] : parts;
    }

    final objAchievements = {
      for (final i in activeIndexes)
        i: scores
                .map((s) =>
                    (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0)
                .fold<double>(0, (a, b) => a + b) /
            scores.length
    };

    final lowCountPerObj = {
      for (final i in activeIndexes)
        i: scores.where((s) {
          final ach = (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
          return ach < 0.6;
        }).length
    };

    // 获取知识图谱节点数
    final db = await DatabaseHelper.instance.database;
    int graphNodeCount = 0;
    try {
      final nodeResult = await db.rawQuery('SELECT COUNT(*) as c FROM nodes');
      graphNodeCount = (nodeResult.first['c'] as int?) ?? 0;
    } catch (e) {
      swallow(e, tag: 'AchievementDao.countNodes');
    }

    // 获取测验题数
    int quizQuestionCount = 0;
    try {
      final quizResult =
          await db.rawQuery('SELECT COUNT(*) as c FROM questions');
      quizQuestionCount = (quizResult.first['c'] as int?) ?? 0;
    } catch (e) {
      swallow(e, tag: 'AchievementDao.countQuestions');
    }

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
    } catch (e) {
      swallow(e, tag: 'AchievementDao.chapterQuizCounts');
    }

    final suggestions = <Map<String, dynamic>>[];

    for (final i in activeIndexes) {
      final ach = objAchievements[i] ?? 0;
      final level = getAchievementLevel(ach);
      final lowCount = lowCountPerObj[i] ?? 0;
      final topics = objectiveTopics(i);
      final chapters = objectiveChapters(i);
      final primaryTopic = topics.first;
      final secondaryTopic = topics.length > 1 ? topics[1] : primaryTopic;
      final lastTopic = topics.last;
      final hasExperimentForObjective = i < envWeights.length &&
          ((envWeights[i]['experiment'] ?? 0) > 0.0001);
      final actions = <String>[];

      if (ach < 0.60) {
        actions.addAll([
          '在知识图谱中增加${topics.join("、")}相关节点，丰富知识结构',
          '增加$chapters相关课时（建议增加2-4学时）',
          '增设$primaryTopic和$lastTopic的章节测验和练习题',
          if (hasExperimentForObjective)
            '增加$chapters的实验项目，强化动手能力'
          else
            '围绕$chapters增加案例分析、课堂练习或阶段性任务',
          '对$lowCount名未达标学生制定一对一帮扶计划',
          '组织$chapters相关的技术专题工作坊',
        ]);
      } else if (ach < 0.70) {
        actions.addAll([
          '补充$primaryTopic和$secondaryTopic相关的知识图谱节点',
          '适当增加$chapters的课时（建议增加1-2学时）',
          '针对$chapters新增综合性测验，提高应用能力',
          '对$lowCount名未达标学生安排额外练习',
          '增加$lastTopic的案例教学内容',
        ]);
      } else if (ach < 0.85) {
        actions.addAll([
          '在知识图谱中补充$primaryTopic的进阶节点',
          '增加$chapters的拓展阅读和实践项目',
          '保持现有$chapters教学节奏，适当提高考核难度',
        ]);
      } else {
        actions.addAll([
          '保持现有教学方案，持续更新$chapters教学内容',
          '鼓励优秀学生参与$primaryTopic的教学辅助工作',
        ]);
      }

      suggestions.add({
        'objectiveIndex': i,
        'objectiveName': objectiveName(i),
        'achievement': ach,
        'level': level,
        'lowStudentCount': lowCount,
        'totalStudents': scores.length,
        'chapters': chapters,
        'topics': topics,
        'actions': actions,
      });
    }

    var weighted = 0.0;
    var weightSum = 0.0;
    for (final i in activeIndexes) {
      final weight = i < weights.length ? weights[i] : 0.0;
      weighted += (objAchievements[i] ?? 0) * weight;
      weightSum += weight;
    }
    if (weightSum > 0 && (weightSum - 1.0).abs() > 0.0001) {
      weighted /= weightSum;
    }
    final hasExperiment = envWeights.any((w) => (w['experiment'] ?? 0) > 0);

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
          weighted, graphNodeCount, quizQuestionCount, hasExperiment),
    });

    return suggestions;
  }

  List<String> _buildOverallSuggestions(
      double weighted, int graphNodes, int quizCount, bool hasExperiment) {
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
        if (hasExperiment)
          '结合大纲复核实验课时与实验成绩占比，强化实验反馈闭环'
        else
          '结合大纲复核过程性评价与终结性评价比例，避免缺失环节被按0分处理',
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

  /// 分项表为空但聚合表 achievement_scores 有数据时，从聚合反推三张分项表。
  ///
  /// 背景：成绩有两条录入路径——课程成绩模板导入(importComponentsToDatabase)
  /// 会同时写分项表+聚合表；而手动录入/编辑/演示/聚合 Excel 导入只写聚合表
  /// (addScore/insertScore)。后者下平时/实验/考核三个 tab 读分项表会显示"暂无数据"，
  /// 尽管达成度已算出。此处用聚合的 objN_achievement 作为各环节该目标达成度回填
  /// （与报告 _defaultEnvs 的回退口径一致），保证三个 tab 不再空白。
  ///
  /// 幂等：分项表已有该批次数据则直接返回，不覆盖真实分项录入。
  Future<void> _ensureComponentScoresFromAggregate(int batchId) async {
    final db = await DatabaseHelper.instance.database;

    Future<bool> hasRows(String table) async {
      final c = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM $table WHERE batch_id = ?', [batchId])) ??
          0;
      return c > 0;
    }

    final pHas = await hasRows('achievement_pingshi_scores');
    final eHas = await hasRows('achievement_experiment_scores');
    final xHas = await hasRows('achievement_exam_scores');
    if (pHas && eHas && xHas) return;

    final envWeights = await resolveObjectiveAssessmentWeights(batchId);
    bool usesEnv(String env) => envWeights.any((w) => (w[env] ?? 0) > 0.0001);
    final usesPingshi = usesEnv('pingshi');
    final usesExperiment = usesEnv('experiment');
    final usesExam = usesEnv('exam');
    if ((!usesPingshi || pHas) &&
        (!usesExperiment || eHas) &&
        (!usesExam || xHas)) {
      return;
    }

    final agg = await db.query('achievement_scores',
        where: 'batch_id = ?', whereArgs: [batchId], orderBy: 'student_id ASC');
    if (agg.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final s in agg) {
        final sid = s['student_id'] as String? ?? '';
        if (sid.isEmpty) continue;
        final name = s['student_name'] ?? '';
        final a1 = (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
        final a2 = (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
        final a3 = (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
        final a4 = (s['obj4_achievement'] as num?)?.toDouble() ?? 0;

        if (!pHas && usesPingshi) {
          // 平时：课堂→目标1, 测验→目标2, 课外→目标4（目标3无平时项）
          await txn.insert(
              'achievement_pingshi_scores',
              {
                'batch_id': batchId,
                'student_id': sid,
                'student_name': name,
                'class_activity_score': a1 * 100,
                'class_activity_achievement': a1,
                'quiz_homework_score': a2 * 100,
                'quiz_homework_achievement': a2,
                'extra_learning_score': a4 * 100,
                'extra_learning_achievement': a4,
                'total_score': (a1 + a2 + a4) / 3 * 100,
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        if (!eHas && usesExperiment) {
          // 实验：1,2→目标1, 3,4→目标2, 5→目标3, 6→目标4
          await txn.insert(
              'achievement_experiment_scores',
              {
                'batch_id': batchId,
                'student_id': sid,
                'student_name': name,
                'exp1_score': a1 * 100,
                'exp2_score': a1 * 100,
                'exp3_score': a2 * 100,
                'exp4_score': a2 * 100,
                'exp5_score': a3 * 100,
                'exp6_score': a4 * 100,
                'exp7_score': 0,
                'obj1_achievement': a1,
                'obj2_achievement': a2,
                'obj3_achievement': a3,
                'obj4_achievement': a4,
                'total_score': (a1 + a2 + a3 + a4) / 4 * 100,
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        if (!xHas && usesExam) {
          // 期末：项目→目标1, 小组→目标2, 个人→目标3, 答辩→目标4
          await txn.insert(
              'achievement_exam_scores',
              {
                'batch_id': batchId,
                'student_id': sid,
                'student_name': name,
                'project_score': a1 * 100,
                'group_score': a2 * 100,
                'individual_score': a3 * 100,
                'defense_score': a4 * 100,
                'obj1_achievement': a1,
                'obj2_achievement': a2,
                'obj3_achievement': a3,
                'obj4_achievement': a4,
                'total_score': a1 * 30 + a2 * 20 + a3 * 20 + a4 * 30,
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  // ── 平时成绩 ─────────────────────────────────────────────────────────
  /// 课堂表现→目标1, 期间测验→目标2, 课外学习→目标4; 目标3无平时成绩

  Future<List<Map<String, dynamic>>> getPingshiScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureComponentScoresFromAggregate(batchId);
    return (await db.query('achievement_pingshi_scores',
            where: 'batch_id = ?',
            whereArgs: [batchId],
            orderBy: 'student_id ASC'))
        .toList();
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

  /// 计算平时成绩的分项达成度（对齐学校表格48）。
  /// 课堂表现(20%) → 目标1, 期间测验(30%) → 目标2,
  /// 课外学习(50%) → 目标4；目标3无平时评价项。
  /// 总评 = 课堂×0.2 + 测验×0.3 + 课外×0.5
  Map<String, double> calculatePingshiAchievement(Map<String, dynamic> score) {
    final classScore = (score['class_activity_score'] as num?)?.toDouble() ?? 0;
    final quizScore = (score['quiz_homework_score'] as num?)?.toDouble() ?? 0;
    final extraScore = (score['extra_learning_score'] as num?)?.toDouble() ?? 0;

    final obj1Ach = (classScore / 100).clamp(0.0, 1.0);
    final obj2Ach = (quizScore / 100).clamp(0.0, 1.0);
    const obj3Ach = 0.0; // 学校模板中课程目标3平时评价为空/0
    final obj4Ach = (extraScore / 100).clamp(0.0, 1.0); // 课外→目标4
    final total = classScore * 0.2 + quizScore * 0.3 + extraScore * 0.5;

    return {
      'obj1_achievement': obj1Ach,
      'obj2_achievement': obj2Ach,
      'obj3_achievement': obj3Ach,
      'obj4_achievement': obj4Ach,
      'total_score': total,
    };
  }

  /// 计算平时成绩的班级平均达成度
  Future<Map<String, double>> calculatePingshiClassAverage(int batchId) async {
    final scores = await getPingshiScores(batchId);
    if (scores.isEmpty) return {'obj1': 0, 'obj2': 0, 'obj3': 0, 'obj4': 0};
    final n = scores.length.toDouble();
    double s1 = 0, s2 = 0, s3 = 0, s4 = 0;
    for (final s in scores) {
      s1 += (s['class_activity_achievement'] as num?)?.toDouble() ?? 0;
      s2 += (s['quiz_homework_achievement'] as num?)?.toDouble() ?? 0;
      s3 += 0;
      s4 += (s['extra_learning_achievement'] as num?)?.toDouble() ?? 0;
    }
    return {'obj1': s1 / n, 'obj2': s2 / n, 'obj3': s3 / n, 'obj4': s4 / n};
  }

  /// 生成平时演示数据

  // ── 实验成绩 ─────────────────────────────────────────────────────────
  /// 实验1-2→目标1, 实验3-4→目标2，兼容两类模板：
  /// - 学校表格48：实验5-6→目标3, 实验7→目标4；
  /// - 简洁/6实验模板：实验5→目标3, 实验6→目标4。

  Future<List<Map<String, dynamic>>> getExperimentScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureComponentScoresFromAggregate(batchId);
    return (await db.query('achievement_experiment_scores',
            where: 'batch_id = ?',
            whereArgs: [batchId],
            orderBy: 'student_id ASC'))
        .toList();
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

  /// 计算实验成绩的分项达成度。存在实验7分数时按学校表格48的 7 实验结构；
  /// 否则按 6 实验结构，保证内置大纲生成的简洁模板仍可用。
  Map<String, double> calculateExperimentAchievement(
      Map<String, dynamic> score) {
    final e1 = (score['exp1_score'] as num?)?.toDouble() ?? 0;
    final e2 = (score['exp2_score'] as num?)?.toDouble() ?? 0;
    final e3 = (score['exp3_score'] as num?)?.toDouble() ?? 0;
    final e4 = (score['exp4_score'] as num?)?.toDouble() ?? 0;
    final e5 = (score['exp5_score'] as num?)?.toDouble() ?? 0;
    final e6 = (score['exp6_score'] as num?)?.toDouble() ?? 0;
    final e7 = (score['exp7_score'] as num?)?.toDouble() ?? 0;

    final obj1Ach = ((e1 + e2) / 2 / 100).clamp(0.0, 1.0);
    final obj2Ach = ((e3 + e4) / 2 / 100).clamp(0.0, 1.0);
    final hasExp7 = e7 > 0;
    final obj3Ach = (hasExp7 ? (e5 + e6) / 2 / 100 : e5 / 100).clamp(0.0, 1.0);
    final obj4Ach = (hasExp7 ? e7 / 100 : e6 / 100).clamp(0.0, 1.0);
    final total = hasExp7
        ? (e1 + e2 + e3 + e4 + e5 + e6 + e7) / 7
        : (e1 + e2 + e3 + e4 + e5 + e6) / 6;

    return {
      'obj1_achievement': obj1Ach,
      'obj2_achievement': obj2Ach,
      'obj3_achievement': obj3Ach,
      'obj4_achievement': obj4Ach,
      'total_score': total,
    };
  }

  /// 计算实验成绩的班级平均达成度
  Future<Map<String, double>> calculateExperimentClassAverage(
      int batchId) async {
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

  // ── 期末考核成绩 ──────────────────────────────────────────────────────
  /// 项目30%→目标1, 小组20%→目标2, 个人20%→目标3, 答辩30%→目标4

  Future<List<Map<String, dynamic>>> getExamScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureComponentScoresFromAggregate(batchId);
    return (await db.query('achievement_exam_scores',
            where: 'batch_id = ?',
            whereArgs: [batchId],
            orderBy: 'student_id ASC'))
        .toList();
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
    final total =
        project * 0.3 + group * 0.2 + individual * 0.2 + defense * 0.3;

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

  // ── 综合达成度计算（三类评价加权汇总）──────────────────────────────
  /// 综合达成度 = Σ(环节达成度 × 大纲环节比例)
  Future<Map<String, dynamic>> calculateCombinedAchievement(int batchId) async {
    final aggregateAvg = await calculateClassAverage(batchId);
    final envWeights = await resolveObjectiveAssessmentWeights(batchId);

    Future<Map<String, double>> envAverage(
      String env,
      Future<Map<String, double>> Function() loadLegacyAverage,
    ) async {
      final usesEnv = envWeights.any((w) => (w[env] ?? 0) > 0.0001);
      if (!usesEnv) return {};
      final synthetic = await _componentRowsAreAggregateBackfill(batchId, env);
      if (!synthetic) return loadLegacyAverage();
      return _aggregateAverageForEnv(aggregateAvg, envWeights, env);
    }

    final pingshi = await envAverage(
        'pingshi', () => calculatePingshiClassAverage(batchId));
    final experiment = await envAverage(
        'experiment', () => calculateExperimentClassAverage(batchId));
    final exam =
        await envAverage('exam', () => calculateExamClassAverage(batchId));
    final combined = <String, double>{
      for (int i = 1; i <= 4; i++) 'obj$i': aggregateAvg['课程目标$i'] ?? 0,
    };

    return {
      'pingshi': pingshi,
      'experiment': experiment,
      'exam': exam,
      'combined': combined,
      'weightsByObjective': envWeights,
      'weights': {
        '平时': envWeights.isEmpty ? 0 : envWeights.first['pingshi'] ?? 0,
        '实验': envWeights.isEmpty ? 0 : envWeights.first['experiment'] ?? 0,
        '期末': envWeights.isEmpty ? 0 : envWeights.first['exam'] ?? 0,
      },
    };
  }

  Map<String, double> _aggregateAverageForEnv(
    Map<String, double> aggregateAvg,
    List<Map<String, double>> envWeights,
    String env,
  ) {
    return {
      for (int i = 1; i <= 4; i++)
        if (i - 1 < envWeights.length &&
            ((envWeights[i - 1][env] ?? 0) > 0.0001))
          'obj$i': aggregateAvg['课程目标$i'] ?? 0,
    };
  }

  Future<bool> _componentRowsAreAggregateBackfill(
      int batchId, String env) async {
    final db = await DatabaseHelper.instance.database;
    final tableName = env == 'pingshi'
        ? 'achievement_pingshi_scores'
        : env == 'experiment'
            ? 'achievement_experiment_scores'
            : 'achievement_exam_scores';
    final componentRows = await db.query(tableName,
        where: 'batch_id = ?', whereArgs: [batchId], orderBy: 'student_id ASC');
    if (componentRows.isEmpty) return true;

    final aggregateRows = await db.query('achievement_scores',
        where: 'batch_id = ?', whereArgs: [batchId], orderBy: 'student_id ASC');
    if (componentRows.length != aggregateRows.length) return false;

    final aggregateById = {
      for (final row in aggregateRows) row['student_id']?.toString() ?? '': row
    };
    bool close(Object? a, Object? b) {
      final av = (a as num?)?.toDouble() ?? 0;
      final bv = (b as num?)?.toDouble() ?? 0;
      return (av - bv).abs() < 0.0001;
    }

    for (final row in componentRows) {
      final sid = row['student_id']?.toString() ?? '';
      final aggregate = aggregateById[sid];
      if (aggregate == null) return false;
      switch (env) {
        case 'pingshi':
          if (!close(row['class_activity_achievement'],
                  aggregate['obj1_achievement']) ||
              !close(row['quiz_homework_achievement'],
                  aggregate['obj2_achievement']) ||
              !close(row['extra_learning_achievement'],
                  aggregate['obj4_achievement'])) {
            return false;
          }
          break;
        case 'experiment':
          for (var i = 1; i <= 4; i++) {
            if (!close(
                row['obj${i}_achievement'], aggregate['obj${i}_achievement'])) {
              return false;
            }
          }
          break;
        default:
          for (var i = 1; i <= 4; i++) {
            if (!close(
                row['obj${i}_achievement'], aggregate['obj${i}_achievement'])) {
              return false;
            }
          }
      }
    }
    return true;
  }
}
