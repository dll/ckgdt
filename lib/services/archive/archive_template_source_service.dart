import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/constants/archive_periods.dart';
import 'base_document_processor.dart';
import 'importers/archive_importers.dart';

/// 期初模板资料识别服务。
///
/// `data/归档/<期>/模板` 中的编号只作为人工排序参考，不参与匹配。
/// 不同课程可使用不同编号或文件名；系统按资料类型关键词、排除词和扩展名
/// 自动识别最合适的源文件/目录。
class ArchiveTemplateSourceService {
  ArchiveTemplateSourceService._();

  static bool supportsDocument(String documentType) =>
      _specs.containsKey(documentType);

  static Future<ArchiveTemplateDocument?> parseBestSource({
    required String periodKey,
    required String documentType,
    required String label,
    DateTime? now,
  }) async {
    final match = bestMatch(periodKey: periodKey, documentType: documentType);
    if (match == null) return null;
    final content = await _parse(match, label: label, now: now);
    if (content == null || content.trim().isEmpty) return null;
    return ArchiveTemplateDocument(
      content: content.trim(),
      sourcePath: match.entity.path,
      sourceName: p.basename(match.entity.path),
    );
  }

  static ArchiveTemplateMatch? bestMatch({
    required String periodKey,
    required String documentType,
  }) {
    final spec = _specs[documentType];
    if (spec == null) return null;
    final dir = _templateDirectory(periodKey);
    if (dir == null || !dir.existsSync()) return null;

    final matches = <ArchiveTemplateMatch>[];
    for (final entity in dir.listSync(recursive: false)) {
      final match = _score(entity, spec);
      if (match != null) matches.add(match);
    }
    matches.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return a.name.compareTo(b.name);
    });
    return matches.isEmpty ? null : matches.first;
  }

  static ArchiveTemplateMatch? _score(
    FileSystemEntity entity,
    _TemplateSpec spec,
  ) {
    final isDir = entity is Directory;
    if (isDir && !spec.allowDirectory) return null;
    if (entity is! File && entity is! Directory) return null;

    final name = p.basename(entity.path);
    final normalized = _normalize(name);
    for (final token in spec.excludeTokens) {
      if (normalized.contains(_normalize(token))) return null;
    }

    final ext = isDir ? '<dir>' : p.extension(name).toLowerCase();
    final extPriority = spec.extensionPriority(ext);
    if (extPriority == null) return null;

    var tokenHits = 0;
    for (final token in spec.tokens) {
      if (normalized.contains(_normalize(token))) tokenHits++;
    }
    if (tokenHits == 0) return null;

    return ArchiveTemplateMatch(
      entity: entity,
      score: tokenHits * 100 + extPriority,
      name: name,
      documentType: spec.documentType,
    );
  }

  static Future<String?> _parse(
    ArchiveTemplateMatch match, {
    required String label,
    DateTime? now,
  }) async {
    final entity = match.entity;
    if (entity is Directory) return _directoryContent(entity, label: label);
    if (entity is! File) return null;

    final ext = p.extension(entity.path).toLowerCase();
    final bytes = await entity.readAsBytes();
    String readText() => entity.readAsStringSync();

    switch (match.documentType) {
      case 'teaching_task':
        if (!_isTextLike(ext)) return null;
        return ArchiveImporters.parseTeachingTask(readText(), now: now);
      case 'calendar':
        if (_isTextLike(ext)) {
          return ArchiveImporters.parseCalendar(readText(), now: now) ??
              _fileContent(entity, label: label);
        }
        return _fileContent(entity, label: label);
      case 'course_schedule':
        if (ext == '.xlsx' || ext == '.xls') {
          final result = ArchiveImporters.parseCourseSchedule(bytes, now: now);
          return result.markdown ?? _fileContent(entity, label: label);
        }
        return _readPlainFile(entity, label: label);
      case 'roll_call':
        if (!_isTextLike(ext)) return null;
        return ArchiveImporters.parseRollCall(readText(), now: now) ??
            _fileContent(entity, label: label);
      case 'survey':
        if (!_isTextLike(ext)) return null;
        return ArchiveImporters.parseSurvey(readText(), now: now) ??
            _fileContent(entity, label: label);
      default:
        return _readPlainFile(entity, label: label);
    }
  }

  static Future<String?> _readPlainFile(File file,
      {required String label}) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.md' || ext == '.txt' || ext == '.html' || ext == '.htm') {
      return await file.readAsString();
    }
    if (ext == '.mhtml' || ext == '.mht') {
      return ArchiveImporters.decodeQuotedPrintable(
        ArchiveImporters.extractHtmlFromMhtml(await file.readAsString()),
      );
    }
    if (ext == '.docx') {
      String? text;
      try {
        text = ArchiveImporters.extractDocxText(await file.readAsBytes());
      } on Exception {
        return null;
      } on Error {
        return null;
      }
      if (text == null || text.trim().isEmpty) return null;
      return '# $label\n\n$text';
    }
    return _fileContent(file, label: label);
  }

  static String _directoryContent(Directory dir, {required String label}) {
    final children = dir
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => f.lengthSync() > 0)
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    final buf = StringBuffer()
      ..writeln('# $label')
      ..writeln()
      ..writeln('**资料来源**：期初模板目录')
      ..writeln('**原始目录**：${dir.path}')
      ..writeln()
      ..writeln('## 文件清单')
      ..writeln()
      ..writeln('| 序号 | 文件名 | 大小 |')
      ..writeln('|------|--------|------|');
    for (var i = 0; i < children.length; i++) {
      final file = children[i];
      buf.writeln(
        '| ${(i + 1).toString().padLeft(2, '0')} | ${p.basename(file.path)} | ${file.lengthSync()} 字节 |',
      );
    }
    if (children.isEmpty) {
      buf.writeln('| 01 | （目录暂为空） | 0 字节 |');
    }

    final markdownFiles = children
        .where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return ext == '.md' || ext == '.txt';
        })
        .take(20)
        .toList();
    for (final file in markdownFiles) {
      buf
        ..writeln()
        ..writeln('---')
        ..writeln()
        ..writeln('## ${p.basenameWithoutExtension(file.path)}')
        ..writeln()
        ..writeln(file.readAsStringSync().trim());
    }
    return buf.toString();
  }

  static String _fileContent(File file, {required String label}) {
    final ext = p.extension(file.path).replaceFirst('.', '').toUpperCase();
    return '''
# $label

**资料来源**：期初模板目录
**原始文件**：${file.path}
**文件类型**：$ext 原件
**文件大小**：${file.lengthSync()} 字节

> 此资料以原始文件为准。预览、打印和归档会优先使用原始文件；如需编辑，请修改模板目录中的对应资料后重新生成。
''';
  }

  static Directory? _templateDirectory(String periodKey) {
    final root = BaseDocumentProcessor.archiveDataRoot;
    if (root == null) return null;
    return Directory(p.join(root, periodLabel(periodKey), '模板'));
  }

  static bool _isTextLike(String ext) =>
      const {'.mhtml', '.mht', '.html', '.htm'}.contains(ext);

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'^\d+\s*[-_＋+、.．]?\s*'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('《', '')
      .replaceAll('》', '');

  static const Map<String, _TemplateSpec> _specs = {
    'teaching_task': _TemplateSpec(
      documentType: 'teaching_task',
      tokens: [
        'courseTableForTeacher!printLessonBook',
        '教学任务单',
        '教学任务书',
        '教学任务',
      ],
      extensions: ['.mhtml', '.mht', '.html', '.htm'],
    ),
    'syllabus': _TemplateSpec(
      documentType: 'syllabus',
      tokens: ['教学大纲', '大纲'],
      excludeTokens: ['合理性', '评价', '审核'],
      extensions: ['.md', '.txt', '.html', '.htm', '.docx'],
    ),
    'syllabus_evaluation': _TemplateSpec(
      documentType: 'syllabus_evaluation',
      tokens: ['大纲合理性评价', '合理性评价', '评价表'],
      excludeTokens: ['审核'],
      extensions: ['.docx', '.md', '.txt'],
    ),
    'syllabus_review': _TemplateSpec(
      documentType: 'syllabus_review',
      tokens: ['大纲合理性审核', '合理性审核', '审核表'],
      excludeTokens: ['评价'],
      extensions: ['.docx', '.md', '.txt'],
    ),
    'calendar': _TemplateSpec(
      documentType: 'calendar',
      tokens: ['教学日历', '校历'],
      extensions: ['.mhtml', '.mht', '.html', '.htm', '.xlsx', '.xls'],
    ),
    'course_schedule': _TemplateSpec(
      documentType: 'course_schedule',
      tokens: ['课程课表', '教师课表', '课表'],
      excludeTokens: ['进度', '教学任务', '问卷'],
      extensions: ['.xlsx', '.xls', '.md', '.txt'],
    ),
    'teaching_schedule': _TemplateSpec(
      documentType: 'teaching_schedule',
      tokens: ['教学进度表', '进度表', '教学进度'],
      extensions: ['.docx', '.md', '.txt', '.html', '.htm'],
    ),
    'lesson_plan': _TemplateSpec(
      documentType: 'lesson_plan',
      tokens: ['教学教案', '理论教案', '教案'],
      extensions: ['.md', '.txt', '.docx', '<dir>'],
      allowDirectory: true,
    ),
    'courseware': _TemplateSpec(
      documentType: 'courseware',
      tokens: ['教学课件', '课件'],
      extensions: ['.pptx', '.ppt', '.pdf', '.md', '.txt', '<dir>'],
      allowDirectory: true,
    ),
    'roll_call': _TemplateSpec(
      documentType: 'roll_call',
      tokens: ['学生点名册', '点名册', '考勤'],
      extensions: ['.mhtml', '.mht', '.html', '.htm'],
    ),
    'teacher_guide': _TemplateSpec(
      documentType: 'teacher_guide',
      tokens: ['教师教学指导手册', '教师指导手册', '教师教学指导'],
      extensions: ['.md', '.txt', '.docx'],
    ),
    'student_guide': _TemplateSpec(
      documentType: 'student_guide',
      tokens: ['学生学习指导手册', '学生指导手册', '学习指导手册'],
      extensions: ['.md', '.txt', '.docx'],
    ),
    'assessment_plan': _TemplateSpec(
      documentType: 'assessment_plan',
      tokens: ['综合考核方案', '考核方案', '考查大作业方案', '大作业方案', '考查'],
      extensions: ['.pdf', '.docx', '.md', '.txt'],
    ),
    'survey': _TemplateSpec(
      documentType: 'survey',
      tokens: ['问卷', 'courseTableForTeacher!printLessonBook', '教学任务书'],
      extensions: ['.mhtml', '.mht', '.html', '.htm'],
    ),
  };
}

class ArchiveTemplateDocument {
  final String content;
  final String sourcePath;
  final String sourceName;

  const ArchiveTemplateDocument({
    required this.content,
    required this.sourcePath,
    required this.sourceName,
  });
}

class ArchiveTemplateMatch {
  final FileSystemEntity entity;
  final int score;
  final String name;
  final String documentType;

  const ArchiveTemplateMatch({
    required this.entity,
    required this.score,
    required this.name,
    required this.documentType,
  });
}

class _TemplateSpec {
  final String documentType;
  final List<String> tokens;
  final List<String> excludeTokens;
  final List<String> extensions;
  final bool allowDirectory;

  const _TemplateSpec({
    required this.documentType,
    required this.tokens,
    required this.extensions,
    this.excludeTokens = const [],
    this.allowDirectory = false,
  });

  int? extensionPriority(String ext) {
    final index = extensions.indexOf(ext);
    if (index == -1) return null;
    return 50 - index;
  }
}
