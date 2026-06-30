/// dev/admin 机器路径解析 — 仅原生（非 web）使用。
///
/// 拆出来不放 [BuildInfo]：BuildInfo 被登录页 / 关于页面引用，
/// 那些代码也跑在 web，不能引 dart:io。这个文件只在
/// admin 工具（构建发布中心、Claude CLI 启动器）里 import。
library;

import 'dart:io';
import 'package:path/path.dart' as p;

class DevPaths {
  DevPaths._();

  /// 项目根目录。
  ///
  /// release 模式下 `Directory.current` 不可靠（装机后 cwd 是
  /// `C:\Windows\System32`），需要回退兜底：
  /// 1. cwd 下有 pubspec.yaml → 用 cwd
  /// 2. 否则用 dev 机硬编码（仅 Windows）
  ///
  /// **跨设备移植**：换 admin 机器只改这里。之前散在
  /// version_bump_service / feedback_manage_page 各自一份，现在合并。
  static String? _cached;
  static String get projectRoot {
    if (_cached != null) return _cached!;
    final cwd = Directory.current.path;
    if (File(p.join(cwd, 'pubspec.yaml')).existsSync()) {
      _cached = cwd;
      return cwd;
    }
    if (Platform.isWindows) {
      _cached = r'D:\FlutterProjects\knowledge_graph_app';
      return _cached!;
    }
    _cached = cwd;
    return cwd;
  }

  /// ffmpeg 可执行文件路径。
  ///
  /// 解析顺序：
  /// 1. PATH 中能直接 `ffmpeg` 调用 → 返回 'ffmpeg'（让 OS 找）
  /// 2. Windows 已知装机路径
  /// 3. macOS Homebrew 路径 / Linux apt 路径
  /// 4. fallback：'ffmpeg'（runShell 时若不在 PATH 会报 ENOENT）
  static String? _ffmpegCached;
  static String get ffmpegPath {
    if (_ffmpegCached != null) return _ffmpegCached!;
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        p.join(exeDir, 'ffmpeg.exe'),
        r'D:\development\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe',
        r'C:\ffmpeg\bin\ffmpeg.exe',
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) {
          _ffmpegCached = c;
          return c;
        }
      }
    } else if (Platform.isMacOS) {
      const candidates = ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg'];
      for (final c in candidates) {
        if (File(c).existsSync()) {
          _ffmpegCached = c;
          return c;
        }
      }
    }
    _ffmpegCached = 'ffmpeg'; // 兜底依赖 PATH
    return _ffmpegCached!;
  }
}
