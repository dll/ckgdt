import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// APK 启动服务
///
/// 完整流程：
/// 1. 检测 ADB / emulator 是否可用
/// 2. 检查是否有已连接设备，无则启动本地模拟器
/// 3. 等待设备就绪（boot_completed == 1）
/// 4. 读取 APK 包名 / 入口 Activity（aapt / aapt2）
/// 5. 安装 APK（adb install -r）
/// 6. 启动 APK（adb shell am start -n package/activity）
class ApkLauncherService {
  // ── 状态：保存最近一次启动的模拟器进程（用于停止）
  Process? _runningEmulator;
  String? _runningAvd;

  // ════════════════════════════════════════════════════════════════
  // 环境检测
  // ════════════════════════════════════════════════════════════════

  /// 检测 ADB 是否在 PATH 中
  Future<bool> isAdbAvailable() async {
    try {
      final r = await Process.run('where', ['adb'], runInShell: true);
      return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 检测 emulator 命令是否可用
  Future<bool> isEmulatorAvailable() async {
    try {
      final r = await Process.run('where', ['emulator'], runInShell: true);
      return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 检测 aapt / aapt2 是否可用（用于读取 APK 包名/入口）
  Future<String?> detectAapt() async {
    for (final exe in ['aapt2', 'aapt']) {
      try {
        final r = await Process.run('where', [exe], runInShell: true);
        if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
          return exe;
        }
      } catch (_) {}
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════
  // 模拟器管理
  // ════════════════════════════════════════════════════════════════

  /// 列出所有 AVD（Android Virtual Device）
  Future<List<String>> listAvds() async {
    try {
      final r = await Process.run('emulator', ['-list-avds'], runInShell: true);
      if (r.exitCode != 0) return [];
      final out = (r.stdout as String).trim();
      if (out.isEmpty) return [];
      // 第一行通常是 "Available Android Virtual Devices:" 或 "INFO..." 之类
      return out
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) =>
              s.isNotEmpty &&
              !s.toLowerCase().contains('available') &&
              !s.startsWith('INFO') &&
              !s.startsWith('WARNING'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 启动指定 AVD
  Future<bool> startEmulator(String avdName) async {
    try {
      // emulator -avd <name> -no-snapshot-load -no-window
      // -no-window 避免阻塞（在无头服务器上也有用）
      _runningEmulator = await Process.start(
        'emulator',
        ['-avd', avdName, '-no-snapshot-load', '-no-boot-anim'],
        runInShell: true,
      );
      _runningAvd = avdName;
      return true;
    } catch (e) {
      debugPrint('startEmulator failed: $e');
      return false;
    }
  }

  /// 停止最近启动的模拟器
  Future<void> stopEmulator() async {
    try {
      _runningEmulator?.kill();
    } catch (_) {}
    _runningEmulator = null;
    _runningAvd = null;
  }

  String? get runningAvd => _runningAvd;

  // ════════════════════════════════════════════════════════════════
  // 设备管理
  // ════════════════════════════════════════════════════════════════

  /// 列出已连接设备（adb devices）
  Future<List<String>> listDevices() async {
    try {
      final r = await Process.run('adb', ['devices'], runInShell: true);
      if (r.exitCode != 0) return [];
      final lines = (r.stdout as String).split(RegExp(r'[\r\n]+'));
      final result = <String>[];
      for (final line in lines) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('List of devices') || t.startsWith('*')) {
          continue;
        }
        // 格式: <serial>\t<state>
        final parts = t.split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1] == 'device') {
          result.add(parts[0]);
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// 等待任意设备连接
  Future<bool> waitForDevice({Duration timeout = const Duration(minutes: 2)}) async {
    try {
      final r = await Process.run('adb', ['wait-for-device'], runInShell: true)
          .timeout(timeout);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 等待设备启动完成（boot_completed == 1）
  Future<bool> waitForBoot({Duration timeout = const Duration(minutes: 3)}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      try {
        final r = await Process.run(
          'adb',
          ['shell', 'getprop', 'sys.boot_completed'],
          runInShell: true,
        );
        if ((r.stdout as String).trim() == '1') {
          // 再等几秒让系统服务就绪
          await Future.delayed(const Duration(seconds: 2));
          return true;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  // ════════════════════════════════════════════════════════════════
  // APK 信息读取
  // ════════════════════════════════════════════════════════════════

  /// 从 APK 读取包名和启动 Activity
  /// 返回 (package, activity) 或 null
  Future<({String packageName, String activity})?> getApkInfo(
      String apkPath) async {
    final aapt = await detectAapt();
    if (aapt == null) {
      debugPrint('aapt / aapt2 未找到，无法读取 APK 信息');
      return null;
    }
    try {
      final r = await Process.run(aapt, ['dump', 'badging', apkPath],
          runInShell: true);
      if (r.exitCode != 0) return null;
      final out = r.stdout as String;

      final pkgMatch = RegExp(r"package:\s*name='([^']+)'").firstMatch(out);
      final actMatch = RegExp(r"launchable-activity:\s*name='([^']+)'")
          .firstMatch(out);

      if (pkgMatch != null && actMatch != null) {
        return (
          packageName: pkgMatch.group(1)!,
          activity: actMatch.group(1)!,
        );
      }
    } catch (e) {
      debugPrint('getApkInfo failed: $e');
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════
  // 安装 & 启动
  // ════════════════════════════════════════════════════════════════

  /// 安装 APK（-r 覆盖安装）
  Future<bool> installApk(String apkPath) async {
    try {
      final r = await Process.run('adb', ['install', '-r', apkPath],
          runInShell: true);
      if (r.exitCode == 0) return true;
      debugPrint('adb install failed: ${r.stdout} ${r.stderr}');
      return false;
    } catch (e) {
      debugPrint('installApk failed: $e');
      return false;
    }
  }

  /// 启动 APK
  Future<bool> launchApkActivity(String packageName, String activity) async {
    try {
      final r = await Process.run('adb', [
        'shell',
        'am',
        'start',
        '-n',
        '$packageName/$activity',
      ], runInShell: true);
      return r.exitCode == 0;
    } catch (e) {
      debugPrint('launchApkActivity failed: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // 一键启动（完整流程）
  // ════════════════════════════════════════════════════════════════

  /// 完整流程：检测 → 启动模拟器 → 安装 → 启动
  /// [onProgress] 用于向 UI 反馈当前步骤
  Future<bool> launchApk({
    required String apkPath,
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('检查 ADB...');
    if (!await isAdbAvailable()) {
      onProgress?.call('未找到 ADB，请安装 Android SDK Platform Tools');
      return false;
    }

    // 1. 检查现有设备
    onProgress?.call('检查已连接设备...');
    final devices = await listDevices();
    var hasReadyDevice = false;
    for (final d in devices) {
      // 检查是否 boot 完成
      try {
        final r = await Process.run('adb',
            ['-s', d, 'shell', 'getprop', 'sys.boot_completed'],
            runInShell: true);
        if ((r.stdout as String).trim() == '1') {
          hasReadyDevice = true;
          break;
        }
      } catch (_) {}
    }

    // 2. 无就绪设备 → 启动模拟器
    if (!hasReadyDevice) {
      onProgress?.call('检查模拟器...');
      if (!await isEmulatorAvailable()) {
        onProgress?.call('未找到 emulator 命令，请安装 Android Emulator');
        return false;
      }
      onProgress?.call('列出可用 AVD...');
      final avds = await listAvds();
      if (avds.isEmpty) {
        onProgress?.call('未找到可用 AVD，请先通过 AVD Manager 创建模拟器');
        return false;
      }
      onProgress?.call('启动模拟器: ${avds.first}');
      final ok = await startEmulator(avds.first);
      if (!ok) {
        onProgress?.call('启动模拟器失败');
        return false;
      }
      onProgress?.call('等待设备连接...');
      if (!await waitForDevice()) {
        onProgress?.call('等待设备超时（2分钟）');
        return false;
      }
      onProgress?.call('等待模拟器启动完成...');
      if (!await waitForBoot()) {
        onProgress?.call('模拟器启动超时（3分钟）');
        return false;
      }
    }

    // 3. 读取 APK 信息
    onProgress?.call('读取 APK 信息...');
    final info = await getApkInfo(apkPath);
    if (info == null) {
      onProgress?.call('无法读取 APK 包名/入口（需要 aapt / aapt2）');
      return false;
    }

    // 4. 安装
    onProgress?.call('安装 APK: ${info.packageName}...');
    if (!await installApk(apkPath)) {
      onProgress?.call('安装 APK 失败');
      return false;
    }

    // 5. 启动
    onProgress?.call('启动 APK: ${info.activity}...');
    if (!await launchApkActivity(info.packageName, info.activity)) {
      onProgress?.call('启动 APK 失败');
      return false;
    }

    onProgress?.call('APK 已成功启动');
    return true;
  }
}
