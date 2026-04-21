import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import '../../widgets/agent_entry_button.dart';

/// 实验材料 Markdown 在线预览页面
///
/// 支持从 assets 或设备文件系统加载 .md 文件，
/// 使用 flutter_markdown 渲染，提供下载到本地功能。
class LabMaterialPreviewPage extends StatefulWidget {
  /// asset 路径（如 'data/实验/实验教程/实验一 开发环境搭建_new.md'）
  final String? assetPath;

  /// 设备文件路径（教师新增的材料存储在本地）
  final String? filePath;

  /// 显示标题
  final String title;

  /// 关联的 AI 智能体 ID（学生 'lab'，教师 'lab_grading'）
  final String agentId;

  const LabMaterialPreviewPage({
    super.key,
    this.assetPath,
    this.filePath,
    required this.title,
    this.agentId = 'lab',
  }) : assert(assetPath != null || filePath != null);

  @override
  State<LabMaterialPreviewPage> createState() => _LabMaterialPreviewPageState();
}

class _LabMaterialPreviewPageState extends State<LabMaterialPreviewPage> {
  String _content = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      String content;
      if (widget.assetPath != null) {
        content = await rootBundle.loadString(widget.assetPath!);
      } else {
        content = await File(widget.filePath!).readAsString();
      }
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadToLocal() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web 平台暂不支持下载')),
        );
      }
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final labDir = Directory('${dir.path}/lab_materials');
      if (!await labDir.exists()) {
        await labDir.create(recursive: true);
      }

      // 从标题生成文件名
      final fileName = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${labDir.path}/$fileName.md');
      await file.writeAsString(_content);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已下载到：${file.path}'),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () {
                // 仅 Windows/macOS 支持
                if (Platform.isWindows) {
                  Process.run('explorer', [labDir.path]);
                } else if (Platform.isMacOS) {
                  Process.run('open', [labDir.path]);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '下载到本地',
            onPressed: _isLoading ? null : _downloadToLocal,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制内容',
            onPressed: _isLoading
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  },
          ),
          AgentEntryButton(agentId: widget.agentId),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载文档...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    return Markdown(
      data: _content,
      selectable: true,
      styleSheet: _buildStyleSheet(isDark),
      onTapLink: (text, href, title) {
        if (href != null) {
          Clipboard.setData(ClipboardData(text: href));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已复制链接: $href')),
          );
        }
      },
    );
  }

  MarkdownStyleSheet _buildStyleSheet(bool isDark) {
    const accentColor = Color(0xFF667eea);
    final baseTextColor = isDark ? Colors.white : Colors.black87;
    const baseFontSize = 14.0;

    return MarkdownStyleSheet(
      p: TextStyle(fontSize: baseFontSize, height: 1.7, color: baseTextColor),
      h1: TextStyle(
          fontSize: baseFontSize + 8,
          fontWeight: FontWeight.bold,
          height: 1.5,
          color: baseTextColor),
      h2: TextStyle(
          fontSize: baseFontSize + 4,
          fontWeight: FontWeight.bold,
          height: 1.5,
          color: baseTextColor),
      h3: TextStyle(
          fontSize: baseFontSize + 2,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: baseTextColor),
      h4: TextStyle(
          fontSize: baseFontSize + 1,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: baseTextColor),
      strong: TextStyle(fontWeight: FontWeight.bold, color: baseTextColor),
      em: TextStyle(fontStyle: FontStyle.italic, color: baseTextColor),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: baseFontSize - 1,
        color: isDark ? Colors.amber[300] : Colors.deepPurple[700],
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.deepPurple.withValues(alpha: 0.06),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      blockquoteDecoration: BoxDecoration(
        color: isDark
            ? accentColor.withValues(alpha: 0.08)
            : accentColor.withValues(alpha: 0.04),
        border: const Border(left: BorderSide(color: accentColor, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      listBullet:
          const TextStyle(fontSize: baseFontSize, color: accentColor),
      tableHead: TextStyle(
          fontSize: baseFontSize - 1,
          fontWeight: FontWeight.bold,
          color: baseTextColor),
      tableBody:
          TextStyle(fontSize: baseFontSize - 1, color: baseTextColor),
      tableBorder: TableBorder.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.3),
      ),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
      ),
      blockSpacing: 10,
    );
  }
}
