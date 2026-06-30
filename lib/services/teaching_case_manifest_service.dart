import 'dart:io';

import '../core/utils/path_utils.dart';

class TeachingCaseManifest {
  final String? manifestPath;
  final String? caseName;
  final String? fullName;
  final String? description;
  final String? appType;
  final String? launchMethod;
  final String? viewSteps;
  final String? featureIntro;
  final String? screenshotPath;
  final String? entryCommand;
  final String? repoUrl;
  final String? projectPathOverride;

  const TeachingCaseManifest({
    this.manifestPath,
    this.caseName,
    this.fullName,
    this.description,
    this.appType,
    this.launchMethod,
    this.viewSteps,
    this.featureIntro,
    this.screenshotPath,
    this.entryCommand,
    this.repoUrl,
    this.projectPathOverride,
  });

  bool get isEmpty =>
      caseName == null &&
      description == null &&
      appType == null &&
      launchMethod == null &&
      viewSteps == null &&
      featureIntro == null &&
      screenshotPath == null &&
      entryCommand == null;
}

class TeachingCaseManifestService {
  static const fileName = '教学案例.md';

  static Future<TeachingCaseManifest?> load(String selectedPath) async {
    final manifest = findManifest(selectedPath);
    if (manifest == null) return null;
    try {
      final content = await File(manifest).readAsString();
      final baseDir = File(manifest).parent.path;
      final parsed = _parse(content, manifest, baseDir);
      return parsed.isEmpty ? null : parsed;
    } catch (_) {
      return null;
    }
  }

  static String? findManifest(String selectedPath) {
    final path = PathUtils.normalize(selectedPath);
    if (path.isEmpty) return null;
    final file = File(path);
    if (file.existsSync() &&
        file.path.split(Platform.pathSeparator).last == fileName) {
      return file.path;
    }

    final dirPath = file.existsSync() ? file.parent.path : path;
    final candidates = [
      '$dirPath${Platform.pathSeparator}$fileName',
      '$dirPath${Platform.pathSeparator}docs${Platform.pathSeparator}$fileName',
      '$dirPath${Platform.pathSeparator}doc${Platform.pathSeparator}$fileName',
      '$dirPath${Platform.pathSeparator}output${Platform.pathSeparator}$fileName',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static String effectiveProjectPath(String selectedPath) {
    final path = PathUtils.normalize(selectedPath);
    final file = File(path);
    if (file.existsSync() &&
        file.path.split(Platform.pathSeparator).last == fileName) {
      return file.parent.path;
    }
    return path;
  }

  static TeachingCaseManifest _parse(
    String content,
    String manifestPath,
    String baseDir,
  ) {
    String? field(List<String> names) {
      for (final name in names) {
        final inline = RegExp(
          '^\\s*(?:[-*]\\s*)?(?:\\*\\*)?$name(?:\\*\\*)?\\s*[:：]\\s*(.+?)\\s*\$',
          multiLine: true,
        ).firstMatch(content);
        final value = inline?.group(1)?.trim();
        if (value != null && value.isNotEmpty) return _stripMarkdown(value);

        final section = _section(content, name);
        if (section != null && section.trim().isNotEmpty) {
          return _stripList(section.trim());
        }
      }
      return null;
    }

    final screenshot = _resolveRelative(
      baseDir,
      field(['启动后的截图', '运行截图', '截图', 'screenshot_path', 'screenshot']),
    );
    final projectPath = _resolveRelative(
      baseDir,
      field(['项目路径', '案例路径', 'project_path']),
    );

    return TeachingCaseManifest(
      manifestPath: manifestPath,
      caseName: field(['案例名称', '名称', 'name']),
      fullName: field(['案例全称', '全称', 'full_name']),
      description: field(['案例简介', '项目简介', '简介', 'description']),
      appType: field(['应用类型', '案例类型', 'app_type']),
      launchMethod: field(['启动应用的方法', '启动方法', '运行方法', 'launch_method']),
      viewSteps: field(['查看应用的步骤', '查看步骤', '演示步骤', 'view_steps']),
      featureIntro: field(['应用特色内容的介绍', '应用特色', '特色介绍', 'feature_intro']),
      screenshotPath: screenshot,
      entryCommand: field(['启动命令', '入口命令', 'entry_command']),
      repoUrl: field(['仓库地址', 'repo_url', 'repository']),
      projectPathOverride: projectPath,
    );
  }

  static String? _section(String content, String title) {
    final lines = content.split(RegExp(r'\r?\n'));
    final heading = RegExp(r'^\s*#{1,4}\s+(.+?)\s*$');
    var collecting = false;
    final buf = StringBuffer();
    for (final line in lines) {
      final match = heading.firstMatch(line);
      if (match != null) {
        final current = (match.group(1) ?? '').trim();
        if (collecting) break;
        if (current == title) {
          collecting = true;
        }
        continue;
      }
      if (collecting) {
        buf.writeln(line);
      }
    }
    final result = buf.toString().trim();
    return result.isEmpty ? null : result;
  }

  static String _stripMarkdown(String value) {
    return value
        .replaceAll(RegExp(r'^\s*[-*]\s*'), '')
        .replaceAll(RegExp(r'^\*\*|\*\*$'), '')
        .trim();
  }

  static String _stripList(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line
            .replaceFirst(RegExp(r'^\s*[-*]\s*'), '')
            .replaceFirst(RegExp(r'^\s*\d+[\.、]\s*'), '')
            .trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  static String? _resolveRelative(String baseDir, String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = PathUtils.normalize(raw);
    if (value.isEmpty) return null;
    if (value.contains(':\\') || value.startsWith('\\\\')) return value;
    return PathUtils.normalize('$baseDir${Platform.pathSeparator}$value');
  }
}
