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

  static Future<ArchiveTemplateDocument?> parseFile({
    required File file,
    required String documentType,
    required String label,
    DateTime? now,
  }) async {
    final spec = _specs[documentType];
    if (spec == null || !await file.exists()) return null;
    final ext = p.extension(file.path).toLowerCase();
    if (spec.extensionPriority(ext) == null) return null;
    final match = ArchiveTemplateMatch(
      entity: file,
      score: 0,
      name: p.basename(file.path),
      documentType: spec.documentType,
    );
    final content = await _parse(match, label: label, now: now);
    if (content == null || content.trim().isEmpty) return null;
    return ArchiveTemplateDocument(
      content: content.trim(),
      sourcePath: file.path,
      sourceName: p.basename(file.path),
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
      case 'midterm_progress_check':
        return _midtermProgressCheckContent(entity, label: label, now: now);
      case 'midterm_homework_review':
        return _midtermHomeworkReviewContent(entity, label: label, now: now);
      case 'midterm_exam':
      case 'midterm_check':
      case 'midterm_analysis':
        return _midtermExamContent(entity, label: label, now: now);
      default:
        return _readPlainFile(entity, label: label);
    }
  }

  static Future<String?> _midtermProgressCheckContent(
    File file, {
    required String label,
    DateTime? now,
  }) async {
    final sourceText = await _readPlainFile(file, label: label);
    if (sourceText == null || sourceText.trim().isEmpty) return null;
    final source = _trimSource(sourceText);
    final normalized = _normalize(sourceText);
    final hasWeeks = _containsAny(normalized, ['周次', '第一周', '第1周']);
    final hasHours = _containsAny(normalized, ['学时', '讲课', '实验课']);
    final hasCourse = _containsAny(normalized, ['课程名称', '授课教师', '班级']);
    final conclusion = hasWeeks && hasHours
        ? '已识别进度表要素，需由教师结合实际授课记录确认是否一致'
        : '源文件要素不完整，需补充周次、学时和实际执行情况后再归档';
    return '''
# $label

**资料来源**：期中模板目录
**原始文件**：${file.path}
**生成日期**：${_formatDate(now)}

## 01 检查范围

| 项目 | 内容 |
|------|------|
| 检查对象 | 期中前课程教学进度执行情况 |
| 核对依据 | 期初教学进度表、实际授课记录、实验/实践安排 |
| 核对重点 | 周次覆盖、章节内容、理论/实验学时、调课补课说明 |
| 初步结论 | $conclusion |

## 02 自动核对摘要

| 核对项 | 自动识别 | 检查结论 | 处理要求 |
|--------|----------|----------|----------|
| 周次覆盖 | ${hasWeeks ? '已识别周次信息' : '未识别明确周次'} | ${hasWeeks ? '基本具备核对条件' : '需补充'} | 核对期中前已到教学周 |
| 学时执行 | ${hasHours ? '已识别学时或讲课/实验课信息' : '未识别学时信息'} | ${hasHours ? '基本具备核对条件' : '需补充'} | 理论、实验/实践学时分别确认 |
| 课程信息 | ${hasCourse ? '已识别课程/教师/班级信息' : '未识别完整课程信息'} | ${hasCourse ? '基本具备归档条件' : '需补充'} | 与教学任务书、课表保持一致 |
| 偏差说明 | 需教师填写实际执行偏差 | 待确认 | 若有调课、补课、滞后或超前，必须说明原因和整改安排 |

## 03 课程进度执行检查表

| 序号 | 检查项目 | 检查要求 | 执行情况 | 结论 |
|------|----------|----------|----------|------|
| 1 | 教学周次 | 期中前教学周次应按计划完成 | 依据原始资料和授课记录核对 | 教师确认 |
| 2 | 教学内容 | 已授章节、知识点、实验项目应与进度表一致 | 依据原始资料逐项核对 | 教师确认 |
| 3 | 学时安排 | 理论、实验、实践学时应与期初计划一致 | 依据课表和进度记录核对 | 教师确认 |
| 4 | 教学调整 | 调课、停课、补课、进度偏差应有记录 | 如有偏差需写明原因和补救措施 | 教师确认 |

## 04 审核结论

本材料用于期中教学检查。系统已完成源文件识别和要素初筛，最终结论需由任课教师根据实际授课记录、课堂考勤、实验安排和补课记录确认后签字归档。

## 附：原始进度资料

$source
''';
  }

  static Future<String?> _midtermHomeworkReviewContent(
    File file, {
    required String label,
    DateTime? now,
  }) async {
    final sourceText = await _readPlainFile(file, label: label);
    if (sourceText == null || sourceText.trim().isEmpty) return null;
    final source = _trimSource(sourceText);
    final normalized = _normalize(sourceText);
    final hasHomeworkEvidence = _containsAny(
      normalized,
      ['作业', '批阅', '评分', '反馈', '提交', '测验', '实验报告'],
    );
    final looksLikeProgress = _containsAny(normalized, ['教学进度表']) &&
        _containsAny(normalized, ['周次', '教学内容摘要']);
    final sourceConclusion = hasHomeworkEvidence && !looksLikeProgress
        ? '已识别作业或批阅统计要素'
        : looksLikeProgress
            ? '源文件疑似为教学进度表，不是作业与批阅次数统计，请更换源文件或补录统计数据'
            : '未识别明确作业/批阅统计要素，需补充后再归档';
    return '''
# $label

**资料来源**：期中模板目录
**原始文件**：${file.path}
**生成日期**：${_formatDate(now)}

## 01 统计范围

| 项目 | 内容 |
|------|------|
| 统计对象 | 期中前布置的作业、测验、实验报告、项目阶段材料 |
| 统计口径 | 应提交人数、实交人数、应批阅份数、已批阅份数、反馈方式 |
| 审核重点 | 作业次数是否达标、批阅是否及时、反馈是否覆盖主要问题 |
| 源文件初判 | $sourceConclusion |

## 02 数据完整性检查

| 核对项 | 自动识别 | 检查结论 | 处理要求 |
|--------|----------|----------|----------|
| 作业记录 | ${hasHomeworkEvidence ? '已识别作业/批阅相关文本' : '未识别作业/批阅文本'} | ${hasHomeworkEvidence ? '可继续核对' : '需补充'} | 列明每次作业或阶段测验 |
| 源文件类型 | ${looksLikeProgress ? '疑似教学进度表' : '未发现明显错配'} | ${looksLikeProgress ? '源文件错配风险' : '可继续核对'} | 错配时不得直接作为作业统计归档 |
| 批阅证据 | 需包含已批阅份数、成绩或反馈记录 | 待确认 | 支持截图、平台记录或汇总表 |
| 改进说明 | 未批、迟批、反馈不足需说明原因 | 待确认 | 补充后续批阅计划 |

## 03 作业与批阅次数统计表

| 序号 | 作业/测验/实验名称 | 布置周次 | 应提交人数 | 实交人数 | 应批阅份数 | 已批阅份数 | 反馈方式 | 备注 |
|------|--------------------|----------|------------|----------|------------|------------|----------|------|
| 01 | 期中前作业或阶段任务 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 分数/评语/课堂反馈 | 教师确认 |
| 02 | 期中前测验或实验报告 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 分数/评语/平台反馈 | 教师确认 |

## 04 审核结论

本材料必须能证明期中前作业布置和批阅反馈情况。若源文件初判提示错配，应先替换为真实作业批阅统计表，或在本表中补录统计数据后再审核、打印和归档。

## 附：原始统计资料

$source
''';
  }

  static Future<String?> _midtermExamContent(
    File file, {
    required String label,
    DateTime? now,
  }) async {
    final sourceText = await _readPlainFile(file, label: label);
    if (sourceText == null || sourceText.trim().isEmpty) return null;
    final source = _trimSource(sourceText);
    final normalized = _normalize(sourceText);
    final hasExamEvidence = _containsAny(
      normalized,
      ['试卷', '答案', '评分标准', '成绩', '考核', '测验', '题目'],
    );
    final hasCourseObjectives =
        _containsAny(normalized, ['课程目标', '目标1', '目标 1']);
    final conclusion = hasExamEvidence
        ? '已识别期中考试或阶段考核要素'
        : '未识别完整试卷、答案、评分标准或成绩记录；如课程无期中考试，应按阶段考核材料归档并写明替代说明';
    return '''
# $label

**资料来源**：期中模板目录
**原始文件**：${file.path}
**生成日期**：${_formatDate(now)}

## 01 材料范围

| 项目 | 内容 |
|------|------|
| 适用场景 | 期中考试、阶段测验、项目阶段检查、作业/实验阶段考核 |
| 必备材料 | 题目或任务书、参考答案或评分标准、成绩/结果记录、质量分析 |
| 目标对应 | 应覆盖期中前核心知识点和课程目标 |
| 源文件初判 | $conclusion |

## 02 自动核对摘要

| 核对项 | 自动识别 | 检查结论 | 处理要求 |
|--------|----------|----------|----------|
| 考核材料 | ${hasExamEvidence ? '已识别考试/考核相关文本' : '未识别完整考试材料'} | ${hasExamEvidence ? '可继续核对' : '需补充或说明替代方式'} | 补齐题目、答案、评分标准和成绩记录 |
| 目标覆盖 | ${hasCourseObjectives ? '已识别课程目标信息' : '未识别课程目标映射'} | ${hasCourseObjectives ? '可继续核对' : '需补充'} | 标明考核内容对应课程目标 |
| 质量分析 | 需说明学生掌握情况和薄弱环节 | 待确认 | 形成后续教学改进措施 |
| 替代说明 | 无正式期中考试时必须说明阶段考核方式 | 待确认 | 写明测验、项目检查或作业检查依据 |

## 03 期中考试/阶段考核归档表

| 序号 | 材料项 | 归档要求 | 当前状态 | 备注 |
|------|--------|----------|----------|------|
| 1 | 试题/任务书 | 覆盖期中前核心内容 | 教师确认 | 无正式期中考试时填阶段任务 |
| 2 | 参考答案/评分标准 | 分值、评分点或等级标准明确 | 教师确认 | 可附评分量规 |
| 3 | 成绩/结果记录 | 能反映学生阶段学习情况 | 教师确认 | 可为平台成绩或项目检查记录 |
| 4 | 质量分析 | 说明共性问题和后续改进措施 | 教师确认 | 与期末教学调整衔接 |

## 04 审核结论

本材料用于证明课程期中阶段已经开展过程性检查或阶段考核。若课程无独立期中考试，不应空缺，应归档阶段测验、项目检查、实验检查或作业检查材料，并在结论中明确替代考核方式。

## 附：原始期中考试资料

$source
''';
  }

  static bool _containsAny(String normalizedText, Iterable<String> tokens) {
    for (final token in tokens) {
      if (normalizedText.contains(_normalize(token))) return true;
    }
    return false;
  }

  static String _formatDate(DateTime? now) {
    final d = now ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _trimSource(String text, {int maxChars = 12000}) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}\n\n...（原始资料较长，已截断；归档时请以源文件为准）';
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
      ..writeln('**资料来源**：模板目录')
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

