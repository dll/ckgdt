import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../../services/auth_service.dart';
import '../../../services/file_opener_service.dart';
import '../../../services/gitee_service.dart';
import '../../../services/tts_flutter_service.dart';
import '../../pages/quiz/quiz_page.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

/// 应用内 PDF 查看器
/// 使用 printing 包的 PdfPreview 组件渲染 PDF 页面
/// AppBar 提供"使用系统工具打开"、"打印"和"章节测验"按钮
///
/// **跨设备路径回退**：file_paths 在不同设备绝对路径不同，本地不存在时
/// 自动尝试从 Gitee 同步仓库按 fileName 下载（实验 PDF 走 sync_files 目录）。
class InAppPdfViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final String? chapter;

  /// 用于回退下载：当 [filePath] 在本机找不到时，按 fileName 从远程拉。
  /// 学生侧由提交后的 file_names 字段填入；如不传则不回退。
  final String? remoteFileName;

  /// 远程文件归属用户 ID（学生跨设备同步用本人；教师批阅时填学生 ID）
  final String? remoteUserId;

  const InAppPdfViewerPage({
    super.key,
    required this.filePath,
    required this.title,
    this.chapter,
    this.remoteFileName,
    this.remoteUserId,
  });

  @override
  State<InAppPdfViewerPage> createState() => _InAppPdfViewerPageState();
}

class _InAppPdfViewerPageState extends State<InAppPdfViewerPage> {
  late Future<File> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = _prepareFile();
  }

  Future<File> _prepareFile() async {
    final file = File(widget.filePath);
    if (await file.exists()) {
      return file;
    }
    // 本机不存在 → 尝试 Gitee 远程拉
    final remote = await _tryDownloadFromRemote();
    if (remote != null) return remote;
    throw '文件不存在: ${widget.filePath}\n（远程仓库也未找到该文件）';
  }

  /// 按 fileName + userId 从 Gitee 同步仓库下载到本地 sync_files 目录
  Future<File?> _tryDownloadFromRemote() async {
    final fileName = widget.remoteFileName;
    final userId =
        widget.remoteUserId ?? AuthService().currentUser?.userId;
    if (fileName == null || fileName.isEmpty || userId == null) return null;
    try {
      final gitee = GiteeService();
      // 与 SyncService._downloadSubmissionFile 同步策略：先 实验/ 后 files/
      // 仓库参数与 SyncService 同源（chzcldl/mad-kgdt master sync/students）
      List<int>? bytes;
      for (final subDir in ['实验', 'files']) {
        final remotePath = 'sync/students/$userId/$subDir/$fileName';
        try {
          bytes = await gitee.downloadBinaryFile(
            owner: 'osgisOne',
            repo: 'mad-fd',
            path: remotePath,
            branch: 'master',
          );
          if (bytes != null && bytes.isNotEmpty) break;
        } catch (e) { swallowDebug(e, tag: 'pdf_viewer_page'); }
      }
      if (bytes == null || bytes.isEmpty) return null;
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/sync_files/$userId');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final localFile = File('${dir.path}/$fileName');
      await localFile.writeAsBytes(bytes);
      return localFile;
    } catch (e) {
      debugPrint('PdfViewer: 远程拉取失败 $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '使用系统工具打开',
            onPressed: () {
              FileOpenerService.openExternalFile(context, widget.filePath);
            },
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: '打印',
            onPressed: () async {
              try {
                final bytes = await File(widget.filePath).readAsBytes();
                await Printing.layoutPdf(onLayout: (_) => bytes);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('打印失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
          // 学完即测按钮
          FilledButton.icon(
            onPressed: () {
              TtsFlutterService.instance.speak('正在跳转到章节测验');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const QuizPage(),
                ),
              );
            },
            icon: const Icon(Icons.quiz, size: 16),
            label: const Text('去测验'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<File>(
        future: _fileFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }

          if (!snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('加载 PDF...'),
                ],
              ),
            );
          }

          return PdfPreview(
            build: (_) => snapshot.data!.readAsBytes(),
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            initialPageFormat: PdfPageFormat.a4,
            pdfPreviewPageDecoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('使用系统工具打开'),
              onPressed: () {
                FileOpenerService.openExternalFile(context, widget.filePath);
              },
            ),
          ],
        ),
      ),
    );
  }
}
