import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import '../../core/error_handler.dart';
import '../course_context_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Makes bundled achievement templates available as normal files.
///
/// The template fillers operate on [File] so that teachers can still override
/// templates by dropping files into an external `data/达成` directory. On a fresh
/// install, bundled assets are copied to the app support directory first.
class AchievementTemplateAssets {
  AchievementTemplateAssets._();

  static const _assetDir = 'assets/achievement_templates';

  static Future<Map<String, String>> getBundledTemplates() async {
    final course = await CourseContextService().getActiveCourse();
    final courseName = course.name.trim().isNotEmpty ? course.name : '当前课程';
    final courseId = course.id.trim().isNotEmpty ? course.id : 'COURSE';
    // 文件名前缀使用当前激活课程的课程ID（如 CKGDT/SEB），取代旧的固定班级「计科22」，
    // 使「课程-达成」导出文件属于当前课程，而非退回移动应用开发课程。
    return {
      'mobile_achievement_template_48.xlsx':
          '$courseId《$courseName》课程达成评价表格48.xlsx',
      'mobile_achievement_report_template.docx':
          '$courseId《$courseName》课程达成评价表格-课程目标达成评价报告.docx',
    };
  }

  static Future<List<Directory>> templateRoots() async {
    final roots = <Directory>[];
    final seen = <String>{};

    void addRoot(Directory dir) {
      final normalized = p.normalize(dir.absolute.path);
      if (seen.add(normalized)) roots.add(dir);
    }

    // 优先搜索当前课程资源包目录（如 data/SEB/达成/），课程专属模板置顶。
    try {
      final course = await CourseContextService().getActiveCourse();
      final courseId = course.id.trim();
      if (courseId.isNotEmpty) {
        addRoot(Directory(p.join('data', courseId, '达成')));
        addRoot(Directory(p.join(Directory.current.path, 'data', courseId, '达成')));
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          var dir = File(Platform.resolvedExecutable).parent;
          for (var i = 0; i < 6; i++) {
            addRoot(Directory(p.join(dir.path, 'data', courseId, '达成')));
            final parent = dir.parent;
            if (parent.path == dir.path) break;
            dir = parent;
          }
        }
      }
    } catch (e) {
      swallow(e, tag: 'AchievementTemplateAssets.courseRoot');
    }

    // 全局共享目录（data/达成/）作为回退
    addRoot(Directory('data/达成'));
    addRoot(Directory(p.join(Directory.current.path, 'data', '达成')));
    var current = Directory.current.absolute;
    for (var i = 0; i < 5; i++) {
      addRoot(Directory(p.join(current.path, 'mad-data', '达成')));
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 6; i++) {
        addRoot(Directory(p.join(dir.path, 'data', '达成')));
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    // 复制内置模板到应用支持目录（仅当课程资源包无模板时兜底）。
    try {
      final supportDir = await getApplicationSupportDirectory();
      final bundledDir = Directory(p.join(supportDir.path, 'data', '达成'));
      await _extractBundledTemplates(bundledDir);
      addRoot(bundledDir);
    } catch (e) {
      swallow(e, tag: 'AchievementTemplateAssets.templateRoots');
    }

    return roots;
  }

  static Future<void> _extractBundledTemplates(Directory targetDir) async {
    await targetDir.create(recursive: true);
    final bundled = await getBundledTemplates();
    for (final entry in bundled.entries) {
      final assetPath = '$_assetDir/${entry.key}';
      try {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final file = File(p.join(targetDir.path, entry.value));
        if (await file.exists() && await file.length() == bytes.length) {
          continue;
        }
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        swallow(e, tag: 'AchievementTemplateAssets._extractBundledTemplates');
      }
    }
  }
}
