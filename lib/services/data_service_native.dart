/// 原生平台文件操作实现
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> saveJsonToFile(String jsonString) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/knowledge_graph_backup.json');
    await file.writeAsString(jsonString);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<String> getNativeDBPath() async {
  final directory = await getApplicationDocumentsDirectory();
  return '${directory.path}/knowledge_graph.db';
}

Future<bool> copyDBFile(String destPath) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = '${directory.path}/knowledge_graph.db';
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.copy(destPath);
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}
