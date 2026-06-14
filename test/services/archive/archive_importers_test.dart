import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/importers/archive_importers.dart';

void main() {
  final fixedNow = DateTime(2026, 5, 30, 10, 0);

  group('ArchiveImporters.decodeQuotedPrintable', () {
    test('解码 =XX 十六进制字节为 UTF-8', () {
      // "课" = E8 AF BE in UTF-8
      expect(ArchiveImporters.decodeQuotedPrintable('=E8=AF=BE'), '课');
    });

    test('软换行 =\\r\\n 被去除', () {
      expect(ArchiveImporters.decodeQuotedPrintable('AB=\r\nCD'), 'ABCD');
    });

    test('软换行 =\\n 被去除', () {
      expect(ArchiveImporters.decodeQuotedPrintable('AB=\nCD'), 'ABCD');
    });

    test('非法 =X 序列保留字面 =', () {
      expect(ArchiveImporters.decodeQuotedPrintable('a=zz'), 'a=zz');
    });

    test('纯 ASCII 原样返回', () {
      expect(
          ArchiveImporters.decodeQuotedPrintable('hello world'), 'hello world');
    });
  });

  group('ArchiveImporters.extractHtmlFromMhtml', () {
    test('从 multipart 提取 text/html 段', () {
      const raw = '''MIME-Version: 1.0
Content-Type: multipart/related; boundary="----=_BND"

------=_BND
Content-Type: text/html
Content-Location: http://x/

<html><body>HELLO</body></html>
------=_BND--''';
      final html = ArchiveImporters.extractHtmlFromMhtml(raw);
      expect(html, contains('<html><body>HELLO</body></html>'));
    });

    test('无 boundary 时原样返回', () {
      const raw = '<p>plain</p>';
      expect(ArchiveImporters.extractHtmlFromMhtml(raw), raw);
    });
  });

  group('ArchiveImporters.parseTeachingTask', () {
    test('命中课程行 → 生成任务书 Markdown（横排 10 列）', () {
      const html = '''
经学校批准聘请张三老师担任2025-2026学年第二学期以下教学任务
<table>
<tr><td>课程名称</td><td>课程类别</td><td>总学时</td><td>讲授</td><td>实验</td><td>实践</td><td>课外自主</td><td>教学班级</td><td>计划人数</td><td>备注</td></tr>
<tr><td>移动应用开发</td><td>必修</td><td>48</td><td>32</td><td>16</td><td>0</td><td>0</td><td>软件231</td><td>45</td><td>无</td></tr>
</table>
2026年06月13日''';
      final md = ArchiveImporters.parseTeachingTask(html, now: fixedNow);
      expect(md, isNotNull);
      expect(md, contains('# 教 学 任 务 书'));
      expect(md, contains('张三'));
      expect(md, contains('移动应用开发'));
      expect(md, contains('签发日期：2026年06月13日'));
      expect(md, contains('课程行数：1'));
      expect(md, contains('2026-05-30 10:00'));
      // 列序：实验=16 在「实验」列、实践=0 在「实践」列
      expect(md,
          contains('| 移动应用开发 | 必修 | 48 | 32 | 16 | 0 | 0 | 软件231 | 45 | 无 |'));
      // 表头不应被当作课程行
      expect('| 课程名称 | 课程类别 |'.allMatches(md!).length, 1);
    });

    test('解析全部课程行（不再只留"移动应用开发"）', () {
      const html = '''
经学校批准聘请刘东良老师担任2026-2027学年第1学期以下教学任务
<table>
<tr><th>课程名称</th><th>课程类别</th><th>总学时</th><th>讲授</th><th>实验</th><th>实践</th><th>课外自主</th><th>教学班级</th><th>计划人数</th><th>备注</th></tr>
<tr><td>办公软件高级应用</td><td>专业选修课</td><td>32</td><td>0</td><td>32</td><td>0</td><td>0</td><td>智能1班</td><td>50</td><td></td></tr>
<tr><td>软件工程基础</td><td>专业基础课</td><td>48</td><td>32</td><td>16</td><td>0</td><td>0</td><td>软件231</td><td>66</td><td></td></tr>
</table>''';
      final md = ArchiveImporters.parseTeachingTask(html, now: fixedNow);
      expect(md, isNotNull);
      expect(md, contains('刘东良'));
      expect(md, contains('办公软件高级应用'));
      expect(md, contains('软件工程基础'));
    });

    test('教师手改 HTML 模板（<input value>）也能解析', () {
      const html = '''
<p>经学校批准聘请<input type="text" value="王老师">老师担任<input type="text" value="2026-2027学年第1学期">学期以下教学任务：</p>
<table>
<tr><th>课程名称</th><th>课程类别</th><th>总学时</th><th>讲授</th><th>实验</th><th>实践</th><th>课外自主</th><th>教学班级</th><th>计划人数</th><th>备注</th></tr>
<tr><td>移动应用开发</td><td>考试</td><td>64</td><td>32</td><td>16</td><td>8</td><td>8</td><td>计科22</td><td>40</td><td></td></tr>
</table>''';
      final md = ArchiveImporters.parseTeachingTask(html, now: fixedNow);
      expect(md, isNotNull);
      expect(md, contains('王老师'));
      expect(
          md, contains('| 移动应用开发 | 考试 | 64 | 32 | 16 | 8 | 8 | 计科22 | 40 |'));
    });

    test('无任何课程行 → 返回 null', () {
      const html = '<p>经学校批准聘请李四老师担任本学期以下教学任务</p><table></table>';
      expect(ArchiveImporters.parseTeachingTask(html), isNull);
    });

    test('真实期初教学任务书模板可解析出多行课程', () {
      final file =
          File('data/归档/期初/模板/01-courseTableForTeacher!printLessonBook.mhtml');
      if (!file.existsSync()) return;
      final md = ArchiveImporters.parseTeachingTask(file.readAsStringSync(),
          now: fixedNow);
      expect(md, isNotNull);
      expect(md, contains('刘东良'));
      expect(md, contains('移动应用开发'));
      expect(md, contains('签发日期：'));
      expect(
          RegExp(r'^\| .* \| .* \| .* \|', multiLine: true)
              .allMatches(md!)
              .length,
          greaterThanOrEqualTo(4));
    });
  });

  group('ArchiveImporters.parseCalendar', () {
    test('空/无表格 → 返回 null', () {
      expect(ArchiveImporters.parseCalendar('no tables here'), isNull);
    });

    test('含 7 列日期行 → 生成校历 Markdown', () {
      // 一行 7 个日期单元格（周一到周日）
      final cells = List.generate(7, (i) => '<td>${i + 2}</td>').join();
      final html = 'boundary 缺失走原文\n<table><tr>$cells</tr></table>';
      final md = ArchiveImporters.parseCalendar(html, now: fixedNow);
      expect(md, isNotNull);
      expect(md, contains('# 校 历'));
      expect(md, contains('节假日安排'));
    });
  });

  group('ArchiveImporters.parseRollCall', () {
    test('非移动应用开发 → 返回 null', () {
      const raw = '课程名称：高等数学 授课教师：王五';
      expect(ArchiveImporters.parseRollCall(raw), isNull);
    });
  });

  group('ArchiveImporters.parseCourseSchedule (CourseScheduleResult)', () {
    test('空字节 → markdown null + 空 names（不抛）', () {
      final r = ArchiveImporters.parseCourseSchedule(const []);
      expect(r.markdown, isNull);
      expect(r.allCourseNames, isEmpty);
    });
  });

  group('CalDay / CourseScheduleResult 值对象', () {
    test('CalDay 默认 label 为空', () {
      const d = CalDay(date: 5);
      expect(d.date, 5);
      expect(d.label, '');
    });

    test('CourseScheduleResult 持有 markdown + names', () {
      const r = CourseScheduleResult('md', {'A', 'B'});
      expect(r.markdown, 'md');
      expect(r.allCourseNames, {'A', 'B'});
    });
  });
}
