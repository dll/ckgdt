import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/dev_paths.dart';
import '../../../../core/error_handler.dart';

/// 归档内容浏览 Tab — 从 data/归档/归档/ 目录读取实际归档文件
class ArchiveContentTab extends StatefulWidget {
  const ArchiveContentTab({super.key});

  @override
  State<ArchiveContentTab> createState() => _ArchiveContentTabState();
}

class _ArchiveContentTabState extends State<ArchiveContentTab> {
  List<FileEntry> _files = [];
  bool _loading = true;
  String? _error;

  static const _archiveDir = 'data\\归档\\归档';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final dir = Directory('${DevPaths.projectRoot}\\$_archiveDir');
      if (!await dir.exists()) {
        if (mounted) {
          setState(() {
            _error = '归档目录不存在：${dir.path}';
            _loading = false;
          });
        }
        return;
      }

      final entities = await dir.list().toList();
      final files = <FileEntry>[];
      for (final e in entities) {
        if (e is! File) continue;
        final name = e.path.split('\\').last;
        final stat = await e.stat();
        files.add(FileEntry(
          name: name,
          path: e.path,
          size: stat.size,
          modified: stat.modified,
        ));
      }

      // Sort by numeric prefix, then by name
      files.sort((a, b) {
        final an = _extractNumber(a.name);
        final bn = _extractNumber(b.name);
        if (an != null && bn != null) return an.compareTo(bn);
        if (an != null) return -1;
        if (bn != null) return 1;
        return a.name.compareTo(b.name);
      });

      if (mounted) setState(() { _files = files; _loading = false; });
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveContentTab._loadFiles', stack: st);
      if (mounted) setState(() { _error = '读取归档目录失败：$e'; _loading = false; });
    }
  }

  int? _extractNumber(String name) {
    final m = RegExp(r'^(\d+)').firstMatch(name);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'docx': return Icons.description;
      case 'doc': return Icons.description;
      case 'xlsx': return Icons.table_chart;
      case 'xls': return Icons.table_chart;
      case 'md': return Icons.code;
      case 'webp': case 'png': case 'jpg': case 'jpeg': return Icons.image;
      case 'zip': return Icons.folder_zip;
      default: return Icons.insert_drive_file;
    }
  }

  Color _colorForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'docx': case 'doc': return Colors.blue;
      case 'xlsx': case 'xls': return Colors.green;
      case 'md': return Colors.orange;
      case 'webp': case 'png': case 'jpg': case 'jpeg': return Colors.purple;
      case 'zip': return Colors.brown;
      default: return Colors.grey;
    }
  }

  String _descriptionForFile(String name) {
    if (name.startsWith('0')) return '课程档案袋目录';
    if (name.startsWith('1')) return '教学大纲';
    if (name.startsWith('2')) return '课程教学大纲合理性评价表';
    if (name.startsWith('3')) return '教学进度表';
    if (name.startsWith('4')) return '理论教案';
    if (name.startsWith('5')) return '课程教学大纲合理性审核表';
    if (name.startsWith('6')) return '课程考核大作业';
    if (name.startsWith('7')) return '记分册';
    if (name.startsWith('8')) return '成绩登记表';
    if (name.startsWith('9')) return '课程考查说明';
    if (name.startsWith('10')) return '课程目标达成评价报告';
    if (name.startsWith('11')) return '教材封面';
    if (name.contains('zip')) return '归档压缩包（全部材料）';
    if (name.contains('达成')) return '课程目标达成评价报告';
    if (name.contains('达成评价表格')) return '达成评价表格';
    return name;
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
              Text(_error!, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
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
            Text('归档目录为空', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
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
                  Text('归档材料总览', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
                  const SizedBox(height: 4),
                  Text('共 ${_files.length} 个文件', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(_archiveDir, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // File list
          ...List.generate(_files.length, (i) {
            final entry = _files[i];
            final icon = _iconForFile(entry.name);
            final color = _colorForFile(entry.name);
            final desc = _descriptionForFile(entry.name);
            return Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, size: 18, color: color),
                ),
                title: Row(children: [
                  Expanded(
                    child: Text(desc != entry.name ? '$desc — ${entry.name}' : entry.name,
                        style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                  ),
                ]),
                subtitle: Text('${_formatSize(entry.size)} — ${entry.modified.toString().substring(0, 10)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                trailing: IconButton(
                  icon: Icon(Icons.open_in_new, size: 18, color: primary),
                  tooltip: '打开文件',
                  onPressed: () => _openFile(entry),
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          // Legend
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('编号说明', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
                  const SizedBox(height: 6),
                  _legendRow('0', '课程档案袋目录'),
                  _legendRow('1', '教学大纲'),
                  _legendRow('2', '大纲合理性评价表'),
                  _legendRow('3', '教学进度表'),
                  _legendRow('4', '理论教案'),
                  _legendRow('5', '大纲合理性审核表'),
                  _legendRow('6', '课程考核大作业'),
                  _legendRow('7', '记分册'),
                  _legendRow('8', '成绩登记表'),
                  _legendRow('9', '课程考查说明'),
                  _legendRow('10', '课程目标达成评价报告'),
                  _legendRow('11', '教材封面'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(String num, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Container(
          width: 24, alignment: Alignment.centerRight,
          child: Text(num, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]),
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
    try {
      await Process.run('explorer', [entry.path]);
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveContentTab._openFile', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件失败：$e')),
        );
      }
    }
  }
}

class FileEntry {
  final String name;
  final String path;
  final int size;
  final DateTime modified;

  FileEntry({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
  });
}
