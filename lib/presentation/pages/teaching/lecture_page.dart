import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/tts_flutter_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/output_path_service.dart';
import '../../../services/lecture_content_service.dart';
import '../../../services/lecture_video_service.dart';
import '../../../data/local/class_dao.dart';
import '../../../data/local/teaching_dao.dart';
import '../../../services/archive/native_pdf_service.dart';
import '../learning/video_player_page.dart';

class LecturePage extends StatefulWidget {
  const LecturePage({super.key});
  @override
  State<LecturePage> createState() => _LecturePageState();
}

class _LecturePageState extends State<LecturePage>
    with TickerProviderStateMixin {
  final LectureContentService _contentService = LectureContentService();
  final LectureVideoService _videoService = LectureVideoService();

  String _content = '';
  String _script = '';
  List<Map<String, String>> _videos = [];
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSpeaking = false;
  int _speakToken = 0;
  bool _generating = false;
  String _genStatus = '';
  String _genDetail = '';
  late TextEditingController _editCtrl;
  late TextEditingController _scriptCtrl;
  late TabController _tabCtrl;

  String _teacherName = '';
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _syllabus = [];
  int _totalStudents = 0;
  String _courseName = '';
  String _majorInfo = '';
  String _studentProfile = '';
  String _lastWorkDir = '';

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
    _courseName = await CourseContextService().activeCourseName();
    await _gatherContextData();
    try {
      await _loadFromFileSystem();
      if (_content.isNotEmpty) {
        _editCtrl.text = _content;
        _scanVideoDirs();
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    } catch (_) {}

    _content = await _contentService.loadContent(_courseName);

    if (_content.isEmpty) {
      _content = await _contentService.generateContent(
        courseName: _courseName,
        teacherName: _teacherName,
        syllabus: _syllabus,
        classes: _classes,
        majorInfo: _majorInfo,
        studentProfile: _studentProfile,
        totalStudents: _totalStudents,
      );
      await _contentService.saveContent(_courseName, _content);
    }

    _script = await _contentService.loadScript(_courseName);
    if (_script.isEmpty) {
      try {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query('lecture_notes',
            where: 'course_id = ?', whereArgs: [_courseName], limit: 1);
        if (rows.isNotEmpty) _script = rows.first['script'] as String? ?? '';
      } catch (e, st) {
        swallowDebug(e, tag: 'LecturePage.loadLectureNotes', stack: st);
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
    _videos = [];
    for (final d in [p.join(_dataDir, '说课'), p.join(_dataDir, '视频')]) {
      final dir = Directory(d);
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync()) {
        if (f is File) {
          final ext = f.path.split('.').last.toLowerCase();
          if (['mp4', 'avi', 'mkv', 'mov'].contains(ext) &&
              !_videos.any((v) => v['path'] == f.path)) {
            _videos.add({
              'path': f.path,
              'name': f.path.split(Platform.pathSeparator).last,
              'type': 'local'
            });
          }
        }
      }
    }
    _videos.sort((a, b) => a['name']!.compareTo(b['name']!));
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
          for (final c in _classes)
            _totalStudents += (c['student_count'] as int? ?? 0);
        } catch (_) {}
      }
      try {
        final teachingDao = TeachingDao();
        _syllabus = await teachingDao.getAllSyllabusItems();
        await teachingDao.getAllTeachingProgress();
      } catch (_) {}
      try {
        await _loadClassesFromExcel();
      } catch (_) {}
    } catch (e, st) {
      swallowDebug(e, tag: 'LecturePage.loadFileSystem', stack: st);
    }
  }

  Future<void> _loadClassesFromExcel() async {
    final paths = [
      p.join(_dataDir, '用户', '学生名单.xlsx'),
      'data/课程知识图谱与数字孪生/用户/学生名单.xlsx'
    ];
    String? found;
    for (final path in paths) {
      if (await File(path).exists()) {
        found = path;
        break;
      }
    }
    if (found == null) return;

    final parsed = await _parseStudentRoster(found);
    _applyRosterContext(parsed);
  }

  Future<void> _importStudentRoster() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) return;
      final parsed = await _parseStudentRoster(result.files.single.path!);
      if (parsed.students.isEmpty)
        throw Exception('未识别到学生行，请确认 Excel 包含学号/姓名/班级列');
      _applyRosterContext(parsed);
      await _persistRoster(parsed);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '已导入 ${parsed.totalStudents} 名学生、${parsed.classCount.length} 个班级，后续说课会自动写入学情分析'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LecturePage.importStudentRoster', stack: st);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('学生名单导入失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<_RosterParseResult> _parseStudentRoster(String path) async {
    final bytes = await File(path).readAsBytes();
    final excel = xl.Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null || sheet.rows.length < 2)
      return _RosterParseResult.empty();

    final headers =
        sheet.row(0).map((c) => c?.value?.toString().trim() ?? '').toList();
    final idCol =
        _findHeader(headers, ['学号', '学生号', '工号', '账号', 'user_id', 'id']);
    final nameCol = _findHeader(headers, ['姓名', '学生姓名', 'name', 'real_name']);
    final classCol = _findHeader(headers, ['班级', '行政班', '教学班', 'class']);
    final majorCol = _findHeader(headers, ['专业', 'major']);
    final deptCol = _findHeader(headers, ['院系', '学院', '系部', 'department']);
    final gradeCol = _findHeader(headers, ['年级', 'grade']);
    if (classCol < 0) return _RosterParseResult.empty();

    final students = <_RosterStudent>[];
    final classCount = <String, int>{};
    final majors = <String>{};
    final depts = <String>{};
    final grades = <String>{};

    String cell(List row, int col) => col >= 0 && row.length > col
        ? (row[col]?.value?.toString().trim() ?? '')
        : '';

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.row(i);
      final cls = cell(row, classCol);
      if (cls.isEmpty) continue;
      final id = cell(row, idCol);
      final name = cell(row, nameCol);
      final major = cell(row, majorCol);
      final dept = cell(row, deptCol);
      final grade = cell(row, gradeCol);
      classCount[cls] = (classCount[cls] ?? 0) + 1;
      if (major.isNotEmpty) majors.add(major);
      if (dept.isNotEmpty) depts.add(dept);
      if (grade.isNotEmpty) grades.add(grade);
      students.add(_RosterStudent(
          userId: id,
          realName: name,
          className: cls,
          major: major,
          department: dept,
          grade: grade));
    }

    return _RosterParseResult(
        students: students,
        classCount: classCount,
        majors: majors,
        departments: depts,
        grades: grades);
  }

  int _findHeader(List<String> headers, List<String> keys) {
    return headers.indexWhere((h) {
      final lower = h.toLowerCase();
      return keys.any((k) => lower.contains(k.toLowerCase()));
    });
  }

  void _applyRosterContext(_RosterParseResult parsed) {
    if (parsed.students.isEmpty) return;
    _totalStudents = parsed.totalStudents;
    _majorInfo = [
      if (parsed.departments.isNotEmpty) parsed.departments.join('、'),
      if (parsed.majors.isNotEmpty) parsed.majors.join('、'),
      if (parsed.grades.isNotEmpty) parsed.grades.join('、'),
    ].join(' · ');
    _classes = parsed.classCount.entries
        .map((e) => {
              'name': e.key,
              'student_count': e.value,
              'major': parsed.majors.join('、')
            })
        .toList();
    final classText =
        parsed.classCount.entries.map((e) => '${e.key}${e.value}人').join('、');
    _studentProfile = '授课对象共 ${parsed.totalStudents} 人，覆盖$classText。'
        '${_majorInfo.isNotEmpty ? '学生来自 $_majorInfo。' : ''}'
        '说课设计应围绕学生前置基础、学习差异和实践能力培养展开，体现以学定教。';
  }

  Future<void> _persistRoster(_RosterParseResult parsed) async {
    final db = await DatabaseHelper.instance.database;
    final teacherId = AuthService().currentUser?.userId;
    final teacherName = _teacherName.isNotEmpty
        ? _teacherName
        : AuthService().currentUser?.realName;
    final now = DateTime.now().toIso8601String();
    for (final entry in parsed.classCount.entries) {
      final existing = await db.query('classes',
          where: 'name = ?', whereArgs: [entry.key], limit: 1);
      final classId = existing.isNotEmpty
          ? existing.first['id'] as int
          : await ClassDao().createClass(
              name: entry.key,
              teacherId: teacherId,
              teacherName: teacherName,
              description: '说课导入：$_courseName',
            );
      final classStudents =
          parsed.students.where((s) => s.className == entry.key).toList();
      for (final s in classStudents) {
        if (s.userId.isEmpty) continue;
        await db.insert(
            'users',
            {
              'user_id': s.userId,
              'real_name': s.realName.isNotEmpty ? s.realName : s.userId,
              'role': 'student',
              'is_active': 1,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await ClassDao().addMembers(
          classId,
          classStudents
              .map((s) => s.userId)
              .where((id) => id.isNotEmpty)
              .toList());
    }
  }

  // ── 平台级说课内容生成 ─────────────────────────────────────────────────────

  Future<void> _generateLectureContent() async {
    setState(() {
      _generating = true;
      _genStatus = '正在生成说课内容...';
      _genDetail = '';
    });
    try {
      final content = await _contentService.generateContent(
        courseName: _courseName,
        teacherName: _teacherName,
        syllabus: _syllabus,
        classes: _classes,
        majorInfo: _majorInfo,
        studentProfile: _studentProfile,
        totalStudents: _totalStudents,
      );
      await _contentService.saveContent(_courseName, content);
      _content = content;
      _editCtrl.text = _content;
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('说课内容已生成'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _genStatus = '生成失败';
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _generateAiScript() async {
    if (_content.isEmpty) return;
    setState(() {
      _generating = true;
      _genStatus = '正在生成配音脚本...';
      _genDetail = '';
    });
    try {
      final script = await _contentService.generateScript(_content);
      if (script.isNotEmpty) {
        _script = script;
        _scriptCtrl.text = _script;
        await _contentService.saveScript(_courseName, _script);
        if (mounted) {
          setState(() => _generating = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('配音脚本已生成'), backgroundColor: Colors.green));
          _tabCtrl.animateTo(1);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('脚本生成失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _generateLectureVideo() async {
    if (_content.isEmpty) return;
    setState(() {
      _generating = true;
      _genStatus = '正在检测环境...';
      _genDetail = '';
    });
    try {
      final result = await _videoService.generateVideo(
        context: context,
        lectureContent: _content,
        courseName: _courseName,
        teacherName: _teacherName,
        outputDir: p.join(_dataDir, '说课'),
        onProgress: (msg) {
          if (mounted) setState(() => _genDetail = msg);
        },
      );
      if (mounted) {
        _lastWorkDir = result?.workDir ?? '';
        setState(() => _generating = false);
        _scanVideoDirs();
        if (result != null && result.segments.isNotEmpty) {
          _script = result.segments.map((s) => s.narration).join('\n\n');
          _scriptCtrl.text = _script;
          await _contentService.saveScript(_courseName, _script);
        }
        if (result != null &&
            result.videoPath.isNotEmpty &&
            File(result.videoPath).existsSync()) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('✓ 说课视频已生成'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
                label: '查看', onPressed: () => _tabCtrl.animateTo(2)),
          ));
        } else if (result != null && result.segments.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_genDetail.isNotEmpty ? _genDetail : '视频未生成，已保留素材'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
                label: '查看素材', onPressed: () => _tabCtrl.animateTo(2)),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$_genDetail'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 8),
          ));
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LecturePage.video', stack: st);
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('视频生成失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── 旧保存/导入方法 ────────────────────────────────────────────────────────

  Future<void> _saveContent() async {
    _content = _editCtrl.text;
    await _contentService.saveContent(_courseName, _content);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('说课内容已保存')));
      setState(() => _isEditing = false);
    }
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['md', 'markdown', 'txt', 'docx']);
      if (result == null || result.files.isEmpty) return;
      final imported = await _readTextFile(result.files.single.path!);
      _editCtrl.text = imported;
      _content = imported;
      await _contentService.saveContent(_courseName, _content);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('说课文档已导入并保存')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _importSyllabusAndGenerate() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['md', 'markdown', 'txt', 'docx']);
      if (result == null || result.files.isEmpty) return;
      final syllabusText = await _readTextFile(result.files.single.path!);
      if (syllabusText.trim().isEmpty) throw Exception('大纲内容为空');
      if (!mounted) return;
      setState(() {
        _generating = true;
        _genStatus = '正在根据导入大纲生成说课内容...';
        _genDetail = '';
      });
      final content = await _contentService.generateContentFromSyllabusText(
        courseName: _courseName,
        teacherName: _teacherName,
        syllabusText: syllabusText,
        classes: _classes,
        majorInfo: _majorInfo,
        studentProfile: _studentProfile,
        totalStudents: _totalStudents,
      );
      _content = content;
      _editCtrl.text = content;
      await _contentService.saveContent(_courseName, content);
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('已根据导入大纲生成说课文档'), backgroundColor: Colors.green));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LecturePage.importSyllabus', stack: st);
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('大纲导入失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<String> _readTextFile(String path) async {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.docx') return _readDocxText(path);
    return File(path).readAsString();
  }

  Future<String> _readDocxText(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? document;
    for (final f in archive.files) {
      if (f.name == 'word/document.xml') {
        document = f;
        break;
      }
    }
    if (document == null) return '';
    final xmlText = String.fromCharCodes(document.content as List<int>);
    final doc = XmlDocument.parse(xmlText);
    return doc
        .findAllElements('t')
        .map((e) => e.innerText)
        .where((t) => t.trim().isNotEmpty)
        .join('\n');
  }

  void _openVideo(String path) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => InAppVideoPlayerPage(
                  filePath: path,
                  title: path.split(Platform.pathSeparator).last,
                  chapter: '说课',
                )));
  }

  Future<void> _exportPdf() async {
    try {
      final pdfBytes = await NativePdfService.instance.markdownToPdf(_content);
      final outDir = await _getLectureOutDir();
      final path = p.join(outDir, '说课_$_courseName.pdf');
      await File(path).writeAsBytes(pdfBytes);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PDF 已导出: $path'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PDF 导出失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _exportMd() async {
    try {
      final outDir = await _getLectureOutDir();
      final path = p.join(outDir, '说课_$_courseName.md');
      await File(path).writeAsString(_content, flush: true);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Markdown 已导出: $path'),
            backgroundColor: Colors.green));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Markdown 导出失败: $e'), backgroundColor: Colors.red));
    }
  }

  void _speakScript() async {
    final tts = TtsFlutterService.instance;
    if (_isSpeaking) {
      _speakToken++;
      await tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    final text = _script.isNotEmpty ? _script : _stripMarkdown(_content);
    if (text.isEmpty) return;
    final token = ++_speakToken;
    setState(() => _isSpeaking = true);
    await tts.speak(text);
    if (mounted && token == _speakToken) setState(() => _isSpeaking = false);
  }

  void _addVideo() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['mp4', 'avi', 'mkv', 'mov']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final name = path.split(Platform.pathSeparator).last;
    setState(() => _videos.add({'path': path, 'name': name, 'type': 'picked'}));
  }

  void _removeVideo(int index) {
    setState(() => _videos.removeAt(index));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

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
    text = text.replaceAll(RegExp(r'^[-:>\s|]+$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final isPrint = AppGradientTheme.isPrint(context);
    final bgColor =
        isPrint ? Colors.white : Theme.of(context).scaffoldBackgroundColor;
    final textColor = isPrint
        ? Colors.black87
        : (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black87);
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
                IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: '取消编辑',
                    onPressed: () {
                      _editCtrl.text = _content;
                      setState(() => _isEditing = false);
                    }),
                IconButton(
                    icon: const Icon(Icons.save_outlined),
                    tooltip: '保存',
                    onPressed: _saveContent),
              ]
            : [
                IconButton(
                    icon: Icon(_isSpeaking
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined),
                    tooltip: _isSpeaking ? '停止' : '语音播报',
                    onPressed: _speakScript),
                if (_videos.isNotEmpty &&
                    (Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS))
                  IconButton(
                      icon: const Icon(Icons.video_library_outlined),
                      tooltip: '视频列表',
                      onPressed: () => _tabCtrl.animateTo(2)),
                IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: '导出 PDF',
                    onPressed: _exportPdf),
                if (_script.isEmpty)
                  IconButton(
                      icon: const Icon(Icons.auto_awesome),
                      tooltip: 'AI 生成配音脚本',
                      onPressed: _generateAiScript),
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '编辑',
                    onPressed: () => setState(() => _isEditing = true)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    if (v == 'gen_content') _generateLectureContent();
                    if (v == 'gen_script') _generateAiScript();
                    if (v == 'gen_video') _generateLectureVideo();
                    if (v == 'import') _importFromFile();
                    if (v == 'import_syllabus') _importSyllabusAndGenerate();
                    if (v == 'import_students') _importStudentRoster();
                    if (v == 'export_md') _exportMd();
                    if (v == 'export_pdf') _exportPdf();
                  },
                  itemBuilder: (_) => [
                    if (_content.isEmpty ||
                        !_contentService.hasContent(_courseName))
                      const PopupMenuItem(
                          value: 'gen_content', child: Text('AI 生成说课内容')),
                    const PopupMenuItem(
                        value: 'gen_script', child: Text('AI 生成配音脚本')),
                    const PopupMenuItem(
                        value: 'gen_video', child: Text('AI 生成说课视频')),
                    const PopupMenuItem(
                        value: 'import_syllabus', child: Text('导入大纲并生成说课')),
                    const PopupMenuItem(
                        value: 'import_students', child: Text('导入班级学生名单')),
                    const PopupMenuItem(value: 'import', child: Text('导入说课文档')),
                    const PopupMenuItem(
                        value: 'export_md', child: Text('导出 Markdown')),
                    const PopupMenuItem(
                        value: 'export_pdf', child: Text('导出 PDF')),
                  ],
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_generating)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _genDetail.isNotEmpty ? _genDetail : _genStatus,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                            onPressed: () =>
                                setState(() => _generating = false),
                            child: const Text('取消')),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildContentTab(isPrint),
                      _buildScriptTab(isPrint),
                      _buildVideoTab(isPrint),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildContentTab(bool isPrint) {
    if (_isEditing) {
      final textColor = isPrint
          ? Colors.black87
          : (Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black87);
      return Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _editCtrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(
              fontFamily: 'monospace', fontSize: 13, color: textColor),
          decoration: InputDecoration(
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            contentPadding: const EdgeInsets.all(12),
            hintText: '输入 Markdown 内容...',
          ),
        ),
      );
    }
    if (_content.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('暂无说课内容',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            const SizedBox(height: 8),
            Text('AI 自动生成适合当前课程的说课文档',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI 生成说课内容'),
              onPressed: _generateLectureContent,
            ),
          ],
        ),
      );
    }
    return Markdown(
      data: _content,
      selectable: true,
      styleSheet: _buildStyleSheet(isPrint),
      onTapLink: (text, href, title) {
        if (href != null) {
          Clipboard.setData(ClipboardData(text: href));
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('已复制链接: $href')));
        }
      },
    );
  }

  Widget _buildScriptTab(bool isPrint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.record_voice_over, size: 20),
              const SizedBox(width: 4),
              const Text('配音脚本',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: Icon(
                    _isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up),
                tooltip: _isSpeaking ? '停止' : '试听',
                onPressed: _speakScript,
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '编辑脚本',
                onPressed: () async {
                  _scriptCtrl.text = _script;
                  final result = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                            title: const Text('编辑配音脚本'),
                            content: SizedBox(
                                width: 500,
                                height: 400,
                                child: TextField(
                                    controller: _scriptCtrl,
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 13),
                                    decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.all(12)))),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('取消')),
                              ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, _scriptCtrl.text),
                                  child: const Text('保存'))
                            ],
                          ));
                  if (result != null && mounted) {
                    _script = result;
                    _scriptCtrl.text = _script;
                    await _contentService.saveScript(_courseName, _script);
                    if (mounted)
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('脚本已保存')));
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'AI 生成',
                onPressed: _generateAiScript,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.smart_display, size: 18),
                label: const Text('生成说课视频'),
                onPressed: _generateLectureVideo,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white),
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
                      Icon(Icons.record_voice_over,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无配音脚本',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('请先在"说课内容"中确认内容，然后点击 AI 生成脚本',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13)),
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
                  child: SelectableText(_script,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.8,
                          color: isPrint
                              ? Colors.black87
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black87))),
                ),
        ),
      ],
    );
  }

  Widget _buildVideoTab(bool isPrint) {
    final videoFiles = _videos.where((v) {
      final path = v['path'] ?? '';
      final ext = path.split('.').last.toLowerCase();
      return ['mp4', 'avi', 'mkv', 'mov'].contains(ext) &&
          File(path).existsSync();
    }).toList();

    var generatedSlides = <String>[];
    if (_lastWorkDir.isNotEmpty && Directory(_lastWorkDir).existsSync()) {
      generatedSlides = Directory(_lastWorkDir)
          .listSync()
          .where((f) => f is File && f.path.endsWith('.png'))
          .map((f) => f.path)
          .toList();
      generatedSlides.sort();
    }
    var generatedAudios = <String>[];
    final audioDir = Directory(p.join(_lastWorkDir, 'audio'));
    if (_lastWorkDir.isNotEmpty && audioDir.existsSync()) {
      generatedAudios = audioDir
          .listSync()
          .where((f) =>
              f is File && (f.path.endsWith('.wav') || f.path.endsWith('.mp3')))
          .map((f) => f.path)
          .toList();
      generatedAudios.sort();
    }

    return Column(
      children: [
        if (videoFiles.isNotEmpty)
          Expanded(
            flex: 3,
            child: _buildVideoPlayer(
                videoFiles.first['path']!, videoFiles.first['name']!, isPrint),
          ),
        if (generatedSlides.isNotEmpty && generatedAudios.isNotEmpty)
          Expanded(
            flex: 3,
            child: _buildSlideshowPreview(
                generatedSlides, generatedAudios, isPrint),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: isPrint ? Colors.grey.shade50 : Theme.of(context).cardColor,
            border: Border(
                bottom: BorderSide(
                    color: isPrint
                        ? Colors.grey.shade300
                        : Colors.grey.shade700.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              const Icon(Icons.video_library, size: 18),
              const SizedBox(width: 6),
              const Text('视频列表',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              if (generatedSlides.isNotEmpty && generatedAudios.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.slideshow, size: 18),
                  label: const Text('预览素材'),
                  onPressed: () =>
                      _openSlideshow(generatedSlides, generatedAudios),
                ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加本地视频'),
                onPressed: _addVideo,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.smart_display, size: 18),
                label: const Text('AI 生成视频'),
                onPressed: _generateLectureVideo,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: (videoFiles.isEmpty && generatedSlides.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无视频',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('可添加本地视频或使用 AI 生成说课视频',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('AI 生成说课视频'),
                        onPressed: _generateLectureVideo,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount:
                      videoFiles.length + (generatedSlides.isNotEmpty ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (generatedSlides.isNotEmpty && i == 0) {
                      return ListTile(
                        leading:
                            const Icon(Icons.slideshow, color: Colors.green),
                        title: const Text('AI 生成视频素材',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                            '${generatedSlides.length} 张幻灯片，${generatedAudios.length} 段语音',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        trailing: IconButton(
                          icon:
                              const Icon(Icons.play_arrow, color: Colors.green),
                          onPressed: () =>
                              _openSlideshow(generatedSlides, generatedAudios),
                        ),
                        onTap: () =>
                            _openSlideshow(generatedSlides, generatedAudios),
                      );
                    }
                    final vi = generatedSlides.isNotEmpty ? i - 1 : i;
                    if (vi >= videoFiles.length) return const SizedBox.shrink();
                    final v = videoFiles[vi];
                    return ListTile(
                      leading: const Icon(Icons.play_circle_fill,
                          color: Colors.blue),
                      title: Text(v['name'] ?? '',
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(v['path'] ?? '',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                          overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.play_arrow,
                                  color: Colors.blue),
                              tooltip: '播放',
                              onPressed: () => _openVideo(v['path']!)),
                          IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _removeVideo(vi)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSlideshowPreview(
      List<String> slides, List<String> audios, bool isPrint) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (slides.isNotEmpty && File(slides.first).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(slides.first),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.slideshow, size: 48, color: Colors.white70),
                const SizedBox(height: 8),
                Text('${slides.length} 张幻灯片 · ${audios.length} 段语音',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('素材预览，正式交付请生成 MP4 视频',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('预览素材'),
                  onPressed: () => _openSlideshow(slides, audios),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSlideshow(List<String> slides, List<String> audios) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _LectureSlideshowPage(
                  slides: slides,
                  audios: audios,
                )));
  }

  Widget _buildVideoPlayer(String path, String name, bool isPrint) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.black, borderRadius: BorderRadius.circular(8)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill,
                    size: 64, color: Colors.white.withValues(alpha: 0.8)),
                const SizedBox(height: 12),
                Text(name,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('点击播放',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12)),
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
    final textColor = isPrint
        ? Colors.black87
        : (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black87);
    const baseFontSize = 14.0;
    final isDark = !isPrint && Theme.of(context).brightness == Brightness.dark;
    return MarkdownStyleSheet(
      p: TextStyle(fontSize: baseFontSize, height: 1.7, color: textColor),
      h1: TextStyle(
          fontSize: baseFontSize + 8,
          fontWeight: FontWeight.bold,
          height: 1.5,
          color: textColor),
      h2: TextStyle(
          fontSize: baseFontSize + 4,
          fontWeight: FontWeight.bold,
          height: 1.5,
          color: textColor),
      h3: TextStyle(
          fontSize: baseFontSize + 2,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor),
      h4: TextStyle(
          fontSize: baseFontSize + 1,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor),
      strong: TextStyle(fontWeight: FontWeight.bold, color: textColor),
      em: TextStyle(fontStyle: FontStyle.italic, color: textColor),
      code: TextStyle(
          fontFamily: 'monospace',
          fontSize: baseFontSize - 1,
          color: isDark ? Colors.amber[300] : Colors.deepPurple[700],
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.deepPurple.withValues(alpha: 0.06)),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.2))),
      blockquoteDecoration: BoxDecoration(
          color: isDark
              ? accentColor.withValues(alpha: 0.08)
              : accentColor.withValues(alpha: 0.04),
          border: const Border(left: BorderSide(color: accentColor, width: 4))),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      listBullet: const TextStyle(fontSize: baseFontSize, color: accentColor),
      tableHead: TextStyle(
          fontSize: baseFontSize - 1,
          fontWeight: FontWeight.bold,
          color: textColor),
      tableBody: TextStyle(fontSize: baseFontSize - 1, color: textColor),
      tableBorder: TableBorder.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.3)),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      horizontalRuleDecoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.3)))),
      blockSpacing: 10,
    );
  }
}

