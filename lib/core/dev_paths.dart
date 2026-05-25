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
}
