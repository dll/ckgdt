import '../data/local/database_helper.dart';
import 'course_context_service.dart';
import 'course_subgraph_service.dart';

/// Resolves user-facing course terms from the active course template/profile.
///
/// Historical DB tables and routes still use "lab" for compatibility, but
/// platform-facing copy should describe the actual course shape: experiment,
/// reading practice, sports training, creation, case practice, etc.
class CourseTerminologyService {
  CourseTerminologyService({
    CourseContextService? courseContext,
    DatabaseHelper? databaseHelper,
    CourseSubgraphService? subgraphService,
  })  : _courseContext = courseContext ?? CourseContextService(),
        _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _subgraphService = subgraphService ?? const CourseSubgraphService();

  final CourseContextService _courseContext;
  final DatabaseHelper _databaseHelper;
  final CourseSubgraphService _subgraphService;

  Future<CourseTerms> activeTerms() async {
    final course = await _courseContext.getActiveCourse();
    final profile = await _latestTemplateProfile(course.id);
    if (profile != null) return CourseTerms.fromTemplateProfile(profile);

    final inferred = _subgraphService.inferProfile(
      courseName: course.name,
      chapters: course.chapters,
      syllabusContent: course.description,
    );
    return CourseTerms.fromPracticeLabel(inferred.practiceLabel);
  }

  Future<String?> _latestTemplateProfile(String courseId) async {
    try {
      final db = await _databaseHelper.database;
      final rows = await db.query(
        'course_package_versions',
        columns: ['template_profile'],
        where: 'course_id = ?',
        whereArgs: [courseId],
        orderBy: 'imported_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final profile = rows.first['template_profile']?.toString().trim();
      return profile == null || profile.isEmpty ? null : profile;
    } catch (_) {
      return null;
    }
  }
}

class CourseTerms {
  final String practiceLabel;
  final String taskLabel;
  final String taskPluralLabel;
  final String reportLabel;
  final String materialLabel;
  final String submitVerbLabel;

  const CourseTerms({
    required this.practiceLabel,
    required this.taskLabel,
    required this.taskPluralLabel,
    required this.reportLabel,
    required this.materialLabel,
    required this.submitVerbLabel,
  });

  /// 导航栏短标签（2-3字）：实验、研读、训练、创作、案例、技能、实践
  String get navLabel {
    if (practiceLabel.contains('实验')) return '实验';
    if (practiceLabel.contains('研读')) return '研读';
    if (practiceLabel.contains('训练')) return '训练';
    if (practiceLabel.contains('创作')) return '创作';
    if (practiceLabel.contains('案例')) return '案例';
    if (practiceLabel.contains('技能')) return '技能';
    return '实践';
  }

  /// 管理入口标签：实验管理、研读实践管理、训练实践管理……
  String get manageLabel => '${practiceLabel}管理';

  /// 英雄区描述中的实践术语（含斜杠前后缀）
  String get heroPracticeRef => practiceLabel;

  factory CourseTerms.fromTemplateProfile(String profile) {
    switch (profile) {
      case 'engineering_experiment':
        return CourseTerms.fromPracticeLabel('实验项目');
      case 'literature_reading':
        return CourseTerms.fromPracticeLabel('研读实践');
      case 'sports_training':
        return CourseTerms.fromPracticeLabel('训练实践');
      case 'art_creation':
        return CourseTerms.fromPracticeLabel('创作实践');
      case 'case_analysis':
        return CourseTerms.fromPracticeLabel('案例实践');
      case 'skill_simulation':
        return CourseTerms.fromPracticeLabel('技能实践');
      default:
        return CourseTerms.fromPracticeLabel('实践任务');
    }
  }

  factory CourseTerms.fromPracticeLabel(String label) {
    final normalized = label.trim().isEmpty ? '实践任务' : label.trim();
    // Derive short task base: "实验项目" → "实验", "研读实践" → "研读", "实践任务" → "实践"
    String base;
    if (normalized.contains('项目')) {
      base = normalized.replaceAll('项目', '').trim();
    } else if (normalized.endsWith('实践')) {
      base = normalized.substring(0, normalized.length - 2);
    } else if (normalized.endsWith('任务')) {
      base = normalized.substring(0, normalized.length - 2);
    } else {
      base = normalized;
    }
    if (base.isEmpty) base = normalized;
    return CourseTerms(
      practiceLabel: normalized,
      taskLabel: '${base}任务',
      taskPluralLabel: '${base}任务',
      reportLabel: '$normalized报告',
      materialLabel: '$normalized材料',
      submitVerbLabel: '提交$normalized',
    );
  }
}
