/// 文件上传服务 — 模拟文件上传，记录文件元数据
class FileUploadService {
  static final FileUploadService instance = FileUploadService._();
  FileUploadService._();

  /// 模拟文件上传，返回虚拟文件路径
  /// 实际生产中替换为 HTTP 上传逻辑
  Future<Map<String, dynamic>> uploadFile({
    required String fileName,
    required String fileType,
    int? fileSize,
    String? userId,
    String? category,
  }) async {
    // Simulate upload delay
    await Future.delayed(const Duration(milliseconds: 500));

    final now = DateTime.now();
    final path = 'uploads/${now.year}/${now.month.toString().padLeft(2, '0')}/$fileName';

    return {
      'success': true,
      'file_path': path,
      'file_name': fileName,
      'file_size': fileSize ?? 0,
      'upload_time': now.toIso8601String(),
    };
  }

  /// 获取支持的文件类型
  List<String> getSupportedTypes(String category) {
    switch (category) {
      case '源码':
        return ['.zip', '.rar', '.7z', '.tar.gz'];
      case '文档':
        return ['.doc', '.docx', '.pdf', '.md', '.txt'];
      case '截图':
        return ['.png', '.jpg', '.jpeg', '.gif', '.bmp'];
      case '视频':
        return ['.mp4', '.avi', '.mov', '.mkv'];
      case 'APK':
        return ['.apk'];
      default:
        return ['.zip', '.pdf', '.doc', '.docx', '.png', '.jpg', '.apk', '.mp4'];
    }
  }

  /// 格式化文件大小
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
