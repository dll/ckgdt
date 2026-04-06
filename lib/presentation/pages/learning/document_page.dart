import 'package:flutter/material.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/file_opener_service.dart';

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

  void _openDocument(Map<String, dynamic> doc) {
    final filePath = doc['file_path'] as String? ?? '';
    final fileName = doc['file_name'] as String? ?? '';
    if (filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件路径未设置')),
      );
      return;
    }
    FileOpenerService.openFile(context, filePath, fileName);
  }
}
