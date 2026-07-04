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
    expect(File('$courseDir/作业/第1章 课程导论-作业.md').existsSync(), isTrue);
    expect(File('$courseDir/文档/数智课程特色设计.md').existsSync(), isTrue);
    expect(File('$courseDir/文档/知识图谱与数字孪生闭环.md').existsSync(), isTrue);
    expect(File('$courseDir/文档/智慧课程审核清单.md').existsSync(), isTrue);
    expect(File('$courseDir/归档/期末/模板/README.md').existsSync(), isTrue);

    final inventory = jsonDecode(
      File('$courseDir/课程资源包清单.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final files = (inventory['files'] as List).cast<String>();
    expect(files, contains('配置/manifest.json'));
    expect(files, contains('配置/homework.json'));
    expect(files, contains('作业/第1章 课程导论-作业.md'));
    expect(files, contains('文档/数智课程特色设计.md'));
    expect(files, contains('文档/知识图谱与数字孪生闭环.md'));
    expect(files, contains('文档/智慧课程审核清单.md'));
    expect(files, contains('考核/试卷分析模板.md'));
    expect(files, contains('推荐/学习路径模板.md'));

    await temp.delete(recursive: true);
  });
}
