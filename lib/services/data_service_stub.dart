/// Web stub — 不支持文件操作

Future<String?> saveJsonToFile(String jsonString) async {
  return null;
}

Future<String> getNativeDBPath() async {
  return 'knowledge_graph.db (IndexedDB)';
}

Future<bool> copyDBFile(String destPath) async {
  return false;
}
