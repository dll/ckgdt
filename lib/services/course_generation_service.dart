import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/error_handler.dart';
import 'ai_service.dart';
import 'course_context_service.dart';
import 'course_subgraph_service.dart';
import 'course_template_registry.dart';

/// 课程资源统一生成服务
/// 在用户输入课程名+章节后，生成完整的课程资源包（与 CKGDT 同等质量）
class CourseGenerationService {
  static final CourseGenerationService instance = CourseGenerationService._();
  CourseGenerationService._();

  final AiService _ai = AiService();
  final CourseSubgraphService _subgraphService = const CourseSubgraphService();

  /// 生成进度回调
  void Function(String step, double progress)? onProgress;

  CourseGenerationService({this.onProgress});

  static String? extractCourseNameFromSyllabus(String outline) {
    final text = outline.replaceAll('\u3000', ' ');
    final patterns = [
      RegExp(r'《([^》]{2,80})》\s*(?:课程)?教学大纲'),
      RegExp(r'课程名称\s*[:：]\s*《?([^》\r\n|,，;；]{2,80})》?'),
      RegExp(r'\|\s*课程名称\s*\|\s*《?([^》\r\n|]{2,80})》?\s*\|'),
      RegExp(r'课程名称\s+《?([^》\r\n|,，;；]{2,80})》?'),
      RegExp(r'^#\s*《?([^》\r\n#]{2,80})》?\s*(?:课程)?教学大纲', multiLine: true),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        return value
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'(课程)?教学大纲$'), '')
            .trim();
      }
    }
    return null;
  }

  static List<String> extractChaptersFromSyllabus(String outline) {
    final lines = outline
        .replaceAll('\u3000', ' ')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final byNumber = <int, String>{};

    void add(int number, String title) {
      if (number <= 0 || number > 40) return;
      final cleaned = _cleanStaticChapterTitle(title, number);
      if (cleaned.length < 2) return;
      byNumber.putIfAbsent(number, () => cleaned);
    }

    for (final line in lines) {
      final heading = RegExp(
        r'^#{1,6}\s*第\s*([一二三四五六七八九十\d]{1,3})\s*章\s+(.+)$',
      ).firstMatch(line);
      if (heading != null) {
        final number = _chapterNumber(heading.group(1)!);
        if (number != null) add(number, heading.group(2)!);
        continue;
      }

      final plain = RegExp(
        r'^\**\s*第\s*([一二三四五六七八九十\d]{1,3})\s*章\s+([^*|]+?)\s*\**$',
      ).firstMatch(line);
      if (plain != null) {
        final number = _chapterNumber(plain.group(1)!);
        if (number != null) add(number, plain.group(2)!);
        continue;
      }

      if (line.contains('|')) {
        final cells = _splitMarkdownRow(line);
        if (cells.length < 2 ||
            cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) {
          continue;
        }
        final number = int.tryParse(cells.first);
        if (number != null) {
          final titleCell = cells.skip(1).firstWhere(
                (cell) =>
                    cell.length >= 2 &&
                    !cell.contains('目标') &&
                    !RegExp(r'^\d+(\.\d+)?$').hasMatch(cell),
                orElse: () => '',
              );
          if (titleCell.isNotEmpty) add(number, titleCell);
        }
      }
    }

    final chapters = byNumber.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return chapters.map((entry) => '第${entry.key}章 ${entry.value}').toList();
  }

  static List<Map<String, dynamic>> extractPracticeTasksFromSyllabus(
    String outline,
  ) {
    final lines = outline.replaceAll('\u3000', ' ').split(RegExp(r'\r?\n'));
    final tasks = <Map<String, dynamic>>[];
    var inPracticeTable = false;
    List<String> headers = const [];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.contains('实验项目与学时分配表') || line.contains('实践项目与学时分配表')) {
        inPracticeTable = true;
        headers = const [];
        continue;
      }
      if (inPracticeTable && line.startsWith('###') && headers.isNotEmpty) {
        break;
      }
      if (!inPracticeTable || !line.contains('|')) continue;
      final cells = _splitMarkdownRow(line);
      if (cells.isEmpty ||
          cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) {
        continue;
      }
      if (headers.isEmpty) {
        if (cells.any((c) => c.contains('实验项目') || c.contains('实践项目'))) {
          headers = cells;
        }
        continue;
      }
      if (cells.length < 3) continue;

      String cell(String key) {
        final index = headers.indexWhere((h) => h.contains(key));
        if (index < 0 || index >= cells.length) return '';
        return cells[index].trim();
      }

      final sequence = int.tryParse(cell('序号')) ?? tasks.length + 1;
      final name = cell('名称').isNotEmpty ? cell('名称') : cell('项目');
      if (name.isEmpty || name.contains('实验项目名称')) continue;
      final hours = int.tryParse(cell('学时').replaceAll(RegExp(r'[^\d]'), ''));
      final objective = cell('课程目标');
      final type = cell('类型');
      final requirement = cell('要求');
      tasks.add({
        'chapter_number': sequence,
        'chapter': '实验$sequence',
        'title': name.startsWith('实验') ? name : '实验$sequence $name',
        'activity_type': type.isNotEmpty ? type : '实践任务',
        'description': '依据大纲实验项目"$name"组织实践学习、过程记录和结果验证。',
        'objectives': objective.isEmpty ? <String>[] : ['课程目标$objective'],
        'requirements': [
          if (requirement.isNotEmpty) requirement,
          '按大纲要求完成$name的关键任务',
          '保留过程证据、运行结果、数据记录或作品材料',
          '提交实践报告并完成反思改进',
        ],
        'deliverables': ['实践报告', '过程证据', '结果截图/数据/作品', '反思说明'],
        'assessment_rubric': ['目标达成', '过程规范', '成果质量', '反思改进'],
        'duration_hours': hours ?? 2,
        'difficulty': sequence == tasks.length + 1 && type.contains('综合')
            ? 'hard'
            : 'medium',
        'source': 'syllabus_practice_table',
        'lazy_generation': true,
      });
    }
    return tasks;
  }

  static Map<String, dynamic> extractAssessmentConfigFromSyllabus(
    String outline,
    String courseName,
  ) {
    final text = outline.replaceAll('\u3000', ' ');
    final groups = <Map<String, dynamic>>[];
    final componentPattern = RegExp(
      r'([^\n。；：:]{1,12}成绩|期末考查成绩|期末考试成绩|综合考核成绩)[^。\n]*?占\s*(\d+(?:\.\d+)?)\s*%',
    );
    final seen = <String>{};
    for (final match in componentPattern.allMatches(text)) {
      final rawName = match.group(1)!.trim();
      final percent = double.tryParse(match.group(2) ?? '') ?? 0;
      if (percent <= 0) continue;
      final name = rawName
          .replaceAll(RegExp(r'^最终成绩由'), '')
          .replaceAll(RegExp(r'成绩$'), '成绩')
          .trim();
      if (!seen.add(name)) continue;
      groups.add({
        'name': name,
        'weight': percent / 100,
        'items': _assessmentItemsForName(name, percent / 100),
      });
    }

    if (groups.isEmpty) {
      return _fallbackAssessmentConfig(courseName);
    }
    final total = groups.fold<double>(
      0,
      (sum, item) => sum + ((item['weight'] as num?)?.toDouble() ?? 0),
    );
    final normalized = total > 0.01
        ? groups
            .map((g) => {
                  ...g,
                  'weight': (((g['weight'] as num?)?.toDouble() ?? 0) / total),
                })
            .toList()
        : groups;
    return {
      'course_name': courseName,
      'generation_mode': 'syllabus',
      'source': 'syllabus_assessment_section',
      'groups': normalized,
    };
  }

  static List<Map<String, dynamic>> _assessmentItemsForName(
    String name,
    double groupWeight,
  ) {
    final normalized = name.replaceAll('考查', '考核');
    if (normalized.contains('平时')) {
      return [
        {'name': '作业完成', 'weight': groupWeight * 0.5},
        {'name': '课堂表现', 'weight': groupWeight * 0.2},
        {'name': '阶段测验', 'weight': groupWeight * 0.3},
      ];
    }
    if (normalized.contains('实验') || normalized.contains('实践')) {
      return [
        {'name': '任务完成情况', 'weight': groupWeight * 0.4},
        {'name': '过程规范与证据', 'weight': groupWeight * 0.3},
        {'name': '报告或成果质量', 'weight': groupWeight * 0.3},
      ];
    }
    if (normalized.contains('期末') || normalized.contains('综合')) {
      return [
        {'name': '综合成果', 'weight': groupWeight * 0.5},
        {'name': '分析论证', 'weight': groupWeight * 0.3},
        {'name': '文档规范', 'weight': groupWeight * 0.2},
      ];
    }
    return [
      {'name': name, 'weight': groupWeight},
    ];
  }

  static Map<String, dynamic> _fallbackAssessmentConfig(String courseName) => {
        'course_name': courseName,
        'generation_mode': 'lazy',
        'groups': [
          {
            'name': '过程评价',
            'weight': 0.3,
            'items': [
              {'name': '课堂参与', 'weight': 0.1},
              {'name': '学习记录', 'weight': 0.2},
            ],
          },
          {
            'name': '实践/作业评价',
            'weight': 0.3,
            'items': [
              {'name': '任务完成', 'weight': 0.2},
              {'name': '成果质量', 'weight': 0.1},
            ],
          },
          {
            'name': '综合评价',
            'weight': 0.4,
            'items': [
              {'name': '综合考核', 'weight': 0.4},
            ],
          },
        ],
      };

  /// 完整生成流程：输入课程信息 → 输出完整资源包
  Future<CourseGenerationResult> generateAll({
    required String courseName,
    required List<String> chapters,
    String? syllabusContent,
    Map<String, dynamic>? existingConfig,
    bool lazy = false,
  }) async {
    final courseId = CourseContextService.buildStableCourseId(courseName);
    final result =
        CourseGenerationResult(courseId: courseId, courseName: courseName);

    try {
      if (lazy) {
        _report('生成课程资源包骨架', 0.0);
        _generateLazyPackage(
          result: result,
          chapters: chapters,
          syllabusContent: syllabusContent,
          existingConfig: existingConfig,
        );
        _report('生成完成', 1.0);
        return result;
      }

      // 1. 基础配置
      _report('生成基础配置', 0.0);
      result.config =
          await _generateConfig(courseName, chapters, existingConfig);

      // 2. 章节配置
      _report('生成章节配置', 0.1);
      result.chapters =
          await _generateChapters(courseName, chapters, syllabusContent);

      // 3. 测验题目（每章 10 题）
      _report('生成测验题目', 0.2);
      result.quizzes =
          await _generateQuizzes(courseName, chapters, syllabusContent);

      // 4. 视频脚本（每章 1 个）
      _report('生成视频脚本', 0.4);
      result.videoScripts =
          await _generateVideoScripts(courseName, chapters, syllabusContent);

      // 5. 课件内容（每章 1 个）
      _report('生成课件内容', 0.5);
      result.courseware =
          await _generateCourseware(courseName, chapters, syllabusContent);

      // 6. 图谱定义（7 类）
      _report('生成图谱定义', 0.6);
      result.courseProfile = _subgraphService
          .inferProfile(
            courseName: courseName,
            chapters: chapters,
            syllabusContent: syllabusContent,
          )
          .toMap();
      final aiGraphs = await _generateGraphDefinitions(courseName, chapters);
      final platformSubgraphs = _subgraphService.generateSubgraphs(
        courseName: courseName,
        chapters: result.chapters,
        syllabusContent: syllabusContent,
        profile: _profileFromMap(result.courseProfile),
      );
      result.graphs = [
        ...platformSubgraphs,
        ...aiGraphs.where((graph) {
          final category = graph['category']?.toString() ?? '';
          return category.isNotEmpty &&
              !platformSubgraphs.any((g) => g['category'] == category);
        }),
      ];
      final readiness = _subgraphService.evaluateReadiness(
        subgraphs: platformSubgraphs,
        profile: _profileFromMap(result.courseProfile),
      );
      result.platformReadiness = {
        'passed': readiness.passed,
        'score': readiness.score,
        'issues': readiness.issues,
      };
      _applyCourseTemplate(result);

      // 7. 实验任务
      _report('生成实验任务', 0.7);
      final parsedLabTasks = syllabusContent == null
          ? <Map<String, dynamic>>[]
          : extractPracticeTasksFromSyllabus(syllabusContent);
      result.labTasks = parsedLabTasks.isNotEmpty
          ? parsedLabTasks
          : await _generateLabTasks(courseName, chapters, syllabusContent);

      // 8. 课后作业
      _report('生成课后作业', 0.78);
      result.homeworks = _generateHomeworks(
        courseName,
        result.chapters.isNotEmpty ? result.chapters : _quickChapters(chapters),
      );

      // 9. 报告模板
      _report('生成报告模板', 0.8);
      result.reportTemplates =
          await _generateReportTemplates(courseName, chapters);

      // 10. 达成配置
      _report('生成达成配置', 0.9);
      result.achievementConfig =
          await _generateAchievementConfig(courseName, chapters);

      // 11. 考核配置
      _report('生成考核配置', 0.95);
      final parsedAssessment = syllabusContent == null
          ? <String, dynamic>{}
          : extractAssessmentConfigFromSyllabus(syllabusContent, courseName);
      result.assessmentConfig = parsedAssessment.isNotEmpty
          ? parsedAssessment
          : await _generateAssessmentConfig(courseName, chapters);

      _report('生成完成', 1.0);
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseGenerationService.generateAll', stack: st);
      result.error = e.toString();
    }

    return result;
  }

  void _generateLazyPackage({
    required CourseGenerationResult result,
    required List<String> chapters,
    String? syllabusContent,
    Map<String, dynamic>? existingConfig,
  }) {
    final courseName = result.courseName;
    result.isLazyPackage = true;
    result.config = existingConfig ??
        _quickConfig(
          courseName: courseName,
          chapters: chapters,
          syllabusContent: syllabusContent,
        );
    result.chapters = _quickChapters(chapters);
    result.courseProfile = _subgraphService
        .inferProfile(
          courseName: courseName,
          chapters: chapters,
          syllabusContent: syllabusContent,
        )
        .toMap();
    final profile = _profileFromMap(result.courseProfile);
    final platformSubgraphs = _subgraphService.generateSubgraphs(
      courseName: courseName,
      chapters: result.chapters,
      syllabusContent: syllabusContent,
      profile: profile,
    );
    result.graphs = platformSubgraphs;
    final readiness = _subgraphService.evaluateReadiness(
      subgraphs: platformSubgraphs,
      profile: profile,
    );
    result.platformReadiness = {
      'passed': readiness.passed,
      'score': readiness.score,
      'issues': readiness.issues,
    };
    _applyCourseTemplate(result);
    final parsedLabTasks = syllabusContent == null
        ? <Map<String, dynamic>>[]
        : extractPracticeTasksFromSyllabus(syllabusContent);
    result.labTasks = parsedLabTasks.isNotEmpty
        ? _normalizePracticeTasks(parsedLabTasks, profile)
        : _quickLabTasks(courseName, result.chapters, profile);
    result.homeworks = _generateHomeworks(courseName, result.chapters);
    result.reportTemplates = _quickReportTemplates(courseName);
    result.achievementConfig =
        _quickAchievementConfig(courseName, result.config);
    result.assessmentConfig = syllabusContent == null
        ? _quickAssessmentConfig(courseName)
        : extractAssessmentConfigFromSyllabus(syllabusContent, courseName);
    result.courseware = _lazyResources(
      chapters: result.chapters,
      type: 'courseware',
      titleSuffix: '课件',
    );
    result.videoScripts = _lazyResources(
      chapters: result.chapters,
      type: 'video_script',
      titleSuffix: '视频脚本',
    );
  }

  Map<String, dynamic> _quickConfig({
    required String courseName,
    required List<String> chapters,
    String? syllabusContent,
  }) {
    final description = _firstMeaningfulLine(syllabusContent) ??
        '围绕$courseName构建课程知识图谱、学习资源、实践任务和达成评价闭环。';
    return {
      'course_name': courseName,
      'version': '1.0.0',
      'description': description.length > 80
          ? '${description.substring(0, 80)}...'
          : description,
      'total_weeks': chapters.isEmpty ? 16 : chapters.length.clamp(8, 18),
      'weekly_hours': 2,
      'credits': 2,
      'category': '课程',
      'generation_mode': 'lazy',
      'objectives': [
        {
          'id': 1,
          'name': '知识理解',
          'description': '理解课程核心概念与知识结构',
          'weight': 0.25
        },
        {
          'id': 2,
          'name': '问题分析',
          'description': '能够结合课程内容分析真实问题',
          'weight': 0.25
        },
        {
          'id': 3,
          'name': '实践应用',
          'description': '能够完成课程实践、训练或项目任务',
          'weight': 0.25
        },
        {
          'id': 4,
          'name': '反思改进',
          'description': '能够基于评价反馈持续改进学习成果',
          'weight': 0.25
        },
      ],
    };
  }

  List<Map<String, dynamic>> _quickChapters(List<String> chapters) {
    final source = chapters.isEmpty ? ['课程导论'] : chapters;
    return List.generate(source.length, (index) {
      final number = index + 1;
      final title = _cleanChapterTitle(source[index], number);
      return {
        'number': number,
        'title': title,
        'description': '$title 的核心概念、方法与应用。',
        'sub_chapters': <String>[],
        'key_points': [title],
        'difficult_points': <String>[],
        'objectives': ['理解$title', '完成$title相关学习任务'],
        'lazy_generation': true,
      };
    });
  }

  List<Map<String, dynamic>> _quickLabTasks(
    String courseName,
    List<Map<String, dynamic>> chapters,
    CourseProfile profile,
  ) {
    return List.generate(chapters.length, (index) {
      final chapter = chapters[index];
      final number = chapter['number'] ?? index + 1;
      final title = chapter['title']?.toString() ?? '第$number章';
      final activityNodes = profile.rubricDimensions.take(4).toList();
      return {
        'chapter_number': number,
        'title': '$title${profile.practiceLabel}',
        'activity_type': profile.practiceLabel,
        'description':
            '围绕《$courseName》$title完成${profile.practiceLabel}、证据采集、分析与反思。',
        'requirements': [
          '阅读或学习本章资源',
          '完成一次${profile.practiceLabel}',
          '提交过程证据和反思'
        ],
        'deliverables': profile.evidenceTypes.take(3).toList(),
        'assessment_rubric': activityNodes.isEmpty
            ? ['知识理解', '过程完整性', '成果质量', '反思改进']
            : activityNodes,
        'duration_hours': 2,
        'difficulty': 'medium',
        'lazy_generation': true,
      };
    });
  }

  List<Map<String, dynamic>> _normalizePracticeTasks(
    List<Map<String, dynamic>> tasks,
    CourseProfile profile,
  ) {
    if (profile.discipline == '工程') return tasks;
    return tasks.asMap().entries.map((entry) {
      final task = Map<String, dynamic>.from(entry.value);
      final title = task['title']?.toString() ?? '';
      final number = task['chapter_number'] ?? entry.key + 1;
      task['title'] = title
          .replaceFirst(RegExp(r'^实验\s*项目?\s*[一二三四五六七八九十\d]*[：:、.\s]*'), '')
          .replaceFirst(RegExp(r'^实验\s*[一二三四五六七八九十\d]*[：:、.\s]*'), '')
          .trim();
      if ((task['title'] as String).isEmpty) {
        task['title'] = '${profile.practiceLabel}$number';
      }
      if (!task['title'].toString().contains(profile.practiceLabel)) {
        task['title'] = '${task['title']}${profile.practiceLabel}';
      }
      task['activity_type'] = profile.practiceLabel;
      task['deliverables'] = (task['deliverables'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if ((task['deliverables'] as List).isEmpty) {
        task['deliverables'] = profile.evidenceTypes.take(3).toList();
      }
      task['assessment_rubric'] =
          (task['assessment_rubric'] as List? ?? const [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
      if ((task['assessment_rubric'] as List).isEmpty) {
        task['assessment_rubric'] = profile.rubricDimensions.take(4).toList();
      }
      return task;
    }).toList();
  }

  List<Map<String, dynamic>> _quickReportTemplates(String courseName) => [
        {
          'name': '$courseName实践报告模板',
          'type': 'practice_report',
          'sections': ['基本信息', '任务目标', '完成过程', '成果证据', '反思改进'],
          'lazy_generation': true,
        },
        {
          'name': '$courseName学习反思模板',
          'type': 'reflection',
          'sections': ['学习内容', '关键收获', '问题与改进'],
          'lazy_generation': true,
        },
      ];

  Map<String, dynamic> _quickAchievementConfig(
    String courseName, [
    Map<String, dynamic>? config,
  ]) {
    final configObjectives =
        (config?['objectives'] as List? ?? const []).whereType<Map>().toList();
    final objectives = configObjectives.isNotEmpty
        ? configObjectives.asMap().entries.map((entry) {
            final raw = entry.value;
            final id = raw['id'] ?? entry.key + 1;
            return {
              'id': id,
              'name': raw['name']?.toString() ?? '课程目标$id',
              'description': raw['description']?.toString() ??
                  raw['name']?.toString() ??
                  '课程目标$id',
              'weight': raw['weight'] ?? (1 / configObjectives.length),
            };
          }).toList()
        : const [
            {
              'id': 1,
              'name': '知识理解',
              'description': '理解课程核心概念与知识结构',
              'weight': 0.25,
            },
            {
              'id': 2,
              'name': '问题分析',
              'description': '能够结合课程内容分析真实问题',
              'weight': 0.25,
            },
            {
              'id': 3,
              'name': '实践应用',
              'description': '能够完成课程实践、训练或项目任务',
              'weight': 0.25,
            },
            {
              'id': 4,
              'name': '反思改进',
              'description': '能够基于评价反馈持续改进学习成果',
              'weight': 0.25,
            },
          ];
    return {
      'course_name': courseName,
      'generation_mode': 'lazy',
      'objectives': objectives,
      'objective_weights': objectives,
      'components': [
        {'name': '平时成绩', 'weight': 0.3},
        {'name': '实践/作业', 'weight': 0.3},
        {'name': '期末/综合考核', 'weight': 0.4},
      ],
    };
  }

  Map<String, dynamic> _quickAssessmentConfig(String courseName) => {
        'course_name': courseName,
        'generation_mode': 'lazy',
        'groups': [
          {
            'name': '过程评价',
            'weight': 0.3,
            'items': [
              {'name': '课堂参与', 'weight': 0.1},
              {'name': '学习记录', 'weight': 0.2},
            ],
          },
          {
            'name': '实践/作业评价',
            'weight': 0.3,
            'items': [
              {'name': '任务完成', 'weight': 0.2},
              {'name': '成果质量', 'weight': 0.1},
            ],
          },
          {
            'name': '综合评价',
            'weight': 0.4,
            'items': [
              {'name': '综合考核', 'weight': 0.4},
            ],
          },
        ],
      };

  List<Map<String, dynamic>> _lazyResources({
    required List<Map<String, dynamic>> chapters,
    required String type,
    required String titleSuffix,
  }) {
    return List.generate(chapters.length, (index) {
      final chapter = chapters[index];
      final number = chapter['number'] ?? index + 1;
      final title = chapter['title']?.toString() ?? '第$number章';
      return {
        'chapter_number': number,
        'title': title,
        'resource_type': type,
        'lazy_generation': true,
        'status': 'pending',
        'description': '$title$titleSuffix将在首次使用时生成。',
      };
    });
  }

  String _cleanChapterTitle(String value, int number) {
    return _cleanStaticChapterTitle(value, number);
  }

  static String _cleanStaticChapterTitle(String value, int number) {
    final cleaned = value
        .replaceAll('*', '')
        .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
        .replaceFirst(RegExp(r'^第\s*[一二三四五六七八九十\d]+\s*章\s*'), '')
        .replaceFirst(RegExp(r'^\d+[.、)\]]\s*'), '')
        .replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '')
        .replaceAll(RegExp(r'\s*（[^）]*）\s*$'), '')
        .trim();
    return cleaned.isEmpty ? '第$number章' : cleaned;
  }

  static List<String> _splitMarkdownRow(String line) {
    var text = line.trim();
    if (text.startsWith('|')) text = text.substring(1);
    if (text.endsWith('|')) text = text.substring(0, text.length - 1);
    return text.split('|').map((cell) => cell.trim()).toList();
  }

  static int? _chapterNumber(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) {
      return 10 + (digits[value.substring(1)] ?? 0);
    }
    if (value.endsWith('十')) {
      return (digits[value.substring(0, 1)] ?? 0) * 10;
    }
    if (value.contains('十')) {
      final parts = value.split('十');
      return (digits[parts[0]] ?? 0) * 10 + (digits[parts[1]] ?? 0);
    }
    return digits[value];
  }

  String? _firstMeaningfulLine(String? text) {
    if (text == null) return null;
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.length >= 12 &&
          !trimmed.contains('|') &&
          !trimmed.contains('课程名称') &&
          !trimmed.contains('教学大纲')) {
        return trimmed;
      }
    }
    return null;
  }

  /// 生成基础配置
  Future<Map<String, dynamic>> _generateConfig(
    String courseName,
    List<String> chapters,
    Map<String, dynamic>? existing,
  ) async {
    if (existing != null) return existing;

    final prompt = '''
为《$courseName》课程生成配置文件，返回 JSON：
{
  "course_name": "$courseName",
  "version": "1.0.0",
  "description": "课程简介（50字以内）",
  "total_weeks": 16,
  "weekly_hours": 2,
  "credits": 2,
  "category": "专业选修课",
  "objectives": [
    {"id": 1, "name": "目标1名称", "description": "目标1描述", "weight": 0.25},
    {"id": 2, "name": "目标2名称", "description": "目标2描述", "weight": 0.25},
    {"id": 3, "name": "目标3名称", "description": "目标3描述", "weight": 0.25},
    {"id": 4, "name": "目标4名称", "description": "目标4描述", "weight": 0.25}
  ]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    return _parseJson(response) ??
        {
          'course_name': courseName,
          'objectives': [],
        };
  }

  /// 生成章节配置
  Future<List<Map<String, dynamic>>> _generateChapters(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final prompt = '''
为《$courseName》课程的以下章节生成详细配置，返回 JSON 数组：
章节列表：${chapters.join('、')}

${syllabusContent != null ? '教学大纲摘要：\n$syllabusContent' : ''}

每个章节返回：
{
  "number": 1,
  "title": "章节标题",
  "description": "章节简介",
  "sub_chapters": ["子节1", "子节2", "子节3"],
  "key_points": ["重点1", "重点2"],
  "difficult_points": ["难点1", "难点2"],
  "objectives": ["本章教学目标"]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    final List? list = _parseJsonArray(response);
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 生成测验题目（每章 10 题）
  Future<List<Map<String, dynamic>>> _generateQuizzes(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final allQuestions = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节生成10道四选一测验题。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

返回 JSON 数组，每个元素：
{
  "question": "题目内容",
  "option_a": "选项A",
  "option_b": "选项B",
  "option_c": "选项C",
  "option_d": "选项D",
  "answer_index": 0,
  "chapter": "$chapter"
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final List? list = _parseJsonArray(response);
      if (list != null) {
        for (final q in list) {
          final question = Map<String, dynamic>.from(q as Map);
          question['chapter_number'] = i + 1;
          allQuestions.add(question);
        }
      }
      _report('生成测验题目', 0.2 + (i / chapters.length) * 0.15);
    }

    return allQuestions;
  }

  /// 生成视频脚本（每章 1 个）
  Future<List<Map<String, dynamic>>> _generateVideoScripts(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final scripts = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节生成一个5-8分钟的教学视频脚本。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

返回 JSON：
{
  "title": "$chapter",
  "duration_minutes": 6,
  "sections": [
    {
      "time": "00:00-01:00",
      "type": "intro",
      "content": "开场白和本节概述",
      "visual": "显示章节标题"
    },
    {
      "time": "01:00-03:00",
      "type": "content",
      "content": "核心知识点讲解",
      "visual": "展示关键概念图"
    },
    {
      "time": "03:00-05:00",
      "type": "example",
      "content": "实例演示",
      "visual": "操作演示"
    },
    {
      "time": "05:00-06:00",
      "type": "summary",
      "content": "本节总结",
      "visual": "显示要点回顾"
    }
  ],
  "script": "完整的旁白文本（包含所有section的content）"
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        data['chapter_number'] = i + 1;
        scripts.add(data);
      }
      _report('生成视频脚本', 0.4 + (i / chapters.length) * 0.1);
    }

    return scripts;
  }

  /// 生成课件内容（每章 1 个）
  Future<List<Map<String, dynamic>>> _generateCourseware(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final courseware = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节生成课件大纲（PPT 结构）。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

返回 JSON：
{
  "title": "$chapter",
  "slides": [
    {
      "slide_number": 1,
      "type": "title",
      "title": "章节标题",
      "subtitle": "课程名称"
    },
    {
      "slide_number": 2,
      "type": "content",
      "title": "本节目标",
      "bullets": ["目标1", "目标2"]
    },
    {
      "slide_number": 3,
      "type": "content",
      "title": "核心概念",
      "bullets": ["概念1：定义", "概念2：特点"],
      "notes": "详细讲解要点"
    },
    {
      "slide_number": 4,
      "type": "content",
      "title": "实例分析",
      "bullets": ["案例描述", "分析过程", "结论"],
      "notes": "配合案例讲解"
    },
    {
      "slide_number": 5,
      "type": "summary",
      "title": "本节小结",
      "bullets": ["要点1", "要点2", "要点3"]
    }
  ],
  "total_slides": 5
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        data['chapter_number'] = i + 1;
        courseware.add(data);
      }
      _report('生成课件内容', 0.5 + (i / chapters.length) * 0.1);
    }

    return courseware;
  }

  /// 生成图谱定义（7 类）
  Future<List<Map<String, dynamic>>> _generateGraphDefinitions(
    String courseName,
    List<String> chapters,
  ) async {
    final graphs = <Map<String, dynamic>>[];
    final categories = ['课程', '技术栈', '实验', '项目', '教学', '学习', '思政'];

    for (var i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final prompt = '''
为《$courseName》课程生成"$cat图谱"的节点和边定义。

章节列表：${chapters.join('、')}

返回 JSON：
{
  "category": "$cat",
  "nodes": [
    {"id": "n1", "label": "节点名称", "type": "concept", "level": 0},
    {"id": "n2", "label": "子节点", "type": "sub_concept", "level": 1, "parent_id": "n1"}
  ],
  "edges": [
    {"from": "n1", "to": "n2", "type": "contains", "label": "包含"}
  ]
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        graphs.add(data);
      }
      _report('生成图谱定义', 0.6 + (i / categories.length) * 0.1);
    }

    return graphs;
  }

  /// 生成实践任务。数据库沿用 labTasks 字段，但内容面向各类高校课程：
  /// 文科可生成研读/赏析/讨论，体育可生成训练/技评，艺术可生成创作/展演，
  /// 理工可生成实验/项目。
  Future<List<Map<String, dynamic>>> _generateLabTasks(
    String courseName,
    List<String> chapters,
    String? syllabusContent,
  ) async {
    final tasks = <Map<String, dynamic>>[];

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final prompt = '''
为《$courseName》课程的"$chapter"章节设计一个适配课程类型的实践任务。

${syllabusContent != null ? '相关教学内容：\n$syllabusContent' : ''}

要求：
1. 如果是文学、历史、哲学、法学、教育学等文科课程，任务应是文本细读、案例研讨、观点辨析、读书报告、课堂讨论或田野/资料分析。
2. 如果是体育课程，如足球专项，任务应是技术动作训练、体能与战术练习、比赛观察、技能测试、训练反思或视频动作分析。
3. 如果是艺术课程，任务应是创作、赏析、展演、作品集、技法练习或评述。
4. 如果是理工、医学、农学等课程，可使用实验、实训、项目、仿真、案例分析。
5. 不要默认所有课程都是计算机实验课。

返回 JSON：
{
  "title": "$chapter实践任务",
  "activity_type": "研讨/训练/创作/实验/项目/案例分析等",
  "description": "任务目的和背景",
  "objectives": ["目标1", "目标2"],
  "requirements": ["要求1", "要求2", "要求3"],
  "deliverables": ["提交物1", "提交物2"],
  "assessment_rubric": ["评价维度1", "评价维度2", "评价维度3"],
  "duration_hours": 4,
  "difficulty": "medium"
}
''';

      final response = await _ai.chat([
        {'role': 'user', 'content': prompt}
      ]);
      final data = _parseJson(response);
      if (data != null) {
        data['chapter_number'] = i + 1;
        tasks.add(data);
      }
    }

    return tasks;
  }

  List<Map<String, dynamic>> _generateHomeworks(
    String courseName,
    List<Map<String, dynamic>> chapters,
  ) {
    return List.generate(chapters.length, (index) {
      final chapterNumber = index + 1;
      final chapterData = chapters[index];
      final chapter = chapterData['title']?.toString().trim().isNotEmpty == true
          ? chapterData['title'].toString().trim()
          : '第$chapterNumber章';
      final keyPoints = (chapterData['key_points'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .take(4)
          .toList();
      final difficultPoints =
          (chapterData['difficult_points'] as List? ?? const [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .take(3)
              .toList();
      final objectives = (chapterData['objectives'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .take(3)
          .toList();
      final contentHint = keyPoints.isEmpty ? chapter : keyPoints.join('、');
      final difficultyHint =
          difficultPoints.isEmpty ? '本章学习难点' : difficultPoints.join('、');
      final objectiveHint =
          objectives.isEmpty ? '本章课程目标' : objectives.join('；');
      final objectiveId = (index % 4) + 1;
      final objectiveMapping = [
        {'objective_id': objectiveId, 'contribution': 1.0}
      ];
      return {
        'chapter': '第$chapterNumber章',
        'chapter_number': chapterNumber,
        'chapter_title': chapter,
        'course_objective': '目标$objectiveId',
        'description': '围绕《$courseName》"$chapter"章节完成知识理解、应用迁移与反思提升。',
        'items': [
          {
            'type_code': 'basic',
            'type': '基础题',
            'question': '围绕"$chapter"梳理$contentHint，说明关键概念、方法或技能之间的关系。',
            'reference_answer':
                '能够覆盖$contentHint，结构清晰，关系说明准确，并能对应$objectiveHint。',
            'max_score': 30,
            'objective_mapping': objectiveMapping,
          },
          {
            'type_code': 'practice',
            'type': '实践题',
            'question': '结合"$chapter"的学习内容完成一次应用任务，写出任务目标、实施步骤、结果证据和验证方法。',
            'reference_answer':
                '任务目标清楚，步骤可执行，结果证据充分，能够体现$contentHint在真实学习、训练、实验、创作或案例中的应用。',
            'max_score': 40,
            'objective_mapping': objectiveMapping,
          },
          {
            'type_code': 'reflection',
            'type': '思考题',
            'question': '针对"$chapter"中的$difficultyHint，分析自己的学习问题并提出可执行的改进计划。',
            'reference_answer': '能够准确定位难点，结合本章目标提出具体改进措施，并说明后续验证方式。',
            'max_score': 30,
            'objective_mapping': objectiveMapping,
          },
        ],
      };
    });
  }

  /// 生成报告模板
  Future<List<Map<String, dynamic>>> _generateReportTemplates(
    String courseName,
    List<String> chapters,
  ) async {
    final prompt = '''
为《$courseName》课程生成报告模板配置，返回 JSON 数组：

[
  {"name": "实验报告模板", "type": "lab_report", "sections": ["实验目的", "实验环境", "实验步骤", "实验结果", "问题与解决"]},
  {"name": "项目报告模板", "type": "project_report", "sections": ["项目背景", "需求分析", "设计方案", "实现过程", "测试结果", "总结"]},
  {"name": "学习心得模板", "type": "reflection", "sections": ["学习内容", "收获与体会", "问题与建议"]},
  {"name": "周报告模板", "type": "weekly_report", "sections": ["本周学习", "完成任务", "遇到问题", "下周计划"]},
  {"name": "课程考核报告模板", "type": "final_report", "sections": ["课程概述", "知识掌握", "技能提升", "作品展示", "自我评价"]}
]
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    final List? list = _parseJsonArray(response);
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 生成达成配置
  Future<Map<String, dynamic>> _generateAchievementConfig(
    String courseName,
    List<String> chapters,
  ) async {
    final prompt = '''
为《$courseName》课程生成成绩达成度计算配置，返回 JSON：

{
  "objectives": [
    {"id": 1, "name": "目标1", "weight": 0.25},
    {"id": 2, "name": "目标2", "weight": 0.25},
    {"id": 3, "name": "目标3", "weight": 0.25},
    {"id": 4, "name": "目标4", "weight": 0.25}
  ],
  "components": [
    {"name": "平时成绩", "weight": 0.3, "objective_weights": [0.2, 0.3, 0.3, 0.2]},
    {"name": "实验成绩", "weight": 0.3, "objective_weights": [0.2, 0.2, 0.4, 0.2]},
    {"name": "期末考试", "weight": 0.4, "objective_weights": [0.25, 0.25, 0.25, 0.25]}
  ]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    return _parseJson(response) ?? {};
  }

  /// 生成考核配置
  Future<Map<String, dynamic>> _generateAssessmentConfig(
    String courseName,
    List<String> chapters,
  ) async {
    final prompt = '''
为《$courseName》课程生成考核配置，返回 JSON：

{
  "groups": [
    {
      "name": "平时成绩",
      "weight": 0.3,
      "items": [
        {"name": "课堂表现", "weight": 0.15},
        {"name": "作业完成", "weight": 0.15}
      ]
    },
    {
      "name": "实验成绩",
      "weight": 0.3,
      "items": [
        {"name": "实验完成度", "weight": 0.2},
        {"name": "实验报告质量", "weight": 0.1}
      ]
    },
    {
      "name": "项目考核",
      "weight": 0.2,
      "items": [
        {"name": "项目完成度", "weight": 0.1},
        {"name": "项目答辩", "weight": 0.1}
      ]
    },
    {
      "name": "期末考试",
      "weight": 0.2,
      "items": [
        {"name": "理论考试", "weight": 0.2}
      ]
    }
  ]
}
''';

    final response = await _ai.chat([
      {'role': 'user', 'content': prompt}
    ]);
    return _parseJson(response) ?? {};
  }

  // ── 辅助方法 ──────────────────────────────────────────────────────────────

  void _report(String step, double progress) {
    onProgress?.call(step, progress);
    debugPrint(
        '=== CourseGeneration: $step (${(progress * 100).toStringAsFixed(0)}%)');
  }

  void _applyCourseTemplate(CourseGenerationResult result) {
    final template = CourseTemplateRegistry.resolve(
      courseProfile: result.courseProfile,
    ).toMap();
    result.courseTemplate = template;
    result.config['course_template'] = {
      'id': template['id'],
      'version': template['version'],
      'profile': template['profile'],
    };
  }

  dynamic _parseJson(String? text) {
    if (text == null || text.isEmpty) return null;
    // 提取 JSON 块
    final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(text);
    if (jsonMatch != null) {
      try {
        return jsonDecode(jsonMatch.group(1)!);
      } catch (e, st) {
        swallowDebug(e, tag: 'CourseGeneration', stack: st);
      }
    }
    // 直接尝试解析
    try {
      return jsonDecode(text);
    } catch (e, st) {
      swallowDebug(e, tag: 'CourseGeneration', stack: st);
    }
    return null;
  }

  List<dynamic>? _parseJsonArray(String? text) {
    final result = _parseJson(text);
    if (result is List) return result;
    return null;
  }

  CourseProfile _profileFromMap(Map<String, dynamic> map) {
    return CourseProfile(
      discipline: map['discipline']?.toString() ?? '通用',
      courseMode: map['course_mode']?.toString() ?? '理论实践型',
      practiceLabel: map['practice_label']?.toString() ?? '实践任务',
      graphCategories: (map['graph_categories'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      evidenceTypes: (map['evidence_types'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      rubricDimensions: (map['rubric_dimensions'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// 课程生成结果
class CourseGenerationResult {
  final String courseId;
  final String courseName;

  Map<String, dynamic> config = {};
  List<Map<String, dynamic>> chapters = [];
  List<Map<String, dynamic>> quizzes = [];
  List<Map<String, dynamic>> videoScripts = [];
  List<Map<String, dynamic>> courseware = [];
  List<Map<String, dynamic>> graphs = [];
  Map<String, dynamic> courseProfile = {};
  Map<String, dynamic> platformReadiness = {};
  Map<String, dynamic> courseTemplate =
      CourseTemplateRegistry.resolve().toMap();
  List<Map<String, dynamic>> labTasks = [];
  List<Map<String, dynamic>> homeworks = [];
  List<Map<String, dynamic>> reportTemplates = [];
  Map<String, dynamic> achievementConfig = {};
  Map<String, dynamic> assessmentConfig = {};
  bool isLazyPackage = false;
  String? error;

  CourseGenerationResult({
    required this.courseId,
    required this.courseName,
  });

  bool get isSuccess => error == null;

  /// 转换为可序列化的 Map（用于存储/上传）
  Map<String, dynamic> toMap() => {
        'course_id': courseId,
        'course_name': courseName,
        'config': config,
        'chapters': chapters,
        'quizzes': quizzes,
        'video_scripts': videoScripts,
        'courseware': courseware,
        'graphs': graphs,
        'course_profile': courseProfile,
        'platform_readiness': platformReadiness,
        'course_template': courseTemplate,
        'lab_tasks': labTasks,
        'homeworks': homeworks,
        'report_templates': reportTemplates,
        'achievement_config': achievementConfig,
        'assessment_config': assessmentConfig,
        'is_lazy_package': isLazyPackage,
        'generated_at': DateTime.now().toIso8601String(),
      };
}
