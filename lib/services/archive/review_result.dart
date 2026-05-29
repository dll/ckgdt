import 'dart:convert';
import '../../core/error_handler.dart';

/// AI 审核结果的 schema —— archive_documents.review_json 列里存的就是这个的 toJson。
///
/// **设计原则**：
///   - errors  / warnings / passed 三类，对应 ❌ ⚠️ ✅
///   - 每条 finding 含"维度 + 证据 + 建议"，让教师能精准定位修订点
///   - 教师可以"忽略"某条 warning，存到 ignoredKeys 里，再审时自动跳过
///   - LLM 自评 confidence（0-1），UI 在低置信度时给视觉提示
class ReviewResult {
  /// 整体结论：approved / needs_revision / rejected
  final String overall;

  /// 必须修改项
  final List<Finding> errors;

  /// 建议改进项（教师可忽略）
  final List<Finding> warnings;

  /// 通过项（仅记录"已确认无误"，UI 折叠不显示也行）
  final List<Finding> passed;

  /// 模型自评置信度 0-1
  final double confidence;

  /// 教师修订的 finding key（再审时这些条 LLM 应跳过）
  final List<String> ignoredKeys;

  /// 审核耗时毫秒（用于性能监控）
  final int latencyMs;

  ReviewResult({
    required this.overall,
    this.errors = const [],
    this.warnings = const [],
    this.passed = const [],
    this.confidence = 0.0,
    this.ignoredKeys = const [],
    this.latencyMs = 0,
  });

  bool get hasBlockers => errors.isNotEmpty;
  bool get isApproved => overall == 'approved' && !hasBlockers;
  int get totalFindings => errors.length + warnings.length + passed.length;

  Map<String, dynamic> toMap() => {
        'overall': overall,
        'errors': errors.map((e) => e.toMap()).toList(),
        'warnings': warnings.map((e) => e.toMap()).toList(),
        'passed': passed.map((e) => e.toMap()).toList(),
        'confidence': confidence,
        'ignoredKeys': ignoredKeys,
        'latencyMs': latencyMs,
      };

  String toJson() => jsonEncode(toMap());

  factory ReviewResult.fromMap(Map<String, dynamic> map) => ReviewResult(
        overall: map['overall'] as String? ?? 'needs_revision',
        errors: _parseFindings(map['errors']),
        warnings: _parseFindings(map['warnings']),
        passed: _parseFindings(map['passed']),
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
        ignoredKeys: (map['ignoredKeys'] as List?)?.cast<String>() ?? const [],
        latencyMs: map['latencyMs'] as int? ?? 0,
      );

  factory ReviewResult.fromJson(String json) {
    if (json.isEmpty) return ReviewResult(overall: 'pending');
    try {
      return ReviewResult.fromMap(jsonDecode(json) as Map<String, dynamic>);
    } catch (e, st) {
      // 解析失败兜底：仍能展示文档但审核状态视作 pending
      swallowDebug(e, tag: 'ReviewResult.fromJson', stack: st);
      return ReviewResult(overall: 'pending');
    }
  }

  /// 渲染给教师看的 markdown 报告（用于 syllabus_review docType 文档的 content 字段）
  String toMarkdown({String? title}) {
    final buf = StringBuffer();
    buf.writeln('# ${title ?? '审核结果'}');
    buf.writeln();
    final overallLabel = {
      'approved': '✅ 通过',
      'needs_revision': '⚠️ 需修订',
      'rejected': '❌ 不合格',
      'pending': '⏳ 待审核',
    }[overall] ?? overall;
    buf.writeln('**综合评级**：$overallLabel');
    buf.writeln('**置信度**：${(confidence * 100).toStringAsFixed(0)}%');
    buf.writeln('**审核耗时**：${latencyMs}ms');
    buf.writeln();

    if (errors.isNotEmpty) {
      buf.writeln('## ❌ 必须修改（${errors.length} 项）');
      buf.writeln();
      _renderTable(buf, errors);
    }
    if (warnings.isNotEmpty) {
      buf.writeln('## ⚠️ 建议改进（${warnings.length} 项）');
      buf.writeln();
      _renderTable(buf, warnings);
    }
    if (passed.isNotEmpty) {
      buf.writeln('## ✅ 通过项（${passed.length} 项）');
      buf.writeln();
      _renderTable(buf, passed);
    }
    return buf.toString();
  }

  void _renderTable(StringBuffer buf, List<Finding> items) {
    buf.writeln('| 维度 | 等级 | 证据 | 修订建议 |');
    buf.writeln('|------|------|------|---------|');
    for (final f in items) {
      final dim = _escape(f.dimension);
      final lvl = _escape(f.level);
      final ev = _escape(f.evidence);
      final sug = _escape(f.suggestion);
      buf.writeln('| $dim | $lvl | $ev | $sug |');
    }
    buf.writeln();
  }

  String _escape(String s) =>
      s.replaceAll('\n', ' ').replaceAll('|', '\\|').trim();

  static List<Finding> _parseFindings(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Finding.fromMap)
        .toList();
  }
}

/// 一条审核发现项
class Finding {
  /// 唯一 key（如 'syllabus.hours_consistency'），再审时教师"忽略"凭这个去重
  final String key;

  /// 审核维度（如 "学时一致性" / "课程目标条数"）
  final String dimension;

  /// 等级图标：✅ 通过 / ⚠️ 建议 / ❌ 错误
  final String level;

  /// 证据：引用文档具体段落 / 数字 / 矛盾点
  final String evidence;

  /// 修订建议
  final String suggestion;

  /// 审核层次：'structural'（粗审：结构/章节/OBE 框架）/ 'numerical'（细审：数字/学时/分数）
  final String layer;

  Finding({
    required this.key,
    required this.dimension,
    required this.level,
    required this.evidence,
    required this.suggestion,
    this.layer = 'structural',
  });

  Map<String, dynamic> toMap() => {
        'key': key,
        'dimension': dimension,
        'level': level,
        'evidence': evidence,
        'suggestion': suggestion,
        'layer': layer,
      };

  factory Finding.fromMap(Map<String, dynamic> map) => Finding(
        key: map['key'] as String? ?? '',
        dimension: map['dimension'] as String? ?? '',
        level: map['level'] as String? ?? '',
        evidence: map['evidence'] as String? ?? '',
        suggestion: map['suggestion'] as String? ?? '',
        layer: map['layer'] as String? ?? 'structural',
      );
}
