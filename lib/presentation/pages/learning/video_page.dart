import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/course_dao.dart';
import '../../../services/courseware_service.dart';
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
  String _resourceMode = 'all'; // 'all', 'preset', 'extended'

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    try {
      final db = await _dbHelper.database;

      // 构建查询条件
      final whereParts = <String>['file_type = ?'];
      final whereArgs = <dynamic>['video'];

      if (widget.filterChapter != null && widget.filterChapter!.isNotEmpty) {
        whereParts.add('chapter LIKE ?');
        whereArgs.add('%${widget.filterChapter}%');
      }

      // 预制/扩展过滤
      if (_resourceMode == 'preset') {
        whereParts.add("(source_type = 'preset' OR source_type IS NULL)");
      } else if (_resourceMode == 'extended') {
        whereParts.add("source_type = 'extended'");
      }

      final result = await db.query(
        'resource_files',
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'chapter',
      );

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
      body: Column(
        children: [
          // 预制/扩展 切换栏
          _buildResourceModeBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _videos.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _videos.length,
                        itemBuilder: (context, index) {
                          final video = _videos[index];
                          final isExtended = video['source_type'] == 'extended';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    isExtended ? Colors.purple : Colors.red,
                                child: Icon(
                                  isExtended
                                      ? Icons.auto_awesome
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(video['chapter'] ?? '视频'),
                              subtitle: Row(
                                children: [
                                  if (isExtended) ...[
                                    Icon(Icons.auto_awesome,
                                        size: 12, color: Colors.purple[300]),
                                    const SizedBox(width: 4),
                                    Text('AI 生成',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.purple[300])),
                                    const SizedBox(width: 8),
                                  ],
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
          _loadVideos();
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
                : _resourceMode == 'extended'
                    ? '暂无扩展视频'
                    : '暂无视频教程',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            _resourceMode == 'extended'
                ? '点击下方按钮，让 AI 自动生成扩展视频主题'
                : '视频将从 Gitee 仓库自动获取',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          if (_resourceMode == 'extended') ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _showExtendedVideoDialog,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('生成扩展视频课件'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.purple,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 显示扩展视频生成对话框（实际生成 PDF 课件脚本）
  Future<void> _showExtendedVideoDialog() async {
    final topicCtrl = TextEditingController();

    // 获取课程信息
    String courseName = '移动应用开发';
    try {
      final course = await CourseDao().getActiveCourse();
      if (course != null) courseName = course.name;
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
                  const Text('生成扩展视频课件',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('AI 将生成视频教学脚本 PDF，可通过课件工坊合成视频',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  TextField(
                    controller: topicCtrl,
                    enabled: !generating,
                    decoration: InputDecoration(
                      labelText: '视频主题 *',
                      hintText: '例如：Flutter 动画系统详解',
                      prefixIcon: const Icon(Icons.topic),
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
                                  color: generating ? Colors.purple : Colors.green,
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
                                const SnackBar(content: Text('请输入视频主题')),
                              );
                              return;
                            }

                            setSheetState(() {
                              generating = true;
                              progress = '正在生成教案...';
                            });

                            try {
                              final coursewareService = CoursewareService();
                              final db = await _dbHelper.database;

                              // Step 1: 生成教案
                              final lessonPlan =
                                  await coursewareService.generateLessonPlan(
                                topic: topic,
                                additionalRequirements:
                                    '课程：$courseName。请生成适合视频教学的内容，包含演示步骤和代码示例。',
                              );
                              setSheetState(() =>
                                  progress = '正在生成 PDF 讲义...');

                              // Step 2: 生成 PDF 讲义
                              final pdfPath =
                                  await coursewareService.generateEnhancedPdf(
                                lessonPlan: lessonPlan,
                              );

                              if (pdfPath == null) {
                                throw Exception('PDF 生成失败');
                              }

                              setSheetState(() => progress = '正在保存...');

                              // Step 3: 保存到 resource_files
                              final safeName = topic.replaceAll(
                                  RegExp(r'[/\\:*?"<>|]'), '_');
                              await db.insert('resource_files', {
                                'file_name': '扩展-$safeName.mp4',
                                'file_path': pdfPath,
                                'file_type': 'video',
                                'chapter': '扩展-$topic',
                                'description':
                                    '${lessonPlan['title'] ?? topic} - 视频讲义',
                                'source_type': 'extended',
                              });

                              setSheetState(() {
                                generating = false;
                                progress = '视频讲义「$topic」生成完成！';
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
      _loadVideos();
    }
  }

  void _playVideo(Map<String, dynamic> video) async {
    final filePath = video['file_path'] as String? ?? '';
    final fileName =
        video['file_name'] as String? ?? '${video['chapter']}.mp4';
    final fileType = video['file_type'] as String? ?? 'video';
    final chapter = video['chapter'] as String? ?? '';
    final isExtended = video['source_type'] == 'extended';

    if (filePath.isEmpty) {
      if (isExtended) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该扩展视频尚未生成文件，请点击"生成扩展视频课件"按钮创建'),
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
