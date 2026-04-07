import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/file_opener_service.dart';
import '../../../services/courseware_download_service.dart';

class VideoListPage extends StatefulWidget {
  final String? filterChapter; // 可选：按章节过滤

  const VideoListPage({super.key, this.filterChapter});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    try {
      final db = await _dbHelper.database;

      List<Map<String, dynamic>> result;
      if (widget.filterChapter != null && widget.filterChapter!.isNotEmpty) {
        // 模糊匹配章节
        result = await db.query(
          'resource_files',
          where: 'file_type = ? AND chapter LIKE ?',
          whereArgs: ['video', '%${widget.filterChapter}%'],
          orderBy: 'chapter',
        );
      } else {
        result = await db.query(
          'resource_files',
          where: 'file_type = ?',
          whereArgs: ['video'],
          orderBy: 'chapter',
        );
      }

      final sorted = List<Map<String, dynamic>>.from(result);
      ChapterSorter.sortByChapter(sorted);
      setState(() {
        _videos = sorted;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _videos = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.filterChapter != null
        ? '视频: ${widget.filterChapter}'
        : '视频教程';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVideos,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red,
                          child:
                              const Icon(Icons.play_arrow, color: Colors.white),
                        ),
                        title: Text(video['chapter'] ?? '视频'),
                        subtitle: Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            const Text('点击播放'),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _playVideo(video),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            widget.filterChapter != null
                ? '未找到「${widget.filterChapter}」的视频'
                : '暂无视频教程',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '视频将从 Gitee 仓库自动获取',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  void _playVideo(Map<String, dynamic> video) async {
    final filePath = video['file_path'] as String? ?? '';
    final fileName =
        video['file_name'] as String? ?? '${video['chapter']}.mp4';
    final fileType = video['file_type'] as String? ?? 'video';
    final chapter = video['chapter'] as String? ?? '';

    if (filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件路径未设置')),
      );
      return;
    }

    // 本地文件存在 → 直接打开
    if (!kIsWeb) {
      final localFile = File(filePath);
      if (await localFile.exists()) {
        if (!mounted) return;
        FileOpenerService.openFile(context, filePath, fileName);
        return;
      }
    }

    // 本地不存在 → 检查是否可远程下载
    if (!mounted) return;

    if (!CoursewareDownloadService.isRemoteAvailable(fileType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CoursewareDownloadService.getLocalOnlyMessage(fileType)),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    await _downloadAndOpen(
      filePath: filePath,
      fileName: fileName,
      fileType: fileType,
      chapter: chapter,
    );
  }

  Future<void> _downloadAndOpen({
    required String filePath,
    required String fileName,
    required String fileType,
    required String chapter,
  }) async {
    final downloadService = CoursewareDownloadService();
    bool cancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('下载视频'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fileName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              const Text('正在从 Gitee 仓库下载...',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    final resultPath = await downloadService.getLocalOrDownload(
      localPath: filePath,
      fileType: fileType,
      chapter: chapter,
      fileName: fileName,
    );

    if (cancelled || !mounted) return;

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (resultPath != null) {
      if (!mounted) return;
      FileOpenerService.openFile(context, resultPath, fileName);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('下载失败: $fileName\n请检查网络连接'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
