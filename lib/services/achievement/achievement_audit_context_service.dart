import 'dart:io';

import '../../core/error_handler.dart';
import '../../data/local/achievement_dao.dart';
import '../../data/local/archive_dao.dart';
import '../../data/local/course_dao.dart';
import '../../data/models/archive_document_model.dart';
import '../achievement_context.dart';

class AchievementAuditSnapshot {
  final String courseName;
  final String courseId;
  final List<Map<String, dynamic>> objectives;
  final List<Map<String, dynamic>> batches;
  final Map<String, dynamic>? selectedBatch;
  final int studentCount;
  final Map<String, double> classAverage;
  final List<ArchiveDocument> archiveDocuments;

  const AchievementAuditSnapshot({
    required this.courseName,
    required this.courseId,
    required this.objectives,
    required this.batches,
    required this.selectedBatch,
    required this.studentCount,
    required this.classAverage,
    required this.archiveDocuments,
  });
}

class AchievementAuditContextService {
  AchievementAuditContextService({
    AchievementDao? achievementDao,
    ArchiveDao? archiveDao,
    CourseDao? courseDao,
  })  : _achievementDao = achievementDao ?? AchievementDao(),
        _archiveDao = archiveDao ?? ArchiveDao(),
        _courseDao = courseDao ?? CourseDao();

  final AchievementDao _achievementDao;
  final ArchiveDao _archiveDao;
  final CourseDao _courseDao;

  static final instance = AchievementAuditContextService();

