import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/error_handler.dart';
import 'gitee_service.dart';
import 'course_generation_service.dart';

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
      'resources': {
        'chapters': {'file': 'chapters.json', 'version': '1.0.0'},
        'config': {'file': 'config.json', 'version': '1.0.0'},
        'assessment': {'file': 'assessment.json', 'version': '1.0.0'},
        'lab_tasks': {'file': 'lab_tasks.json', 'version': '1.0.0'},
        'quiz_config': {'file': 'quiz_config.json', 'version': '1.0.0'},
        'achievement_calc': {
          'file': 'achievement_calc.json',
          'version': '1.0.0'
        },
        'report_templates': {
          'file': 'report_templates.json',
          'version': '1.0.0'
        },
        'graph_categories': {
          'file': 'graph_categories.json',
          'version': '1.0.0'
        },
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

    // quiz_config.json
    await _writeJson('$courseDir/配置/quiz_config.json', {
      'questions_per_chapter': 10,
      'total_questions': result.quizzes.length,
    });

    // lab_tasks.json
    await _writeJson('$courseDir/配置/lab_tasks.json', result.labTasks);

    // 2. 保存测验题目
    final theoryDir = Directory('$courseDir/理论');
    if (!await theoryDir.exists()) await theoryDir.create(recursive: true);
    await _saveQuizzesAsMd(theoryDir.path, result);

    // 3. 保存视频脚本
    final videoDir = Directory('$courseDir/视频');
    if (!await videoDir.exists()) await videoDir.create(recursive: true);
    for (var i = 0; i < result.videoScripts.length; i++) {
      final script = result.videoScripts[i];
      final chapterNum = script['chapter_number'] ?? i + 1;
      final title = script['title'] ?? '第${chapterNum}章';
      await _writeJson(
          '${videoDir.path}/${_cnChapter(chapterNum)}$title-视频脚本.json', script);
    }

    // 4. 保存课件
    final coursewareDir = Directory('$courseDir/课件');
    if (!await coursewareDir.exists())
      await coursewareDir.create(recursive: true);
    for (var i = 0; i < result.courseware.length; i++) {
      final cw = result.courseware[i];
      final chapterNum = cw['chapter_number'] ?? i + 1;
      final title = cw['title'] ?? '第${chapterNum}章';
      await _writeJson(
          '${coursewareDir.path}/${_cnChapter(chapterNum)}$title-课件.json', cw);
    }

    // 5. 保存图谱定义
    final graphDir = Directory('$courseDir/图谱');
    if (!await graphDir.exists()) await graphDir.create(recursive: true);
    for (final graph in result.graphs) {
      final cat = graph['category'] ?? '未分类';
      await _writeJson('${graphDir.path}/${cat}图谱.json', graph);
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
      final owner = 'chzcldl';

      // 上传配置文件
      final configFiles = [
        'manifest.json',
        'config.json',
        'chapters.json',
        'assessment.json',
        'achievement_calc.json',
        'report_templates.json',
        'quiz_config.json',
        'lab_tasks.json'
      ];

      for (final file in configFiles) {
        final content = jsonEncode(result.toMap()[_configKey(file)] ?? {});
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
        final title = chapter['title'] ?? '第${chapterNum}章';
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
        final title = script['title'] ?? '第${chapterNum}章';
        await _gitee.createOrUpdateFile(
          owner: owner,
          repo: repoName,
          path: '视频/${_cnChapter(chapterNum)}$title-视频脚本.json',
          content: jsonEncode(script),
          message: 'feat: 添加视频脚本 $title',
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
      final owner = 'chzcldl';
      final repoName = 'courses-$courseId';

      // 读取 manifest
      final manifestJson =
          await _gitee.getFileContent(owner, repoName, '配置/manifest.json');
      if (manifestJson == null) return null;

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

      // 读取测验题目
      final quizzes = <Map<String, dynamic>>[];
      // 读取视频脚本
      final videoScripts = <Map<String, dynamic>>[];
      // 读取课件
      final courseware = <Map<String, dynamic>>[];
      // 读取图谱
      final graphs = <Map<String, dynamic>>[];

      return CourseGenerationResult(
        courseId: courseId,
        courseName: config?['course_name'] ?? courseId,
      )
        ..config = config ?? {}
        ..chapters = chapters ?? []
        ..assessmentConfig = assessment ?? {}
        ..achievementConfig = achievement ?? {}
        ..reportTemplates = reportTemplates ?? []
        ..labTasks = labTasks ?? []
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
    return num <= cnNums.length ? '第${cnNums[num - 1]}章' : '第${num}章';
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
          '第${chapterNum}章';
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
        'quiz_config': {'file': '配置/quiz_config.json', 'format': 'json'},
        'achievement_config': {
          'file': '配置/achievement_calc.json',
          'format': 'json'
        },
      },
      'output_targets': {
        'database_tables': [
          'courses',
          'questions',
          'lab_tasks',
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

    await _saveTheoryOutlines(courseDir, result);
    await _saveSyllabusAndSchedule(courseDir, result);
    await _saveLabMaterials(courseDir, result);
    await _saveAssessmentMaterials(courseDir, result);
    await _saveAchievementMaterials(courseDir, result);
    await _saveArchiveMaterials(courseDir, result);
    await _saveDemoMaterials(courseDir, result);
  }

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
      ..writeln('## 章节安排');
    for (var i = 0; i < result.chapters.length; i++) {
      syllabus.writeln('- 第${i + 1}章 ${result.chapters[i]['title'] ?? ''}');
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
      final title = lab['title'] ?? '实验${i + 1}';
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
      '# ${result.courseName}实验指导\n\n本目录存放实验组织、提交规范、评分量规和常见问题。\n',
    );
    await _writeText(
      '$courseDir/实验/平台技术栈/README.md',
      '# 平台技术栈参考\n\n围绕${result.courseName}的课程图谱、学习分析、AI辅助教学、达成评价和归档工具链。\n',
    );
  }

  String _labTutorialMd(String title, Map<String, dynamic> lab) {
    final buffer = StringBuffer()
      ..writeln('# $title 教程')
      ..writeln()
      ..writeln('## 实验目的')
      ..writeln(lab['description'] ?? '')
      ..writeln()
      ..writeln('## 实验要求');
    for (final item in (lab['requirements'] as List? ?? const [])) {
      buffer.writeln('- $item');
    }
    buffer.writeln('\n## 交付物');
    for (final item in (lab['deliverables'] as List? ?? const [])) {
      buffer.writeln('- $item');
    }
    return buffer.toString();
  }

  String _labReportMd(String title, Map<String, dynamic> lab) {
    return '# $title 报告模板\n\n'
        '## 基本信息\n\n- 姓名：\n- 学号：\n- 班级：\n\n'
        '## 实验目标\n\n${lab['description'] ?? ''}\n\n'
        '## 实验过程\n\n\n## 结果截图\n\n\n## 问题与改进\n';
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
    const stages = ['期初', '期中', '期末', '结课'];
    for (final stage in stages) {
      await _writeText(
        '$courseDir/归档/$stage/模板/README.md',
        '# $stage 归档模板\n\n课程：${result.courseName}\n\n## 材料清单\n\n- 教学大纲\n- 教学进度\n- 教学实施记录\n- 审核与改进记录\n',
      );
    }
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
      '$courseDir/推荐/学习路径模板.md',
      '# 学习路径模板\n\n基于课程图谱、测验结果和数字孪生画像生成个性化学习路径。\n',
    );
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

    final inventory = {
      'course_id': result.courseId,
      'course_name': result.courseName,
      'generated_at': DateTime.now().toIso8601String(),
      'summary': {
        'chapters': result.chapters.length,
        'quizzes': result.quizzes.length,
        'video_scripts': result.videoScripts.length,
        'courseware': result.courseware.length,
        'graphs': result.graphs.length,
        'lab_tasks': result.labTasks.length,
        'report_templates': result.reportTemplates.length,
        'files': files.length,
      },
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
      ..writeln('- 生成时间：${DateTime.now().toIso8601String()}')
      ..writeln('- 章节数：${result.chapters.length}')
      ..writeln('- 测验题：${result.quizzes.length}')
      ..writeln('- 视频脚本：${result.videoScripts.length}')
      ..writeln('- 课件：${result.courseware.length}')
      ..writeln('- 图谱：${result.graphs.length}')
      ..writeln('- 实验任务：${result.labTasks.length}')
      ..writeln('- 报告模板：${result.reportTemplates.length}')
      ..writeln('- 文件总数：${files.length}')
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
      'quiz_config.json': 'quizzes',
      'lab_tasks.json': 'labTasks',
    };
    return map[fileName] ?? 'config';
  }

  Future<Map<String, dynamic>?> _readGiteeJson(
      String owner, String repo, String path, String? token) async {
    final content = await _gitee.getFileContent(owner, repo, path);
    if (content == null) return null;
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
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
    } catch (_) {
      return null;
    }
  }
}
