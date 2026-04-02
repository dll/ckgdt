/// Stub 实现 — Web 平台（不使用 dart:io）
import 'package:flutter/material.dart';

Future<String?> copyAssetToTemp(String assetPath, String fileName) async {
  return null;
}

Future<void> openAndHandleResult(
    ScaffoldMessengerState messenger, String filePath, String fileName) async {
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Web 平台暂不支持此操作'),
      backgroundColor: Colors.orange,
    ),
  );
}

Future<void> openExternalFileNative(
    ScaffoldMessengerState messenger, String filePath) async {
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Web 平台暂不支持打开本地文件'),
      backgroundColor: Colors.orange,
    ),
  );
}

Future<void> clearCacheNative() async {}
