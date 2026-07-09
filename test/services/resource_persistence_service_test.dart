import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/course_generation_service.dart';
import 'package:knowledge_graph_app/services/resource_persistence_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveLocally writes required package directories and inventory',
      () async {
    final temp = await Directory.systemTemp.createTemp('ckgdt_pkg_test_');
    PathProviderPlatform.instance = _FakePathProvider(temp);

    final result = CourseGenerationResult(
      courseId: 'demo_course',
      courseName: '演示课程',
    )
      ..config = {
        'course_name': '演示课程',
        'description': '用于测试资源包生成',
      }
      ..chapters = [
        {
          'number': 1,
          'title': '课程导论',
          'objectives': ['理解课程定位'],
          'key_points': ['课程目标'],
          'difficult_points': ['学习路径'],
        }
      ]
      ..quizzes = [
        {
          'chapter_number': 1,
          'question': '测试题',
          'option_a': 'A',
          'option_b': 'B',
          'option_c': 'C',
          'option_d': 'D',
          'answer_index': 0,
        }
      ]
      ..videoScripts = [
        {'chapter_number': 1, 'title': '课程导论'}
      ]
      ..courseware = [
        {'chapter_number': 1, 'title': '课程导论'}
      ]
      ..graphs = [
        {'category': '课程', 'nodes': [], 'edges': []}
      ]
      ..labTasks = [
        {
          'title': '实验一 平台体验',
          'description': '体验平台',
          'requirements': ['完成登录'],
          'deliverables': ['截图'],
        }
      ]
      ..homeworks = [
        {
          'chapter': '第1章',
          'chapter_number': 1,
          'chapter_title': '课程导论',
          'course_objective': '目标1',
          'description': '完成课程导论作业',
          'items': [
            {
              'type_code': 'basic',
              'type': '基础题',
              'question': '说明课程定位',
              'reference_answer': '能说明课程目标与学习路径',
              'max_score': 100,
              'objective_mapping': [
                {'objective_id': 1, 'contribution': 1.0}
              ],
            }
          ],
        }
      ]
      ..reportTemplates = [
        {'name': '实验报告模板', 'type': 'lab_report'}
      ]
      ..achievementConfig = {'objectives': []}
      ..assessmentConfig = {'groups': []};

    final courseDir =
        await ResourcePersistenceService.instance.saveLocally(result);

    expect(File('$courseDir/课程资源包清单.md').existsSync(), isTrue);
    expect(File('$courseDir/课程资源包清单.json').existsSync(), isTrue);
    expect(File('$courseDir/大纲/演示课程-教学大纲.md').existsSync(), isTrue);
    expect(File('$courseDir/实验/报告模板/实验一 平台体验报告模板.md').existsSync(), isTrue);
    expect(File('$courseDir/配置/homework.json').existsSync(), isTrue);
    expect(File('$courseDir/配置/course_profile.json').existsSync(), isTrue);
    expect(File('$courseDir/配置/platform_readiness.json').existsSync(), isTrue);
    expect(File('$courseDir/配置/course_template.json').existsSync(), isTrue);
    expect(File('$courseDir/配置/archive_templates.json').existsSync(), isTrue);
    expect(File('$courseDir/作业/第1章 课程导论-作业.md').existsSync(), isTrue);
    expect(File('$courseDir/文档/数智课程特色设计.md').existsSync(), isTrue);
    expect(File('$courseDir/文档/知识图谱与数字孪生闭环.md').existsSync(), isTrue);
    expect(File('$courseDir/文档/智慧课程审核清单.md').existsSync(), isTrue);
    expect(File('$courseDir/文档/平台化检测报告.md').existsSync(), isTrue);
    expect(File('$courseDir/归档/期末/模板/README.md').existsSync(), isTrue);
    expect(
      File('$courseDir/归档/期末/模板/final_archive_catalog-课程档案袋目录.md').existsSync(),
      isTrue,
    );
    expect(
      File('$courseDir/归档/结课/模板/archive_form-归档确认表.md').existsSync(),
      isTrue,
    );

    final inventory = jsonDecode(
      File('$courseDir/课程资源包清单.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final manifest = jsonDecode(
      File('$courseDir/配置/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final courseTemplate = jsonDecode(
      File('$courseDir/配置/course_template.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final readiness = jsonDecode(
      File('$courseDir/配置/platform_readiness.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final archiveTemplates = jsonDecode(
      File('$courseDir/配置/archive_templates.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final files = (inventory['files'] as List).cast<String>();
    expect(manifest['template_version'], '1.0.0');
    expect((manifest['template'] as Map)['id'], 'universal_smart_course');
    expect(courseTemplate['id'], 'universal_smart_course');
    expect(courseTemplate['modules'], contains('达成'));
    expect((inventory['template'] as Map)['version'], '1.0.0');
    final contract =
        (readiness['resource_contract'] as Map).cast<String, dynamic>();
    expect(contract['template_id'], 'universal_smart_course');
    expect(contract['profile_template_id'], 'profile_general_smart_course');
    expect(
      (contract['required_config_files'] as List).cast<String>(),
      containsAll([
        'manifest.json',
        'course_template.json',
        'platform_readiness.json',
        'achievement_calc.json',
        'archive_templates.json',
      ]),
    );
    expect((contract['archive_stages'] as List).cast<String>(),
        ['期初', '期中', '期末', '结课']);
    expect((inventory['platform_readiness'] as Map)['resource_contract'],
        isA<Map>());
    expect(archiveTemplates['workflow'], contains('归档'));
    final archiveStages =
        (archiveTemplates['stages'] as List).cast<Map<String, dynamic>>();
    expect(archiveStages.map((s) => s['label']), ['期初', '期中', '期末', '结课']);
    expect(
      archiveStages
          .expand((s) => (s['documents'] as List).cast<Map>())
          .map((d) => d['key']),
      containsAll(['syllabus', 'final_archive_catalog', 'archive_form']),
    );
    expect(files, contains('配置/manifest.json'));
    expect(files, contains('配置/homework.json'));
    expect(files, contains('配置/course_profile.json'));
    expect(files, contains('配置/platform_readiness.json'));
    expect(files, contains('配置/course_template.json'));
    expect(files, contains('配置/archive_templates.json'));
    expect(files, contains('归档/期末/模板/final_archive_catalog-课程档案袋目录.md'));
    expect(files, contains('归档/结课/模板/archive_form-归档确认表.md'));
    expect(files, contains('作业/第1章 课程导论-作业.md'));
    expect(files, contains('文档/数智课程特色设计.md'));
    expect(files, contains('文档/知识图谱与数字孪生闭环.md'));
    expect(files, contains('文档/智慧课程审核清单.md'));
    expect(files, contains('文档/平台化检测报告.md'));
    expect(files, contains('考核/试卷分析模板.md'));
    expect(files, contains('推荐/学习路径模板.md'));

    await temp.delete(recursive: true);
  });

  test('lazy course package writes directories and pending generation manifest',
      () async {
    final temp = await Directory.systemTemp.createTemp('ckgdt_lazy_pkg_test_');
    PathProviderPlatform.instance = _FakePathProvider(temp);

    final result = await CourseGenerationService().generateAll(
      courseName: '移动应用开发',
      chapters: ['第1章 课程导论', '第2章 页面布局'],
      syllabusContent: '《移动应用开发》教学大纲\n第1章 课程导论\n第2章 页面布局',
      lazy: true,
    );

    expect(result.isSuccess, isTrue);
    expect(result.isLazyPackage, isTrue);
    expect(result.quizzes, isEmpty);
    expect(result.courseware.length, 2);
    expect(result.courseware.first['lazy_generation'], isTrue);
    expect(result.courseTemplate['id'], 'universal_smart_course');
    expect(result.courseTemplate['profile'], 'engineering_experiment');

    final courseDir =
        await ResourcePersistenceService.instance.saveLocally(result);

    expect(File('$courseDir/配置/lazy_generation.json').existsSync(), isTrue);
    expect(File('$courseDir/配置/course_template.json').existsSync(), isTrue);
    expect(File('$courseDir/理论/README.md').existsSync(), isTrue);
    expect(File('$courseDir/理论/第一章课程导论-测验.md').existsSync(), isFalse);
    expect(File('$courseDir/课件/第一章课程导论-课件.lazy.json').existsSync(), isTrue);
    expect(File('$courseDir/视频/第一章课程导论-视频脚本.lazy.json').existsSync(), isTrue);

    final inventory = jsonDecode(
      File('$courseDir/课程资源包清单.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(inventory['generation_mode'], 'lazy');
    expect((inventory['template'] as Map)['profile'], 'engineering_experiment');
    expect((inventory['summary'] as Map)['lazy_pending_resources'], 8);
    expect(inventory['lazy_generation'], isA<Map<String, dynamic>>());
    final readiness = jsonDecode(
      File('$courseDir/配置/platform_readiness.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final contract =
        (readiness['resource_contract'] as Map).cast<String, dynamic>();
    expect(contract['generation_mode'], 'lazy');
    expect((contract['lazy_resource_types'] as List).cast<String>(),
        containsAll(['theory_outline', 'quiz', 'courseware', 'video_script']));
    expect(contract['manual_review_required'], isTrue);

    await temp.delete(recursive: true);
  });

  test(
      'mobile app syllabus lazy generation keeps all six chapters and rich graphs',
      () async {
    final syllabus = File('data/归档/期初/模板/02-软件+6+《移动应用开发》+教学大纲+刘东良+new.md')
        .readAsStringSync();
    final courseName =
        CourseGenerationService.extractCourseNameFromSyllabus(syllabus);
    final chapters =
        CourseGenerationService.extractChaptersFromSyllabus(syllabus);

    expect(courseName, '移动应用开发');
    expect(chapters.length, 6);
    expect(chapters.last, contains('综合开发实践'));

    final result = await CourseGenerationService().generateAll(
      courseName: courseName!,
      chapters: chapters,
      syllabusContent: syllabus,
      lazy: true,
    );

    final graphNodeCount = result.graphs.fold<int>(
      0,
      (sum, graph) => sum + ((graph['nodes'] as List?)?.length ?? 0),
    );
    final graphCategories =
        result.graphs.map((graph) => graph['category']).toList();

    expect(result.chapters.length, 6);
    expect(result.labTasks.length, 6);
    expect(result.labTasks.first['title'], contains('开发环境搭建'));
    expect(result.labTasks.last['title'], contains('跨平台综合项目实战'));
    expect(result.labTasks.last['duration_hours'], 6);
    expect(result.labTasks.last['source'], 'syllabus_practice_table');
    expect(result.homeworks.length, 6);
    final homeworkText = jsonEncode(result.homeworks);
    expect(homeworkText, contains('移动应用开发技术体系'));
    expect(homeworkText, isNot(contains('课程知识图谱与数字化教学')));
    final assessmentGroups =
        (result.assessmentConfig['groups'] as List).cast<Map>();
    expect(result.assessmentConfig['source'], 'syllabus_assessment_section');
    expect(assessmentGroups.map((g) => g['name']).join('、'), contains('平时'));
    expect(assessmentGroups.map((g) => g['name']).join('、'), contains('实验'));
    expect(assessmentGroups.map((g) => g['name']).join('、'), contains('期末'));
    expect(
      assessmentGroups.map((g) => (g['weight'] as num).toDouble()).toList(),
      containsAll(<double>[0.2, 0.3, 0.5]),
    );
    expect(graphCategories, contains('技术体系图谱'));
    expect(graphCategories, contains('实践项目图谱'));
    expect(graphNodeCount, greaterThanOrEqualTo(150));
  });

  test('literature course uses versioned template without engineering residue',
      () async {
    final temp = await Directory.systemTemp.createTemp('ckgdt_lit_pkg_test_');
    PathProviderPlatform.instance = _FakePathProvider(temp);

    const syllabus = '''
# 《文学鉴赏》教学大纲

课程名称：文学鉴赏

## 一、课程目标
1. 能够理解文学作品的文本结构、主题意蕴和审美特征。
2. 能够运用细读、比较和批评方法开展作品分析。
3. 能够形成有证据支撑的审美判断和表达。

## 二、教学内容
### 第1章 文学鉴赏导论
### 第2章 诗歌意象与节奏
### 第3章 小说叙事与人物
### 第4章 戏剧冲突与舞台表达

## 三、考核方式
平时成绩占30%，研读报告成绩占30%，期末赏析论文成绩占40%。
''';
    final courseName =
        CourseGenerationService.extractCourseNameFromSyllabus(syllabus);
    final chapters =
        CourseGenerationService.extractChaptersFromSyllabus(syllabus);

    expect(courseName, '文学鉴赏');
    expect(chapters.length, 4);

    final result = await CourseGenerationService().generateAll(
      courseName: courseName!,
      chapters: chapters,
      syllabusContent: syllabus,
      lazy: true,
    );

    expect(result.courseTemplate['id'], 'universal_smart_course');
    expect(result.courseTemplate['version'], '1.0.0');
    expect(result.courseTemplate['profile'], 'literature_reading');
    expect(
      result.courseTemplate['profile_template_id'],
      'profile_literature_reading',
    );
    expect(result.courseTemplate['profile_template_version'], '1.0.0');
    expect(result.courseProfile['practice_label'], '研读实践');
    expect(result.graphs.map((g) => g['category']), contains('文本研读图谱'));
    expect(result.graphs.map((g) => g['category']), contains('主题流派图谱'));
    expect(result.labTasks.length, 4);
    expect(
      result.labTasks.every((task) =>
          task['activity_type'] == '研读实践' &&
          !task['title'].toString().contains('实验')),
      isTrue,
    );

    final courseDir =
        await ResourcePersistenceService.instance.saveLocally(result);
    final inventoryMd = File('$courseDir/课程资源包清单.md').readAsStringSync();
    final readiness = jsonDecode(
      File('$courseDir/配置/platform_readiness.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final contract =
        (readiness['resource_contract'] as Map).cast<String, dynamic>();
    final checklist = File('$courseDir/文档/智慧课程审核清单.md').readAsStringSync();
    final packageText = Directory(courseDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where(
            (file) => file.path.endsWith('.md') || file.path.endsWith('.json'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(inventoryMd, contains('- 研读实践：4'));
    expect(inventoryMd, contains('| 画像模板ID | profile_literature_reading |'));
    expect(inventoryMd, contains('| 画像模板名称 | 文学研读课程画像模板 |'));
    expect(contract['practice_label'], '研读实践');
    expect(contract['template_profile'], 'literature_reading');
    expect((contract['archive_stages'] as List).cast<String>(),
        ['期初', '期中', '期末', '结课']);
    expect(checklist, contains('| 研读实践 |'));
    expect(packageText, contains('literature_reading'));
    expect(packageText, isNot(contains('移动应用开发')));
    expect(packageText, isNot(contains('软件23')));
    expect(packageText, isNot(contains('移动技术栈')));

    await temp.delete(recursive: true);
  });

  test('skill simulation course gets dedicated profile template', () async {
    final result = await CourseGenerationService().generateAll(
      courseName: '师范教学技能训练',
      chapters: ['第1章 教学技能规范', '第2章 课堂情境模拟'],
      syllabusContent: '''
# 《师范教学技能训练》教学大纲
课程通过教学技能、模拟授课、操作规范和课堂情境判断训练，培养师范生教学实践能力。
### 第1章 教学技能规范
### 第2章 课堂情境模拟
''',
      lazy: true,
    );

    expect(result.courseTemplate['profile'], 'skill_simulation');
    expect(result.courseTemplate['profile_template_id'],
        'profile_skill_simulation');
    expect(result.courseProfile['practice_label'], '技能实践');
    expect(result.graphs.map((g) => g['category']), contains('技能规范图谱'));
    expect(result.labTasks.every((t) => t['activity_type'] == '技能实践'), isTrue);
  });
}
