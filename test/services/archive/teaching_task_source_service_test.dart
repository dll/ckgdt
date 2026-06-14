import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/base_document_processor.dart';
import 'package:knowledge_graph_app/services/archive/teaching_task_source_service.dart';
import 'package:path/path.dart' as p;

void main() {
  const validHtml = '''
<html><body>
<p>经学校批准聘请刘东良老师担任2026-2027学年第1学期以下教学任务：</p>
<table>
<tr><th>课程名称</th><th>课程类别</th><th>总学时</th><th>讲授</th><th>实验</th><th>实践</th><th>课外自主学时</th><th>教学班级</th><th>计划人数</th><th>备注</th></tr>
<tr><td>移动应用开发</td><td>专业课</td><td>64</td><td>32</td><td>32</td><td>0</td><td>0</td><td>软件231</td><td>43</td><td></td></tr>
</table>
<p>2026年06月13日</p>
</body></html>
''';

  late String? oldRoot;
  late Directory temp;

  setUp(() {
    oldRoot = BaseDocumentProcessor.archiveDataRoot;
    temp = Directory.systemTemp.createTempSync('kg_archive_source_');
    BaseDocumentProcessor.archiveDataRoot = temp.path;
  });

  tearDown(() {
    BaseDocumentProcessor.archiveDataRoot = oldRoot;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test(
      'parseBestStoredSource skips invalid cached pages and parses lesson book',
      () async {
    final dir = Directory(p.join(temp.path, '期初', '模板'))
      ..createSync(recursive: true);
    final invalid = File(p.join(dir.path, '01-login.html'))
      ..writeAsStringSync('<html><body>统一身份认证</body></html>');
    final valid = File(
      p.join(dir.path, '01-courseTableForTeacher!printLessonBook.mhtml'),
    )..writeAsStringSync(validHtml);
    invalid.setLastModifiedSync(DateTime(2026, 6, 15));
    valid.setLastModifiedSync(DateTime(2026, 6, 14));

    final result = await TeachingTaskSourceService.parseBestStoredSource(
      periodKey: 'beginning',
      includeDownloads: false,
      now: DateTime(2026, 6, 14, 9, 30),
    );

    expect(result, isNotNull);
    expect(result!.sourcePath, valid.path);
    expect(result.markdown, contains('移动应用开发'));
    expect(result.markdown, contains('签发日期：2026年06月13日'));
  });

  test('saveFetchedHtml stores authorized page outside template directory',
      () async {
    final file = await TeachingTaskSourceService.saveFetchedHtml(
      periodKey: 'beginning',
      html: validHtml,
      now: DateTime(2026, 6, 14, 10, 11, 12),
    );

    expect(
      file.path,
      endsWith(p.join(
        '期初',
        '源文件',
        '01-courseTableForTeacher!printLessonBook.fetched.20260614-101112.html',
      )),
    );
    expect(file.readAsStringSync(), validHtml);
  });

  test(
      'parseBestStoredSource also reads authorized pages from source directory',
      () async {
    final dir = Directory(p.join(temp.path, '期初', '源文件'))
      ..createSync(recursive: true);
    final fetched = File(
      p.join(
        dir.path,
        '01-courseTableForTeacher!printLessonBook.fetched.20260614-101112.html',
      ),
    )..writeAsStringSync(validHtml);

    final result = await TeachingTaskSourceService.parseBestStoredSource(
      periodKey: 'beginning',
      includeDownloads: false,
    );

    expect(result, isNotNull);
    expect(result!.sourcePath, fetched.path);
    expect(result.markdown, contains('移动应用开发'));
  });

  test('print lesson book url is the original academic affairs path', () {
    expect(
      TeachingTaskSourceService.printLessonBookUrl,
      'https://jwgl.chzu.edu.cn/eams/courseTableForTeacher!printLessonBook.action?',
    );
  });
}
