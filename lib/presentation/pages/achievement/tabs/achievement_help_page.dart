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
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHelp();
  }

  Future<void> _loadHelp() async {
    try {
      final raw = await rootBundle.loadString('assets/help/achievement_help.md');
      if (mounted) setState(() { _content = raw; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _content = '加载帮助手册失败：$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: BackButtonBar(
        title: '达成度评价帮助',
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '关于',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('达成度评价帮助手册'),
                content: const Text(
                  '本手册详细介绍如何使用课程达成度评价系统，'
                  '从上传大纲到生成 Word 报告的完整流程。\n\n'
                  '如需更多帮助，请使用页面右上角的智慧助手。',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('了解')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Markdown(
              data: _content,
              padding: const EdgeInsets.all(16),
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                h1: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primary),
                h2: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary),
                h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
                p: const TextStyle(fontSize: 14, height: 1.6),
                tableHead: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                tableBody: const TextStyle(fontSize: 13),
                codeblockDecoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(left: BorderSide(color: primary, width: 3)),
                ),
              ),
            ),
    );
  }
}
