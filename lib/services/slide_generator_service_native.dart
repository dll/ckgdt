/// 原生平台 PDF 文件保存实现
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<Map<String, dynamic>?> savePdfFile(String fileName, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final filePath = '${dir.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(bytes);
  final stat = await file.stat();
  return {'path': filePath, 'size': stat.size};
}
