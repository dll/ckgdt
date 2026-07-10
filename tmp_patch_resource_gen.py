path = 'lib/services/resource_generation_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 1. Insert imports after line 11 (0-based index 11, so insert at 12)
imports = [
    "import '../data/local/ai_config_dao.dart';\n",
    "import '../data/models/ai_config_model.dart';\n",
    "import 'courseware_service.dart';\n",
    "import 'tts_service.dart';\n",
    "import 'video_service.dart';\n",
]
for i, imp in enumerate(imports):
    lines.insert(12 + i, imp)

# line numbers shift by 5
shift = 5

# 2. Replace generateForChapter signature (originally 27-32, now 32-37)
sig_start = 26 + shift
sig_end = 31 + shift
new_sig = [
    '  Future<GenerationResult> generateForChapter({\n',
    '    required String courseId,\n',
    '    required String chapterTitle,\n',
    '    required String chapterMdPath,\n',
    '    String sourceType = \'preset\',\n',
    '    bool rich = false,\n',
    '    _PlannedChapter? plannedChapter,\n',
    '  }) async {\n',
]
lines[sig_start:sig_end + 1] = new_sig

# 3. Insert rich branch after the new signature (now ends at index 32+shift+7-1 = 43? Let me compute)
# We replaced 6 lines with 8 lines, so net +2 from shift. Total shift now = 7.
# Signature ends at index sig_start + len(new_sig) - 1 = (26+5) + 8 - 1 = 38
rich_branch = [
    '    if (rich && plannedChapter != null) {\n',
    '      return _generateRichResourcesForChapter(\n',
    '        courseId: courseId,\n',
    '        chapter: plannedChapter,\n',
    '        sourceType: sourceType,\n',
    '      );\n',
    '    }\n',
    '\n',
]
insert_idx = sig_start + len(new_sig)
for i, line in enumerate(rich_branch):
    lines.insert(insert_idx + i, line)

# Recompute total shift: original shift 5 + new_sig extra 2 + rich_branch 8 = 15
shift = 15

# 4. Replace generateAll signature (originally 433-436, now 448-451)
all_sig_start = 432 + shift
all_sig_end = 435 + shift
new_all_sig = [
    '  Future<List<GenerationResult>> generateAll({\n',
    '    required String courseId,\n',
    '    String sourceType = \'preset\',\n',
    '    bool rich = false,\n',
    '  }) async {\n',
]
lines[all_sig_start:all_sig_end + 1] = new_all_sig

# 5. Replace generateForChapter call (originally 452-457, now 467-472)
# Need to locate by scanning for the call
for i in range(all_sig_end + 1, min(len(lines), all_sig_end + 50)):
    if lines[i].strip() == 'final r = await generateForChapter(':
        # find closing ');'
        j = i
        while j < len(lines) and lines[j].strip() != ');':
            j += 1
        new_call = [
            '        final r = await generateForChapter(\n',
            '          courseId: courseId,\n',
            '          chapterTitle: title,\n',
            '          chapterMdPath: chapterMdPath,\n',
            '          sourceType: sourceType,\n',
            '          rich: rich,\n',
            '          plannedChapter: chapter,\n',
            '        );\n',
        ]
        lines[i:j + 1] = new_call
        break

