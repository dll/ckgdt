import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/clipboard_helper.dart';
import '../../../services/tts_flutter_service.dart';
import '../learning/video_player_page.dart';

class LecturePage extends StatefulWidget {
  const LecturePage({super.key});

  @override
  State<LecturePage> createState() => _LecturePageState();
}

class _LecturePageState extends State<LecturePage> {
  String _content = '';
  List<String> _videoUrls = [];
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSpeaking = false;
  late TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
    _loadContent();
  }

  @override
  void dispose() {
    TtsFlutterService.instance.stop();
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'lecture_notes',
        where: 'course_id = ?',
        whereArgs: ['default'],
        limit: 1,
      );
      if (rows.isNotEmpty && rows.first['content'] != null && (rows.first['content'] as String).isNotEmpty) {
        _content = rows.first['content'] as String;
        _videoUrls = _parseVideoUrls(rows.first['video_urls']);
      } else {
        _content = await rootBundle.loadString('assets/说课/说课.md');
        _videoUrls = [];
        await db.update(
          'lecture_notes',
          {'content': _content, 'video_urls': jsonEncode(_videoUrls), 'updated_at': DateTime.now().toIso8601String()},
          where: 'course_id = ?',
          whereArgs: ['default'],
        );
      }
    } catch (e) {
      try {
        _content = await rootBundle.loadString('assets/说课/说课.md');
        _videoUrls = [];
      } catch (_) {
        _content = '# 说课\n\n内容加载失败。';
      }
    }
    _editCtrl.text = _content;
    if (mounted) setState(() => _isLoading = false);
  }

  List<String> _parseVideoUrls(dynamic value) {
    if (value == null) return [];
    try {
      final list = jsonDecode(value as String);
      return List<String>.from(list);
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveContent() async {
    _content = _editCtrl.text;
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'lecture_notes',
        {'content': _content, 'video_urls': jsonEncode(_videoUrls), 'updated_at': DateTime.now().toIso8601String()},
        where: 'course_id = ?',
        whereArgs: ['default'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('说课内容已保存')),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      final imported = await file.readAsString();
      _editCtrl.text = imported;
      _content = imported;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件已导入')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    setState(() => _videoUrls.add(path));
    _saveVideoUrls();
  }

  void _removeVideo(int index) {
    setState(() => _videoUrls.removeAt(index));
    _saveVideoUrls();
  }

  Future<void> _saveVideoUrls() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'lecture_notes',
        {'video_urls': jsonEncode(_videoUrls), 'updated_at': DateTime.now().toIso8601String()},
        where: 'course_id = ?',
        whereArgs: ['default'],
      );
    } catch (_) {}
  }

  Future<void> _speakContent() async {
    final tts = TtsFlutterService.instance;
    if (_isSpeaking) {
      await tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    if (_content.isEmpty) return;
    setState(() => _isSpeaking = true);
    await tts.speak(_content);
    if (mounted) setState(() => _isSpeaking = false);
  }

  void _openVideo(String path) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => InAppVideoPlayerPage(
        filePath: path,
        title: path.split(Platform.pathSeparator).last,
        chapter: '说课',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isPrint = AppGradientTheme.isPrint(context);
    final bgColor = isPrint ? Colors.white : Theme.of(context).scaffoldBackgroundColor;
    final textColor = isPrint ? Colors.black87 : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isPrint ? Colors.white : null,
        title: Text('说课', style: TextStyle(color: isPrint ? Colors.black87 : null)),
        iconTheme: IconThemeData(color: isPrint ? Colors.black87 : null),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
              tooltip: _isSpeaking ? '停止播报' : '语音播报',
              onPressed: _isLoading ? null : _speakContent,
            ),
            if (_videoUrls.isNotEmpty && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
              PopupMenuButton<String>(
                icon: const Icon(Icons.video_library_outlined),
                tooltip: '视频演示',
                onSelected: (path) => _openVideo(path),
                itemBuilder: (_) => _videoUrls.map((path) {
                  final name = path.split(Platform.pathSeparator).last;
                  return PopupMenuItem(value: path, child: Text(name, overflow: TextOverflow.ellipsis));
                }).toList(),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: _isLoading ? null : () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: '导入 .md',
              onPressed: _isLoading ? null : () async {
                await _importFromFile();
                if (_isEditing == false) setState(() => _isEditing = true);
              },
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制内容',
              onPressed: _isLoading ? null : () => ClipboardHelper.copyWithToast(context, _content),
            ),
          ],
          if (_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: '取消编辑',
              onPressed: () {
                _editCtrl.text = _content;
                setState(() => _isEditing = false);
              },
            ),
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '保存',
              onPressed: _saveContent,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isEditing
              ? _buildEditor(textColor)
              : _buildPreview(isPrint),
    );
  }

  Widget _buildEditor(Color textColor) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _editCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: textColor,
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.all(12),
                hintText: '输入 Markdown 内容...',
              ),
            ),
          ),
        ),
        _buildVideoEditor(),
      ],
    );
  }

  Widget _buildVideoEditor() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.video_library_outlined, size: 18),
              const SizedBox(width: 6),
              const Text('视频演示', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加视频'),
                onPressed: _addVideo,
              ),
            ],
          ),
          if (_videoUrls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('暂无视频，点击"添加视频"选择文件', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            )
          else
            ...List.generate(_videoUrls.length, (i) {
              final name = _videoUrls[i].split(Platform.pathSeparator).last;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.play_circle_outline, size: 20),
                title: Text(name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _removeVideo(i),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPreview(bool isPrint) {
    final showVideos = _videoUrls.isNotEmpty && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (!showVideos) {
      return Markdown(
        data: _content,
        selectable: true,
        styleSheet: _buildStyleSheet(isPrint),
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
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Markdown(
            data: _content,
            selectable: true,
            shrinkWrap: true,
            styleSheet: _buildStyleSheet(isPrint),
            onTapLink: (text, href, title) {
              if (href != null) {
                Clipboard.setData(ClipboardData(text: href));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制链接: $href')),
                );
              }
            },
          ),
        ),
        SliverToBoxAdapter(child: _buildVideoPreviewSection(isPrint)),
      ],
    );
  }

  Widget _buildVideoPreviewSection(bool isPrint) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPrint ? Colors.grey.shade50 : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isPrint ? Colors.grey.shade300 : Colors.grey.shade700.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.video_library, size: 20, color: isPrint ? Colors.black54 : null),
              const SizedBox(width: 6),
              Text('视频演示', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isPrint ? Colors.black87 : null)),
            ],
          ),
          const SizedBox(height: 8),
          if (_videoUrls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('暂无视频', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            )
          else
            ...List.generate(_videoUrls.length, (i) {
              final name = _videoUrls[i].split(Platform.pathSeparator).last;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.play_circle_fill, color: Colors.blue),
                  title: Text(name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _openVideo(_videoUrls[i]),
                ),
              );
            }),
        ],
      ),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(bool isPrint) {
    const accentColor = Color(0xFF1677FF);
    final textColor = isPrint ? Colors.black87 : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87);
    const baseFontSize = 14.0;
    final isDark = !isPrint && Theme.of(context).brightness == Brightness.dark;

    return MarkdownStyleSheet(
      p: TextStyle(fontSize: baseFontSize, height: 1.7, color: textColor),
      h1: TextStyle(fontSize: baseFontSize + 8, fontWeight: FontWeight.bold, height: 1.5, color: textColor),
      h2: TextStyle(fontSize: baseFontSize + 4, fontWeight: FontWeight.bold, height: 1.5, color: textColor),
      h3: TextStyle(fontSize: baseFontSize + 2, fontWeight: FontWeight.w600, height: 1.4, color: textColor),
      h4: TextStyle(fontSize: baseFontSize + 1, fontWeight: FontWeight.w600, height: 1.4, color: textColor),
      strong: TextStyle(fontWeight: FontWeight.bold, color: textColor),
      em: TextStyle(fontStyle: FontStyle.italic, color: textColor),
      code: TextStyle(fontFamily: 'monospace', fontSize: baseFontSize - 1, color: isDark ? Colors.amber[300] : Colors.deepPurple[700], backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.deepPurple.withValues(alpha: 0.06)),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2))),
      blockquoteDecoration: BoxDecoration(color: isDark ? accentColor.withValues(alpha: 0.08) : accentColor.withValues(alpha: 0.04), border: const Border(left: BorderSide(color: accentColor, width: 4))),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      listBullet: const TextStyle(fontSize: baseFontSize, color: accentColor),
      tableHead: TextStyle(fontSize: baseFontSize - 1, fontWeight: FontWeight.bold, color: textColor),
      tableBody: TextStyle(fontSize: baseFontSize - 1, color: textColor),
      tableBorder: TableBorder.all(color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.3)),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.3)))),
      blockSpacing: 10,
    );
  }
}