**资料来源**：模板目录
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
    'midterm_progress_check': _TemplateSpec(
      documentType: 'midterm_progress_check',
      tokens: ['教学进度表', '进度表', '教学进度', '课程进度'],
      extensions: ['.docx', '.md', '.txt', '.html', '.htm', '.pdf'],
    ),
    'midterm_homework_review': _TemplateSpec(
      documentType: 'midterm_homework_review',
      tokens: ['作业次数和批阅次数', '作业次数', '批阅次数', '作业', '批阅'],
      extensions: ['.docx', '.md', '.txt', '.html', '.htm', '.pdf'],
    ),
    'midterm_exam': _TemplateSpec(
      documentType: 'midterm_exam',
      tokens: ['期中考试', '期中试卷', '期中考核', '期中'],
      extensions: ['.docx', '.pdf', '.md', '.txt', '.html', '.htm'],
    ),
    'midterm_check': _TemplateSpec(
      documentType: 'midterm_check',
      tokens: ['期中检查', '期中'],
      extensions: ['.docx', '.pdf', '.md', '.txt', '.html', '.htm'],
    ),
    'midterm_analysis': _TemplateSpec(
      documentType: 'midterm_analysis',
      tokens: ['期中成绩分析', '成绩分析', '期中分析'],
      extensions: ['.docx', '.pdf', '.md', '.txt', '.html', '.htm'],
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
