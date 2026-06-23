import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:xml/xml.dart';

/// 归档导入解析器集合 —— 把教务系统导出的 mhtml / xlsx / docx 解析成
/// 归档可用的 Markdown。
///
/// **为何独立成类**：这些都是纯函数（输入字节/文本 → Markdown 字符串），
/// 原先内联在 period_tab（2600+ 行 god-file）里，零测试且藏过插值 bug。
/// 抽出后可单元测试（见 test/services/archive/archive_importers_test.dart）。
///
/// 全部 static、无状态、无 Flutter 依赖。
class ArchiveImporters {
  ArchiveImporters._();

  /// 教学任务书 → Markdown（官方横排 10 列，含全部课程）。
  ///
  /// 兼容三种来源：
  /// 1. 教务系统 MHTML 导出（multipart + quoted-printable）；
  /// 2. 浏览器另存的纯 HTML；
  /// 3. 教师手改的 HTML 模板（单元格用 `<input value="…">` 或直接填文本）。
  ///
  /// 解析不出任何课程行返回 null。
  static String? parseTeachingTask(String raw, {DateTime? now}) {
    // MHTML 包裹先解包 + quoted-printable 解码（与点名册/校历一致）。
    String html = raw;
    if (raw.contains('boundary=') && raw.contains('Content-Type:')) {
      html = decodeQuotedPrintable(extractHtmlFromMhtml(raw));
    } else if (raw.contains('=3D')) {
      // 裸 quoted-printable（无 multipart 包裹）也解一下。
      html = decodeQuotedPrintable(raw);
    }

    // <input value="X"> → X，便于读取教师手填的模板。
    html = html.replaceAllMapped(
      RegExp(r'<input\b[^>]*\bvalue="([^"]*)"[^>]*>', caseSensitive: false),
      (m) => m.group(1) ?? '',
    );
    final tagStrip = RegExp(r'<[^>]*>', dotAll: true);
    final wsCollapse = RegExp(r'\s+');
    String clean(String s) => s
        .replaceAll(tagStrip, '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(wsCollapse, ' ')
        .trim();

    final pageText = clean(html);
    final headerMatch =
        RegExp(r'经学校批准聘请(.*?)老师担任(.*?)以下教学任务').firstMatch(pageText);
    final teacher = (headerMatch?.group(1)?.trim().isNotEmpty ?? false)
        ? headerMatch!.group(1)!.trim()
        : '未知';
    final semester = (headerMatch?.group(2)?.trim().isNotEmpty ?? false)
        ? headerMatch!.group(2)!.trim()
        : '未知学期';
    final issueDate =
        RegExp(r'\d{4}年\d{1,2}月\d{1,2}日').firstMatch(pageText)?.group(0) ?? '';

    // 逐 <tr> 取单元格，跳过表头与空行，收集全部课程行（去重：mhtml 含存根+正本两份）。
    final rowRegex =
        RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    final cellRegex = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>',
        dotAll: true, caseSensitive: false);
    final courses = <List<String>>[];
    final seen = <String>{};
    for (final rm in rowRegex.allMatches(html)) {
      final cells = cellRegex
          .allMatches(rm.group(1)!)
          .map((c) => clean(c.group(1)!))
          .toList();
      if (cells.length < 10) continue;
      final name = cells[0];
      if (name.isEmpty || name == '课程名称') continue; // 表头/空行
      // 班级单元格去掉「班级:」前缀（教务系统导出带，样表不含）。
      cells[7] = cells[7].replaceFirst(RegExp(r'^班级[:：]\s*'), '');
      final row = cells.take(10).toList();
      final sig = row.join('');
      if (!seen.add(sig)) continue; // 存根/正本重复行去重
      courses.add(row);
    }
    if (courses.isEmpty) return null;

    final stamp = (now ?? DateTime.now()).toString().substring(0, 16);
    final buf = StringBuffer();
    buf.writeln('# 教 学 任 务 书\n');
    buf.writeln('经学校批准聘请$teacher老师担任$semester以下教学任务：\n');
    buf.writeln(
        '| 课程名称 | 课程类别 | 总学时 | 讲授 | 实验 | 实践 | 课外自主学时 | 教学班级 | 计划人数 | 备注 |');
    buf.writeln(
        '|------|------|------|------|------|------|------|------|------|------|');
    for (final c in courses) {
      buf.writeln(
          '| ${c[0]} | ${c[1]} | ${c[2]} | ${c[3]} | ${c[4]} | ${c[5]} | ${c[6]} | ${c[7]} | ${c[8]} | ${c[9]} |');
    }
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 教师：$teacher ｜ 学期：$semester');
    if (issueDate.isNotEmpty) {
      buf.writeln('> 签发日期：$issueDate');
    }
    buf.writeln('> 课程行数：${courses.length}');
    buf.writeln('> 数据来源：教务系统（jwgl.chzu.edu.cn）');
    buf.writeln('> 导入时间：$stamp');
    return buf.toString();
  }

