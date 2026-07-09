import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/error_handler.dart';
import 'gitee_service.dart';
import 'course_generation_service.dart';
import 'course_template_registry.dart';

/// 课程资源持久化服务
/// 将生成的资源保存到本地文件系统，并上传到 Gitee 仓库
class ResourcePersistenceService {
  static final ResourcePersistenceService instance =
      ResourcePersistenceService._();
  ResourcePersistenceService._();

  final GiteeService _gitee = GiteeService();

  /// 获取课程资源目录
  Future<String> getCourseDir(String courseId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final courseDir = Directory('${appDir.path}/courses/$courseId');
    if (!await courseDir.exists()) {
      await courseDir.create(recursive: true);
    }
    return courseDir.path;
  }

  /// 保存生成结果到本地文件系统
  Future<String> saveLocally(CourseGenerationResult result) async {
    final courseDir = await getCourseDir(result.courseId);
    final courseTemplate = _templateMetadata(result);

    // 1. 保存配置目录
    final configDir = Directory('$courseDir/配置');
    if (!await configDir.exists()) await configDir.create(recursive: true);

    // manifest.json
    await _writeJson('$courseDir/配置/manifest.json', {
      'schema_version': '2.0.0',
      'package_version': '1.0.0',
      'course_id': result.courseId,
      'course_name': result.courseName,
      'last_updated': DateTime.now().toIso8601String().split('T').first,
      'min_app_version': '2.1.0',
      'description': '${result.courseName}课程资源包',
      'generation_mode': result.isLazyPackage ? 'lazy' : 'full',
      'template_version': courseTemplate['version'],
      'template': courseTemplate,
      'resources': {
        'chapters': {'file': 'chapters.json', 'version': '1.0.0'},
        'config': {'file': 'config.json', 'version': '1.0.0'},
        'assessment': {'file': 'assessment.json', 'version': '1.0.0'},
        'lab_tasks': {'file': 'lab_tasks.json', 'version': '1.0.0'},
        'homework': {'file': 'homework.json', 'version': '1.0.0'},
        'quiz_config': {'file': 'quiz_config.json', 'version': '1.0.0'},
        'achievement_calc': {
          'file': 'achievement_calc.json',
          'version': '1.0.0'
        },
        'report_templates': {
          'file': 'report_templates.json',
          'version': '1.0.0'
        },
        'archive_templates': {
          'file': 'archive_templates.json',
          'version': '1.0.0'
        },
        'graph_categories': {
          'file': 'graph_categories.json',
          'version': '1.0.0'
        },
        'course_profile': {'file': 'course_profile.json', 'version': '1.0.0'},
        'platform_readiness': {
          'file': 'platform_readiness.json',
          'version': '1.0.0'
        },
        'course_template': {
          'file': 'course_template.json',
          'version': courseTemplate['version'] ?? '1.0.0'
        },
        'lazy_generation': {'file': 'lazy_generation.json', 'version': '1.0.0'},
      },
    });

    // config.json
    await _writeJson('$courseDir/配置/config.json', result.config);

    // chapters.json
    await _writeJson('$courseDir/配置/chapters.json', result.chapters);

    // assessment.json
    await _writeJson('$courseDir/配置/assessment.json', result.assessmentConfig);

    // achievement_calc.json
    await _writeJson(
        '$courseDir/配置/achievement_calc.json', result.achievementConfig);

    // report_templates.json
    await _writeJson(
        '$courseDir/配置/report_templates.json', result.reportTemplates);
    await _writeJson(
      '$courseDir/配置/archive_templates.json',
      _archiveTemplatePlan(result),
    );

    // quiz_config.json
    await _writeJson('$courseDir/配置/quiz_config.json', {
      'questions_per_chapter': 10,
      'total_questions': result.quizzes.length,
    });

    // lab_tasks.json
    await _writeJson('$courseDir/配置/lab_tasks.json', result.labTasks);

    // homework.json
    await _writeJson('$courseDir/配置/homework.json', result.homeworks);

    await _writeJson(
        '$courseDir/配置/course_profile.json',
        result.courseProfile.isEmpty
            ? _fallbackCourseProfile()
            : result.courseProfile);
    await _writeJson(
      '$courseDir/配置/platform_readiness.json',
      _platformReadinessPayload(result),
    );
    await _writeJson('$courseDir/配置/course_template.json', courseTemplate);
    await _writeJson(
      '$courseDir/配置/lazy_generation.json',
      _lazyGenerationManifest(result),
    );

    // 2. 保存测验题目
    final theoryDir = Directory('$courseDir/理论');
    if (!await theoryDir.exists()) await theoryDir.create(recursive: true);
    if (result.isLazyPackage) {
      await _writeText(
        '${theoryDir.path}/README.md',
        '# ${result.courseName}理论资源\n\n本目录已建立。章节测验、讲义和拓展材料将在首次进入对应章节或点击生成时实时生成。\n',
      );
    } else {
      await _saveQuizzesAsMd(theoryDir.path, result);
    }

    // 3. 保存视频脚本
    final videoDir = Directory('$courseDir/视频');
    if (!await videoDir.exists()) await videoDir.create(recursive: true);
    for (var i = 0; i < result.videoScripts.length; i++) {
      final script = result.videoScripts[i];
      final chapterNum = script['chapter_number'] ?? i + 1;
      final title = script['title'] ?? '第$chapterNum章';
      if (result.isLazyPackage && script['lazy_generation'] == true) {
        await _writeJson(
          '${videoDir.path}/${_cnChapter(chapterNum)}$title-视频脚本.lazy.json',
          _lazyResourceStub(result, 'video_script', chapterNum, title),
        );
        continue;
      }
      await _writeJson(
          '${videoDir.path}/${_cnChapter(chapterNum)}$title-视频脚本.json', script);
    }

    // 4. 保存课件
    final coursewareDir = Directory('$courseDir/课件');
    if (!await coursewareDir.exists()) {
      await coursewareDir.create(recursive: true);
    }
    for (var i = 0; i < result.courseware.length; i++) {
      final cw = result.courseware[i];
      final chapterNum = cw['chapter_number'] ?? i + 1;
      final title = cw['title'] ?? '第$chapterNum章';
      if (result.isLazyPackage && cw['lazy_generation'] == true) {
        await _writeJson(
          '${coursewareDir.path}/${_cnChapter(chapterNum)}$title-课件.lazy.json',
          _lazyResourceStub(result, 'courseware', chapterNum, title),
        );
        continue;
      }
      await _writeJson(
          '${coursewareDir.path}/${_cnChapter(chapterNum)}$title-课件.json', cw);
    }

    // 5. 保存图谱定义
    final graphDir = Directory('$courseDir/图谱');
    if (!await graphDir.exists()) await graphDir.create(recursive: true);
    for (final graph in result.graphs) {
      final cat = graph['category'] ?? '未分类';
      await _writeJson('${graphDir.path}/$cat图谱.json', graph);
    }

    await _saveRequiredPackageFiles(courseDir, result);
    await _writePackageInventory(courseDir, result);

    debugPrint('=== ResourcePersistenceService: Saved to $courseDir');
    return courseDir;
  }

