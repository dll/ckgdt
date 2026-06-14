import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/constants/archive_periods.dart' as periods;
import '../../core/error_handler.dart';
import '../../data/local/archive_dao.dart';
import '../../data/models/archive_document_model.dart';
import '../ai_service.dart';
import '../archive_context_service.dart';
import '../archive_template_loader.dart';
import 'base_document_processor.dart';
import 'document_processor.dart';
import 'review_result.dart';

/// AI 审核处理器（核心 ★）。
///
/// **价值主张**：传统填表器只能找到"格式不对"的错；本处理器要找到
/// "教师肉眼忽略的事实错"——比如学时加和不到 24、第三章学时声明 4 但
/// 教学进度表里只排了 2、课程目标 4 条但权重只填 3 条。
///
/// **两层审核**：
///
///   1. **粗审 structural**——文档结构 / OBE 框架 / 章节齐全 / 必备段落
///      （由 LLM 一次性扫读全文给出结构性 finding）
///
///   2. **细审 numerical**——所有数字相互一致：
///      - 学时加和（每章学时 + 实验学时 = 总学时）
///      - 权重加和（平时+实验+期末 = 100%）
///      - 课程目标 vs 评价方式 vs 毕业要求映射 三方对账
///      - 每个章节的"学习预期成果"是否真支撑某条课程目标
///      （由 LLM 第二次精读给出数字性 finding）
///
/// **修订-再审循环**：
///   - ReviewResult.ignoredKeys 让教师可"忽略此条"
///   - 再审时把忽略的 key 列表注入 prompt，LLM 跳过相同 finding
///
/// **为什么不直接复用现有 archive_agent.reviewDocument**：那个版本输出
/// markdown 字符串，无法解析 / 持久化 / 比对。本处理器输出强类型
/// [ReviewResult]，可入库、可 diff、可"忽略此条"。
class AiAuditProcessor extends BaseDocumentProcessor {
  AiAuditProcessor({
    required this.targetDocType,
    required this.targetDocLabel,
    required this.auditDocType,
    required this.auditDocLabel,
  });

  /// 被审目标 docType（如 'syllabus' 教学大纲）
  final String targetDocType;
  final String targetDocLabel;

  /// 审核结果落到哪个 docType 卡片（如 'syllabus_review' 大纲合理性审核表）
  final String auditDocType;
  final String auditDocLabel;

  final _ai = AiService();
  final _ctx = ArchiveContextService();
  final _dao = ArchiveDao();

  @override
  String get docType => auditDocType;

  @override
  String get docLabel => auditDocLabel;

  @override
  ProcessorKind get kind => ProcessorKind.aiAudit;

  @override
  bool get supportsGenerate => false;

  @override
  bool get supportsReview => false;

  @override
  Future<String> generate({
    required String period,
    required String courseType,
    Map<String, dynamic>? extra,
  }) {
    throw UnsupportedError(
      'AiAuditProcessor 不直接生成新文档。要审核请用 reviewTarget()，'
      '审核结果会自动 saveDocument 一份 docType=$auditDocType 的卡片。',
    );
  }

  @override
  Future<String> review(ArchiveDocument doc) {
    throw UnsupportedError('audit 文档自身不需要再审');
  }

