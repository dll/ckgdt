import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path/path.dart' as p;
import '../../../core/constants/app_theme.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/clipboard_helper.dart';
import '../../../services/tts_flutter_service.dart';
import '../../../services/tts_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/output_path_service.dart';
import '../../../services/ai_service.dart';
import '../../../services/lecture_video_service.dart';
import '../../../data/local/class_dao.dart';
import '../../../data/local/teaching_dao.dart';
import '../../../services/archive/native_pdf_service.dart';
import '../../../services/video_service.dart';
import '../learning/video_player_page.dart';

class LecturePage extends StatefulWidget {
  const LecturePage({super.key});
  @override
  State<LecturePage> createState() => _LecturePageState();
}

class _LecturePageState extends State<LecturePage> with TickerProviderStateMixin {
  String _content = '';
  String _script = '';
  List<Map<String, String>> _videos = [];
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSpeaking = false;
  bool _generating = false;
  String _genStatus = '';
  int _genProgress = 0;
  int _genTotal = 0;
  late TextEditingController _editCtrl;
  late TextEditingController _scriptCtrl;
  late TabController _tabCtrl;

  String _teacherName = '';
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _syllabus = [];
  List<Map<String, dynamic>> _progress = [];
  int _totalStudents = 0;
  String _courseName = '';
  String _majorInfo = '';

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
    _scriptCtrl = TextEditingController();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadContent();
  }

  @override
  void dispose() {
    TtsFlutterService.instance.stop();
    _editCtrl.dispose();
    _scriptCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  String get _dataDir => 'data/$_courseName';

  Future<String> _getLectureOutDir() async {
    final outRoot = await OutputPathService.getOutputDirectory();
    final dir = Directory(p.join(outRoot.path, '说课'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _loadContent() async {
    _courseName = CourseContextService.defaultCourseName;
    await _gatherContextData();
    try {
      await _loadFromFileSystem();
      if (_content.isNotEmpty) {
        _editCtrl.text = _content;
        await _saveToDb(_content);
        _scanVideoDirs();
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    } catch (_) {}

    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('lecture_notes', where: 'course_id = ?', whereArgs: ['default'], limit: 1);
      if (rows.isNotEmpty && rows.first['content'] != null && (rows.first['content'] as String).isNotEmpty) {
        _content = rows.first['content'] as String;
        _videos = _parseVideos(rows.first['video_urls']);
        _script = rows.first['script'] as String? ?? '';
      } else {
        _content = await rootBundle.loadString('assets/说课/说课.md');
        if (_teacherName.isNotEmpty) _content = await _buildCompleteLecture();
        await _saveToDb(_content);
      }
    } catch (e) {
      try {
        _content = await rootBundle.loadString('assets/说课/说课.md');
      } catch (_) {
        _content = '# 说课\n\n内容加载失败。';
      }
    }
    _editCtrl.text = _content;
    _scriptCtrl.text = _script;
    _scanVideoDirs();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadFromFileSystem() async {
    final candidates = ['$_dataDir/说课/说课.md'];
    for (final relative in candidates) {
      final file = File(relative);
      if (await file.exists()) {
        _content = await file.readAsString();
        _videos = [];
        return;
      }
    }
    throw Exception('说课文件未找到');
  }

  void _scanVideoDirs() {
    _videos = _parseVideos(null);
    final dirs = ['$_dataDir/视频', '$_dataDir/说课'];
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync()) {
        if (f is File) {
          final ext = f.path.split('.').last.toLowerCase();
          if (['mp4', 'avi', 'mkv', 'mov'].contains(ext)) {
            final name = f.path.split(Platform.pathSeparator).last;
            if (!_videos.any((v) => v['path'] == f.path)) {
              _videos.add({'path': f.path, 'name': name, 'type': 'local'});
            }
          }
        }
      }
    }
    _saveVideos();
  }

  Future<void> _gatherContextData() async {
    try {
      final auth = AuthService();
      _teacherName = auth.currentUser?.realName ?? '';
      final teacherId = auth.currentUser?.userId ?? '';
      if (teacherId.isNotEmpty) {
        try {
          final classDao = ClassDao();
          _classes = await classDao.getTeacherClasses(teacherId);
          for (final c in _classes) { _totalStudents += (c['student_count'] as int? ?? 0); }
        } catch (_) {}
      }
      try {
        final teachingDao = TeachingDao();
        _syllabus = await teachingDao.getAllSyllabusItems();
        _progress = await teachingDao.getAllTeachingProgress();
      } catch (_) {}
      try {
        await _loadClassesFromExcel();
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _loadClassesFromExcel() async {
    final xlsxPath = p.join('data', _courseName, '用户', '学生名单.xlsx');
    const altPath = 'data/课程知识图谱与数字孪生/用户/学生名单.xlsx';
    String? found;
    if (await File(xlsxPath).exists()) { found = xlsxPath; }
    else if (await File(altPath).exists()) { found = altPath; }
    if (found == null) return;

    final bytes = await File(found).readAsBytes();
    final excel = xl.Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null || sheet.rows.length < 2) return;

    final headerRow = sheet.row(0);
    final headers = headerRow.map((c) => c?.value?.toString() ?? '').toList();
    int classCol = headers.indexWhere((h) => h.contains('班级'));
    int majorCol = headers.indexWhere((h) => h.contains('专业'));
    int deptCol = headers.indexWhere((h) => h.contains('院系'));
    if (classCol < 0) return;

    final Map<String, int> classCount = {};
    final Set<String> majors = {};
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.row(i);
      final cls = row.length > classCol ? (row[classCol]?.value?.toString() ?? '').trim() : '';
      if (cls.isEmpty) continue;
      classCount[cls] = (classCount[cls] ?? 0) + 1;
      if (majorCol >= 0 && row.length > majorCol) {
        final m = row[majorCol]?.value?.toString() ?? '';
        if (m.isNotEmpty) majors.add(m);
      }
      if (deptCol >= 0 && _majorInfo.isEmpty && row.length > deptCol) {
        final d = row[deptCol]?.value?.toString() ?? '';
        if (d.isNotEmpty && !_majorInfo.contains(d)) {
          _majorInfo += '${_majorInfo.isEmpty ? '' : '·'}$d';
        }
      }
    }
    if (_majorInfo.isEmpty && majors.isNotEmpty) _majorInfo = majors.join('·');
    final newClasses = <Map<String, dynamic>>[];
    int total = 0;
    for (final entry in classCount.entries) {
      newClasses.add({'name': entry.key, 'student_count': entry.value, 'major': majors.isNotEmpty ? majors.join('、') : ''});
      total += entry.value;
    }
    if (newClasses.isNotEmpty) { _classes = newClasses; _totalStudents = total; }
  }

  Future<String> _buildCompleteLecture() async {
    final buf = StringBuffer();
    buf.writeln('# 《$_courseName》说课'); buf.writeln();
    if (_teacherName.isNotEmpty) { buf.writeln('**说课教师**：$_teacherName'); buf.writeln(); }
    if (_classes.isNotEmpty) {
      buf.writeln('## 授课班级'); buf.writeln();
      buf.writeln('| 班级 | 人数 | 专业 |'); buf.writeln('|------|:---:|------|');
      for (final c in _classes) {
        final major = c['major'] as String? ?? _majorInfo;
        buf.writeln('| ${c['name']} | ${c['student_count'] ?? 0} | $major |');
      }
      buf.writeln('| **合计** | **$_totalStudents** | |'); buf.writeln();
      if (_majorInfo.isNotEmpty) { buf.writeln('**涉及专业**：$_majorInfo'); buf.writeln(); }
    }
    if (_syllabus.isNotEmpty) {
      buf.writeln('## 教学大纲'); buf.writeln();
      buf.writeln('| 章 | 主题 | 学时 |'); buf.writeln('|:--:|------|:---:|');
      for (final item in _syllabus) {
        buf.writeln('| ${item['chapter_number']} | ${item['title']} | ${item['hours'] ?? 2} |');
      }
      buf.writeln();
    }
    if (_progress.isNotEmpty) {
      buf.writeln('## 教学进度'); buf.writeln();
      buf.writeln('| 章 | 主题 | 状态 |'); buf.writeln('|:--:|------|:----:|');
      for (final p in _progress) {
        buf.writeln('| ${p['chapter']} | ${p['topic'] ?? ''} | ${p['status'] ?? 'planned'} |');
      }
      buf.writeln();
    }
    buf.writeln('---'); buf.writeln();
    buf.writeln('## 说课正文'); buf.writeln();
    buf.writeln('《$_courseName》（CKGDT）是面向多课程的 Flutter 全平台教学平台。系统围绕"教—学—练—评—管"五个维度构建：知识图谱浏览、章节测验、视频教程、课程资料、实验管理、作品展示、成绩达成、AI 多智能体辅助。支持教师端和学生端差异化导航。');
    return buf.toString();
  }

  String _stripMarkdown(String md) {
    var text = md;
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    text = text.replaceAll(RegExp(r'`[^`]+`'), '');
    text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), '');
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'[*_]{1,3}'), '');
    text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'\|'), ' ');
    text = text.replaceAll(RegExp(r'^[-:\s|]+$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  List<Map<String, String>> _parseVideos(dynamic value) {
    final list = <Map<String, String>>[];
    if (value != null) {
      try {
        final raw = jsonDecode(value as String);
        if (raw is List) {
          for (final item in raw) {
            if (item is String) {
              final name = item.split(Platform.pathSeparator).last;
              list.add({'path': item, 'name': name, 'type': 'legacy'});
            } else if (item is Map) {
              list.add({'path': item['path'] as String? ?? '', 'name': item['name'] as String? ?? '', 'type': item['type'] as String? ?? 'unknown'});
            }
          }
        }
      } catch (_) {}
    }
    return list;
  }

  Future<void> _saveToDb(String content) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('lecture_notes', where: 'course_id = ?', whereArgs: ['default'], limit: 1);
      final data = {'content': content, 'video_urls': jsonEncode(_videos), 'script': _script, 'updated_at': DateTime.now().toIso8601String()};
      if (rows.isEmpty) {
        await db.insert('lecture_notes', {'course_id': 'default', 'title': '说课', ...data});
      } else {
        await db.update('lecture_notes', data, where: 'course_id = ?', whereArgs: ['default']);
      }
    } catch (_) {}
  }

  Future<void> _saveContent() async {
    _content = _editCtrl.text;
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update('lecture_notes', {'content': _content, 'video_urls': jsonEncode(_videos), 'script': _script, 'updated_at': DateTime.now().toIso8601String()}, where: 'course_id = ?', whereArgs: ['default']);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('说课内容已保存'))); setState(() => _isEditing = false); }
    } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red)); } }
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['md', 'markdown', 'txt']);
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      final imported = await file.readAsString();
      _editCtrl.text = imported; _content = imported;
      if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件已导入'))); }
    } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red)); } }
  }

  void _openVideo(String path) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => InAppVideoPlayerPage(
      filePath: path,
      title: path.split(Platform.pathSeparator).last,
      chapter: '说课',
    )));
  }

  void _openVideoInApp(String path) {
    _tabCtrl.animateTo(2);
    setState(() {});
  }

  Future<void> _exportPdf() async {
    try {
      final pdfBytes = await NativePdfService.instance.markdownToPdf(_content);
      final outDir = await _getLectureOutDir();
      final path = p.join(outDir, '说课_$_courseName.pdf');
      await File(path).writeAsBytes(pdfBytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF 已导出: $path'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF 导出失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _generateAiScript() async {
    if (_content.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先编辑说课内容'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _generating = true);
    try {
      final ai = AiService();
      final prompt = '''
你是一位教学说课专家。根据以下说课文档内容，生成一份口播配音脚本。

要求：
- 语言口语化、自然流畅，适合 TTS 朗读
- 使用"尊敬的各位评委老师，大家好"开头
- 涵盖：开场介绍、课程定位、教学内容、教学方法、实践环节、考核评价、教学改革、结语
- 每个段落 100-200 字
- 段落之间用空行分隔
- 总字数 1500-2500 字
- 必须基于以下具体内容生成，不使用通用模板

说课文档内容：
$_content
''';
      final result = await ai.chat([{'role': 'user', 'content': prompt}], systemPrompt: '你是一位教学督导专家，擅长撰写教师说课口播稿。');
      if (result.isNotEmpty) {
        _script = result;
        _scriptCtrl.text = _script;
        await _saveToDb(_content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配音脚本已生成'), backgroundColor: Colors.green));
          _tabCtrl.animateTo(1);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('脚本生成失败: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _generating = false);
  }

  Future<void> _generateLectureVideo() async {
    setState(() { _generating = true; _genProgress = 0; _genTotal = 6; _genStatus = '正在生成视频脚本...'; });

    try {
      final outDir = await _getLectureOutDir();
      final service = LectureVideoService();

      await service.generateVideo(
        lectureContent: _content,
        courseName: _courseName,
        teacherName: _teacherName,
        classes: _classes,
        totalStudents: _totalStudents,
        outputDir: outDir,
        onProgress: (current, total, message) {
          if (mounted) setState(() { _genProgress = current; _genTotal = total; _genStatus = message; });
        },
      );

      if (mounted) {
        setState(() { _generating = false; });
        _scanVideoDirs();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('说课视频已生成到: $outDir'),
          backgroundColor: Colors.green,
          action: SnackBarAction(label: '查看视频', onPressed: () => _tabCtrl.animateTo(2)),
        ));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LecturePage.generateVideo', stack: st);
      if (mounted) {
        setState(() { _generating = false; _genStatus = '生成失败'; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('视频生成失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _speakContent() async {
    final tts = TtsFlutterService.instance;
    if (_isSpeaking) { await tts.stop(); if (mounted) setState(() => _isSpeaking = false); return; }
    final text = _script.isNotEmpty ? _script : _stripMarkdown(_content);
    if (text.isEmpty) return;
    setState(() => _isSpeaking = true);
    await tts.speak(text);
    if (mounted) setState(() => _isSpeaking = false);
  }

  void _addVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp4', 'avi', 'mkv', 'mov']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path; if (path == null) return;
    final name = path.split(Platform.pathSeparator).last;
    setState(() => _videos.add({'path': path, 'name': name, 'type': 'picked'}));
    _saveVideos();
  }

  void _removeVideo(int index) { setState(() => _videos.removeAt(index)); _saveVideos(); }

  Future<void> _saveVideos() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update('lecture_notes', {'video_urls': jsonEncode(_videos), 'updated_at': DateTime.now().toIso8601String()}, where: 'course_id = ?', whereArgs: ['default']);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isPrint = AppGradientTheme.isPrint(context);
    final bgColor = isPrint ? Colors.white : Theme.of(context).scaffoldBackgroundColor;
    final textColor = isPrint ? Colors.black87 : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87);
    final accentColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isPrint ? Colors.white : null,
        title: const Text('说课'),
        iconTheme: IconThemeData(color: isPrint ? Colors.black87 : null),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: accentColor,
          unselectedLabelColor: textColor.withValues(alpha: 0.6),
          tabs: const [
            Tab(icon: Icon(Icons.article_outlined), text: '说课内容'),
            Tab(icon: Icon(Icons.record_voice_over_outlined), text: '配音脚本'),
            Tab(icon: Icon(Icons.videocam_outlined), text: '视频演示'),
          ],
        ),
        actions: _isEditing
            ? [
                IconButton(icon: const Icon(Icons.undo), tooltip: '取消编辑', onPressed: () { _editCtrl.text = _content; setState(() => _isEditing = false); }),
                IconButton(icon: const Icon(Icons.save_outlined), tooltip: '保存', onPressed: _saveContent),
              ]
            : [
                IconButton(icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined), tooltip: _isSpeaking ? '停止播报' : '语音播报', onPressed: _isLoading ? null : _speakContent),
                if (_videos.isNotEmpty && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
                  IconButton(icon: const Icon(Icons.video_library_outlined), tooltip: '视频列表', onPressed: () => _tabCtrl.animateTo(2)),
                IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: '导出 PDF', onPressed: _isLoading ? null : _exportPdf),
                IconButton(icon: const Icon(Icons.auto_awesome), tooltip: 'AI生成脚本', onPressed: _isLoading ? null : _generateAiScript),
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: '编辑', onPressed: _isLoading ? null : () => setState(() => _isEditing = true)),
                IconButton(icon: const Icon(Icons.file_upload_outlined), tooltip: '导入 .md', onPressed: _isLoading ? null : () async { await _importFromFile(); if (_isEditing == false) setState(() => _isEditing = true); }),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _generating
              ? _buildGenerationProgress()
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildContentTab(isPrint),
                    _buildScriptTab(isPrint),
                    _buildVideoTab(isPrint),
                  ],
                ),
    );
  }

  Widget _buildGenerationProgress() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              value: _genTotal > 0 ? _genProgress / _genTotal : null,
            ),
          ),
          const SizedBox(height: 24),
          Text(_genStatus, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          if (_genTotal > 0)
            Text('$_genProgress / $_genTotal', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 16),
          TextButton(onPressed: () => setState(() => _generating = false), child: const Text('取消')),
        ],
      ),
    );
  }

  Widget _buildContentTab(bool isPrint) {
    if (_isEditing) {
      final textColor = isPrint ? Colors.black87 : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87);
      return Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _editCtrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textColor),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            contentPadding: const EdgeInsets.all(12),
            hintText: '输入 Markdown 内容...',
          ),
        ),
      );
    }
    return Markdown(
      data: _content,
      selectable: true,
      styleSheet: _buildStyleSheet(isPrint),
      onTapLink: (text, href, title) {
        if (href != null) { Clipboard.setData(ClipboardData(text: href)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制链接: $href'))); }
      },
    );
  }

  Widget _buildScriptTab(bool isPrint) {
    final textColor = isPrint ? Colors.black87 : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.record_voice_over, size: 20),
              const SizedBox(width: 4),
              const Text('配音脚本', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up),
                tooltip: _isSpeaking ? '停止' : '试听',
                onPressed: _speakContent,
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '编辑脚本',
                onPressed: () async {
                  _scriptCtrl.text = _script;
                  final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
                    title: const Text('编辑配音脚本'),
                    content: SizedBox(width: 500, height: 400, child: TextField(controller: _scriptCtrl, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(12)))),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), ElevatedButton(onPressed: () => Navigator.pop(ctx, _scriptCtrl.text), child: const Text('保存'))],
                  ));
                  if (result != null && mounted) { _script = result; _scriptCtrl.text = _script; await _saveToDb(_content); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('脚本已保存'))); }
                },
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'AI 重新生成',
                onPressed: _generateAiScript,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.smart_display, size: 18),
                label: const Text('生成说课视频'),
                onPressed: _generateLectureVideo,
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _script.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.record_voice_over, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无配音脚本', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('请先在"说课内容"中编辑内容，然后点击 AI 生成脚本', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('AI 生成脚本'),
                        onPressed: _generateAiScript,
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_script, style: TextStyle(fontSize: 14, height: 1.8, color: textColor)),
                ),
        ),
      ],
    );
  }

  Widget _buildVideoTab(bool isPrint) {
    final videoFiles = _videos.where((v) {
      final path = v['path'] ?? '';
      final ext = path.split('.').last.toLowerCase();
      return ['mp4', 'avi', 'mkv', 'mov'].contains(ext) && File(path).existsSync();
    }).toList();

    return Column(
      children: [
        if (videoFiles.isNotEmpty)
          Expanded(
            flex: 3,
            child: _buildVideoPlayer(videoFiles.first['path']!, videoFiles.first['name']!, isPrint),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: isPrint ? Colors.grey.shade50 : Theme.of(context).cardColor,
            border: Border(bottom: BorderSide(color: isPrint ? Colors.grey.shade300 : Colors.grey.shade700.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              const Icon(Icons.video_library, size: 18),
              const SizedBox(width: 6),
              const Text('视频列表', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加本地视频'),
                onPressed: _addVideo,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.smart_display, size: 18),
                label: const Text('AI 生成说课视频'),
                onPressed: _generateLectureVideo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: videoFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无视频', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('可添加本地视频或使用 AI 生成说课视频', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: videoFiles.length,
                  itemBuilder: (ctx, i) {
                    final v = videoFiles[i];
                    return ListTile(
                      leading: const Icon(Icons.play_circle_fill, color: Colors.blue),
                      title: Text(v['name'] ?? '', style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                      subtitle: Text(v['path'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_arrow, color: Colors.blue),
                            tooltip: '播放',
                            onPressed: () => _openVideo(v['path']!),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _removeVideo(i),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer(String path, String name, bool isPrint) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill, size: 64, color: Colors.white.withValues(alpha: 0.8)),
                const SizedBox(height: 12),
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('点击播放', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openVideo(path),
              ),
            ),
          ),
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
