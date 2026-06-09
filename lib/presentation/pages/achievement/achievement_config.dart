import '../../../core/error_handler.dart';

/// 达成度配置单一来源（SSOT）。
///
/// 历史上权重/满分散落在 5+ 处且互相矛盾（UI 0.10/0.20/0.30/0.40、
/// DAO 0.15/0.25/0.30/0.30、满分 15/25/30/30、report_tab 又是 10/20/30/40），
/// 同一份成绩在不同代码路径算出不同达成度。此类收敛为唯一来源。
///
/// 权威基准取自《移动应用开发》教学大纲第六节「课程成绩评定」：
/// 目标权重 0.15/0.25/0.30/0.30、满分 15/25/30/30、指标点 1.4/3.2/4.2/5.1、
/// 三环节权重 平时0.20/实验0.30/期末0.50。
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

  /// 回落默认（与大纲、Python 参考、DB 默认 objective_weights_json 一致）。
  /// 满分与权重必须同源，不可分开维护。
  static const AchievementConfig defaults = AchievementConfig(
    weights: [0.15, 0.25, 0.30, 0.30],
    fullMarks: [15.0, 25.0, 30.0, 30.0],
    objectiveNames: ['课程目标1', '课程目标2', '课程目标3', '课程目标4'],
    indicators: ['1.4', '3.2', '4.2', '5.1'],
    descriptions: [
      '掌握移动应用开发技术体系（原生/混合/跨平台）及主流平台特性，理解技术选型逻辑，熟悉跨平台开发框架和 AI 编程工具的基本使用',
      '运用跨平台开发框架及小程序技术，结合 AI 编程工具与后端 API 交互，设计实现跨平台应用，具备需求建模与创新应用能力',
      '调研对比多端开发方案，分析不同技术栈在跨设备适配场景中的优劣，具备技术方案评估与选型能力',
      '遵循软件工程规范，使用现代开发工具（含 AI 编程工具、Git 版本控制）完成应用测试与优化，具备工程实践能力',
    ],
    chapters: ['第1章 + 第2章', '第3章 + 第4章', '第5章', '第6章'],
    assessContents: [
      '课堂表现、实验1-2、期末项目',
      '期间测验、实验3-4、小组评价',
      '实验5-6、个人考核',
      '课外学习、实验7、答辩',
    ],
    assessmentWeights: {'平时': 0.20, '实验': 0.30, '期末': 0.50},
  );

  /// 从 course_objectives 表行（按 idx 升序）构建完整配置。缺字段回落默认。
  static AchievementConfig fromObjectiveRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return defaults;
    final sorted = [...rows]..sort((a, b) => (a['idx'] as int).compareTo(b['idx'] as int));
    final n = sorted.length;
    if (n == 0) return defaults;
    try {
      List<T> pick<T>(T Function(Map<String, dynamic>, int) f) =>
          List<T>.generate(n, (i) => f(sorted[i], i));
      return AchievementConfig(
        weights: pick((r, i) => (r['weight'] as num?)?.toDouble() ?? _at(defaults.weights, i)),
        fullMarks: pick((r, i) => (r['full_mark'] as num?)?.toDouble() ?? _at(defaults.fullMarks, i)),
        objectiveNames: pick((r, i) => (r['name'] as String?)?.trim().isNotEmpty == true
            ? r['name'] as String
            : _at(defaults.objectiveNames, i)),
        indicators: pick((r, i) => (r['indicator'] as String?) ?? _at(defaults.indicators, i)),
        descriptions: pick((r, i) => (r['description'] as String?) ?? _at(defaults.descriptions, i)),
        chapters: pick((r, i) => (r['chapters'] as String?) ?? _at(defaults.chapters, i)),
        assessContents: pick((r, i) => (r['assess_content'] as String?) ?? _at(defaults.assessContents, i)),
        assessmentWeights: defaults.assessmentWeights,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementConfig.fromObjectiveRows', stack: st);
      return defaults;
    }
  }

  static T _at<T>(List<T> list, int i) => i < list.length ? list[i] : list.last;
}
