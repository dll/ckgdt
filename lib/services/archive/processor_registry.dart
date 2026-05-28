import 'package:flutter/foundation.dart';
import 'ai_audit_processor.dart';
import 'document_processor.dart';

/// 归档文档处理器注册表（单例）。
///
/// **用途**：UI 调"一键审核 / 打印 / 归档"时，按 docType 找到对应 Processor，
/// 委托具体策略。这避免 period_tab 里出现长长的 if-else 链。
///
/// **生命周期**：app 启动时调用 [registerAll] 注册全部内置 Processor。
/// 之后通过 [find] 按 docType 查询。未注册的 docType 返回 null，UI 应回退
/// 到现有 archive_agent.generateDocument 路径（向后兼容）。
class ProcessorRegistry {
  ProcessorRegistry._();
  static final instance = ProcessorRegistry._();

  final Map<String, DocumentProcessor> _processors = {};

  /// 注册一个 Processor。重复注册同 docType 会覆盖（带警告日志）。
  void register(DocumentProcessor processor) {
    final key = processor.docType;
    if (_processors.containsKey(key)) {
      if (kDebugMode) {
        debugPrint('[ProcessorRegistry] override processor for docType=$key');
      }
    }
    _processors[key] = processor;
  }

  /// 按 docType 查找 Processor，未注册返回 null
  DocumentProcessor? find(String docType) => _processors[docType];

  /// 列出全部已注册 docType（用于诊断 / 设置页）
  List<String> get registeredDocTypes => _processors.keys.toList()..sort();

  /// 统计各 ProcessorKind 的数量
  Map<ProcessorKind, int> get kindStats {
    final result = <ProcessorKind, int>{};
    for (final p in _processors.values) {
      result[p.kind] = (result[p.kind] ?? 0) + 1;
    }
    return result;
  }

  /// 注册全部内置 Processor。
  /// commit 4: AiAuditProcessor 大纲合理性审核表 / 评价表
  /// 后续 commit 5/6/7 会逐步加 SystemImport / AiDraft 类型
  void registerAll() {
    // 大纲合理性审核表 — 审核源 docType=syllabus，结果落 docType=syllabus_review
    register(AiAuditProcessor(
      targetDocType: 'syllabus',
      targetDocLabel: '教学大纲',
      auditDocType: 'syllabus_review',
      auditDocLabel: '大纲合理性审核表',
    ));
    // 大纲合理性评价表 — 同样审核教学大纲，但出第二份评价表（二审视角）
    register(AiAuditProcessor(
      targetDocType: 'syllabus',
      targetDocLabel: '教学大纲',
      auditDocType: 'syllabus_evaluation',
      auditDocLabel: '大纲合理性评价表',
    ));
  }

  /// 测试用：清空注册表
  @visibleForTesting
  void resetForTest() => _processors.clear();
}
