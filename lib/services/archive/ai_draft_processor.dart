import 'package:flutter/foundation.dart';
import '../../core/constants/archive_periods.dart' as periods;
import '../../core/error_handler.dart';
import '../../data/local/archive_dao.dart';
import '../../data/models/archive_document_model.dart';
import '../agent/agents/archive_agent.dart';
import 'base_document_processor.dart';
import 'document_processor.dart';

/// AI 起草处理器。
///
/// **价值主张**：把现有 [ArchiveAgent.generateDocument] 包装为 [DocumentProcessor]
/// 接口实现，让"一键生成"走统一注册表路径。这样 period_tab 不必再 if-else
/// 区分"哪些 docType 走 agent / 哪些走 audit"，UI 一律 `registry.find(docType)
/// .generate(...)` 就行。
///
/// **职责边界**：
///   - 生成 → 委托 archive_agent（保留三段式 prompt：persona + 系统事实 + 历届模板）
///   - 审核 → 委托 archive_agent.reviewDocument（旧 markdown 字符串路径）
///   - 打印 / 归档 → 走 BaseDocumentProcessor 默认（pandoc + reference-doc）
///
/// **何时不用 AiDraftProcessor**：
///   - SystemImport 类（教学任务书 / 课表 / 学生名单）由 period_tab 内的
///     mhtml/xlsx 解析器导入，不走 AI。
///   - AiAudit 类（大纲合理性审核表 / 评价表）已有专门的 AiAuditProcessor。
///
/// **registerAll 配套**：[ProcessorRegistry.registerAll] 里枚举所有
/// `needsGeneration=true` 的 docType 自动注册。
class AiDraftProcessor extends BaseDocumentProcessor {
  AiDraftProcessor({
    required this.docTypeKey,
    required this.docTypeLabel,
    required this.agent,
    this.dao,
  });

  /// 该 Processor 处理的 docType key（必须与 archive_constants.dart 一致）
  final String docTypeKey;
  final String docTypeLabel;
  final ArchiveAgent agent;
  final ArchiveDao? dao;

  @override
  String get docType => docTypeKey;

  @override
  String get docLabel => docTypeLabel;

  @override
  ProcessorKind get kind => ProcessorKind.aiDraft;

  /// **一键生成** —— 委托 archive_agent.generateDocument 走三段式 prompt。
  /// 返回的是 markdown 字符串（来自落库后的 doc.content）。
  ///
  /// 注意：archive_agent.generateDocument 内部已经 saveDocument 了一份，
  /// 这里只是把 content 抽出来交给上层。上层若需要 doc.id 应改用
  /// [generateAsDocument]。
  @override
  Future<String> generate({
    required String period,
    required String courseType,
    Map<String, dynamic>? extra,
  }) async {
    final title = (extra?['title'] as String?) ?? _defaultTitle(period);
    final templateRef = extra?['templateRef'] as String?;
    final doc = await agent.generateDocument(
      title: title,
      documentType: docTypeKey,
      period: period,
      courseType: courseType,
      templateRef: templateRef,
    );
    return doc.content ?? '';
  }

  /// 直接返回完整 [ArchiveDocument]（含 id），UI 拿来后可立即跳转预览。
  /// 业务路径推荐：UI 调这个，再交给 [ProcessorRegistry] 找的 audit processor 审核。
  Future<ArchiveDocument> generateAsDocument({
    required String period,
    required String courseType,
    String? title,
    String? templateRef,
  }) async {
    final t = title ?? _defaultTitle(period);
    return agent.generateDocument(
      title: t,
      documentType: docTypeKey,
      period: period,
      courseType: courseType,
      templateRef: templateRef,
    );
  }

  /// **一键审核** —— 委托 archive_agent.reviewDocument 给出 markdown 审核摘要。
  ///
  /// **设计选择**：保留旧版字符串审核路径，让 docType 没专门 AiAuditProcessor
  /// 时也有兜底审核。需要结构化 finding 时上层应优先用 AiAuditProcessor。
  @override
  Future<String> review(ArchiveDocument doc) async {
    try {
      return await agent.reviewDocument(doc);
    } catch (e, st) {
      swallowDebug(e, tag: 'AiDraftProcessor.review.$docTypeKey', stack: st);
      rethrow;
    }
  }

  String _defaultTitle(String period) =>
      '${periods.periodLabel(period)}$docTypeLabel';

  @visibleForTesting
  static AiDraftProcessor forTest({
    required String docTypeKey,
    required String docTypeLabel,
    required ArchiveAgent agent,
  }) =>
      AiDraftProcessor(
        docTypeKey: docTypeKey,
        docTypeLabel: docTypeLabel,
        agent: agent,
      );
}
