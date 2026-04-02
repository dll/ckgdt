import 'package:flutter/foundation.dart' show kIsWeb;
import '../data/local/material_dao.dart';
import '../data/models/material_model.dart';

// 条件导入
import 'material_service_stub.dart'
    if (dart.library.io) 'material_service_native.dart' as impl;

class MaterialService {
  final MaterialDao _dao = MaterialDao();

  Future<List<MaterialModel>> getAll() => _dao.getAll();

  Future<List<MaterialModel>> getByType(String type) => _dao.getByType(type);

  Future<List<MaterialModel>> getByChapter(String chapter) =>
      _dao.getByChapter(chapter);

  Future<int> count() => _dao.count();

  Future<bool> delete(MaterialModel material) async {
    // 删除物理文件（仅原生平台）
    if (!kIsWeb && material.filePath != null) {
      await impl.deleteFileIfExists(material.filePath!);
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