  /// **核心入口**：审核 [target]（如教学大纲），返回审核结果。
  ///
  /// 副作用：
  ///   1. 更新 [target].review_json / status / reviewed_at
  ///   2. 创建（或更新）一份 docType=auditDocType 的"审核表"卡片，
  ///      content = ReviewResult.toMarkdown，origin_doc_id 指向 target.id
  ///
  /// 修订-再审循环：[target] 的 review_json 里如果已有 ignoredKeys，
  /// 自动注入 prompt 让 LLM 跳过同名 finding。
  Future<ReviewResult> reviewTarget(ArchiveDocument target) async {
    if (target.id == null) {
      throw ArgumentError('target 必须先入库（id != null）才能审核');
    }
    if ((target.content ?? '').isEmpty) {
      throw ArgumentError('target.content 为空，无可审核内容');
    }

    final stopwatch = Stopwatch()..start();

    // 取上次审核的 ignoredKeys，再审时跳过
    final prev = ReviewResult.fromJson(target.reviewJson);
    final ignoredKeys = prev.ignoredKeys;

    // 收集系统事实 + 历届模板（细审对数字一致性必不可少）
    String systemFacts = '';
    try {
      systemFacts = await _ctx.collectForPrompt();
    } catch (e, st) {
      swallowDebug(e, tag: 'AiAuditProcessor.collectForPrompt', stack: st);
    }
    final referenceMd = await ArchiveTemplateLoader.loadPrimary(
      periodZh: periods.periodLabel(target.period),
      docType: targetDocType,
    );

    final prompt = _buildAuditPrompt(
      target: target,
      systemFacts: systemFacts,
      referenceMd: referenceMd,
      ignoredKeys: ignoredKeys,
    );

    final messages = [
      {
        'role': 'system',
        'content': '你是教学归档审核专家。**只输出 JSON**，不输出额外文字。JSON schema 在用户消息末尾。',
      },
      {'role': 'user', 'content': prompt},
    ];

    final result = await _ai.chat(
      messages,
      temperature: 0.2, // 审核要稳定低温
    );

    stopwatch.stop();
    final latencyMs = stopwatch.elapsedMilliseconds;

    final review = _parseReviewJson(result, latencyMs: latencyMs);

    // 把 ignoredKeys 继承下来（教师之前忽略的，本次仍视作忽略）
    final mergedIgnored =
        <String>{...review.ignoredKeys, ...ignoredKeys}.toList();
    final finalReview = ReviewResult(
      overall: review.overall,
      errors: review.errors,
      warnings:
          review.warnings.where((w) => !mergedIgnored.contains(w.key)).toList(),
      passed: review.passed,
      confidence: review.confidence,
      ignoredKeys: mergedIgnored,
      latencyMs: latencyMs,
    );

    // 副作用 1：更新 target 的 review_json + status
    final newStatus = finalReview.isApproved
        ? 'approved'
        : finalReview.hasBlockers
            ? 'reviewing'
            : 'reviewing';
    await _dao.saveDocument(target.copyWith(
      reviewJson: finalReview.toJson(),
      reviewedAt: DateTime.now().toIso8601String(),
      status: newStatus,
    ));

    // 副作用 2：创建/更新审核表 docType 文档
    await _upsertAuditDoc(target, finalReview);

    return finalReview;
  }

  /// 教师"忽略此条"操作 —— 把 [findingKey] 加进 ignoredKeys，UI 重新展示
  /// 时不再显示该 warning。
  Future<ReviewResult> ignoreFinding(
    ArchiveDocument target,
    String findingKey,
  ) async {
    final current = ReviewResult.fromJson(target.reviewJson);
    if (current.ignoredKeys.contains(findingKey)) return current;
    final updated = ReviewResult(
      overall: current.overall,
      errors: current.errors.where((e) => e.key != findingKey).toList(),
      warnings: current.warnings.where((w) => w.key != findingKey).toList(),
      passed: current.passed,
      confidence: current.confidence,
      ignoredKeys: [...current.ignoredKeys, findingKey],
      latencyMs: current.latencyMs,
    );
    await _dao.saveDocument(target.copyWith(reviewJson: updated.toJson()));
    await _upsertAuditDoc(target, updated);
    return updated;
  }

  /// 创建或更新审核表 docType 文档（origin_doc_id 关联源文档）
  Future<void> _upsertAuditDoc(
    ArchiveDocument target,
    ReviewResult review,
  ) async {
    // origin_doc_id 是 audit→target 的反向键，DAO 已有索引友好的查询。
    final linkedAll = await _dao.getAuditDocsForOrigin(target.id!);
    ArchiveDocument? linked;
    for (final d in linkedAll) {
      if (d.documentType == auditDocType) {
        linked = d;
        break;
      }
    }

    final auditTitle = '$auditDocLabel - ${target.title}';
    final auditMd = review.toMarkdown(title: auditTitle);

    if (linked != null) {
      await _dao.saveDocument(linked.copyWith(
        title: auditTitle,
        content: auditMd,
        reviewJson: review.toJson(),
        reviewedAt: DateTime.now().toIso8601String(),
        // 审核表自身的 status 跟随源文档
        status: review.isApproved ? 'approved' : 'reviewing',
      ));
    } else {
      await _dao.saveDocument(ArchiveDocument(
        title: auditTitle,
        documentType: auditDocType,
        period: target.period,
        courseId: target.courseId,
        courseType: target.courseType,
        content: auditMd,
        isGenerated: true,
        originDocId: target.id,
        reviewJson: review.toJson(),
        reviewedAt: DateTime.now().toIso8601String(),
        status: review.isApproved ? 'approved' : 'reviewing',
      ));
    }
  }