  /// 上传到 Gitee 仓库（假设仓库已存在）
  Future<bool> uploadToGitee(CourseGenerationResult result) async {
    try {
      final repoName = 'courses-${result.courseId}';
      const owner = 'chzcldl';

      // 上传配置文件
      final configFiles = [
        'manifest.json',
        'config.json',
        'chapters.json',
        'assessment.json',
        'achievement_calc.json',
        'report_templates.json',
        'archive_templates.json',
        'quiz_config.json',
        'lab_tasks.json',
        'homework.json',
        'course_profile.json',
        'platform_readiness.json',
        'course_template.json',
        'lazy_generation.json',
      ];

      for (final file in configFiles) {
        final content = jsonEncode(_uploadConfigPayload(file, result));
        await _gitee.createOrUpdateFile(
          owner: owner,
          repo: repoName,
          path: '配置/$file',
          content: content,
          message: 'feat: 添加课程配置 $file',
        );
      }

      // 上传测验题目
      for (var i = 0; i < result.chapters.length; i++) {
        final chapter = result.chapters[i];
        final chapterNum = chapter['number'] ?? i + 1;
        final title = chapter['title'] ?? '第$chapterNum章';
        final chapterQuizzes = result.quizzes
            .where((q) => q['chapter_number'] == chapterNum)
            .toList();
        final content = _quizzesToMd(chapterNum, title, chapterQuizzes);
        await _gitee.createOrUpdateFile(
          owner: owner,
          repo: repoName,
          path: '理论/${_cnChapter(chapterNum)}$title-测验.md',
          content: content,
          message: 'feat: 添加测验题目 $title',
        );
      }

      // 上传视频脚本
      for (var i = 0; i < result.videoScripts.length; i++) {
        final script = result.videoScripts[i];
        final chapterNum = script['chapter_number'] ?? i + 1;
        final title = script['title'] ?? '第$chapterNum章';
        await _gitee.createOrUpdateFile(
          owner: owner,
          repo: repoName,
          path: '视频/${_cnChapter(chapterNum)}$title-视频脚本.json',
          content: jsonEncode(script),
          message: 'feat: 添加视频脚本 $title',
        );
      }

      // 上传图谱定义。图谱是平台化课程的运行核心，远程包不能只保留资源清单。
      for (final graph in result.graphs) {
        final category = graph['category']?.toString().trim().isNotEmpty == true
            ? graph['category'].toString().trim()
            : '课程图谱';
        await _gitee.createOrUpdateFile(
          owner: owner,
          repo: repoName,
          path: '图谱/$category图谱.json',
          content: jsonEncode(graph),
          message: 'feat: 添加课程图谱 $category',
        );
      }

      debugPrint(
          '=== ResourcePersistenceService: Uploaded to $owner/$repoName');
      return true;
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ResourcePersistenceService.uploadToGitee', stack: st);
      return false;
    }
  }

  /// 从 Gitee 拉取课程资源
  Future<CourseGenerationResult?> pullFromGitee(String courseId) async {
    try {
      const owner = 'chzcldl';
      final repoName = 'courses-$courseId';

      // 读取 manifest
      final manifestJson =
          await _gitee.getFileContent(owner, repoName, '配置/manifest.json');
      if (manifestJson == null) return null;
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      // 读取各配置文件
      final config =
          await _readGiteeJson(owner, repoName, '配置/config.json', null);
      final chapters =
          await _readGiteeJsonList(owner, repoName, '配置/chapters.json', null);
      final assessment =
          await _readGiteeJson(owner, repoName, '配置/assessment.json', null);
      final achievement = await _readGiteeJson(
          owner, repoName, '配置/achievement_calc.json', null);
      final reportTemplates = await _readGiteeJsonList(
          owner, repoName, '配置/report_templates.json', null);
      final labTasks =
          await _readGiteeJsonList(owner, repoName, '配置/lab_tasks.json', null);
      final homeworks =
          await _readGiteeJsonList(owner, repoName, '配置/homework.json', null);
      final courseProfile =
          await _readGiteeJson(owner, repoName, '配置/course_profile.json', null);
      final platformReadiness = await _readGiteeJson(
          owner, repoName, '配置/platform_readiness.json', null);
      final courseTemplate = await _readGiteeJson(
          owner, repoName, '配置/course_template.json', null);

      // 读取测验题目
      final quizzes = <Map<String, dynamic>>[];
      // 读取视频脚本
      final videoScripts = <Map<String, dynamic>>[];
      // 读取课件
      final courseware = <Map<String, dynamic>>[];
      final graphs = await _readGiteeGraphs(owner, repoName);
      final resolvedCourseName = manifest['course_name']?.toString() ??
          config?['course_name']?.toString() ??
          courseId;
      final resolvedTemplate = courseTemplate ??
          (manifest['template'] is Map
              ? Map<String, dynamic>.from(manifest['template'] as Map)
              : _templateMetadata(
                  CourseGenerationResult(
                    courseId: courseId,
                    courseName: resolvedCourseName,
                  )..courseProfile = courseProfile ?? {},
                ));

      return CourseGenerationResult(
        courseId: courseId,
        courseName: resolvedCourseName,
      )
        ..config = {
          ...manifest,
          if (config != null) 'course_config': config,
        }
        ..chapters = chapters ?? []
        ..assessmentConfig = assessment ?? {}
        ..achievementConfig = achievement ?? {}
        ..reportTemplates = reportTemplates ?? []
        ..labTasks = labTasks ?? []
        ..homeworks = homeworks ?? []
        ..courseProfile = courseProfile ?? {}
        ..courseTemplate = resolvedTemplate
        ..platformReadiness = platformReadiness ?? {}
        ..quizzes = quizzes
        ..videoScripts = videoScripts
        ..courseware = courseware
        ..graphs = graphs;
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ResourcePersistenceService.pullFromGitee', stack: st);
      return null;
    }
  }

  // ── 辅助方法 ──────────────────────────────────────────────────────────────

  String _cnChapter(int num) {
    const cnNums = [
      '一',
      '二',
      '三',
      '四',
      '五',
      '六',
      '七',
      '八',
      '九',
      '十',
      '十一',
      '十二'
    ];
    return num <= cnNums.length ? '第${cnNums[num - 1]}章' : '第$num章';
  }

