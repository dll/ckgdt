path = 'lib/services/resource_generation_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 1. Insert import after line 9 (0-based index 9)
lines.insert(9, "import 'rich_resource_generation_service.dart';\r\n")

# line numbers shift by 1
shift = 1

# 2. Replace generateForChapter signature (originally 27-32, now 28-33)
sig_start = 26 + shift
sig_end = 31 + shift
new_sig = [
    '  Future<GenerationResult> generateForChapter({\r\n',
    '    required String courseId,\r\n',
    '    required String chapterTitle,\r\n',
    '    required String chapterMdPath,\r\n',
    '    String sourceType = \'preset\',\r\n',
    '    bool rich = false,\r\n',
    '    _PlannedChapter? plannedChapter,\r\n',
    '  }) async {\r\n',
]
lines[sig_start:sig_end + 1] = new_sig

# Insert rich branch after new signature
insert_idx = sig_start + len(new_sig)
rich_branch = [
    '    if (rich && plannedChapter != null) {\r\n',
    '      return _generateRichResourcesForChapter(\r\n',
    '        courseId: courseId,\r\n',
    '        chapter: plannedChapter,\r\n',
    '        sourceType: sourceType,\r\n',
    '      );\r\n',
    '    }\r\n',
    '\r\n',
]
for i, line in enumerate(rich_branch):
    lines.insert(insert_idx + i, line)

# recompute shift: +1 (import) + (8-6) signature + 7 rich branch = +10
shift = 10

# 3. Replace generateAll signature (originally 433-436, now 443-446)
all_sig_start = 432 + shift
all_sig_end = 435 + shift
new_all_sig = [
    '  Future<List<GenerationResult>> generateAll({\r\n',
    '    required String courseId,\r\n',
    '    String sourceType = \'preset\',\r\n',
    '    bool rich = false,\r\n',
    '  }) async {\r\n',
]
lines[all_sig_start:all_sig_end + 1] = new_all_sig

# 4. Update generateForChapter call in loop (scan after generateAll signature)
for i in range(all_sig_start, min(len(lines), all_sig_start + 50)):
    if lines[i].strip() == 'final r = await generateForChapter(':
        j = i
        while j < len(lines) and lines[j].strip() != ');':
            j += 1
        new_call = [
            '        final r = await generateForChapter(\r\n',
            '          courseId: courseId,\r\n',
            '          chapterTitle: title,\r\n',
            '          chapterMdPath: chapterMdPath,\r\n',
            '          sourceType: sourceType,\r\n',
            '          rich: rich,\r\n',
            '          plannedChapter: chapter,\r\n',
            '        );\r\n',
        ]
        lines[i:j + 1] = new_call
        break

# 5. Insert _generateRichResourcesForChapter before class _PlannedChapter
for i, line in enumerate(lines):
    if line.startswith('class _PlannedChapter'):
        new_method = '''\r\n  // Rich resource generation: lesson plan -> PDF / PPTX / video\r\n\r\n  /// Generates teachable resources driven by an AI lesson plan.\r\n  Future<GenerationResult> _generateRichResourcesForChapter({\r\n    required String courseId,\r\n    required _PlannedChapter chapter,\r\n    required String sourceType,\r\n  }) async {\r\n    final result = GenerationResult(chapter: chapter.title);\r\n    final db = await DatabaseHelper.instance.database;\r\n    final courseDir = await _getCourseDir(courseId);\r\n\r\n    final rich = RichResourceGenerationService();\r\n    rich.onProgress = (fileType, progress) {\r\n      onProgress?.call(chapter.title, fileType, progress);\r\n    };\r\n\r\n    final paths = await rich.generateForChapter(\r\n      courseId: courseId,\r\n      chapterTitle: chapter.title,\r\n      chapterShortTitle: chapter.shortTitle,\r\n      description: chapter.description,\r\n      objectives: chapter.objectives,\r\n      keyPoints: chapter.keyPoints,\r\n      difficultPoints: chapter.difficultPoints,\r\n      sourceType: sourceType,\r\n      outputBaseDir: courseDir,\r\n    );\r\n\r\n    if (paths['pdf'] != null) {\r\n      result.pdfPath = paths['pdf'];\r\n      result.generated.add('pdf');\r\n      await db.insert(\r\n        'resource_files',\r\n        {\r\n          'course_id': courseId,\r\n          'file_name': paths['pdf']!.split(Platform.pathSeparator).last,\r\n          'file_path': paths['pdf']!,\r\n          'file_type': 'pdf',\r\n          'chapter': chapter.title,\r\n          'description': '[LessonPlan] ${chapter.title} PDF',\r\n          'source_type': sourceType,\r\n        },\r\n        conflictAlgorithm: ConflictAlgorithm.replace,\r\n      );\r\n    }\r\n\r\n    if (paths['ppt'] != null) {\r\n      result.pptxPath = paths['ppt'];\r\n      result.generated.add('ppt');\r\n      await db.insert(\r\n        'resource_files',\r\n        {\r\n          'course_id': courseId,\r\n          'file_name': paths['ppt']!.split(Platform.pathSeparator).last,\r\n          'file_path': paths['ppt']!,\r\n          'file_type': 'ppt',\r\n          'chapter': chapter.title,\r\n          'description': '[LessonPlan] ${chapter.title} PPTX',\r\n          'source_type': sourceType,\r\n        },\r\n        conflictAlgorithm: ConflictAlgorithm.replace,\r\n      );\r\n    }\r\n\r\n    if (paths['video'] != null) {\r\n      result.videoScriptPath = paths['video'];\r\n      result.generated.add('video');\r\n      await db.insert(\r\n        'resource_files',\r\n        {\r\n          'course_id': courseId,\r\n          'file_name': paths['video']!.split(Platform.pathSeparator).last,\r\n          'file_path': paths['video']!,\r\n          'file_type': 'video',\r\n          'chapter': chapter.title,\r\n          'description': '[LessonPlan] ${chapter.title} Video',\r\n          'source_type': sourceType,\r\n        },\r\n        conflictAlgorithm: ConflictAlgorithm.replace,\r\n      );\r\n    }\r\n\r\n    return result;\r\n  }\r\n'''
        for j, mline in enumerate(new_method.split('\r\n')):
            if j < len(new_method.split('\r\n')) - 1 or mline:
                lines.insert(i + j, mline + '\r\n')
        break

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('patched')
