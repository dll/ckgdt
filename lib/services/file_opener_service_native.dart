/// 原生平台文件打开实现（使用 dart:io + open_filex + path_provider）
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<String?> copyAssetToTemp(String assetPath, String fileName) async {
  final tempDir = await getTemporaryDirectory();
  final tempFilePath = p.join(tempDir.path, 'course_files', fileName);
  final tempFile = File(tempFilePath);

  if (!await tempFile.exists()) {
    await tempFile.parent.create(recursive: true);

    try {
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await tempFile.writeAsBytes(bytes, flush: true);
    } on FlutterError catch (_) {
      return null;
    }
  }

  return tempFilePath;
}

Future<void> openAndHandleResult(
    ScaffoldMessengerState messenger, String filePath, String fileName) async {
  final result = await OpenFilex.open(filePath);

  switch (result.type) {
    case ResultType.done:
      break;
    case ResultType.noAppToOpen:
      messenger.showSnackBar(
        SnackBar(
          content: Text('没有可以打开「$fileName」的应用，请安装对应的阅读器'),
          backgroundColor: Colors.orange,
        ),
      );
      break;
    case ResultType.fileNotFound:
      messenger.showSnackBar(
        SnackBar(
          content: Text('文件未找到: $fileName'),
          backgroundColor: Colors.red,
        ),
      );
      break;
    case ResultType.permissionDenied:
      messenger.showSnackBar(
        const SnackBar(
          content: Text('没有权限打开此文件，请检查存储权限设置'),
          backgroundColor: Colors.red,
        ),
      );
      break;
    case ResultType.error:
      messenger.showSnackBar(
        SnackBar(
          content: Text('打开文件失败: ${result.message}'),
          backgroundColor: Colors.red,
        ),
      );
      break;
  }
}

Future<void> openExternalFileNative(
    ScaffoldMessengerState messenger, String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('文件未找到: ${p.basename(filePath)}，请联系管理员。'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  await openAndHandleResult(messenger, filePath, p.basename(filePath));
}

Future<void> clearCacheNative() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'course_files'));
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  } catch (_) {
    // 静默失败
  }
}
