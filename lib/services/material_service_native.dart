/// 原生平台文件删除实现
import 'dart:io';

Future<void> deleteFileIfExists(String filePath) async {
  try {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}
