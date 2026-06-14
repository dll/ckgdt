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

  /// 学生点名册（MHTML 考勤表）→ Markdown。非"移动应用开发"或无学生返回 null。
  static String? parseRollCall(String raw, {DateTime? now}) {
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

    if (!courseName.contains('移动应用开发')) return null;

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
    buf.writeln('**课程**：移动应用开发');
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
      {DateTime? now}) {
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

    final header =
        sheet.rows[0].map((c) => (c?.value?.toString() ?? '').trim()).toList();
    final typeIdx = header.indexOf('类型');
    final classIdx = header.indexOf('班级');
    final courseIdx = header.indexOf('课程名称');
    final dateIdx = header.indexOf('日期');
    final weekIdx = header.indexOf('周');
    final dayIdx = header.indexOf('星期');
    final periodIdx = header.indexOf('课节');
    final teacherIdx = header.indexOf('指导教师');
    final locationIdx = header.indexOf('地点');
    if (typeIdx == -1 || classIdx == -1 || courseIdx == -1) {
      return const CourseScheduleResult(null, {});
    }

    String cell(List<dynamic> r, int idx) =>
        (r.length > idx && r[idx]?.value != null)
            ? r[idx]!.value.toString().trim()
            : '';

    final rows = <Map<String, String>>[];
    final allCourseNames = <String>{};
    for (var i = 1; i < sheet.rows.length; i++) {
      final r = sheet.rows[i];
      final courseName = cell(r, courseIdx);
      if (courseName.isNotEmpty) allCourseNames.add(courseName);
      if (!courseName.contains('移动应用开发')) continue;
      rows.add({
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

    const dayNames = {
      1: '星期一',
      2: '星期二',
      3: '星期三',
      4: '星期四',
      5: '星期五',
      6: '星期六',
      7: '星期日'
    };
    final theory = rows.where((r) => r['type']!.contains('教务')).toList();
    final lab = rows.where((r) => r['type']!.contains('实验')).toList();
    final teacher = rows.firstWhere(
      (r) => r['teacher']!.isNotEmpty,
      orElse: () => {'teacher': '未知'},
    )['teacher']!;

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

    int? w(Map<String, String> r) => int.tryParse(r['week']!);

    final buf = StringBuffer();
    buf.writeln('# 课程课表：移动应用开发\n');
    buf.writeln('**教师**：$teacher');
    buf.writeln('**学期**：$semester');
    buf.writeln('**班级**：软件231,软件232（85人）\n');

    theory.sort((a, b) => (w(a) ?? 0).compareTo(w(b) ?? 0));
    buf.writeln('## 一、理论课\n');
    buf.writeln('| 周次 | 日期 | 星期 | 节次 | 地点 |');
    buf.writeln('|------|------|------|------|------|');
    for (final r in theory) {
      final dayNum = int.tryParse(r['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : r['day']!;
      buf.writeln(
          '| ${r['week']} | ${r['date']} | $dayName | ${r['period']} | ${r['location']} |');
    }
    buf.writeln('');

    final groups = <String, List<Map<String, String>>>{};
    for (final r in lab) {
      final groupMatch = RegExp(r'班组(\d)[：:]\d+人').firstMatch(r['class']!);
      final grpKey = groupMatch != null ? '班组${groupMatch.group(1)}' : '综合组';
      groups.putIfAbsent(grpKey, () => []).add(r);
    }

    buf.writeln('## 二、实验课\n');
    for (final entry in groups.entries) {
      entry.value.sort((a, b) => (w(a) ?? 0).compareTo(w(b) ?? 0));
      final peopleMatch =
          RegExp(r'班组\d[：:](\d+)人').firstMatch(entry.value.first['class']!);
      final people = peopleMatch?.group(1) ?? '';
      final dayNum = int.tryParse(entry.value.first['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : entry.value.first['day'] ?? '';
      final periodInfo = entry.value.first['period'] ?? '';
      buf.writeln('### ${entry.key}（$people人）— $dayName $periodInfo\n');
      buf.writeln('| 周次 | 日期 | 地点 |');
      buf.writeln('|------|------|------|');
      for (final r in entry.value) {
        buf.writeln('| ${r['week']} | ${r['date']} | ${r['location']} |');
      }
      buf.writeln('');
    }

    buf.writeln('## 三、统计\n');
    final theoryWeeks = theory.map((r) => r['week']!).toSet().length;
    final labWeeks = lab.map((r) => r['week']!).toSet().length;
    final groupCount = groups.length;
    final totalTheoryHours = theory.length * 2;
    final totalLabHours = lab.length * 2;
    buf.writeln(
        '- 理论课：$theoryWeeks周 × 2学时 = ${theoryWeeks * 2}学时（实际$totalTheoryHours课时）');
    buf.writeln(
        '- 实验课：$groupCount组 × $labWeeks周 × 2学时 = ${groupCount * labWeeks * 2}学时（实际$totalLabHours课时）');
    buf.writeln('- 总学时：${totalTheoryHours + totalLabHours}课时\n');
    buf.writeln('---');
    buf.writeln('> 数据来源：教务系统课表（Excel）');
    buf.writeln(
        '> 导入时间：${(now ?? DateTime.now()).toString().substring(0, 16)}');
    return CourseScheduleResult(buf.toString(), allCourseNames);
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
          bytes.add('='.codeUnitAt(0));
        }
      } else {
        bytes.add(input.codeUnitAt(i));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 校历（MHTML）→ Markdown。解析不出表格行返回 null。
  static String? parseCalendar(String raw, {DateTime? now}) {
    String html = extractHtmlFromMhtml(raw);
    html = decodeQuotedPrintable(html);

    final rowRegex =
        RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    final cellTextRegex =
        RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false);
    final tagStrip = RegExp(r'<[^>]*>', dotAll: true);

    final parsedRows = <List<String>>[];
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
        if (text.isNotEmpty) cells.add(text);
      }
      if (cells.isNotEmpty) parsedRows.add(cells);
    }

    if (parsedRows.isEmpty) return null;

    final startDate = DateTime(2026, 3, 2);
    final holidayMap = <String, String>{'清明': '清明节', '劳动': '劳动节', '端午': '端午节'};
    final phaseMap = <String, String>{'缓补': '缓补考试周', '期末': '期末考试周', '暑假': '暑假'};

    final weeks = <List<CalDay>>[];
    for (final cells in parsedRows) {
      if (cells.length <= 2) continue;
      final dayCells =
          cells.length >= 8 ? cells.sublist(cells.length - 7) : cells;
      if (dayCells.length != 7) continue;

      final currentWeek = <CalDay>[];
      for (var d = 0; d < 7; d++) {
        final rawCell = dayCells[d];
        final numMatch = RegExp(r'^(\d+)').firstMatch(rawCell);
        final dayNum = numMatch != null ? int.parse(numMatch.group(1)!) : 0;
        String label = '';
        for (final entry in holidayMap.entries) {
          if (rawCell.contains(entry.key)) {
            label = entry.value;
            break;
          }
        }
        if (label.isEmpty) {
          for (final entry in phaseMap.entries) {
            if (rawCell.contains(entry.key)) {
              label = entry.value;
              break;
            }
          }
        }
        currentWeek.add(CalDay(date: dayNum, label: label));
      }
      weeks.add(currentWeek);
    }

    final uniqueWeeks = <List<CalDay>>[];
    for (var i = 0; i < weeks.length; i++) {
      if (i > 0 && weeks[i][0].date == weeks[i - 1][0].date) continue;
      uniqueWeeks.add(weeks[i]);
    }

    final buf = StringBuffer();
    buf.writeln('# 校 历\n');
    buf.writeln('**学年学期：** 2025-2026学年第二学期\n');
    buf.writeln('**起始日期：** ${startDate.toString().substring(0, 10)}（周一）\n');
    buf.writeln('## 校历总览\n');
    buf.writeln('| 周次 | 起止日期 | 周一 | 周二 | 周三 | 周四 | 周五 | 周六 | 周日 | 备注 |');
    buf.writeln(
        '|------|----------|------|------|------|------|------|------|------|------|');

    for (var wk = 0; wk < uniqueWeeks.length; wk++) {
      final week = uniqueWeeks[wk];
      final monDate = startDate.add(Duration(days: wk * 7));
      final sunDate = monDate.add(const Duration(days: 6));
      final dateRange =
          '${monDate.month}/${monDate.day}-${sunDate.month}/${sunDate.day}';

      String weekLabel = '';
      final holidays = <String>[];
      for (final day in week) {
        if (day.label.isNotEmpty && !day.label.contains('周')) {
          holidays.add(day.label);
        }
        if (day.label == '缓补考试周') weekLabel = '缓补';
        if (day.label == '期末考试周') weekLabel = '期末';
        if (day.label == '暑假') weekLabel = '暑假';
      }

      final weekNum = weekLabel.isNotEmpty ? weekLabel : '${wk + 1}';
      final note = holidays.isNotEmpty
          ? holidays.toSet().join('、')
          : (weekLabel.isNotEmpty ? '（$weekLabel）' : '');

      final dayCols = <String>[];
      for (var d = 0; d < 7; d++) {
        final day = week[d];
        if (day.label == '清明节' || day.label == '劳动节' || day.label == '端午节') {
          dayCols.add('🎉${day.date}');
        } else if (day.label == '缓补考试周' ||
            day.label == '期末考试周' ||
            day.label == '暑假') {
          dayCols.add('📌${day.date}');
        } else {
          dayCols.add('${day.date}');
        }
      }

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
    buf.writeln(
        '> 导入时间：${(now ?? DateTime.now()).toString().substring(0, 16)}');
    buf.writeln('> 注：本日历为全校通用校历，具体教学安排以课表为准');
    return buf.toString();
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

/// 校历单元格：日期数字 + 可选标签（节假日/考试周）。
class CalDay {
  final int date;
  final String label;
  const CalDay({required this.date, this.label = ''});
}
