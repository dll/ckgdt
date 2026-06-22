/// 升版服务 — 把 v X.Y.Z 同步写到 10 个文件。
///
/// **单一来源原则**：lib/core/build_info.dart 的 `appVersion` 常量是 SSOT，
/// 但平台原生清单（pubspec / strings.xml / Runner.rc / web meta / ohos）
/// 不能从 Dart 常量读，必须文件级同步——本服务一次改完。
///
/// **冲突处理**：bump 前调 [resolveTargetVersion]，
/// 如果目标 tag / GitHub Release / Gitee Release 已存在，自动 +patch 重试。
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/dev_paths.dart';

class VersionBumpService {
  VersionBumpService._();

  /// 项目根目录 — 委派给 [DevPaths.projectRoot]（统一兜底逻辑）。
  static String get projectRoot => DevPaths.projectRoot;

  /// 解析当前 Version.display（SSOT）。
  static Future<String> readCurrentVersion() async {
    final f = File(p.join(projectRoot, 'lib', 'core', 'version.dart'));
    final s = await f.readAsString();
    final m = RegExp(r"static const String display\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'").firstMatch(s);
    if (m == null) {
      throw StateError('version.dart 里找不到 display 常量');
    }
    return m.group(1)!;
  }

  /// `0.13.1` → `0.13.2`（patch +1）。
  /// 不支持 minor/major 自动升级——若需要 admin 在 UI 手动改 BuildInfo.dart 后再发版。
  static String bumpPatch(String version) {
    final parts = version.split('.').map(int.parse).toList();
    if (parts.length != 3) {
      throw ArgumentError('版本号格式必须是 x.y.z，收到：$version');
    }
    parts[2] += 1;
    return parts.join('.');
  }

  /// 把 [newVersion] 写到所有 10 个目标文件。
  /// 返回每个文件的更新摘要（用于 admin UI 日志）。
  ///
  /// **不更改**任何中间产物（dist/、build/）；这些靠后续构建步骤重生。
  static Future<List<String>> applyVersion(String newVersion) async {
    final root = projectRoot;
    final logs = <String>[];

    Future<void> patch(
      String relPath,
      RegExp pattern,
      String Function(Match m) replacer, {
      String? tag,
    }) async {
      final f = File(p.join(root, relPath));
      if (!await f.exists()) {
        logs.add('  跳过（不存在）: $relPath');
        return;
      }
      final orig = await f.readAsString();
      final next = orig.replaceAllMapped(pattern, replacer);
      if (next == orig) {
        logs.add('  无变化: $relPath');
        return;
      }
      await f.writeAsString(next);
      logs.add('  ✓ ${tag ?? relPath}');
    }

    // 1. lib/core/build_info.dart — Dart 单一来源
    await patch(
      'lib/core/build_info.dart',
      RegExp(r"(appVersion\s*=\s*')[0-9.]+(')"),
      (m) => '${m.group(1)}$newVersion${m.group(2)}',
      tag: 'BuildInfo.appVersion',
    );

    // 2. pubspec.yaml — pubspec 自身（构建号 +N 归零）
    await patch(
      'pubspec.yaml',
      RegExp(r'(version:\s*)[0-9.]+(\+\d+)?'),
      (m) => '${m.group(1)}$newVersion+0',
      tag: 'pubspec.yaml version',
    );

    // 3. Android strings.xml — app_name
    await patch(
      'android/app/src/main/res/values/strings.xml',
      RegExp(r'(课程图谱与数字孪生v)[0-9.]+'),
      (m) => '${m.group(1)}$newVersion',
      tag: 'android strings.xml',
    );

    // 4-6. Windows
    await patch(
      'windows/CMakeLists.txt',
      RegExp(r'(BINARY_OUTPUT_NAME\s+"课程图谱与数字孪生v)[0-9.]+(")'),
      (m) => '${m.group(1)}$newVersion${m.group(2)}',
      tag: 'CMakeLists.txt',
    );
    await patch(
      'windows/runner/main.cpp',
      RegExp(r'(window\.Create\(L"课程图谱与数字孪生v)[0-9.]+(")'),
      (m) => '${m.group(1)}$newVersion${m.group(2)}',
      tag: 'main.cpp',
    );
    await patch(
      'windows/runner/Runner.rc',
      // 同时改 FileDescription / OriginalFilename / ProductName 这 3 处，
      // 不动 InternalName（按 CLAUDE.md 规则不带版本号）
      // 注：用 \d+\.\d+\.\d+ 而非 [0-9.]+ 以避免误吞 .exe 后缀
      RegExp(
          r'(FileDescription|OriginalFilename|ProductName)(",\s*"课程图谱与数字孪生v)\d+\.\d+\.\d+'),
      (m) => '${m.group(1)}${m.group(2)}$newVersion',
      tag: 'Runner.rc (3 处)',
    );

    // 7-8. Web
    await patch(
      'web/index.html',
      RegExp(
          r'(<meta name="application-name" content="课程图谱与数字孪生v|<meta name="apple-mobile-web-app-title" content="课程图谱与数字孪生v|<title>课程图谱与数字孪生v)[0-9.]+'),
      (m) => '${m.group(1)}$newVersion',
      tag: 'web/index.html (3 处)',
    );
    await patch(
      'web/manifest.json',
      RegExp(r'("name":\s*"课程图谱与数字孪生v)[0-9.]+'),
      (m) => '${m.group(1)}$newVersion',
      tag: 'web/manifest.json',
    );

    // 9. ohos versionName
    await patch(
      'ohos/AppScope/app.json5',
      RegExp(r'("versionName":\s*")[0-9.]+(")'),
      (m) => '${m.group(1)}$newVersion${m.group(2)}',
      tag: 'ohos versionName',
    );
    // 9b. ohos versionCode +1（独立递增，不和 versionName 联动）
    await patch(
      'ohos/AppScope/app.json5',
      RegExp(r'("versionCode":\s*)(\d+)'),
      (m) {
        final code = int.parse(m.group(2)!) + 1;
        return '${m.group(1)}$code';
      },
      tag: 'ohos versionCode +1',
    );

    // 10. i18n example（占位符示例，无功能影响）
    await patch(
      'lib/l10n/app_zh.arb',
      RegExp(r'("example":\s*")[0-9.]+(")'),
      (m) => '${m.group(1)}$newVersion${m.group(2)}',
      tag: 'app_zh.arb example',
    );

    return logs;
  }