  Future<AchievementAuditSnapshot> loadSnapshot({int? batchId}) async {
    final activeCourse = await _courseDao.getActiveCourse();
    final courseName = activeCourse?.name.trim().isNotEmpty == true
        ? activeCourse!.name.trim()
        : AchievementContext.instance.courseName.trim().isNotEmpty
            ? AchievementContext.instance.courseName.trim()
            : '当前课程';
    final courseId = activeCourse?.id ?? '';

    final objectives = await _achievementDao.getCourseObjectives(courseName);
    final batches = await _achievementDao.getAllBatches(courseName: courseName);
    final selectedBatch = _selectBatch(batches, batchId);

    var studentCount = 0;
    var classAverage = <String, double>{};
    if (selectedBatch != null) {
      final id = _asInt(selectedBatch['id']);
      if (id > 0) {
        try {
          studentCount = (await _achievementDao.getScores(id)).length;
          classAverage = await _achievementDao.calculateClassAverage(id);
        } catch (e, st) {
          swallowDebug(e,
              tag: 'AchievementAuditContext.loadAchievement', stack: st);
        }
      }
    }

    List<ArchiveDocument> archiveDocs = const [];
    try {
      archiveDocs = await _archiveDao.getDocuments(
        courseId: courseId,
        filterByCourse: true,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementAuditContext.loadArchive', stack: st);
    }

    return AchievementAuditSnapshot(
      courseName: courseName,
      courseId: courseId,
      objectives: objectives,
      batches: batches,
      selectedBatch: selectedBatch,
      studentCount: studentCount,
      classAverage: classAverage,
      archiveDocuments: archiveDocs,
    );
  }

  Future<String> buildAuditMarkdown(
      {int? batchId, bool compact = false}) async {
    final snapshot = await loadSnapshot(batchId: batchId);
    return buildAuditMarkdownFromSnapshot(snapshot, compact: compact);
  }

  String buildAuditMarkdownFromSnapshot(
    AchievementAuditSnapshot snapshot, {
    bool compact = false,
  }) {
    final docs = snapshot.archiveDocuments;
    final objectives = snapshot.objectives;
    final selectedBatch = snapshot.selectedBatch;
    final issues = <String>[];
    final actions = <String>[];

    if (objectives.isEmpty) {
      issues.add('未检测到课程目标。请先从教学大纲导入或维护课程目标、权重、满分和考核环节。');
      actions.add('期初先完成教学大纲和课程目标对照表，再生成达成评价批次。');
    } else {
      final weightSum = objectives.fold<double>(
          0, (sum, row) => sum + _asRatio(row['weight']));
      if ((weightSum - 1.0).abs() > 0.02) {
        issues.add('课程目标权重合计为 ${weightSum.toStringAsFixed(2)}，建议复核是否等于 1.00。');
      }
      for (final row in objectives) {
        final idx = _asInt(row['idx']);
        if (_asDouble(row['full_mark']) <= 0) {
          issues.add('课程目标$idx 未设置满分，达成度计算会缺少可靠分母。');
        }
        if (row['indicator']?.toString().trim().isEmpty ?? true) {
          issues.add('课程目标$idx 未绑定毕业要求或指标点，审核时缺少支撑关系。');
        }
      }
    }

    if (snapshot.batches.isEmpty) {
      issues.add('当前课程没有达成度批次。');
      actions.add('根据当前课程创建达成评价批次，并导入学生平时、实验、考核成绩。');
    } else if (selectedBatch == null) {
      issues.add('未找到指定达成度批次。');
    } else if (snapshot.studentCount == 0) {
      issues.add('达成度批次没有学生成绩，无法形成有效达成评价。');
      actions.add('导入或同步成绩后重新计算达成度。');
    }

    final requiredDocs = _requiredDocs();
    final docLines = <String>[];
    var readyRequired = 0;
    for (final req in requiredDocs) {
      final doc = _findDoc(docs, req);
      if (doc == null) {
        issues.add('${req.stage}${req.label}缺失。');
        docLines.add('| ${req.stage} | ${req.label} | 缺失 | - | - |');
        continue;
      }
      final hasOriginal = _hasOriginalFile(doc);
      final reviewed = doc.reviewJson.trim().isNotEmpty ||
          doc.reviewedAt.trim().isNotEmpty ||
          doc.status == 'approved' ||
          doc.status == 'archived';
      final ready = hasOriginal || (doc.content?.trim().isNotEmpty ?? false);
      if (ready) readyRequired++;
      if (!ready) issues.add('${req.stage}${req.label}没有原件或可编辑内容。');
      if (req.mustReview && !reviewed) {
        issues.add('${req.stage}${req.label}尚未审核。');
      }
      docLines.add('| ${req.stage} | ${req.label} | ${doc.status} | '
          '${hasOriginal ? '原件' : (doc.content?.trim().isNotEmpty ?? false) ? 'Markdown' : '空'} | '
          '${reviewed ? '已审核' : '待审核'} |');
    }

    final passed = issues.isEmpty;
    if (actions.isEmpty) {
      if (passed) {
        actions.add(
            '可执行一键生成、审核、打印、归档；归档前保留 Word/Excel/PDF 原件，同时保留 Markdown 草稿用于编辑。');
      } else {
        actions.add('按缺口补齐材料后，再执行生成、审核、打印、归档。');
      }
    }

    final buf = StringBuffer();
    buf.writeln(compact ? '## 达成归档审核上下文' : '## 达成材料多维度审核');
    buf.writeln();
    buf.writeln('- 当前课程：《${snapshot.courseName}》');
    if (snapshot.courseId.isNotEmpty) {
      buf.writeln('- 课程ID：${snapshot.courseId}');
    }
    buf.writeln('- 课程目标：${objectives.length} 项');
    buf.writeln('- 达成批次：${snapshot.batches.length} 个');
    if (selectedBatch != null) {
      buf.writeln('- 当前批次：#${selectedBatch['id']} '
          '${selectedBatch['batch_name'] ?? selectedBatch['name'] ?? '未命名'}，'
          '学生数 ${snapshot.studentCount}');
    }
    buf.writeln('- 关键材料：$readyRequired/${requiredDocs.length} 项有原件或可编辑内容');
    buf.writeln('- 审核结论：${passed ? '满足归档前置条件' : '暂不满足一键归档条件'}');
    buf.writeln();

    if (!compact) {
      buf.writeln('### 材料状态');
      buf.writeln();
      buf.writeln('| 阶段 | 材料 | 状态 | 内容形态 | 审核 |');
      buf.writeln('|------|------|------|----------|------|');
      for (final line in docLines) {
        buf.writeln(line);
      }
      buf.writeln();
    }

    if (objectives.isNotEmpty) {
      buf.writeln('### 课程目标与评价依据');
      buf.writeln();
      buf.writeln('| 目标 | 权重 | 满分 | 指标点 | 评价环节 |');
      buf.writeln('|------|------|------|--------|----------|');
      for (final row in objectives) {
        final idx = _asInt(row['idx']);
        final envs = _assessmentParts(row);
        buf.writeln(
            '| 目标$idx | ${_asRatio(row['weight']).toStringAsFixed(2)} | '
            '${_asDouble(row['full_mark']).toStringAsFixed(0)} | '
            '${_escapeCell(row['indicator'])} | ${envs.join('、')} |');
      }
      buf.writeln();
    }

    if (snapshot.classAverage.isNotEmpty) {
      buf.writeln('### 达成结果摘要');
      buf.writeln();
      for (final entry in snapshot.classAverage.entries) {
        buf.writeln('- ${entry.key}：${entry.value.toStringAsFixed(3)}');
      }
      buf.writeln();
    }

    buf.writeln('### 审核问题');
    buf.writeln();
    if (issues.isEmpty) {
      buf.writeln('- 暂未发现阻断项。');
    } else {
      for (final issue in issues) {
        buf.writeln('- $issue');
      }
    }
    buf.writeln();
    buf.writeln('### 建议动作');
    buf.writeln();
    for (final action in actions) {
      buf.writeln('- $action');
    }
    return buf.toString().trimRight();
  }

  static Map<String, dynamic>? _selectBatch(
    List<Map<String, dynamic>> batches,
    int? batchId,
  ) {
    if (batches.isEmpty) return null;
    if (batchId == null) return batches.first;
    for (final batch in batches) {
      if (_asInt(batch['id']) == batchId) return batch;
    }
    return null;
  }

  static List<_RequiredArchiveDoc> _requiredDocs() => const [
        _RequiredArchiveDoc('期初', '教学大纲', ['syllabus', '大纲'], mustReview: true),
        _RequiredArchiveDoc('期初', '教学进度表', ['teaching_schedule', '进度']),
        _RequiredArchiveDoc('期初', '课程表', ['course_schedule', '课表', '课程表']),
        _RequiredArchiveDoc('期中', '教学检查材料', ['midterm', '期中', '检查']),
        _RequiredArchiveDoc('期末', '课程目标达成评价报告',
            ['final_achievement_report', 'achievement_report', '达成']),
        _RequiredArchiveDoc('期末', '课程档案袋目录',
            ['final_archive_catalog', 'archive_catalog', '档案袋', '目录']),
        _RequiredArchiveDoc(
            '结课', '结课归档审批材料', ['closure', 'archive_form', '审批', '归档']),
      ];

  static ArchiveDocument? _findDoc(
    List<ArchiveDocument> docs,
    _RequiredArchiveDoc required,
  ) {
    for (final doc in docs) {
      final haystack =
          '${doc.period} ${doc.documentType} ${doc.title}'.toLowerCase();
      if (required.keywords.any(
            (keyword) => haystack.contains(keyword.toLowerCase()),
          ) ||
          haystack.contains(required.label)) {
        return doc;
      }
    }
    return null;
  }

  static bool _hasOriginalFile(ArchiveDocument doc) {
    final path = doc.filePath?.trim();
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static List<String> _assessmentParts(Map<String, dynamic> row) {
    final parts = <String>[];
    final pingshi = _asRatio(row['pingshi_ratio']);
    final experiment = _asRatio(row['experiment_ratio']);
    final exam = _asRatio(row['exam_ratio']);
    if (pingshi > 0) parts.add('平时${(pingshi * 100).toStringAsFixed(0)}%');
    if (experiment > 0) {
      parts.add('实验${(experiment * 100).toStringAsFixed(0)}%');
    }
    if (exam > 0) parts.add('考核${(exam * 100).toStringAsFixed(0)}%');
    return parts.isEmpty ? ['未设置'] : parts;
  }

  static String _escapeCell(Object? value) =>
      value?.toString().replaceAll('|', '/') ?? '';

  static int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static double _asDouble(Object? value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll('%', '')) ?? fallback;
    }
    return fallback;
  }

  static double _asRatio(Object? value, [double fallback = 0]) {
    final ratio = _asDouble(value, fallback);
    return ratio > 1 ? ratio / 100 : ratio;
  }
}

class _RequiredArchiveDoc {
  final String stage;
  final String label;
  final List<String> keywords;
  final bool mustReview;

  const _RequiredArchiveDoc(
    this.stage,
    this.label,
    this.keywords, {
    this.mustReview = false,
  });
}
