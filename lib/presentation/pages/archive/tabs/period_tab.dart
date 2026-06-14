import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../../../../core/error_handler.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import '../../../../services/archive/ai_audit_processor.dart';
import '../../../../services/archive/ai_draft_processor.dart';
import '../../../../services/archive/base_document_processor.dart';
import '../../../../services/archive/pandoc_service.dart';
import '../../../../services/archive/processor_registry.dart';
import '../../../../services/archive/review_result.dart';
import '../../../../services/archive/archive_template_source_service.dart';
import '../../../../services/archive/teaching_task_pdf.dart';
import '../../../../services/archive/teaching_task_source_service.dart';
import '../../../../services/archive/importers/archive_importers.dart';
import '../../../../services/archive_package_service.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../presentation/widgets/markdown_bubble.dart';
import '../archive_constants.dart';
import '../teaching_task_authorized_fetch_page.dart';
import '../widgets/review_result_dialog.dart';

class ArchivePeriodTab extends StatefulWidget {
  final String periodKey;
  final String courseType;
  final ArchiveDao dao;
  final ArchiveAgent agent;
  final VoidCallback? onSyllabusChanged;

  /// 期中/期末等期特有的附加面板（进度一致性检查 / 考核材料统计等）。
  /// 渲染在文档卡片列表上方，随列表一起滚动。期初不传，保持纯文档流。
  final List<Widget> extraHeader;

  const ArchivePeriodTab({
    super.key,
    required this.periodKey,
    required this.courseType,
    required this.dao,
    required this.agent,
    this.onSyllabusChanged,
    this.extraHeader = const [],
  });

  @override
  State<ArchivePeriodTab> createState() => _ArchivePeriodTabState();
}

