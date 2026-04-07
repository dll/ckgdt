import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'gitee_service.dart';

/// 课件下载服务 — 本地优先 + Gitee 远程兜底
///
/// 工作流程：
/// 1. 检查本地原始路径（DataLoadingService 写入的绝对路径）
/// 2. 检查本地缓存目录（之前下载过的文件）
/// 3. 仅 PDF 文件可从 Gitee 远程下载（视频/PPT 因仓库容量限制需本地部署）
class CoursewareDownloadService {
  static final CoursewareDownloadService instance =
      CoursewareDownloadService._();
  factory CoursewareDownloadService() => instance;
  CoursewareDownloadService._();

  final GiteeService _gitee = GiteeService();

  /// Gitee 仓库信息
  static const String _owner = 'osgisOne';
  static const String _repo = 'mad-fd';
  static const String _branch = 'master';

  /// 可远程下载的文件类型（PDF 已推送到仓库）
  static const Set<String> _remoteAvailableTypes = {'pdf'};

  /// 远程路径映射
  static String _remotePath(String fileType, String chapter) {
    switch (fileType) {
      case 'video':
        return 'data/视频/$chapter.mp4';
      case 'pdf':
        return 'data/课件/清言智谱/$chapter.pdf';
      case 'ppt':
        return 'data/课件/秒出PPT/$chapter.pptx';
      default:
        return 'data/$chapter';
    }
  }

  /// 文件扩展名
  static String _extension(String fileType) {
    switch (fileType) {
      case 'video':
        return '.mp4';
      case 'pdf':
        return '.pdf';
      case 'ppt':
        return '.pptx';
      default:
        return '';
    }
  }

  /// 判断该类型是否支持远程下载
  static bool isRemoteAvailable(String fileType) =>
      _remoteAvailableTypes.contains(fileType);

  /// 获取不可远程下载时的提示消息
  static String getLocalOnlyMessage(String fileType) {
    switch (fileType) {
      case 'video':
        return '视频文件较大，需从教师处获取或本地部署。\n请联系教师获取课件分发包。';
      case 'ppt':
        return 'PPT文件较大，需从教师处获取或本地部署。\n请联系教师获取课件分发包。';
      default:
        return '该类型文件需要本地部署。';
    }
  }

