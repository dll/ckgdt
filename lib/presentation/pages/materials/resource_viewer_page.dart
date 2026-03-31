import 'package:flutter/material.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/file_opener_service.dart';

/// 资源查看页面 — 按章节过滤显示 PDF/PPT 课件
class ResourceViewerPage extends StatefulWidget {
  final String fileType; // 'pdf' 或 'ppt'
  final String? filterChapter; // 可选章节过滤

  const ResourceViewerPage({
    super.key,
    required this.fileType,
    this.filterChapter,
  });

  @override
  State<ResourceViewerPage> createState() => _ResourceViewerPageState();
}

class _ResourceViewerPageState extends State<ResourceViewerPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _resources = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  Future<void> _loadResources() async {
    try {
      final db = await _dbHelper.database;

      List<Map<String, dynamic>> result;
      if (widget.filterChapter != null && widget.filterChapter!.isNotEmpty) {
        result = await db.query(
          'resource_files',
          where: 'file_type = ? AND chapter LIKE ?',
          whereArgs: [widget.fileType, '%${widget.filterChapter}%'],
          orderBy: 'chapter',
        );
      } else {
        result = await db.query(
          'resource_files',
          where: 'file_type = ?',
          whereArgs: [widget.fileType],
          orderBy: 'chapter',
        );
      }

      setState(() {
        _resources = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _resources = [];
        _isLoading = false;
      });
    }
  }

  String get _typeLabel => widget.fileType == 'pdf' ? 'PDF文档' : 'PPT课件';
  IconData get _typeIcon =>
      widget.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.slideshow;
  Color get _typeColor =>
      widget.fileType == 'pdf' ? Colors.red : Colors.orange;

  @override
  Widget build(BuildContext context) {
    final title = widget.filterChapter != null
        ? '$_typeLabel: ${widget.filterChapter}'
        : _typeLabel;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _resources.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_typeIcon, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        widget.filterChapter != null
                            ? '未找到「${widget.filterChapter}」的$_typeLabel'
                            : '暂无$_typeLabel',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _resources.length,
                  itemBuilder: (ctx, i) {
                    final res = _resources[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _typeColor.withValues(alpha: 0.1),
                          child: Icon(_typeIcon, color: _typeColor, size: 22),
                        ),
                        title: Text(res['chapter'] ?? res['file_name'] ?? ''),
                        subtitle: Text(res['description'] ?? '',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          final filePath = res['file_path'] as String? ?? '';
                          final fileName = res['file_name'] as String? ?? '';
                          if (filePath.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('文件路径未设置')),
                            );
                            return;
                          }
                          FileOpenerService.openFile(context, filePath, fileName);
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
