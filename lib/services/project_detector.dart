import 'dart:io';

enum ProjectType {
  flutter,
  java,
  node,
  executable,
  unknown,
}

class ProjectInfo {
  final ProjectType type;
  final String path;
  final String? runCommand;
  final List<String> runArgs;
  final String? buildCommand;
  final List<String> buildArgs;
  final String label;

  const ProjectInfo({
    required this.type,
    required this.path,
    this.runCommand,
    this.runArgs = const [],
    this.buildCommand,
    this.buildArgs = const [],
    required this.label,
  });
}

class ProjectDetector {
  static ProjectType detectType(String projectPath) {
    if (!Directory(projectPath).existsSync()) return ProjectType.unknown;
    final dir = Directory(projectPath);
    try {
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.path.split(Platform.pathSeparator).last;
        if (name == 'pubspec.yaml') return ProjectType.flutter;
        if (name == 'pom.xml') return ProjectType.java;
        if (name == 'package.json') return ProjectType.node;
      }
    } catch (_) {}
    final lower = projectPath.toLowerCase();
    if (lower.endsWith('.exe') || lower.endsWith('.bat') || lower.endsWith('.cmd')) {
      return ProjectType.executable;
    }
    return ProjectType.unknown;
  }

  static ProjectInfo getProjectInfo(String projectPath) {
    final type = detectType(projectPath);
    switch (type) {
      case ProjectType.flutter:
        return ProjectInfo(
          type: type,
          path: projectPath,
          runCommand: 'flutter',
          runArgs: ['run'],
          buildCommand: 'flutter',
          buildArgs: ['build', 'windows', '--release'],
          label: 'Flutter',
        );
      case ProjectType.java:
        return ProjectInfo(
          type: type,
          path: projectPath,
          runCommand: 'mvn',
          runArgs: ['spring-boot:run'],
          buildCommand: 'mvn',
          buildArgs: ['package', '-DskipTests'],
          label: 'Java/Maven',
        );
      case ProjectType.node:
        return ProjectInfo(
          type: type,
          path: projectPath,
          runCommand: 'npm',
          runArgs: ['start'],
          buildCommand: 'npm',
          buildArgs: ['run', 'build'],
          label: 'Node.js',
        );
      case ProjectType.executable:
        return ProjectInfo(
          type: type,
          path: projectPath,
          runCommand: projectPath,
          runArgs: [],
          buildCommand: null,
          buildArgs: [],
          label: '可执行文件',
        );
      case ProjectType.unknown:
        return ProjectInfo(
          type: type,
          path: projectPath,
          runCommand: null,
          runArgs: [],
          buildCommand: null,
          buildArgs: [],
          label: '未知',
        );
    }
  }

  static Future<bool> canOpenInVSCode(String projectPath) async {
    try {
      final result = await Process.run('where', ['code'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInVSCode(String projectPath) async {
    try {
      await Process.run('code', [projectPath], runInShell: true);
    } catch (_) {}
  }

  static Future<void> openInExplorer(String projectPath) async {
    try {
      await Process.run('explorer', [projectPath], runInShell: true);
    } catch (_) {}
  }
}