  /// 获取本地缓存目录
  Future<String> _getCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(appDir.path, 'courseware_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  /// 获取缓存文件路径
  Future<String> _getCachePath(String fileType, String fileName) async {
    final cacheDir = await _getCacheDir();
    final subDir = Directory(p.join(cacheDir, fileType));
    if (!await subDir.exists()) {
      await subDir.create(recursive: true);
    }
    return p.join(subDir.path, fileName);
  }

  /// 核心方法：获取文件路径（本地优先，远程兜底）
  ///
  /// [localPath] — DataLoadingService 写入的本地绝对路径
  /// [fileType] — 文件类型: video / pdf / ppt
  /// [chapter] — 章节名称（如 "第一章 移动应用开发技术体系1"）
  /// [fileName] — 文件名（如 "第一章 移动应用开发技术体系1.pdf"）
  /// [onProgress] — 下载进度回调 (0.0 ~ 1.0)
  ///
  /// 返回可用的本地文件路径，或 null（下载失败）
  Future<String?> getLocalOrDownload({
    required String localPath,
    required String fileType,
    required String chapter,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) return null;

    // 1. 检查原始本地路径
    if (localPath.isNotEmpty) {
      final localFile = File(localPath);
      if (await localFile.exists()) {
        debugPrint('CoursewareDownload: Local file found: $localPath');
        return localPath;
      }
    }

    // 2. 检查缓存目录
    final cachePath = await _getCachePath(fileType, fileName);
    final cacheFile = File(cachePath);
    if (await cacheFile.exists() && await cacheFile.length() > 0) {
      debugPrint('CoursewareDownload: Cache hit: $cachePath');
      return cachePath;
    }

    // 3. 检查是否支持远程下载
    if (!isRemoteAvailable(fileType)) {
      debugPrint('CoursewareDownload: $fileType not available for remote download');
      return null;
    }

    // 4. 从 Gitee 下载
    debugPrint('CoursewareDownload: Downloading from Gitee...');
    final downloaded = await _downloadFromGitee(
      fileType: fileType,
      chapter: chapter,
      savePath: cachePath,
      onProgress: onProgress,
    );

    return downloaded ? cachePath : null;
  }

  /// 从 Gitee Raw URL 下载文件
  Future<bool> _downloadFromGitee({
    required String fileType,
    required String chapter,
    required String savePath,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final token = await _gitee.getToken();
      final remotePath = _remotePath(fileType, chapter);

      // 使用 Gitee Raw URL 下载（比 Contents API 效率高，无 base64 开销）
      final encodedPath = Uri.encodeFull(remotePath);
      var url =
          'https://gitee.com/$_owner/$_repo/raw/$_branch/$encodedPath';
      if (token != null && token.isNotEmpty) {
        url += '?access_token=$token';
      }

      debugPrint('CoursewareDownload: GET $url');

      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send().timeout(
        const Duration(minutes: 10),
      );

      if (response.statusCode != 200) {
        debugPrint(
            'CoursewareDownload: Download failed: ${response.statusCode}');
        return false;
      }

      // 流式下载，支持进度回调
      final file = File(savePath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();

      final contentLength = response.contentLength ?? 0;
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(received / contentLength);
        }
      }

      await sink.flush();
      await sink.close();

      final fileSize = await file.length();
      debugPrint(
          'CoursewareDownload: Downloaded ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB → $savePath');
      return fileSize > 0;
    } catch (e) {
      debugPrint('CoursewareDownload: Error: $e');
      // 清理不完整的下载
      try {
        final file = File(savePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      return false;
    }
  }

  /// 检查文件是否在本地可用（不触发下载）
  Future<bool> isLocallyAvailable(String localPath, String fileType,
      String fileName) async {
    if (kIsWeb) return false;

    // 检查原始路径
    if (localPath.isNotEmpty && await File(localPath).exists()) {
      return true;
    }

    // 检查缓存
    final cachePath = await _getCachePath(fileType, fileName);
    return File(cachePath).existsSync();
  }

  /// 获取缓存统计
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final cacheDir = await _getCacheDir();
      final dir = Directory(cacheDir);
      if (!await dir.exists()) {
        return {'totalFiles': 0, 'totalSize': 0, 'totalSizeMB': '0.0'};
      }

      int totalFiles = 0;
      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalFiles++;
          totalSize += await entity.length();
        }
      }

      return {
        'totalFiles': totalFiles,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / 1024 / 1024).toStringAsFixed(1),
      };
    } catch (e) {
      return {'totalFiles': 0, 'totalSize': 0, 'totalSizeMB': '0.0'};
    }
  }

  /// 清除下载缓存
  Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDir();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('CoursewareDownload: Cache cleared');
      }
    } catch (e) {
      debugPrint('CoursewareDownload: Clear cache error: $e');
    }
  }

  /// 预下载指定类型的所有文件
  Future<int> preDownloadAll({
    required String fileType,
    required List<String> chapters,
    void Function(int completed, int total)? onProgress,
  }) async {
    int downloaded = 0;
    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final ext = _extension(fileType);
      final fileName = '$chapter$ext';
      final cachePath = await _getCachePath(fileType, fileName);

      if (!await File(cachePath).exists()) {
        final success = await _downloadFromGitee(
          fileType: fileType,
          chapter: chapter,
          savePath: cachePath,
        );
        if (success) downloaded++;
      } else {
        downloaded++; // 已缓存
      }

      onProgress?.call(i + 1, chapters.length);
    }
    return downloaded;
  }
}