class _ArchivePeriodTabState extends State<ArchivePeriodTab> {
  List<ArchiveDocument> _documents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArchivePeriodTab old) {
    super.didUpdateWidget(old);
    if (old.courseType != widget.courseType ||
        old.periodKey != widget.periodKey) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs = await widget.dao.getDocuments(
        period: widget.periodKey,
        courseType: widget.courseType,
      );
      if (mounted) {
        setState(() {
          _documents = docs;
          _loading = false;
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DocumentTypeDef> get _expectedDocs =>
      docsForPeriod(widget.courseType, widget.periodKey);

  ArchiveDocument? _findDoc(DocumentTypeDef def) {
    for (final d in _documents) {
      if (d.documentType == def.key) return d;
    }
    return null;
  }

  bool _canAutoGenerate(DocumentTypeDef def) {
    if (def.needsGeneration) return true;
    return widget.periodKey == 'beginning' &&
        ArchiveTemplateSourceService.supportsDocument(def.key);
  }

  Future<void> _generateDoc(DocumentTypeDef def) async {
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      // 优先走 ProcessorRegistry → AiDraftProcessor.generateAsDocument
      // 内部仍委托 archive_agent，但走统一接口未来更易替换。
      // 没注册的 docType（系统导入类不会有 needsGeneration）回退原路径。
      final processor = ProcessorRegistry.instance.find(def.key);
      ArchiveDocument doc;
      if (def.key == 'teaching_task') {
        final generated = await _generateTeachingTaskFromSource();
        if (generated == null) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('未获取到可解析的教学任务书。请在教务网页登录后进入任务书打印页，或使用手动导入兜底。'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        doc = generated;
      } else if (widget.periodKey == 'beginning') {
        final generated = await _generateFromTemplate(def);
        if (generated != null) {
          doc = generated;
        } else if (!def.needsGeneration) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('未在期初/模板中找到可解析的${def.label}资料'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        } else if (processor is AiDraftProcessor) {
          doc = await processor.generateAsDocument(
            period: widget.periodKey,
            courseType: widget.courseType,
            title: title,
          );
        } else {
          doc = await widget.agent.generateDocument(
            title: title,
            documentType: def.key,
            period: widget.periodKey,
            courseType: widget.courseType,
          );
        }
      } else if (processor is AiDraftProcessor) {
        doc = await processor.generateAsDocument(
          period: widget.periodKey,
          courseType: widget.courseType,
          title: title,
        );
      } else {
        doc = await widget.agent.generateDocument(
          title: title,
          documentType: def.key,
          period: widget.periodKey,
          courseType: widget.courseType,
        );
      }
      if (mounted) Navigator.of(context).pop();
      _load();
      if (def.key == 'syllabus') widget.onSyllabusChanged?.call();
      if (mounted) _previewDoc(doc);
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._generateDoc', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生成失败，请重试')),
        );
      }
    }
  }

  void _previewDoc(ArchiveDocument doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DocumentPreviewSheet(
        doc: doc,
        pdfBuilder: _renderPdfBytes,
      ),
    );
  }

  Future<void> _printDoc(ArchiveDocument doc) async {
    if (!mounted) return;

    // 跨平台守门：移动端 / web 不支持 pandoc + libreoffice 子进程
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('一键打印仅在 Windows/macOS/Linux 桌面端可用')),
      );
      return;
    }

    final content = doc.content ?? '';
    if (content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文档内容为空，无法打印')),
      );
      return;
    }

    final loadingText = doc.documentType == 'teaching_task'
        ? '正在生成学校版式 PDF...'
        : '正在生成 PDF（pandoc + LibreOffice）...';

    // loading 提示（普通文档 pandoc + soffice 两步通常 5-15 秒）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: SizedBox(
          height: 80,
          child: Row(
            children: [
              const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 16),
              Expanded(child: Text(loadingText)),
            ],
          ),
        ),
      ),
    );

    try {
      final pdfBytes = await _renderPdfBytes(doc);
      if (!mounted) return;
      Navigator.of(context).pop(); // 关 loading

      // 唤起系统打印对话框（用户选打印机/份数/页码）
      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: doc.title,
      );
    } on PandocException catch (e) {
      swallowDebug(e, tag: 'ArchivePeriodTab._printDoc.pandoc');
      if (!mounted) return;
      Navigator.of(context).pop();
      _showPrintErrorDialog(
        title: '打印环境未就绪',
        message: e.message,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._printDoc', stack: st);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打印失败：$e')),
      );
    }
  }

  /// 走 ProcessorRegistry 拿 toPdf；未注册则用 PandocService 默认路径，
  /// 自动从 `data/归档/<期>/模板/<docType>.docx` 找 reference-doc 继承样式。
  Future<Uint8List> _renderPdfBytes(ArchiveDocument doc) async {
    final sourcePath = doc.filePath;
    if (sourcePath != null && sourcePath.toLowerCase().endsWith('.pdf')) {
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) return sourceFile.readAsBytes();
    }
    final processor = ProcessorRegistry.instance.find(doc.documentType);
    if (processor != null && processor.supportsPrint) {
      return processor.toPdf(doc);
    }
    return PandocService.instance.markdownToPdf(
      doc.content ?? '',
      referenceDocPath: BaseDocumentProcessor.findReferenceDocx(
        period: doc.period,
        docLabel: _docLabelFor(doc.documentType),
      ),
    );
  }

  void _showPrintErrorDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _reviewDoc(ArchiveDocument doc) async {
    if (!mounted) return;

    if (doc.documentType == 'teaching_task') {
      await _reviewTeachingTask(doc);
      return;
    }

    // 优先走 Processor 路径（结构化审核 + 自动创建审核表卡片）。
    // 一个目标文档可能对应多个审核处理器（如教学大纲 → 合理性审核表 + 评价表），
    // 全部运行，各自生成对应审核表卡片。其它 docType 回退到旧的 markdown 审核。
    final processors = _findAuditProcessorsFor(doc);
    if (processors.isNotEmpty) {
      await _reviewDocViaProcessors(doc, processors);
      return;
    }

    // ── 回退：旧版 markdown 审核（保留向后兼容）───────────────────────────
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final review = await widget.agent.reviewDocument(doc);
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.rate_review,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('AI 审核结果'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: MarkdownBubble(content: review),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭')),
            ],
          ),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._reviewDoc', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('审核失败，请重试')),
        );
      }
    }
  }

  Future<ReviewResult> _reviewTeachingTask(
    ArchiveDocument doc, {
    bool showResult = true,
  }) async {
    final result = TeachingTaskPdf.review(doc.content ?? '');
    final updated = doc.copyWith(
      status: result.isApproved ? 'approved' : 'reviewing',
      reviewJson: result.toJson(),
      reviewedAt: DateTime.now().toIso8601String(),
    );
    await widget.dao.saveDocument(updated);
    if (showResult && mounted) {
      await showDialog(
        context: context,
        builder: (_) => ReviewResultDialog(
          target: updated,
          initial: result,
          onUpdated: (_) => _load(),
        ),
      );
      if (mounted) await _load();
    }
    return result;
  }

  /// 查找该 doc.documentType 对应的全部 AiAuditProcessor。
  /// 一个目标（如 syllabus）可被多个审核器消费（审核表 + 评价表），全部返回。
  /// 注意：审核处理器的 targetDocType 是被审目标，遍历找 targetDocType 匹配的。
  List<AiAuditProcessor> _findAuditProcessorsFor(ArchiveDocument doc) {
    final reg = ProcessorRegistry.instance;
    final result = <AiAuditProcessor>[];
    for (final t in reg.registeredDocTypes) {
      final p = reg.find(t);
      if (p is AiAuditProcessor && p.targetDocType == doc.documentType) {
        result.add(p);
      }
    }
    return result;
  }

  /// Processor 路径：依次跑全部审核器的 reviewTarget（各自生成审核表卡片），
  /// 用最后一个结果弹 ReviewResultDialog（含三栏 + 忽略 + 再审）。
  Future<void> _reviewDocViaProcessors(
    ArchiveDocument doc,
    List<AiAuditProcessor> processors,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      ReviewResult? result;
      for (final processor in processors) {
        result = await processor.reviewTarget(doc);
      }
      if (!mounted) return;
      Navigator.of(context).pop(); // 关 loading
      if (result == null) return;

      // 重新拉一次 doc 以拿到最新的 reviewJson / status
      final fresh = await widget.dao.getDocumentById(doc.id!);
      final target = fresh ?? doc;
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => ReviewResultDialog(
          target: target,
          initial: result!,
          onUpdated: (_) => _load(), // 父级刷新文档列表（审核表自动出现）
        ),
      );
      // 对话框关闭后再刷一次（覆盖再审/忽略后的状态）
      if (mounted) await _load();
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ArchivePeriodTab._reviewDocViaProcessors', stack: st);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 审核失败：$e')),
        );
      }
    }
  }

  Future<void> _archiveDoc(ArchiveDocument doc) async {
    if (!mounted) return;

    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('一键归档仅在桌面端可用')),
      );
      return;
    }

    final content = doc.content ?? '';
    if (content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文档内容为空，无法归档')),
      );
      return;
    }

    final docLabel = _docLabelFor(doc.documentType);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Row(
            children: [
              SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('正在归档（pandoc 生成 docx 并落盘）...')),
            ],
          ),
        ),
      ),
    );

    try {
      final svc = ArchivePackageService.instance;
      final outPath = await svc.archiveDocxOf(doc, docLabel: docLabel);
      // status 流转 → archived
      await widget.dao.saveDocument(doc.copyWith(status: 'archived'));
      if (!mounted) return;
      Navigator.of(context).pop();
      _load();

      // 复制到剪贴板（QQ 群粘贴）
      await Clipboard.setData(ClipboardData(text: outPath));
      if (!mounted) return;
      _showArchivedDialog(
        title: '已归档',
        path: outPath,
        message: outPath.toLowerCase().endsWith('.pdf')
            ? '原始 PDF 已按学校命名保存，文件路径已复制到剪贴板，可直接粘贴到 QQ 群发送。'
            : doc.documentType == 'teaching_task'
                ? 'docx 与学校版式 PDF 已保存，文件路径已复制到剪贴板，可直接粘贴到 QQ 群发送。'
                : 'docx 已保存，文件路径已复制到剪贴板，可直接粘贴到 QQ 群发送。',
      );
    } on ArchivePackageException catch (e) {
      swallowDebug(e, tag: 'ArchivePeriodTab._archiveDoc.pkg');
      if (!mounted) return;
      Navigator.of(context).pop();
      _showPrintErrorDialog(title: '归档失败', message: e.message);
    } on PandocException catch (e) {
      swallowDebug(e, tag: 'ArchivePeriodTab._archiveDoc.pandoc');
      if (!mounted) return;
      Navigator.of(context).pop();
      _showPrintErrorDialog(title: '归档环境未就绪', message: e.message);
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._archiveDoc', stack: st);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('归档失败：$e')),
      );
    }
  }

  String _docLabelFor(String docType) {
    final defs = docsForCourseType(widget.courseType);
    for (final list in defs.values) {
      for (final d in list) {
        if (d.key == docType) return d.label;
      }
    }
    return docType;
  }

  /// 归档完成提示：显示文件路径 + 「打开文件夹 / 复制路径 / 关闭」三个动作
  void _showArchivedDialog({
    required String title,
    required String path,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            SelectableText(
              path,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('打开文件夹'),
            onPressed: () async {
              await ArchivePackageService.instance.revealInFileManager(path);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('再次复制'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDoc(ArchiveDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除"${doc.title}"？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && doc.id != null) {
      await widget.dao.deleteDocument(doc.id!);
      _load();
    }
  }

  Future<void> _importDoc(DocumentTypeDef def) async {
    if (!mounted) return;
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';

    if (def.key == 'teaching_task') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mhtml', 'mht', 'htm', 'html'],
        dialogTitle: '选择教学任务书文件（教务系统 MHTML 或 HTML）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final html = await file.readAsString();
      final parsed = ArchiveImporters.parseTeachingTask(html);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('未找到"移动应用开发"课程数据，请确认HTML文件内容'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从教务系统导入教学任务书：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'course_schedule') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        dialogTitle: '选择课表Excel文件',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      String? parsed;
      Set<String> foundNames = {};
      try {
        final result = ArchiveImporters.parseCourseSchedule(bytes);
        parsed = result.markdown;
        foundNames = result.allCourseNames;
      } catch (e, st) {
        swallowDebug(e, tag: 'ArchivePeriodTab._importDoc.xlsx', stack: st);
      }
      if (parsed == null) {
        if (mounted) {
          final found = foundNames.take(10).join('、');
          final msg = found.isNotEmpty
              ? '课表中未找到"移动应用开发"课程。找到的课程：$found'
              : '未在课表中找到"移动应用开发"课程，请确认Excel文件包含"课程名称"列';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(msg),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5)),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从Excel导入课程课表：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'calendar') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mhtml', 'mht', 'htm', 'html'],
        dialogTitle: '选择校历文件（从教务系统另存为.mhtml）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final raw = await file.readAsString();
      final parsed = ArchiveImporters.parseCalendar(raw);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('校历解析失败，请确认文件为完整的MHTML格式'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入校历：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'roll_call') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mhtml', 'mht', 'htm', 'html'],
        dialogTitle: '选择考勤表文件（另存为.mhtml）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final raw = await file.readAsString();
      final parsed = ArchiveImporters.parseRollCall(raw);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('未找到"移动应用开发"点名册数据，请确认MHTML文件内容'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从教务系统导入学生点名册：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'syllabus') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'htm', 'html'],
        dialogTitle: '选择教学大纲文件（txt/md/html）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final parsed = await file.readAsString();
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed.trim(),
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      widget.onSyllabusChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入教学大纲：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'teaching_schedule') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt', 'htm', 'html'],
        dialogTitle: '选择教学进度表文件（md/txt/html）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final parsed = await file.readAsString();
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed.trim(),
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入教学进度表：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'syllabus_evaluation' ||
        def.key == 'syllabus_review' ||
        def.key == 'teacher_guide' ||
        def.key == 'student_guide' ||
        def.key == 'assessment_plan') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
        dialogTitle: '选择${def.label}文件（docx）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      final text = ArchiveImporters.extractDocxText(bytes);
      if (text == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('解析docx文件失败，请确认文件格式'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: text.trim(),
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入${def.label}：${doc.title}')),
        );
      }
      return;
    }

    if (def.key == 'survey') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mhtml', 'mht', 'htm', 'html'],
        dialogTitle: '选择问卷文件（从教务系统另存为.mhtml）',
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final raw = await file.readAsString();
      final parsed = ArchiveImporters.parseSurvey(raw);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('问卷解析失败，请确认文件为完整的MHTML格式'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: parsed,
        filePath: file.path,
        isGenerated: false,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入问卷：${doc.title}')),
        );
      }
      return;
    }

    final doc = ArchiveDocument(
      title: title,
      documentType: def.key,
      period: widget.periodKey,
      courseType: widget.courseType,
      content: '（已从${_importSource(def.key)}导入）',
    );
    await widget.dao.saveDocument(doc);
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从${_importSource(def.key)}导入：${def.label}')),
      );
    }
  }

  Future<ArchiveDocument?> _generateFromTemplate(DocumentTypeDef def) async {
    final parsed = await ArchiveTemplateSourceService.parseBestSource(
      periodKey: widget.periodKey,
      documentType: def.key,
      label: def.label,
    );
    if (parsed == null) return null;
    final doc = ArchiveDocument(
      title: '${periodLabel(widget.periodKey)}${def.label}',
      documentType: def.key,
      period: widget.periodKey,
      courseType: widget.courseType,
      content: parsed.content,
      filePath: parsed.sourcePath,
      isGenerated: false,
    );
    final id = await widget.dao.saveDocument(doc);
    if (def.key == 'syllabus') widget.onSyllabusChanged?.call();
    return doc.copyWith(id: id);
  }

  Future<ArchiveDocument?> _generateTeachingTaskFromSource() async {
    final teachingDef =
        _expectedDocs.where((d) => d.key == 'teaching_task').firstOrNull;
    if (teachingDef == null) return null;
    final stored = await TeachingTaskSourceService.parseBestStoredSource(
      periodKey: widget.periodKey,
    );
    if (stored != null) {
      return _saveTeachingTaskDocument(teachingDef, stored);
    }
    final fetched = await _captureTeachingTaskFromWeb();
    if (fetched == null) return null;
    return _saveTeachingTaskDocument(teachingDef, fetched);
  }

  Future<TeachingTaskParseResult?> _captureTeachingTaskFromWeb() async {
    if (!mounted) return null;
    final result =
        await Navigator.of(context).push<TeachingTaskAuthorizedFetchResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const TeachingTaskAuthorizedFetchPage(),
      ),
    );
    if (result == null) return null;

    final sourceFile = await TeachingTaskSourceService.saveFetchedHtml(
      periodKey: widget.periodKey,
      html: result.html,
    );
    final parsed = ArchiveImporters.parseTeachingTask(result.html);
    if (parsed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('当前网页未解析出教学任务书课程行，原始页面已保存：${sourceFile.path}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return null;
    }
    return TeachingTaskParseResult(
      markdown: parsed,
      sourcePath: sourceFile.path,
      sourceLabel: '网页登录授权获取',
    );
  }

  Future<ArchiveDocument> _saveTeachingTaskDocument(
    DocumentTypeDef def,
    TeachingTaskParseResult source,
  ) async {
    final doc = ArchiveDocument(
      title: '${periodLabel(widget.periodKey)}${def.label}',
      documentType: def.key,
      period: widget.periodKey,
      courseType: widget.courseType,
      content: source.markdown,
      filePath: source.sourcePath,
      isGenerated: false,
    );
    final id = await widget.dao.saveDocument(doc);
    return doc.copyWith(id: id);
  }

  Future<void> _fetchLatestTeachingTaskFromWeb(DocumentTypeDef def) async {
    final source = await _captureTeachingTaskFromWeb();
    if (source == null) return;
    final doc = await _saveTeachingTaskDocument(def, source);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已通过教务网页登录获取：${doc.title}')),
    );
    _previewDoc(doc);
  }

  Future<void> _showSourceInfo(DocumentTypeDef def) async {
    final detail = _sourceDetail(def.key);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${def.label} — 来源说明',
                    style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sourceLine('文档', def.label),
              const SizedBox(height: 8),
              _sourceLine('来源系统', detail['system'] ?? ''),
              if ((detail['description'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                _sourceLine('说明', detail['description']!),
              ],
              if (detail['url'] != null) ...[
                const SizedBox(height: 8),
                _sourceLine('访问地址', detail['url']!),
              ],
            ],
          ),
        ),
        actions: [
          if (def.key == 'teaching_task')
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _fetchLatestTeachingTaskFromWeb(def);
              },
              icon: const Icon(Icons.public, size: 18),
              label: const Text('网页登录获取'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  Widget _sourceLine(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text('$label：',
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Map<String, String> _sourceDetail(String key) {
    switch (key) {
      case 'teaching_task':
        return {
          'system': '教务管理系统（jwgl.chzu.edu.cn/eams/）',
          'url': TeachingTaskSourceService.printLessonBookUrl,
          'description':
              '主流程为网页登录授权后读取“打印教学任务书”页面 HTML，自动结构化生成学校版式归档件；手动导入仅作为无网络或 WebView 不可用时的兜底。',
        };
      case 'syllabus':
        return {
          'system': '学院 / 教师编写（Markdown）',
          'description':
              '教师根据学院规范编写的Markdown教学大纲，课程编码 d203010351/d203010092，含7章教学内容、4项课程目标及考核标准',
        };
      case 'syllabus_evaluation':
        return {
          'system': '学院课程群建设工作组',
          'description':
              '计算机与信息工程学院课程教学大纲合理性评价表，含10项评价指标、课程群建设工作组意见、学院教学指导委员会意见，docx格式',
        };
      case 'syllabus_review':
        return {
          'system': '学院教学指导委员会',
          'description':
              '移动应用开发课程过程性考核合理性审核表，依据2023版人才培养方案，含课程目标-毕业要求对应关系、考核方式及成绩评定对照表（平时20%+实验30%+期末50%），docx格式',
        };
      case 'calendar':
        return {
          'system': '校历系统（webvpn.chzu.edu.cn）',
          'description':
              '滁州学院校历（2025-2026第二学期），通过学校WebVPN网关访问的React SPA页面，从浏览器保存为MHTML/HTML文件',
        };
      case 'course_schedule':
        return {
          'system': '实验教学服务平台',
          'description':
              '实验教学服务平台 → 实践教学 → 课表查询 → 我的课表 导出XLSX文件。含★教务（排课）和○实验两种类型标记',
        };
      case 'teaching_schedule':
        return {
          'system': '教师编写（Markdown）',
          'description':
              '教师根据教学大纲编写的16周教学进度表（2026年3月2日-6月21日），含6个实验项目及平时20%+实验30%+期末50%考核比例',
        };
      case 'lesson_plan':
        return {
          'system': 'AI生成 / 教师自备',
          'description': '由教师编写或通过AI辅助生成，每讲一份教案',
        };
      case 'courseware':
        return {
          'system': '课件库 / AI生成',
          'description': '教师自备课件上传，或使用AI自动生成课件',
        };
      case 'roll_call':
        return {
          'system': '教务管理系统（jwgl.chzu.edu.cn/eams/）',
          'description':
              '从 homeExt.action# 进入 → 打印点名册 → 浏览器另存为MHTML文件。URL路径: courseTableForTeacher!printAttendanceCheckList.action，含85名学生（软件231/232）考勤记录',
        };
      case 'teacher_guide':
        return {
          'system': '学院',
          'description': '学院编制的教师教学指导手册docx文档，含课程定位、教学目标、教学内容结构和考核方式说明',
        };
      case 'student_guide':
        return {
          'system': '学院',
          'description': '学院编制的学生学习指导手册docx文档，含课程结构、各章学习要点、实验指导和考核说明',
        };
      case 'assessment_plan':
        return {
          'system': '学院',
          'description':
              '学院编制的综合考核方案docx文档（V1.0版），以SmartCampus智慧校园项目为载体，含4种技术栈的团队项目考核（每组6人，15天）',
        };
      case 'survey':
        return {
          'system': '教务管理系统（jwgl.chzu.edu.cn/eams/）',
          'description':
              '课表查询 → 课表查询（实时课表）→ 打印教学任务书 → 浏览器另存为MHTML文件。URL: courseTableForTeacher!printLessonBook.mhtml，含课程教学问卷数据',
        };
      default:
        return {
          'system': '外部系统',
          'description': '请根据具体材料要求准备',
        };
    }
  }

  Future<void> _downloadTemplate(DocumentTypeDef def) async {
    if (!mounted) return;

    String content;
    String filename;
    String mimeType;

    switch (def.key) {
      case 'teaching_task':
        content = '''<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>教学任务书模板</title></head>
<body>
<p>经学校批准聘请<input type="text" placeholder="教师姓名" size="10">老师担任<input type="text" placeholder="学期" size="20">学期以下教学任务：</p>
<table border="1" cellpadding="4" style="border-collapse:collapse;width:100%">
<tr>
  <th>课程名称</th><th>课程类别</th><th>总学时</th><th>讲授</th><th>实验</th><th>实践</th><th>课外自主</th><th>教学班级</th><th>计划人数</th><th>备注</th>
</tr>
<tr>
  <td>移动应用开发</td><td>考试</td><td>64</td><td>32</td><td>16</td><td>8</td><td>8</td><td>计科22</td><td>40</td><td></td>
</tr>
</table>
</body>
</html>''';
        filename = '教学任务书模板.html';
        mimeType = 'text/html';
        break;
      case 'syllabus':
        content = '''# 教学大纲模板

## 一、课程基本信息
- **课程名称**：[请填写]
- **课程编码**：[请填写]
- **课程类别**：[考试/考查]
- **总学时**：[请填写]
- **讲授学时**：[请填写]
- **实验/实践学时**：[请填写]
- **学分**：[请填写]
- **适用专业**：[请填写]
- **先修课程**：[请填写]

## 二、课程目标
[请描述本课程的总体教学目标]

## 三、教学内容与学时分配
| 章节 | 内容 | 学时 | 教学方式 |
|------|------|------|----------|
| 第1章 | [标题] | [学时] | [讲授/实验] |
| 第2章 | [标题] | [学时] | [讲授/实验] |

## 四、考核方式
- 平时成绩：[比例]%
- 实验成绩：[比例]%
- 期末成绩：[比例]%

## 五、教材与参考书
- 教材：[请填写]
- 参考书：[请填写]''';
        filename = '教学大纲模板.md';
        mimeType = 'text/markdown';
        break;
      case 'syllabus_evaluation':
        content = '''# 大纲合理性评价表模板

## 评价项目
- **大纲名称**：[请填写]
- **评价人**：[请填写]
- **评价日期**：[请填写]

## 评价内容
| 评价指标 | 评价等级（优/良/中/差） | 评价意见 |
|----------|-------------------------|----------|
| 课程目标与人才培养方案符合度 | [优/良/中/差] | [评价意见] |
| 教学内容完整性 | [优/良/中/差] | [评价意见] |
| 学时分配合理性 | [优/良/中/差] | [评价意见] |
| 考核方式科学性 | [优/良/中/差] | [评价意见] |
| 教材选用恰当性 | [优/良/中/差] | [评价意见] |

## 综合评价意见
[请填写综合评价意见]

## 评价结论
[通过/修改后通过/不通过]''';
        filename = '大纲合理性评价表模板.md';
        mimeType = 'text/markdown';
        break;
      case 'syllabus_review':
        content = '''# 大纲合理性审核表模板

## 审核项目
- **大纲名称**：[请填写]
- **审核人（教研室主任）**：[请填写]
- **审核日期**：[请填写]

## 审核要点
| 审核内容 | 是否合格 | 审核意见 |
|----------|----------|----------|
| 课程目标是否明确、可衡量 | [是/否] | [审核意见] |
| 教学内容是否支撑课程目标 | [是/否] | [审核意见] |
| 学时分配是否合理 | [是/否] | [审核意见] |
| 考核方式是否与目标对应 | [是/否] | [审核意见] |
| 教材选用是否恰当 | [是/否] | [审核意见] |

## 审核结论
[通过/修改后通过/不通过]

## 审核意见
[请填写详细审核意见]''';
        filename = '大纲合理性审核表模板.md';
        mimeType = 'text/markdown';
        break;
      case 'calendar':
        content = '''<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>教学日历模板</title></head>
<body>
<h2>教学日历</h2>
<p><b>课程名称：</b>移动应用开发</p>
<p><b>学期：</b>[请填写]</p>
<p><b>授课教师：</b>[请填写]</p>
<table border="1" cellpadding="4" style="border-collapse:collapse;width:100%">
<tr><th>周次</th><th>日期</th><th>教学内容</th><th>教学方式</th><th>学时</th><th>地点</th></tr>
<tr><td>第1周</td><td></td><td></td><td>讲授</td><td>4</td><td></td></tr>
<tr><td>第2周</td><td></td><td></td><td>讲授</td><td>4</td><td></td></tr>
<tr><td>第3周</td><td></td><td></td><td>讲授</td><td>4</td><td></td></tr>
</table>
</body>
</html>''';
        filename = '教学日历模板.html';
        mimeType = 'text/html';
        break;
      case 'course_schedule':
        content = '''# 课程课表模板

## Excel导入格式说明
课表XLSX文件需包含以下列（从教务系统导出即可，无需手动创建）：

| 列名 | 说明 | 示例 |
|------|------|------|
| 课程名称 | 课程全称 | 移动应用开发 |
| 课程类型 | 理论课/实验课 | 理论课 |
| 授课教师 | 教师姓名 | 张三 |
| 上课时间 | 时间安排 | 周一1-2节 |
| 上课地点 | 教室/实验室 | YF3404 |
| 教学周次 | 起止周 | 1-16 |
| 教学班级 | 班级名称 | 计科22 |

**注意事项：**
1. 请从教务系统直接导出XLSX文件
2. 课程类型列应包含"理论"字段
3. 课程名称列应包含"移动应用开发"''';
        filename = '课程课表导入说明.md';
        mimeType = 'text/markdown';
        break;
      case 'teaching_schedule':
        content = '''# 教学进度表模板

**课程名称**：移动应用开发
**学期**：[请填写]
**授课教师**：[请填写]

| 周次 | 章节 | 教学内容 | 学时 | 教学方式 | 备注 |
|------|------|----------|------|----------|------|
| 1 | 第1章 | [填写教学内容] | 4 | 讲授 | |
| 2 | 第1章 | [填写教学内容] | 4 | 讲授 | |
| 3 | 第2章 | [填写教学内容] | 4 | 讲授 | |
| 4 | 第2章 | [填写教学内容] | 4 | 实验 | |
| 5 | 第3章 | [填写教学内容] | 4 | 讲授 | |
| 6 | 第3章 | [填写教学内容] | 4 | 实验 | |
| 7 | 第4章 | [填写教学内容] | 4 | 讲授 | |
| 8 | 第4章 | [填写教学内容] | 4 | 实验 | |
| 9 | 期中 | 期中测验 | 4 | 测验 | |
| 10 | 第5章 | [填写教学内容] | 4 | 讲授 | |
| 11 | 第5章 | [填写教学内容] | 4 | 实验 | |
| 12 | 第6章 | [填写教学内容] | 4 | 讲授 | |
| 13 | 第6章 | [填写教学内容] | 4 | 实验 | |
| 14 | 实验 | 综合实验 | 4 | 实验 | |
| 15 | 实验 | 综合实验 | 4 | 实验 | |
| 16 | 复习 | 期末复习 | 4 | 讲授 | |''';
        filename = '教学进度表模板.md';
        mimeType = 'text/markdown';
        break;
      case 'lesson_plan':
        content = '''# 教学教案模板

**课程名称**：[请填写]
**教师**：[请填写]
**章节**：[请填写]
**学时**：[请填写]

## 教学目标
[请填写本讲教学目标]

## 教学重点与难点
- **重点**：[请填写]
- **难点**：[请填写]

## 教学内容
### 1. 导入（5分钟）
[导入内容]

### 2. 新课讲授（XX分钟）
[讲授内容]

### 3. 课堂练习（XX分钟）
[练习内容]

### 4. 小结（5分钟）
[小结内容]

## 教学资源
- 课件：[文件名]
- 参考资料：[文件名]

## 课后作业
[作业内容]''';
        filename = '教学教案模板.md';
        mimeType = 'text/markdown';
        break;
      case 'courseware':
        content = '''# 教学课件模板

## 课件要求
- 请提交PPT/PDF格式的课件文件
- 课件应覆盖教学大纲规定的全部章节
- 每章讲课时数请参考教学进度表

## 技术支持
如需帮助生成课件，可使用 "一键生成" 功能通过AI自动生成。''';
        filename = '教学课件说明.md';
        mimeType = 'text/markdown';
        break;
      case 'roll_call':
        content = '''<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>学生点名册模板</title></head>
<body>
<h2>学生点名册</h2>
<p><b>课程名称：</b>移动应用开发</p>
<p><b>学期：</b>[请填写]</p>
<table border="1" cellpadding="4" style="border-collapse:collapse;width:100%">
<tr><th>序号</th><th>学号</th><th>姓名</th><th>班级</th><th>第1周</th><th>第2周</th><th>...</th><th>备注</th></tr>
<tr><td>1</td><td>20220101</td><td>[姓名]</td><td>计科22</td><td>✓</td><td>✓</td><td></td><td></td></tr>
<tr><td>2</td><td>20220102</td><td>[姓名]</td><td>计科22</td><td>✓</td><td>请假</td><td></td><td></td></tr>
</table>
</body>
</html>''';
        filename = '学生点名册模板.html';
        mimeType = 'text/html';
        break;
      case 'teacher_guide':
        content = '''# 教师教学指导手册模板

## 课程定位与目标
**课程名称**：移动应用开发
**适用专业**：[请填写]
**总学时**：[请填写]（理论[ ]学时 + 实验[ ]学时）
**学分**：[请填写]
**课程性质**：[专业核心课/选修课]

## 课程教学目标
### 知识目标
[请填写知识目标]

### 能力目标
[请填写能力目标]

### 素质目标
[请填写素质目标]

## 教学内容与学时分配
| 章节 | 内容 | 理论学时 | 实验学时 |
|------|------|----------|----------|
| 第1章 | 移动应用开发技术体系全景 | | |
| 第2章 | Android与iOS原生开发基础 | | |
| 第3章 | 混合开发技术（Flutter等） | | |
| 第4章 | 微信小程序开发 | | |
| 第5章 | 华为HarmonyOS多端应用开发 | | |
| 第6章 | 综合开发实践 | | |

## 教学方法建议
[请填写教学方法建议]

## 考核方式
- 平时成绩：[ ]%
- 实验成绩：[ ]%
- 期末成绩：[ ]%

## 教学资源
- 教材：[请填写]
- 参考书：[请填写]
- 在线资源：[请填写]''';
        filename = '教师教学指导手册模板.md';
        mimeType = 'text/markdown';
        break;
      case 'student_guide':
        content = '''# 学生学习指导手册模板

## 课程概述
**课程名称**：移动应用开发
**总学时**：[请填写]
**学分**：[请填写]

## 课程结构
| 模块 | 内容 | 学时 |
|------|------|------|
| 理论教学 | 6章系统知识 | 24 |
| 实验实践 | 7个综合项目 | 24 |
| 综合考核 | 团队项目 | 15天 |

## 各章学习要点
### 第1章 移动应用开发技术体系全景
- 学习重点：[请填写]
- 学习建议：[请填写]

### 第2章 Android与iOS原生开发基础
- 学习重点：[请填写]
- 学习建议：[请填写]

### 第3章 混合开发技术
- 学习重点：[请填写]
- 学习建议：[请填写]

### 第4章 微信小程序开发
- 学习重点：[请填写]
- 学习建议：[请填写]

### 第5章 华为HarmonyOS多端应用开发
- 学习重点：[请填写]
- 学习建议：[请填写]

### 第6章 综合开发实践
- 学习重点：[请填写]
- 学习建议：[请填写]

## 实验指导
[请填写各实验项目说明]

## 考核说明
- 考核方式：[请填写]
- 评分标准：[请填写]''';
        filename = '学生学习指导手册模板.md';
        mimeType = 'text/markdown';
        break;
      case 'assessment_plan':
        content = '''# 综合考核方案模板

## 考核目标
[请填写本课程的考核目标]

## 考核对象
- 专业：[请填写]
- 年级：[请填写]
- 人数：[请填写]

## 考核形式
### 平时考核（[ ]%）
- 作业：[ ]次，占比[ ]%
- 课堂表现：[ ]%
- 考勤：[ ]%

### 实验考核（[ ]%）
- 实验项目：[ ]个
- 实验报告：[ ]%
- 实验操作：[ ]%

### 期末考核（[ ]%）
- 考试形式：[闭卷/开卷/项目]
- 考试时间：[ ]分钟

## 项目考核（如适用）
### 项目分组
- 每组人数：[ ]人
- 组数：[ ]组

### 项目要求
[请填写项目要求]

### 评分标准
| 评分项 | 分值 | 评分标准 |
|--------|------|----------|
| 功能完整性 | [ ]分 | |
| 代码质量 | [ ]分 | |
| UI设计 | [ ]分 | |
| 创新性 | [ ]分 | |
| 团队协作 | [ ]分 | |
| 答辩表现 | [ ]分 | |

## 成绩评定
[请填写成绩评定方法]''';
        filename = '综合考核方案模板.md';
        mimeType = 'text/markdown';
        break;
      default:
        content = '# ${def.label}模板\n\n请按照系统规范格式准备${def.label}内容。';
        filename = '${def.key}模板.md';
        mimeType = 'text/markdown';
    }

    if (!mounted) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存${def.label}模板',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: [mimeType == 'text/html' ? 'html' : 'md'],
    );
    if (result == null) return;
    try {
      final file = File(result);
      await file.writeAsString(content, encoding: utf8);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('模板已保存：$filename')),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._downloadTemplate', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模板保存失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _importSource(String key) {
    switch (key) {
      case 'teaching_task':
        return '教务系统';
      case 'syllabus':
        return '学院';
      case 'syllabus_evaluation':
        return '学院';
      case 'syllabus_review':
        return '学院';
      case 'calendar':
        return '校历';
      case 'course_schedule':
        return '实验教学服务平台';
      case 'teaching_schedule':
        return '外部系统';
      case 'lesson_plan':
        return '外部系统';
      case 'courseware':
        return '课件库';
      case 'roll_call':
        return '教务系统';
      case 'teacher_guide':
        return '学院';
      case 'student_guide':
        return '学院';
      case 'assessment_plan':
        return '学院';
      case 'survey':
        return '教务系统';
      default:
        return '外部系统';
    }
  }

  Future<void> _createDoc(DocumentTypeDef def) async {
    if (!mounted) return;
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';
    // 打开模板编辑
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('新建${def.label}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请填写教学进度表内容：', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: '输入教学进度安排...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final doc = ArchiveDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
        content: result,
        isGenerated: true,
      );
      await widget.dao.saveDocument(doc);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建：${def.label}')),
        );
      }
    }
  }

  Future<ArchiveDocument?> _doGenerate(DocumentTypeDef def) async {
    final label = periodLabel(widget.periodKey);
    final title = '$label${def.label}';
    try {
      if (def.key == 'teaching_task') {
        return _generateTeachingTaskFromSource();
      }
      if (widget.periodKey == 'beginning') {
        final fromTemplate = await _generateFromTemplate(def);
        if (fromTemplate != null || !def.needsGeneration) {
          return fromTemplate;
        }
      }
      return await widget.agent.generateDocument(
        title: title,
        documentType: def.key,
        period: widget.periodKey,
        courseType: widget.courseType,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._doGenerate', stack: st);
      return null;
    }
  }

  Future<void> _generateAll() async {
    int sourced = 0;
    final order = widget.periodKey == 'beginning'
        ? _expectedDocs.map((d) => d.key).toList()
        : _expectedDocs.where(_canAutoGenerate).map((d) => d.key).toList();
    final toGenerate = order
        .map((key) => _expectedDocs.where((d) => d.key == key).firstOrNull)
        .whereType<DocumentTypeDef>()
        .where(_canAutoGenerate)
        .where((d) => _findDoc(d) == null)
        .toList();
    if (toGenerate.isEmpty) {
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    int success = 0;
    for (final def in toGenerate) {
      final doc = await _doGenerate(def);
      if (doc != null) {
        success++;
        if ((doc.filePath ?? '').isNotEmpty) sourced++;
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('已获取 $sourced 份源材料，生成 $success/${toGenerate.length} 份文档')),
      );
    }
  }

  Future<void> _reviewAll() async {
    final toReview = _documents
        .where((d) => d.content != null && d.content!.isNotEmpty)
        .toList();
    if (toReview.isEmpty) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final results = <String>[];
    for (final doc in toReview) {
      try {
        final review = await _reviewDocForBatch(doc);
        if (review != null && review.trim().isNotEmpty) {
          results.add('### ${doc.title}\n\n$review');
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'ArchivePeriodTab._reviewAll', stack: st);
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
      if (results.isNotEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.rate_review,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('审核结果 (${results.length}/${toReview.length})'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: MarkdownBubble(content: results.join('\n\n---\n\n')),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭')),
            ],
          ),
        );
      }
    }
  }

  Future<String?> _reviewDocForBatch(ArchiveDocument doc) async {
    if (doc.documentType == 'teaching_task') {
      final result = await _reviewTeachingTask(doc, showResult: false);
      return result.toMarkdown(title: '教学任务单结构化审核');
    }

    final processors = _findAuditProcessorsFor(doc);
    if (processors.isNotEmpty) {
      ReviewResult? result;
      for (final processor in processors) {
        result = await processor.reviewTarget(doc);
      }
      return result?.toMarkdown(title: '${doc.title}审核结果');
    }

    return widget.agent.reviewDocument(doc);
  }

  Future<void> _printAll() async {
    final toPrint =
        _expectedDocs.where((d) => d.canPrint && _findDoc(d) != null).toList();
    if (toPrint.isEmpty) return;
    // 顺序触发，每次都唤起系统打印框；用户可在框内取消跳过该份
    for (final def in toPrint) {
      final doc = _findDoc(def)!;
      if (!mounted) return;
      await _printDoc(doc);
    }
  }

  Future<void> _archiveAll() async {
    if (!mounted) return;

    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('一键归档仅在桌面端可用')),
      );
      return;
    }

    final toArchive =
        _documents.where((d) => (d.content ?? '').trim().isNotEmpty).toList();
    if (toArchive.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前期没有可归档的文档')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Row(
            children: [
              SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('正在归档当前期所有文档并打包 zip...')),
            ],
          ),
        ),
      ),
    );

    int success = 0;
    final failures = <String>[];
    String? lastSampleDocPath;
    final svc = ArchivePackageService.instance;
    ArchiveNaming? naming;
    try {
      // 用第一份非空文档算 naming（教师/课程/学期相同）
      naming = await svc.buildNaming(
        doc: toArchive.first,
        docLabel: _docLabelFor(toArchive.first.documentType),
      );

      for (final doc in toArchive) {
        try {
          final docLabel = _docLabelFor(doc.documentType);
          final path = await svc.archiveDocxOf(
            doc,
            docLabel: docLabel,
            naming: naming.copyWith(docLabel: docLabel),
          );
          await widget.dao.saveDocument(doc.copyWith(status: 'archived'));
          success++;
          lastSampleDocPath = path;
        } on Exception catch (e, st) {
          swallowDebug(e, tag: 'ArchivePeriodTab._archiveAll.one', stack: st);
          failures.add('${doc.title}: $e');
        }
      }

      if (success == 0) {
        if (!mounted) return;
        Navigator.of(context).pop();
        _showPrintErrorDialog(
          title: '归档全部失败',
          message: failures.isEmpty ? '未知错误' : failures.join('\n'),
        );
        return;
      }

      // 打 zip
      final zipPath = await svc.zipPeriod(
        period: widget.periodKey,
        naming: naming,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _load();

      // 复制 zip 路径到剪贴板
      await Clipboard.setData(ClipboardData(text: zipPath));
      if (!mounted) return;
      _showArchivedDialog(
        title: '本期已归档（$success/${toArchive.length}）',
        path: zipPath,
        message: failures.isEmpty
            ? 'zip 已生成，路径已复制。教学任务单等官方版式 PDF 会随包归档，粘贴到 QQ 群即可分享，或拖动文件到群窗口。'
            : '$success 份归档成功，${failures.length} 份失败。zip 已生成，路径已复制。\n\n失败列表：\n${failures.join('\n')}',
      );
    } on ArchivePackageException catch (e) {
      swallowDebug(e, tag: 'ArchivePeriodTab._archiveAll.pkg');
      if (!mounted) return;
      Navigator.of(context).pop();
      _showPrintErrorDialog(title: '归档失败', message: e.message);
      // 即便 zip 失败，已写入的 docx 仍能在文件夹里手动找到
      if (lastSampleDocPath != null) {
        await svc.revealInFileManager(lastSampleDocPath);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._archiveAll', stack: st);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('归档失败：$e')),
      );
    }
  }

  /// 全期合并打包：把 期初/期中/期末/归档 四目录的 docx 打成一个 zip。
  Future<void> _zipAllPeriods() async {
    if (!mounted) return;
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全期打包仅在桌面端可用')),
      );
      return;
    }
    final sample =
        _documents.where((d) => (d.content ?? '').trim().isNotEmpty).toList();
    if (sample.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无已归档内容可合并，请先在各期完成归档')),
      );
      return;
    }
    final svc = ArchivePackageService.instance;
    try {
      final naming = await svc.buildNaming(
        doc: sample.first,
        docLabel: _docLabelFor(sample.first.documentType),
      );
      final zipPath = await svc.zipAllPeriods(naming);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: zipPath));
      _showArchivedDialog(
        title: '全期已合并打包',
        path: zipPath,
        message: '已把全部期的归档 docx 合并为一个 zip，路径已复制到剪贴板。',
      );
    } on ArchivePackageException catch (e) {
      swallowDebug(e, tag: 'ArchivePeriodTab._zipAllPeriods.pkg');
      if (!mounted) return;
      _showPrintErrorDialog(title: '全期打包失败', message: e.message);
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._zipAllPeriods', stack: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('全期打包失败：$e')),
      );
    }
  }

  Widget _buildActionBar() {
    final primary = Theme.of(context).colorScheme.primary;
    final hasUnfinished =
        _expectedDocs.any((d) => _canAutoGenerate(d) && _findDoc(d) == null);
    final hasUnreviewed =
        _documents.any((d) => d.content != null && d.content!.isNotEmpty);
    final hasUnprinted =
        _expectedDocs.any((d) => d.canPrint && _findDoc(d) != null);
    final hasUnarchived = _documents.any((d) => d.status != 'archived');

    Widget chip(IconData icon, String label, bool enabled, [Color? color]) {
      final c = color ?? primary;
      return Material(
        color: enabled ? c.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => _onBatchAction(label) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: enabled ? c : Colors.grey),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: enabled ? c : Colors.grey,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.03),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          chip(Icons.auto_awesome, '一键生成', hasUnfinished),
          const SizedBox(width: 6),
          chip(Icons.rate_review_outlined, '一键审核', hasUnreviewed, Colors.teal),
          const SizedBox(width: 6),
          chip(Icons.print, '一键打印', hasUnprinted),
          const SizedBox(width: 6),
          chip(Icons.archive, '一键归档', hasUnarchived, Colors.green),
          const SizedBox(width: 6),
          chip(Icons.folder_zip, '全期打包', true, Colors.deepPurple),
        ],
      ),
    );
  }

  void _onBatchAction(String label) {
    switch (label) {
      case '一键生成':
        _generateAll();
        break;
      case '一键审核':
        _reviewAll();
        break;
      case '一键打印':
        _printAll();
        break;
      case '一键归档':
        _archiveAll();
        break;
      case '全期打包':
        _zipAllPeriods();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final docs = _expectedDocs;
    final hasHeader = widget.extraHeader.isNotEmpty;
    final cards = <Widget>[];
    for (var i = 0; i < docs.length; i++) {
      final def = docs[i];
      final doc = _findDoc(def);
      cards.add(DocCard(
        def: def,
        ordinal: i + 1,
        doc: doc,
        source: _importSource(def.key),
        onShowSource: () => _showSourceInfo(def),
        onDownloadTemplate: def.canImport ? () => _downloadTemplate(def) : null,
        onImport: def.canImport ? () => _importDoc(def) : null,
        onCreate: def.canCreate ? () => _createDoc(def) : null,
        onGenerate: _canAutoGenerate(def) ? () => _generateDoc(def) : null,
        onReview: doc != null ? () => _reviewDoc(doc) : null,
        onPreview: doc != null ? () => _previewDoc(doc) : null,
        onPrint: (doc != null && def.canPrint) ? () => _printDoc(doc) : null,
        onArchive: doc != null && doc.status != 'archived'
            ? () => _archiveDoc(doc)
            : null,
        onDelete: doc != null ? () => _deleteDoc(doc) : null,
      ));
    }

    final body = cards.isEmpty && !hasHeader
        ? const [
            SizedBox(height: 80),
            Center(
                child: Text('暂无配置的文档类型', style: TextStyle(color: Colors.grey))),
          ]
        : cards;

    return Column(
      children: [
        if (docs.isNotEmpty) _buildActionBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...widget.extraHeader,
                if (hasHeader && cards.isNotEmpty) const SizedBox(height: 12),
                ...body,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DocCard extends StatelessWidget {
  final DocumentTypeDef def;
  final int ordinal;
  final ArchiveDocument? doc;
  final String source;
  final VoidCallback? onShowSource;
  final VoidCallback? onDownloadTemplate;
  final VoidCallback? onGenerate;
  final VoidCallback? onImport;
  final VoidCallback? onCreate;
  final VoidCallback? onPreview;
  final VoidCallback? onReview;
  final VoidCallback? onPrint;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;

  const DocCard({
    super.key,
    required this.def,
    required this.ordinal,
    this.doc,
    required this.source,
    this.onShowSource,
    this.onDownloadTemplate,
    this.onGenerate,
    this.onImport,
    this.onCreate,
    this.onPreview,
    this.onReview,
    this.onPrint,
    this.onArchive,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final badge = _StatusBadge.from(doc);
    // 桌面才允许打印 / 归档（PandocService + LibreOffice 子进程依赖）
    final canDesktopOps =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final isTeachingTask = def.key == 'teaching_task';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            _OrdinalBadge(number: ordinal),
            const SizedBox(width: 10),
            Icon(Icons.description_outlined, size: 26, color: primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(def.label,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onShowSource,
                        child: Icon(Icons.info_outline,
                            size: 14, color: Colors.grey.shade500),
                      ),
                      const SizedBox(width: 6),
                      badge.build(),
                    ],
                  ),
                  if (badge.subtitle != null)
                    Text(badge.subtitle!,
                        style: TextStyle(
                            fontSize: 11,
                            color: badge.subtitleColor ?? Colors.grey)),
                ],
              ),
            ),
            if (onDownloadTemplate != null)
              ActionBtn(
                  icon: Icons.download,
                  tooltip: '下载模板',
                  color: Colors.orange,
                  onTap: onDownloadTemplate),
            if (onImport != null)
              ActionBtn(
                  icon: Icons.file_download_outlined,
                  tooltip: isTeachingTask ? '手动导入(兜底)' : '导入',
                  color: Colors.blue,
                  onTap: onImport),
            if (onCreate != null)
              ActionBtn(
                  icon: Icons.add_circle_outline,
                  tooltip: '新建',
                  color: Colors.deepPurple,
                  onTap: onCreate),
            if (onGenerate != null)
              ActionBtn(
                  icon: Icons.auto_awesome,
                  tooltip: isTeachingTask ? '自动获取/生成' : '生成',
                  color: Colors.deepPurple,
                  onTap: onGenerate),
            if (onReview != null)
              ActionBtn(
                  icon: Icons.rate_review_outlined,
                  tooltip: '审核',
                  color: Colors.teal,
                  onTap: onReview),
            if (onPreview != null)
              ActionBtn(
                  icon: Icons.visibility, tooltip: '预览', onTap: onPreview),
            if (onPrint != null)
              ActionBtn(
                icon: Icons.print,
                tooltip: canDesktopOps ? '打印' : '打印仅桌面端可用',
                onTap: canDesktopOps ? onPrint : null,
              ),
            if (onArchive != null)
              ActionBtn(
                icon: Icons.archive,
                tooltip: canDesktopOps ? '归档' : '归档仅桌面端可用',
                color: canDesktopOps ? Colors.green : null,
                onTap: canDesktopOps ? onArchive : null,
              ),
            if (onDelete != null)
              ActionBtn(
                  icon: Icons.delete_outline,
                  tooltip: '删除',
                  color: Colors.red.shade300,
                  onTap: onDelete),
          ],
        ),
      ),
    );
  }
}

