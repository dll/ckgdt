import 'dart:io';
import '../core/utils/path_utils.dart';

enum ProjectType {
  flutter,
  java,
  node,
  executable,
  packaged,
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
  final String? workingDir;
  final String? url;

  const ProjectInfo({
    required this.type,
    required this.path,
    this.runCommand,
    this.runArgs = const [],
    this.buildCommand,
    this.buildArgs = const [],
    required this.label,
    this.workingDir,
    this.url,
  });
}

/// Lightweight entry-point descriptor found in a directory.
class _EntryPoint {
  final String path;       // absolute path to the entry file
  final String label;      // display label, e.g. "打包应用", "Python 脚本"
  final String? runExe;    // interpreter or null (null = run path directly)
  final List<String>? runArgs; // args to pass to the interpreter

  const _EntryPoint({
    required this.path,
    required this.label,
    this.runExe,
    this.runArgs,
  });

  /// Whether this entry point needs an external interpreter.
  bool get isDirect => runExe == null;
}

class ProjectDetector {
  // ═══════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════

  static ProjectType detectType(String projectPath) {
    // 关键：先规范化路径，去除可能的多余引号
    final p = PathUtils.normalize(projectPath);

    // ── File path: detect by extension ──────────────────────────────
    if (PathUtils.fileExists(p)) {
      if (_isEntryPointFile(p)) return ProjectType.packaged;
    }

    // ── Directory path ───────────────────────────────────────────────
    if (!PathUtils.dirExists(p)) return ProjectType.unknown;

    final names = <String>{};
    try {
      for (final entry in Directory(p).listSync()) {
        if (entry is File) {
          names.add(entry.path.split(Platform.pathSeparator).last);
        }
      }
    } catch (_) {}

    if (names.contains('pubspec.yaml')) return ProjectType.flutter;
    if (names.contains('pom.xml')) return ProjectType.java;
    if (names.contains('package.json') && _isRealNodeProject(p)) {
      return ProjectType.node;
    }
    if (_hasAnyEntryPoint(p)) return ProjectType.packaged;
    return ProjectType.unknown;
  }

