import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/error_handler.dart';
import '../../../../services/archive_package_service.dart';

/// 归档内容浏览 Tab — 递归读取「一键归档」实际输出目录 archive_out/
/// （ArchivePackageService.outputRoot），让教师归档后立即看到自己的产物。
class ArchiveContentTab extends StatefulWidget {
  const ArchiveContentTab({super.key});

  @override
  State<ArchiveContentTab> createState() => _ArchiveContentTabState();
}

class _ArchiveContentTabState extends State<ArchiveContentTab> {
  List<FileEntry> _files = [];
  bool _loading = true;
  String? _error;

  String get _archiveRoot => ArchivePackageService.outputRoot ?? '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final root = _archiveRoot;
      if (root.isEmpty) {
        if (mounted) {
          setState(() {
            _error = '归档输出目录未初始化（仅桌面端可用）';
            _loading = false;
          });
        }
        return;
      }
      final dir = Directory(root);
      if (!await dir.exists()) {
        if (mounted) {
          setState(() {
            _error = '尚无归档产物。请先在期初/期中/期末用「一键归档」生成。\n目录：$root';
            _loading = false;
          });
        }
        return;
      }

      // archive_out 按 学期/课程/期 分层，递归收集 docx + zip
      final entities = await dir.list(recursive: true).toList();
      final files = <FileEntry>[];
      for (final e in entities) {
        if (e is! File) continue;
        final stat = await e.stat();
        files.add(FileEntry(
          name: p.basename(e.path),
          path: e.path,
          size: stat.size,
          modified: stat.modified,
          relPath: p.relative(e.path, from: root),
        ));
      }

      // 最近修改的排前面
      files.sort((a, b) => b.modified.compareTo(a.modified));

      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveContentTab._loadFiles', stack: st);
      if (mounted) {
        setState(() {
          _error = '读取归档目录失败：$e';
          _loading = false;
        });
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'docx':
        return Icons.description;
      case 'doc':
        return Icons.description;
      case 'xlsx':
        return Icons.table_chart;
      case 'xls':
        return Icons.table_chart;
      case 'md':
        return Icons.code;
      case 'webp':
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Icons.image;
      case 'zip':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _colorForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'docx':
      case 'doc':
        return Colors.blue;
      case 'xlsx':
      case 'xls':
        return Colors.green;
      case 'md':
        return Colors.orange;
      case 'webp':
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Colors.purple;
      case 'zip':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadFiles,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('归档目录为空',
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFiles,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.archive, size: 40, color: primary),
                  const SizedBox(height: 8),
                  Text('归档材料总览',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primary)),
                  const SizedBox(height: 4),
                  Text('共 ${_files.length} 个文件',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(_archiveRoot,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // File list（显示相对路径：学期/课程/期/文件名）
          ...List.generate(_files.length, (i) {
            final entry = _files[i];
            final icon = _iconForFile(entry.name);
            final color = _colorForFile(entry.name);
            return Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, size: 18, color: color),
                ),
                title: Text(entry.name,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${entry.relPath} · ${_formatSize(entry.size)} · ${entry.modified.toString().substring(0, 16)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: Icon(Icons.open_in_new, size: 18, color: primary),
                  tooltip: '在文件管理器中显示',
                  onPressed: () => _openFile(entry),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _openFile(FileEntry entry) async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web 端不支持直接打开本地文件')),
        );
      }
      return;
    }
    // 复用 ArchivePackageService 的跨平台「在文件管理器中显示」实现
    // （Windows explorer /select、macOS open -R、Linux xdg-open 父目录）。
    await ArchivePackageService.instance.revealInFileManager(entry.path);
  }
}

class FileEntry {
  final String name;
  final String path;
  final int size;
  final DateTime modified;

  /// 相对 archive_out 根的路径（学期/课程/期/文件名），用于列表副标题展示归档归属。
  final String relPath;

  FileEntry({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    required this.relPath,
  });
}
