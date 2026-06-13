import 'dart:typed_data';

import '../../data/models/archive_document_model.dart';
import 'base_document_processor.dart';
import 'document_processor.dart';
import 'teaching_task_pdf.dart';

/// 教学任务书处理器（系统导入类）。
///
/// 数据由教务系统 MHTML/HTML 导入（ArchiveImporters.parseTeachingTask），AI 不参与。
/// 打印走原生 [TeachingTaskPdf]（官方存根+签章版式，零外部依赖，不需 LibreOffice/pandoc）；
/// 归档 docx 仍走基类 pandoc/原生 OOXML 路径。
class TeachingTaskProcessor extends BaseDocumentProcessor {
  @override
  String get docType => 'teaching_task';

  @override
  String get docLabel => '教学任务单';

  @override
  ProcessorKind get kind => ProcessorKind.systemImport;

  // 审核走 period_tab 结构化校验，不走 Processor.review()（其 review() 抛 UnsupportedError）。
  @override
  bool get supportsReview => false;

  @override
  Future<String> generate({
    required String period,
    required String courseType,
    Map<String, dynamic>? extra,
  }) =>
      throw UnsupportedError('教学任务书由教务系统导入，不支持 AI 生成');

  @override
  Future<String> review(ArchiveDocument doc) =>
      throw UnsupportedError('教学任务书审核走 period_tab 结构化校验');

  /// 打印：原生官方版式 PDF（覆盖基类 pandoc 路径）。
  @override
  Future<Uint8List> toPdf(ArchiveDocument doc) {
    final content = doc.content ?? '';
    if (content.trim().isEmpty) {
      throw StateError('教学任务书内容为空，无法打印');
    }
    return TeachingTaskPdf.build(content);
  }
}
