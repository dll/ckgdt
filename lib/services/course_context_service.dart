import '../data/local/course_dao.dart';
import '../data/models/course_model.dart';

/// 当前课程上下文。
///
/// 平台化后，题库、图谱、实验、资料等数据都应优先绑定当前课程。
class CourseContextService {
  static const String defaultCourseId = 'ckgdt';
  static const String defaultCourseName = '课程知识图谱与数字孪生';
  static const String defaultCourseDescription =
      '面向课程知识建模、数字孪生教学、学习评价与持续改进的平台化课程';
  static const List<String> defaultCourseChapters = [
    '课程知识图谱基础',
    '课程数据建模与资源治理',
    '数字孪生教学场景设计',
    '智能学习路径与学习分析',
    '实验实践与作品评价',
    '课程持续改进与平台应用',
  ];

  final CourseDao _courseDao;

  CourseContextService({CourseDao? courseDao})
      : _courseDao = courseDao ?? CourseDao();

  static CourseModel fallbackCourse() => CourseModel(
        id: defaultCourseId,
        name: defaultCourseName,
        description: defaultCourseDescription,
        chapterCount: defaultCourseChapters.length,
        chapters: defaultCourseChapters,
        isActive: true,
        createdAt: '',
      );

  Future<CourseModel> getActiveCourse() async {
    return await _courseDao.getActiveCourse() ?? fallbackCourse();
  }

  Future<String> activeCourseId() async => (await getActiveCourse()).id;

  Future<String> activeCourseName({String fallback = defaultCourseName}) async {
    final name = (await getActiveCourse()).name.trim();
    return name.isEmpty ? fallback : name;
  }

  /// 生成课程作用域 where 片段。
  /// 所有课程使用严格匹配，scopedWhere 只返回该课程的数据。
  Future<({String where, List<Object?> args})> scopedWhere({
    String column = 'course_id',
    String? extraWhere,
    List<Object?> extraArgs = const [],
  }) async {
    final courseId = await activeCourseId();
    final parts = <String>[];
    final args = <Object?>[];

    parts.add('$column = ?');
    args.add(courseId);

    if (extraWhere != null && extraWhere.trim().isNotEmpty) {
      parts.add('($extraWhere)');
      args.addAll(extraArgs);
    }

    return (where: parts.join(' AND '), args: args);
  }

  Future<List<String>> chapterTitles({bool includeAll = false}) async {
    final course = await getActiveCourse();
    final raw = course.chapters.isNotEmpty
        ? course.chapters
        : List.generate(course.chapterCount, (i) => '第${i + 1}章');
    final chapters = <String>[
      for (var i = 0; i < raw.length; i++) formatChapterTitle(raw[i], i + 1),
    ];
    if (includeAll) return ['全部/自定义', ...chapters];
    return chapters;
  }

  Future<List<String>> shortChapterTitles({bool includeAll = false}) async {
    final course = await getActiveCourse();
    final count = course.chapters.isNotEmpty
        ? course.chapters.length
        : course.chapterCount;
    final chapters = List.generate(count, (i) => '第${i + 1}章');
    if (includeAll) return ['全部/自定义', ...chapters];
    return chapters;
  }

  Future<List<String>> chapterQueryPatterns(int chapter) async {
    final course = await getActiveCourse();
    final patterns = <String>{'第$chapter章'};
    final chinese = _toChineseNumber(chapter);
    if (chinese.isNotEmpty) patterns.add('第$chinese章');

    if (chapter > 0 && chapter <= course.chapters.length) {
      final raw = course.chapters[chapter - 1].trim();
      if (raw.isNotEmpty) {
        patterns
          ..add(raw)
          ..add(formatChapterTitle(raw, chapter));
      }
    }

    return patterns
        .where((p) => p.trim().isNotEmpty)
        .map((p) => '%$p%')
        .toList();
  }

  static String formatChapterTitle(String raw, int index) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '第$index章';
    if (RegExp(r'^第\s*[一二三四五六七八九十百\d]+\s*章').hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^\d+\s*[.、)\]]').hasMatch(trimmed)) {
      final withoutNumber =
          trimmed.replaceFirst(RegExp(r'^\d+\s*[.、)\]]\s*'), '');
      return '第$index章 $withoutNumber';
    }
    return '第$index章 $trimmed';
  }

  static String buildStableCourseId(String name) {
    final normalized = name.trim().toLowerCase();
    final ascii = normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (ascii.isNotEmpty) return ascii;

    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 'course_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  static String _toChineseNumber(int value) {
    const digits = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    if (value <= 0 || value > 99) return '';
    if (value < 10) return digits[value];
    if (value == 10) return '十';
    if (value < 20) return '十${digits[value % 10]}';
    final tens = value ~/ 10;
    final ones = value % 10;
    return '${digits[tens]}十${ones == 0 ? '' : digits[ones]}';
  }
}
