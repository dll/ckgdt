import 'dart:io';

/// 路径处理工具
class PathUtils {
  /// 规范化路径：
  /// - 去除首尾空白
  /// - 去除首尾的单引号或双引号（用户复制路径时常见带入）
  /// - 统一使用反斜杠（Windows 风格）
  /// - 去除末尾的分隔符
  ///
  /// 例：
  /// - `"'D:\project'"` → `D:\project`
  /// - `'"D:\project"'` → `D:\project`
  /// - `'D:\project\'` → `D:\project`
  static String normalize(String? raw) {
    if (raw == null) return '';
    var p = raw.trim();

    // 循环去除首尾的多层引号（防止 `"'D:\project'"` 这种情况）
    while (p.length >= 2) {
      final first = p[0];
      final last = p[p.length - 1];
      if ((first == '"' && last == '"') ||
          (first == "'" && last == "'")) {
        p = p.substring(1, p.length - 1).trim();
      } else {
        break;
      }
    }

    // 统一反斜杠
    p = p.replaceAll('/', '\\');

    // 去除末尾分隔符（保留盘符后的 `:\`）
    if (p.length > 3 && (p.endsWith('\\') || p.endsWith('/'))) {
      p = p.substring(0, p.length - 1);
    }

    return p;
  }

  /// 安全检查目录是否存在（捕获异常，避免 FileSystemException 崩溃）
  static bool dirExists(String? path) {
    final p = normalize(path);
    if (p.isEmpty) return false;
    try {
      return Directory(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 安全检查文件是否存在（捕获异常）
  static bool fileExists(String? path) {
    final p = normalize(path);
    if (p.isEmpty) return false;
    try {
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 路径是否可访问（目录或文件任一存在）
  static bool pathExists(String? path) {
    return dirExists(path) || fileExists(path);
  }

  /// 获取路径的最后一段名称（去除扩展名和版本号）
  /// 例：`TingChengGIS-v1.0.5` → `TingChengGIS`
  static String deriveName(String path) {
    final p = normalize(path);
    final name = p.split('\\').last;
    // 去除 .apk / .exe / .bat 等扩展名
    final noExt = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    // 去除 `-v1.0.5` / `_v2.0` / `-release` 等后缀
    return noExt
        .replaceFirst(RegExp(r'[-_]v?\d+(\.\d+)*.*$'), '')
        .replaceFirst(RegExp(r'[-_]release.*$', caseSensitive: false), '')
        .trim();
  }
}