  Future<void> _writeJson(String path, dynamic data) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );
  }

  Future<void> _writeText(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, encoding: utf8);
  }

  String _quizzesToMd(
      int chapterNum, String title, List<Map<String, dynamic>> quizzes) {
    final buffer = StringBuffer();
    buffer.writeln('# ${_cnChapter(chapterNum)}$title 测验题');
    buffer.writeln();
    for (var i = 0; i < quizzes.length; i++) {
      final q = quizzes[i];
      buffer.writeln('### 第${i + 1}题');
      buffer.writeln();
      buffer.writeln('**题目**：${q['question'] ?? ''}');
      buffer.writeln();
      buffer.writeln('A. ${q['option_a'] ?? ''}');
      buffer.writeln('B. ${q['option_b'] ?? ''}');
      buffer.writeln('C. ${q['option_c'] ?? ''}');
      buffer.writeln('D. ${q['option_d'] ?? ''}');
      buffer.writeln();
      final answerIdx = q['answer_index'] ?? 0;
      buffer.writeln('**正确答案**：${'ABCD'[answerIdx as int]}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  Future<void> _saveQuizzesAsMd(
      String dirPath, CourseGenerationResult result) async {
    // 按章节分组
    final byChapter = <int, List<Map<String, dynamic>>>{};
    for (final q in result.quizzes) {
      final ch = q['chapter_number'] ?? 1;
      byChapter.putIfAbsent(ch, () => []).add(q);
    }

    for (final entry in byChapter.entries) {
      final chapterNum = entry.key;
      final quizzes = entry.value;
      final title = result.chapters
              .where((c) => c['number'] == chapterNum)
              .map((c) => c['title'] as String? ?? '')
              .firstOrNull ??
          '第$chapterNum章';
      final md = _quizzesToMd(chapterNum, title, quizzes);
      await File('$dirPath/${_cnChapter(chapterNum)}$title-测验.md')
          .writeAsString(md, encoding: utf8);
    }
  }

  Future<void> _saveRequiredPackageFiles(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    await _writeJson('$courseDir/配置/course_gen_input.json', {
      'version': '1.0.0',
      'description': '一键生课输入配置',
      'course_info': result.config,
      'input_sources': {
        'chapters_config': {'file': '配置/chapters.json', 'format': 'json'},
        'assessment_config': {'file': '配置/assessment.json', 'format': 'json'},
        'lab_tasks_config': {'file': '配置/lab_tasks.json', 'format': 'json'},
        'homework_config': {'file': '配置/homework.json', 'format': 'json'},
        'course_profile': {'file': '配置/course_profile.json', 'format': 'json'},
        'platform_readiness': {
          'file': '配置/platform_readiness.json',
          'format': 'json'
        },
        'archive_templates': {
          'file': '配置/archive_templates.json',
          'format': 'json'
        },
        'course_template': {
          'file': '配置/course_template.json',
          'format': 'json'
        },
        'quiz_config': {'file': '配置/quiz_config.json', 'format': 'json'},
        'achievement_config': {
          'file': '配置/achievement_calc.json',
          'format': 'json'
        },
        'lazy_generation': {
          'file': '配置/lazy_generation.json',
          'format': 'json'
        },
      },
      'output_targets': {
        'database_tables': [
          'courses',
          'questions',
          'lab_tasks',
          'homeworks',
          'homework_items',
          'resource_files',
          'graphs',
          'nodes',
          'edges',
        ],
      },
    });
    await _writeJson('$courseDir/配置/graph_categories.json', {
      'categories': result.graphs.map((g) => g['category']).toList(),
    });

    if (result.isLazyPackage) {
      await _writeText(
        '$courseDir/理论/章节资源懒生成说明.md',
        '# 章节资源懒生成说明\n\n本课程采用快速建课模式。理论讲义、测验题、课件和视频脚本已登记在 `配置/lazy_generation.json`，首次使用时根据大纲、章节和当前课程上下文实时生成。\n',
      );
    } else {
      await _saveTheoryOutlines(courseDir, result);
    }
    await _saveSyllabusAndSchedule(courseDir, result);
    await _saveLabMaterials(courseDir, result);
    await _saveHomeworkMaterials(courseDir, result);
    await _saveAssessmentMaterials(courseDir, result);
    await _saveAchievementMaterials(courseDir, result);
    await _saveArchiveMaterials(courseDir, result);
    await _saveDemoMaterials(courseDir, result);
  }

  Map<String, dynamic> _lazyGenerationManifest(CourseGenerationResult result) {
    final chapters = result.chapters.asMap().entries.map((entry) {
      final index = entry.key;
      final chapter = entry.value;
      final number = chapter['number'] ?? index + 1;
      final title = chapter['title']?.toString() ?? '第$number章';
      return {
        'chapter_number': number,
        'chapter_title': title,
        'resources': [
          {
            'type': 'lecture_notes',
            'target': '理论/第$number章 $title.md',
            'status': result.isLazyPackage ? 'pending' : 'generated',
          },
          {
            'type': 'quiz',
            'target': '理论/${_cnChapter(number)}$title-测验.md',
            'status': result.isLazyPackage ? 'pending' : 'generated',
          },
          {
            'type': 'courseware',
            'target': '课件/${_cnChapter(number)}$title-课件.json',
            'status': result.isLazyPackage ? 'pending' : 'generated',
          },
          {
            'type': 'video_script',
            'target': '视频/${_cnChapter(number)}$title-视频脚本.json',
            'status': result.isLazyPackage ? 'pending' : 'generated',
          },
        ],
      };
    }).toList();
    return {
      'course_id': result.courseId,
      'course_name': result.courseName,
      'mode': result.isLazyPackage ? 'lazy' : 'full',
      'created_at': DateTime.now().toIso8601String(),
      'template': {
        'id': _templateMetadata(result)['id'],
        'version': _templateMetadata(result)['version'],
        'profile': _templateMetadata(result)['profile'],
      },
      'policy': result.isLazyPackage
          ? '一键生课只生成资源包目录、配置、清单和可编辑骨架；重资源首次使用时实时生成。'
          : '资源已完整生成。',
      'chapters': chapters,
    };
  }

  Map<String, dynamic> _lazyResourceStub(
    CourseGenerationResult result,
    String type,
    Object chapterNum,
    String title,
  ) =>
      {
        'course_id': result.courseId,
        'course_name': result.courseName,
        'chapter_number': chapterNum,
        'chapter_title': title,
        'resource_type': type,
        'lazy_generation': true,
        'status': 'pending',
        'description': '该资源将在首次使用时根据课程大纲和章节信息实时生成。',
      };

  Future<void> _saveTheoryOutlines(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    for (var i = 0; i < result.chapters.length; i++) {
      final chapter = result.chapters[i];
      final number = chapter['number'] ?? i + 1;
      final title = chapter['title'] ?? '第$number章';
      final buffer = StringBuffer()
        ..writeln('# 第$number章 $title')
        ..writeln()
        ..writeln('## 教学目标');
      for (final objective in (chapter['objectives'] as List? ?? const [])) {
        buffer.writeln('- $objective');
      }
      buffer
        ..writeln()
        ..writeln('## 重点内容');
      for (final item in (chapter['key_points'] as List? ?? const [])) {
        buffer.writeln('- $item');
      }
      buffer
        ..writeln()
        ..writeln('## 难点内容');
      for (final item in (chapter['difficult_points'] as List? ?? const [])) {
        buffer.writeln('- $item');
      }
      await _writeText('$courseDir/理论/第$number章 $title.md', buffer.toString());
    }
  }

  Future<void> _saveSyllabusAndSchedule(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    final syllabus = StringBuffer()
      ..writeln('# ${result.courseName}教学大纲')
      ..writeln()
      ..writeln('## 课程简介')
      ..writeln(result.config['description'] ?? '${result.courseName}课程')
      ..writeln()
      ..writeln('## 课程目标');
    final objectives = (result.config['objectives'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    if (objectives.isEmpty) {
      syllabus.writeln('- 能够理解${result.courseName}的核心知识结构。');
      syllabus.writeln('- 能够完成课程相关实践、训练或作品任务。');
      syllabus.writeln('- 能够基于评价反馈进行反思改进。');
    } else {
      for (final objective in objectives) {
        final id = objective['id']?.toString() ?? '';
        final name = objective['name']?.toString() ?? '课程目标$id';
        final description = objective['description']?.toString() ?? name;
        syllabus.writeln('- 课程目标$id：$description');
      }
    }
    syllabus
      ..writeln()
      ..writeln('## 章节安排');
    for (var i = 0; i < result.chapters.length; i++) {
      syllabus.writeln('- 第${i + 1}章 ${result.chapters[i]['title'] ?? ''}');
    }
    syllabus
      ..writeln()
      ..writeln('## 考核方式');
    final assessmentGroups =
        (result.assessmentConfig['groups'] as List? ?? const [])
            .whereType<Map>()
            .toList();
    if (assessmentGroups.isEmpty) {
      syllabus.writeln('平时成绩占30%，实践或作业成绩占30%，期末或综合考核成绩占40%。');
    } else {
      final parts = assessmentGroups.map((group) {
        final name = group['name']?.toString() ?? '评价项目';
        final weight = ((group['weight'] as num?)?.toDouble() ?? 0) * 100;
        return '$name占${weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1)}%';
      }).toList();
      syllabus.writeln('${parts.join('，')}。');
    }
    await _writeText(
      '$courseDir/大纲/${result.courseName}-教学大纲.md',
      syllabus.toString(),
    );

    final schedule = StringBuffer()
      ..writeln('# ${result.courseName}教学进度')
      ..writeln()
      ..writeln('| 周次 | 内容 | 类型 | 备注 |')
      ..writeln('|------|------|------|------|');
    for (var i = 0; i < result.chapters.length; i++) {
      schedule.writeln(
        '| ${i + 1} | 第${i + 1}章 ${result.chapters[i]['title'] ?? ''} | 理论+实践 | 自动生成 |',
      );
    }
    await _writeText(
      '$courseDir/进度/${result.courseName}-教学进度.md',
      schedule.toString(),
    );
  }

  Future<void> _saveLabMaterials(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    for (var i = 0; i < result.labTasks.length; i++) {
      final lab = result.labTasks[i];
      final title = lab['title'] ?? '实践任务${i + 1}';
      await _writeText(
        '$courseDir/实验/实验教程/$title教程.md',
        _labTutorialMd(title, lab),
      );
      await _writeText(
        '$courseDir/实验/报告模板/$title报告模板.md',
        _labReportMd(title, lab),
      );
    }
    await _writeText(
      '$courseDir/实验/实验指导/README.md',
      '# ${result.courseName}实践指导\n\n本目录存放课程实践、实验、研讨、训练、创作、案例分析等活动的组织规范、提交要求、评价量规和常见问题。\n',
    );
    await _writeText(
      '$courseDir/实验/平台技术栈/README.md',
      '# 数智课程工具链参考\n\n围绕${result.courseName}的课程图谱、学习分析、数字孪生、AI辅助教学、达成评价和归档工具链。文科课程可用于文本分析与主题图谱，体育课程可用于训练记录与技能画像，艺术课程可用于作品集与评审，理工课程可用于实验和项目管理。\n',
    );
  }

  String _labTutorialMd(String title, Map<String, dynamic> lab) {
    final activityType = lab['activity_type']?.toString();
    final buffer = StringBuffer()
      ..writeln('# $title 教程')
      ..writeln()
      ..writeln('## 活动类型')
      ..writeln(activityType?.isNotEmpty == true ? activityType : '实践任务')
      ..writeln()
      ..writeln('## 任务目的')
      ..writeln(lab['description'] ?? '')
      ..writeln()
      ..writeln('## 任务要求');
    for (final item in (lab['requirements'] as List? ?? const [])) {
      buffer.writeln('- $item');
    }
    buffer.writeln('\n## 交付物');
    for (final item in (lab['deliverables'] as List? ?? const [])) {
      buffer.writeln('- $item');
    }
    final rubric = lab['assessment_rubric'] as List? ?? const [];
    if (rubric.isNotEmpty) {
      buffer.writeln('\n## 评价量规');
      for (final item in rubric) {
        buffer.writeln('- $item');
      }
    }
    return buffer.toString();
  }

  String _labReportMd(String title, Map<String, dynamic> lab) {
    return '# $title 报告模板\n\n'
        '## 基本信息\n\n- 姓名：\n- 学号：\n- 班级：\n\n'
        '## 任务目标\n\n${lab['description'] ?? ''}\n\n'
        '## 完成过程\n\n\n## 成果证据\n\n可填写文本分析、课堂讨论记录、训练数据、动作视频截图、作品图片、实验结果或项目运行截图。\n\n'
        '## 反思与改进\n';
  }

  Future<void> _saveHomeworkMaterials(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    for (var i = 0; i < result.homeworks.length; i++) {
      final homework = result.homeworks[i];
      final chapterNumber = homework['chapter_number'] ?? i + 1;
      final chapterTitle = homework['chapter_title']?.toString() ??
          homework['chapter']?.toString() ??
          '第$chapterNumber章';
      await _writeText(
        '$courseDir/作业/第$chapterNumber章 $chapterTitle-作业.md',
        _homeworkMd(result.courseName, homework),
      );
    }
  }

  String _homeworkMd(String courseName, Map<String, dynamic> homework) {
    final chapter = homework['chapter'] ?? '';
    final chapterTitle = homework['chapter_title'] ?? '';
    final buffer = StringBuffer()
      ..writeln('# $chapter $chapterTitle 作业')
      ..writeln()
      ..writeln('## 作业信息')
      ..writeln()
      ..writeln('- 课程：$courseName')
      ..writeln('- 章节：$chapter $chapterTitle')
      ..writeln('- 对应目标：${homework['course_objective'] ?? ''}')
      ..writeln()
      ..writeln(homework['description'] ?? '')
      ..writeln()
      ..writeln('## 作业题目');
    final items = homework['items'] as List? ?? const [];
    for (var i = 0; i < items.length; i++) {
      final item = Map<String, dynamic>.from(items[i] as Map);
      buffer
        ..writeln()
        ..writeln('### ${i + 1}. ${item['type'] ?? '作业题'}')
        ..writeln()
        ..writeln('- 分值：${item['max_score'] ?? 100}')
        ..writeln('- 题目：${item['question'] ?? ''}')
        ..writeln()
        ..writeln('#### 参考要点')
        ..writeln()
        ..writeln(item['reference_answer'] ?? '');
    }
    return buffer.toString();
  }

  Future<void> _saveAssessmentMaterials(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    await _writeText(
      '$courseDir/考核/${result.courseName}考核方案.md',
      '# ${result.courseName}考核方案\n\n```json\n${const JsonEncoder.withIndent('  ').convert(result.assessmentConfig)}\n```\n',
    );
    await _writeText(
      '$courseDir/考核/试卷分析模板.md',
      '# 试卷分析模板\n\n## 试卷结构\n\n## 分数统计\n\n## 课程目标达成分析\n\n## 改进措施\n',
    );
  }

  Future<void> _saveAchievementMaterials(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    await _writeText(
      '$courseDir/达成/${result.courseName}达成评价方案.md',
      '# ${result.courseName}达成评价方案\n\n```json\n${const JsonEncoder.withIndent('  ').convert(result.achievementConfig)}\n```\n',
    );
    await _writeText(
      '$courseDir/达成/达成报告模板.md',
      '# 达成报告模板\n\n## 课程目标\n\n## 评价依据\n\n## 达成结果\n\n## 持续改进\n',
    );
  }

  Future<void> _saveArchiveMaterials(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    final plan = _archiveTemplatePlan(result);
    final stages = (plan['stages'] as List).cast<Map<String, dynamic>>();
    for (final stage in stages) {
      final label = stage['label']?.toString() ?? '归档';
      final docs = (stage['documents'] as List).cast<Map<String, dynamic>>();
      await _writeText(
        '$courseDir/归档/$label/模板/README.md',
        _archiveStageReadme(result, stage),
      );
      for (final doc in docs) {
        final key = doc['key']?.toString() ?? 'document';
        final docLabel = doc['label']?.toString() ?? key;
        await _writeText(
          '$courseDir/归档/$label/模板/$key-$docLabel.md',
          _archiveTemplateMd(result, stage, doc),
        );
      }
    }
  }

  Map<String, dynamic> _archiveTemplatePlan(CourseGenerationResult result) {
    final template = _templateMetadata(result);
    final profile = result.courseProfile.isEmpty
        ? _fallbackCourseProfile()
        : result.courseProfile;
    return {
      'version': '1.0.0',
      'course_id': result.courseId,
      'course_name': result.courseName,
      'template': {
        'id': template['id'],
        'version': template['version'],
        'profile': template['profile'],
      },
      'course_profile': {
        'discipline': profile['discipline'],
        'course_mode': profile['course_mode'],
        'practice_label': profile['practice_label'],
      },
      'workflow': ['模板', '样例', '填写', '审核', '编辑', '预览', '打印', '归档'],
      'stages': [
        _archiveStage(
          key: 'beginning',
          label: '期初',
          documents: const [
            ['teaching_task', '教学任务单'],
            ['syllabus', '教学大纲'],
            ['syllabus_evaluation', '大纲合理性评价表'],
            ['syllabus_review', '大纲合理性审核表'],
            ['calendar', '教学日历'],
            ['course_schedule', '课程课表'],
            ['teaching_schedule', '教学进度表'],
            ['lesson_plan', '教学教案'],
            ['courseware', '教学课件'],
            ['roll_call', '学生点名册'],
            ['teacher_guide', '教师教学指导手册'],
            ['student_guide', '学生学习指导手册'],
            ['assessment_plan', '综合考核方案'],
            ['survey', '问卷'],
          ],
        ),
        _archiveStage(
          key: 'midterm',
          label: '期中',
          documents: const [
            ['midterm_progress_check', '课程进度执行检查'],
            ['midterm_homework_review', '作业与批阅次数统计'],
            ['midterm_exam', '期中考试或阶段考核材料'],
          ],
        ),
        _archiveStage(
          key: 'final',
          label: '期末',
          documents: const [
            ['final_archive_catalog', '课程档案袋目录'],
            ['final_syllabus', '教学大纲'],
            ['final_syllabus_evaluation', '大纲合理性评价表'],
            ['final_teaching_schedule', '教学进度表'],
            ['final_lesson_plan', '教学教案'],
            ['final_syllabus_review', '大纲合理性审核表'],
            ['final_assessment_review', '课程期末考核命题审核表'],
            ['final_grade_book', '记分册'],
            ['final_score_register', '成绩登记表'],
            ['final_assessment_description', '课程考核说明'],
            ['final_achievement_report', '课程达成评价材料'],
            ['final_textbook_guide', '教材与实践指导书'],
            ['final_sample_works', '课程考核成果样本'],
          ],
        ),
        _archiveStage(
          key: 'archive',
          label: '结课',
          documents: const [
            ['archive_form', '归档确认表'],
            ['print_report', '印刷审批表'],
          ],
        ),
      ],
    };
  }

  Map<String, dynamic> _archiveStage({
    required String key,
    required String label,
    required List<List<String>> documents,
  }) =>
      {
        'key': key,
        'label': label,
        'documents': [
          for (final doc in documents)
            {
              'key': doc[0],
              'label': doc[1],
              'required': true,
              'source': 'course_context',
              'actions': [
                'generate',
                'review',
                'edit',
                'preview',
                'print',
                'archive'
              ],
            }
        ],
      };

  String _archiveStageReadme(
    CourseGenerationResult result,
    Map<String, dynamic> stage,
  ) {
    final label = stage['label']?.toString() ?? '归档';
    final docs = (stage['documents'] as List).cast<Map<String, dynamic>>();
    final buffer = StringBuffer()
      ..writeln('# $label 归档模板')
      ..writeln()
      ..writeln('- 课程：${result.courseName}')
      ..writeln('- 清单版本：1.0.0')
      ..writeln('- 流程：模板 -> 样例 -> 填写 -> 审核 -> 编辑 -> 预览 -> 打印 -> 归档')
      ..writeln()
      ..writeln('## 材料清单')
      ..writeln()
      ..writeln('| 编号 | 类型 | 材料 | 模板文件 |')
      ..writeln('| --- | --- | --- | --- |');
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final key = doc['key']?.toString() ?? '';
      final docLabel = doc['label']?.toString() ?? key;
      buffer.writeln('| ${i + 1} | `$key` | $docLabel | `$key-$docLabel.md` |');
    }
    return buffer.toString();
  }

  String _archiveTemplateMd(
    CourseGenerationResult result,
    Map<String, dynamic> stage,
    Map<String, dynamic> doc,
  ) {
    final stageLabel = stage['label']?.toString() ?? '归档';
    final docLabel = doc['label']?.toString() ?? '归档材料';
    final docKey = doc['key']?.toString() ?? 'document';
    return '''# $docLabel

## 基本信息

- 课程：${result.courseName}
- 阶段：$stageLabel
- 文档类型：$docKey
- 大纲版本：
- 班级：
- 学期：
- 教师：

## 填写要点

- 依据当前课程大纲、教学进度、课程目标、教学活动和评价数据填写。
- 不得保留其他课程、旧班级、旧学期、旧教师姓名或旧学生名单。
- 如学校原始 Word/Excel/PDF 模板存在，应保留原格式归档；本 Markdown 用于编辑、审核和生成说明。

## 审核要点

- 课程、班级、学期、教师与当前课程上下文一致。
- 内容覆盖本阶段应归档材料，关键数据可追溯到课程资源、达成批次或教学记录。
- 通过审核后再打印和归档。

## 正文

待根据当前课程生成或填写。
''';
  }

  Future<void> _saveDemoMaterials(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    await _writeText(
      '$courseDir/用户/README.md',
      '# 用户与班级样例\n\n可在课程包导入时生成教师、学生、班级和分组样例。\n',
    );
    await _writeText(
      '$courseDir/项目/README.md',
      '# 项目与作品样例\n\n记录课程综合项目、作品展示和案例演示信息。\n',
    );
    await _writeText(
      '$courseDir/文档/智能体目录.md',
      '# 智能体目录\n\n围绕${result.courseName}生成课程辅导、实验批阅、达成分析和归档助手上下文。\n',
    );
    await _writeText(
      '$courseDir/文档/数智课程特色设计.md',
      _smartCourseFeatureMd(result),
    );
    await _writeText(
      '$courseDir/文档/知识图谱与数字孪生闭环.md',
      _graphTwinLoopMd(result),
    );
    await _writeText(
      '$courseDir/文档/智慧课程审核清单.md',
      _smartCourseChecklistMd(result),
    );
    await _writeText(
      '$courseDir/文档/平台化检测报告.md',
      _platformReadinessMd(result),
    );
    await _writeText(
      '$courseDir/推荐/学习路径模板.md',
      '# 学习路径模板\n\n基于课程图谱、测验结果和数字孪生画像生成个性化学习路径。\n',
    );
  }

  String _smartCourseFeatureMd(CourseGenerationResult result) {
    return '''# ${result.courseName} 数智课程特色设计

## 课程定位

本课程按智慧课程标准组织资源，以知识图谱、数字孪生、AI 智能体、学习分析和达成评价构成数智课程能力底座。

## 核心特色

| 特色 | 建设内容 | 平台体现 |
| --- | --- | --- |
| 知识图谱组织课程 | 章节、知识点、资源、目标、评价建立关联 | 图谱、学习路径、资源推荐 |
| 数字孪生刻画师生 | 学生学习画像与教师教学画像 | 数字孪生、学习分析、AI 解读 |
| 智能体服务全过程 | 答疑、导学、实验、评价、归档辅助 | 智慧问答、技能工具、智能体 |
| 数据驱动达成评价 | 测验、作业、实验、项目、试卷分析支撑达成 | 达成模块、归档材料 |
| 一键生课平台化 | 生成资源包、清单和可编辑模板 | 课程资源包清单 |

## 建设要求

- 每章至少有理论资源、测验、作业和学习建议。
- 每个实验有教程、报告模板和评分要求。
- 每个课程目标能追踪到评价数据。
- 每门课程能形成可审核、可打印、可归档材料。
''';
  }

  String _platformReadinessMd(CourseGenerationResult result) {
    final readiness = _platformReadinessPayload(result);
    final profile = result.courseProfile.isEmpty
        ? _fallbackCourseProfile()
        : result.courseProfile;
    final contract =
        readiness['resource_contract'] as Map<String, dynamic>? ?? const {};
    final requiredConfigs =
        (contract['required_config_files'] as List? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList();
    final archiveStages =
        (contract['archive_stages'] as List? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList();
    final lazyResources =
        (contract['lazy_resource_types'] as List? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList();
    final issues = (readiness['issues'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final buffer = StringBuffer()
      ..writeln('# ${result.courseName} 平台化检测报告')
      ..writeln()
      ..writeln('- 检测结论：${readiness['passed'] == true ? '通过' : '需完善'}')
      ..writeln('- 平台化得分：${readiness['score'] ?? 0}')
      ..writeln('- 学科类型：${profile['discipline'] ?? '通用'}')
      ..writeln('- 课程形态：${profile['course_mode'] ?? '理论实践型'}')
      ..writeln('- 实践标签：${profile['practice_label'] ?? '实践任务'}')
      ..writeln()
      ..writeln('## 子图谱要求')
      ..writeln()
      ..writeln('| 类型 | 内容 |')
      ..writeln('| --- | --- |')
      ..writeln(
          '| 子图谱 | ${(profile['graph_categories'] as List? ?? const []).join('、')} |')
      ..writeln(
          '| 证据类型 | ${(profile['evidence_types'] as List? ?? const []).join('、')} |')
      ..writeln(
          '| 评价维度 | ${(profile['rubric_dimensions'] as List? ?? const []).join('、')} |')
      ..writeln()
      ..writeln('## 资源包运行契约')
      ..writeln()
      ..writeln('| 检查项 | 要求 |')
      ..writeln('| --- | --- |')
      ..writeln('| 必备配置 | ${requiredConfigs.join('、')} |')
      ..writeln('| 归档阶段 | ${archiveStages.join('、')} |')
      ..writeln(
          '| 懒生成资源 | ${lazyResources.isEmpty ? '无' : lazyResources.join('、')} |')
      ..writeln(
          '| 模板版本 | ${contract['template_id'] ?? ''}@${contract['template_version'] ?? ''} / ${contract['profile_template_id'] ?? ''}@${contract['profile_template_version'] ?? ''} |')
      ..writeln()
      ..writeln('## 问题清单');
    if (issues.isEmpty) {
      buffer.writeln('\n无阻断问题。');
    } else {
      for (final issue in issues) {
        buffer.writeln('- $issue');
      }
    }
    return buffer.toString();
  }

  Map<String, dynamic> _fallbackCourseProfile() => {
        'discipline': '通用',
        'course_mode': '理论实践型',
        'practice_label': '实践任务',
        'graph_categories': ['课程图谱', '实践活动图谱', '学习资源图谱', '评价达成图谱'],
        'evidence_types': ['作业', '实践报告', '测验', '作品', '课堂表现'],
        'rubric_dimensions': ['知识理解', '实践应用', '问题分析', '表达呈现', '持续改进'],
      };

  Map<String, dynamic> _fallbackPlatformReadiness() => {
        'passed': true,
        'score': 100,
        'issues': <String>[],
      };

  Map<String, dynamic> _platformReadinessPayload(
    CourseGenerationResult result,
  ) {
    final base = result.platformReadiness.isEmpty
        ? _fallbackPlatformReadiness()
        : Map<String, dynamic>.from(result.platformReadiness);
    final template = _templateMetadata(result);
    final profile = result.courseProfile.isEmpty
        ? _fallbackCourseProfile()
        : result.courseProfile;
    final archivePlan = _archiveTemplatePlan(result);
    final archiveStages = (archivePlan['stages'] as List? ?? const [])
        .whereType<Map>()
        .map((stage) => stage['label']?.toString() ?? '')
        .where((label) => label.isNotEmpty)
        .toList();
    const requiredConfigs = [
      'manifest.json',
      'config.json',
      'chapters.json',
      'course_profile.json',
      'course_template.json',
      'platform_readiness.json',
      'lazy_generation.json',
      'achievement_calc.json',
      'assessment.json',
      'homework.json',
      'lab_tasks.json',
      'archive_templates.json',
    ];

    return {
      ...base,
      'checked_at': DateTime.now().toIso8601String(),
      'resource_contract': {
        'course_id': result.courseId,
        'course_name': result.courseName,
        'generation_mode': result.isLazyPackage ? 'lazy' : 'full',
        'template_id': template['id'],
        'template_version': template['version'],
        'template_profile': template['profile'],
        'profile_template_id': template['profile_template_id'],
        'profile_template_name': template['profile_template_name'],
        'profile_template_version': template['profile_template_version'],
        'discipline': profile['discipline'],
        'course_mode': profile['course_mode'],
        'practice_label': profile['practice_label'],
        'required_config_files': requiredConfigs,
        'required_modules': template['modules'] ?? const [],
        'required_resource_groups': template['required_resources'] ?? const {},
        'archive_stages': archiveStages,
        'archive_workflow': archivePlan['workflow'] ?? const [],
        'lazy_generation': result.isLazyPackage,
        'lazy_resource_types': result.isLazyPackage
            ? const ['theory_outline', 'quiz', 'courseware', 'video_script']
            : const <String>[],
        'achievement_required': true,
        'assessment_required': true,
        'inventory_required': true,
        'manual_review_required': true,
      },
    };
  }

  String _graphTwinLoopMd(CourseGenerationResult result) {
    final chapterLines = result.chapters.asMap().entries.map((entry) {
      final number = entry.key + 1;
      final title = entry.value['title']?.toString() ?? '第$number章';
      return '| 第$number章 $title | 知识节点 | 掌握度/风险 | 推荐资源/任务 |';
    }).join('\n');
    return '''# ${result.courseName} 知识图谱与数字孪生闭环

## 闭环模型

```text
课程目标 -> 知识节点 -> 资源与活动 -> 学习行为数据 -> 师生数字孪生
  -> 风险诊断与学习推荐 -> 教学干预 -> 达成评价 -> 图谱与资源持续改进
```

## 人体隐喻

| 图谱元素 | 数字孪生隐喻 | 教学含义 |
| --- | --- | --- |
| 核心节点 | 器官 | 关键知识或核心能力 |
| 前置关系 | 血管/神经 | 学习依赖和认知通路 |
| 节点掌握度 | 健康指标 | 学生掌握情况 |
| 薄弱节点 | 风险部位 | 需要补救的知识点 |
| 学习路径 | 训练方案 | 个性化学习建议 |
| 教学干预 | 调节方案 | 教师讲解、反馈、资源推送 |

## 章节映射

| 章节 | 图谱对象 | 孪生指标 | 干预动作 |
| --- | --- | --- | --- |
$chapterLines
''';
  }

  String _smartCourseChecklistMd(CourseGenerationResult result) {
    final profile = result.courseProfile.isEmpty
        ? _fallbackCourseProfile()
        : result.courseProfile;
    final practiceLabel = profile['practice_label'] ?? '实践任务';
    return '''# ${result.courseName} 智慧课程审核清单

## 资源完整度

| 检查项 | 要求 | 状态 |
| --- | --- | --- |
| 教学大纲 | 明确课程目标、章节、评价方式 | 待审核 |
| 教学进度 | 与章节、实验、作业、考核对应 | 待审核 |
| 理论资源 | 每章有教案、测验、作业 | 待审核 |
| $practiceLabel | 有任务说明、报告/证据模板、评分要求 | 待审核 |
| 归档资源 | 期初、期中、期末、结课材料齐全 | 待审核 |

## 知识图谱与数字孪生

| 检查项 | 要求 | 状态 |
| --- | --- | --- |
| 课程图谱 | 覆盖课程目标、章节和核心知识点 | 待审核 |
| 关系类型 | 包含前置、包含、相关、支撑等关系 | 待审核 |
| 学生画像 | 体现掌握度、活跃度、任务完成度 | 待审核 |
| 教师画像 | 体现教学覆盖、反馈、班级健康度 | 待审核 |
| AI 解读 | 给出可执行建议 | 待审核 |

## 评价闭环

| 检查项 | 要求 | 状态 |
| --- | --- | --- |
| 测验 | 支撑章节知识检测 | 待审核 |
| 作业 | 支撑基础、实践、思考能力评价 | 待审核 |
| $practiceLabel | 支撑课程实践能力或表现性成果评价 | 待审核 |
| 试卷分析 | 能分析课程目标达成 | 待审核 |
| 达成报告 | 能形成持续改进建议 | 待审核 |
''';
  }

  Future<void> _writePackageInventory(
    String courseDir,
    CourseGenerationResult result,
  ) async {
    final root = Directory(courseDir);
    final files = <String>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path
          .replaceFirst(courseDir, '')
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      if (relative == '课程资源包清单.md' || relative == '课程资源包清单.json') {
        continue;
      }
      files.add(relative);
    }
    files.sort();
    final courseTemplate = _templateMetadata(result);
    final practiceLabel = courseTemplate['practice_label'] ?? '实践任务';
    final readiness = _platformReadinessPayload(result);

    final inventory = {
      'course_id': result.courseId,
      'course_name': result.courseName,
      'generated_at': DateTime.now().toIso8601String(),
      'generation_mode': result.isLazyPackage ? 'lazy' : 'full',
      'template': courseTemplate,
      'summary': {
        'chapters': result.chapters.length,
        'quizzes': result.quizzes.length,
        'video_scripts': result.videoScripts.length,
        'courseware': result.courseware.length,
        'graphs': result.graphs.length,
        'practice_tasks': result.labTasks.length,
        'homeworks': result.homeworks.length,
        'platform_ready': readiness['passed'] ?? true,
        'report_templates': result.reportTemplates.length,
        'files': files.length,
        'lazy_pending_resources':
            result.isLazyPackage ? result.chapters.length * 4 : 0,
      },
      'lazy_generation': _lazyGenerationManifest(result),
      'platform_readiness': readiness,
      'files': files,
    };
    await _writeJson('$courseDir/课程资源包清单.json', inventory);

    final grouped = <String, List<String>>{};
    for (final file in files) {
      final top = file.contains('/') ? file.split('/').first : '根目录';
      grouped.putIfAbsent(top, () => []).add(file);
    }

    final md = StringBuffer()
      ..writeln('# ${result.courseName}课程资源包清单')
      ..writeln()
      ..writeln('- 课程ID：${result.courseId}')
      ..writeln(
          '- 课程模板：${courseTemplate['name']} ${courseTemplate['version']} (${courseTemplate['profile']})')
      ..writeln('- 生成模式：${result.isLazyPackage ? '快速建课 / 懒生成' : '完整生成'}')
      ..writeln('- 生成时间：${DateTime.now().toIso8601String()}')
      ..writeln('- 章节数：${result.chapters.length}')
      ..writeln('- 测验题：${result.quizzes.length}')
      ..writeln('- 视频脚本：${result.videoScripts.length}')
      ..writeln('- 课件：${result.courseware.length}')
      ..writeln('- 图谱：${result.graphs.length}')
      ..writeln('- $practiceLabel：${result.labTasks.length}')
      ..writeln('- 作业：${result.homeworks.length}')
      ..writeln('- 报告模板：${result.reportTemplates.length}')
      ..writeln(
          '- 待懒生成资源：${result.isLazyPackage ? result.chapters.length * 4 : 0}')
      ..writeln('- 文件总数：${files.length}')
      ..writeln()
      ..writeln('## 模板与版本')
      ..writeln()
      ..writeln('| 项目 | 内容 |')
      ..writeln('| --- | --- |')
      ..writeln('| 模板ID | ${courseTemplate['id']} |')
      ..writeln('| 模板版本 | ${courseTemplate['version']} |')
      ..writeln('| 模板画像 | ${courseTemplate['profile']} |')
      ..writeln('| 画像模板ID | ${courseTemplate['profile_template_id'] ?? ''} |')
      ..writeln('| 画像模板名称 | ${courseTemplate['profile_template_name'] ?? ''} |')
      ..writeln(
          '| 画像模板版本 | ${courseTemplate['profile_template_version'] ?? ''} |')
      ..writeln('| 学科类型 | ${courseTemplate['discipline']} |')
      ..writeln('| 课程形态 | ${courseTemplate['course_mode']} |')
      ..writeln()
      ..writeln('## 懒生成策略')
      ..writeln()
      ..writeln(result.isLazyPackage
          ? '本资源包已先生成目录、配置、图谱、作业和实践骨架；理论讲义、测验、课件和视频脚本将在首次使用时实时生成。'
          : '本资源包已完整生成。')
      ..writeln()
      ..writeln('## 资源明细');
    for (final entry in grouped.entries) {
      md
        ..writeln()
        ..writeln('### ${entry.key}');
      for (final file in entry.value) {
        md.writeln('- `$file`');
      }
    }
    await _writeText('$courseDir/课程资源包清单.md', md.toString());
  }

  String _configKey(String fileName) {
    const map = {
      'manifest.json': 'config',
      'config.json': 'config',
      'chapters.json': 'chapters',
      'assessment.json': 'assessmentConfig',
      'achievement_calc.json': 'achievementConfig',
      'report_templates.json': 'reportTemplates',
      'archive_templates.json': 'archive_templates',
      'quiz_config.json': 'quizzes',
      'lab_tasks.json': 'labTasks',
      'homework.json': 'homeworks',
      'course_profile.json': 'courseProfile',
      'platform_readiness.json': 'platformReadiness',
      'course_template.json': 'courseTemplate',
      'lazy_generation.json': 'lazy_generation',
    };
    return map[fileName] ?? 'config';
  }

  dynamic _uploadConfigPayload(String fileName, CourseGenerationResult result) {
    if (fileName == 'manifest.json') {
      final template = _templateMetadata(result);
      return {
        'schema_version': '2.0.0',
        'package_version': '1.0.0',
        'course_id': result.courseId,
        'course_name': result.courseName,
        'generation_mode': result.isLazyPackage ? 'lazy' : 'full',
        'template_version': template['version'],
        'template': template,
      };
    }
    if (fileName == 'course_template.json') {
      return _templateMetadata(result);
    }
    if (fileName == 'lazy_generation.json') {
      return _lazyGenerationManifest(result);
    }
    if (fileName == 'archive_templates.json') {
      return _archiveTemplatePlan(result);
    }
    if (fileName == 'platform_readiness.json') {
      return _platformReadinessPayload(result);
    }
    return result.toMap()[_configKey(fileName)] ?? {};
  }

  Map<String, dynamic> _templateMetadata(CourseGenerationResult result) {
    if (result.courseTemplate.isNotEmpty) return result.courseTemplate;
    return CourseTemplateRegistry.resolve(
      courseProfile: result.courseProfile.isEmpty
          ? _fallbackCourseProfile()
          : result.courseProfile,
    ).toMap();
  }

  Future<Map<String, dynamic>?> _readGiteeJson(
      String owner, String repo, String path, String? token) async {
    final content = await _gitee.getFileContent(owner, repo, path);
    if (content == null) return null;
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e, st) {
      swallowDebug(e, tag: 'ResourcePersistence', stack: st);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> _readGiteeJsonList(
      String owner, String repo, String path, String? token) async {
    final content = await _gitee.getFileContent(owner, repo, path);
    if (content == null) return null;
    try {
      final list = jsonDecode(content) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e, st) {
      swallowDebug(e, tag: 'ResourcePersistence', stack: st);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _readGiteeGraphs(
    String owner,
    String repo,
  ) async {
    try {
      final entries = await _gitee.listDir(owner, repo, '图谱');
      final graphs = <Map<String, dynamic>>[];
      for (final entry in entries) {
        if (entry['type']?.toString() != 'file') continue;
        final path = entry['path']?.toString() ?? '';
        if (!path.toLowerCase().endsWith('.json')) continue;
        final graph = await _readGiteeJson(owner, repo, path, null);
        if (graph != null && graph.isNotEmpty) graphs.add(graph);
      }
      return graphs;
    } catch (e, st) {
      swallowDebug(e, tag: 'ResourcePersistence.readGiteeGraphs', stack: st);
      return const [];
    }
  }
}
