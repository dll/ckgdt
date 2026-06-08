import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/archive_periods.dart' as periods;
import '../../data/models/archive_document_model.dart';
import 'document_processor.dart';
import 'native_docx_service.dart';
import 'pandoc_service.dart';

/// 通用基类 —— 提供 toPdf / toDocx 的默认实现（pandoc 路径），
/// 子类只需实现 generate / review。
///
/// **样式继承**：[referenceDocxFor] 子类可 override，给某个 docType 指定
/// 学校原版 docx 模板，pandoc 转 docx 时走 `--reference-doc` 继承字体 / 页边距 /
/// 标题样式。默认从 `data/归档/<期>/模板/<docType>.docx` 自动找，找不到不传。
abstract class BaseDocumentProcessor extends DocumentProcessor {
  PandocService get pandoc => PandocService.instance;

  /// 项目根路径下"data/归档"的绝对路径。运行时由 main.dart 注入。
  /// 注：这里走桌面端文件系统路径，移动端不可用——归档功能本就只在 Windows 运行。
  static String? archiveDataRoot;

  /// 子类可 override 给特定 docType 指定 reference docx 模板路径。
  /// 默认走自动发现：`<archiveDataRoot>/<期>/模板/{docType}.docx` 或同期任一
  /// 文件名包含 [docType] 中文 keyword 的 docx。
  String? referenceDocxFor(ArchiveDocument doc) =>
      findReferenceDocx(period: doc.period, docLabel: docLabel);

  /// 静态版本：UI fallback（registry 没注册的 docType）也能复用同一套查找逻辑，
  /// 不必再造一份 `data/归档/<期>/模板/` 扫描。
  static String? findReferenceDocx({
    required String period,
    required String docLabel,
  }) {
    if (archiveDataRoot == null) return null;
    final periodZh = periods.periodLabel(period);
    final templateDir = Directory(p.join(archiveDataRoot!, periodZh, '模板'));
    if (!templateDir.existsSync()) return null;
    try {
      for (final entry in templateDir.listSync()) {
        if (entry is! File) continue;
        if (!entry.path.toLowerCase().endsWith('.docx')) continue;
        if (p.basename(entry.path).contains(docLabel)) {
          if (kDebugMode) {
            debugPrint('[BaseDocumentProcessor] reference docx for $docLabel: ${entry.path}');
          }
          return entry.path;
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('[BaseDocumentProcessor] reference docx scan failed: $e');
      }
    }
    return null;
  }

  @override
  Future<Uint8List> toDocx(ArchiveDocument doc) async {
    final content = doc.content ?? '';
    if (content.isEmpty) {
      throw StateError('文档内容为空，无法转换为 docx');
    }
    // pandoc 可套学校模板样式，优先；未安装时回退原生 OOXML 生成器（仅默认排版）。
    if (await pandoc.isInstalled) {
      try {
        return await pandoc.markdownToDocx(
          content,
          referenceDocPath: referenceDocxFor(doc),
        );
      } on PandocException catch (e) {
        if (kDebugMode) {
          debugPrint('[BaseDocumentProcessor] pandoc 失败，回退原生 docx: $e');
        }
      }
    }
    return NativeDocxService.instance.markdownToDocx(content);
  }

  @override
  Future<Uint8List> toPdf(ArchiveDocument doc) async {
    final content = doc.content ?? '';
    if (content.isEmpty) {
      throw StateError('文档内容为空，无法转换为 PDF');
    }
    return pandoc.markdownToPdf(
      content,
      referenceDocPath: referenceDocxFor(doc),
    );
  }
}