  String _buildAuditPrompt({
    required ArchiveDocument target,
    required String systemFacts,
    required String? referenceMd,
    required List<String> ignoredKeys,
  }) {
    final buf = StringBuffer();

    buf.writeln('# 审核任务');
    buf.writeln();
    buf.writeln('请审核下方"$targetDocLabel"的合理性，按两层标准给 finding：');
    buf.writeln();
    buf.writeln('## 第一层：粗审（structural）');
    buf.writeln('- 文档必备段落是否齐全（如教学大纲必含：基本信息 / 课程简介 / '
        '课程目标 / 教学内容 / 实验项目 / 考核方式 / 参考教材）');
    buf.writeln('- OBE 框架完整性（课程目标 → 毕业要求映射 → 评价方式三角是否闭环）');
    buf.writeln('- 章节是否与系统事实第 3 段的根节点对齐');
    buf.writeln('- 思政元素 / 教学重难点 / 学习预期成果是否每章都有');
    buf.writeln();
    buf.writeln('## 第二层：细审（numerical）★ 这是教师肉眼最易忽略的');
    buf.writeln('- **学时加和**：每章学时之和 + 实验学时之和 是否等于总学时');
    buf.writeln('- **权重加和**：平时 + 实验 + 期末 三项 = 100%？');
    buf.writeln('- **课程目标 vs 权重映射**：N 个目标必须每个都在评价方式表中有权重，'
        '不能漏不能重');
    buf.writeln('- **章节学习成果 vs 课程目标支撑**：每章末尾的"学习预期成果支撑课程目标 X"，'
        '所有目标都被覆盖至少 1 次了吗');
    buf.writeln('- **实验项目编号** 是否与系统事实第 4 段一致');
    buf.writeln('- **基本身份字段**：教师 / 班级 / 专业 / 学期 / 学时 / 学分 是否与'
        '系统事实第 1、2、5 段完全一致（否则属 ❌ 错误）');
    buf.writeln();

    if (ignoredKeys.isNotEmpty) {
      buf.writeln('## 教师已忽略的 finding key（本次不再上报相同 key）');
      for (final k in ignoredKeys) {
        buf.writeln('- $k');
      }
      buf.writeln();
    }

    buf.writeln('---');
    buf.writeln();
    buf.writeln('## [SYSTEM_FACTS] 系统当前事实');
    buf.writeln(systemFacts.isEmpty ? '[无]' : systemFacts);
    buf.writeln();

    if (referenceMd != null && referenceMd.isNotEmpty) {
      final ref = referenceMd.length > 2500
          ? '${referenceMd.substring(0, 2500)}\n...（截断）'
          : referenceMd;
      buf.writeln('## [REFERENCE] 历届同类材料（参考结构和 OBE 框架）');
      buf.writeln(ref);
      buf.writeln();
    }

    buf.writeln('---');
    buf.writeln();
    buf.writeln('## [AUDIT_TARGET] 待审文档');
    buf.writeln('**标题**：${target.title}');
    buf.writeln('**类型**：$targetDocLabel');
    buf.writeln('**期间**：${periods.periodLabel(target.period)}');
    buf.writeln();
    buf.writeln('```markdown');
    final content = target.content ?? '';
    final body = content.length > 6000
        ? '${content.substring(0, 6000)}\n...（截断）'
        : content;
    buf.writeln(body);
    buf.writeln('```');
    buf.writeln();

    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 输出 JSON Schema（**只输出此 JSON 一段，不要其它字符**）');
    buf.writeln('```json');
    buf.writeln(_jsonSchemaExample());
    buf.writeln('```');
    buf.writeln();
    buf.writeln('硬性要求：');
    buf.writeln('- 必须是合法 JSON，UTF-8，无尾随逗号，无注释');
    buf.writeln(
        '- key 字段用 `<docType>.<dimension_snake>` 格式，如 `syllabus.hours_total`');
    buf.writeln('- level 必须是这三个字符串之一：`✅ 通过` / `⚠️ 建议` / `❌ 错误`');
    buf.writeln('- layer 必须是 `structural` 或 `numerical` 之一');
    buf.writeln('- evidence 引用文档原文具体片段或数字（不少于 10 字符）');
    buf.writeln('- suggestion 给可执行的修订建议（不少于 10 字符）');
    buf.writeln('- 没找到错误时也要返回 JSON，errors=[] warnings=[] passed=[基本通过项]');
    buf.writeln('- confidence ∈ [0, 1]，自评把握度');

    return buf.toString();
  }

