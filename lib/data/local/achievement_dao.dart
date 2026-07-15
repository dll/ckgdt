import 'dart:convert';
import 'dart:math' show max, sqrt;
import 'package:sqflite/sqflite.dart';
import 'active_student_scope.dart';
import 'database_helper.dart';
import 'ordinary_score_dao.dart';
import '../../core/error_handler.dart';
import '../../core/init_logger.dart';
import '../../services/auth_service.dart';
import '../../services/course_context_service.dart';
import '../../services/achievement_context.dart';

/// 课程达成度 DAO — 达成度批次管理、成绩录入、计算、报告生成
class AchievementDao {
  final CourseContextService _courseContext = CourseContextService();

  /// 默认课程目标满分数值（与大纲第六节、AchievementConfig.defaults 一致）。
  /// DAO 属数据层，不能依赖 presentation 层的 AchievementConfig，故在此独立维护。
  /// 优先使用 course_objectives 表中的满分值，此处仅作兜底。
  static const List<double> _kFullMarks = [15.0, 25.0, 30.0, 30.0, 0.0];

  static int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static double _asDouble(Object? value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final text = value.trim().replaceAll('%', '');
      return double.tryParse(text) ?? fallback;
    }
    return fallback;
  }

  static String _nonEmpty(Object? value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _asRatio(Object? value, [double fallback = 0]) {
    final ratio = _asDouble(value, fallback);
    return ratio > 1 ? ratio / 100 : ratio;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 课程目标定义（course_objectives，权威源来自大纲导入）
  // ═══════════════════════════════════════════════════════════════════════

  /// 读取某课程的目标定义行（按 idx 升序）。无则返回空列表。
  Future<List<Map<String, dynamic>>> getCourseObjectives(
      String courseName) async {
    final db = await DatabaseHelper.instance.database;
    return db.query('course_objectives',
        where: 'course_name = ?', whereArgs: [courseName], orderBy: 'idx ASC');
  }

  /// 覆盖写入某课程的目标定义（先删后插，保证与大纲一致）。
  /// [objectives] 每项含 idx/name/indicator/weight/full_mark/
  /// pingshi_ratio/experiment_ratio/exam_ratio/chapters/description/assess_content。
  Future<void> saveCourseObjectives(
    String courseName,
    List<Map<String, dynamic>> objectives, {
    String? syllabusVersion,
    Map<String, String>? syllabusInfo,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    final normalizedCourseName =
        courseName.trim().isNotEmpty ? courseName.trim() : '当前课程';
    final effectiveVersion = (syllabusVersion?.trim().isNotEmpty == true
            ? syllabusVersion!.trim()
            : objectives
                .map((o) => o['syllabus_version']?.toString().trim() ?? '')
                .firstWhere((v) => v.isNotEmpty, orElse: () => '未标注版本'))
        .trim();
    // 保存大纲元信息（适用专业、开课学期等）
    if (syllabusInfo != null && syllabusInfo.isNotEmpty) {
      try {
        await db.update(
          'courses',
          {'syllabus_info_json': jsonEncode(syllabusInfo)},
          where: 'name = ?',
          whereArgs: [normalizedCourseName],
        );
      } catch (e, st) {
        swallowDebug(e, tag: 'AchievementDao.saveSyllabusInfo', stack: st);
      }
    }
    await db.transaction((txn) async {
      await txn.delete('course_objectives',
          where: 'course_name = ?', whereArgs: [normalizedCourseName]);
      for (var i = 0; i < objectives.length; i++) {
        final o = objectives[i];
        final idx = _asInt(o['idx'], i + 1);
        await txn.insert('course_objectives', {
          'course_name': normalizedCourseName,
          'idx': idx,
          'name': o['name']?.toString().trim().isNotEmpty == true
              ? o['name']
              : '课程目标$idx',
          'indicator': o['indicator'],
          'weight': _asDouble(o['weight']),
          'full_mark': _asDouble(o['full_mark']),
          'pingshi_ratio': _asRatio(o['pingshi_ratio']),
          'experiment_ratio': _asRatio(o['experiment_ratio']),
          'exam_ratio': _asRatio(o['exam_ratio']),
          'chapters': o['chapters'],
          'description': o['description'],
          'assess_content': o['assess_content'],
          'experiments': o['experiments'],
          'pingshi_standard': o['pingshi_standard'],
          'experiment_standard': o['experiment_standard'],
          'assessment_items_json': o['assessment_items_json'],
          'extra_columns_json': o['extra_columns_json'],
          'syllabus_version': effectiveVersion,
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  }

  /// 删除指定课程的单个目标（按 idx）。
  Future<int> deleteCourseObjective(String courseName, int idx) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('course_objectives',
        where: 'course_name = ? AND idx = ?', whereArgs: [courseName, idx]);
  }

  /// 删除指定课程的全部目标。
  Future<int> deleteAllCourseObjectives(String courseName) async {
    final db = await DatabaseHelper.instance.database;
    return db.delete('course_objectives',
        where: 'course_name = ?', whereArgs: [courseName]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 批次 CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// 获取批次列表，默认按当前激活课程过滤。
  /// [courseName] 为 null 时使用课程管理中的活动课程。
  /// 管理页需跨课程查询时传 courseName='' 或使用 [getAllBatchesUnscoped]。
  Future<List<Map<String, dynamic>>> getAllBatches({
    String? courseName,
  }) async {
    final effective = courseName ??
        await _courseContext.activeCourseName(
          fallback: '当前课程',
        );
   if (effective.isNotEmpty) {
     AchievementContext.instance.courseName = effective;
   }
   final db = await DatabaseHelper.instance.database;
    final courseWhere = effective.isNotEmpty ? 'WHERE ab.course_name = ?' : '';
    final args = effective.isNotEmpty ? <Object?>[effective] : <Object?>[];
    try {
      return db.rawQuery('''
        SELECT ab.*,
          (
            SELECT COUNT(*)
            FROM achievement_scores s
            WHERE s.batch_id = ab.id
          ) AS student_count
        FROM achievement_batches ab
        $courseWhere
        ORDER BY ab.created_at DESC
      ''', args);
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.getAllBatches.count', stack: st);
      return db.rawQuery('''
        SELECT ab.*,
          (SELECT COUNT(*) FROM achievement_scores WHERE batch_id = ab.id) AS student_count
        FROM achievement_batches ab
        $courseWhere
        ORDER BY ab.created_at DESC
      ''', args);
    }
  }

  /// 获取所有课程的全部批次（管理用，无课程过滤）
  Future<List<Map<String, dynamic>>> getAllBatchesUnscoped() =>
      getAllBatches(courseName: '');

  /// 按课程获取批次（显式指定课程名）
  Future<List<Map<String, dynamic>>> getBatchesByCourse(String courseName) =>
      getAllBatches(courseName: courseName);

  /// 兼容旧调用：默认用当前课程
  Future<List<Map<String, dynamic>>> getBatches() => getAllBatches();

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
    // 批次自身即权威作用域；导入/聚合时已按当前教学班级筛选，
    // 查看历史批次时不应再因班级归档而隐藏已有成绩。
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
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final dynamicAvg = await _dynamicAggregateClassAverage(batchId);
    if (scores.isEmpty && dynamicAvg.isEmpty) return {};
    final objectiveCount = _objectiveCount(
      weights: weights,
      fullMarks: fullMarks,
      dynamicObjectives: dynamicAvg.keys,
    );
    final activeIndexes = [
      for (var i = 0; i < objectiveCount; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0) ||
            dynamicAvg.containsKey(i + 1))
          i
    ];
    if (activeIndexes.isEmpty) {
      activeIndexes.addAll(List<int>.generate(objectiveCount, (i) => i));
    }

    final sums = List<double>.filled(objectiveCount, 0);
    double sumTotal = 0;
    for (final s in scores) {
      final jsonStr = s['achievements_json'] as String?;
      Map<String, dynamic>? parsed;
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (e) { swallow(e, tag: 'AchievementDao.calcClassAvg.json'); }
      }
      for (final i in activeIndexes) {
        final fromJson = parsed?['obj${i + 1}_achievement'];
        final fromCol = (s['obj${i + 1}_achievement'] as num?)?.toDouble();
        sums[i] += (fromJson ?? fromCol ?? 0);
      }
      sumTotal += (s['total_score'] as num?)?.toDouble() ?? 0;
    }

    final n = scores.isEmpty ? 1.0 : scores.length.toDouble();
    return {
      for (final i in activeIndexes)
        '课程目标${i + 1}': dynamicAvg[i + 1] ?? sums[i] / n,
      if (scores.isNotEmpty) '总评': sumTotal / n / 100,
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
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final dynamicValues = await _dynamicAggregateStudentAchievements(batchId);
    if (scores.isEmpty && dynamicValues.isEmpty) return {};
    final objectiveCount = _objectiveCount(
      weights: weights,
      fullMarks: fullMarks,
      dynamicObjectives: dynamicValues.keys,
    );
    final activeIndexes = [
      for (var i = 0; i < objectiveCount; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0) ||
            dynamicValues.containsKey(i + 1))
          i
    ];
    if (activeIndexes.isEmpty) {
      activeIndexes.addAll(List<int>.generate(objectiveCount, (i) => i));
    }

    return {
      for (final i in activeIndexes)
        '课程目标${i + 1}': _calcStats(
          dynamicValues[i + 1] ??
              scores
                  .map((s) =>
                      (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0)
                  .toList(),
        ),
    };
  }

  int _objectiveCount({
    required List<double> weights,
    required List<double> fullMarks,
    Iterable<int> dynamicObjectives = const [],
  }) {
    var count = 0;
    for (var i = 0; i < weights.length; i++) {
      if (weights[i] > 0) count = max(count, i + 1);
    }
    for (var i = 0; i < fullMarks.length; i++) {
      if (fullMarks[i] > 0) count = max(count, i + 1);
    }
    for (final idx in dynamicObjectives) {
      if (idx > 0) count = max(count, idx);
    }
    return count.clamp(1, 10).toInt();
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

    final courseName = batch['course_name'] ?? '当前课程';
    final className = _nonEmpty(batch['class_name'], fallback: '未绑定班级');
    final scores = await getScores(batchId);
    final avgAchievements = await calculateClassAverage(batchId);
    final stats = await getStudentStats(batchId);
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final objectiveRows = await getCourseObjectives(courseName.toString());
    final objectiveByIdx = <int, Map<String, dynamic>>{
      for (final row in objectiveRows)
        if (_asInt(row['idx']) > 0) _asInt(row['idx']): row
    };
    final objectiveCount = _objectiveCount(
      weights: weights,
      fullMarks: fullMarks,
    );
    final activeIndexes = [
      for (var i = 0; i < objectiveCount; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0))
          i
    ];
    if (activeIndexes.isEmpty) {
      activeIndexes.addAll(List<int>.generate(objectiveCount, (i) => i));
    }

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
        '1. **整体表现**：学生在$courseName课程的学习中取得了一定的成果，加权总达成度为${weighted.toStringAsFixed(2)}。');
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

 /// getScoresByBatch — 别名，等价于 getScores(batchId)
 Future<List<Map<String, dynamic>>> getScoresByBatch(int batchId) =>
     getScores(batchId);

  /// 标准达成度批次命名：课程--学期--班级--教师（双横线分隔，内部横线保留）
  static String buildBatchName({
    required String courseName,
    required String className,
    required String semester,
    required String teacherName,
  }) {
    final parts = [courseName.trim(), semester.trim(), className.trim(), teacherName.trim()];
    return parts.where((p) => p.isNotEmpty).join('--');
  }

  /// 从未归档班级列表中选择最合适的班级用于新建达成批次。
  /// 允许外部传入优先匹配关键词（如适用专业缩写）。
  static String selectClassForBatch(List<Map<String, dynamic>> classes,
      {String? preferKeyword}) {
    if (classes.isEmpty) return '';
    final nonDemo = classes.where((c) {
      final name = (c['name'] ?? '').toString();
      return !name.contains('演示') &&
          !name.contains('测试') &&
          !name.contains('示例');
    }).toList();
    final source = nonDemo.isNotEmpty ? nonDemo : classes;
    if (preferKeyword != null && preferKeyword.isNotEmpty) {
      final matched = source.where((c) {
        final name = (c['name'] ?? '').toString();
        return name.contains(preferKeyword);
      }).toList();
      if (matched.isNotEmpty) {
        return matched.map((c) => c['name'].toString()).join('+');
      }
    }
    return source.first['name']?.toString() ?? '';
  }

  /// 把原始学期字符串规范化为「YYYY-YYYY年第N学期」。
  static String normalizeAcademicSemester(String? raw, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final text = (raw ?? '').trim();
    final yearMatch = RegExp(r'(\d{4})\s*[-—~至]\s*(\d{4})').firstMatch(text);
    int startYear;
    int endYear;
    if (yearMatch != null) {
      startYear = int.parse(yearMatch.group(1)!);
      endYear = int.parse(yearMatch.group(2)!);
    } else if (current.month >= 9) {
      startYear = current.year;
      endYear = current.year + 1;
    } else {
      startYear = current.year - 1;
      endYear = current.year;
    }

    final term = text.contains('第一') || text.contains('第1')
        ? 1
        : text.contains('第二') || text.contains('第2')
            ? 2
            : current.month >= 9
                ? 1
                : 2;
    return '$startYear-$endYear年第$term学期';
  }

  /// 从班级列表中查找指定班级的学期并规范化。
  static String semesterForClass(
    List<Map<String, dynamic>> classes,
    String className,
    DateTime now,
  ) {
    final row = classes.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['name']?.toString() == className,
          orElse: () => null,
        );
    return normalizeAcademicSemester(row?['semester']?.toString(), now: now);
  }

 /// addBatch — 命名参数便捷方法
 Future<int> addBatch({
    required String batchName,
    String courseName = '',
    String className = '',
    String semester = '',
    String teacherId = '',
    String? syllabusVersion,
    String? objectiveWeightsJson,
    String? assessmentWeightsJson,
  }) async {
    final effectiveCourseName = courseName.isNotEmpty
        ? courseName
        : await _courseContext.activeCourseName();
    final effectiveClassName = className.trim().isNotEmpty
        ? className.trim()
        : await _defaultActiveClassName();
    final effectiveVersion = syllabusVersion?.trim().isNotEmpty == true
        ? syllabusVersion!.trim()
        : await currentSyllabusVersion(effectiveCourseName);
    return createBatch({
      'batch_name': batchName,
      'course_name': effectiveCourseName,
      'class_name': effectiveClassName,
      'semester': semester,
      'teacher_id': teacherId,
      'syllabus_version': effectiveVersion,
      'status': 'draft',
      if (objectiveWeightsJson != null && objectiveWeightsJson.isNotEmpty)
        'objective_weights_json': objectiveWeightsJson,
      if (assessmentWeightsJson != null && assessmentWeightsJson.isNotEmpty)
        'assessment_weights_json': assessmentWeightsJson,
    });
  }

  /// 自动为该激活课程生成达成度批次（无需用户点击）。
  ///
  /// 平台化要求：批次必须随当前激活课程自动创建，绝不应要求用户手工新建，
  /// 也不应因大纲已导入而仍提示"请先导入大纲"。
  /// 当课程、班级、学期、教师信息均已确定时，若当前激活课程尚无批次，
  /// 则依据激活课程名/活跃班级/当前学期/当前登录教师自动创建一个草稿批次，
  /// 返回其 id（已存在则直接返回首个批次 id）。
  Future<int> ensureBatchForActiveCourse() async {
    try {
      var courseName = (await _courseContext.activeCourseName()).trim();
      if (courseName.isEmpty) {
        courseName = AchievementContext.instance.courseName.trim();
      }
      if (courseName.isEmpty) courseName = '当前课程';

      final existing = await getBatches();
      if (existing.isNotEmpty) return existing.first['id'] as int;

      final semester = await _currentSemester();
      final teacherId = AuthService().currentUser?.userId ?? '';
      final teacherName = AuthService().currentUser?.realName?.trim() ?? '';
      // 查询当前课程关联的班级
      var className = '';
      try {
        final activeCourse = await _courseContext.getActiveCourse();
        final dao = await DatabaseHelper.instance.database;
        final rows = await dao.query('classes',
            columns: ['name'],
            where: 'COALESCE(is_archived, 0) = 0 AND (course_id IS NULL OR course_id = ?)',
            whereArgs: [activeCourse.id]);
        className = selectClassForBatch(rows);
      } catch (e, st) {
        swallowDebug(e, tag: 'AchievementDao.ensureBatchForActiveCourse.classes', stack: st);
      }
      final batchName = buildBatchName(
        courseName: courseName,
        className: className,
        semester: semester,
        teacherName: teacherName.isNotEmpty ? teacherName : '教师',
      );
      final id = await addBatch(
        batchName: batchName,
        courseName: courseName,
        className: className,
        semester: semester,
        teacherId: teacherId,
      );
      if (id <= 0) {
        InitLogger.error('achievement',
            'ensureBatchForActiveCourse: 批次创建失败 courseName=$courseName id=$id');
      }
      return id;
    } catch (e, st) {
      InitLogger.error('achievement', e, st);
      return -1;
    }
  }

  Future<String> _currentSemester() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final batch = await db.query('achievement_batches',
          columns: ['semester'],
          where: 'semester IS NOT NULL AND semester <> ?',
          whereArgs: [''],
          orderBy: 'id DESC',
          limit: 1);
      final last = batch.isNotEmpty ? batch.first['semester']?.toString() : null;
      if (last != null && last.isNotEmpty) return last;
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.currentSemester', stack: st);
    }
    return normalizeAcademicSemester(null);
  }

  /// 对外公开的默认班级名，供 ReportTab 等页面调用。
  Future<String> defaultActiveClassName() => _defaultActiveClassName();

  Future<String> _defaultActiveClassName() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'classes',
        columns: ['name'],
        where: 'COALESCE(is_archived, 0) = 0',
        orderBy: 'id ASC',
        limit: 1,
      );
      final name = rows.isEmpty ? '' : rows.first['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.defaultActiveClassName', stack: st);
    }
    return '未绑定班级';
  }

  Future<String> currentSyllabusVersion(String courseName) async {
    final db = await DatabaseHelper.instance.database;
    try {
      final rows = await db.query(
        'course_objectives',
        columns: ['syllabus_version'],
        where:
            'course_name = ? AND syllabus_version IS NOT NULL AND syllabus_version <> ?',
        whereArgs: [courseName, ''],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final version = rows.first['syllabus_version']?.toString().trim();
        if (version != null && version.isNotEmpty) return version;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.currentSyllabusVersion', stack: st);
    }
    return '未标注版本';
  }

  /// addScore — 便捷方法（计算达成度后插入）
  /// [objectiveScores] 索引 0 对应目标1，可扩展至 N 个目标。
  Future<int> addScore({
    required int batchId,
    required String studentId,
    required String studentName,
    required List<double> objectiveScores,
    required double totalScore,
  }) async {
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    double achievement(double score, double fullMark) =>
        fullMark > 0 ? (score / fullMark).clamp(0.0, 1.0) : 0.0;
    final data = <String, dynamic>{
      'batch_id': batchId,
      'student_id': studentId,
      'student_name': studentName,
    };
    for (int i = 0; i < objectiveScores.length && i < fullMarks.length; i++) {
      data['obj${i + 1}_score'] = objectiveScores[i];
      data['obj${i + 1}_achievement'] =
          achievement(objectiveScores[i], fullMarks[i]);
    }
    data['total_score'] = totalScore;
    return insertScore(data);
  }

  /// updateBatchStatus — 更新批次状态
  Future<int> updateBatchStatus(int batchId, String status) {
    return updateBatch(batchId, {'status': status});
  }

  /// saveCalculationResults — 将计算后的达成度保存到批次
  /// 支持任意数量的课程目标（通过 Map 传入）
  Future<void> saveCalculationResults({
    required int batchId,
    required double weightedAchievement,
    Map<int, double>? objectiveAchievements,
  }) async {
    final results = <String, dynamic>{
      'weighted_achievement': weightedAchievement,
    };
    if (objectiveAchievements != null) {
      for (final entry in objectiveAchievements.entries) {
        results['objective${entry.key}_achievement'] = entry.value;
      }
    }
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

  /// 解析批次应使用的课程目标权重。
  /// 优先级：course_objectives 表（大纲导入）> 批次 objective_weights_json 快照 > 默认。
  Future<List<double>> resolveObjectiveWeights(int batchId) async {
    const fallback = [0.15, 0.20, 0.25, 0.20, 0.20];
    try {
      final batch = await getBatch(batchId);
      // 1. course_objectives（大纲权威源）
      final courseName = batch?['course_name'] as String? ?? '当前课程';
      final objs = await getCourseObjectives(courseName);
      if (objs.isNotEmpty) {
        final w = List<double>.filled(10, 0);
        for (final o in objs) {
          final idx = _asInt(o['idx']);
          final weight = _asDouble(o['weight']);
          if (idx >= 1 && idx <= 10 && weight > 0) {
            w[idx - 1] = weight;
          }
        }
        // 只返回实际有值的部分
        final maxIdx = objs.fold<int>(0, (m, o) {
          final idx = _asInt(o['idx']);
          return idx > m ? idx : m;
        });
        if (maxIdx > 0 && w.any((x) => x > 0)) return w.sublist(0, maxIdx);
      }
      // 2. 批次快照
      final json = batch?['objective_weights_json'] as String?;
      if (json != null && json.isNotEmpty) {
        final m = jsonDecode(json) as Map<String, dynamic>;
        final w = <double>[];
        for (int i = 1; i <= 10; i++) {
          final key = '目标$i';
          if (m.containsKey(key)) {
            w.add(_asDouble(m[key], i <= fallback.length ? fallback[i - 1] : 0));
          } else {
            break;
          }
        }
        if (w.isNotEmpty && w.every((x) => x > 0)) return w;
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
      final courseName = batch?['course_name'] as String? ?? '当前课程';
      final objs = await getCourseObjectives(courseName);
      if (objs.isNotEmpty) {
        final marks = List<double>.filled(10, 0);
        var hasMark = false;
        for (final o in objs) {
          final idx = _asInt(o['idx']);
          final mark = _asDouble(o['full_mark']);
          if (idx >= 1 && idx <= 10 && mark > 0) {
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
      5,
      (_) => {'pingshi': 0.20, 'experiment': 0.30, 'exam': 0.50},
    );
    try {
      final batch = await getBatch(batchId);
      final courseName = batch?['course_name'] as String? ?? '当前课程';
      final objs = await getCourseObjectives(courseName);
      if (objs.isEmpty) return fallback;

      final maxIdx = objs.fold<int>(0, (m, o) {
        final idx = _asInt(o['idx']);
        return idx > m ? idx : m;
      });
      final count = maxIdx > 0 ? maxIdx : 5;
      final result = List<Map<String, double>>.generate(
        count,
        (_) => {'pingshi': 0, 'experiment': 0, 'exam': 0},
      );
      for (final o in objs) {
        final idx = _asInt(o['idx']);
        if (idx < 1 || idx > count) continue;
        result[idx - 1] = _normalizeAssessmentWeights({
          'pingshi': _asRatio(o['pingshi_ratio']),
          'experiment': _asRatio(o['experiment_ratio']),
          'exam': _asRatio(o['exam_ratio']),
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
  Future<Map<String, double>> recalculateAndSaveBatch(int batchId) async {
    final avg = await calculateClassAverage(batchId);
    if (avg.isEmpty) return {};
    final weights = await resolveObjectiveWeights(batchId);
    double weighted = 0;
    final objAch = <int, double>{};
    for (int i = 1; i <= weights.length; i++) {
      final v = avg['课程目标$i'] ?? 0;
      weighted += v * weights[i - 1];
      objAch[i] = v;
    }
    await saveCalculationResults(
      batchId: batchId,
      weightedAchievement: weighted,
      objectiveAchievements: objAch,
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
    final objCount = envWeights.length;
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
        final pAch =
            p != null ? calculatePingshiAchievement(p, objectiveCount: objCount) : null;
        if (p != null) {
          final pRow = <String, dynamic>{
            'batch_id': batchId,
            'student_id': sid,
            'student_name': name,
            'class_activity_score': p['class_activity_score'] ?? 0,
            'class_activity_achievement': pAch!['obj1_achievement'],
            'quiz_homework_score': p['quiz_homework_score'] ?? 0,
            'quiz_homework_achievement': pAch['obj2_achievement'],
            'extra_learning_score': p['extra_learning_score'] ?? 0,
            'extra_learning_achievement':
                objCount >= 3 ? (pAch['obj3_achievement'] ?? 0) : null,
            'total_score': pAch['total_score'],
            'created_at': now,
            'updated_at': now,
          };
          pRow['achievements_json'] =
              jsonEncode({for (int k = 1; k <= objCount; k++) 'obj${k}_achievement': pAch['obj${k}_achievement']});
          await txn.insert('achievement_pingshi_scores', pRow,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 实验分项达成度
        final eAch =
            e != null ? calculateExperimentAchievement(e, objectiveCount: objCount) : null;
        if (e != null) {
          final eRow = <String, dynamic>{
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
          };
          eRow['achievements_json'] =
              jsonEncode({for (int k = 1; k <= objCount; k++) 'obj${k}_achievement': eAch['obj${k}_achievement']});
          await txn.insert('achievement_experiment_scores', eRow,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 期末分项达成度
        final xAch =
            x != null ? calculateExamAchievement(x, objectiveCount: objCount) : null;
        if (x != null) {
          final xRow = <String, dynamic>{
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
          };
          xRow['achievements_json'] =
              jsonEncode({for (int k = 1; k <= objCount; k++) 'obj${k}_achievement': xAch['obj${k}_achievement']});
          await txn.insert('achievement_exam_scores', xRow,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 合成总表：目标i达成度 = Σ(环节i达成度 × 大纲环节比例)。
        // 无实验课程的 experiment_ratio 为 0，不会因为缺实验表被扣分。
        final objAch = List<double>.generate(objCount, (k) {
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
        final scoreMap = <String, dynamic>{
          'batch_id': batchId,
          'student_id': sid,
          'student_name': name,
          'created_at': now,
          'updated_at': now,
        };
        double total = 0;
        for (int k = 0; k < objCount && k < fm.length; k++) {
          scoreMap['obj${k + 1}_score'] = objAch[k] * fm[k];
          scoreMap['obj${k + 1}_achievement'] = objAch[k];
          total += objAch[k] * fm[k];
        }
        scoreMap['total_score'] = total;
        scoreMap['achievements_json'] =
            jsonEncode({for (int k = 1; k <= objCount; k++) 'obj${k}_achievement': objAch[k - 1]});
        await txn.insert(
            'achievement_scores', scoreMap,
            conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
    });

    await recalculateAndSaveBatch(batchId);
    return count;
  }

  /// 将平台自动汇总的平时成绩同步到指定达成度批次。
  ///
  /// 仅替换该批次的平时分项；实验、期末分项会先读取保留，然后复用
  /// [importComponentsToDatabase] 重新合成 achievement_scores，避免覆盖教师
  /// 已导入或已录入的实验/考核成绩。
  Future<int> importPlatformPingshiScores(
    int batchId,
    List<Map<String, dynamic>> pingshiRows,
  ) async {
    if (pingshiRows.isEmpty) return 0;

    final experiment = await getExperimentScores(batchId);
    final exam = await getExamScores(batchId);
    return importComponentsToDatabase(batchId, {
      'pingshi': pingshiRows,
      'experiment': experiment,
      'exam': exam,
    });
  }

  /// 从平台现有数据聚合平时、实验、考核三类明细，并写入与 Excel 导入
  /// 完全相同的三张分项表和 achievement_scores 总表。
  Future<int> importPlatformAchievementScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    final batchRows = await db.query('achievement_batches',
        columns: ['class_name', 'course_name'],
        where: 'id = ?',
        whereArgs: [batchId],
        limit: 1);
    final className =
        batchRows.isNotEmpty ? (batchRows.first['class_name'] ?? '').toString() : '';
    final courseName =
        batchRows.isNotEmpty ? (batchRows.first['course_name'] ?? '').toString() : '';
    final components =
        await collectPlatformAchievementComponents(className: className, courseName: courseName);
    return importComponentsToDatabase(batchId, components);
  }

  /// 聚合结果结构与 AchievementExcelService.parseComponentSheets 一致：
  /// {pingshi: [...], experiment: [...], exam: [...]}。
  Future<Map<String, List<Map<String, dynamic>>>>
      collectPlatformAchievementComponents({String className = '', String courseName = ''}) async {
    final db = await DatabaseHelper.instance.database;
    final students = await _loadActiveStudents(db, className: className, courseName: courseName);
    if (students.isEmpty) {
      return {
        'pingshi': <Map<String, dynamic>>[],
        'experiment': <Map<String, dynamic>>[],
        'exam': <Map<String, dynamic>>[],
      };
    }

    final pingshi = await _collectPlatformPingshiRows();
    final experiment = await _collectPlatformExperimentRows(db, students);
    final exam = await _collectPlatformExamRows(db, students);
    return {
      'pingshi': pingshi,
      'experiment': experiment,
      'exam': exam,
    };
  }

  Future<List<Map<String, dynamic>>> _loadActiveStudents(
    Database db, {
    String className = '',
    String courseName = '',
  }) async {
    // If a class name is provided, scope students to that class.
    if (className.isNotEmpty) {
      try {
        return (await db.rawQuery('''
          SELECT u.user_id,
                 COALESCE(NULLIF(TRIM(u.real_name), ''), u.user_id) AS real_name
          FROM users u
          JOIN class_members cm ON cm.user_id = u.user_id
          JOIN classes c ON c.id = cm.class_id
          WHERE c.name = ?
            AND u.role = 'student'
            AND COALESCE(u.is_active, 1) = 1
            AND COALESCE(c.is_archived, 0) = 0
          ORDER BY u.user_id ASC
        ''', [className])).toList();
      } catch (e, st) {
        swallowDebug(e, tag: 'AchievementDao.loadActiveStudentsByClass', stack: st);
      }
    }
    // Fallback: load all active students (no class scoping).
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    try {
      return (await db.rawQuery('''
        SELECT u.user_id,
               COALESCE(NULLIF(TRIM(u.real_name), ''), u.user_id) AS real_name
        FROM users u
        WHERE $activeWhere
        ORDER BY u.user_id ASC
      ''')).toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.loadActiveStudents', stack: st);
      return (await db.rawQuery('''
        SELECT user_id,
               COALESCE(NULLIF(TRIM(real_name), ''), user_id) AS real_name
        FROM users
        WHERE role = 'student' AND COALESCE(is_active, 1) = 1
        ORDER BY user_id ASC
      ''')).toList();
    }
  }

  Future<List<Map<String, dynamic>>> _collectPlatformPingshiRows() async {
    final snapshot = await OrdinaryScoreDao().loadSnapshot();
    return snapshot.rows.map((row) => row.toPingshiComponentRow()).toList();
  }

  List<Map<String, dynamic>> _baseExperimentRows(
      List<Map<String, dynamic>> students) {
    return [
      for (final student in students)
        {
          'student_id': student['user_id']?.toString() ?? '',
          'student_name': student['real_name']?.toString() ??
              student['user_id']?.toString() ??
              '',
          'exp1_score': 0.0,
          'exp2_score': 0.0,
          'exp3_score': 0.0,
          'exp4_score': 0.0,
          'exp5_score': 0.0,
          'exp6_score': 0.0,
          'exp7_score': 0.0,
        }
    ];
  }

  Future<List<Map<String, dynamic>>> _collectPlatformExperimentRows(
    Database db,
    List<Map<String, dynamic>> students,
  ) async {
    final rows = _baseExperimentRows(students);
    final byStudent = {
      for (final row in rows) row['student_id'].toString(): row,
    };

    try {
      final taskScope =
          await _courseContext.scopedWhere(column: 'lt.course_id');
      final tasks = await db.rawQuery('''
        SELECT lt.id, lt.max_score
        FROM lab_tasks lt
        WHERE ${taskScope.where}
        ORDER BY lt.id ASC
        LIMIT 7
      ''', taskScope.args);
      final taskSlot = <int, String>{
        for (var i = 0; i < tasks.length; i++)
          (tasks[i]['id'] as num).toInt(): 'exp${i + 1}_score',
      };
      if (taskSlot.isEmpty) return rows;

      final activeWhere = ActiveStudentScope.where(alias: 'u');
      final scoreScope =
          await _courseContext.scopedWhere(column: 't.course_id');
      final scores = await db.rawQuery('''
        SELECT s.user_id, s.task_id, s.score, t.max_score
        FROM lab_submissions s
        JOIN lab_tasks t ON t.id = s.task_id
        JOIN users u ON u.user_id = s.user_id
        WHERE ${scoreScope.where}
          AND $activeWhere
          AND s.score IS NOT NULL
      ''', scoreScope.args);

      for (final score in scores) {
        final sid = score['user_id']?.toString() ?? '';
        final taskId = (score['task_id'] as num?)?.toInt();
        final column = taskId == null ? null : taskSlot[taskId];
        final row = byStudent[sid];
        if (row == null || column == null) continue;
        final value = _scoreAsPercent(score['score'], score['max_score']);
        _setScoreIfHigher(row, column, value);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.platformExperiment', stack: st);
    }
    return rows;
  }

  List<Map<String, dynamic>> _baseExamRows(
      List<Map<String, dynamic>> students) {
    return [
      for (final student in students)
        {
          'student_id': student['user_id']?.toString() ?? '',
          'student_name': student['real_name']?.toString() ??
              student['user_id']?.toString() ??
              '',
          'project_score': 0.0,
          'group_score': 0.0,
          'individual_score': 0.0,
          'defense_score': 0.0,
        }
    ];
  }

  Future<List<Map<String, dynamic>>> _collectPlatformExamRows(
    Database db,
    List<Map<String, dynamic>> students,
  ) async {
    final rows = _baseExamRows(students);
    final byStudent = {
      for (final row in rows) row['student_id'].toString(): row,
    };
    await _mergeAssessmentReportScores(db, byStudent);
    await _mergeProjectScores(db, byStudent);
    await _mergeContributionScores(db, byStudent);
    await _mergeWorkScores(db, byStudent);
    return rows;
  }

  Future<void> _mergeAssessmentReportScores(
    Database db,
    Map<String, Map<String, dynamic>> byStudent,
  ) async {
    try {
      if (!await _tableExists(db, 'assessment_reports')) return;
      final activeWhere = ActiveStudentScope.where(alias: 'u');
      final reports = await db.rawQuery('''
        SELECT ar.user_id, ar.title, ar.score
        FROM assessment_reports ar
        JOIN users u ON u.user_id = ar.user_id
        WHERE ar.score IS NOT NULL
          AND $activeWhere
        ORDER BY COALESCE(ar.reviewed_at, ar.submit_time, ar.updated_at, ar.created_at) ASC
      ''');
      for (final report in reports) {
        final row = byStudent[report['user_id']?.toString() ?? ''];
        if (row == null) continue;
        final title = report['title']?.toString() ?? '';
        final score = _scoreAsPercent(report['score'], 100);
        final isFinal = title.contains('课程考核大作业报告') ||
            title.contains('最终') ||
            title.contains('大作业');
        if (isFinal) {
          for (final column in const [
            'project_score',
            'group_score',
            'individual_score',
            'defense_score',
          ]) {
            _setScoreIfHigher(row, column, score);
          }
          continue;
        }
        if (title.contains('项目')) {
          _setScoreIfHigher(row, 'project_score', score);
        }
        if (title.contains('小组')) {
          _setScoreIfHigher(row, 'group_score', score);
        }
        if (title.contains('个人')) {
          _setScoreIfHigher(row, 'individual_score', score);
        }
        if (title.contains('答辩')) {
          _setScoreIfHigher(row, 'defense_score', score);
        }
      }
    } catch (e, st) {
      swallowDebug(e,
          tag: 'AchievementDao.platformAssessmentReports', stack: st);
    }
  }

  Future<void> _mergeProjectScores(
    Database db,
    Map<String, Map<String, dynamic>> byStudent,
  ) async {
    try {
      if (!await _tableExists(db, 'project_scores') ||
          !await _tableExists(db, 'assessment_groups')) {
        return;
      }
      final scores = await db.rawQuery('''
        SELECT ps.total_score, g.member_ids
        FROM project_scores ps
        LEFT JOIN assessment_groups g ON g.id = ps.group_id
        WHERE ps.total_score IS NOT NULL
        ORDER BY ps.scored_at ASC
      ''');
      for (final score in scores) {
        final value = _scoreAsPercent(score['total_score'], 100);
        for (final sid in _parseStringList(score['member_ids'])) {
          final row = byStudent[sid];
          if (row != null) _setScoreIfHigher(row, 'project_score', value);
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.platformProjectScores', stack: st);
    }
  }

  Future<void> _mergeContributionScores(
    Database db,
    Map<String, Map<String, dynamic>> byStudent,
  ) async {
    try {
      if (!await _tableExists(db, 'contribution_scores')) return;
      final activeWhere = ActiveStudentScope.where(alias: 'u');
      final scores = await db.rawQuery('''
        SELECT cs.target_user_id, cs.dimension, AVG(cs.overall_score) AS avg_score
        FROM contribution_scores cs
        JOIN users u ON u.user_id = cs.target_user_id
        WHERE cs.overall_score IS NOT NULL
          AND $activeWhere
        GROUP BY cs.target_user_id, cs.dimension
      ''');
      for (final score in scores) {
        final row = byStudent[score['target_user_id']?.toString() ?? ''];
        if (row == null) continue;
        final value = _scoreAsPercent(score['avg_score'], 100);
        switch (score['dimension']?.toString()) {
          case 'project':
            _setScoreIfHigher(row, 'project_score', value);
            break;
          case 'group':
            _setScoreIfHigher(row, 'group_score', value);
            break;
          case 'individual':
            _setScoreIfHigher(row, 'individual_score', value);
            break;
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.platformContribution', stack: st);
    }
  }

  Future<void> _mergeWorkScores(
    Database db,
    Map<String, Map<String, dynamic>> byStudent,
  ) async {
    try {
      if (!await _tableExists(db, 'work_scores') ||
          !await _tableExists(db, 'student_works')) {
        return;
      }
      final activeWhere = ActiveStudentScope.where(alias: 'u');
      final scope = await _courseContext.scopedWhere(column: 'sw.course_id');
      final scores = await db.rawQuery('''
        SELECT sw.user_id, AVG(ws.total_score) AS avg_score
        FROM work_scores ws
        JOIN student_works sw ON sw.id = ws.work_id
        JOIN users u ON u.user_id = sw.user_id
        LEFT JOIN users scorer ON scorer.user_id = ws.scorer_id
        WHERE ${scope.where}
          AND $activeWhere
          AND COALESCE(ws.scorer_role, scorer.role, '') IN ('teacher', 'admin')
          AND ws.total_score IS NOT NULL
        GROUP BY sw.user_id
      ''', scope.args);
      for (final score in scores) {
        final row = byStudent[score['user_id']?.toString() ?? ''];
        if (row == null) continue;
        _setScoreIfHigher(
            row, 'project_score', _scoreAsPercent(score['avg_score'], 100));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.platformWorks', stack: st);
    }
  }

  List<String> _parseStringList(Object? raw) {
    final text = raw?.toString() ?? '';
    if (text.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (e) {
      swallow(e, tag: 'AchievementDao._parseStringList');
    }
    return text
        .split(RegExp(r'[,，;；\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tableName],
    );
    return result.isNotEmpty;
  }

  double _scoreAsPercent(Object? score, Object? fullScore) {
    double number(Object? value, double fallback) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final value = number(score, 0);
    final full = number(fullScore, 100);
    if (full <= 0) return value.clamp(0.0, 100.0).toDouble();
    final percent = full == 100 ? value : value / full * 100;
    return percent.clamp(0.0, 100.0).toDouble();
  }

  void _setScoreIfHigher(
    Map<String, dynamic> row,
    String column,
    double value,
  ) {
    final current = (row[column] as num?)?.toDouble() ?? 0;
    if (value > current) row[column] = value;
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
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    List<Map<String, dynamic>> rows;
    try {
      rows = await db.rawQuery('''
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
        WHERE $activeWhere
        ORDER BY u.user_id
      ''', quizScope.args);
    } catch (e, st) {
      swallowDebug(e,
          tag: 'AchievementDao.generateScoresFromQuizResults.active',
          stack: st);
      rows = await db.rawQuery('''
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
        WHERE u.role = 'student' AND COALESCE(u.is_active, 1) = 1
        ORDER BY u.user_id
      ''', quizScope.args);
    }

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

      const fm = _kFullMarks;
      final objCount = fm.length;
      final rawScores = <double>[
        avgScore * 0.15,
        correctRate * 25,
        avgScore * 0.30,
        correctRate * 30,
      ];
      while (rawScores.length < objCount) {
        rawScores.add(rawScores.last * 0.5);
      }
      final scoreMap = <String, dynamic>{
        'batch_id': batchId,
        'student_id': userId,
        'student_name': userName,
        'created_at': now,
        'updated_at': now,
      };
      double totalScore = 0;
      for (int i = 0; i < objCount; i++) {
        scoreMap['obj${i + 1}_score'] = rawScores[i];
        scoreMap['obj${i + 1}_achievement'] =
            (rawScores[i] / (fm[i] > 0 ? fm[i] : 1)).clamp(0.0, 1.0);
        totalScore += rawScores[i];
      }
      scoreMap['total_score'] = totalScore;
      batchOp.insert(
          'achievement_scores', scoreMap,
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

  /// MAD 课程默认章节关键词（回落用）。
  static const Map<int, List<String>> _defaultChapterKeywords = {
    1: ['技术体系', '移动应用', '全景', '概述', '第一章', '开发环境'],
    2: ['原生开发', 'Android', 'iOS', 'Kotlin', 'Swift', '第二章'],
    3: ['跨平台', 'Flutter', 'React Native', 'Uniapp', 'MAUI', '混合开发', '第三章'],
    4: ['小程序', '微信', 'WXML', 'WXSS', 'Taro', '第四章'],
    5: ['鸿蒙', 'HarmonyOS', 'ArkUI', 'ArkTS', '分布式', '多端', '第五章'],
    6: ['综合', '实践', '项目', 'Git', '团队', '第六章'],
  };

  /// 根据课程动态生成章节关键词映射。非 MAD 课程按章节标题提取。
  static Future<Map<int, List<String>>> chapterKeywords(
      Database db, String courseId) async {
    final chapters = await _getCourseChapters(db, courseId);
    // 平台化：无章节时不套用 MAD 关键词，返回空映射，由调用方提示教师配置章节，
    // 避免把「移动应用 / 软件 / 技术体系」等 MAD 专属关键词强加给其它课程。
    if (chapters.isEmpty) return const {};
    if (chapters.length == _defaultChapterKeywords.length) {
      final isMad = chapters.every((c) => _defaultChapterKeywords.values
          .any((kws) => kws.any((kw) => c.contains(kw))));
      if (isMad) return _defaultChapterKeywords;
    }
    final result = <int, List<String>>{};
    for (var i = 0; i < chapters.length; i++) {
      final keywords = _extractKeywords(chapters[i]);
      result[i + 1] = ['第${i + 1}章', ...keywords];
    }
    return result;
  }

  static Future<List<String>> _getCourseChapters(
      Database db, String courseId) async {
    try {
      final rows = await db.query('courses',
          columns: ['chapters'],
          where: courseId.isNotEmpty ? 'id = ?' : 'is_active = 1',
          whereArgs: courseId.isNotEmpty ? [courseId] : null,
          limit: 1);
      if (rows.isEmpty) return [];
      final raw = rows.first['chapters'];
      if (raw == null) return [];
      if (raw is List) return raw.cast<String>();
      if (raw is String && raw.trim().startsWith('[')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } catch (e) {
          swallow(e, tag: 'AchievementDao.parseKeywords.inner');
        }
      }
      return [];
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.parseKeywords.outer', stack: st);
      return [];
    }
  }

  static List<String> _extractKeywords(String chapterTitle) {
    final keywords = <String>[];
    for (final word in chapterTitle.split(RegExp(r'[\s、，,./]'))) {
      final trimmed = word.trim();
      if (trimmed.length >= 2 && !RegExp(r'^[第\d章]+$').hasMatch(trimmed)) {
        keywords.add(trimmed);
      }
    }
    return keywords;
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

    final courseId = await _courseContext.activeCourseId();
    final chapterKeywordsMap = await chapterKeywords(db, courseId);

    int count = 0;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    for (final res in resources) {
      final fileName = (res['file_name'] as String? ?? '').toLowerCase();
      final filePath = (res['file_path'] as String? ?? '').toLowerCase();
      final desc = (res['description'] as String? ?? '').toLowerCase();
      final combined = '$fileName $filePath $desc';

      for (final entry in chapterKeywordsMap.entries) {
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
                  'chapter_title': '第$chapter章',
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
                final val = _surveyLikertScore(answer);
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

            // 满意度/达成度题统一按 1-5 量表转换为 0-1。
            double likertSum = 0;
            int likertCount = 0;
            for (final entry in optionCounts.entries) {
              final score = _surveyLikertScore(entry.key);
              if (score > 0 && entry.value > 0) {
                likertSum += score * entry.value;
                likertCount += entry.value;
              }
            }
            if (likertCount > 0 &&
                (options.any((o) =>
                        o.contains('满意') ||
                        o.contains('符合') ||
                        o.contains('达成')) ||
                    (q['question']?.toString().contains('达成') ?? false) ||
                    (q['question']?.toString().contains('毕业要求') ?? false))) {
              satisfactionSum += likertSum / likertCount / 5.0;
              satisfactionCount++;
            }

            // 计算达成率（针对'达成程度'类题目）
            final achievementKeys = ['完全达成', '较好达成', '基本达成'];
            int achieved = 0;
            int totalSelected = 0;
            for (final entry in optionCounts.entries) {
              totalSelected += entry.value;
              if (achievementKeys.contains(entry.key)) {
                achieved += entry.value;
              }
            }

            allQuestionStats.add({
              'question': q['question'],
              'type': 'single_choice',
              'options': options,
              'counts': optionCounts,
              'total': responses.length,
              'achievementRate': likertCount > 0
                  ? likertSum / likertCount / 5.0
                  : totalSelected > 0
                      ? achieved / totalSelected
                      : 0.0,
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

  int _surveyLikertScore(Object? value) {
    final text = value?.toString().trim().toUpperCase() ?? '';
    if (text.isEmpty) return 0;
    if (text == 'E' || text.contains('完全符合') || text.contains('非常满意')) {
      return 5;
    }
    if (text == 'D' || text.contains('比较符合') || text.contains('较好达成')) {
      return 4;
    }
    if (text == 'C' || text.contains('一般符合') || text.contains('基本达成')) {
      return 3;
    }
    if (text == 'B' || text.contains('不太符合') || text.contains('部分达成')) {
      return 2;
    }
    if (text == 'A' || text.contains('完全不符合') || text.contains('未达成')) {
      return 1;
    }
    final numeric = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (numeric != null && numeric >= 1 && numeric <= 5) return numeric;
    return 0;
  }

  /// 生成持续改进建议（基于达成度分析）
  Future<List<Map<String, dynamic>>> generateImprovementSuggestions(
      int batchId) async {
    final scores = await getScores(batchId);
    if (scores.isEmpty) return [];

    final batch = await getBatch(batchId);
    final courseName = batch?['course_name']?.toString() ?? '当前课程';
    final objectives = await getCourseObjectives(courseName);
    final weights = await resolveObjectiveWeights(batchId);
    final fullMarks = await resolveObjectiveFullMarks(batchId);
    final envWeights = await resolveObjectiveAssessmentWeights(batchId);
    final objectiveByIdx = <int, Map<String, dynamic>>{
      for (final row in objectives)
        if (_asInt(row['idx']) > 0) _asInt(row['idx']): row
    };
    final objectiveCount = _objectiveCount(
      weights: weights,
      fullMarks: fullMarks,
    );
    final activeIndexes = [
      for (var i = 0; i < objectiveCount; i++)
        if ((i < weights.length && weights[i] > 0) ||
            (i < fullMarks.length && fullMarks[i] > 0))
          i
    ];
    if (activeIndexes.isEmpty) {
      activeIndexes.addAll(List<int>.generate(objectiveCount, (i) => i));
    }

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
          .take(10)
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
        final aggJson = s['achievements_json'] as String?;

        if (!pHas && usesPingshi) {
          // 平时：课堂→目标1, 测验→目标2, 课外→目标4（目标3无平时项）
          final pRow = <String, dynamic>{
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
          };
          if (aggJson != null) pRow['achievements_json'] = aggJson;
          await txn.insert('achievement_pingshi_scores', pRow,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (!eHas && usesExperiment) {
          final eRow = <String, dynamic>{
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
          };
          if (aggJson != null) eRow['achievements_json'] = aggJson;
          await txn.insert('achievement_experiment_scores', eRow,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (!xHas && usesExam) {
          final xRow = <String, dynamic>{
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
          };
          if (aggJson != null) xRow['achievements_json'] = aggJson;
          await txn.insert('achievement_exam_scores', xRow,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  // ── 平时成绩 ─────────────────────────────────────────────────────────
  /// 前 3 个子分项（class_activity/quiz_homework/extra_learning）依次映射到 obj1-obj3，剩余目标达成度为 0。

  Future<List<Map<String, dynamic>>> getPingshiScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureComponentScoresFromAggregate(batchId);
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    try {
      return (await db.rawQuery('''
        SELECT s.*
        FROM achievement_pingshi_scores s
        LEFT JOIN users u ON u.user_id = s.student_id
        WHERE s.batch_id = ?
          AND (u.user_id IS NULL OR ($activeWhere))
        ORDER BY s.student_id ASC
      ''', [batchId])).toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.getPingshiScores.active', stack: st);
      return (await db.query('achievement_pingshi_scores',
              where: 'batch_id = ?',
              whereArgs: [batchId],
              orderBy: 'student_id ASC'))
          .toList();
    }
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

  /// 计算平时成绩的分项达成度。
  /// [objectiveCount] 来自 course_objectives 的实际目标数。
  /// 前 3 个子分项依次映射到 obj1-obj3，剩余目标达成度为 0。
  Map<String, double> calculatePingshiAchievement(
    Map<String, dynamic> score, {
    int objectiveCount = 10,
  }) {
    final classScore = (score['class_activity_score'] as num?)?.toDouble() ?? 0;
    final quizScore = (score['quiz_homework_score'] as num?)?.toDouble() ?? 0;
    final extraScore = (score['extra_learning_score'] as num?)?.toDouble() ?? 0;
    final subScores = [classScore, quizScore, extraScore];

    final result = <String, double>{};
    for (int i = 0; i < objectiveCount && i < 10; i++) {
      final sub = i < subScores.length ? subScores[i] : 0;
      result['obj${i + 1}_achievement'] = (sub / 100).clamp(0.0, 1.0);
    }
    result['total_score'] =
        classScore * 0.2 + quizScore * 0.3 + extraScore * 0.5;
    return result;
  }

  /// 计算平时成绩的班级平均达成度（任意目标数）。
  Future<Map<String, double>> calculatePingshiClassAverage(
    int batchId, {
    int objectiveCount = 10,
  }) async {
    final scores = await getPingshiScores(batchId);
    if (scores.isEmpty) {
      return {for (int i = 1; i <= objectiveCount; i++) 'obj$i': 0.0};
    }
    final n = scores.length.toDouble();
    final sums = List<double>.filled(objectiveCount, 0);
    for (final s in scores) {
      final ach = _extractAchievementsFromRow(s, 'pingshi', objectiveCount);
      for (int i = 0; i < objectiveCount && i < ach.length; i++) {
        sums[i] += ach[i];
      }
    }
    return {for (int i = 0; i < objectiveCount; i++) 'obj${i + 1}': sums[i] / n};
  }

  /// 从成绩行中提取各目标达成度数组（支持任意目标数）。
  /// 先尝试 achievements_json（通用列），回退到固定 objN_achievement 列。
  static List<double> _extractAchievementsFromRow(
    Map<String, dynamic> row,
    String table, // 'pingshi', 'experiment', 'exam'
    int objectiveCount,
  ) {
    // 尝试 achievements_json
    final jsonStr = row['achievements_json'] as String?;
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        final result = List<double>.filled(objectiveCount, 0.0);
        for (int i = 1; i <= objectiveCount; i++) {
          result[i - 1] =
              (parsed['obj${i}_achievement'] as num?)?.toDouble() ?? 0.0;
        }
        return result;
      } catch (e) {
        swallow(e, tag: 'AchievementDao.extractAch.json');
      }
    }
    // 回退到固定列
    return [
      for (int i = 1; i <= objectiveCount; i++)
        (row['obj${i}_achievement'] as num?)?.toDouble() ?? 0.0,
    ];
  }

  /// 生成平时演示数据

  // ── 实验成绩 ─────────────────────────────────────────────────────────
  /// 实验1-2→目标1, 实验3-4→目标2，兼容两类模板：
  /// - 学校表格48：实验5-6→目标3, 实验7→目标4；
  /// - 简洁/6实验模板：实验5→目标3, 实验6→目标4。

  Future<List<Map<String, dynamic>>> getExperimentScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureComponentScoresFromAggregate(batchId);
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    try {
      return (await db.rawQuery('''
        SELECT s.*
        FROM achievement_experiment_scores s
        LEFT JOIN users u ON u.user_id = s.student_id
        WHERE s.batch_id = ?
          AND (u.user_id IS NULL OR ($activeWhere))
        ORDER BY s.student_id ASC
      ''', [batchId])).toList();
    } catch (e, st) {
      swallowDebug(e,
          tag: 'AchievementDao.getExperimentScores.active', stack: st);
      return (await db.query('achievement_experiment_scores',
              where: 'batch_id = ?',
              whereArgs: [batchId],
              orderBy: 'student_id ASC'))
          .toList();
    }
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

  /// 计算实验成绩的分项达成度。
  /// [objectiveCount] 来自 course_objectives 的实际目标数。
  /// 前 N 个实验按 2 个一组依次映射到目标（exp1+exp2→obj1 等）。
  Map<String, double> calculateExperimentAchievement(
    Map<String, dynamic> score, {
    int objectiveCount = 10,
  }) {
    final exps = <double>[];
    for (int i = 1; i <= 7; i++) {
      exps.add((score['exp${i}_score'] as num?)?.toDouble() ?? 0);
    }
    final activeExps = exps.where((e) => e > 0).toList();
    final count = activeExps.length;

    final result = <String, double>{};
    for (int i = 0; i < objectiveCount && i < 10; i++) {
      final idx = i * 2;
      if (idx < count) {
        final a = activeExps[idx];
        final b = idx + 1 < count ? activeExps[idx + 1] : a;
        result['obj${i + 1}_achievement'] = ((a + b) / 2 / 100).clamp(0.0, 1.0);
      } else if (idx < 7 && exps[idx] > 0) {
        result['obj${i + 1}_achievement'] = (exps[idx] / 100).clamp(0.0, 1.0);
      } else {
        result['obj${i + 1}_achievement'] = 0.0;
      }
    }
    result['total_score'] = count > 0 ? activeExps.reduce((a, b) => a + b) / count : 0;
    return result;
  }

  /// 计算实验成绩的班级平均达成度（任意目标数）。
  Future<Map<String, double>> calculateExperimentClassAverage(
    int batchId, {
    int objectiveCount = 10,
  }) async {
    final scores = await getExperimentScores(batchId);
    if (scores.isEmpty) {
      return {for (int i = 1; i <= objectiveCount; i++) 'obj$i': 0.0};
    }
    final n = scores.length.toDouble();
    final sums = List<double>.filled(objectiveCount, 0);
    for (final s in scores) {
      final ach = _extractAchievementsFromRow(s, 'experiment', objectiveCount);
      for (int i = 0; i < objectiveCount && i < ach.length; i++) {
        sums[i] += ach[i];
      }
    }
    return {for (int i = 0; i < objectiveCount; i++) 'obj${i + 1}': sums[i] / n};
  }

  /// 生成实验演示数据

  // ── 期末考核成绩 ──────────────────────────────────────────────────────
  /// 项目30%→目标1, 小组20%→目标2, 个人20%→目标3, 答辩30%→目标4

  Future<List<Map<String, dynamic>>> getExamScores(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureComponentScoresFromAggregate(batchId);
    final activeWhere = ActiveStudentScope.where(alias: 'u');
    try {
      return (await db.rawQuery('''
        SELECT s.*
        FROM achievement_exam_scores s
        LEFT JOIN users u ON u.user_id = s.student_id
        WHERE s.batch_id = ?
          AND (u.user_id IS NULL OR ($activeWhere))
        ORDER BY s.student_id ASC
      ''', [batchId])).toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementDao.getExamScores.active', stack: st);
      return (await db.query('achievement_exam_scores',
              where: 'batch_id = ?',
              whereArgs: [batchId],
              orderBy: 'student_id ASC'))
          .toList();
    }
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

  /// 计算期末考核的分项达成度。
  /// [objectiveCount] 来自 course_objectives 的实际目标数。
  /// 前 4 个子分项依次映射到 obj1-obj4，其余目标的达成度为 0。
  Map<String, double> calculateExamAchievement(
    Map<String, dynamic> score, {
    int objectiveCount = 10,
  }) {
    final subScores = <double>[
      (score['project_score'] as num?)?.toDouble() ?? 0,
      (score['group_score'] as num?)?.toDouble() ?? 0,
      (score['individual_score'] as num?)?.toDouble() ?? 0,
      (score['defense_score'] as num?)?.toDouble() ?? 0,
    ];
    final weights = [0.3, 0.2, 0.2, 0.3];

    final result = <String, double>{};
    for (int i = 0; i < objectiveCount && i < 10; i++) {
      final sub = i < subScores.length ? subScores[i] : 0;
      result['obj${i + 1}_achievement'] = (sub / 100).clamp(0.0, 1.0);
    }
    double total = 0;
    for (int i = 0; i < subScores.length; i++) {
      total += subScores[i] * weights[i];
    }
    result['total_score'] = total;
    return result;
  }

  /// 计算期末考核的班级平均达成度（任意目标数）。
  Future<Map<String, double>> calculateExamClassAverage(
    int batchId, {
    int objectiveCount = 10,
  }) async {
    final scores = await getExamScores(batchId);
    if (scores.isEmpty) {
      return {for (int i = 1; i <= objectiveCount; i++) 'obj$i': 0.0};
    }
    final n = scores.length.toDouble();
    final sums = List<double>.filled(objectiveCount, 0);
    for (final s in scores) {
      final ach = _extractAchievementsFromRow(s, 'exam', objectiveCount);
      for (int i = 0; i < objectiveCount && i < ach.length; i++) {
        sums[i] += ach[i];
      }
    }
    return {for (int i = 0; i < objectiveCount; i++) 'obj${i + 1}': sums[i] / n};
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
      final dynamicAverage = await _dynamicComponentClassAverage(batchId, env);
      if (dynamicAverage.isNotEmpty) return dynamicAverage;
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
    final objCount = envWeights.length;
    final combined = <String, double>{
      for (int i = 1; i <= objCount; i++) 'obj$i': aggregateAvg['课程目标$i'] ?? 0,
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
      for (int i = 1; i <= envWeights.length; i++)
        if ((envWeights[i - 1][env] ?? 0) > 0.0001)
          'obj$i': aggregateAvg['课程目标$i'] ?? 0,
    };
  }

  Future<void> _ensureDynamicComponentScoresTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievement_component_scores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        student_id TEXT NOT NULL,
        student_name TEXT,
        kind TEXT NOT NULL,
        objective INTEGER NOT NULL,
        label TEXT,
        score REAL DEFAULT 0,
        achievement REAL DEFAULT 0,
        ratio REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        UNIQUE(batch_id, student_id, kind, objective, label)
      )
    ''');
  }

  Future<Map<String, double>> _dynamicComponentClassAverage(
      int batchId, String env) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureDynamicComponentScoresTable(db);
    final rows = await db.rawQuery('''
      SELECT objective, AVG(student_achievement) AS achievement
      FROM (
        SELECT student_id,
               objective,
               CASE
                 WHEN SUM(ratio) > 0
                 THEN SUM(achievement * ratio) / SUM(ratio)
                 ELSE AVG(achievement)
               END AS student_achievement
        FROM achievement_component_scores
        WHERE batch_id = ? AND kind = ?
        GROUP BY student_id, objective
      )
      GROUP BY objective
    ''', [batchId, env]);
    return {
      for (final row in rows)
        if (_asInt(row['objective']) >= 1 && _asInt(row['objective']) <= 10)
          'obj${_asInt(row['objective'])}':
              _asDouble(row['achievement']).clamp(0.0, 1.0).toDouble()
    };
  }

  Future<Map<int, double>> _dynamicAggregateClassAverage(int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureDynamicComponentScoresTable(db);
    final rows = await db.rawQuery('''
      SELECT objective, AVG(student_achievement) AS achievement
      FROM (
        SELECT student_id,
               objective,
               CASE
                 WHEN SUM(ratio) > 0
                 THEN SUM(achievement * ratio) / SUM(ratio)
                 ELSE AVG(achievement)
               END AS student_achievement
        FROM achievement_component_scores
        WHERE batch_id = ?
        GROUP BY student_id, objective
      )
      GROUP BY objective
    ''', [batchId]);
    return {
      for (final row in rows)
        if (_asInt(row['objective']) >= 1 && _asInt(row['objective']) <= 10)
          _asInt(row['objective']):
              _asDouble(row['achievement']).clamp(0.0, 1.0).toDouble()
    };
  }

  Future<Map<int, List<double>>> _dynamicAggregateStudentAchievements(
      int batchId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensureDynamicComponentScoresTable(db);
    final rows = await db.rawQuery('''
      SELECT student_id,
             objective,
             CASE
               WHEN SUM(ratio) > 0
               THEN SUM(achievement * ratio) / SUM(ratio)
               ELSE AVG(achievement)
             END AS achievement
      FROM achievement_component_scores
      WHERE batch_id = ?
      GROUP BY student_id, objective
      ORDER BY student_id ASC, objective ASC
    ''', [batchId]);
    final result = <int, List<double>>{};
    for (final row in rows) {
      final objective = _asInt(row['objective']);
      if (objective < 1 || objective > 10) continue;
      result
          .putIfAbsent(objective, () => <double>[])
          .add(_asDouble(row['achievement']).clamp(0.0, 1.0).toDouble());
    }
    return result;
  }

  /// 从 aggregate 行推断课程目标数量。
  /// 优先从 course_objectives 表读取，再回退到行中 objN_achievement 列数。
  Future<int> _inferObjectiveCount(Map<String, dynamic>? row,
      [String courseName = '']) async {
    if (courseName.isNotEmpty) {
      try {
        final objs = await getCourseObjectives(courseName);
        if (objs.isNotEmpty) return objs.length;
      } catch (e) {
        swallow(e, tag: 'AchievementDao.inferObjCount');
      }
    }
    if (row == null) return 4;
    var count = 0;
    for (int i = 1; i <= 10; i++) {
      if (row.containsKey('obj${i}_achievement')) count = i;
    }
    return count > 0 ? count : 4;
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
        default:
          final objCount = await _inferObjectiveCount(aggregate);
          for (var i = 1; i <= objCount; i++) {
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
