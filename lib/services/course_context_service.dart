import '../data/local/course_dao.dart';
import '../data/models/course_model.dart';

/// 当前课程上下文。
///
/// 平台化后，题库、图谱、实验、资料等数据都应优先绑定当前课程。
/// 旧种子库默认课程 ID 为 `mad`，用于兼容历史的《移动应用开发》数据。
class CourseContextService {
  static const defaultCourseId = 'mad';
  static const defaultCourseName = '移动应用开发';

  final CourseDao _courseDao;

  CourseContextService({CourseDao? courseDao})
      : _courseDao = courseDao ?? CourseDao();

  static CourseModel fallbackCourse() => CourseModel(
        id: defaultCourseId,
        name: defaultCourseName,
        description: '默认课程',
        chapterCount: 6,
        chapters: const [
          '移动应用开发技术体系全景',
          'Android 与 iOS 原生开发基础',
          'Flutter、React Native 等混合开发技术',
          '微信小程序开发流程',
          '华为 HarmonyOS 多端应用开发',
          '综合开发实践',
        ],
        isActive: true,
        createdAt: '',
      );

  Future<CourseModel> getActiveCourse() async {
    return await _courseDao.getActiveCourse() ?? fallbackCourse();
  }

  Future<String> activeCourseId() async => (await getActiveCourse()).id;

  Future<String> activeCourseName({String fallback = '课程'}) async {
    final name = (await getActiveCourse()).name.trim();
    return name.isEmpty ? fallback : name;
  }

  /// 生成课程作用域 where 片段。
  ///
  /// 默认课程保留空 course_id 兼容；其它课程必须显式匹配，避免串课。
  Future<({String where, List<Object?> args})> scopedWhere({
    String column = 'course_id',
    String? extraWhere,
    List<Object?> extraArgs = const [],
  }) async {
    final courseId = await activeCourseId();
    final parts = <String>[];
    final args = <Object?>[];

    if (courseId == defaultCourseId) {
      parts.add("($column = ? OR $column IS NULL OR $column = '')");
    } else {
      parts.add('$column = ?');
    }
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

  static bool isDefaultMobileCourseName(String name) {
    return name.trim().isEmpty || name.contains(defaultCourseName);
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
