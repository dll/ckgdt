import 'package:flutter/material.dart';
import '../../../data/local/database_helper.dart';

class VideoListPage extends StatefulWidget {
  const VideoListPage({super.key});

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
      
      // First check if we have videos in database
      var result = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['video'],
        orderBy: 'chapter',
      );
      
      if (result.isEmpty) {
        // Insert video resources from assets
        final videos = [
          {'file_name': '第一章 移动应用开发技术体系1.mp4', 'file_path': 'assets/第一章 移动应用开发技术体系1.mp4', 'file_type': 'video', 'chapter': '第一章 移动应用开发技术体系1', 'description': '视频教程'},
          {'file_name': '第一章 移动应用开发技术体系2.mp4', 'file_path': 'assets/第一章 移动应用开发技术体系2.mp4', 'file_type': 'video', 'chapter': '第一章 移动应用开发技术体系2', 'description': '视频教程'},
          {'file_name': '第二章 原生开发基础1.mp4', 'file_path': 'assets/第二章 原生开发基础1.mp4', 'file_type': 'video', 'chapter': '第二章 原生开发基础1', 'description': '视频教程'},
          {'file_name': '第二章 原生开发基础2.mp4', 'file_path': 'assets/第二章 原生开发基础2.mp4', 'file_type': 'video', 'chapter': '第二章 原生开发基础2', 'description': '视频教程'},
          {'file_name': '第三章 混合开发技术1.mp4', 'file_path': 'assets/第三章 混合开发技术1.mp4', 'file_type': 'video', 'chapter': '第三章 混合开发技术1', 'description': '视频教程'},
          {'file_name': '第三章 混合开发技术2.mp4', 'file_path': 'assets/第三章 混合开发技术2.mp4', 'file_type': 'video', 'chapter': '第三章 混合开发技术2', 'description': '视频教程'},
          {'file_name': '第三章 混合开发技术3.mp4', 'file_path': 'assets/第三章 混合开发技术3.mp4', 'file_type': 'video', 'chapter': '第三章 混合开发技术3', 'description': '视频教程'},
          {'file_name': '第四章 小程序开发1.mp4', 'file_path': 'assets/第四章 小程序开发1.mp4', 'file_type': 'video', 'chapter': '第四章 小程序开发1', 'description': '视频教程'},
          {'file_name': '第四章 小程序开发2.mp4', 'file_path': 'assets/第四章 小程序开发2.mp4', 'file_type': 'video', 'chapter': '第四章 小程序开发2', 'description': '视频教程'},
          {'file_name': '第五章 华为多端应用开发1.mp4', 'file_path': 'assets/第五章 华为多端应用开发1.mp4', 'file_type': 'video', 'chapter': '第五章 华为多端应用开发1', 'description': '视频教程'},
          {'file_name': '第五章 华为多端应用开发2.mp4', 'file_path': 'assets/第五章 华为多端应用开发2.mp4', 'file_type': 'video', 'chapter': '第五章 华为多端应用开发2', 'description': '视频教程'},
          {'file_name': '第五章 华为多端应用开发3.mp4', 'file_path': 'assets/第五章 华为多端应用开发3.mp4', 'file_type': 'video', 'chapter': '第五章 华为多端应用开发3', 'description': '视频教程'},
          {'file_name': '第六章 综合开发实践1.mp4', 'file_path': 'assets/第六章 综合开发实践1.mp4', 'file_type': 'video', 'chapter': '第六章 综合开发实践1', 'description': '视频教程'},
          {'file_name': '第六章 综合开发实践2.mp4', 'file_path': 'assets/第六章 综合开发实践2.mp4', 'file_type': 'video', 'chapter': '第六章 综合开发实践2', 'description': '视频教程'},
          {'file_name': '第六章 综合开发实践3.mp4', 'file_path': 'assets/第六章 综合开发实践3.mp4', 'file_type': 'video', 'chapter': '第六章 综合开发实践3', 'description': '视频教程'},
        ];
        
        for (final video in videos) {
          await db.insert('resource_files', video);
        }
        
        result = await db.query(
          'resource_files',
          where: 'file_type = ?',
          whereArgs: ['video'],
          orderBy: 'chapter',
        );
      }
      
      setState(() {
        _videos = result;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频教程'),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
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
                          child: const Icon(Icons.play_arrow, color: Colors.white),
                        ),
                        title: Text(video['chapter'] ?? '视频'),
                        subtitle: Row(
                          children: [
                            const Icon(Icons.access_time, size: 14, color: Colors.grey),
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
            '暂无视频教程',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  void _playVideo(Map<String, dynamic> video) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('播放: ${video['chapter']}\n文件: ${video['file_path']}')),
    );
  }
}
