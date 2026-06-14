import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
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
  static const _bundledTemplates = {
    'mobile_achievement_template_48.xlsx': '计科22《移动应用开发》课程达成评价表格48.xlsx',
    'mobile_achievement_report_template.docx':
        '计科22《移动应用开发》课程达成评价表格-课程目标达成评价报告.docx',
  };

  static Future<List<Directory>> templateRoots() async {
    final roots = <Directory>[];
    final seen = <String>{};

    void addRoot(Directory dir) {
      final normalized = p.normalize(dir.absolute.path);
      if (seen.add(normalized)) roots.add(dir);
    }

    addRoot(Directory('data/达成'));
    addRoot(Directory(p.join(Directory.current.path, 'data', '达成')));

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 6; i++) {
        addRoot(Directory(p.join(dir.path, 'data', '达成')));
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    // 复制内置模板到应用支持目录。path_provider 在纯单测环境不可用，
    // 失败时退回上面的本地/外部 data/达成 根，不影响模板查找。
    try {
      final supportDir = await getApplicationSupportDirectory();
      final bundledDir = Directory(p.join(supportDir.path, 'data', '达成'));
      await _extractBundledTemplates(bundledDir);
      addRoot(bundledDir);
    } catch (_) {
      // 无 path_provider（单测）或写入失败：忽略，使用其它根。
    }

    return roots;
  }

  static Future<void> _extractBundledTemplates(Directory targetDir) async {
    await targetDir.create(recursive: true);
    for (final entry in _bundledTemplates.entries) {
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
      } catch (_) {
        // Asset may be absent in older builds. Template lookup will then fall
        // back to external roots or generated reports.
      }
    }
  }
}
