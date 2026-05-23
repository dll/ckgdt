import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 输出目录服务：桌面端输出到应用所在目录/out/，移动端沿用文档目录
class OutputPathService {
  OutputPathService._();

  static Directory? _cached;

  /// 获取输出文件根目录
  /// - Windows/macOS/Linux：{应用所在目录}/out/
  /// - Android/iOS：getApplicationDocumentsDirectory()
  static Future<Directory> getOutputDirectory() async {
    if (_cached != null) return _cached!;

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final outDir = Directory(p.join(exeDir.path, 'out'));
      if (!outDir.existsSync()) {
        await outDir.create(recursive: true);
      }
      _cached = outDir;
      return outDir;
    }

    final dir = await getApplicationDocumentsDirectory();
    _cached = dir;
    return dir;
  }
}
