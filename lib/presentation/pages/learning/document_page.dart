import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/course_dao.dart';
import '../../../services/courseware_service.dart';
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
              FilledButton.icon(
                onPressed: () => _showExtendedGenerateDialog(type),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('生成扩展课件'),
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

  /// 显示扩展课件生成对话框
  Future<void> _showExtendedGenerateDialog(String docType) async {
    final topicCtrl = TextEditingController();
    final extraCtrl = TextEditingController();

    // 获取课程信息
    String courseName = '移动应用开发';
    try {
      final course = await CourseDao().getActiveCourse();
      if (course != null) {
        courseName = course.name;
      }
    } catch (_) {}

    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool generating = false;
        String progress = '';

        return StatefulBuilder(builder: (ctx, setSheetState) {
          final bottomPadding = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 16, bottom: bottomPadding + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('生成扩展${docType == 'PDF' ? 'PDF' : 'PPT'}课件',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('AI 将根据您的需求生成实际的课件文件',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600]),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  TextField(
                    controller: topicCtrl,
                    enabled: !generating,
                    decoration: InputDecoration(
                      labelText: '课件主题 *',
                      hintText: '例如：Flutter 状态管理最佳实践',
                      prefixIcon: const Icon(Icons.topic),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: extraCtrl,
                    maxLines: 3,
                    enabled: !generating,
                    decoration: InputDecoration(
                      labelText: '额外要求（可选）',
                      hintText: '例如：侧重实战案例，包含代码示例...',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.edit_note),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (progress.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          if (generating)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (generating) const SizedBox(width: 8),
                          Expanded(
                            child: Text(progress,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: generating
                                      ? Colors.purple
                                      : Colors.green,
                                )),
                          ),
                        ],
                      ),
                    ),
                  FilledButton.icon(
                    icon: generating
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(generating ? '生成中...' : '开始生成'),
                    onPressed: generating
                        ? null
                        : () async {
                            final topic = topicCtrl.text.trim();
                            if (topic.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text('请输入课件主题')),
                              );
                              return;
                            }

                            setSheetState(() {
                              generating = true;
                              progress = '正在生成教案...';
                            });

                            try {
                              final extra = extraCtrl.text.trim();
                              final coursewareService = CoursewareService();
                              final db = await _dbHelper.database;

                              // Step 1: 生成教案
                              final lessonPlan =
                                  await coursewareService.generateLessonPlan(
                                topic: topic,
                                additionalRequirements: extra.isNotEmpty
                                    ? '课程：$courseName。$extra'
                                    : '课程：$courseName。请确保内容专业、实用。',
                              );
                              setSheetState(() =>
                                  progress = '正在生成 PDF 课件...');

                              // Step 2: 生成 PDF
                              final pdfPath =
                                  await coursewareService.generateEnhancedPdf(
                                lessonPlan: lessonPlan,
                              );

                              if (pdfPath == null) {
                                throw Exception('PDF 生成失败');
                              }

                              setSheetState(() =>
                                  progress = '正在保存到资源库...');

                              // Step 3: 保存到 resource_files
                              final safeName = topic.replaceAll(
                                  RegExp(r'[/\\:*?"<>|]'), '_');
                              final fileType =
                                  docType == 'PPT' ? 'ppt' : 'pdf';
                              final ext =
                                  docType == 'PPT' ? 'pptx' : 'pdf';
                              await db.insert('resource_files', {
                                'file_name': '扩展-$safeName.$ext',
                                'file_path': pdfPath,
                                'file_type': fileType,
                                'chapter': '扩展-$topic',
                                'description':
                                    '${lessonPlan['objectives']?.take(2).join('；') ?? topic}',
                                'source_type': 'extended',
                              });

                              setSheetState(() {
                                generating = false;
                                progress = '课件「$topic」生成完成！';
                              });

                              await Future.delayed(
                                  const Duration(milliseconds: 800));
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              setSheetState(() {
                                generating = false;
                                progress = '生成失败：$e';
                              });
                            }
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    if (result == true) {
      _loadDocuments();
    }
  }

  void _openDocument(Map<String, dynamic> doc) async {
    final filePath = doc['file_path'] as String? ?? '';
    final fileName = doc['file_name'] as String? ?? '';
    final fileType = doc['file_type'] as String? ?? '';
    final chapter = doc['chapter'] as String? ?? '';
    final isExtended = doc['source_type'] == 'extended';

    if (filePath.isEmpty) {
      if (isExtended) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该扩展课件尚未生成文件，请点击"生成扩展课件"按钮创建'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件路径未设置')),
        );
      }
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
