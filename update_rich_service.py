path = 'lib/services/rich_resource_generation_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Normalize line endings
text = text.replace('\r\n', '\n')

# 1. Add optional courseName and aiConfig parameters
old_sig = '''    String sourceType = 'preset',
    String outputBaseDir = '',
  }) async {'''
new_sig = '''    String sourceType = 'preset',
    String outputBaseDir = '',
    String? courseName,
    AiConfigModel? aiConfig,
  }) async {'''
text = text.replace(old_sig, new_sig)

# 2. Make DB query conditional on courseName
old_lookup = '''    // 1. 课程名称
    final db = await DatabaseHelper.instance.database;
    final courseRows = await db.query(
      'courses',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [courseId],
    );
    final courseName = courseRows.isNotEmpty
        ? (courseRows.first['name']?.toString() ?? '')
        : '';

    // 2. 生成教案
    onProgress?.call('plan', 0.0);
    final aiConfig = await AiConfigDao().getConfig();'''
new_lookup = '''    // 1. 课程名称
    final effectiveCourseName = courseName ?? await _lookupCourseName(courseId);

    // 2. 生成教案
    onProgress?.call('plan', 0.0);
    final effectiveAiConfig = aiConfig ?? await AiConfigDao().getConfig();'''
text = text.replace(old_lookup, new_lookup)

# 3. Update usages of courseName and aiConfig in generateLessonPlan
old_call = '''    final lessonPlan = await _courseware.generateLessonPlan(
      topic: chapterShortTitle,
      chapter: chapterTitle,
      classHours: 2,
      additionalRequirements: additional.toString(),
      configOverride: aiConfig,
    );'''
new_call = '''    final lessonPlan = await _courseware.generateLessonPlan(
      topic: chapterShortTitle,
      chapter: chapterTitle,
      classHours: 2,
      additionalRequirements: additional.toString(),
      configOverride: effectiveAiConfig,
    );'''
text = text.replace(old_call, new_call)

old_scripts = '''        final scripts = await _courseware.generateNarrationScripts(
          lessonPlan,
          configOverride: aiConfig,
        );'''
new_scripts = '''        final scripts = await _courseware.generateNarrationScripts(
          lessonPlan,
          configOverride: effectiveAiConfig,
        );'''
text = text.replace(old_scripts, new_scripts)

# 4. Update additional.writeln('课程：$courseName')
text = text.replace("additional.writeln('课程：$courseName');", "additional.writeln('课程：$effectiveCourseName');")

# 5. Add _lookupCourseName helper before generateForChapter
old_method_start = '''  /// 为单个章节生成高质量资源
  /// 返回 { 'pdf': path, 'ppt': path, 'video': path }
  Future<Map<String, String>> generateForChapter({'''
new_method_start = '''  /// 从数据库查询课程名称
  Future<String> _lookupCourseName(String courseId) async {
    final db = await DatabaseHelper.instance.database;
    final courseRows = await db.query(
      'courses',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [courseId],
    );
    return courseRows.isNotEmpty
        ? (courseRows.first['name']?.toString() ?? '')
        : '';
  }

  /// 为单个章节生成高质量资源
  /// 返回 { 'pdf': path, 'ppt': path, 'video': path }
  Future<Map<String, String>> generateForChapter({'''
text = text.replace(old_method_start, new_method_start)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
print('rich_resource_generation_service updated')