  /// 一致性 grep — 跑完 bump 后用，扫所有文件确认版本号统一。
  /// 返回 (期望版本号, 找到的所有版本号字符串列表)，
  /// admin UI 据此决定是否中断。
  static Future<Map<String, dynamic>> verifyConsistency() async {
    final root = projectRoot;
    final found = <String, String>{};

    Future<void> probe(String key, RegExp pat, {String? sourceFile}) async {
      final f = File(p.join(root, sourceFile ?? key));
      if (!await f.exists()) return;
      final s = await f.readAsString();
      final m = pat.firstMatch(s);
      if (m != null) found[key] = m.group(1)!;
    }

    await probe('lib/core/build_info.dart',
        RegExp(r"appVersion\s*=\s*'([0-9.]+)'"));
    await probe('pubspec.yaml', RegExp(r'version:\s*([0-9.]+)'));
    await probe(
        'android/app/src/main/res/values/strings.xml',
        RegExp(r'课程图谱与数字孪生v([0-9.]+)'));
    await probe('windows/CMakeLists.txt',
        RegExp(r'BINARY_OUTPUT_NAME\s+"课程图谱与数字孪生v([0-9.]+)"'));
    await probe('windows/runner/main.cpp',
        RegExp(r'window\.Create\(L"课程图谱与数字孪生v([0-9.]+)"'));
    // Runner.rc 有 3 处版本号字段（FileDescription/OriginalFilename/ProductName），
    // 必须**全部**对齐。早期只 probe ProductName，导致其它两处的回归 bug 不会被
    // verifyConsistency 抓到。这里独立 probe 三处。
    await probe('windows/runner/Runner.rc',
        RegExp(r'FileDescription",\s*"课程图谱与数字孪生v(\d+\.\d+\.\d+)'));
    await probe('windows/runner/Runner.rc#OriginalFilename',
        RegExp(r'OriginalFilename",\s*"课程图谱与数字孪生v(\d+\.\d+\.\d+)'),
        sourceFile: 'windows/runner/Runner.rc');
    await probe('windows/runner/Runner.rc#ProductName',
        RegExp(r'ProductName",\s*"课程图谱与数字孪生v(\d+\.\d+\.\d+)'),
        sourceFile: 'windows/runner/Runner.rc');
    await probe('web/index.html', RegExp(r'<title>课程图谱与数字孪生v([0-9.]+)'));
    await probe('web/manifest.json',
        RegExp(r'"name":\s*"课程图谱与数字孪生v([0-9.]+)'));
    await probe('ohos/AppScope/app.json5',
        RegExp(r'"versionName":\s*"([0-9.]+)"'));

    final unique = found.values.toSet();
    return {
      'found': found,
      'isConsistent': unique.length == 1,
      'expectedVersion': unique.length == 1 ? unique.first : null,
    };
  }
}
