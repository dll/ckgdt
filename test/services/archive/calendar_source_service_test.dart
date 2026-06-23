import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/base_document_processor.dart';
import 'package:knowledge_graph_app/services/archive/calendar_source_service.dart';
import 'package:path/path.dart' as p;

void main() {
  const validHtml = '''
<html><body>
<div>2026-2027学年第一学期</div>
<table>
<tr><td></td><td></td><td>九月</td></tr>
<tr><td></td><td></td><td>7</td><td>8</td><td>9</td><td>10中秋</td><td>11</td><td>12</td><td>13</td></tr>
</table>
</body></html>
''';

  late String? oldRoot;
  late Directory temp;

  setUp(() {
    oldRoot = BaseDocumentProcessor.archiveDataRoot;
    temp = Directory.systemTemp.createTempSync('kg_calendar_source_');
    BaseDocumentProcessor.archiveDataRoot = temp.path;
  });

  tearDown(() {
    BaseDocumentProcessor.archiveDataRoot = oldRoot;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('parseBestStoredSource skips invalid pages and parses calendar',
      () async {
    final dir = Directory(p.join(temp.path, '期初', '模板'))
      ..createSync(recursive: true);
    final invalid = File(p.join(dir.path, '06-login.html'))
      ..writeAsStringSync('<html><body>统一身份认证</body></html>');
    final valid = File(p.join(dir.path, '06-校历.html'))
      ..writeAsStringSync(validHtml);
    invalid.setLastModifiedSync(DateTime(2026, 6, 15));
    valid.setLastModifiedSync(DateTime(2026, 6, 14));

    final result = await CalendarSourceService.parseBestStoredSource(
      periodKey: 'beginning',
      includeDownloads: false,
      now: DateTime(2026, 6, 14, 9, 30),
    );

    expect(result, isNotNull);
    expect(result!.sourcePath, valid.path);
    expect(result.markdown, contains('2026-2027学年第一学期'));
    expect(result.markdown, contains('中秋节'));
  });

  test('saveFetchedHtml stores authorized calendar page outside template',
      () async {
    final file = await CalendarSourceService.saveFetchedHtml(
      periodKey: 'beginning',
      html: validHtml,
      now: DateTime(2026, 6, 14, 10, 11, 12),
    );

    expect(
      file.path,
      endsWith(p.join(
        '期初',
        '源文件',
        '06-schcalendar.fetched.20260614-101112.html',
      )),
    );
    expect(file.readAsStringSync(), validHtml);
  });

  test('preferredCalendarUrl reuses schcalendar URL from saved MHTML',
      () async {
    final dir = Directory(p.join(temp.path, '期初', '模板'))
      ..createSync(recursive: true);
    File(p.join(dir.path, '06-校历.mhtml')).writeAsStringSync('''
Snapshot-Content-Location: https://webvpn.chzu.edu.cn/example/schcalendar
Content-Type: text/html

$validHtml
''');

    final url = await CalendarSourceService.preferredCalendarUrl(
      periodKey: 'beginning',
    );

    expect(url, 'https://webvpn.chzu.edu.cn/example/schcalendar');
  });
}
