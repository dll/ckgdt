import '../../../core/error_handler.dart';
import '../../../data/models/course_model.dart';

/// 达成度配置单一来源（SSOT）。
///
/// 历史上权重/满分散落在 5+ 处且互相矛盾（UI 0.10/0.20/0.30/0.40、
/// DAO 0.15/0.25/0.30/0.30、满分 15/25/30/30、report_tab 又是 10/20/30/40），
/// 同一份成绩在不同代码路径算出不同达成度。此类收敛为唯一来源。
///
/// 取值优先级：course_objectives 表（大纲导入）> 批次 objective_weights_json > 此处默认。
class AchievementConfig {
  final List<double> weights; // 4 个课程目标权重，和为 1
  final List<double> fullMarks; // 4 个课程目标满分
  final List<String> objectiveNames;
  final List<String> indicators; // 毕业要求指标点，如 '1.4'
  final List<String> descriptions; // 课程目标完整描述
  final List<String> chapters; // 支撑章节
  final List<String> assessContents; // 考核内容
  final Map<String, double> assessmentWeights; // 平时/实验/期末环节权重

  const AchievementConfig({
    required this.weights,
    required this.fullMarks,
    required this.objectiveNames,
    required this.indicators,
    required this.descriptions,
    required this.chapters,
    required this.assessContents,
    required this.assessmentWeights,
  });

  /// 回落默认（无任何课程上下文时的通用兜底，不绑定《移动应用开发》等具体课程）。
  /// 满分与权重必须同源，不可分开维护。真实课程应基于大纲（course_objectives）动态生成。
  static const AchievementConfig defaults = AchievementConfig(
    weights: [0.15, 0.25, 0.30, 0.30],
    fullMarks: [15.0, 25.0, 30.0, 30.0],
    objectiveNames: ['课程目标1', '课程目标2', '课程目标3', '课程目标4'],
    indicators: ['', '', '', ''],
    descriptions: [
      '目标1：掌握本课程核心知识与基本概念，建立课程整体认知框架',
      '目标2：能够运用课程方法与技术完成典型任务，具备问题分析与实践能力',
      '目标3：能够采集与分析学习与实践过程数据，识别问题并提出改进方案',
      '目标4：能够结合工具与持续改进流程完成课程综合实践与质量评价',
    ],
    chapters: ['', '', '', ''],
    assessContents: [
      '课堂表现与过程参与',
      '实验/实践任务',
      '过程测验与作品成果',
      '综合项目与持续改进',
    ],
    assessmentWeights: {'平时': 0.20, '实验': 0.30, '期末': 0.50},
  );

  /// 基于课程模型动态生成默认配置，替代硬编码的 MAD 默认值。
  ///
  /// 当目标数 > 4 时，按比例重新分配权重和满分，确保每个目标都有非零值，
  /// 避免页面过滤器将权重/满分为 0 的目标静默隐藏。
  static Map<String, dynamic> defaultsForCourse(CourseModel course) {
    final chapterCount = course.chapters.isNotEmpty
        ? course.chapters.length
        : course.chapterCount;
    // 无章节信息时给通用兜底目标数，避免达成报告因 0 目标而空白
    // （仅作平台化兜底，真实目标数始终以大纲 course_objectives 为准）。
    final objectiveCount = chapterCount <= 0
        ? 4
        : (chapterCount <= 3 ? chapterCount : chapterCount.clamp(4, 10));
    final baseWeights = [0.15, 0.25, 0.30, 0.30];
    final baseMarks = [15.0, 25.0, 30.0, 30.0];
    List<double> weights;
    List<double> marks;
    if (objectiveCount <= baseWeights.length) {
      weights = baseWeights.sublist(0, objectiveCount);
      marks = baseMarks.sublist(0, objectiveCount);
    } else {
      // 超出基础目标数时，按比例均匀分配，确保所有目标都有非零权重/满分
      final totalWeight = baseWeights.reduce((a, b) => a + b);
      final totalMarks = baseMarks.reduce((a, b) => a + b);
      final perWeight = totalWeight / objectiveCount;
      final perMark = totalMarks / objectiveCount;
      weights = List.generate(objectiveCount, (i) => double.parse(perWeight.toStringAsFixed(4)));
      marks = List.generate(objectiveCount, (i) => double.parse(perMark.toStringAsFixed(2)));
      // 补偿浮点误差使总和精确
      final weightDiff = totalWeight - weights.reduce((a, b) => a + b);
      final markDiff = totalMarks - marks.reduce((a, b) => a + b);
      if (weightDiff.abs() > 1e-9) weights[0] += weightDiff;
      if (markDiff.abs() > 1e-9) marks[0] += markDiff;
    }
    return {
      'objectiveCount': objectiveCount,
      'chapterCount': chapterCount,
      'weights': weights,
      'fullMarks': marks,
      'pingshi_ratio': 0.20,
      'experiment_ratio': 0.30,
      'exam_ratio': 0.50,
      'descriptions':
          List.generate(objectiveCount, (i) => '目标${i + 1}：掌握课程相关知识与技能'),
      'chapters': _splitChaptersIntoObjectives(chapterCount, objectiveCount),
      'indicators':
          List.generate(objectiveCount, (i) => _defaultIndicator(i + 1)),
      'assessContents': List.generate(objectiveCount, (i) => '考核内容${i + 1}'),
      'assessmentWeights': {'平时': 0.20, '实验': 0.30, '期末': 0.50},
    };
  }

