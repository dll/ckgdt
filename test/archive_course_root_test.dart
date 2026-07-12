// 归档模块平台化回归测试：
// 验证当前激活课程（如 CKGDT）的归档模板目录被设为首选，
// 使归档文档取用当前课程资料，而非退回 data/归档（MAD 通用模板）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:knowledge_graph_app/core/constants/archive_periods.dart';
import 'package:knowledge_graph_app/services/archive/archive_template_source_service.dart';

Future<Directory> _makeCourseRoot(String courseId,
    {required String periodKey, required String fileName, required String body}) async {
  final dir = await Directory.systemTemp.createTemp('archive_$courseId');
  final templateDir =
      Directory(p.join(dir.path, '归档', periodLabel(periodKey), '模板'));
  await templateDir.create(recursive: true);
  final file = File(p.join(templateDir.path, fileName));
  await file.writeAsString(body);
  return dir;
}

void main() {
  tearDown(() => ArchiveTemplateSourceService.clearRegisteredCourseArchiveRoots());

  group('归档模板取用当前激活课程（CKGDT）而非 MAD', () {
    test('prefer=true 的课程根优先于其他课程根与普通 data/归档', () async {
      final ckgdt = await _makeCourseRoot('CKGDT',
          periodKey: 'beginning',
          fileName: '教学大纲.md',
          body: '# CKGDT 教学大纲\n平台化课程资料。');
      final mad = await _makeCourseRoot('MAD',
          periodKey: 'beginning',
          fileName: '教学大纲.md',
          body: '# MAD 教学大纲\n移动应用开发课程资料。');

      ArchiveTemplateSourceService.registerCourseArchiveRoot(
        courseId: 'MAD',
        archiveRoot: p.join(mad.path, '归档'),
      );
      ArchiveTemplateSourceService.registerCourseArchiveRoot(
        courseId: 'CKGDT',
        archiveRoot: p.join(ckgdt.path, '归档'),
        prefer: true, // 当前激活课程
      );

      final doc = await ArchiveTemplateSourceService.parseBestSource(
        periodKey: 'beginning',
        documentType: 'syllabus',
        label: '测试',
      );

      expect(doc, isNotNull,
          reason: '应当能从课程归档模板目录解析出大纲');
      expect(doc!.sourcePath, contains('CKGDT'),
          reason: '应取用 CKGDT（当前课程）的模板，而非 MAD');
      expect(doc.sourcePath, isNot(contains('MAD')),
          reason: '不应取用 MAD 的模板');
      expect(doc.content, contains('平台化课程资料'),
          reason: '内容应来自 CKGDT 模板');
    });

    test('未指定 prefer 时回落到普通 data/归档（旧 MAD 通用模板）', () async {
      final mad = await _makeCourseRoot('MAD',
          periodKey: 'beginning',
          fileName: '教学大纲.md',
          body: '# MAD 教学大纲\n移动应用开发课程资料。');

      ArchiveTemplateSourceService.registerCourseArchiveRoot(
        courseId: 'MAD',
        archiveRoot: p.join(mad.path, '归档'),
      );

      final doc = await ArchiveTemplateSourceService.parseBestSource(
        periodKey: 'beginning',
        documentType: 'syllabus',
        label: '测试',
      );

      expect(doc, isNotNull);
      expect(doc!.sourcePath, contains('MAD'),
          reason: '无首选课程时取用已注册的 MAD 根（兼容旧数据）');
    });
  });
}
