/// Bootstrap-phase file logger.
///
/// 桌面 release 模式下 `debugPrint` 不输出到任何用户可见处（无 console），
/// 数据库初始化等"启动期"问题没有日志可查 → bug 反复修不好。
/// 这个 logger 把日志直接写到 `<exe同级>/logs/mad_init.log`，学生机器复现时直接捞文件。
///
/// 设计原则：
/// - 不能依赖 DatabaseHelper / SettingsService（它们自己可能正在挂）
/// - 写文件失败必须吞，不能反过来把 main() 干掉
/// - 路径优先级：exe 同级 → ApplicationSupport → 退到 debugPrint
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'error_handler.dart';

class InitLogger {
  InitLogger._();

  static File? _file;
  static bool _initialized = false;

  /// 在 main() 第一行调用。失败也不能抛。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) return;

    try {
      final dir = await _resolveLogDir();
      if (dir == null) return;
      final logFile = File(p.join(dir.path, 'mad_init.log'));
      // 单文件超过 1MB 时滚动一次（保留 .old 一份）
      if (await logFile.exists() && await logFile.length() > 1024 * 1024) {
        final old = File(p.join(dir.path, 'mad_init.log.old'));
        if (await old.exists()) await old.delete();
        await logFile.rename(old.path);
      }
      _file = logFile;
      await _file!.writeAsString(
        '\n===== ${DateTime.now().toIso8601String()} session start =====\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // 日志器自身挂掉绝不能影响 main
      swallow(e, tag: 'InitLogger.init');
      _file = null;
    }
  }

  /// 路径策略：先试 exe 同级 logs/（最容易让用户找到），失败回退到 ApplicationSupport
  static Future<Directory?> _resolveLogDir() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final logs = Directory(p.join(exeDir.path, 'logs'));
      if (!await logs.exists()) await logs.create(recursive: true);
      // 写一次试探，确认有写权限
      final probe = File(p.join(logs.path, '.probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return logs;
    } catch (e) {
      // exe 同级不可写（只读安装目录等），回退到下一策略
      swallow(e, tag: 'InitLogger.resolveLogDir.exe');
    }

    try {
      final support = await getApplicationSupportDirectory();
      final logs = Directory(p.join(support.path, 'logs'));
      if (!await logs.exists()) await logs.create(recursive: true);
      return logs;
    } catch (e) {
      swallow(e, tag: 'InitLogger.resolveLogDir.support');
    }

    return null;
  }

  /// 写一行日志。tag 用于 grep 定位。
  static void log(String tag, String message) {
    debugPrint('[$tag] $message');
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(
        '${DateTime.now().toIso8601String()} [$tag] $message\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (e) {
      swallow(e, tag: 'InitLogger.log');
    }
  }

  /// 写一行日志并立即落盘 — 在调用容易"硬崩溃"的原生 API 前用，
  /// 即使进程随后 abort，最后一条 logFlush 仍可在文件里看到。
  static void logFlush(String tag, String message) {
    debugPrint('[$tag] $message');
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(
        '${DateTime.now().toIso8601String()} [$tag] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      swallow(e, tag: 'InitLogger.logFlush');
    }
  }

  /// 写带 stack 的错误。
  static void error(String tag, Object e, [StackTrace? st]) {
    final stStr = st != null ? '\n$st' : '';
    debugPrint('[$tag] ERROR: $e$stStr');
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(
        '${DateTime.now().toIso8601String()} [$tag] ERROR: $e$stStr\n',
        mode: FileMode.append,
        flush: true, // 错误立即落盘
      );
    } catch (e) {
      swallow(e, tag: 'InitLogger.error');
    }
  }

  /// 当前日志文件路径（用于 UI 提示用户去哪找）
  static String? get currentLogPath => _file?.path;
}
