import 'dart:typed_data';
import '../../data/models/archive_document_model.dart';

/// 归档文档处理器抽象接口。
///
/// **设计原则**：每个 docType（教学大纲 / 教学日历 / 课表 / ...）有一个
/// Processor 实现，按文档真实来源分 3 类策略：
///
///   1. [SystemImportProcessor] —— 教学任务书 / 课表 / 校历 / 学生名单
///      数据来自教务系统的 mhtml/xlsx，AI 不参与，纯解析。
///
///   2. [AiDraftProcessor] —— 教学大纲 / 教案 / 进度表 / 综合考核方案 / 指导手册
///      AI 起草内容，教师可改可审。
///
///   3. [AiAuditProcessor] —— 大纲合理性审核表 / 评价表
///      不生成新文档，对已有文档（如教学大纲）做审核，输出审核表 markdown。
///
/// **共用契约**：所有 Processor 实现都要支持 4 个动作（一键生成 / 审核 /
/// 打印 / 归档），但每个动作具体行为按 docType 定制。
///
/// **打印 / 归档** 由通用基类逻辑处理（pandoc 转 docx + PDF），各 Processor 不重复实现。
abstract class DocumentProcessor {
  /// 该 Processor 处理的 docType key（与 archive_constants.dart 一致）
  String get docType;

  /// 该 Processor 处理的 docType 中文标签
  String get docLabel;

  /// 处理器策略类型，用于 UI 显示"AI 起草" / "教务导入" / "AI 审核"等标签
  ProcessorKind get kind;

  /// 是否支持"一键生成"按钮（SystemImport 类型不支持，要走"导入"按钮）
  bool get supportsGenerate => kind == ProcessorKind.aiDraft;

  /// 是否支持"一键审核"按钮（仅对 AiDraft 和 SystemImport 生成的文档有效；
  /// AiAudit 自身就是审核结果，不需要再审）
  bool get supportsReview => kind != ProcessorKind.aiAudit;

  /// 是否支持"一键打印"按钮（默认全部支持）
  bool get supportsPrint => true;

  /// 是否支持"一键归档"按钮（默认全部支持）
  bool get supportsArchive => true;

  /// **一键生成** —— 让 AI 生成新文档，返回 markdown 内容（入 archive_documents.content）。
  /// SystemImport 不应实现该方法（throw UnsupportedError）。
  Future<String> generate({
    required String period,
    required String courseType,
    Map<String, dynamic>? extra,
  });

  /// **一键审核** —— 对已有 [doc] 做 AI 审核，返回审核结果的 markdown
  /// （含 ✅⚠️❌ + 证据 + 建议）。
  /// AiAudit 自身不应实现该方法（throw UnsupportedError）。
  Future<String> review(ArchiveDocument doc);

  /// **一键打印** —— 把 [doc] 的 markdown 内容转成 PDF 字节供 Printing.layoutPdf。
  /// 由 commit 5 在通用基类 [BaseDocumentProcessor] 实现，子类一般无需 override。
  Future<Uint8List> toPdf(ArchiveDocument doc);

  /// **一键归档** —— 把 [doc] 的 markdown 内容转成 docx 字节落盘。
  /// 由 commit 5 在通用基类 [BaseDocumentProcessor] 实现，子类一般无需 override。
  Future<Uint8List> toDocx(ArchiveDocument doc);
}

/// 处理器策略类型
enum ProcessorKind {
  /// 系统导入（教务系统 mhtml/xlsx 解析，AI 不参与）
  systemImport,

  /// AI 起草（教师本人写的内容，AI 起草供修订）
  aiDraft,

  /// AI 审核（对已有文档做合理性审核，输出审核表）
  aiAudit,
}

extension ProcessorKindLabel on ProcessorKind {
  String get label {
    switch (this) {
      case ProcessorKind.systemImport:
        return '教务导入';
      case ProcessorKind.aiDraft:
        return 'AI 起草';
      case ProcessorKind.aiAudit:
        return 'AI 审核';
    }
  }
}