  String _jsonSchemaExample() => '''{
  "overall": "needs_revision",
  "errors": [
    {
      "key": "syllabus.hours_total_mismatch",
      "dimension": "学时加和",
      "level": "❌ 错误",
      "evidence": "第三章学时 4 + 第四章学时 4 + ... = 22，但总学时声明 24",
      "suggestion": "确认第几章漏算 2 学时，或修正总学时声明",
      "layer": "numerical"
    }
  ],
  "warnings": [
    {
      "key": "syllabus.思政_章节4",
      "dimension": "思政元素契合度",
      "level": "⚠️ 建议",
      "evidence": "第四章微信小程序的思政元素写'民族品牌自信'，与本章主题契合度较低",
      "suggestion": "建议改为'技术服务社会'相关方向",
      "layer": "structural"
    }
  ],
  "passed": [
    {
      "key": "syllabus.OBE_objectives",
      "dimension": "OBE 框架完整性",
      "level": "✅ 通过",
      "evidence": "课程目标 4 条 → 毕业要求 1.4/3.2/4.2/5.1 一一映射",
      "suggestion": "保持现状",
      "layer": "structural"
    }
  ],
  "confidence": 0.92
}''';

  /// 解析 LLM 返回的 JSON，容错：去掉 markdown 围栏、去掉多余文本
  ReviewResult _parseReviewJson(String raw, {int latencyMs = 0}) {
    var s = raw.trim();
    // 去 markdown 围栏
    if (s.startsWith('```')) {
      final firstNewline = s.indexOf('\n');
      if (firstNewline != -1) s = s.substring(firstNewline + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    }
    s = s.trim();
    // 找第一个 { 和最后一个 }，去多余前后文本
    final firstBrace = s.indexOf('{');
    final lastBrace = s.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace == -1) {
      if (kDebugMode) {
        debugPrint('[AiAuditProcessor] JSON 解析失败：找不到 {} 包裹\n$raw');
      }
      return ReviewResult(
        overall: 'needs_revision',
        errors: [
          Finding(
            key: 'audit.parse_failed',
            dimension: 'AI 审核响应',
            level: '❌ 错误',
            evidence:
                'LLM 输出无法解析为 JSON：${raw.substring(0, raw.length.clamp(0, 200))}',
            suggestion: '检查 AI provider 配置或重试一次',
          ),
        ],
        latencyMs: latencyMs,
      );
    }
    s = s.substring(firstBrace, lastBrace + 1);

    try {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return ReviewResult.fromMap({...map, 'latencyMs': latencyMs});
    } catch (e, st) {
      swallowDebug(e, tag: 'AiAuditProcessor.parseReviewJson', stack: st);
      return ReviewResult(
        overall: 'needs_revision',
        errors: [
          Finding(
            key: 'audit.json_decode_failed',
            dimension: 'AI 审核响应',
            level: '❌ 错误',
            evidence:
                'JSON 解析异常：$e。原始响应前 200 字符：${raw.substring(0, raw.length.clamp(0, 200))}',
            suggestion: '换 AI provider 或修订 prompt',
          ),
        ],
        latencyMs: latencyMs,
      );
    }
  }

  // BaseDocumentProcessor 默认 toPdf/toDocx 已经处理 markdown→docx。
  // 审核表自身的 content 就是 ReviewResult.toMarkdown 输出，可直接打印归档。
}
