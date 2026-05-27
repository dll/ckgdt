import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import '../../../../core/error_handler.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../presentation/widgets/markdown_bubble.dart';
import '../archive_constants.dart';

class ArchivePeriodTab extends StatefulWidget {
  final String periodKey;
  final String courseType;
  final ArchiveDao dao;
  final ArchiveAgent agent;

  const ArchivePeriodTab({
    super.key,
    required this.periodKey,
    required this.courseType,
    required this.dao,
    required this.agent,
  });

  @override
  State<ArchivePeriodTab> createState() => _ArchivePeriodTabState();
}

class _ArchivePeriodTabState extends State<ArchivePeriodTab> {
  List<ArchiveDocument> _documents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArchivePeriodTab old) {
    super.didUpdateWidget(old);
    if (old.courseType != widget.courseType || old.periodKey != widget.periodKey) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs = await widget.dao.getDocuments(
        period: widget.periodKey,
        courseType: widget.courseType,
      );
      if (mounted) setState(() { _documents = docs; _loading = false; });
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DocumentTypeDef> get _expectedDocs =>
      docsForPeriod(widget.courseType, widget.periodKey);

  ArchiveDocument? _findDoc(DocumentTypeDef def) {
    for (final d in _documents) {
      if (d.documentType == def.key) return d;
    }
    return null;
  }

  Future<void> _generateDoc(DocumentTypeDef def) async {
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final doc = await widget.agent.generateDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
      );
      if (mounted) Navigator.of(context).pop();
      _load();
      if (mounted) _previewDoc(doc);
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._generateDoc', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生成失败，请重试')),
        );
      }
    }
  }

  void _previewDoc(ArchiveDocument doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DocumentPreviewSheet(doc: doc, dao: widget.dao, agent: widget.agent, onArchived: _load),
    );
  }

  Future<void> _printDoc(ArchiveDocument doc) async {
    if (!mounted) return;
    final formatted = _officialFormat(doc);
    showDialog(
      context: context,
      builder: (_) => _PrintPreviewDialog(doc: doc.copyWith(content: formatted)),
    );
  }

  Future<void> _reviewDoc(ArchiveDocument doc) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final review = await widget.agent.reviewDocument(doc);
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.rate_review, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('AI 审核结果'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: MarkdownBubble(content: review),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
            ],
          ),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._reviewDoc', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('审核失败，请重试')),
        );
      }
    }
  }

  Future<void> _archiveDoc(ArchiveDocument doc) async {
    final updated = doc.copyWith(status: 'archived');
    await widget.dao.saveDocument(updated);
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已归档：${doc.title}')),
      );
    }
  }

  Future<void> _deleteDoc(ArchiveDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除"${doc.title}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && doc.id != null) {
      await widget.dao.deleteDocument(doc.id!);
      _load();
    }
  }

  Future<void> _importDoc(DocumentTypeDef def) async {
    if (!mounted) return;
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';

    if (def.key == 'teaching_task') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['htm', 'html'],
        dialogTitle: '选择教学任务书HTML文件',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final html = await file.readAsString();
      final parsed = _parseTeachingTask(html);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到"移动应用开发"课程数据，请确认HTML文件内容'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        isGenerated: true,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从教务系统导入教学任务书：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'course_schedule') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        dialogTitle: '选择课表Excel文件',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      String? parsed;
      try {
        parsed = _parseCourseSchedule(bytes);
      } catch (e, st) {
        swallowDebug(e, tag: 'ArchivePeriodTab._importDoc.xlsx', stack: st);
      }
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未在课表中找到"移动应用开发"课程，请确认Excel文件内容'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        isGenerated: true,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从Excel导入课程课表：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'calendar') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mhtml', 'mht', 'htm', 'html'],
        dialogTitle: '选择校历文件（从教务系统另存为.mhtml）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final raw = await file.readAsString();
      final parsed = _parseCalendar(raw);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('校历解析失败，请确认文件为完整的MHTML格式'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        isGenerated: true,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入校历：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'roll_call') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mhtml', 'mht', 'htm', 'html'],
        dialogTitle: '选择考勤表文件（另存为.mhtml）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final raw = await file.readAsString();
      final parsed = _parseRollCall(raw);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到"移动应用开发"点名册数据，请确认MHTML文件内容'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        isGenerated: true,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从教务系统导入学生点名册：${doc.title}')),
        );
      }
      return;
    }

    final doc = ArchiveDocument(
      title: title,
      documentType: def.key,
      period: widget.periodKey,
      courseType: widget.courseType,
      content: '（已从${_importSource(def.key)}导入）',
    );
    await widget.dao.saveDocument(doc);
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从${_importSource(def.key)}导入：${def.label}')),
      );
    }
  }

  String? _parseTeachingTask(String html) {
    var match = RegExp(
      r'经学校批准聘请(.+?)老师担任(.+?)以下教学任务',
    ).firstMatch(html);
    final teacher = match?.group(1) ?? '未知';
    final semester = match?.group(2) ?? '未知学期';

    final courseRows = RegExp(
      r'<tr>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*</tr>',
      dotAll: true,
    ).allMatches(html);

    Map<String, String>? courseData;
    for (final row in courseRows) {
      final name = row.group(1)?.trim() ?? '';
      if (name.contains('移动应用开发')) {
        courseData = {
          'course_name': name,
          'course_type': row.group(2)?.trim() ?? '',
          'total_hours': row.group(3)?.trim() ?? '',
          'lecture_hours': row.group(4)?.trim() ?? '',
          'lab_hours': row.group(5)?.trim() ?? '',
          'practice_hours': row.group(6)?.trim() ?? '',
          'self_study_hours': row.group(7)?.trim() ?? '',
          'class_info': row.group(8)?.trim() ?? '',
          'student_count': row.group(9)?.trim() ?? '',
          'notes': row.group(10)?.trim() ?? '',
        };
        break;
      }
    }
    if (courseData == null) return null;

    return '''# 教 学 任 务 书

**教师**：$teacher
**学期**：$semester

| 项目 | 内容 |
|------|------|
| 课程名称 | ${courseData['course_name']} |
| 课程类别 | ${courseData['course_type']} |
| 总学时 | ${courseData['total_hours']} |
| 讲授 | ${courseData['lecture_hours']} |
| 实验 | ${courseData['practice_hours']} |
| 实践 | ${courseData['lab_hours']} |
| 课外自主学时 | ${courseData['self_study_hours']} |
| 教学班级 | ${courseData['class_info']} |
| 计划人数 | ${courseData['student_count']} |
| 备注 | ${courseData['notes']} |

---
> 数据来源：教务系统（j﻿wgl.chzu.edu.cn）
> 导入时间：${DateTime.now().toString().substring(0, 16)}
''';
  }

  String? _parseRollCall(String raw) {
    String html = raw;
    // Extract HTML part from MHTML (between boundary markers)
    final boundaryMatch = RegExp(r'boundary="(.*?)"').firstMatch(raw);
    if (boundaryMatch != null) {
      final boundary = '--${boundaryMatch.group(1)}';
      final parts = raw.split(boundary);
      for (final part in parts) {
        if (part.contains('Content-Type: text/html')) {
          final contentStart = part.indexOf('Content-Location:');
          if (contentStart == -1) continue;
          final content = part.substring(contentStart);
          final lineEnd = content.indexOf('\n');
          if (lineEnd == -1) continue;
          html = content.substring(lineEnd + 1).trim();
          break;
        }
      }
    }

    // Decode quoted-printable: =XX → byte, =3D → =
    final bytes = <int>[];
    for (var i = 0; i < html.length; i++) {
      if (html[i] == '=' && i + 2 < html.length) {
        if (html[i + 1] == '\r' && html[i + 2] == '\n') {
          i += 2;
          continue;
        }
        if (html[i + 1] == '\n') { i += 1; continue; }
        final hex = html.substring(i + 1, i + 3);
        if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(hex)) {
          bytes.add(int.parse(hex, radix: 16));
          i += 2;
        } else {
          bytes.add('='.codeUnitAt(0));
        }
      } else {
        bytes.add(html.codeUnitAt(i));
      }
    }
    html = utf8.decode(bytes);

    // Extract course info header
    final courseMatch = RegExp(r'课程名称：(.+?)(?:<|$)').firstMatch(html);
    final teacherMatch = RegExp(r'授课教师：(.+?)(?:<|$)').firstMatch(html);
    final scheduleMatch = RegExp(r'课程安排：(.+?)(?:<|$)').firstMatch(html);
    final courseName = courseMatch?.group(1)?.trim() ?? '';
    final teacher = teacherMatch?.group(1)?.trim() ?? '未知';
    final schedule = scheduleMatch?.group(1)?.trim() ?? '';

    if (!courseName.contains('移动应用开发')) return null;

    // Extract student rows: <td>序号</td><td>学号</td><td>姓名</td><td>性别</td>
    final students = <Map<String, String>>[];
    final rowRegex = RegExp(
      r'<tr[^>]*>.*?<td>\s*(\d+)\s*</td>.*?<td>\s*(\d+)\s*</td>.*?<td>(.*?)</td>.*?<td>(.*?)</td>',
      dotAll: true,
    );
    for (final m in rowRegex.allMatches(html)) {
      final name = m.group(3)!.trim();
      final gender = m.group(4)!.trim();
      if (name.isEmpty || name == '&nbsp;') continue;
      students.add({
        'seq': m.group(1)!.trim(),
        'student_id': m.group(2)!.trim(),
        'name': name,
        'gender': gender == '男' ? '男' : '女',
      });
    }

    if (students.isEmpty) return null;

    // Build markdown
    final buf = StringBuffer();
    buf.writeln('# 学生点名册\n');
    buf.writeln('**课程**：移动应用开发');
    buf.writeln('**授课教师**：$teacher');
    buf.writeln('**课程安排**：$schedule');
    buf.writeln('**学生人数**：${students.length}人\n');
    buf.writeln('| 序号 | 学号 | 姓名 | 性别 |');
    buf.writeln('|------|------|------|------|');
    for (final s in students) {
      buf.writeln('| ${s['seq']} | ${s['student_id']} | ${s['name']} | ${s['gender']} |');
    }
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 数据来源：教务系统考勤表');
    buf.writeln('> 导入时间：${DateTime.now().toString().substring(0, 16)}');
    return buf.toString();
  }

  String? _parseCourseSchedule(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.sheets.isEmpty) return null;
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return null;

    // Find column indices from header
    final header = sheet.rows[0]
        .map((c) => (c?.value?.toString() ?? '').trim())
        .toList();
    final typeIdx = header.indexOf('类型');
    final classIdx = header.indexOf('班级');
    final courseIdx = header.indexOf('课程名称');
    final dateIdx = header.indexOf('日期');
    final weekIdx = header.indexOf('周');
    final dayIdx = header.indexOf('星期');
    final periodIdx = header.indexOf('课节');
    final teacherIdx = header.indexOf('指导教师');
    final locationIdx = header.indexOf('地点');
    if (typeIdx == -1 || classIdx == -1 || courseIdx == -1) return null;

    final rows = <Map<String, String>>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final r = sheet.rows[i];
      final courseName = (r.length > courseIdx && r[courseIdx]?.value != null)
          ? r[courseIdx]!.value.toString().trim()
          : '';
      if (!courseName.contains('移动应用开发')) continue;
      final weekStr = (r.length > weekIdx && r[weekIdx]?.value != null)
          ? r[weekIdx]!.value.toString().trim()
          : '';
      rows.add({
        'type': (r.length > typeIdx && r[typeIdx]?.value != null)
            ? r[typeIdx]!.value.toString().trim()
            : '',
        'class': (r.length > classIdx && r[classIdx]?.value != null)
            ? r[classIdx]!.value.toString().trim()
            : '',
        'date': (r.length > dateIdx && r[dateIdx]?.value != null)
            ? r[dateIdx]!.value.toString().trim()
            : '',
        'week': weekStr,
        'day': (r.length > dayIdx && r[dayIdx]?.value != null)
            ? r[dayIdx]!.value.toString().trim()
            : '',
        'period': (r.length > periodIdx && r[periodIdx]?.value != null)
            ? r[periodIdx]!.value.toString().trim()
            : '',
        'teacher': (r.length > teacherIdx && r[teacherIdx]?.value != null)
            ? r[teacherIdx]!.value.toString().trim()
            : '',
        'location': (r.length > locationIdx && r[locationIdx]?.value != null)
            ? r[locationIdx]!.value.toString().trim()
            : '',
      });
    }
    if (rows.isEmpty) return null;

    // Day of week mapping
    const dayNames = {1: '星期一', 2: '星期二', 3: '星期三', 4: '星期四', 5: '星期五', 6: '星期六', 7: '星期日'};

    // Split theory vs lab
    final theory = rows.where((r) => r['type']!.contains('教务')).toList();
    final lab = rows.where((r) => r['type']!.contains('实验')).toList();

    // Extract teacher name
    final teacher = rows.firstWhere(
      (r) => r['teacher']!.isNotEmpty,
      orElse: () => {'teacher': '未知'},
    )['teacher']!;

    // Determine semester from first date
    String semester = '未知学期';
    if (rows.isNotEmpty && rows[0]['date']!.isNotEmpty) {
      final d = rows[0]['date']!;
      final year = int.tryParse(d.substring(0, 4)) ?? 0;
      final month = int.tryParse(d.substring(5, 7)) ?? 0;
      if (month >= 2 && month <= 7) {
        semester = '${year - 1}-$year学年第二学期';
      } else if (month >= 8) {
        semester = '$year-${year + 1}学年第一学期';
      }
    }

    // Helper: parse week number as int
    int? w(Map<String, String> r) => int.tryParse(r['week']!);

    final buf = StringBuffer();
    buf.writeln('# 课程课表：移动应用开发\n');
    buf.writeln('**教师**：$teacher');
    buf.writeln('**学期**：$semester');
    buf.writeln('**班级**：软件231,软件232（85人）\n');

    // Theory
    theory.sort((a, b) => (w(a) ?? 0).compareTo(w(b) ?? 0));
    buf.writeln('## 一、理论课\n');
    buf.writeln('| 周次 | 日期 | 星期 | 节次 | 地点 |');
    buf.writeln('|------|------|------|------|------|');
    for (final r in theory) {
      final dayNum = int.tryParse(r['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : r['day']!;
      buf.writeln('| ${r['week']} | ${r['date']} | $dayName | ${r['period']} | ${r['location']} |');
    }
    buf.writeln('');

    // Lab - group by group name
    final groups = <String, List<Map<String, String>>>{};
    for (final r in lab) {
      // Extract group info from class column: "软件232,软件231(班组1:29人)"
      final groupMatch = RegExp(r'班组(\d)[：:]\d+人').firstMatch(r['class']!);
      final grpKey = groupMatch != null
          ? '班组${groupMatch.group(1)}'
          : '综合组';
      groups.putIfAbsent(grpKey, () => []).add(r);
    }

    buf.writeln('## 二、实验课\n');
    for (final entry in groups.entries) {
      entry.value.sort((a, b) => (w(a) ?? 0).compareTo(w(b) ?? 0));
      // Extract people count from first row
      final peopleMatch = RegExp(r'班组\d[：:](\d+)人').firstMatch(entry.value.first['class']!);
      final people = peopleMatch?.group(1) ?? '';
      final dayNum = int.tryParse(entry.value.first['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : entry.value.first['day'] ?? '';
      final periodInfo = entry.value.first['period'] ?? '';
      buf.writeln('### $entry.key（$people人）— $dayName $periodInfo\n');
      buf.writeln('| 周次 | 日期 | 地点 |');
      buf.writeln('|------|------|------|');
      for (final r in entry.value) {
        buf.writeln('| ${r['week']} | ${r['date']} | ${r['location']} |');
      }
      buf.writeln('');
    }

    // Statistics
    buf.writeln('## 三、统计\n');
    final theoryWeeks = theory.map((r) => r['week']!).toSet().length;
    final labWeeks = lab.map((r) => r['week']!).toSet().length;
    final groupCount = groups.length;
    final totalTheoryHours = theory.length * 2;
    final totalLabHours = lab.length * 2;
    buf.writeln('- 理论课：$theoryWeeks周 × 2学时 = ${theoryWeeks * 2}学时（实际$totalTheoryHours课时）');
    buf.writeln('- 实验课：${groups.length}组 × $labWeeks周 × 2学时 = ${groupCount * labWeeks * 2}学时（实际$totalLabHours课时）');
    buf.writeln('- 总学时：${totalTheoryHours + totalLabHours}课时\n');
    buf.writeln('---');
    buf.writeln('> 数据来源：教务系统课表（Excel）');
    buf.writeln('> 导入时间：${DateTime.now().toString().substring(0, 16)}');
    return buf.toString();
  }

  /// Extract HTML content from MHTML multipart wrapper
  String _extractHtmlFromMhtml(String raw) {
    final boundaryMatch = RegExp(r'boundary="(.*?)"').firstMatch(raw);
    if (boundaryMatch != null) {
      final boundary = '--${boundaryMatch.group(1)}';
      final parts = raw.split(boundary);
      for (final part in parts) {
        if (part.contains('Content-Type: text/html')) {
          final contentStart = part.indexOf('Content-Location:');
          if (contentStart == -1) continue;
          final content = part.substring(contentStart);
          final lineEnd = content.indexOf('\n');
          if (lineEnd == -1) continue;
          return content.substring(lineEnd + 1).trim();
        }
      }
    }
    return raw;
  }

  /// Decode quoted-printable text to UTF-8 string
  String _decodeQuotedPrintable(String input) {
    final bytes = <int>[];
    for (var i = 0; i < input.length; i++) {
      if (input[i] == '=' && i + 2 < input.length) {
        if (input[i + 1] == '\r' && input[i + 2] == '\n') {
          i += 2;
          continue;
        }
        if (input[i + 1] == '\n') {
          i += 1;
          continue;
        }
        final hex = input.substring(i + 1, i + 3);
        if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(hex)) {
          bytes.add(int.parse(hex, radix: 16));
          i += 2;
        } else {
          bytes.add('='.codeUnitAt(0));
        }
      } else {
        bytes.add(input.codeUnitAt(i));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String? _parseCalendar(String raw) {
    String html = _extractHtmlFromMhtml(raw);
    html = _decodeQuotedPrintable(html);

    // Parse table rows
    final rowRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    final cellTextRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false);
    final tagStrip = RegExp(r'<[^>]*>', dotAll: true);

    final parsedRows = <List<String>>[];
    for (final rowMatch in rowRegex.allMatches(html)) {
      final rowHtml = rowMatch.group(1)!;
      final cells = <String>[];
      for (final cellMatch in cellTextRegex.allMatches(rowHtml)) {
        // Extract text from cell, merge p.dp1 + p.dp2 sibling text
        var cellContent = cellMatch.group(1)!;
        // Extract dp1 (day number) and dp2 (label) text
        final dp1 = RegExp(r'class="dp1"[^>]*>(.*?)</p>', dotAll: true)
            .firstMatch(cellContent)
            ?.group(1)
            ?.trim() ?? '';
        final dp2 = RegExp(r'class="dp2"[^>]*>(.*?)</p>', dotAll: true)
            .firstMatch(cellContent)
            ?.group(1)
            ?.trim() ?? '';
        final combined = (dp1 + dp2).trim();
        // Fallback: extract all visible text
        final text = combined.isNotEmpty
            ? combined
            : cellContent.replaceAll(tagStrip, '').trim();
        if (text.isNotEmpty) cells.add(text);
      }
      if (cells.isNotEmpty) parsedRows.add(cells);
    }

    if (parsedRows.isEmpty) return null;

    // Skip header row (周次 | 一 二 三 四 五 六 日)
    // Month rows have 1 cell (just month name)
    // Week rows have 7 cells (Mon-Sun dates) + optional week number

    // Build weekly calendar starting from March 2, 2026 (Monday)
    final startDate = DateTime(2026, 3, 2);
    final holidayMap = <String, String>{
      '清明': '清明节',
      '劳动': '劳动节',
      '端午': '端午节',
    };
    final phaseMap = <String, String>{
      '缓补': '缓补考试周',
      '期末': '期末考试周',
      '暑假': '暑假',
    };

    // Collect all day cells across all data rows
    final weeks = <List<_CalDay>>[];
    List<_CalDay>? currentWeek;

    for (final cells in parsedRows) {
      if (cells.length <= 2) continue; // month header or empty
      // Cells could be: [week_no?] + [7 days]
      // Or just [7 days] with colspan merging
      final dayCells = cells.length >= 8 ? cells.sublist(cells.length - 7) : cells;
      if (dayCells.length != 7) continue;

      currentWeek = [];
      for (var d = 0; d < 7; d++) {
        final raw = dayCells[d];
        // Extract day number and label
        final numMatch = RegExp(r'^(\d+)').firstMatch(raw);
        final dayNum = numMatch != null ? int.parse(numMatch.group(1)!) : 0;
        String label = '';
        for (final entry in holidayMap.entries) {
          if (raw.contains(entry.key)) {
            label = entry.value;
            break;
          }
        }
        if (label.isEmpty) {
          for (final entry in phaseMap.entries) {
            if (raw.contains(entry.key)) {
              label = entry.value;
              break;
            }
          }
        }
        currentWeek.add(_CalDay(date: dayNum, label: label));
      }
      weeks.add(currentWeek);
    }

    // Deduplicate: if two consecutive weeks have same Monday date, skip
    final uniqueWeeks = <List<_CalDay>>[];
    for (var i = 0; i < weeks.length; i++) {
      if (i > 0 && weeks[i][0].date == weeks[i - 1][0].date) continue;
      uniqueWeeks.add(weeks[i]);
    }

    // Generate markdown - SCHOOL calendar, NOT course-specific
    final buf = StringBuffer();
    buf.writeln('# 校 历\n');
    buf.writeln('**学年学期：** 2025-2026学年第二学期\n');
    buf.writeln('**起始日期：** ${startDate.toString().substring(0, 10)}（周一）\n');
    buf.writeln('## 校历总览\n');
    buf.writeln('| 周次 | 起止日期 | 周一 | 周二 | 周三 | 周四 | 周五 | 周六 | 周日 | 备注 |');
    buf.writeln('|------|----------|------|------|------|------|------|------|------|------|');

    for (var w = 0; w < uniqueWeeks.length; w++) {
      final wk = uniqueWeeks[w];
      final monDate = startDate.add(Duration(days: w * 7));
      final sunDate = monDate.add(const Duration(days: 6));
      final dateRange = '${monDate.month}/${monDate.day}-${sunDate.month}/${sunDate.day}';

      // Determine week label
      String weekLabel = '';
      final holidays = <String>[];
      for (final day in wk) {
        if (day.label.isNotEmpty && !day.label.contains('周')) {
          holidays.add(day.label);
        }
        if (day.label == '缓补考试周') weekLabel = '缓补';
        if (day.label == '期末考试周') weekLabel = '期末';
        if (day.label == '暑假') weekLabel = '暑假';
      }

      final weekNum = weekLabel.isNotEmpty ? weekLabel : '${w + 1}';
      final note = holidays.isNotEmpty
          ? holidays.toSet().join('、')
          : (weekLabel.isNotEmpty ? '（$weekLabel）' : '');

      // Day columns (show date number, mark holidays)
      final dayCols = <String>[];
      for (var d = 0; d < 7; d++) {
        final day = wk[d];
        if (day.label == '清明节' || day.label == '劳动节' || day.label == '端午节') {
          dayCols.add('🎉${day.date}');
        } else if (day.label == '缓补考试周' || day.label == '期末考试周' || day.label == '暑假') {
          dayCols.add('📌${day.date}');
        } else {
          dayCols.add('${day.date}');
        }
      }

      // Mark holiday weeks
      String noteStr = note;
      if (note.contains('清明')) {
        noteStr = '清明节放假';
      } else if (note.contains('劳动')) {
        noteStr = '劳动节放假';
      } else if (note.contains('端午')) {
        noteStr = '端午节放假';
      }

      buf.writeln(
          '| $weekNum | $dateRange | ${dayCols[0]} | ${dayCols[1]} | ${dayCols[2]} | ${dayCols[3]} | ${dayCols[4]} | ${dayCols[5]} | ${dayCols[6]} | $noteStr |');
    }

    buf.writeln('');
    buf.writeln('## 节假日安排\n');
    buf.writeln('| 节日 | 日期 | 天数 | 说明 |');
    buf.writeln('|------|------|------|------|');
    buf.writeln('| 清明节 | 4月5日（周日） | 4月4-6日放假 | 调休安排以学校通知为准 |');
    buf.writeln('| 劳动节 | 5月1日（周五） | 5月1-5日放假 | 调休安排以学校通知为准 |');
    buf.writeln('| 端午节 | 6月19日（周五） | 6月12-14日放假 | 调休安排以学校通知为准 |');
    buf.writeln('');
    buf.writeln('## 作息时间\n');
    buf.writeln('| 时段 | 冬季作息（第1-10周） | 夏季作息（第11周起） |');
    buf.writeln('|------|----------------------|----------------------|');
    buf.writeln('| 上午 | 8:00-11:50 | 8:00-11:50 |');
    buf.writeln('| 下午 | 14:00-17:30 | 14:30-18:00 |');
    buf.writeln('| 晚上 | 19:00-21:00 | 19:00-21:00 |');
    buf.writeln('');
    buf.writeln('## 关键节点\n');
    buf.writeln('- **缓补考试**：第1周（3月2-8日）');
    buf.writeln('- **期末考试**：第19-20周（7月6-19日）');
    buf.writeln('- **暑假**：第21周起（7月20日起）');
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 数据来源：滁州学院校历系统');
    buf.writeln('> 导入时间：${DateTime.now().toString().substring(0, 16)}');
    buf.writeln('> 注：本日历为全校通用校历，具体教学安排以课表为准');
    return buf.toString();
  }

  String _importSource(String key) {
    switch (key) {
      case 'teaching_task': return '教务系统';
      case 'syllabus': return '学院';
      case 'calendar': return '校历';
      case 'course_schedule': return '教务系统';
      case 'courseware': return '课件库';
      case 'roll_call': return '教务系统';
      default: return '外部系统';
    }
  }

  Future<void> _createDoc(DocumentTypeDef def) async {
    if (!mounted) return;
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';
    // 打开模板编辑
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('新建${def.label}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请填写教学进度表内容：', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: '输入教学进度安排...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: result,
        isGenerated: true,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建：${def.label}')),
        );
      }
    }
  }

  Future<ArchiveDocument?> _doGenerate(DocumentTypeDef def) async {
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';
    try {
      return await widget.agent.generateDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._doGenerate', stack: st);
      return null;
    }
  }

  Future<void> _generateAll() async {
    final order = widget.periodKey == 'beginning'
        ? ['calendar', 'teaching_schedule', 'lesson_plan']
        : _expectedDocs.where((d) => d.needsGeneration).map((d) => d.key).toList();
    final toGenerate = order
        .map((key) => _expectedDocs.where((d) => d.key == key).firstOrNull)
        .whereType<DocumentTypeDef>()
        .where((d) => _findDoc(d) == null)
        .toList();
    if (toGenerate.isEmpty) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    int success = 0;
    for (final def in toGenerate) {
      final doc = await _doGenerate(def);
      if (doc != null) success++;
    }
    if (mounted) {
      Navigator.of(context).pop();
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成 $success/${toGenerate.length} 份文档')),
      );
    }
  }

  Future<void> _reviewAll() async {
    final toReview =
        _documents.where((d) => d.content != null && d.content!.isNotEmpty).toList();
    if (toReview.isEmpty) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final results = <String>[];
    for (final doc in toReview) {
      try {
        final review = await widget.agent.reviewDocument(doc);
        results.add('### ${doc.title}\n\n$review');
      } catch (e, st) {
        swallowDebug(e, tag: 'ArchivePeriodTab._reviewAll', stack: st);
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
      if (results.isNotEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.rate_review, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('审核结果 (${results.length}/${toReview.length})'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: MarkdownBubble(content: results.join('\n\n---\n\n')),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _printAll() async {
    final toPrint = _expectedDocs
        .where((d) => d.canPrint && _findDoc(d) != null)
        .toList();
    if (toPrint.isEmpty) return;
    for (final def in toPrint) {
      final doc = _findDoc(def)!;
      if (!mounted) return;
      final formatted = _officialFormat(doc);
      await showDialog(
        context: context,
        builder: (_) => _PrintPreviewDialog(doc: doc.copyWith(content: formatted)),
      );
    }
  }

  Future<void> _archiveAll() async {
    final toArchive = _documents.where((d) => d.status != 'archived').toList();
    if (toArchive.isEmpty) return;
    for (final doc in toArchive) {
      await widget.dao.saveDocument(doc.copyWith(status: 'archived'));
    }
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已归档 ${toArchive.length} 份文档')),
      );
    }
  }

  String _officialFormat(ArchiveDocument doc) {
    final base = doc.content ?? '';
    final hasContent =
        base.isNotEmpty && !base.startsWith('（已从') && !base.startsWith('（暂无');
    final ts = DateTime.now().toString().substring(0, 16);
    const semester = '2025-2026学年第二学期';

    /// Wrap actual content with official document header/footer
    String wrap(String title, [String? extraHeader]) {
      final buf = StringBuffer();
      buf.writeln('# $title\n');
      if (extraHeader != null) buf.writeln('$extraHeader\n');
      buf.writeln('---\n');

      if (doc.documentType == 'teaching_task' && hasContent) {
        // Extract data table from markdown, put into official layout
        final lines = base.split('\n');
        final dataRow = lines.where((l) => l.startsWith('|') && !l.startsWith('|-')).toList();
        final teacherMatch = RegExp(r'\*\*教师\*\*[：:]\s*(.*?)[\n|]').firstMatch(base);
        final teacher = teacherMatch?.group(1)?.trim() ?? '刘东良';
        final semesterMatch = RegExp(r'\*\*学期\*\*[：:]\s*(.*?)[\n|]').firstMatch(base);
        final semesterText = semesterMatch?.group(1)?.trim() ?? semester;
        buf.writeln('**院（系）：** ________     **教研室主任：** ________\n');
        buf.writeln('经学校批准聘请 **$teacher** 老师担任 **$semesterText** 以下教学任务：\n');
        if (dataRow.isNotEmpty) {
          buf.writeln('| 课程名称 | 课程类别 | 总学时 | 讲授 | 实验 | 实践 | 课外自主 | 教学班级 | 计划人数 | 备注 |');
          buf.writeln('|----------|----------|--------|------|------|------|----------|----------|----------|------|');
          for (final row in dataRow) {
            // Extract cells from markdown table row
            final cells = row.split('|').where((c) => c.trim().isNotEmpty).toList();
            if (cells.length >= 8) {
              buf.writeln('| ${cells[0].trim()} | ${cells[1].trim()} | ${cells[2].trim()} | ${cells[3].trim()} | ${cells[4].trim()} | ${cells[5].trim()} | ${cells[6].trim()} | ${cells[7].trim()} | ${cells.length > 8 ? cells[8].trim() : ''} | ${cells.length > 9 ? cells[9].trim() : ''} |');
            }
          }
        }
        buf.writeln('');
        buf.writeln('**系（部）主任：** ________     **教研室主任：** ________\n');
        buf.writeln('**填表人：** ________     **日期：** ____年____月____日\n');
      } else if (hasContent) {
        // Use actual content (already structured markdown)
        buf.writeln(base.trim());
      } else {
        // Show empty template
        buf.writeln('（暂无内容）');
      }
      buf.writeln('');
      buf.writeln('---');
      buf.writeln('> 打印时间：$ts');
      return buf.toString();
    }

    switch (doc.documentType) {
      case 'teaching_task':
        return wrap('教 学 任 务 书');
      case 'syllabus':
        return wrap('教 学 大 纲');
      case 'calendar':
        return wrap('校 历', '**学年学期：** $semester');
      case 'course_schedule':
        return wrap('课 程 课 表', '**学期：** $semester  **课程：** 移动应用开发  **班级：** 软件231,软件232');
      case 'teaching_schedule':
        return wrap('教 学 进 度 表', '**学期：** $semester  **课程：** 移动应用开发  **班级：** 软件231,软件232');
      case 'lesson_plan':
        return wrap('教 学 教 案');
      default:
        return base;
    }
  }

  Widget _buildActionBar() {
    final primary = Theme.of(context).colorScheme.primary;
    final hasUnfinished = _expectedDocs.any((d) => d.needsGeneration && _findDoc(d) == null);
    final hasUnreviewed = _documents.any((d) => d.content != null && d.content!.isNotEmpty);
    final hasUnprinted =
        _expectedDocs.any((d) => d.canPrint && _findDoc(d) != null);
    final hasUnarchived = _documents.any((d) => d.status != 'archived');

    Widget chip(IconData icon, String label, bool enabled, [Color? color]) {
      final c = color ?? primary;
      return Material(
        color: enabled ? c.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => _onBatchAction(label) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: enabled ? c : Colors.grey),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: enabled ? c : Colors.grey,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.03),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          chip(Icons.auto_awesome, '一键生成', hasUnfinished),
          const SizedBox(width: 6),
          chip(Icons.rate_review_outlined, '一键审核', hasUnreviewed, Colors.teal),
          const SizedBox(width: 6),
          chip(Icons.print, '一键打印', hasUnprinted),
          const SizedBox(width: 6),
          chip(Icons.archive, '一键归档', hasUnarchived, Colors.green),
        ],
      ),
    );
  }

  void _onBatchAction(String label) {
    switch (label) {
      case '一键生成':
        _generateAll();
        break;
      case '一键审核':
        _reviewAll();
        break;
      case '一键打印':
        _printAll();
        break;
      case '一键归档':
        _archiveAll();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final docs = _expectedDocs;
    return Column(
      children: [
        if (docs.isNotEmpty) _buildActionBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: docs.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    Center(
                        child: Text('暂无配置的文档类型',
                            style: TextStyle(color: Colors.grey))),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final def = docs[i];
                      final doc = _findDoc(def);
                      return DocCard(
                        def: def,
                        doc: doc,
                        onImport: def.canImport ? () => _importDoc(def) : null,
                        onCreate: def.canCreate ? () => _createDoc(def) : null,
                        onGenerate: def.needsGeneration
                            ? () => _generateDoc(def)
                            : null,
                        onReview: doc != null ? () => _reviewDoc(doc) : null,
                        onPreview: doc != null ? () => _previewDoc(doc) : null,
                        onPrint: (doc != null && def.canPrint)
                            ? () => _printDoc(doc)
                            : null,
                        onArchive: doc != null && doc.status != 'archived'
                            ? () => _archiveDoc(doc)
                            : null,
                        onDelete: doc != null ? () => _deleteDoc(doc) : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class DocCard extends StatelessWidget {
  final DocumentTypeDef def;
  final ArchiveDocument? doc;
  final VoidCallback? onGenerate;
  final VoidCallback? onImport;
  final VoidCallback? onCreate;
  final VoidCallback? onPreview;
  final VoidCallback? onReview;
  final VoidCallback? onPrint;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;

  const DocCard({
    super.key,
    required this.def,
    this.doc,
    this.onGenerate,
    this.onImport,
    this.onCreate,
    this.onPreview,
    this.onReview,
    this.onPrint,
    this.onArchive,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasDoc = doc != null;
    final statusLabel = hasDoc
        ? (doc!.status == 'archived' ? '已归档' : doc!.isGenerated ? '已生成' : '草稿')
        : '未创建';
    final statusColor = hasDoc
        ? (doc!.status == 'archived' ? Colors.green : Colors.blue)
        : Colors.grey;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.description_outlined, size: 26, color: primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  Text(statusLabel, style: TextStyle(fontSize: 11, color: statusColor)),
                ],
              ),
            ),
            if (onImport != null)
              ActionBtn(icon: Icons.file_download_outlined, tooltip: '导入', color: Colors.blue, onTap: onImport),
            if (onCreate != null)
              ActionBtn(icon: Icons.add_circle_outline, tooltip: '新建', color: Colors.deepPurple, onTap: onCreate),
            if (onGenerate != null)
              ActionBtn(icon: Icons.auto_awesome, tooltip: '生成', color: Colors.deepPurple, onTap: onGenerate),
            if (onReview != null)
              ActionBtn(icon: Icons.rate_review_outlined, tooltip: '审核', color: Colors.teal, onTap: onReview),
            if (onPreview != null)
              ActionBtn(icon: Icons.visibility, tooltip: '预览', onTap: onPreview),
            if (onPrint != null)
              ActionBtn(icon: Icons.print, tooltip: '打印', onTap: onPrint),
            if (onArchive != null)
              ActionBtn(icon: Icons.archive, tooltip: '归档', color: Colors.green, onTap: onArchive),
            if (onDelete != null)
              ActionBtn(icon: Icons.delete_outline, tooltip: '删除', color: Colors.red.shade300, onTap: onDelete),
          ],
        ),
      ),
    );
  }
}

class ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;
  const ActionBtn({super.key, required this.icon, required this.tooltip, this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: color,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _DocumentPreviewSheet extends StatelessWidget {
  final ArchiveDocument doc;
  final ArchiveDao dao;
  final ArchiveAgent? agent;
  final VoidCallback? onArchived;
  const _DocumentPreviewSheet({required this.doc, required this.dao, this.agent, this.onArchived});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(doc.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.rate_review_outlined), tooltip: '审核', onPressed: () {
                  Navigator.pop(context);
                }),
                IconButton(icon: const Icon(Icons.print), tooltip: '打印', onPressed: () {
                  Navigator.pop(context);
                }),
                IconButton(icon: const Icon(Icons.archive), tooltip: '归档', onPressed: () async {
                  await dao.saveDocument(doc.copyWith(status: 'archived'));
                  onArchived?.call();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已归档：${doc.title}')),
                    );
                  }
                }),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              child: doc.content != null
                  ? MarkdownBubble(content: doc.content!)
                  : const Center(child: Text('暂无内容')),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrintPreviewDialog extends StatelessWidget {
  final ArchiveDocument doc;
  const _PrintPreviewDialog({required this.doc});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('打印预览'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: doc.content != null
                    ? MarkdownBubble(content: doc.content!)
                    : const Text('（文档无内容）'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已发送到打印机：${doc.title}')),
            );
            Navigator.pop(context);
          },
          icon: const Icon(Icons.print),
          label: const Text('确认打印'),
        ),
      ],
    );
  }
}

class _CalDay {
  final int date;
  final String label;
  const _CalDay({required this.date, this.label = ''});
}
