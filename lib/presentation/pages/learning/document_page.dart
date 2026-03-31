import 'package:flutter/material.dart';
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

      var pdfs = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['pdf'],
        orderBy: 'chapter',
      );

      var ppts = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['ppt'],
        orderBy: 'chapter',
      );

      if (pdfs.isEmpty && ppts.isEmpty) {
        // Insert PDF resources
        final pdfFiles = [
          {
            'file_name': '第一章 移动应用开发技术体系1.pdf',
            'file_path': 'assets/pdf/第一章 移动应用开发技术体系1.pdf',
            'file_type': 'pdf',
            'chapter': '第一章 移动应用开发技术体系1',
            'description': 'PDF课件'
          },
          {
            'file_name': '第一章 移动应用开发技术体系2.pdf',
            'file_path': 'assets/pdf/第一章 移动应用开发技术体系2.pdf',
            'file_type': 'pdf',
            'chapter': '第一章 移动应用开发技术体系2',
            'description': 'PDF课件'
          },
          {
            'file_name': '第二章 原生开发基础1.pdf',
            'file_path': 'assets/pdf/第二章 原生开发基础1.pdf',
            'file_type': 'pdf',
            'chapter': '第二章 原生开发基础1',
            'description': 'PDF课件'
          },
          {
            'file_name': '第二章 原生开发基础2.pdf',
            'file_path': 'assets/pdf/第二章 原生开发基础2.pdf',
            'file_type': 'pdf',
            'chapter': '第二章 原生开发基础2',
            'description': 'PDF课件'
          },
          {
            'file_name': '第三章 混合开发技术1.pdf',
            'file_path': 'assets/pdf/第三章 混合开发技术1.pdf',
            'file_type': 'pdf',
            'chapter': '第三章 混合开发技术1',
            'description': 'PDF课件'
          },
          {
            'file_name': '第三章 混合开发技术2.pdf',
            'file_path': 'assets/pdf/第三章 混合开发技术2.pdf',
            'file_type': 'pdf',
            'chapter': '第三章 混合开发技术2',
            'description': 'PDF课件'
          },
          {
            'file_name': '第三章 混合开发技术3.pdf',
            'file_path': 'assets/pdf/第三章 混合开发技术3.pdf',
            'file_type': 'pdf',
            'chapter': '第三章 混合开发技术3',
            'description': 'PDF课件'
          },
          {
            'file_name': '第四章 小程序开发1.pdf',
            'file_path': 'assets/pdf/第四章 小程序开发1.pdf',
            'file_type': 'pdf',
            'chapter': '第四章 小程序开发1',
            'description': 'PDF课件'
          },
          {
            'file_name': '第四章 小程序开发2.pdf',
            'file_path': 'assets/pdf/第四章 小程序开发2.pdf',
            'file_type': 'pdf',
            'chapter': '第四章 小程序开发2',
            'description': 'PDF课件'
          },
          {
            'file_name': '第五章 华为多端应用开发1.pdf',
            'file_path': 'assets/pdf/第五章 华为多端应用开发1.pdf',
            'file_type': 'pdf',
            'chapter': '第五章 华为多端应用开发1',
            'description': 'PDF课件'
          },
          {
            'file_name': '第五章 华为多端应用开发2.pdf',
            'file_path': 'assets/pdf/第五章 华为多端应用开发2.pdf',
            'file_type': 'pdf',
            'chapter': '第五章 华为多端应用开发2',
            'description': 'PDF课件'
          },
          {
            'file_name': '第五章 华为多端应用开发3.pdf',
            'file_path': 'assets/pdf/第五章 华为多端应用开发3.pdf',
            'file_type': 'pdf',
            'chapter': '第五章 华为多端应用开发3',
            'description': 'PDF课件'
          },
          {
            'file_name': '第六章 综合开发实践1.pdf',
            'file_path': 'assets/pdf/第六章 综合开发实践1.pdf',
            'file_type': 'pdf',
            'chapter': '第六章 综合开发实践1',
            'description': 'PDF课件'
          },
          {
            'file_name': '第六章 综合开发实践2.pdf',
            'file_path': 'assets/pdf/第六章 综合开发实践2.pdf',
            'file_type': 'pdf',
            'chapter': '第六章 综合开发实践2',
            'description': 'PDF课件'
          },
          {
            'file_name': '第六章 综合开发实践3.pdf',
            'file_path': 'assets/pdf/第六章 综合开发实践3.pdf',
            'file_type': 'pdf',
            'chapter': '第六章 综合开发实践3',
            'description': 'PDF课件'
          },
        ];

        for (final pdf in pdfFiles) {
          await db.insert('resource_files', pdf);
        }

        // Insert PPT resources
        final pptFiles = [
          {
            'file_name': '第一章 移动应用开发技术体系1.pptx',
            'file_path': 'assets/ppt/第一章 移动应用开发技术体系1.pptx',
            'file_type': 'ppt',
            'chapter': '第一章 移动应用开发技术体系1',
            'description': 'PPT课件'
          },
          {
            'file_name': '第一章 移动应用开发技术体系2.pptx',
            'file_path': 'assets/ppt/第一章 移动应用开发技术体系2.pptx',
            'file_type': 'ppt',
            'chapter': '第一章 移动应用开发技术体系2',
            'description': 'PPT课件'
          },
          {
            'file_name': '第二章 原生开发基础1.pptx',
            'file_path': 'assets/ppt/第二章 原生开发基础1.pptx',
            'file_type': 'ppt',
            'chapter': '第二章 原生开发基础1',
            'description': 'PPT课件'
          },
          {
            'file_name': '第二章 原生开发基础2.pptx',
            'file_path': 'assets/ppt/第二章 原生开发基础2.pptx',
            'file_type': 'ppt',
            'chapter': '第二章 原生开发基础2',
            'description': 'PPT课件'
          },
          {
            'file_name': '第三章 混合开发技术1.pptx',
            'file_path': 'assets/ppt/第三章 混合开发技术1.pptx',
            'file_type': 'ppt',
            'chapter': '第三章 混合开发技术1',
            'description': 'PPT课件'
          },
          {
            'file_name': '第三章 混合开发技术2.pptx',
            'file_path': 'assets/ppt/第三章 混合开发技术2.pptx',
            'file_type': 'ppt',
            'chapter': '第三章 混合开发技术2',
            'description': 'PPT课件'
          },
          {
            'file_name': '第三章 混合开发技术3.pptx',
            'file_path': 'assets/ppt/第三章 混合开发技术3.pptx',
            'file_type': 'ppt',
            'chapter': '第三章 混合开发技术3',
            'description': 'PPT课件'
          },
          {
            'file_name': '第四章 小程序开发1.pptx',
            'file_path': 'assets/ppt/第四章 小程序开发1.pptx',
            'file_type': 'ppt',
            'chapter': '第四章 小程序开发1',
            'description': 'PPT课件'
          },
          {
            'file_name': '第四章 小程序开发2.pptx',
            'file_path': 'assets/ppt/第四章 小程序开发2.pptx',
            'file_type': 'ppt',
            'chapter': '第四章 小程序开发2',
            'description': 'PPT课件'
          },
          {
            'file_name': '第五章 华为多端应用开发1.pptx',
            'file_path': 'assets/ppt/第五章 华为多端应用开发1.pptx',
            'file_type': 'ppt',
            'chapter': '第五章 华为多端应用开发1',
            'description': 'PPT课件'
          },
          {
            'file_name': '第五章 华为多端应用开发2.pptx',
            'file_path': 'assets/ppt/第五章 华为多端应用开发2.pptx',
            'file_type': 'ppt',
            'chapter': '第五章 华为多端应用开发2',
            'description': 'PPT课件'
          },
          {
            'file_name': '第五章 华为多端应用开发3.pptx',
            'file_path': 'assets/ppt/第五章 华为多端应用开发3.pptx',
            'file_type': 'ppt',
            'chapter': '第五章 华为多端应用开发3',
            'description': 'PPT课件'
          },
          {
            'file_name': '第六章 综合开发实践1.pptx',
            'file_path': 'assets/ppt/第六章 综合开发实践1.pptx',
            'file_type': 'ppt',
            'chapter': '第六章 综合开发实践1',
            'description': 'PPT课件'
          },
          {
            'file_name': '第六章 综合开发实践2.pptx',
            'file_path': 'assets/ppt/第六章 综合开发实践2.pptx',
            'file_type': 'ppt',
            'chapter': '第六章 综合开发实践2',
            'description': 'PPT课件'
          },
          {
            'file_name': '第六章 综合开发实践3.pptx',
            'file_path': 'assets/ppt/第六章 综合开发实践3.pptx',
            'file_type': 'ppt',
            'chapter': '第六章 综合开发实践3',
            'description': 'PPT课件'
          },
        ];

        for (final ppt in pptFiles) {
          await db.insert('resource_files', ppt);
        }

        pdfs = await db.query(
          'resource_files',
          where: 'file_type = ?',
          whereArgs: ['pdf'],
          orderBy: 'chapter',
        );

        ppts = await db.query(
          'resource_files',
          where: 'file_type = ?',
          whereArgs: ['ppt'],
          orderBy: 'chapter',
        );
      }

      setState(() {
        _pdfs = pdfs;
        _ppts = ppts;
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