  static ProjectInfo getProjectInfo(String projectPath) {
    // 关键：规范化路径
    final p = PathUtils.normalize(projectPath);

    // ── APK 文件：返回特殊标记，由 CasesPage 调用 ApkLauncherService ─
    if (p.toLowerCase().endsWith('.apk')) {
      return ProjectInfo(
        type: ProjectType.packaged,
        path: p,
        label: 'APK',
      );
    }

    final type = detectType(p);
    switch (type) {
      case ProjectType.flutter:
        return ProjectInfo(
          type: type,
          path: p,
          runCommand: 'flutter',
          runArgs: ['run'],
          buildCommand: 'flutter',
          buildArgs: ['build', 'windows', '--release'],
          label: 'Flutter',
        );
      case ProjectType.java:
        return _getJavaInfo(p);
      case ProjectType.node:
        return _getNodeInfo(p);
      case ProjectType.packaged:
        return _getPackagedInfo(p);
      case ProjectType.executable:
        return ProjectInfo(
          type: type,
          path: p,
          runCommand: p,
          label: '可执行文件',
        );
      case ProjectType.unknown:
        return ProjectInfo(
          type: type,
          path: p,
          label: '未知',
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Dev-project detection
  // ═══════════════════════════════════════════════════════════════════════

  static bool _isRealNodeProject(String projectPath) {
    final file = File('$projectPath${Platform.pathSeparator}package.json');
    if (!file.existsSync()) return false;
    try {
      final content = file.readAsStringSync();
      return content.contains('"start"') &&
          (content.contains('"dependencies"') || content.contains('"devDependencies"'));
    } catch (_) {}
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Entry-point detection (file paths + directories)
  // ═══════════════════════════════════════════════════════════════════════

  /// Check whether `path` is a known runnable file (by extension).
  static bool _isEntryPointFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.exe') ||
        lower.endsWith('.bat') ||
        lower.endsWith('.cmd') ||
        lower.endsWith('.jar') ||
        lower.endsWith('.py') ||
        lower.endsWith('.ps1');
  }

  /// Check whether `dirPath` contains at least one known runnable file.
  static bool _hasAnyEntryPoint(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return false;
    try {
      for (final entry in dir.listSync()) {
        if (entry is File && _isEntryPointFile(entry.path)) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Find the best entry point in a directory (or treat a file path as-is).
  ///
  /// Priority: .exe > .bat/.cmd > .jar > .py > .ps1
  /// Within the same extension, prefers name matching the directory basename.
  static _EntryPoint? _findBestEntryPoint(String projectPath) {
    // ── File path: wrap the file as the entry point ──────────────────
    final pathFile = File(projectPath);
    if (pathFile.existsSync()) {
      return _entryForFile(projectPath);
    }

    // ── Directory: scan for candidates ──────────────────────────────
    final dir = Directory(projectPath);
    if (!dir.existsSync()) return null;

    final dirName = projectPath.split(Platform.pathSeparator).last;

    // Collect candidates grouped by extension priority
    final exes = <File>[];
    final bats = <File>[];
    final jars = <File>[];
    final pys = <File>[];
    final ps1s = <File>[];

    try {
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final lower = entry.path.toLowerCase();
        if (lower.endsWith('.exe')) {
          exes.add(entry);
        } else if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
          bats.add(entry);
        } else if (lower.endsWith('.jar') && !lower.endsWith('.jar.original')) {
          jars.add(entry);
        } else if (lower.endsWith('.py')) {
          pys.add(entry);
        } else if (lower.endsWith('.ps1')) {
          ps1s.add(entry);
        }
      }
    } catch (_) {}

    // Pick first non-empty group by priority, preferring name match
    if (exes.isNotEmpty) return _entryForExe(exes, dirName);
    if (bats.isNotEmpty) return _entryForBat(bats, dirName);
    if (jars.isNotEmpty) return _entryForJar(jars, dirName, projectPath);
    if (pys.isNotEmpty) return _entryForPython(pys, dirName);
    if (ps1s.isNotEmpty) return _entryForPs1(ps1s, dirName);

    return null;
  }

  // ── Per-type entry helpers ────────────────────────────────────────────

  static _EntryPoint? _entryForFile(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.exe')) {
      return _EntryPoint(path: filePath, label: '打包应用');
    }
    if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
      return _EntryPoint(path: filePath, label: '脚本 (bat)',
        runExe: 'cmd', runArgs: ['/c', filePath],
      );
    }
    if (lower.endsWith('.jar')) {
      // Use system java as fallback
      final sep = Platform.pathSeparator;
      final parent = filePath.split(sep).sublist(0, filePath.split(sep).length - 1).join(sep);
      final embeddedJre = '$parent${sep}jre${sep}bin${sep}java.exe';
      final javaExe = File(embeddedJre).existsSync() ? embeddedJre : 'java';
      return _EntryPoint(path: filePath, label: 'Java 应用',
        runExe: javaExe, runArgs: ['-jar', filePath],
      );
    }
    if (lower.endsWith('.py')) {
      return _EntryPoint(path: filePath, label: 'Python 脚本',
        runExe: 'python', runArgs: [filePath],
      );
    }
    if (lower.endsWith('.ps1')) {
      return _EntryPoint(path: filePath, label: 'PowerShell 脚本',
        runExe: 'powershell', runArgs: ['-ExecutionPolicy', 'Bypass', '-File', filePath],
      );
    }
    return null;
  }

  static _EntryPoint _entryForExe(List<File> exes, String dirName) {
    final best = _pickBest(exes, dirName, '.exe');
    // Check for companion JRE to refine label
    final parent = best.path.split(Platform.pathSeparator).sublist(0, best.path.split(Platform.pathSeparator).length - 1).join(Platform.pathSeparator);
    final jreExe = '$parent${Platform.pathSeparator}jre${Platform.pathSeparator}bin${Platform.pathSeparator}java.exe';
    final hasJre = File(jreExe).existsSync();
    return _EntryPoint(
      path: best.path,
      label: hasJre ? '打包应用 (Java)' : '打包应用',
    );
  }

  static _EntryPoint _entryForBat(List<File> bats, String dirName) {
    final best = _pickBest(bats, dirName, '.bat');
    return _EntryPoint(
      path: best.path, label: '脚本 (bat)',
      runExe: 'cmd', runArgs: ['/c', best.path],
    );
  }

  static _EntryPoint _entryForJar(List<File> jars, String dirName, String projectPath) {
    final best = _pickBest(jars, dirName, '.jar');
    final sep = Platform.pathSeparator;

    // Look for embedded JRE (projectPath/jre, deploy/jre)
    String javaExe = 'java';
    final rootJre = '$projectPath${sep}jre${sep}bin${sep}java.exe';
    final deployJre = '$projectPath${sep}deploy${sep}jre${sep}bin${sep}java.exe';
    if (File(rootJre).existsSync()) {
      javaExe = rootJre;
    } else if (File(deployJre).existsSync()) {
      javaExe = deployJre;
    }

    final hasEmbeddedJre = javaExe != 'java';

    return _EntryPoint(
      path: best.path, label: hasEmbeddedJre ? '打包应用 (Java)' : 'Java 应用',
      runExe: javaExe, runArgs: ['-jar', best.path],
    );
  }

  static _EntryPoint _entryForPython(List<File> pys, String dirName) {
    final best = _pickBest(pys, dirName, '.py');
    return _EntryPoint(
      path: best.path, label: 'Python 脚本',
      runExe: 'python', runArgs: [best.path],
    );
  }

  static _EntryPoint _entryForPs1(List<File> ps1s, String dirName) {
    final best = _pickBest(ps1s, dirName, '.ps1');
    return _EntryPoint(
      path: best.path, label: 'PowerShell 脚本',
      runExe: 'powershell', runArgs: ['-ExecutionPolicy', 'Bypass', '-File', best.path],
    );
  }

  /// From a list of files, pick the one whose basename matches `dirName`,
  /// otherwise return the first.
  static File _pickBest(List<File> files, String dirName, String suffix) {
    if (files.length == 1) return files.first;
    final target = '$dirName$suffix'.toLowerCase();
    final match = files.cast<File?>().firstWhere(
      (f) => f!.path.split(Platform.pathSeparator).last.toLowerCase() == target,
      orElse: () => null,
    );
    return match ?? files.first;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Packaged app info
  // ═══════════════════════════════════════════════════════════════════════

  static ProjectInfo _getPackagedInfo(String projectPath) {
    final entry = _findBestEntryPoint(projectPath);

    if (entry == null) {
      return ProjectInfo(type: ProjectType.packaged, path: projectPath, label: '未知');
    }

    // Determine working directory
    final entryFile = File(entry.path);
    String? workingDir;
    if (entryFile.existsSync()) {
      workingDir = entryFile.parent.path;
    } else {
      workingDir = Directory(projectPath).existsSync() ? projectPath : null;
    }

    // Detect port / URL from config files and entry script
    final sep = Platform.pathSeparator;
    final port = _detectPort('$projectPath${sep}deploy${sep}application-demo.yml') ??
        _detectPort('$projectPath${sep}application-demo.yml') ??
        _detectPort('$projectPath${sep}application.yml') ??
        _detectPortFromBatContent(entry.path);
    final explicitUrl = _detectUrlFromBatContent(entry.path) ??
        (port != null ? 'http://localhost:$port' : null);

    // Web 应用标签优化
    final label = explicitUrl != null && !entry.label.contains('APK')
        ? entry.label.replaceFirst('脚本', 'Web 脚本').replaceFirst('打包应用', 'Web 应用')
        : entry.label;

    return ProjectInfo(
      type: ProjectType.packaged,
      path: projectPath,
      runCommand: entry.isDirect ? entry.path : entry.runExe,
      runArgs: entry.isDirect ? [] : (entry.runArgs ?? []),
      label: label,
      workingDir: workingDir,
      url: explicitUrl,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Java / Node info
  // ═══════════════════════════════════════════════════════════════════════

  static ProjectInfo _getJavaInfo(String projectPath) {
    final sep = Platform.pathSeparator;

    // 0. 优先检查 output 目录中的打包应用（如 Start-*.bat / TingChengGIS.exe）
    //    教学场景下，用户添加的是开发项目目录，但实际想跑的是已发布的打包版本
    final packaged = _findPackagedAppInOutput(projectPath);
    if (packaged != null) return packaged;

    // 1. Find JAR: deploy/*.jar > root *.jar > target/*.jar
    String? jarPath;
    String? jarDir;
    final deployDir = Directory('$projectPath${sep}deploy');
    if (deployDir.existsSync()) {
      try {
        for (final f in deployDir.listSync()) {
          if (f is File && f.path.endsWith('.jar') && !f.path.endsWith('.jar.original')) {
            jarPath = f.path;
            jarDir = deployDir.path;
            break;
          }
        }
      } catch (_) {}
    }
    if (jarPath == null) {
      try {
        for (final f in Directory(projectPath).listSync()) {
          if (f is File && f.path.endsWith('.jar') && !f.path.endsWith('.jar.original')) {
            jarPath = f.path;
            jarDir = projectPath;
            break;
          }
        }
      } catch (_) {}
    }
    if (jarPath == null) {
      final targetDir = Directory('$projectPath${sep}target');
      if (targetDir.existsSync()) {
        try {
          for (final f in targetDir.listSync()) {
            if (f is File && f.path.endsWith('.jar') && !f.path.endsWith('.jar.original')) {
              jarPath = f.path;
              jarDir = targetDir.path;
              break;
            }
          }
        } catch (_) {}
      }
    }

    // 2. Find JRE: deploy/jre > project/jre > system java
    String? javaExe;
    final embeddedJre = '$projectPath${sep}deploy${sep}jre${sep}bin${sep}java.exe';
    if (File(embeddedJre).existsSync()) {
      javaExe = embeddedJre;
    } else {
      final rootJre = '$projectPath${sep}jre${sep}bin${sep}java.exe';
      if (File(rootJre).existsSync()) {
        javaExe = rootJre;
      }
    }

    // 3. Find config
    String? configPath;
    final deployConfig = '$projectPath${sep}deploy${sep}application-demo.yml';
    if (File(deployConfig).existsSync()) {
      configPath = deployConfig;
    } else {
      final rootConfig = '$projectPath${sep}application-demo.yml';
      if (File(rootConfig).existsSync()) {
        configPath = rootConfig;
      }
    }

    // 4. Detect port
    final port = _detectPort(configPath) ??
        _detectPort('$projectPath${sep}src${sep}main${sep}resources${sep}application.yml') ??
        _detectPort('$projectPath${sep}application.yml');

    // 5. Build java command
    if (jarPath != null && javaExe != null) {
      final args = <String>[
        '-Dfile.encoding=UTF-8',
        '-Xmx1024m',
        '-jar', jarPath,
      ];
      if (configPath != null) {
        final configName = configPath.split(sep).last;
        args.add('--spring.config.additional-location=file:$configName');
      }
      return ProjectInfo(
        type: ProjectType.java,
        path: projectPath,
        runCommand: javaExe,
        runArgs: args,
        buildCommand: 'mvn',
        buildArgs: ['package', '-DskipTests'],
        label: 'Java/Maven',
        workingDir: jarDir,
        url: port != null ? 'http://localhost:$port' : null,
      );
    }

    // 6. Fallback: try bat script
    final bat = _findDeployBat(projectPath);
    if (bat != null) {
      return ProjectInfo(
        type: ProjectType.java,
        path: projectPath,
        runCommand: 'cmd',
        runArgs: ['/c', bat],
        buildCommand: 'mvn',
        buildArgs: ['package', '-DskipTests'],
        label: 'Java/Maven (bat)',
        workingDir: '$projectPath${sep}deploy',
        url: port != null ? 'http://localhost:$port' : null,
      );
    }

    // 7. Fallback: maven spring-boot:run
    return ProjectInfo(
      type: ProjectType.java,
      path: projectPath,
      runCommand: 'mvn',
      runArgs: ['spring-boot:run'],
      buildCommand: 'mvn',
      buildArgs: ['package', '-DskipTests'],
      label: 'Java/Maven',
      url: port != null ? 'http://localhost:$port' : null,
    );
  }

  static ProjectInfo _getNodeInfo(String projectPath) {
    final port = _detectPortFromPackageJson(projectPath);
    return ProjectInfo(
      type: ProjectType.node,
      path: projectPath,
      runCommand: 'npm',
      runArgs: ['start'],
      buildCommand: 'npm',
      buildArgs: ['run', 'build'],
      label: 'Node.js',
      url: port != null ? 'http://localhost:$port' : null,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // output 目录中查找打包应用（Start-*.bat / *.exe）
  // ═══════════════════════════════════════════════════════════════════════

  /// 在 `<projectPath>/output/` 及其直接子目录中查找打包好的应用入口。
  /// 典型场景：教学案例的开发目录是 `D:\project\xxx`，
  /// 但实际想启动的是 `D:\project\xxx\output\xxx-v1.0.5\Start-xxx.bat`。
  ///
  /// 优先级：Start-*.bat（最常见，约定俗成） > 任意 .bat > 任意 .exe
  static ProjectInfo? _findPackagedAppInOutput(String projectPath) {
    final sep = Platform.pathSeparator;
    final outputRoot = Directory('$projectPath${sep}output');
    if (!outputRoot.existsSync()) return null;

    // 收集候选目录：output 根目录 + output 下所有子目录
    final candidates = <Directory>[outputRoot];
    try {
      for (final entry in outputRoot.listSync()) {
        if (entry is Directory) candidates.add(entry);
      }
    } catch (_) {}

    // 第一遍：找 Start-*.bat（最优先）
    for (final dir in candidates) {
      final startBat = _findStartBat(dir.path);
      if (startBat != null) {
        return _buildPackagedFromBat(startBat, dir.path, projectPath);
      }
    }

    // 第二遍：找任意 .bat / .cmd
    for (final dir in candidates) {
      final entry = _findBestEntryPoint(dir.path);
      if (entry == null) continue;
      final lower = entry.path.toLowerCase();
      if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
        return _buildPackagedFromEntry(entry, dir.path, projectPath);
      }
    }

    // 第三遍：找 .exe
    for (final dir in candidates) {
      final entry = _findBestEntryPoint(dir.path);
      if (entry == null) continue;
      if (entry.path.toLowerCase().endsWith('.exe')) {
        return _buildPackagedFromEntry(entry, dir.path, projectPath);
      }
    }

    return null;
  }

  /// 在目录中找 Start-*.bat / Start-*.cmd（约定俗成的启动脚本）
  static String? _findStartBat(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;
    try {
      // 优先匹配"目录名.bat"（如 TingChengGIS-v1.0.5 -> Start-TingChengGIS.bat）
      final allBats = <File>[];
      String? firstStart;
      for (final entry in dir.listSync()) {
        if (entry is File) {
          final lower = entry.path.toLowerCase();
          if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
            allBats.add(entry);
            final name = entry.path.split(Platform.pathSeparator).last;
            if (name.toLowerCase().startsWith('start') && firstStart == null) {
              firstStart = entry.path;
            }
          }
        }
      }
      return firstStart ?? (allBats.isNotEmpty ? allBats.first.path : null);
    } catch (_) {
      return null;
    }
  }

  /// 从 .bat 路径构建 ProjectInfo
  static ProjectInfo _buildPackagedFromBat(
      String batPath, String dirPath, String projectPath) {
    final sep = Platform.pathSeparator;
    final port = _detectPort('$dirPath${sep}deploy${sep}application-demo.yml') ??
        _detectPort('$dirPath${sep}application-demo.yml') ??
        _detectPort('$dirPath${sep}application.yml') ??
        _detectPortFromBatContent(batPath);
    final explicitUrl = _detectUrlFromBatContent(batPath) ??
        (port != null ? 'http://localhost:$port' : null);
    final batName = batPath.split(sep).last;
    return ProjectInfo(
      type: ProjectType.packaged,
      path: projectPath,
      runCommand: 'cmd',
      runArgs: ['/c', batPath],
      label: explicitUrl != null ? 'Web 应用 ($batName)' : '打包应用 ($batName)',
      workingDir: dirPath,
      url: explicitUrl,
    );
  }

  /// 从 _EntryPoint 构建 ProjectInfo
  static ProjectInfo _buildPackagedFromEntry(
      _EntryPoint entry, String dirPath, String projectPath) {
    final sep = Platform.pathSeparator;
    final port = _detectPort('$dirPath${sep}deploy${sep}application-demo.yml') ??
        _detectPort('$dirPath${sep}application-demo.yml') ??
        _detectPort('$dirPath${sep}application.yml') ??
        (entry.path.toLowerCase().endsWith('.bat') ||
                entry.path.toLowerCase().endsWith('.cmd')
            ? _detectPortFromBatContent(entry.path)
            : null);
    final explicitUrl = _detectUrlFromBatContent(entry.path) ??
        (port != null ? 'http://localhost:$port' : null);
    final isWeb = explicitUrl != null;
    if (entry.isDirect) {
      return ProjectInfo(
        type: ProjectType.packaged,
        path: projectPath,
        runCommand: entry.path,
        label: isWeb ? 'Web 应用 (exe)' : '打包应用 (exe)',
        workingDir: dirPath,
        url: explicitUrl,
      );
    }
    return ProjectInfo(
      type: ProjectType.packaged,
      path: projectPath,
      runCommand: entry.runExe ?? 'cmd',
      runArgs: entry.runArgs ?? ['/c', entry.path],
      label: isWeb ? 'Web 应用 (${entry.label})' : '打包应用 (${entry.label})',
      workingDir: dirPath,
      url: explicitUrl,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Config helpers
  // ═══════════════════════════════════════════════════════════════════════

  static int? _detectPort(String? configPath) {
    if (configPath == null) return null;
    final file = File(configPath);
    if (!file.existsSync()) return null;
    try {
      final lines = file.readAsLinesSync();
      bool inServerBlock = false;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed == 'server:') { inServerBlock = true; continue; }
        if (inServerBlock && trimmed.startsWith('port:')) {
          final portStr = trimmed.replaceFirst('port:', '').trim();
          return int.tryParse(portStr);
        }
        if (inServerBlock && trimmed.isNotEmpty && !trimmed.startsWith(' ') && !trimmed.startsWith('#')) {
          inServerBlock = false;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从 bat / cmd 脚本内容中读取显式 URL（如 start http://localhost:8080）
  static String? _detectUrlFromBatContent(String? batPath) {
    if (batPath == null) return null;
    final lower = batPath.toLowerCase();
    if (!lower.endsWith('.bat') && !lower.endsWith('.cmd')) return null;
    final file = File(batPath);
    if (!file.existsSync()) return null;
    try {
      final content = file.readAsStringSync();
      // 显式打开浏览器
      final direct = RegExp(r'https?://localhost:\d+', caseSensitive: false)
          .firstMatch(content);
      if (direct != null) return direct.group(0);
      // start http://... / explorer http://...
      final startUrl = RegExp(
        "(?:start|explorer|cmd\\s+/c\\s+start)\\s+(?:[\"'])?(https?://[^\"'\\s]+)(?:[\"'])?",
        caseSensitive: false,
      ).firstMatch(content);
      if (startUrl != null) return startUrl.group(1);
    } catch (_) {}
    return null;
  }

  /// 从 bat / cmd 脚本内容中读取常见服务端口号
  static int? _detectPortFromBatContent(String? batPath) {
    if (batPath == null) return null;
    final lower = batPath.toLowerCase();
    if (!lower.endsWith('.bat') && !lower.endsWith('.cmd')) return null;
    final file = File(batPath);
    if (!file.existsSync()) return null;
    try {
      final content = file.readAsStringSync();
      // 1. --server.port=8080 / -Dserver.port=8080
      final explicit = RegExp(r'(?:server\.port|port)[:=]\s*(\d{4,5})',
              caseSensitive: false)
          .firstMatch(content);
      if (explicit != null) return int.tryParse(explicit.group(1)!);
      // 2. 常见的教学场景端口（如果脚本中多处提到取第一个）
      final common = RegExp(r'\b(8080|8090|8443|3000|5000|8000|9000|9090)\b')
          .firstMatch(content);
      if (common != null) return int.tryParse(common.group(1)!);
    } catch (_) {}
    return null;
  }

  static int? _detectPortFromPackageJson(String projectPath) {
    final file = File('$projectPath${Platform.pathSeparator}package.json');
    if (!file.existsSync()) return null;
    try {
      final content = file.readAsStringSync();
      final portMatch = RegExp(r'PORT.+?(\d{4,5})').firstMatch(content);
      if (portMatch != null) return int.tryParse(portMatch.group(1)!);
    } catch (_) {}
    return null;
  }

  static String? _findDeployBat(String projectPath) {
    final sep = Platform.pathSeparator;
    final dir = Directory('$projectPath${sep}deploy');
    if (!dir.existsSync()) {
      final rootDir = Directory(projectPath);
      if (rootDir.existsSync()) {
        try {
          for (final f in rootDir.listSync()) {
            if (f is File) {
              final name = f.path.split(sep).last.toLowerCase();
              if (name.contains('start') && (name.endsWith('.bat') || name.endsWith('.cmd'))) {
                return f.path;
              }
            }
          }
        } catch (_) {}
      }
      return null;
    }
    try {
      for (final f in dir.listSync()) {
        if (f is File) {
          final name = f.path.split(sep).last.toLowerCase();
          if (name.contains('start') && (name.endsWith('.bat') || name.endsWith('.cmd'))) {
            return f.path;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // External tool helpers
  // ═══════════════════════════════════════════════════════════════════════

  static Future<bool> canOpenInEditor(String projectPath) async {
    try {
      final result = await Process.run('where', ['trae'], runInShell: true);
      if (result.exitCode == 0) return true;
    } catch (_) {}
    try {
      final result = await Process.run('where', ['code'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInEditor(String projectPath) async {
    try {
      await Process.run('trae', [projectPath], runInShell: true);
      return;
    } catch (_) {}
    try {
      await Process.run('code', [projectPath], runInShell: true);
    } catch (_) {}
  }

  static Future<void> openInExplorer(String projectPath) async {
    try {
      await Process.run('explorer', [projectPath], runInShell: true);
    } catch (_) {}
  }

  static Future<void> openInBrowser(String url) async {
    try {
      await Process.run('cmd', ['/c', 'start', url], runInShell: true);
    } catch (_) {}
  }
}
