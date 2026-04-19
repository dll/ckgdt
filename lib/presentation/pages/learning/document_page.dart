import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/course_dao.dart';
import '../../../services/ai_service.dart';
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
  bool _generatingExtended = false;
  String _resourceMode = 'all'; // 'all', 'preset', 'extended'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final db = await _dbHelper.database;

      // 构建 source_type 过滤条件
      String sourceFilter = '';
      if (_resourceMode == 'preset') {
        sourceFilter = " AND (source_type = 'preset' OR source_type IS NULL)";
      } else if (_resourceMode == 'extended') {
        sourceFilter = " AND source_type = 'extended'";
      }

      final pdfs = await db.rawQuery(
        "SELECT * FROM resource_files WHERE file_type = 'pdf'$sourceFilter ORDER BY chapter",
      );

      final ppts = await db.rawQuery(
        "SELECT * FROM resource_files WHERE file_type = 'ppt'$sourceFilter ORDER BY chapter",
      );

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
      body: Column(
        children: [
          // 预制/扩展 切换栏
          _buildResourceModeBar(),
          Expanded(
            child: _isLoading
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
          ),
        ],
      ),
    );
  }

  Widget _buildResourceModeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'all', label: Text('全部')),
          ButtonSegment(value: 'preset', label: Text('预制')),
          ButtonSegment(value: 'extended', label: Text('扩展')),
        ],
        selected: {_resourceMode},
        onSelectionChanged: (Set<String> newSelection) {
          setState(() => _resourceMode = newSelection.first);
          _loadDocuments();
        },
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
              _resourceMode == 'extended'
                  ? '暂无扩展$type文档'
                  : '暂无$type文档',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              _resourceMode == 'extended'
                  ? '点击下方按钮，让 AI 自动生成扩展课件主题'
                  : '文档将从 Gitee 仓库自动获取',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            if (_resourceMode == 'extended') ...[
              const SizedBox(height: 20),
              _generatingExtended
                  ? const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('AI 正在生成扩展课件主题...',
                            style: TextStyle(fontSize: 13, color: Colors.purple)),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: _generateExtendedDocuments,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('AI 生成扩展课件'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.purple,
                      ),
                    ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final isExtended = doc['source_type'] == 'extended';
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isExtended ? Colors.purple : color,
              child: Icon(
                isExtended ? Icons.auto_awesome : icon,
                color: Colors.white,
              ),
            ),
            title: Text(doc['chapter'] ?? '文档'),
            subtitle: Row(
              children: [
                if (isExtended) ...[
                  Icon(Icons.auto_awesome,
                      size: 12, color: Colors.purple[300]),
                  const SizedBox(width: 4),
                  Text('AI 生成',
                      style: TextStyle(
                          fontSize: 11, color: Colors.purple[300])),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(doc['file_name'] ?? '')),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDocument(doc),
          ),
        );
      },
    );
  }

  Future<void> _generateExtendedDocuments() async {
    setState(() => _generatingExtended = true);

    try {
      final aiService = AiService();
      final db = await _dbHelper.database;

      // 获取当前课程信息
      String courseName = '移动应用开发';
      String chaptersInfo = '';
      try {
        final course = await CourseDao().getActiveCourse();
        if (course != null) {
          courseName = course.name;
          chaptersInfo = course.chapters
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value}')
              .join('\n');
        }
      } catch (_) {}

      if (chaptersInfo.isEmpty) {
        chaptersInfo = '1. 第一章\n2. 第二章\n3. 第三章';
      }

      final prompt = '''
基于《$courseName》课程的章节内容，为 PDF 和 PPT 各生成5个扩展学习主题。

课程章节：
$chaptersInfo

请生成以下JSON格式（直接返回JSON，不要包含其他文字）：
{
  "pdf": [
    {"chapter": "扩展-主题名称", "description": "30字以内的描述"},
    ...
  ],
  "ppt": [
    {"chapter": "扩展-主题名称", "description": "30字以内的描述"},
    ...
  ]
}

要求：
- PDF 和 PPT 各5个，合计10个
- 主题应超越课程预设内容，涵盖进阶/实战/前沿方向
- chapter字段以"扩展-"开头
- description字段30字以内
''';

      final raw = await aiService.chat(
        [{'role': 'user', 'content': prompt}],
        systemPrompt: '你是$courseName课程的教学设计专家，请用中文回复，仅返回合法JSON。',
      );

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (jsonMatch == null) throw Exception('AI 返回格式不正确');

      final data = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final batch = db.batch();

      for (final type in ['pdf', 'ppt']) {
        final items = data[type] as List<dynamic>? ?? [];
        for (final item in items) {
          final chapter = item['chapter'] as String? ?? '扩展课件';
          final desc = item['description'] as String? ?? '';
          final ext = type == 'ppt' ? 'pptx' : 'pdf';
          batch.insert('resource_files', {
            'file_name': '$chapter.$ext',
            'file_path': '',
            'file_type': type,
            'chapter': chapter,
            'description': desc,
            'source_type': 'extended',
          });
        }
      }

      await batch.commit(noResult: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('扩展课件主题生成成功！'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() => _generatingExtended = false);
      _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generatingExtended = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('生成失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
