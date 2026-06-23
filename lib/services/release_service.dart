/// 构建发布编排服务 — 把 4 端构建 + 打包 + git 双推 + 双仓库 Release + gh-pages
/// 串成一条流水线。每步通过 [logStream] 实时输出日志给 admin UI。
///
/// **运行场景**：仅装了完整工具链的 dev 机（Flutter SDK / Android SDK /
/// DevEco Studio / Git / gh CLI / Python+requests）。生产 EXE 跑不通。
///
/// **设计取舍**：
/// - Windows EXE 不能在自己运行时构建自己（LNK1104），admin 须先在
///   PowerShell 跑 `flutter build windows --release`。本服务只检测 EXE 是否
///   存在 + 版本号匹配。
/// - 凭证从 [SettingsService.getReleaseGithubPat] / Gitee Token 读取。
/// - 进程模型：[Process.start] + UTF-8 stdout 流（参考
///   feedback_manage_page.dart:583）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/build_info.dart';
import '../core/error_handler.dart';
import 'settings_service.dart';
import 'version_bump_service.dart';

enum ReleaseStepStatus { pending, running, success, failed, skipped }

class _RunningProcess {
  final int pid;
  final String name;
  final String path;

  const _RunningProcess({
    required this.pid,
    required this.name,
    required this.path,
  });
}

class ReleaseStep {
  final String id;
  final String label;
  ReleaseStepStatus status;
  String? errorMessage;
  Duration? duration;

  ReleaseStep(
      {required this.id,
      required this.label,
      this.status = ReleaseStepStatus.pending});
}

class ReleaseService {
  static const String _brand = BuildInfo.appBrand;

  // ── 常量 ──────────────────────────────────────────────────────
  /// bump 时遇 tag/release 已存在 → 自动 +patch 重试上限。
  /// 超出抛错（防止跑飞到 0.13.30）。
  static const int _kMaxBumpAttempts = 20;

  /// HTTP 调用瞬时 5xx / 网络抖动重试次数。
  static const int _kHttpRetryAttempts = 3;

