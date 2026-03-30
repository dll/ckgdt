import 'dart:io';
import '../data/local/material_dao.dart';
import '../data/models/material_model.dart';

class MaterialService {
  final MaterialDao _dao = MaterialDao();

  Future<List<MaterialModel>> getAll() => _dao.getAll();

  Future<List<MaterialModel>> getByType(String type) => _dao.getByType(type);

  Future<List<MaterialModel>> getByChapter(String chapter) =>
      _dao.getByChapter(chapter);

  Future<int> count() => _dao.count();

  Future<bool> delete(MaterialModel material) async {
    // 删除物理文件
    if (material.filePath != null) {
      try {
        final file = File(material.filePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    final rows = await _dao.delete(material.id!);
    return rows > 0;
  }

  /// 获取文件大小的可读字符串
  static String formatSize(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// 根据类型返回图标字符（用于 UI 展示）
  static String typeIcon(String type) {
    switch (type) {
      case 'pdf':
        return '📄';
      case 'slide':
        return '🖼️';
      case 'script':
        return '📝';
      case 'uml':
        return '🔷';
      case 'video_script':
        return '🎬';
      default:
        return '📦';
    }
  }
}
