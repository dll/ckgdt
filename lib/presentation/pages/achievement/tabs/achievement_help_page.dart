import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../widgets/back_button_bar.dart';

/// 达成度评价系统帮助手册页面
class AchievementHelpPage extends StatefulWidget {
  const AchievementHelpPage({super.key});

  @override
  State<AchievementHelpPage> createState() => _AchievementHelpPageState();
}

class _AchievementHelpPageState extends State<AchievementHelpPage> {
  static const _assetPath = 'assets/help/achievement_help.md';

  final _scrollController = ScrollController();
  String _content = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHelp();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHelp() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await _readHelpMarkdown();
      if (!mounted) return;
      setState(() {
        _content = raw;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _content = '';
        _error = '加载帮助手册失败：$e';
        _loading = false;
      });
    }
  }

  Future<String> _readHelpMarkdown() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      if (raw.trim().isNotEmpty) return raw;
    } catch (_) {
      // 继续尝试读取开发目录或安装目录旁边的 Markdown 文件。
    }

    for (final file in _localHelpCandidates()) {
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) return raw;
      }
    }
    throw StateError('未找到 $_assetPath');
  }

  Iterable<File> _localHelpCandidates() sync* {
    yield File(_assetPath);

    if (Platform.isAndroid || Platform.isIOS) return;
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 6; i++) {
      yield File(_joinPath(dir.path, _assetPath));
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }

  String _joinPath(String root, String relativePath) {
    final parts = relativePath.split('/');
    return [root, ...parts].join(Platform.pathSeparator);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Scaffold(
      appBar: BackButtonBar(
        title: '达成度评价帮助',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _loading ? null : _loadHelp,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '关于',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('达成度评价帮助手册'),
                content: const Text(
                  '本手册介绍课程达成度评价的 8 个菜单流程：'
                  '导入大纲、导入成绩、计算过程、平时达成、实验达成、'
                  '考核达成、持续改进和生成报告。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('了解'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(primary, theme.dividerColor),
    );
  }

  Widget _buildBody(Color primary, Color dividerColor) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 54, color: Colors.grey[500]),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadHelp,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: Markdown(
        data: _content,
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 18, 28, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          h1: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: primary,
            height: 1.4,
          ),
          h2: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: primary,
            height: 1.45,
          ),
          h3: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: primary,
            height: 1.45,
          ),
          p: const TextStyle(fontSize: 14, height: 1.65),
          listBullet: const TextStyle(fontSize: 14, height: 1.55),
          tableHead: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tableBody: const TextStyle(fontSize: 13, height: 1.45),
          tableBorder: TableBorder.all(color: dividerColor, width: 0.6),
          tableCellsPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          tableScrollbarThumbVisibility: true,
          codeblockPadding: const EdgeInsets.all(12),
          codeblockDecoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          blockquoteDecoration: BoxDecoration(
            border: Border(left: BorderSide(color: primary, width: 3)),
          ),
        ),
      ),
    );
  }
}
