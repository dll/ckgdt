import 'package:flutter/foundation.dart';
import '../agent/agents/archive_agent.dart';
import 'ai_audit_processor.dart';
import 'ai_draft_processor.dart';
import 'document_processor.dart';
import 'teaching_task_processor.dart';

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
  ///
  /// - AiAuditProcessor — 大纲合理性审核表 / 评价表
  /// - AiDraftProcessor — 所有 needsGeneration=true 的 docType（教学大纲 /
  ///           日历 / 进度表 / 教案 / 课件 / 期中试卷 / ...）
  /// 系统导入类（教学任务书 / 课表 / 学生名单）不在这里注册——它们的入口是
  /// period_tab 内的 mhtml/xlsx 解析器，按 docType=null 兜底走 PandocService。
  void registerAll() {
    // ── 系统导入处理器（教务导入，打印走原生官方版式）─────────────────
    register(TeachingTaskProcessor());

    // ── AI 审核处理器 ─────────────────────────────────────────────────
    register(AiAuditProcessor(
      targetDocType: 'syllabus',
      targetDocLabel: '教学大纲',
      auditDocType: 'syllabus_review',
      auditDocLabel: '大纲合理性审核表',
    ));
    register(AiAuditProcessor(
      targetDocType: 'syllabus',
      targetDocLabel: '教学大纲',
      auditDocType: 'syllabus_evaluation',
      auditDocLabel: '大纲合理性评价表',
    ));

    // ── AI 起草处理器 ─────────────────────────────────────────────────
    // 共享一份 ArchiveAgent 实例，避免每个 Processor 各起一次（每个会启 ai_service）
    // 不从 archive_constants 取列表（service 层不依赖 UI 层），改用本地白名单。
    // **维护点**：archive_constants 加 needsGeneration=true 的新 docType 时，
    // 这里也要加，否则该 docType 走不了 Processor 路径，UI 会回退到 archive_agent
    // 直接调用（依然能用，只是状态徽标和注册表统计漏报）。
    final agent = ArchiveAgent();
    const aiDraftDocTypes = <List<String>>[
      // [docType, label]
      ['syllabus', '教学大纲'],
      ['calendar', '教学日历'],
      ['teaching_schedule', '教学进度表'],
      ['lesson_plan', '教学教案'],
      ['courseware', '教学课件'],
      ['midterm_exam', '期中试卷'],
      ['midterm_analysis', '期中成绩分析'],
      ['midterm_check', '期中检查表'],
      ['final_exam', '期末试卷'],
      ['final_analysis', '期末成绩分析'],
      ['final_assessment', '期末考核材料'],
      ['course_summary', '课程总结'],
      ['exam_review_form', '试卷审核表'],
      ['assessment_review_form', '考核审核表'],
      ['print_report', '印刷审批表'],
      ['archive_form', '归档确认表'],
    ];
    for (final entry in aiDraftDocTypes) {
      final key = entry[0];
      final label = entry[1];
      // 已注册的 audit docType 不要被 AiDraft 覆盖
      if (_processors.containsKey(key)) continue;
      register(AiDraftProcessor(
        docTypeKey: key,
        docTypeLabel: label,
        agent: agent,
      ));
    }

    if (kDebugMode) {
      debugPrint('[ProcessorRegistry] registered ${_processors.length} '
          'processors: $kindStats');
    }
  }

  /// 测试用：清空注册表
  @visibleForTesting
  void resetForTest() => _processors.clear();
}