  /// 学生点名册（MHTML 考勤表）→ Markdown。指定 [targetCourseName] 时仅解析该课程。
  static String? parseRollCall(String raw,
      {DateTime? now, String? targetCourseName}) {
    String html = raw;
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

    html = decodeQuotedPrintable(html);

    final courseMatch = RegExp(r'课程名称：(.+?)(?:<|$)').firstMatch(html);
    final teacherMatch = RegExp(r'授课教师：(.+?)(?:<|$)').firstMatch(html);
    final scheduleMatch = RegExp(r'课程安排：(.+?)(?:<|$)').firstMatch(html);
    final courseName = courseMatch?.group(1)?.trim() ?? '';
    final teacher = teacherMatch?.group(1)?.trim() ?? '未知';
    final schedule = scheduleMatch?.group(1)?.trim() ?? '';

    final target = targetCourseName?.trim();
    if (target != null && target.isNotEmpty && !courseName.contains(target)) {
      return null;
    }

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

    final buf = StringBuffer();
    buf.writeln('# 学生点名册\n');
    buf.writeln(
        '**课程**：${courseName.isNotEmpty ? courseName : target ?? '当前课程'}');
    buf.writeln('**授课教师**：$teacher');
    buf.writeln('**课程安排**：$schedule');
    buf.writeln('**学生人数**：${students.length}人\n');
    buf.writeln('| 序号 | 学号 | 姓名 | 性别 |');
    buf.writeln('|------|------|------|------|');
    for (final s in students) {
      buf.writeln(
          '| ${s['seq']} | ${s['student_id']} | ${s['name']} | ${s['gender']} |');
    }
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 数据来源：教务系统考勤表');
    buf.writeln(
        '> 导入时间：${(now ?? DateTime.now()).toString().substring(0, 16)}');
    return buf.toString();
  }

  /// 课程课表（Excel）→ [CourseScheduleResult]。
  /// markdown 为 null 时 allCourseNames 含表中实际发现的课程名（供 UI 提示）。
  static CourseScheduleResult parseCourseSchedule(List<int> bytes,
      {DateTime? now, String? targetCourseName}) {
    Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } on Exception {
      // 非法/非 .xlsx 字节：decodeBytes 会抛 UnsupportedError 等，按"未解析"处理
      return const CourseScheduleResult(null, {});
    } on Error {
      return const CourseScheduleResult(null, {});
    }
    if (excel.sheets.isEmpty) return const CourseScheduleResult(null, {});
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return const CourseScheduleResult(null, {});

    final detailResult = _parseCourseScheduleDetailTable(
      sheet.rows,
      now: now,
      targetCourseName: targetCourseName,
    );
    if (detailResult != null) return detailResult;

    final matrixResult = _parseCourseScheduleMatrix(
      sheet.rows,
      now: now,
      targetCourseName: targetCourseName,
    );
    if (matrixResult != null) return matrixResult;