  /// 从 course_objectives 表行（按 idx 升序）构建完整配置。缺字段回落默认。
  static AchievementConfig fromObjectiveRows(List<Map<String, dynamic>> rows,
      {CourseModel? course}) {
    final fallback = _buildFallback(course);
    if (rows.isEmpty) return fallback;
    final sorted = [...rows]
      ..sort((a, b) => _asInt(a['idx']).compareTo(_asInt(b['idx'])));
    final byIdx = <int, Map<String, dynamic>>{
      for (final row in sorted)
        if (_asInt(row['idx']) > 0) _asInt(row['idx']): row
    };
    // 动态目标数量：以 course_objectives 表中的实际 idx 为准，
    // 不为空时不再以 fallback.weights.length 为下限，确保 3 个目标就显示 3 个。
    final objCount = byIdx.isNotEmpty
        ? byIdx.keys.fold<int>(0, (m, k) => k > m ? k : m)
        : fallback.weights.length;
    final count = byIdx.isNotEmpty ? objCount : objCount > fallback.weights.length ? objCount : fallback.weights.length;
    try {
      List<T> pick<T>(T Function(Map<String, dynamic>?, int) f) =>
          List<T>.generate(count, (i) => f(byIdx[i + 1], i));
      return AchievementConfig(
        weights: pick((r, i) => r == null
            ? _at(fallback.weights, i)
            : _asRatio(r['weight'], _at(fallback.weights, i))),
        fullMarks: pick((r, i) => r == null
            ? _at(fallback.fullMarks, i)
            : _asDouble(r['full_mark'], _at(fallback.fullMarks, i))),
        objectiveNames: pick((r, i) =>
            (r?['name'] as String?)?.trim().isNotEmpty == true
                ? r!['name'] as String
                : _at(fallback.objectiveNames, i)),
        indicators: pick((r, i) => (r?['indicator'] as String?) ?? ''),
        descriptions: pick((r, i) => (r?['description'] as String?) ?? ''),
        chapters: pick((r, i) => (r?['chapters'] as String?) ?? ''),
        assessContents: pick((r, i) => (r?['assess_content'] as String?) ?? ''),
        assessmentWeights: _averageAssessmentWeights(sorted),
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementConfig.fromObjectiveRows', stack: st);
      return fallback;
    }
  }

  static AchievementConfig _buildFallback(CourseModel? course) {
    if (course == null) return defaults;
    final d = defaultsForCourse(course);
    final oc = d['objectiveCount'] as int;
    return AchievementConfig(
      weights: List<double>.from(d['weights'] as List<double>),
      fullMarks: List<double>.from(d['fullMarks'] as List<double>),
      objectiveNames: List.generate(oc, (i) => '课程目标${i + 1}'),
      indicators: List<String>.from(d['indicators'] as List<String>),
      descriptions: List<String>.from(d['descriptions'] as List<String>),
      chapters: List<String>.from(d['chapters'] as List<String>),
      assessContents: List<String>.from(d['assessContents'] as List<String>),
      assessmentWeights:
          Map<String, double>.from(d['assessmentWeights'] as Map),
    );
  }

  static T _at<T>(List<T> list, int i) => i < list.length ? list[i] : list.last;

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

  static double _asRatio(Object? value, [double fallback = 0]) {
    final ratio = _asDouble(value, fallback);
    return ratio > 1 ? ratio / 100 : ratio;
  }

  static Map<String, double> _averageAssessmentWeights(
      List<Map<String, dynamic>> rows) {
    double p = 0, e = 0, x = 0;
    var count = 0;
    for (final row in rows) {
      final rp = _asRatio(row['pingshi_ratio']);
      final re = _asRatio(row['experiment_ratio']);
      final rx = _asRatio(row['exam_ratio']);
      final sum = rp + re + rx;
      if (sum <= 0) continue;
      p += rp / sum;
      e += re / sum;
      x += rx / sum;
      count++;
    }
    if (count == 0) return const {'平时': 0, '实验': 0, '期末': 1};
    return {
      '平时': p / count,
      '实验': e / count,
      '期末': x / count,
    };
  }

  static String _defaultIndicator(int idx) {
    final major = ((idx - 1) ~/ 3) + 1;
    final minor = ((idx - 1) % 3) + 1;
    return '$major.$minor';
  }

  static List<String> _splitChaptersIntoObjectives(
      int chapterCount, int objectiveCount) {
    if (objectiveCount <= 0) return [];
    final perGroup = (chapterCount / objectiveCount).ceil();
    final result = <String>[];
    for (var i = 0; i < objectiveCount; i++) {
      final start = i * perGroup + 1;
      final end = (start + perGroup - 1).clamp(1, chapterCount);
      if (start == end) {
        result.add('第$start章');
      } else {
        result.add('第$start章 - 第$end章');
      }
    }
    return result;
  }
}