class _OrdinalBadge extends StatelessWidget {
  final int number;

  const _OrdinalBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 34,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.10),
        border: Border.all(color: primary.withValues(alpha: 0.35), width: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        number.toString().padLeft(2, '0'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      ),
    );
  }
}

/// 状态徽标 —— 把 5 状态（未创建/草稿/审核中/已批准/已归档）+ 审核结果
/// 错误/警告计数浓缩成一个 chip + 一行 subtitle。
class _StatusBadge {
  final String label;
  final Color color;
  final IconData? icon;
  final String? subtitle;
  final Color? subtitleColor;

  _StatusBadge({
    required this.label,
    required this.color,
    this.icon,
    this.subtitle,
    this.subtitleColor,
  });

  factory _StatusBadge.from(ArchiveDocument? doc) {
    if (doc == null) {
      return _StatusBadge(
        label: '未创建',
        color: Colors.grey,
        icon: Icons.radio_button_unchecked,
        subtitle: '尚未生成或导入',
      );
    }
    final status = doc.status;
    final review = ReviewResult.fromJson(doc.reviewJson);
    final errCount = review.errors.length;
    final warnCount = review.warnings.length;

    switch (status) {
      case 'archived':
        return _StatusBadge(
          label: '已归档',
          color: Colors.green,
          icon: Icons.check_circle,
          subtitle: review.totalFindings > 0
              ? '审核通过 (置信 ${(review.confidence * 100).toStringAsFixed(0)}%)'
              : '已写入归档目录',
          subtitleColor: Colors.green.shade700,
        );
      case 'approved':
        return _StatusBadge(
          label: '已批准',
          color: Colors.green.shade600,
          icon: Icons.task_alt,
          subtitle: '可一键打印 / 归档',
          subtitleColor: Colors.green.shade700,
        );
      case 'reviewing':
        if (errCount > 0) {
          return _StatusBadge(
            label: '需修订',
            color: Colors.red,
            icon: Icons.error_outline,
            subtitle: '$errCount 项错误'
                '${warnCount > 0 ? ' / $warnCount 项建议' : ''}',
            subtitleColor: Colors.red.shade700,
          );
        }
        return _StatusBadge(
          label: warnCount > 0 ? '建议改进' : '审核中',
          color: Colors.orange,
          icon: Icons.hourglass_top,
          subtitle: warnCount > 0 ? '$warnCount 项建议（可忽略）' : '等待审核',
          subtitleColor: Colors.orange.shade700,
        );
      default: // draft
        if ((doc.filePath ?? '').isNotEmpty) {
          if (doc.documentType == 'teaching_task') {
            return _StatusBadge(
              label: '已获取',
              color: Colors.blue,
              icon: Icons.public,
              subtitle: '来自教务系统源文件，待审核',
              subtitleColor: Colors.blue.shade700,
            );
          }
          return _StatusBadge(
            label: '已导入',
            color: Colors.blue,
            icon: Icons.file_download_done_outlined,
            subtitle: '来自教务/模板文件，待审核',
            subtitleColor: Colors.blue.shade700,
          );
        }
        return _StatusBadge(
          label: doc.isGenerated ? '已生成' : '草稿',
          color: Colors.blue,
          icon: doc.isGenerated ? Icons.auto_awesome : Icons.edit_note,
          subtitle: doc.isGenerated ? '由 AI 起草，待审核' : '已创建，待审核',
          subtitleColor: Colors.blue.shade700,
        );
    }
  }

