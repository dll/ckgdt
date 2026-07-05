import 'package:flutter/material.dart';
import '../../../core/constants/chapter_helper.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/course_context_service.dart';
import '../../../services/file_opener_service.dart';

/// 资源查看页面 — 按章节过滤显示 PDF/PPT 课件
///
/// 支持两种模式：
/// - 单类型模式：fileType = 'pdf' 或 'ppt'（向后兼容）
/// - 双类型模式：fileType = 'all'，用 TabBar 切换 PPT/PDF
class ResourceViewerPage extends StatefulWidget {
  final String fileType; // 'pdf'、'ppt' 或 'all'
  final String? filterChapter; // 可选章节过滤

  const ResourceViewerPage({
    super.key,
    required this.fileType,
    this.filterChapter,
  });

  @override
  State<ResourceViewerPage> createState() => _ResourceViewerPageState();
}

class _ResourceViewerPageState extends State<ResourceViewerPage>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  // 双 Tab 模式
  TabController? _tabController;
  List<Map<String, dynamic>> _pptResources = [];
  List<Map<String, dynamic>> _pdfResources = [];

  // 单类型模式
  List<Map<String, dynamic>> _resources = [];

  bool _isLoading = true;

  bool get _isAllMode => widget.fileType == 'all';

  Future<({String where, List<Object?> args})> _resourceScope(
    String fileType,
  ) async {
    final whereParts = <String>['file_type = ?'];
    final whereArgs = <Object?>[fileType];
    final chFilter = widget.filterChapter;

    if (chFilter != null && chFilter.isNotEmpty) {
      final chapter = ChapterHelper.parseChapter(chFilter);
      if (chapter == null) {
        whereParts.add('chapter LIKE ?');
        whereArgs.add('%$chFilter%');
      } else {
        final patterns = await _courseContext.chapterQueryPatterns(chapter);
        whereParts.add(
          '(${List.filled(patterns.length, 'chapter LIKE ?').join(' OR ')})',
        );
        whereArgs.addAll(patterns);
      }
    }

    return _courseContext.scopedWhere(
      extraWhere: whereParts.join(' AND '),
      extraArgs: whereArgs,
    );
  }

  @override
  void initState() {
    super.initState();
    if (_isAllMode) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _loadResources();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadResources() async {
    try {
      final db = await _dbHelper.database;

      if (_isAllMode) {
        // 同时加载 PPT 和 PDF
        List<Map<String, dynamic>> pptResult;
        List<Map<String, dynamic>> pdfResult;

        final pptScope = await _resourceScope('ppt');
        final pdfScope = await _resourceScope('pdf');
        pptResult = await db.query(
          'resource_files',
          where: pptScope.where,
          whereArgs: pptScope.args,
          orderBy: 'chapter',
        );
        pdfResult = await db.query(
          'resource_files',
          where: pdfScope.where,
          whereArgs: pdfScope.args,
          orderBy: 'chapter',
        );

        final sortedPpt = List<Map<String, dynamic>>.from(pptResult);
        final sortedPdf = List<Map<String, dynamic>>.from(pdfResult);
        ChapterSorter.sortByChapter(sortedPpt);
        ChapterSorter.sortByChapter(sortedPdf);

        setState(() {
          _pptResources = sortedPpt;
          _pdfResources = sortedPdf;
          _isLoading = false;
        });
      } else {
        // 单类型模式（向后兼容）
        final scope = await _resourceScope(widget.fileType);
        final result = await db.query(
          'resource_files',
          where: scope.where,
          whereArgs: scope.args,
          orderBy: 'chapter',
        );

        final sorted = List<Map<String, dynamic>>.from(result);
        ChapterSorter.sortByChapter(sorted);

        setState(() {
          _resources = sorted;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _resources = [];
        _pptResources = [];
        _pdfResources = [];
        _isLoading = false;
      });
    }
  }

  String get _typeLabel => widget.fileType == 'pdf'
      ? 'PDF文档'
      : widget.fileType == 'ppt'
          ? 'PPT课件'
          : '课件资料';

  @override
  Widget build(BuildContext context) {
    final title = widget.filterChapter != null
        ? '$_typeLabel: ${widget.filterChapter}'
        : _typeLabel;

    if (_isAllMode) {
      return _buildAllModeScaffold(title);
    }
    return _buildSingleModeScaffold(title);
  }

  /// 双 Tab 模式 — PPT + PDF
  Widget _buildAllModeScaffold(String title) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.slideshow, size: 20),
              text: 'PPT课件 (${_pptResources.length})',
            ),
            Tab(
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              text: 'PDF文档 (${_pdfResources.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildResourceList(_pptResources, 'ppt'),
                _buildResourceList(_pdfResources, 'pdf'),
              ],
            ),
    );
  }

  /// 单类型模式（向后兼容）
  Widget _buildSingleModeScaffold(String title) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildResourceList(_resources, widget.fileType),
    );
  }

  /// 资源列表
  Widget _buildResourceList(List<Map<String, dynamic>> resources, String type) {
    final icon = type == 'pdf' ? Icons.picture_as_pdf : Icons.slideshow;
    final color = type == 'pdf' ? Colors.red : Colors.orange;
    final label = type == 'pdf' ? 'PDF文档' : 'PPT课件';

    if (resources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.filterChapter != null
                  ? '未找到「${widget.filterChapter}」的$label'
                  : '暂无$label',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: resources.length,
      itemBuilder: (ctx, i) {
        final res = resources[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 22),
            ),
            title: Text(res['chapter'] ?? res['file_name'] ?? ''),
            subtitle: Text(res['description'] ?? '',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
    );
  }
}
