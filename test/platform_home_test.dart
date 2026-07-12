// 平台化回归测试：验证首页三角色功能不再硬编码《移动应用开发》课程。
//
// 覆盖：
// 1. CourseTerminologyService 按课程画像输出不同实践术语（研读/实验/训练/创作/案例/模拟）。
// 2. 首页可达页面源码中不再出现硬编码的课程/班级名（移动应用开发/软件23/计科22）。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/course_terminology_service.dart';

void main() {
  group('CourseTerminologyService 平台化术语适配', () {
    test('工程实验画像 → 实验项目 / 实验', () {
      final t = CourseTerms.fromTemplateProfile('engineering_experiment');
      expect(t.practiceLabel, '实验项目');
      expect(t.navLabel, '实验');
      expect(t.manageLabel, '实验项目管理');
    });

    test('文学研读画像 → 研读实践 / 研读', () {
      final t = CourseTerms.fromTemplateProfile('literature_reading');
      expect(t.practiceLabel, '研读实践');
      expect(t.navLabel, '研读');
      expect(t.manageLabel, '研读实践管理');
    });

    test('体育训练画像 → 训练实践 / 训练', () {
      final t = CourseTerms.fromTemplateProfile('sports_training');
      expect(t.practiceLabel, '训练实践');
      expect(t.navLabel, '训练');
    });

    test('艺术创作画像 → 创作实践 / 创作', () {
      final t = CourseTerms.fromTemplateProfile('art_creation');
      expect(t.practiceLabel, '创作实践');
      expect(t.navLabel, '创作');
    });

    test('经管法案例画像 → 案例实践 / 案例', () {
      final t = CourseTerms.fromTemplateProfile('case_analysis');
      expect(t.practiceLabel, '案例实践');
      expect(t.navLabel, '案例');
    });

    test('技能模拟画像 → 模拟实践 / 模拟', () {
      final t = CourseTerms.fromTemplateProfile('skill_simulation');
      expect(t.practiceLabel, '模拟实践');
      expect(t.navLabel, '模拟');
    });

    test('未知画像兜底 → 实验实践', () {
      final t = CourseTerms.fromTemplateProfile('unknown_x');
      expect(t.practiceLabel, '实验实践');
    });

    test('fromPracticeLabel 正确派生任务/报告/材料术语', () {
      final t = CourseTerms.fromPracticeLabel('研读实践');
      expect(t.taskLabel, '研读任务');
      expect(t.taskPluralLabel, '研读任务');
      expect(t.reportLabel, '研读实践报告');
      expect(t.materialLabel, '研读实践材料');
      expect(t.submitVerbLabel, '提交研读实践');
    });
  });

  group('首页可达页面无硬编码课程名', () {
    // 这些文件是首页模块直接可达的页面；不应再出现移动应用开发旧的硬编码。
    final targets = [
      'lib/presentation/pages/course/course_objectives_page.dart',
      'lib/presentation/pages/notification/notification_list_page.dart',
      'lib/presentation/pages/profile/virtual_twin_page.dart',
      'lib/presentation/pages/repo/student_repo_page.dart',
      'lib/presentation/pages/skill/ai_skill_page.dart',
      'lib/presentation/pages/archive/tabs/period_tab.dart',
      'lib/data/local/class_dao.dart',
    ];

    for (final rel in targets) {
      test('$rel 不含硬编码课程班级名', () {
        final file = File(rel);
        expect(file.existsSync(), isTrue,
            reason: '测试目标文件应存在: $rel');
        final content = file.readAsStringSync();
        // 排除旧模板识别 token（如归档兼容说明）只检查"功能性"硬编码：
        // 不允许把 移动应用开发 当作当前课程文案，或把 软件23/计科22 当作活跃课程分支。
        expect(content.contains('移动应用开发'), isFalse,
            reason: '$rel 不应再硬编码《移动应用开发》课程名');
        // 作为"活跃课程"特判的硬编码分支不应存在
        expect(content.contains("name.contains('软件23')"), isFalse,
            reason: '$rel 不应将软件23作为活跃课程特判');
        expect(
            content.contains("name.contains('计科22') && !isArchived") ||
                content.contains("name.contains('软件23') && !isArchived"),
            isFalse,
            reason: '$rel 不应为特定课程活跃班级特判占位数据');
      });
    }
  });
}