  Widget build() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 2),
          ],
          Text(label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

class ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;
  const ActionBtn(
      {super.key,
      required this.icon,
      required this.tooltip,
      this.color,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: color,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _DocumentPreviewSheet extends StatelessWidget {
  final ArchiveDocument doc;
  final Future<Uint8List> Function(ArchiveDocument doc) pdfBuilder;

  const _DocumentPreviewSheet({
    required this.doc,
    required this.pdfBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final sourcePath = doc.filePath;
    final usePdfPreview = doc.documentType == 'teaching_task' ||
        (sourcePath != null && sourcePath.toLowerCase().endsWith('.pdf'));
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
                Expanded(
                    child: Text(doc.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))),
                // 注：审核 / 打印 / 归档 操作请在卡片上的快捷按钮处发起，
                //    走 ArchivePackageService 完整路径（生成 docx/PDF + 打包 + 复制路径）。
                //    预览面板只负责"看内容"，不再提供伪操作按钮。
              ],
            ),
          ),
          Expanded(
            child: usePdfPreview
                ? PdfPreview(
                    build: (_) => pdfBuilder(doc),
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                    pdfFileName: '${doc.title}.pdf',
                  )
                : SingleChildScrollView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    child: doc.content != null
                        ? MarkdownBubble(content: doc.content!)
                        : const Center(child: Text('暂无内容')),
                  ),
          ),
        ],
      ),
    );
  }
}