# 6. Insert _generateRichResourcesForChapter before class _PlannedChapter
for i, line in enumerate(lines):
    if line.startswith('class _PlannedChapter'):
        new_method = '''\n  // ═══════════════════════════════════════════════════════════════════════════\n  // 高质量资源生成：教案 → PDF / PPTX / 视频\n  // ═══════════════════════════════════════════════════════════════════════════\n\n  /// 以教案驱动的方式生成可直接授课的高质量资源。\n  /// 输出 PDF 讲义、真实 PPTX 课件、带字幕的 MP4 教学视频，并注册到 resource_files。\n  Future<GenerationResult> _generateRichResourcesForChapter({\n    required String courseId,\n    required _PlannedChapter chapter,\n    required String sourceType,\n  }) async {\n    final result = GenerationResult(chapter: chapter.title);\n    final db = await DatabaseHelper.instance.database;\n\n    // 1. 课程名称\n    final courseRows = await db.query(\n      'courses',\n      columns: ['name'],\n      where: 'id = ?',\n      whereArgs: [courseId],\n    );\n    final courseName = courseRows.isNotEmpty\n        ? (courseRows.first['name']?.toString() ?? '')\n        : '';\n\n    // 2. AI 教案\n    onProgress?.call(chapter.title, 'plan', 0.0);\n    final courseware = CoursewareService();\n    final aiConfig = await AiConfigDao().getConfig();\n    final additional = StringBuffer();\n    additional.writeln('课程：\$courseName');\n    additional.writeln('章节描述：\${chapter.description}');\n    if (chapter.objectives.isNotEmpty) {\n      additional.writeln('教学目标：\${chapter.objectives.join('、')}');\n    }\n    if (chapter.keyPoints.isNotEmpty) {\n      additional.writeln('教学重点：\${chapter.keyPoints.join('、')}');\n    }\n    if (chapter.difficultPoints.isNotEmpty) {\n      additional.writeln('教学难点：\${chapter.difficultPoints.join('、')}');\n    }\n    additional.writeln('请生成内容详实、可直接授课的教案，包含完整教学环节、示例、实践任务和评价方式。');\n\n    final lessonPlan = await courseware.generateLessonPlan(\n      topic: chapter.shortTitle,\n      chapter: chapter.title,\n      classHours: 2,\n      additionalRequirements: additional.toString(),\n      configOverride: aiConfig,\n    );\n    onProgress?.call(chapter.title, 'plan', 1.0);\n\n    // 3. 增强版 PDF\n    onProgress?.call(chapter.title, 'pdf', 0.0);\n    try {\n      final courseDir = await _getCourseDir(courseId);\n      final pdfDir = '\$courseDir\${Platform.pathSeparator}PDF';\n      final pdfPath = await courseware.generateEnhancedPdf(\n        lessonPlan: lessonPlan,\n        outputDir: pdfDir,\n      );\n      if (pdfPath != null && pdfPath.isNotEmpty) {\n        result.pdfPath = pdfPath;\n        result.generated.add('pdf');\n        await db.insert(\n          'resource_files',\n          {\n            'course_id': courseId,\n            'file_name': pdfPath.split(Platform.pathSeparator).last,\n            'file_path': pdfPath,\n            'file_type': 'pdf',\n            'chapter': chapter.title,\n            'description': '[教案驱动] \${chapter.title} PDF讲义',\n            'source_type': sourceType,\n          },\n          conflictAlgorithm: ConflictAlgorithm.replace,\n        );\n      }\n    } catch (e, st) {\n      swallowDebug(e, tag: 'ResourceGen.richPdf', stack: st);\n      result.errors.add('PDF: \$e');\n    }\n    onProgress?.call(chapter.title, 'pdf', 1.0);\n\n    // 4. 真实 PPTX\n    onProgress?.call(chapter.title, 'ppt', 0.0);\n    try {\n      final hasPptx = await courseware.isPythonPptxInstalled();\n      if (hasPptx) {\n        final slides = courseware.lessonPlanToSlides(lessonPlan);\n        if (slides.isNotEmpty) {\n          final courseDir = await _getCourseDir(courseId);\n          final pptxDir = '\$courseDir\${Platform.pathSeparator}课件';\n          final pptxPath = await courseware.generatePptx(\n            title: chapter.shortTitle,\n            slides: slides,\n            chapter: chapter.title,\n            outputDir: pptxDir,\n          );\n          if (pptxPath != null && pptxPath.isNotEmpty) {\n            result.pptxPath = pptxPath;\n            result.generated.add('ppt');\n            await db.insert(\n              'resource_files',\n              {\n                'course_id': courseId,\n                'file_name': pptxPath.split(Platform.pathSeparator).last,\n                'file_path': pptxPath,\n                'file_type': 'ppt',\n                'chapter': chapter.title,\n                'description': '[教案驱动] \${chapter.title} PPT课件',\n                'source_type': sourceType,\n              },\n              conflictAlgorithm: ConflictAlgorithm.replace,\n            );\n          }\n        }\n      }\n    } catch (e, st) {\n      swallowDebug(e, tag: 'ResourceGen.richPptx', stack: st);\n      result.errors.add('PPTX: \$e');\n    }\n    onProgress?.call(chapter.title, 'ppt', 1.0);\n\n    // 5. 教学视频：旁白脚本 → TTS → 幻灯片图片 → 视频合成\n    onProgress?.call(chapter.title, 'video', 0.0);\n    try {\n      final hasTts = await TtsService().isEdgeTtsInstalled();\n      final hasFfmpeg = await VideoService().isFfmpegInstalled();\n      if (hasTts && hasFfmpeg) {\n        final scripts = await courseware.generateNarrationScripts(\n          lessonPlan,\n          configOverride: aiConfig,\n        );\n        if (scripts.isNotEmpty) {\n          final sessionDir = await courseware.createSessionDir();\n          final audioDir = '\$sessionDir/audio';\n          final audioPaths = await TtsService().generateBatchAudio(\n            scripts: scripts,\n            outputDir: audioDir,\n          );\n\n          final slidesDir = '\$sessionDir/slides';\n          final slideImages = await courseware.generateSlideImages(\n            title: chapter.shortTitle,\n            slides: courseware.lessonPlanToSlides(lessonPlan),\n            outputDir: slidesDir,\n            chapter: chapter.title,\n          );\n\n          if (slideImages.isNotEmpty) {\n            final courseDir = await _getCourseDir(courseId);\n            final videoDir = '\$courseDir\${Platform.pathSeparator}视频';\n            Directory(videoDir).createSync(recursive: true);\n            final timestamp = DateTime.now().millisecondsSinceEpoch;\n            final safeTitle = chapter.shortTitle\n                .replaceAll(RegExp(r'[/\\\\:*?"<>|]'), '_');\n            final rawPath =\n                '\$videoDir\${Platform.pathSeparator}\${safeTitle}_raw_\$timestamp.mp4';\n            final finalPath =\n                '\$videoDir\${Platform.pathSeparator}\${safeTitle}_\$timestamp.mp4';\n\n            final success = await VideoService().generateVideo(\n              slides: slideImages,\n              audios: audioPaths,\n              outputPath: rawPath,\n              clipDirPath: '\$sessionDir/video_clips',\n            );\n\n            if (success && File(rawPath).existsSync()) {\n              final narrations =\n                  scripts.map((s) => s['narration'] ?? '').toList();\n              final srtPath =\n                  '\$videoDir\${Platform.pathSeparator}\${safeTitle}_\$timestamp.srt';\n              final srtResult = await VideoService().generateSrt(\n                narrations: narrations,\n                audioPaths: audioPaths,\n                outputPath: srtPath,\n              );\n\n              String videoPath = rawPath;\n              if (srtResult != null) {\n                final burned = await VideoService().burnSubtitles(\n                  videoPath: rawPath,\n                  srtPath: srtPath,\n                  outputPath: finalPath,\n                );\n                if (burned != null) {\n                  try {\n                    File(rawPath).deleteSync();\n                  } catch (_) {}\n                  videoPath = finalPath;\n                } else {\n                  try {\n                    File(rawPath).renameSync(finalPath);\n                  } catch (_) {\n                    videoPath = rawPath;\n                  }\n                }\n              } else {\n                try {\n                  File(rawPath).renameSync(finalPath);\n                } catch (_) {\n                  videoPath = rawPath;\n                }\n              }\n\n              result.videoScriptPath = videoPath;\n              result.generated.add('video');\n              await db.insert(\n                'resource_files',\n                {\n                  'course_id': courseId,\n                  'file_name': videoPath.split(Platform.pathSeparator).last,\n                  'file_path': videoPath,\n                  'file_type': 'video',\n                  'chapter': chapter.title,\n                  'description': '[教案驱动] \${chapter.title} 教学视频',\n                  'source_type': sourceType,\n                },\n                conflictAlgorithm: ConflictAlgorithm.replace,\n              );\n            }\n          }\n        }\n      }\n    } catch (e, st) {\n      swallowDebug(e, tag: 'ResourceGen.richVideo', stack: st);\n      result.errors.add('视频: \$e');\n    }\n    onProgress?.call(chapter.title, 'video', 1.0);\n\n    return result;\n  }\n'''
        for j, mline in enumerate(new_method.split('\n')):
            lines.insert(i + j, mline + '\n')
        break

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('resource_generation_service.dart patched')