  /// HTTP 重试退避序列（指数）：1s / 4s / 16s。
  static const List<Duration> _kHttpRetryBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 4),
    Duration(seconds: 16),
  ];

  /// 步骤定义（顺序即执行顺序）。
  static List<ReleaseStep> defaultSteps() => [
        ReleaseStep(id: 'bump', label: '升版（自动 +patch 重发）'),
        ReleaseStep(id: 'check_windows', label: '检查 Windows 构建产物'),
        ReleaseStep(id: 'build_android', label: '构建 Android (apk)'),
        ReleaseStep(id: 'build_web', label: '构建 Web (--base-href /mad-fd/)'),
        ReleaseStep(id: 'build_ohos', label: '构建 HarmonyOS (hap)'),
        ReleaseStep(id: 'pack_zips', label: '打包 4 端 zip + ASCII alias'),
        ReleaseStep(id: 'git_push', label: 'git 提交 + tag + 双推'),
        ReleaseStep(id: 'create_releases', label: '创建 GitHub + Gitee Release'),
        ReleaseStep(id: 'upload_assets', label: '上传 Release 资产（双仓）'),
        ReleaseStep(id: 'deploy_ghpages', label: '部署 gh-pages'),
      ];

  final List<ReleaseStep> _steps = defaultSteps();

  /// 只读视图（防止外部 mutate）。
  List<ReleaseStep> get steps => List.unmodifiable(_steps);
  final StreamController<String> _logCtrl = StreamController.broadcast();
  final StreamController<void> _stepCtrl = StreamController.broadcast();
  String? _targetVersion;
  bool _running = false;

  Stream<String> get logStream => _logCtrl.stream;
  Stream<void> get stepStream => _stepCtrl.stream;
  String? get targetVersion => _targetVersion;
  bool get isRunning => _running;

  static String windowsReleaseExePath({
    required String projectRoot,
    required String version,
  }) =>
      p.join(
        projectRoot,
        'build',
        'windows',
        'x64',
        'runner',
        'Release',
        '${_brand}v$version.exe',
      );

  void _log(String tag, String msg) {
    if (_logCtrl.isClosed) return;
    _logCtrl.add('[$tag] $msg');
  }

  void _setStep(ReleaseStep s, ReleaseStepStatus status,
      {String? error, Duration? dur}) {
    s.status = status;
    s.errorMessage = error;
    s.duration = dur;
    if (!_stepCtrl.isClosed) _stepCtrl.add(null);
  }

  /// 解析"目标版本"——之前 bump 已设过就用缓存，否则回退到 BuildInfo
  /// 当前版本（admin 跳过 bump 直接重试 build/pack 的场景）。
  Future<String> _resolveTargetVersion() async {
    if (_targetVersion != null) return _targetVersion!;
    return await VersionBumpService.readCurrentVersion();
  }

  /// 跑某一步（[stepId]）；其余步骤不动。
  /// 重试时 admin 点"重试此步"调用本方法。
  Future<bool> runStep(String stepId) async {
    final s = _steps.firstWhere((x) => x.id == stepId);
    final start = DateTime.now();
    _setStep(s, ReleaseStepStatus.running);
    try {
      switch (stepId) {
        case 'bump':
          await _stepBump();
          break;
        case 'check_windows':
          await _stepCheckWindows();
          break;
        case 'build_android':
          await _stepBuildAndroid();
          break;
        case 'build_web':
          await _stepBuildWeb();
          break;
        case 'build_ohos':
          await _stepBuildOhos();
          break;
        case 'pack_zips':
          await _stepPackZips();
          break;
        case 'git_push':
          await _stepGitPush();
          break;
        case 'create_releases':
          await _stepCreateReleases();
          break;
        case 'upload_assets':
          await _stepUploadAssets();
          break;
        case 'deploy_ghpages':
          await _stepDeployGhPages();
          break;
        default:
          throw StateError('未知步骤：$stepId');
      }
      _setStep(s, ReleaseStepStatus.success,
          dur: DateTime.now().difference(start));
      return true;
    } catch (e, st) {
      _log(stepId, 'FAIL: $e');
      _log(stepId, st.toString().split('\n').take(5).join('\n'));
      _setStep(s, ReleaseStepStatus.failed,
          error: '$e', dur: DateTime.now().difference(start));
      return false;
    }
  }

  /// 一键发布全流程：从 [fromStepId]（默认 'bump'）开始顺序跑，
  /// 任意一步失败则后续 mark skipped。
  Future<bool> runAll({String? fromStepId}) async {
    if (_running) {
      _log('orch', '已在运行，忽略重复启动');
      return false;
    }
    _running = true;
    try {
      // 起始 index：fromStepId 指定的步骤（默认 0）
      final fromIdx =
          fromStepId == null ? 0 : _steps.indexWhere((s) => s.id == fromStepId);
      if (fromIdx < 0) {
        _log('orch', '未知 fromStepId: $fromStepId');
        return false;
      }

      // 重置 fromIdx 之后的所有步骤为 pending（含本身）。
      // **不动 fromIdx 之前的步骤** — 之前 success/failed 都保持，
      // 避免回退覆盖 admin 之前的进度。
      for (var i = fromIdx; i < _steps.length; i++) {
        if (_steps[i].status != ReleaseStepStatus.running) {
          _setStep(_steps[i], ReleaseStepStatus.pending);
        }
      }

      var allOk = true;
      for (var i = fromIdx; i < _steps.length; i++) {
        final s = _steps[i];
        if (s.status == ReleaseStepStatus.success) continue;
        if (!allOk) {
          _setStep(s, ReleaseStepStatus.skipped);
          continue;
        }
        final ok = await runStep(s.id);
        if (!ok) allOk = false;
      }
      return allOk;
    } finally {
      _running = false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // Step 实现
  // ════════════════════════════════════════════════════════════════

  Future<void> _stepBump() async {
    final cur = await VersionBumpService.readCurrentVersion();
    _log('bump', '当前版本：$cur');
    final githubRepo = await SettingsService.getReleaseGithubRepo();
    final pat = await SettingsService.getReleaseGithubPat();

    // 起始版本：当前 +1
    var target = VersionBumpService.bumpPatch(cur);

    // 冲突检测：tag 已存在 / GitHub Release 已存在 → 继续 +patch。
    // 超过 [_kMaxBumpAttempts] 次仍冲突就抛错，防止数字飞到不合理值。
    var bumped = false;
    for (var i = 0; i < _kMaxBumpAttempts; i++) {
      final hasTag = await _gitTagExists('v$target');
      final hasRelease = pat.isNotEmpty
          ? await _githubReleaseExists(githubRepo, 'v$target', pat)
          : false;
      if (!hasTag && !hasRelease) {
        bumped = true;
        break;
      }
      _log('bump',
          'v$target 已存在（tag=$hasTag, github_release=$hasRelease），继续 +1');
      target = VersionBumpService.bumpPatch(target);
    }

    if (!bumped) {
      throw StateError(
          '$_kMaxBumpAttempts 次 +patch 仍冲突，最后尝试 v$target — 检查仓库 tag/release');
    }

    _targetVersion = target;
    _log('bump', '目标版本：$cur → $target');
    final logs = await VersionBumpService.applyVersion(target);
    for (final l in logs) {
      _log('bump', l);
    }

    final verify = await VersionBumpService.verifyConsistency();
    if (verify['isConsistent'] != true) {
      throw StateError('版本号不一致：${verify['found']}');
    }
    _log('bump', '✓ 9 个文件已同步到 v$target');
  }

  Future<void> _stepCheckWindows() async {
    final ver = await _resolveTargetVersion();
    final exe = File(windowsReleaseExePath(
      projectRoot: VersionBumpService.projectRoot,
      version: ver,
    ));
    final running = await _findRunningProcessesByPath(exe.path);
    if (running.isNotEmpty) {
      final details =
          running.map((p) => 'PID ${p.pid} ${p.name} (${p.path})').join('\n');
      throw StateError('Windows 发布程序仍在运行，构建/打包前请先关闭：\n$details\n\n'
          '关闭后重新执行：\n  flutter build windows --release');
    }
    if (!await exe.exists()) {
      throw StateError(
          'Windows EXE 不存在：${exe.path}\n\nadmin 请先在 PowerShell 终端跑：\n'
          '  flutter build windows --release\n\n（应用内不能构建 Windows——'
          'EXE 自我编译会 LNK1104）');
    }
    _log('check_windows',
        '✓ ${exe.path} 已就绪 (${(await exe.length()) ~/ 1024} KB)');
  }

  Future<void> _stepBuildAndroid() async {
    await _runShell('flutter', ['build', 'apk', '--release'],
        tag: 'build:android', timeout: const Duration(minutes: 15));
  }

  Future<void> _stepBuildWeb() async {
    // base-href 必须 /mad-fd/ 且斜杠尾，否则 GitHub Pages 资源 404。
    // bash 的 MSYS 不需要在这里管——Process.start 直接调 flutter，不经 shell 转换。
    await _runShell(
      'flutter',
      ['build', 'web', '--release', '--base-href', '/mad-fd/'],
      tag: 'build:web',
      timeout: const Duration(minutes: 10),
    );
  }

  Future<void> _stepBuildOhos() async {
    final root = VersionBumpService.projectRoot;
    final bat = File(p.join(root, 'build_ohos.bat'));
    if (!await bat.exists()) {
      throw StateError('build_ohos.bat 不存在，无法构建 HarmonyOS');
    }
    await _runShell(bat.path, [],
        tag: 'build:ohos', timeout: const Duration(minutes: 20));
  }

  Future<void> _stepPackZips() async {
    final root = VersionBumpService.projectRoot;
    final ver = await _resolveTargetVersion();
    final distDir = Directory(p.join(root, 'dist'));
    if (!await distDir.exists()) await distDir.create();

    // 清掉旧版本号 zip（避免 dist/ 残留多版本）
    await for (final f in distDir.list()) {
      if (f is File && f.path.endsWith('.zip')) {
        final nm = p.basename(f.path);
        if (nm.contains('v0.') && !nm.contains('v$ver')) {
          await f.delete();
          _log('pack', '清理旧 zip: $nm');
        }
      }
    }

    final ps1 = p.join(root, 'scripts', 'pack_dist_zip.ps1');

    // Windows zip：直接打 build/windows/x64/runner/Release/
    await _runShell(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          ps1,
          '-SourceDir',
          p.join(root, 'build', 'windows', 'x64', 'runner', 'Release'),
          '-ZipPath',
          p.join(distDir.path, '$_brand+windows+v$ver.zip'),
        ],
        tag: 'pack:windows');

    // Android / Web / HarmonyOS：先在 build/_pack/ 各端组装 staging dir + README
    final pack = Directory(p.join(root, 'build', '_pack'));
    if (await pack.exists()) await pack.delete(recursive: true);
    await pack.create(recursive: true);

    // Android
    final androidDir = Directory(p.join(pack.path, 'android'));
    await androidDir.create();
    await File(p.join(
            root, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'))
        .copy(p.join(androidDir.path, '$_brand' 'v$ver.apk'));
    await _writeReadme(p.join(androidDir.path, '安装说明.txt'), 'android', ver);
    await _runShell(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          ps1,
          '-SourceDir',
          androidDir.path,
          '-ZipPath',
          p.join(distDir.path, '$_brand+android+v$ver.zip'),
        ],
        tag: 'pack:android');

    // Web
    final webDir = Directory(p.join(pack.path, 'web'));
    await webDir.create();
    await _copyDir(Directory(p.join(root, 'build', 'web')), webDir);
    await _writeReadme(p.join(webDir.path, '启动说明.txt'), 'web', ver);
    await _runShell(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          ps1,
          '-SourceDir',
          webDir.path,
          '-ZipPath',
          p.join(distDir.path, '$_brand+web+v$ver.zip'),
        ],
        tag: 'pack:web');

    // HarmonyOS
    final hapDir = Directory(p.join(pack.path, 'harmonyos'));
    await hapDir.create();
    final hapSrc = File(p.join(root, 'ohos', 'entry', 'build', 'default',
        'outputs', 'default', 'entry-default-signed.hap'));
    if (!await hapSrc.exists()) {
      throw StateError('HAP 不存在：${hapSrc.path}');
    }
    await hapSrc.copy(p.join(hapDir.path, '$_brand' 'v$ver.hap'));
    await _writeReadme(p.join(hapDir.path, '安装说明.txt'), 'harmonyos', ver);
    await _runShell(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          ps1,
          '-SourceDir',
          hapDir.path,
          '-ZipPath',
          p.join(distDir.path, '$_brand+harmonyos+v$ver.zip'),
        ],
        tag: 'pack:harmonyos');

    // ASCII 别名（Windows 260 字符路径限制兜底）
    final winZip = File(p.join(distDir.path, '$_brand+windows+v$ver.zip'));
    final asciiAlias = File(p.join(distDir.path, 'CKGDT-windows-v$ver.zip'));
    if (await asciiAlias.exists()) await asciiAlias.delete();
    await winZip.copy(asciiAlias.path);
    _log('pack', '✓ ASCII 别名: ${p.basename(asciiAlias.path)}');

    // 清理 staging
    await pack.delete(recursive: true);
  }

  Future<void> _stepGitPush() async {
    final ver = await _resolveTargetVersion();
    final root = VersionBumpService.projectRoot;

    // 1. 添加版本号相关文件 + 仅这些（避免误传 dist 大文件 / 学生同步副作用）
    final filesToAdd = [
      'lib/core/build_info.dart',
      'lib/l10n/app_zh.arb',
      'pubspec.yaml',
      'android/app/src/main/res/values/strings.xml',
      'windows/CMakeLists.txt',
      'windows/runner/main.cpp',
      'windows/runner/Runner.rc',
      'web/index.html',
      'web/manifest.json',
      'ohos/AppScope/app.json5',
    ];
    await _runShell('git', ['add', ...filesToAdd], tag: 'git', cwd: root);

    // 2. commit（即使无改动也允许，例如 admin 重试 git_push）
    await _runShell(
      'git',
      ['commit', '-m', 'release: v$ver — 一键发布中心自动升版', '--allow-empty'],
      tag: 'git',
      cwd: root,
    );

    // 3. tag
    await _runShell('git', ['tag', '-d', 'v$ver'],
        tag: 'git', cwd: root, allowFail: true);
    await _runShell('git', ['tag', '-a', 'v$ver', '-m', 'release: v$ver'],
        tag: 'git', cwd: root);

    // 4. push origin / github master + tag（Gitee 易撞学生 push，rebase）
    await _runShell('git', ['fetch', 'origin'], tag: 'git', cwd: root);
    await _runShell('git', ['pull', '--rebase', 'origin', 'master'],
        tag: 'git', cwd: root, allowFail: true);
    await _runShell('git', ['push', 'origin', 'master'], tag: 'git', cwd: root);
    await _runShell('git', ['push', 'origin', 'v$ver', '--force'],
        tag: 'git', cwd: root);

    // GitHub 是否配了 remote？没有就跳
    final remotesProc = await Process.run('git', ['remote'],
        workingDirectory: root, runInShell: true);
    final remotes = (remotesProc.stdout as String).trim().split('\n');
    if (remotes.contains('github')) {
      await _runShell('git', ['push', 'github', 'master', '--force-with-lease'],
          tag: 'git', cwd: root);
      await _runShell('git', ['push', 'github', 'v$ver', '--force'],
          tag: 'git', cwd: root);
    } else {
      _log('git', '! 未配置 github remote，跳过 GitHub push');
    }
  }

  Future<void> _stepCreateReleases() async {
    final ver = await _resolveTargetVersion();
    final notes = _releaseNotes(ver);
    final pat = await SettingsService.getReleaseGithubPat();
    final giteeToken = await SettingsService.getReleaseGiteeToken();
    final githubRepo = await SettingsService.getReleaseGithubRepo();
    final giteeRepo = await SettingsService.getReleaseGiteeRepo();

    // GitHub
    if (pat.isEmpty) {
      _log('release', '! GitHub PAT 未配置，跳过 GitHub Release 创建');
    } else {
      final r = await _withHttpRetry(
        'github create release',
        () => http.post(
          Uri.parse('https://api.github.com/repos/$githubRepo/releases'),
          headers: {
            'Authorization': 'Bearer $pat',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
          body: jsonEncode({
            'tag_name': 'v$ver',
            'name': 'v$ver',
            'body': notes,
            'target_commitish': 'master',
          }),
        ),
        // 201 创建 / 422 已存在 都是确定结果；5xx 才重试
        isSuccess: (r) => r.statusCode < 500,
      );
      if (r.statusCode == 201 || r.statusCode == 422) {
        // 422 = already exists（发版重试场景）
        _log('release', 'GitHub: HTTP ${r.statusCode}（已存在则忽略）');
      } else {
        throw StateError('GitHub Release 创建失败 [${r.statusCode}]: ${r.body}');
      }
    }

    // Gitee
    if (giteeToken.isEmpty) {
      _log('release', '! Gitee Token 未配置，跳过 Gitee Release 创建');
    } else {
      final r = await _withHttpRetry(
        'gitee create release',
        () => http.post(
          Uri.parse('https://gitee.com/api/v5/repos/$giteeRepo/releases'),
          headers: {'Content-Type': 'application/json;charset=UTF-8'},
          body: utf8.encode(jsonEncode({
            'access_token': giteeToken,
            'tag_name': 'v$ver',
            'name': 'v$ver',
            'body': notes,
            'target_commitish': 'master',
            'prerelease': false,
          })),
        ),
        isSuccess: (r) => r.statusCode < 500,
      );
      if (r.statusCode == 201) {
        _log('release', 'Gitee: 创建成功');
      } else if (r.body.contains('已存在') ||
          r.statusCode == 400 ||
          r.statusCode == 422) {
        _log('release', 'Gitee: 已存在（HTTP ${r.statusCode}），跳过');
      } else {
        throw StateError('Gitee Release 创建失败 [${r.statusCode}]: ${r.body}');
      }
    }
  }

  Future<void> _stepUploadAssets() async {
    final ver = await _resolveTargetVersion();
    final root = VersionBumpService.projectRoot;
    final distDir = Directory(p.join(root, 'dist'));

    final assets = <String, String>{
      // 中文名（Gitee 用，GitHub 自动 ASCII 化）
      '$_brand+windows+v$ver.zip': 'CKGDT-windows-v$ver.zip',
      '$_brand+android+v$ver.zip': 'CKGDT-android-v$ver.zip',
      '$_brand+web+v$ver.zip': 'CKGDT-web-v$ver.zip',
      '$_brand+harmonyos+v$ver.zip': 'CKGDT-harmonyos-v$ver.zip',
      'CKGDT-windows-v$ver.zip': 'CKGDT-windows-v$ver.zip',
      '一键安装-Windows.bat': 'install-windows.bat',
      '安装手册.pdf': 'install-manual.pdf',
    };

    // 检查源文件
    final missing = <String>[];
    for (final src in assets.keys) {
      if (!await File(p.join(distDir.path, src)).exists()) {
        // 部分 optional：bat / pdf
        if (src.endsWith('.bat') || src.endsWith('.pdf')) continue;
        missing.add(src);
      }
    }
    if (missing.isNotEmpty) {
      throw StateError('缺失资产：${missing.join(", ")}');
    }

    // GitHub: gh CLI（必需）
    final pat = await SettingsService.getReleaseGithubPat();
    final githubRepo = await SettingsService.getReleaseGithubRepo();
    if (pat.isEmpty) {
      _log('upload', '! GitHub PAT 未配置，跳过 GitHub 资产上传');
    } else {
      // 用 ASCII 名（GitHub 默认会过滤非 ASCII，stripping 掉中文段）
      final tmpDir = Directory(p.join(root, 'build', '_gh_assets'));
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      await tmpDir.create(recursive: true);
      final filesToUpload = <String>[];
      for (final entry in assets.entries) {
        final src = File(p.join(distDir.path, entry.key));
        if (!await src.exists()) continue;
        final ascii = File(p.join(tmpDir.path, entry.value));
        await src.copy(ascii.path);
        filesToUpload.add(ascii.path);
      }
      // gh release upload（覆盖式 --clobber，避免重发版冲突）
      await _runShell(
        'gh',
        [
          'release',
          'upload',
          'v$ver',
          '--repo',
          githubRepo,
          '--clobber',
          ...filesToUpload,
        ],
        tag: 'upload:github',
        env: {'GITHUB_TOKEN': pat},
        timeout: const Duration(minutes: 10),
      );
      await tmpDir.delete(recursive: true);
    }

    // Gitee: 调 scripts/gitee_upload_assets.py（已规避 + → %2B + UTF-8 名）
    final giteeToken = await SettingsService.getReleaseGiteeToken();
    if (giteeToken.isEmpty) {
      _log('upload', '! Gitee Token 未配置，跳过 Gitee 资产上传');
    } else {
      // 直接调内置上传函数，避免每次复制 .py 路径硬编码
      await _uploadAssetsToGitee(ver, distDir.path);
    }
  }

  Future<void> _stepDeployGhPages() async {
    final root = VersionBumpService.projectRoot;
    final ver = await _resolveTargetVersion();
    final remotesProc = await Process.run('git', ['remote'],
        workingDirectory: root, runInShell: true);
    final remotes = (remotesProc.stdout as String).trim().split('\n');
    if (!remotes.contains('github')) {
      _log('ghpages', '! 未配置 github remote，跳过 gh-pages 部署');
      return;
    }

    final deployDir = Directory(p.join(root, 'build', '_gh-pages-deploy'));
    if (await deployDir.exists()) await deployDir.delete(recursive: true);
    await deployDir.create(recursive: true);
    await _copyDir(Directory(p.join(root, 'build', 'web')), deployDir);

    await _runShell('git', ['init', '-q', '-b', 'gh-pages'],
        tag: 'ghpages', cwd: deployDir.path);
    await _runShell('git', ['config', 'core.longpaths', 'true'],
        tag: 'ghpages', cwd: deployDir.path);
    await _runShell('git', ['add', '-A'], tag: 'ghpages', cwd: deployDir.path);
    await _runShell(
      'git',
      [
        '-c',
        'user.email=ldl@github',
        '-c',
        'user.name=ldl',
        'commit',
        '-q',
        '-m',
        'deploy: web v$ver base=/mad-fd/',
      ],
      tag: 'ghpages',
      cwd: deployDir.path,
    );
    await _runShell(
      'git',
      ['remote', 'add', 'origin', 'git@github.com:dll/mad-fd.git'],
      tag: 'ghpages',
      cwd: deployDir.path,
    );
    await _runShell(
      'git',
      ['push', '-u', '--force', 'origin', 'gh-pages'],
      tag: 'ghpages',
      cwd: deployDir.path,
    );

    // 清理（占用解除后）
    try {
      await deployDir.delete(recursive: true);
    } catch (e, st) {
      swallowDebug(e, tag: 'ReleaseService._deployGhPages', stack: st);
      _log('ghpages', '! 清理临时目录失败（不致命，下次启动重试）');
    }
  }

  // ════════════════════════════════════════════════════════════════
  // 工具函数
  // ════════════════════════════════════════════════════════════════

  Future<void> _runShell(
    String cmd,
    List<String> args, {
    required String tag,
    String? cwd,
    Duration? timeout,
    Map<String, String>? env,
    bool allowFail = false,
  }) async {
    final root = VersionBumpService.projectRoot;
    final wd = cwd ?? root;
    _log(tag, '\$ $cmd ${args.join(" ")}');
    final proc = await Process.start(
      cmd,
      args,
      workingDirectory: wd,
      runInShell: true,
      environment: env,
      includeParentEnvironment: true,
    );
    final subs = <StreamSubscription>[];
    subs.add(proc.stdout.transform(utf8.decoder).listen((chunk) {
      for (final line in chunk.split('\n')) {
        if (line.trim().isNotEmpty) _log(tag, line.trimRight());
      }
    }));
    subs.add(proc.stderr.transform(utf8.decoder).listen((chunk) {
      for (final line in chunk.split('\n')) {
        if (line.trim().isNotEmpty) _log(tag, '[!] ${line.trimRight()}');
      }
    }));

    int code;
    if (timeout != null) {
      try {
        code = await proc.exitCode.timeout(timeout);
      } on TimeoutException {
        proc.kill();
        throw StateError('$cmd 超时（${timeout.inMinutes} 分钟）');
      }
    } else {
      code = await proc.exitCode;
    }
    for (final s in subs) {
      await s.cancel();
    }
    if (code != 0 && !allowFail) {
      throw StateError('$cmd 退出码 $code');
    }
  }

  Future<List<_RunningProcess>> _findRunningProcessesByPath(
      String targetPath) async {
    if (!Platform.isWindows) return const [];
    final escaped = targetPath.replaceAll("'", "''");
    final script = '''
\$target = [System.IO.Path]::GetFullPath('$escaped')
\$matches = @(Get-Process | ForEach-Object {
  try {
    if (\$_.Path -eq \$target) {
      [pscustomobject]@{ Id = \$_.Id; ProcessName = \$_.ProcessName; Path = \$_.Path }
    }
  } catch {}
})
\$matches | ConvertTo-Json -Compress
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-Command', script],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      _log('check_windows', '! 进程占用检测失败：${result.stderr}');
      return const [];
    }
    final raw = (result.stdout as String).trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      final items = decoded is List ? decoded : [decoded];
      return [
        for (final item in items)
          if (item is Map)
            _RunningProcess(
              pid: (item['Id'] as num?)?.toInt() ?? 0,
              name: item['ProcessName']?.toString() ?? '',
              path: item['Path']?.toString() ?? '',
            )
      ];
    } catch (e) {
      _log('check_windows', '! 进程占用检测结果解析失败：$e');
      return const [];
    }
  }

  Future<bool> _gitTagExists(String tag) async {
    final root = VersionBumpService.projectRoot;
    final r = await Process.run('git', ['tag', '-l', tag],
        workingDirectory: root, runInShell: true);
    return (r.stdout as String).trim() == tag;
  }

  /// HTTP 重试封装：5xx 或网络异常时按 [_kHttpRetryBackoff] 退避重试。
  /// 4xx 不重试（业务错误）；2xx 直接返回；最后一次失败抛错。
  /// **谁该用**：所有发到 GitHub / Gitee 的请求。它们偶发 502/503/504 + 突然 RST。
  Future<T> _withHttpRetry<T>(
    String label,
    Future<T> Function() action, {
    bool Function(T)? isSuccess,
  }) async {
    for (var i = 0; i < _kHttpRetryAttempts; i++) {
      try {
        final r = await action();
        if (isSuccess == null || isSuccess(r)) return r;
        // isSuccess=false 视同瞬时错误，重试
        if (i < _kHttpRetryAttempts - 1) {
          _log('http',
              '$label: 上游返回非成功，${_kHttpRetryBackoff[i].inSeconds}s 后重试');
          await Future<void>.delayed(_kHttpRetryBackoff[i]);
          continue;
        }
        return r;
      } catch (e) {
        if (i < _kHttpRetryAttempts - 1) {
          _log(
              'http', '$label 异常 ($e)，${_kHttpRetryBackoff[i].inSeconds}s 后重试');
          await Future<void>.delayed(_kHttpRetryBackoff[i]);
          continue;
        }
        rethrow;
      }
    }
    throw StateError('$label 重试 $_kHttpRetryAttempts 次仍失败');
  }

  Future<bool> _githubReleaseExists(String repo, String tag, String pat) async {
    final r = await _withHttpRetry(
      'github release tags/$tag',
      () => http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/tags/$tag'),
        headers: {
          'Authorization': 'Bearer $pat',
          'Accept': 'application/vnd.github+json',
        },
      ),
      // 200 = 存在, 404 = 不存在，都是确定结果，不需要重试；5xx 视为瞬时
      isSuccess: (r) => r.statusCode < 500,
    );
    return r.statusCode == 200;
  }

  Future<void> _uploadAssetsToGitee(String ver, String distPath) async {
    final giteeToken = await SettingsService.getReleaseGiteeToken();
    final giteeRepo = await SettingsService.getReleaseGiteeRepo();
    // 拿 release id（最近一个 tag = ver 的）
    final r = await _withHttpRetry(
      'gitee get release by tag',
      () => http.get(Uri.parse(
          'https://gitee.com/api/v5/repos/$giteeRepo/releases/tags/v$ver?access_token=$giteeToken')),
      isSuccess: (r) => r.statusCode < 500,
    );
    if (r.statusCode != 200) {
      throw StateError('Gitee 取 release id 失败 [${r.statusCode}]: ${r.body}');
    }
    final rel = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final releaseId = rel['id'] as int;

    // 删旧资产（重发版）
    final list = await _withHttpRetry(
      'gitee list attach_files',
      () => http.get(Uri.parse(
          'https://gitee.com/api/v5/repos/$giteeRepo/releases/$releaseId/attach_files?access_token=$giteeToken')),
      isSuccess: (r) => r.statusCode < 500,
    );
    if (list.statusCode == 200) {
      final files = jsonDecode(utf8.decode(list.bodyBytes)) as List;
      for (final a in files) {
        final id = a['id'];
        final del = await _withHttpRetry(
          'gitee delete attach_file',
          () => http.delete(Uri.parse(
              'https://gitee.com/api/v5/repos/$giteeRepo/releases/$releaseId/attach_files/$id?access_token=$giteeToken')),
          isSuccess: (r) => r.statusCode < 500,
        );
        _log('upload:gitee', '删除旧资产 ${a['name']}: ${del.statusCode}');
      }
    }

    // 上传新资产 — 大文件 multipart 是最容易遭遇 5xx 的；retry 价值最大。
    final assets = <String>[
      '$_brand+windows+v$ver.zip',
      '$_brand+android+v$ver.zip',
      '$_brand+web+v$ver.zip',
      '$_brand+harmonyos+v$ver.zip',
      'CKGDT-windows-v$ver.zip',
      '一键安装-Windows.bat',
      '安装手册.pdf',
    ];
    for (final name in assets) {
      final f = File(p.join(distPath, name));
      if (!await f.exists()) {
        _log('upload:gitee', '跳过（不存在）: $name');
        continue;
      }
      final size = await f.length();
      // 重试时 MultipartRequest 不能复用（stream 已 drain），每次新建一份
      final result = await _withHttpRetry(
        'gitee upload $name',
        () async {
          final req = http.MultipartRequest(
            'POST',
            Uri.parse(
                'https://gitee.com/api/v5/repos/$giteeRepo/releases/$releaseId/attach_files?access_token=$giteeToken'),
          );
          // **关键**：把 + 预编码成 %2B（Gitee 服务端会把 multipart filename 当 URL 解码）
          final submitName = name.replaceAll('+', '%2B');
          req.files.add(http.MultipartFile(
            'file',
            f.openRead(),
            size,
            filename: submitName,
          ));
          final streamed = await req.send();
          final body = await streamed.stream.bytesToString();
          return (status: streamed.statusCode, body: body);
        },
        isSuccess: (r) => r.status < 500,
      );
      if (result.status == 201) {
        _log('upload:gitee',
            '✓ $name (${(size / 1024 / 1024).toStringAsFixed(1)} MB)');
      } else {
        throw StateError(
            'Gitee 上传 $name 失败 [${result.status}]: ${result.body}');
      }
    }
  }

  Future<void> _writeReadme(String path, String platform, String ver) async {
    const defaults = '''
默认账号：
- 管理员：419116 / 419116
- 学生：学号最后 6 位作为密码（如 2023210123 → 密码 210123）
''';
    String content;
    switch (platform) {
      case 'android':
        content = '''
$_brand — Android 安装说明
========================================
版本：v$ver
包名：cn.edu.chzu.madkgdt
最低 Android 版本：5.0 (API 21)

安装：
1. 在手机设置中允许"未知来源"安装
2. 把 .apk 文件传到手机，点击安装
3. 首次启动会自动复制种子数据库（约 5-10 秒）

$defaults
''';
        break;
      case 'web':
        content = '''
$_brand — Web 启动说明
========================================
版本：v$ver

本目录是 Flutter Web 编译产物（base href: /mad-fd/），需要本地 HTTP 服务器才能访问：

方法 1（Python，推荐）：
  cd 本目录
  python -m http.server 8080
  浏览器访问 http://localhost:8080/

方法 2（Node serve）：
  npm install -g serve
  serve -l 8080 .
  浏览器访问 http://localhost:8080/

方法 3（在线访问）：
  https://dll.github.io/mad-fd/

$defaults
''';
        break;
      case 'harmonyos':
        content = '''
$_brand — HarmonyOS HAP 安装说明
============================================
版本：v$ver
包格式：HAP (OpenHarmony 调试签名)
架构：arm64-v8a

⚠ 重要：仅可装到鸿蒙真机（任何商用 NEXT 设备都是 arm64）
        不兼容华为模拟器（x86_64 镜像）。装模拟器报 abi 不匹配错误。

安装：
1. 真机打开"开发者模式"（设置 → 关于手机 → 连点版本号）
2. 用 hdc 工具：hdc install ${_brand}v$ver.hap
3. 或者用 DevEco Studio 安装

$defaults
''';
        break;
      default:
        content = '版本：v$ver\n\n$defaults';
    }
    await File(path).writeAsString(content);
  }

  String _releaseNotes(String ver) {
    return '''
# v$ver

通过"构建发布中心"一键发布。

## 资产说明

| 端 | 包名 | 大小 |
|----|------|------|
| Windows | $_brand+windows+v$ver.zip | ~66 MB |
| Android | $_brand+android+v$ver.zip | ~76 MB |
| Web | $_brand+web+v$ver.zip | ~39 MB |
| HarmonyOS | $_brand+harmonyos+v$ver.zip | ~39 MB |
| 一键安装 | 一键安装-Windows.bat | < 2 KB |
| 安装手册 | 安装手册.pdf | ~4 MB |

> Windows 端额外提供 ASCII 别名包 `CKGDT-windows-v$ver.zip`，用于绕开 Windows 260 字符路径限制。
> 鸿蒙 HAP 用 OpenHarmony 调试签名，仅可装到鸿蒙真机（arm64-v8a），不兼容华为模拟器（x86_64）。

## Web 在线访问

部署在 GitHub Pages：https://dll.github.io/mad-fd/
''';
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await for (final e in src.list(recursive: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        final sub = Directory(p.join(dst.path, name));
        await sub.create();
        await _copyDir(e, sub);
      } else if (e is File) {
        await e.copy(p.join(dst.path, name));
      }
    }
  }

  void dispose() {
    _logCtrl.close();
    _stepCtrl.close();
  }
}
