/// 原生平台文件删除实现
library;
import 'dart:io';
import 'package:knowledge_graph_app/core/error_handler.dart';

Future<void> deleteFileIfExists(String filePath) async {
  try {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  } catch (e) { swallowDebug(e, tag: 'material_service_native'); }
}
