import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/file_opener_service.dart';
import '../../../services/courseware_download_service.dart';

class DocumentListPage extends StatefulWidget {
  const DocumentListPage({super.key});

  @override
  State<DocumentListPage> createState() => _DocumentListPageState();
}

class _DocumentListPageState extends State<DocumentListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  List<Map<String, dynamic>> _pdfs = [];
  List<Map<String, dynamic>> _ppts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final db = await _dbHelper.database;

      final pdfs = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['pdf'],
        orderBy: 'chapter',
      );

      final ppts = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['ppt'],
        orderBy: 'chapter',
      );

      // 数据由 DataLoadingService 统一初始化，不再在此处硬编码

      final sortedPdfs = List<Map<String, dynamic>>.from(pdfs);
      final sortedPpts = List<Map<String, dynamic>>.from(ppts);
      ChapterSorter.sortByChapter(sortedPdfs);
      ChapterSorter.sortByChapter(sortedPpts);

      setState(() {
        _pdfs = sortedPdfs;
        _ppts = sortedPpts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _pdfs = [];
        _ppts = [];
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程资料'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'PDF文档', icon: Icon(Icons.picture_as_pdf)),
            Tab(text: 'PPT课件', icon: Icon(Icons.slideshow)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDocuments,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDocumentList(
                    _pdfs, Icons.picture_as_pdf, Colors.red, 'PDF'),
                _buildDocumentList(
                    _ppts, Icons.slideshow, Colors.orange, 'PPT'),
              ],
            ),
    );
  }

  Widget _buildDocumentList(List<Map<String, dynamic>> documents, IconData icon,
      Color color, String type) {
    if (documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '暂无${type}文档',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '文档将从 Gitee 仓库自动获取',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color,
              child: Icon(icon, color: Colors.white),
            ),
            title: Text(doc['chapter'] ?? '文档'),
            subtitle: Text(doc['file_name'] ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDocument(doc),
          ),
        );
      },
    );
  }

  void _openDocument(Map<String, dynamic> doc) async {
    final filePath = doc['file_path'] as String? ?? '';
    final fileName = doc['file_name'] as String? ?? '';
    final fileType = doc['file_type'] as String? ?? '';
    final chapter = doc['chapter'] as String? ?? '';

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
          title: const Text('下载课件'),
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