class _LectureSlideshowPage extends StatefulWidget {
  final List<String> slides;
  final List<String> audios;
  const _LectureSlideshowPage({required this.slides, required this.audios});

  @override
  State<_LectureSlideshowPage> createState() => _LectureSlideshowPageState();
}

class _LectureSlideshowPageState extends State<_LectureSlideshowPage> {
  int _currentIndex = 0;
  bool _isPlaying = false;
  Player? _player;
  StreamSubscription? _posSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _player?.stream.completed.listen((_) => _next());
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _play() async {
    if (widget.audios.isEmpty) return;
    if (_currentIndex >= widget.audios.length) _currentIndex = 0;
    await _player?.open(
        Media('file:///${widget.audios[_currentIndex].replaceAll('\\', '/')}'));
    await _player?.play();
    setState(() => _isPlaying = true);
  }

  void _pause() async {
    await _player?.pause();
    setState(() => _isPlaying = false);
  }

  void _next() {
    if (_currentIndex < widget.slides.length - 1) {
      setState(() => _currentIndex++);
      _play();
    } else {
      _pause();
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSlide = _currentIndex < widget.slides.length
        ? widget.slides[_currentIndex]
        : null;

    return Scaffold(
      appBar: AppBar(
          title: Text('幻灯片 ${_currentIndex + 1}/${widget.slides.length}')),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: currentSlide != null && File(currentSlide).existsSync()
                ? InteractiveViewer(
                    child: Center(
                      child: Image.file(
                        File(currentSlide),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image,
                                  color: Colors.white54, size: 64),
                              SizedBox(height: 8),
                              Text('幻灯片加载失败',
                                  style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child:
                        Text('幻灯片不可用', style: TextStyle(color: Colors.white54)),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade900,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous,
                      color: Colors.white, size: 32),
                  onPressed: _currentIndex > 0 ? _prev : null,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 48,
                  ),
                  onPressed: _isPlaying ? _pause : _play,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next,
                      color: Colors.white, size: 32),
                  onPressed:
                      _currentIndex < widget.slides.length - 1 ? _next : null,
                ),
                const SizedBox(width: 32),
                Text(
                  '${_currentIndex + 1} / ${widget.slides.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterStudent {
  final String userId;
  final String realName;
  final String className;
  final String major;
  final String department;
  final String grade;

  const _RosterStudent({
    required this.userId,
    required this.realName,
    required this.className,
    required this.major,
    required this.department,
    required this.grade,
  });
}

class _RosterParseResult {
  final List<_RosterStudent> students;
  final Map<String, int> classCount;
  final Set<String> majors;
  final Set<String> departments;
  final Set<String> grades;

  const _RosterParseResult({
    required this.students,
    required this.classCount,
    required this.majors,
    required this.departments,
    required this.grades,
  });

  factory _RosterParseResult.empty() => const _RosterParseResult(
        students: [],
        classCount: {},
        majors: {},
        departments: {},
        grades: {},
      );

  int get totalStudents => students.length;
}