    return const CourseScheduleResult(null, {});
  }

  static CourseScheduleResult? _parseCourseScheduleDetailTable(
    List<List<Data?>> sheetRows, {
    DateTime? now,
    String? targetCourseName,
  }) {
    final headerRowIndex = sheetRows.indexWhere((row) {
      final values = row.map(_excelCellText).toList();
      return values.contains('课程名称') && values.contains('班级');
    });
    if (headerRowIndex == -1) return null;

    final header = sheetRows[headerRowIndex].map(_excelCellText).toList();
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

    String cell(List<Data?> r, int idx) =>
        r.length > idx ? _excelCellText(r[idx]) : '';

    final rows = <Map<String, String>>[];
    final allCourseNames = <String>{};
    final target = targetCourseName?.trim();
    for (var i = headerRowIndex + 1; i < sheetRows.length; i++) {
      final r = sheetRows[i];
      final courseName = cell(r, courseIdx);
      if (courseName.isNotEmpty) allCourseNames.add(courseName);
      if (!_courseMatches(courseName, target)) {
        continue;
      }
      rows.add({
        'course': courseName,
        'type': cell(r, typeIdx),
        'class': cell(r, classIdx),
        'date': cell(r, dateIdx),
        'week': cell(r, weekIdx),
        'day': cell(r, dayIdx),
        'period': cell(r, periodIdx),
        'teacher': cell(r, teacherIdx),
        'location': cell(r, locationIdx),
      });
    }
    if (rows.isEmpty) return CourseScheduleResult(null, allCourseNames);

    return _buildCourseScheduleMarkdown(
      rows: rows,
      allCourseNames: allCourseNames,
      targetCourseName: target,
      now: now,
      sourceLabel: '教务系统课表（Excel明细表）',
    );
  }

  static CourseScheduleResult? _parseCourseScheduleMatrix(
    List<List<Data?>> sheetRows, {
    DateTime? now,
    String? targetCourseName,
  }) {
    final title = sheetRows.isNotEmpty
        ? sheetRows.first
            .map(_excelCellText)
            .where((v) => v.isNotEmpty)
            .join(' ')
        : '';
    final headerRowIndex = sheetRows.indexWhere((row) {
      final values = row.map(_excelCellText).toList();
      return values.any((v) => v.contains('节次')) &&
          values.any((v) => v.contains('星期一')) &&
          values.any((v) => v.contains('星期日'));
    });
    if (headerRowIndex == -1) return null;

    final header = sheetRows[headerRowIndex].map(_excelCellText).toList();
    final dayColumns = <int, String>{};
    for (var col = 0; col < header.length; col++) {
      final day = _normalizeWeekday(header[col]);
      if (day != null) dayColumns[col] = day;
    }
    if (dayColumns.isEmpty) return null;

    final rows = <Map<String, String>>[];
    final allCourseNames = <String>{};
    final target = targetCourseName?.trim();
    for (var rowIndex = headerRowIndex + 1;
        rowIndex < sheetRows.length;
        rowIndex++) {
      final row = sheetRows[rowIndex];
      if (row.isEmpty) continue;
      final periodLabel = _excelCellText(row.first);
      if (!periodLabel.contains('节')) continue;
      for (final entry in dayColumns.entries) {
        final col = entry.key;
        if (row.length <= col) continue;
        final cellText = _excelCellText(row[col]);
        if (cellText.isEmpty) continue;
        for (final item in _splitScheduleCell(cellText)) {
          final parsed = _parseMatrixScheduleItem(
            item,
            weekday: entry.value,
            fallbackPeriod: periodLabel,
          );
          if (parsed == null) continue;
          final courseName = parsed['course'] ?? '';
          if (courseName.isNotEmpty) allCourseNames.add(courseName);
          if (!_courseMatches(courseName, target)) {
            continue;
          }
          rows.add(parsed);
        }
      }
    }
    if (rows.isEmpty) return CourseScheduleResult(null, allCourseNames);

    return _buildCourseScheduleMarkdown(
      rows: rows,
      allCourseNames: allCourseNames,
      targetCourseName: target,
      now: now,
      sourceLabel:
          title.isNotEmpty ? '$title（Excel矩阵课表）' : '实验教学服务平台课表（Excel矩阵）',
    );
  }

  static CourseScheduleResult _buildCourseScheduleMarkdown({
    required List<Map<String, String>> rows,
    required Set<String> allCourseNames,
    required String? targetCourseName,
    required DateTime? now,
    required String sourceLabel,
  }) {
    final target = targetCourseName?.trim();

    const dayNames = {
      1: '星期一',
      2: '星期二',
      3: '星期三',
      4: '星期四',
      5: '星期五',
      6: '星期六',
      7: '星期日'
    };
    final theory = rows.where((r) => _isTheoryType(r['type'] ?? '')).toList();
    final lab = rows.where((r) => _isLabType(r['type'] ?? '')).toList();
    final other = rows
        .where((r) =>
            !_isTheoryType(r['type'] ?? '') && !_isLabType(r['type'] ?? ''))
        .toList();
    final teacher = rows.firstWhere(
      (r) => r['teacher']!.isNotEmpty,
      orElse: () => {'teacher': '未知'},
    )['teacher']!;
    final displayCourseName = (target != null && target.isNotEmpty)
        ? target
        : rows.first['course'] ?? '当前课程';
    final displayClasses = rows
        .map((r) => r['class'] ?? '')
        .where((v) => v.trim().isNotEmpty)
        .map((v) => v.replaceAll(RegExp(r'班组\d[：:].*'), '').trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .join('、');

    String semester = '未知学期';
    if (rows.isNotEmpty && rows[0]['date']!.isNotEmpty) {
      final d = rows[0]['date']!;
      final year = int.tryParse(d.substring(0, 4)) ?? 0;
      final month = d.length >= 7 ? (int.tryParse(d.substring(5, 7)) ?? 0) : 0;
      if (month >= 2 && month <= 7) {
        semester = '${year - 1}-$year学年第二学期';
      } else if (month >= 8) {
        semester = '$year-${year + 1}学年第一学期';
      }
    }

    int? w(Map<String, String> r) => _firstInt(r['week'] ?? '');
    int? d(Map<String, String> r) => _weekdayOrder(r['day'] ?? '');
    int? p(Map<String, String> r) => _firstInt(r['period'] ?? '');
    int compareSchedule(Map<String, String> a, Map<String, String> b) {
      final weekOrder = (w(a) ?? 0).compareTo(w(b) ?? 0);
      if (weekOrder != 0) return weekOrder;
      final dayOrder = (d(a) ?? 0).compareTo(d(b) ?? 0);
      if (dayOrder != 0) return dayOrder;
      return (p(a) ?? 0).compareTo(p(b) ?? 0);
    }

    final buf = StringBuffer();
    buf.writeln('# 课程课表：$displayCourseName\n');
    buf.writeln('**教师**：$teacher');
    buf.writeln('**学期**：$semester');
    if (displayClasses.isNotEmpty) {
      buf.writeln('**班级**：$displayClasses\n');
    }

    theory.sort(compareSchedule);
    buf.writeln('## 一、理论课\n');
    buf.writeln('| 周次 | 星期 | 节次 | 地点 | 班级 |');
    buf.writeln('|------|------|------|------|------|');
    for (final r in theory) {
      final dayNum = int.tryParse(r['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : r['day']!;
      buf.writeln(
          '| ${r['week']} | $dayName | ${r['period']} | ${r['location']} | ${r['class']} |');
    }
    if (theory.isEmpty) buf.writeln('| - | - | - | - | - |');
    buf.writeln('');

    final groups = <String, List<Map<String, String>>>{};
    for (final r in lab) {
      final groupMatch = RegExp(r'班组(\d)[：:]\d+人').firstMatch(r['class']!);
      final grpKey = groupMatch != null ? '班组${groupMatch.group(1)}' : '综合组';
      groups.putIfAbsent(grpKey, () => []).add(r);
    }

    buf.writeln('## 二、实验课\n');
    for (final entry in groups.entries) {
      entry.value.sort(compareSchedule);
      final peopleMatch =
          RegExp(r'班组\d[：:](\d+)人').firstMatch(entry.value.first['class']!);
      final people = peopleMatch?.group(1) ?? '';
      final dayNum = int.tryParse(entry.value.first['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : entry.value.first['day'] ?? '';
      final periodInfo = entry.value.first['period'] ?? '';
      final peopleSuffix = people.isNotEmpty ? '（$people人）' : '';
      buf.writeln('### ${entry.key}$peopleSuffix — $dayName $periodInfo\n');
      buf.writeln('| 周次 | 星期 | 节次 | 地点 | 班级 |');
      buf.writeln('|------|------|------|------|------|');
      for (final r in entry.value) {
        buf.writeln(
            '| ${r['week']} | ${r['day']} | ${r['period']} | ${r['location']} | ${r['class']} |');
      }
      buf.writeln('');
    }
    if (groups.isEmpty) buf.writeln('（无实验课记录）\n');

    if (other.isNotEmpty) {
      other.sort(compareSchedule);
      buf.writeln('## 三、其它安排\n');
      buf.writeln('| 类型 | 周次 | 星期 | 节次 | 地点 | 班级 |');
      buf.writeln('|------|------|------|------|------|------|');
      for (final r in other) {
        buf.writeln(
            '| ${r['type']} | ${r['week']} | ${r['day']} | ${r['period']} | ${r['location']} | ${r['class']} |');
      }
      buf.writeln('');
    }

    buf.writeln('## ${other.isEmpty ? '三' : '四'}、统计\n');
    final theoryWeeks =
        theory.map((r) => _weekSpanCount(r['week'] ?? '')).fold<int>(
              0,
              (sum, count) => sum + count,
            );
    final labWeeks = lab.map((r) => _weekSpanCount(r['week'] ?? '')).fold<int>(
          0,
          (sum, count) => sum + count,
        );
    final groupCount = groups.length;
    final totalTheoryHours = theory.length * 2;
    final totalLabHours = lab.length * 2;
    buf.writeln(
        '- 理论课：$theoryWeeks周 × 2学时 = ${theoryWeeks * 2}学时（实际$totalTheoryHours课时）');
    buf.writeln(
        '- 实验课：$groupCount组 × $labWeeks周 × 2学时 = ${groupCount * labWeeks * 2}学时（实际$totalLabHours课时）');
    buf.writeln('- 总学时：${totalTheoryHours + totalLabHours}课时\n');
    buf.writeln('---');
    buf.writeln('> 数据来源：$sourceLabel');
    buf.writeln(
        '> 导入时间：${(now ?? DateTime.now()).toString().substring(0, 16)}');
    return CourseScheduleResult(buf.toString(), allCourseNames);
  }

  static String _excelCellText(Data? cell) =>
      (cell?.value?.toString() ?? '').trim();

  static bool _courseMatches(String courseName, String? targetCourseName) {
    final target = _normalizeCourseName(targetCourseName ?? '');
    if (target.isEmpty) return true;
    final course = _normalizeCourseName(courseName);
    if (course.isEmpty) return false;
    return course.contains(target) || target.contains(course);
  }

  static String _normalizeCourseName(String value) => value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('《', '')
      .replaceAll('》', '')
      .toLowerCase();

  static List<String> _splitScheduleCell(String text) => text
      .split(RegExp(r'[\r\n]+'))
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  static Map<String, String>? _parseMatrixScheduleItem(
    String text, {
    required String weekday,
    required String fallbackPeriod,
  }) {
    final parts = text.split('◇').map((v) => v.trim()).toList();
    if (parts.length < 2) return null;
    final first = parts[0];
    final marker = first.isNotEmpty ? first.substring(0, 1) : '';
    final course = first.replaceFirst(RegExp(r'^[★○●◎◇\s]+'), '').trim();
    if (course.isEmpty) return null;
    final weekAndPeriod = parts.length > 1 ? parts[1] : '';
    final classText = parts.length > 2 ? parts[2] : '';
    final teacher = parts.length > 3 ? parts[3] : '';
    final location = parts.length > 4 ? parts.sublist(4).join('◇') : '';
    final weekMatch = RegExp(r'([\d,\-、]+)\s*周').firstMatch(weekAndPeriod);
    final periodMatch = RegExp(r'\[([^\]]+)\]').firstMatch(weekAndPeriod);
    return {
      'course': course,
      'type': _scheduleTypeFromMarker(marker),
      'class': classText,
      'date': '',
      'week': weekMatch?.group(1) ?? weekAndPeriod,
      'day': weekday,
      'period': periodMatch?.group(1) ?? fallbackPeriod,
      'teacher': teacher,
      'location': location,
    };
  }

  static String _scheduleTypeFromMarker(String marker) {
    if (marker == '★') return '教务';
    if (marker == '○' || marker == '●' || marker == '◎') return '实验';
    return '其它';
  }

  static String? _normalizeWeekday(String value) {
    const values = {
      '星期一': '星期一',
      '周一': '星期一',
      '一': '星期一',
      '星期二': '星期二',
      '周二': '星期二',
      '二': '星期二',
      '星期三': '星期三',
      '周三': '星期三',
      '三': '星期三',
      '星期四': '星期四',
      '周四': '星期四',
      '四': '星期四',
      '星期五': '星期五',
      '周五': '星期五',
      '五': '星期五',
      '星期六': '星期六',
      '周六': '星期六',
      '六': '星期六',
      '星期日': '星期日',
      '星期天': '星期日',
      '周日': '星期日',
      '周天': '星期日',
      '日': '星期日',
    };
    return values[value.trim()];
  }

  static bool _isTheoryType(String value) =>
      value.contains('教务') || value.contains('理论') || value.contains('★');

  static bool _isLabType(String value) =>
      value.contains('实验') || value.contains('实践') || value.contains('○');

  static int? _firstInt(String value) =>
      int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '');

  static int _weekSpanCount(String value) {
    final normalized = value.replaceAll('，', ',').replaceAll('、', ',');
    var total = 0;
    for (final part in normalized.split(',')) {
      final range = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(part);
      if (range != null) {
        final start = int.parse(range.group(1)!);
        final end = int.parse(range.group(2)!);
        if (end >= start) {
          total += end - start + 1;
          continue;
        }
      }
      if (RegExp(r'\d+').hasMatch(part)) total++;
    }
    return total;
  }

  static int? _weekdayOrder(String value) {
    const order = {
      '星期一': 1,
      '星期二': 2,
      '星期三': 3,
      '星期四': 4,
      '星期五': 5,
      '星期六': 6,
      '星期日': 7,
    };
    return order[_normalizeWeekday(value) ?? value];
  }

  /// 从 MHTML multipart 包裹里提取 HTML 正文。无 boundary 时原样返回。
  static String extractHtmlFromMhtml(String raw) {
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

  /// quoted-printable 解码为 UTF-8 字符串（=XX → 字节，软换行 =\r\n 去除）。
  static String decodeQuotedPrintable(String input) {
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
          bytes.addAll(utf8.encode('='));
        }
      } else {
        bytes.addAll(utf8.encode(input[i]));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 校历（MHTML）→ Markdown。解析不出表格行返回 null。
  static String? parseCalendar(String raw, {DateTime? now}) {
    String html = extractHtmlFromMhtml(raw);
    html = decodeQuotedPrintable(html);

    final tagStrip = RegExp(r'<[^>]*>', dotAll: true);
    final plainText =
        html.replaceAll(tagStrip, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final semester = _extractCalendarSemester(plainText) ?? '未识别学年学期';
    final parsedRows = _extractCalendarRows(html);

    if (parsedRows.isEmpty) return null;

    final weeks = <List<CalDay>>[];
    int? currentMonth;
    for (final cells in parsedRows) {
      for (final cell in cells) {
        final month = _calendarMonthNumber(cell);
        if (month != null) {
          currentMonth = month;
          break;
        }
      }

      if (cells.length <= 2) continue;
      final dayCells =
          cells.length >= 8 ? cells.sublist(cells.length - 7) : cells;
      if (dayCells.length != 7) continue;

      final dayNumbers = dayCells
          .map((cell) => int.tryParse(
                RegExp(r'^(\d+)').firstMatch(cell)?.group(1) ?? '',
              ))
          .toList();
      if (dayNumbers.every((day) => day == null)) continue;

      final month = currentMonth ?? _calendarFallbackStartMonth(semester);
      final firstCurrentMonthIndex = dayNumbers.indexWhere(
        (day) => day != null && day > 0 && day <= 7,
      );
      final currentWeek = <CalDay>[];
      int? previousDay;
      int assignedMonth = month;
      for (var d = 0; d < 7; d++) {
        final rawCell = dayCells[d];
        final dayNum = dayNumbers[d] ?? 0;
        if (dayNum > 0) {
          if (firstCurrentMonthIndex > 0 &&
              d < firstCurrentMonthIndex &&
              dayNum > 20) {
            assignedMonth = _previousMonth(month);
          } else if (previousDay != null && previousDay > 20 && dayNum <= 7) {
            assignedMonth = _nextMonth(assignedMonth);
          } else if (d >= firstCurrentMonthIndex ||
              firstCurrentMonthIndex < 0) {
            assignedMonth = month;
          }
        }
        final fullDate = dayNum > 0
            ? DateTime(
                _calendarYearForMonth(semester, assignedMonth, now: now),
                assignedMonth,
                dayNum,
              )
            : null;
        currentWeek.add(
          CalDay(
            date: dayNum,
            label: _calendarCellLabel(rawCell),
            fullDate: fullDate,
          ),
        );
        if (dayNum > 0) previousDay = dayNum;
      }
      weeks.add(currentWeek);
    }

    final uniqueWeeks = <List<CalDay>>[];
    final seenWeekKeys = <String>{};
    for (final week in weeks) {
      final key = week
          .map((day) => day.fullDate?.toIso8601String() ?? '${day.date}')
          .join('|');
      if (!seenWeekKeys.add(key)) continue;
      uniqueWeeks.add(week);
    }
    if (uniqueWeeks.isEmpty) return null;

    final buf = StringBuffer();
    buf.writeln('# 校 历\n');
    buf.writeln('**学年学期：** $semester\n');
    final firstDate = uniqueWeeks.first.first.fullDate;
    if (firstDate != null) {
      buf.writeln('**起始日期：** ${_formatCalendarDate(firstDate)}（周一）\n');
    }
    buf.writeln('## 校历总览\n');
    buf.writeln('| 周次 | 起止日期 | 周一 | 周二 | 周三 | 周四 | 周五 | 周六 | 周日 | 备注 |');
    buf.writeln(
        '|------|----------|------|------|------|------|------|------|------|------|');

    final eventDates = <String, Set<String>>{};
    final phaseRows = <String>[];
    for (var wk = 0; wk < uniqueWeeks.length; wk++) {
      final week = uniqueWeeks[wk];
      final dateRange = _formatCalendarWeekRange(week);
      String phaseLabel = '';
      final notes = <String>[];
      for (final day in week) {
        if (day.label.isEmpty) continue;
        if (day.label.contains('考试') || day.label == '暑假') {
          phaseLabel = day.label.replaceAll('考试周', '').replaceAll('周', '');
          phaseRows.add('${day.label}：$dateRange');
        } else {
          final dateText = day.fullDate == null
              ? '${day.date}日'
              : _formatCalendarDate(day.fullDate!);
          eventDates.putIfAbsent(day.label, () => <String>{}).add(dateText);
          notes.add(day.label);
        }
      }

      final weekNum = phaseLabel.isNotEmpty ? phaseLabel : '${wk + 1}';
      final note = notes.isNotEmpty
          ? notes.toSet().join('、')
          : (phaseLabel.isNotEmpty ? phaseLabel : '');

      final dayCols = <String>[];
      for (var d = 0; d < 7; d++) {
        final day = week[d];
        if (day.label.isNotEmpty) {
          dayCols.add('${day.date}（${day.label}）');
        } else {
          dayCols.add('${day.date}');
        }
      }

      buf.writeln(
          '| $weekNum | $dateRange | ${dayCols[0]} | ${dayCols[1]} | ${dayCols[2]} | ${dayCols[3]} | ${dayCols[4]} | ${dayCols[5]} | ${dayCols[6]} | $note |');
    }

    if (eventDates.isNotEmpty) {
      buf.writeln('');
      buf.writeln('## 节假日安排\n');
      buf.writeln('| 节日 | 日期 | 说明 |');
      buf.writeln('|------|------|------|');
      for (final entry in eventDates.entries) {
        buf.writeln('| ${entry.key} | ${entry.value.join('、')} | 以学校校历页面为准 |');
      }
    }

    if (phaseRows.isNotEmpty) {
      buf.writeln('');
      buf.writeln('## 关键节点\n');
      for (final row in phaseRows.toSet()) {
        buf.writeln('- $row');
      }
    }

    buf.writeln('');
    buf.writeln('## 说明\n');
    buf.writeln('- 本日历为全校通用校历，不包含具体课程、教师或班级信息。');
    buf.writeln('- 具体教学安排以课程课表和后续学校通知为准。');
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 数据来源：学校校历系统');
    buf.writeln(
        '> 导入时间：${(now ?? DateTime.now()).toString().substring(0, 16)}');
    return buf.toString();
  }

  static List<List<String>> _extractCalendarRows(String html) {
    final rowRegex =
        RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    final cellTextRegex =
        RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false);
    final tagStrip = RegExp(r'<[^>]*>', dotAll: true);

    final rows = <List<String>>[];
    for (final rowMatch in rowRegex.allMatches(html)) {
      final rowHtml = rowMatch.group(1)!;
      final cells = <String>[];
      for (final cellMatch in cellTextRegex.allMatches(rowHtml)) {
        final cellContent = cellMatch.group(1)!;
        final dp1 = RegExp(r'class="dp1"[^>]*>(.*?)</p>', dotAll: true)
                .firstMatch(cellContent)
                ?.group(1)
                ?.trim() ??
            '';
        final dp2 = RegExp(r'class="dp2"[^>]*>(.*?)</p>', dotAll: true)
                .firstMatch(cellContent)
                ?.group(1)
                ?.trim() ??
            '';
        final combined = (dp1 + dp2).trim();
        final text = combined.isNotEmpty
            ? combined
            : cellContent.replaceAll(tagStrip, '').trim();
        final normalized = text.replaceAll(RegExp(r'\s+'), '');
        if (normalized.isNotEmpty) cells.add(normalized);
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  static String? _extractCalendarSemester(String text) {
    return RegExp(r'\d{4}\s*-\s*\d{4}\s*学年\s*第[一二三四1-4]+学期')
        .firstMatch(text)
        ?.group(0)
        ?.replaceAll(RegExp(r'\s+'), '');
  }

  static int _calendarFallbackStartMonth(String semester) {
    if (semester.contains('第二') || semester.contains('第2')) return 3;
    return 9;
  }

  static int _calendarYearForMonth(
    String semester,
    int month, {
    DateTime? now,
  }) {
    final match = RegExp(r'(\d{4})\s*-\s*(\d{4})').firstMatch(semester);
    if (match == null) return (now ?? DateTime.now()).year;
    final startYear = int.parse(match.group(1)!);
    final endYear = int.parse(match.group(2)!);
    return month >= 8 ? startYear : endYear;
  }

  static int? _calendarMonthNumber(String value) {
    const months = {
      '一月': 1,
      '二月': 2,
      '三月': 3,
      '四月': 4,
      '五月': 5,
      '六月': 6,
      '七月': 7,
      '八月': 8,
      '九月': 9,
      '十月': 10,
      '十一月': 11,
      '十二月': 12,
    };
    for (final entry in months.entries) {
      if (value.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static int _previousMonth(int month) => month == 1 ? 12 : month - 1;

  static int _nextMonth(int month) => month == 12 ? 1 : month + 1;

  static String _calendarCellLabel(String value) {
    const labels = {
      '清明': '清明节',
      '劳动': '劳动节',
      '端午': '端午节',
      '中秋': '中秋节',
      '国庆': '国庆节',
      '元旦': '元旦',
      '缓补': '缓补考试周',
      '期末': '期末考试周',
      '暑假': '暑假',
      '寒假': '寒假',
    };
    for (final entry in labels.entries) {
      if (value.contains(entry.key)) return entry.value;
    }
    return '';
  }

  static String _formatCalendarDate(DateTime date) =>
      '${date.month}月${date.day}日';

  static String _formatCalendarWeekRange(List<CalDay> week) {
    final first = week.first.fullDate;
    final last = week.last.fullDate;
    if (first == null || last == null) return '';
    return '${first.month}/${first.day}-${last.month}/${last.day}';
  }

  /// 教学问卷（MHTML）→ Markdown。从教务系统"打印教学任务书"页面提取课程评价问卷数据。
  /// 解析不出可用的内容行返回 null。
  static String? parseSurvey(String raw, {DateTime? now}) {
    String html = extractHtmlFromMhtml(raw);
    html = decodeQuotedPrintable(html);

    final tagStrip = RegExp(r'<[^>]*>', dotAll: true);

    // 提取页面标题
    final titleMatch =
        RegExp(r'<title>(.*?)</title>', dotAll: true, caseSensitive: false)
            .firstMatch(html);
    final pageTitle = titleMatch?.group(1)?.trim() ?? '教学任务书';

    // 提取所有表格内容
    final tableRows = <List<String>>[];
    final tableRegex =
        RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    for (final rowMatch in tableRegex.allMatches(html)) {
      final rowHtml = rowMatch.group(1)!;
      final cells = <String>[];
      final cellRegex = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>',
          dotAll: true, caseSensitive: false);
      for (final cellMatch in cellRegex.allMatches(rowHtml)) {
        var text = cellMatch.group(1)!.replaceAll(tagStrip, '').trim();
        text = text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) cells.add(text);
      }
      if (cells.isNotEmpty) tableRows.add(cells);
    }

    if (tableRows.isEmpty) return null;

    final buf = StringBuffer();
    buf.writeln('# 教学问卷：$pageTitle\n');
    buf.writeln('**来源**：教务系统（courseTableForTeacher!printLessonBook.mhtml）\n');

    for (var i = 0; i < tableRows.length; i++) {
      final row = tableRows[i];
      buf.writeln('| ${row.join(' | ')} |');
    }

    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 数据来源：教务管理系统（jwgl.chzu.edu.cn）');
    buf.writeln('> 文件来源：courseTableForTeacher!printLessonBook.mhtml');
    buf.writeln(
        '> 导入时间：${(now ?? DateTime.now()).toString().substring(0, 16)}');
    return buf.toString();
  }

  /// 课程目标支撑毕业要求达成度调查问卷（Excel）→ Markdown。
  ///
  /// 兼容问卷星/校内问卷导出的表格：前几行为标题与发起信息，某一行包含
  /// `学号/工号`、`学生姓名` 和若干 `[单选题]...` 列，后续为学生作答。
  static String? parseSurveyExcel(List<int> bytes, {DateTime? now}) {
    Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } on Exception {
      return null;
    } on Error {
      return null;
    }
    if (excel.sheets.isEmpty) return null;
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return null;

    final rows = sheet.rows;
    final headerRowIndex = rows.indexWhere((row) {
      final values = row.map(_excelCellText).toList();
      return values.any((v) => v.contains('学号') || v.contains('工号')) &&
          values.any((v) => v.contains('学生姓名') || v == '姓名') &&
          values.any((v) => v.contains('[单选题]') || v.contains('单选题'));
    });
    if (headerRowIndex == -1) return null;

    final title = rows
        .take(headerRowIndex)
        .expand((row) => row.map(_excelCellText))
        .firstWhere(
          (v) => v.trim().isNotEmpty,
          orElse: () => '课程目标支撑毕业要求达成度调查问卷',
        );
    final meta = rows
        .take(headerRowIndex)
        .skip(1)
        .expand((row) => row.map(_excelCellText))
        .where((v) => v.trim().isNotEmpty)
        .join('；');

    final header = rows[headerRowIndex].map(_excelCellText).toList();
    int findColumn(List<String> tokens) => header.indexWhere(
          (value) => tokens.any(value.contains),
        );
    final idIdx = findColumn(['学号', '工号']);
    final nameIdx = findColumn(['学生姓名', '姓名']);
    final classIdx = findColumn(['班级']);
    final submitIdx = findColumn(['提交时间']);
    final questionIndices = <int>[
      for (var i = 0; i < header.length; i++)
        if (header[i].contains('[单选题]') || header[i].contains('单选题')) i,
    ];
    if (questionIndices.isEmpty) return null;

    final answers = <_SurveyAnswerRow>[];
    for (var r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int idx) => row.length > idx ? _excelCellText(row[idx]) : '';
      final choices = <String>[
        for (final qIdx in questionIndices) _normalizeSurveyChoice(cell(qIdx)),
      ];
      if (choices.every((v) => v.isEmpty)) continue;
      answers.add(
        _SurveyAnswerRow(
          id: idIdx == -1 ? '' : cell(idIdx),
          name: nameIdx == -1 ? '' : cell(nameIdx),
          className: classIdx == -1 ? '' : cell(classIdx),
          submittedAt: submitIdx == -1 ? '' : cell(submitIdx),
          choices: choices,
        ),
      );
    }
    if (answers.isEmpty) return null;

    final questions = <String>[
      for (final qIdx in questionIndices) _cleanSurveyQuestion(header[qIdx]),
    ];
    const choiceOrder = ['A', 'B', 'C', 'D', 'E'];
    final buf = StringBuffer();
    buf.writeln('# $title\n');
    if (meta.isNotEmpty) buf.writeln('**发起信息**：$meta');
    buf.writeln('**有效答卷**：${answers.length} 份');
    buf.writeln('**题目数量**：${questions.length} 题');
    buf.writeln(
        '**导入时间**：${(now ?? DateTime.now()).toString().substring(0, 16)}\n');

    buf.writeln('## 一、达成度统计\n');
    buf.writeln('| 题号 | 题目摘要 | A | B | C | D | E | 平均分 | 达成度 |');
    buf.writeln('|------|----------|---|---|---|---|---|--------|--------|');
    for (var i = 0; i < questions.length; i++) {
      final counts = {
        for (final choice in choiceOrder) choice: 0,
      };
      var scoreSum = 0.0;
      var scoreCount = 0;
      for (final answer in answers) {
        final choice = i < answer.choices.length ? answer.choices[i] : '';
        if (counts.containsKey(choice)) counts[choice] = counts[choice]! + 1;
        final score = _surveyChoiceScore(choice);
        if (score != null) {
          scoreSum += score;
          scoreCount++;
        }
      }
      final avg = scoreCount == 0 ? 0.0 : scoreSum / scoreCount;
      final achievement = avg / 5 * 100;
      buf.writeln(
        '| Q${i + 1} | ${_shortSurveyQuestion(questions[i])} | '
        '${counts['A']} | ${counts['B']} | ${counts['C']} | ${counts['D']} | ${counts['E']} | '
        '${avg.toStringAsFixed(2)} | ${achievement.toStringAsFixed(1)}% |',
      );
    }

    buf.writeln('\n## 二、题目原文\n');
    for (var i = 0; i < questions.length; i++) {
      buf.writeln('${i + 1}. ${questions[i]}');
    }

    buf.writeln('\n## 三、作答明细\n');
    final qHeaders = [
      for (var i = 0; i < questions.length; i++) 'Q${i + 1}',
    ];
    buf.writeln('| 序号 | 学号/工号 | 姓名 | 班级 | 提交时间 | ${qHeaders.join(' | ')} |');
    buf.writeln(
        '|------|-----------|------|------|----------|${List.filled(qHeaders.length, '----').join('|')}|');
    for (var i = 0; i < answers.length; i++) {
      final answer = answers[i];
      buf.writeln(
        '| ${i + 1} | ${answer.id} | ${answer.name} | ${answer.className} | ${answer.submittedAt} | ${answer.choices.join(' | ')} |',
      );
    }

    buf.writeln('\n---');
    buf.writeln('> 数据来源：课程目标支撑毕业要求达成度调查问卷（Excel）');
    return buf.toString();
  }

  static String _cleanSurveyQuestion(String value) {
    var text = value
        .replaceAll('_x000D_', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('null.', '')
        .replaceAll('null', '')
        .trim();
    text = text.replaceFirst(RegExp(r'^\[单选题\]\s*'), '');
    text = text.replaceFirst(RegExp(r'^\d+[、.．]\s*'), '');
    final optionStart = RegExp(r'\s+A\.\s*1\s*-').firstMatch(text)?.start;
    if (optionStart != null) text = text.substring(0, optionStart).trim();
    return text;
  }

  static String _shortSurveyQuestion(String value, {int maxChars = 42}) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }

  static String _normalizeSurveyChoice(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.isEmpty) return '';
    final letter = RegExp(r'[A-E]').firstMatch(trimmed)?.group(0);
    if (letter != null) return letter;
    final score = RegExp(r'[1-5]').firstMatch(trimmed)?.group(0);
    if (score == null) return trimmed;
    return const {'1': 'A', '2': 'B', '3': 'C', '4': 'D', '5': 'E'}[score] ??
        trimmed;
  }

  static int? _surveyChoiceScore(String choice) =>
      const {'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5}[choice];

  /// 从 docx（zip）提取纯文本。解析失败返回 null（调用方记录日志）。
  static String? extractDocxText(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('word/document.xml');
    if (file == null) return null;
    final xml = utf8.decode(file.content);
    final doc = XmlDocument.parse(xml);
    final texts = doc.findAllElements('w:t').map((e) => e.innerText).join('');
    return texts.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// 课表解析结果：markdown 为 null 时 allCourseNames 含表中实际课程名（供 UI 提示）。
class CourseScheduleResult {
  final String? markdown;
  final Set<String> allCourseNames;
  const CourseScheduleResult(this.markdown, this.allCourseNames);
}

class _SurveyAnswerRow {
  final String id;
  final String name;
  final String className;
  final String submittedAt;
  final List<String> choices;

  const _SurveyAnswerRow({
    required this.id,
    required this.name,
    required this.className,
    required this.submittedAt,
    required this.choices,
  });
}

/// 校历单元格：日期数字 + 可选标签（节假日/考试周）。
class CalDay {
  final int date;
  final String label;
  final DateTime? fullDate;

  const CalDay({
    required this.date,
    this.label = '',
    this.fullDate,
  });
}
