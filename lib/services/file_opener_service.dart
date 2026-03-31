import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 文件打开服务
///
/// 提供从 assets 或本地路径打开文件（PDF、PPT、视频等）的工具方法。
/// 对于 assets 中的文件，会先复制到临时目录再调用系统应用打开；
/// 支持缓存机制，已复制过的文件不会重复复制。
class FileOpenerService {
  /// 从 assets 打开文件
  ///
  /// [context] - BuildContext，用于显示 SnackBar 提示
  /// [assetPath] - assets 中的路径，例如 `assets/pdf/第一章.pdf`
  /// [fileName] - 文件显示名称，用于提示信息
  static Future<void> openFile(
    BuildContext context,
    String assetPath,
    String fileName,
  ) async {
    // 保存 context 相关引用，避免异步间隙后使用失效的 context
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // 显示加载提示
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('正在准备文件: $fileName')),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = p.join(tempDir.path, 'course_files', fileName);
      final tempFile = File(tempFilePath);

      // 检查缓存：文件已存在则跳过复制
      if (!await tempFile.exists()) {
        // 确保父目录存在
        await tempFile.parent.create(recursive: true);

        try {
          // 从 assets 加载文件数据
          final byteData = await rootBundle.load(assetPath);
          final bytes = byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          );

          // 写入临时文件
          await tempFile.writeAsBytes(bytes, flush: true);
        } on FlutterError catch (_) {
          // rootBundle.load 在找不到 asset 时抛出 FlutterError
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('课件文件尚未内置，请联系管理员获取'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      // 隐藏加载提示
      scaffoldMessenger.hideCurrentSnackBar();

      // 使用系统应用打开文件
      final result = await OpenFilex.open(tempFilePath);

      // 处理打开结果
      switch (result.type) {
        case ResultType.done:
          // 成功打开，无需额外提示
          break;
        case ResultType.noAppToOpen:
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('没有可以打开此文件的应用'),
              backgroundColor: Colors.orange,
            ),
          );
          break;
        case ResultType.fileNotFound:
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('文件未找到: $fileName'),
              backgroundColor: Colors.red,
            ),
          );
          break;
        case ResultType.permissionDenied:
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('没有权限打开此文件'),
              backgroundColor: Colors.red,
            ),
          );
          break;
        case ResultType.error:
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('打开文件失败: ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
          break;
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();

      if (e is FlutterError || e.toString().contains('Unable to load asset')) {
        // Asset 不存在的情况
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('课件文件尚未内置，请联系管理员获取'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('打开文件失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 直接打开设备上已有的文件
  ///
  /// [context] - BuildContext，用于显示 SnackBar 提示
  /// [filePath] - 文件在设备上的绝对路径
  static Future<void> openExternalFile(
    BuildContext context,
    String filePath,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // 先检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('文件未找到: ${p.basename(filePath)}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 使用系统应用打开文件
      final result = await OpenFilex.open(filePath);

      switch (result.type) {
        case ResultType.done:
          break;
        case ResultType.noAppToOpen:
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('没有可以打开此文件的应用'),
              backgroundColor: Colors.orange,
            ),
          );
          break;
        case ResultType.fileNotFound:
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('文件未找到: ${p.basename(filePath)}'),
              backgroundColor: Colors.red,
            ),
          );
          break;
        case ResultType.permissionDenied:
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('没有权限打开此文件'),
              backgroundColor: Colors.red,
            ),
          );
          break;
        case ResultType.error:
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('打开文件失败: ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
          break;
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('打开文件失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 清除文件缓存
  ///
  /// 删除临时目录中的所有已缓存课件文件
  static Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'course_files'));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {
      // 静默失败，缓存清理不影响功能
    }
  }
}
