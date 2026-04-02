import 'package:flutter/material.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/file_opener_service.dart';

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
        ],
      ),
    );
  }

  void _playVideo(Map<String, dynamic> video) {
    final filePath = video['file_path'] as String? ?? '';
    final fileName = video['file_name'] as String? ?? '${video['chapter']}.mp4';
    if (filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件路径未设置')),
      );
      return;
    }
    FileOpenerService.openFile(context, filePath, fileName);
  }
}
