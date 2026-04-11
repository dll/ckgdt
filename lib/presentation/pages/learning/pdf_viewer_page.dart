import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../../services/file_opener_service.dart';

/// 应用内 PDF 查看器
/// 使用 printing 包的 PdfPreview 组件渲染 PDF 页面
/// AppBar 提供"使用系统工具打开"和"打印"按钮
class InAppPdfViewerPage extends StatefulWidget {
  final String filePath;
  final String title;

  const InAppPdfViewerPage({
    super.key,
    required this.filePath,
    required this.title,
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
    throw '文件不存在: ${widget.filePath}';
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('打印失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
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
                  color: Colors.grey.withValues(alpha: 0.3),
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
