import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/constants/archive_periods.dart';
import 'base_document_processor.dart';
import 'importers/archive_importers.dart';

/// 教学任务单真实来源。
///
/// 主流程不是让教师手动重录任务单，而是基于教务系统打印页的 HTML/MHTML
/// 结构化生成学校版式归档件。这里集中管理来源 URL、本地缓存发现和抓取结果保存。
///
/// `data/归档/<期>/模板` 是学校原始样例/版式依据，只读扫描，不做删除或覆盖。
/// 网页授权抓取的新页面保存到 `data/归档/<期>/源文件`，避免污染模板目录。
class TeachingTaskSourceService {
  TeachingTaskSourceService._();

  static const printLessonBookUrl =
      'https://jwgl.chzu.edu.cn/eams/courseTableForTeacher!printLessonBook.action?';

  static const _sourceNameToken = 'courseTableForTeacher!printLessonBook';
  static const _sourcePrefix = '01-';
  static const _sourceExtensions = ['.mhtml', '.mht', '.html', '.htm'];

  static Future<TeachingTaskParseResult?> parseBestStoredSource({
    required String periodKey,
    DateTime? now,
    bool includeDownloads = true,
  }) async {
    for (final file in storedSourceCandidates(
      periodKey: periodKey,
      includeDownloads: includeDownloads,
    )) {
      if (!await file.exists()) continue;
      final raw = await file.readAsString();
      final parsed = ArchiveImporters.parseTeachingTask(raw, now: now);
      if (parsed == null) continue;
      return TeachingTaskParseResult(
        markdown: parsed,
        sourcePath: file.path,
        sourceLabel: '已保存教务系统源文件',
      );
    }
    return null;
  }

  static List<File> storedSourceCandidates({
    required String periodKey,
    bool includeDownloads = true,
  }) {
    final files = <File>[];
    final seen = <String>{};

    void addIfCandidate(File file) {
      final name = p.basename(file.path).toLowerCase();
      final ext = p.extension(name);
      if (!_sourceExtensions.contains(ext)) return;
      final isLessonBook = name.contains(_sourceNameToken.toLowerCase());
      final isNumberedSource = name.startsWith(_sourcePrefix);
      if (!isLessonBook && !isNumberedSource) return;
      final fullPath = p.normalize(file.absolute.path);
      if (seen.add(fullPath)) files.add(file);
    }

    final root = BaseDocumentProcessor.archiveDataRoot;
    if (root != null) {
      for (final dirName in const ['模板', '源文件']) {
        final dir = Directory(p.join(root, periodLabel(periodKey), dirName));
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync()) {
          if (entity is File) addIfCandidate(entity);
        }
      }
    }

    final downloads = includeDownloads ? _downloadsDirectory() : null;
    if (downloads != null && downloads.existsSync()) {
      for (final entity in downloads.listSync()) {
        if (entity is File) addIfCandidate(entity);
      }
    }

    files.sort((a, b) {
      final bTime = b.lastModifiedSync();
      final aTime = a.lastModifiedSync();
      final timeOrder = bTime.compareTo(aTime);
      if (timeOrder != 0) return timeOrder;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    return files;
  }

  static Future<File> saveFetchedHtml({
    required String periodKey,
    required String html,
    DateTime? now,
  }) async {
    final dir = _sourceDirectory(periodKey);
    await dir.create(recursive: true);
    final stamp = _timestamp(now ?? DateTime.now());
    final file = File(
      p.join(dir.path, '01-$_sourceNameToken.fetched.$stamp.html'),
    );
    await file.writeAsString(html);
    return file;
  }

  static Directory _sourceDirectory(String periodKey) {
    final root = BaseDocumentProcessor.archiveDataRoot;
    if (root != null) {
      return Directory(p.join(root, periodLabel(periodKey), '源文件'));
    }
    return Directory(p.join('data', '归档', periodLabel(periodKey), '源文件'));
  }

  static Directory? _downloadsDirectory() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return Directory(p.join(userProfile, 'Downloads'));
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return Directory(p.join(home, 'Downloads'));
    }
    return null;
  }

  static String _timestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}

class TeachingTaskParseResult {
  final String markdown;
  final String sourcePath;
  final String sourceLabel;

  const TeachingTaskParseResult({
    required this.markdown,
    required this.sourcePath,
    required this.sourceLabel,
  });
}
