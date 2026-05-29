import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
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
import '../../../../services/archive_package_service.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../presentation/widgets/markdown_bubble.dart';
import '../archive_constants.dart';
import '../widgets/review_result_dialog.dart';

class ArchivePeriodTab extends StatefulWidget {
  final String periodKey;
  final String courseType;
  final ArchiveDao dao;
  final ArchiveAgent agent;
  final VoidCallback? onSyllabusChanged;

  const ArchivePeriodTab({
    super.key,
    required this.periodKey,
    required this.courseType,
    required this.dao,
    required this.agent,
    this.onSyllabusChanged,
  });

  @override
  State<ArchivePeriodTab> createState() => _ArchivePeriodTabState();
}

class _ArchivePeriodTabState extends State<ArchivePeriodTab> {
  List<ArchiveDocument> _documents = [];
  bool _loading = true;
  Set<String> _lastCourseScheduleNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArchivePeriodTab old) {
    super.didUpdateWidget(old);
    if (old.courseType != widget.courseType || old.periodKey != widget.periodKey) {
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
      if (mounted) setState(() { _documents = docs; _loading = false; });
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
      if (processor is AiDraftProcessor) {
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
      builder: (_) => _DocumentPreviewSheet(doc: doc),
    );
  }

  Future<void> _printDoc(ArchiveDocument doc) async {
    if (!mounted) return;

    // 跨平台守门：移动端 / web 不支持 pandoc + libreoffice 子进程
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
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

    // loading 提示（pandoc + soffice 两步通常 5-15 秒）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Row(
            children: [
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('正在生成 PDF（pandoc + LibreOffice）...')),
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
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _reviewDoc(ArchiveDocument doc) async {
    if (!mounted) return;

    // 优先走 Processor 路径（结构化审核 + 自动创建审核表卡片）。
    // 当前注册了 syllabus 的 AiAuditProcessor → docType=syllabus 的文档走新流水线。
    // 其它 docType 仍回退到旧的 archive_agent.reviewDocument（markdown 字符串）。
    final processor = _findAuditProcessorFor(doc);
    if (processor != null) {
      await _reviewDocViaProcessor(doc, processor);
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
                Icon(Icons.rate_review, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('AI 审核结果'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: MarkdownBubble(content: review),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
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

  /// 查找该 doc.documentType 对应的 AiAuditProcessor。
  /// 注意：审核处理器的 targetDocType 是被审目标，所以遍历找 targetDocType 匹配的。
  AiAuditProcessor? _findAuditProcessorFor(ArchiveDocument doc) {
    final reg = ProcessorRegistry.instance;
    for (final t in reg.registeredDocTypes) {
      final p = reg.find(t);
      if (p is AiAuditProcessor && p.targetDocType == doc.documentType) {
        return p;
      }
    }
    return null;
  }

  /// Processor 路径：跑 reviewTarget → 弹 ReviewResultDialog（含三栏 + 忽略 + 再审）
  Future<void> _reviewDocViaProcessor(
    ArchiveDocument doc,
    AiAuditProcessor processor,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final result = await processor.reviewTarget(doc);
      if (!mounted) return;
      Navigator.of(context).pop(); // 关 loading

      // 重新拉一次 doc 以拿到最新的 reviewJson / status
      final fresh = await widget.dao.getDocumentById(doc.id!);
      final target = fresh ?? doc;
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => ReviewResultDialog(
          target: target,
          initial: result,
          onUpdated: (_) => _load(), // 父级刷新文档列表（审核表自动出现）
        ),
      );
      // 对话框关闭后再刷一次（覆盖再审/忽略后的状态）
      if (mounted) await _load();
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePeriodTab._reviewDocViaProcessor', stack: st);
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

    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
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
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
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
        message: 'docx 已保存，文件路径已复制到剪贴板，可直接粘贴到 QQ 群发送。',
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
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
        allowedExtensions: ['htm', 'html'],
        dialogTitle: '选择教学任务书HTML文件',
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
      final parsed = _parseTeachingTask(html);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到"移动应用开发"课程数据，请确认HTML文件内容'), backgroundColor: Colors.red),
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
        isGenerated: true,
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
      try {
        parsed = _parseCourseSchedule(bytes);
      } catch (e, st) {
        swallowDebug(e, tag: 'ArchivePeriodTab._importDoc.xlsx', stack: st);
      }
      if (parsed == null) {
        if (mounted) {
          final found = _lastCourseScheduleNames.take(10).join('、');
          final msg = found.isNotEmpty
              ? '课表中未找到"移动应用开发"课程。找到的课程：$found'
              : '未在课表中找到"移动应用开发"课程，请确认Excel文件包含"课程名称"列';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
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
        isGenerated: true,
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
      final parsed = _parseCalendar(raw);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('校历解析失败，请确认文件为完整的MHTML格式'), backgroundColor: Colors.red),
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
        isGenerated: true,
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
      final parsed = _parseRollCall(raw);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到"移动应用开发"点名册数据，请确认MHTML文件内容'), backgroundColor: Colors.red),
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
        isGenerated: true,
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
        isGenerated: true,
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
        isGenerated: true,
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

    if (def.key == 'syllabus_evaluation' || def.key == 'syllabus_review'
        || def.key == 'teacher_guide' || def.key == 'student_guide'
        || def.key == 'assessment_plan') {
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
      final text = _extractDocxText(bytes);
      if (text == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('解析docx文件失败，请确认文件格式'), backgroundColor: Colors.red),
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
        isGenerated: true,
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

  String? _parseTeachingTask(String html) {
    var match = RegExp(
      r'经学校批准聘请(.+?)老师担任(.+?)以下教学任务',
    ).firstMatch(html);
    final teacher = match?.group(1) ?? '未知';
    final semester = match?.group(2) ?? '未知学期';

    final courseRows = RegExp(
      r'<tr>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*</tr>',
      dotAll: true,
    ).allMatches(html);

    Map<String, String>? courseData;
    for (final row in courseRows) {
      final name = row.group(1)?.trim() ?? '';
      if (name.contains('移动应用开发')) {
        courseData = {
          'course_name': name,
          'course_type': row.group(2)?.trim() ?? '',
          'total_hours': row.group(3)?.trim() ?? '',
          'lecture_hours': row.group(4)?.trim() ?? '',
          'lab_hours': row.group(5)?.trim() ?? '',
          'practice_hours': row.group(6)?.trim() ?? '',
          'self_study_hours': row.group(7)?.trim() ?? '',
          'class_info': row.group(8)?.trim() ?? '',
          'student_count': row.group(9)?.trim() ?? '',
          'notes': row.group(10)?.trim() ?? '',
        };
        break;
      }
    }
    if (courseData == null) return null;

    return '''# 教 学 任 务 书

**教师**：$teacher
**学期**：$semester

| 项目 | 内容 |
|------|------|
| 课程名称 | ${courseData['course_name']} |
| 课程类别 | ${courseData['course_type']} |
| 总学时 | ${courseData['total_hours']} |
| 讲授 | ${courseData['lecture_hours']} |
| 实验 | ${courseData['practice_hours']} |
| 实践 | ${courseData['lab_hours']} |
| 课外自主学时 | ${courseData['self_study_hours']} |
| 教学班级 | ${courseData['class_info']} |
| 计划人数 | ${courseData['student_count']} |
| 备注 | ${courseData['notes']} |

---
> 数据来源：教务系统（j﻿wgl.chzu.edu.cn）
> 导入时间：${DateTime.now().toString().substring(0, 16)}
''';
  }

  String? _parseRollCall(String raw) {
    String html = raw;
    // Extract HTML part from MHTML (between boundary markers)
    final boundaryMatch = RegExp(r'boundary="(.*?)"').firstMatch(raw);
    if (boundaryMatch != null) {
      final boundary = '--${boundaryMatch.group(1)}';
      final parts = raw.split(boundary);
      for (final part in parts) {
        if (part.contains('Content-Type: text/html')) {
          final contentStart = part.indexOf('Content-Location:');
          if (contentStart == -1) continue;
          final content = part.substring(contentStart);
          final lineEnd = content.indexOf('\n');
          if (lineEnd == -1) continue;
          html = content.substring(lineEnd + 1).trim();
          break;
        }
      }
    }

    // Decode quoted-printable: =XX → byte, =3D → =
    final bytes = <int>[];
    for (var i = 0; i < html.length; i++) {
      if (html[i] == '=' && i + 2 < html.length) {
        if (html[i + 1] == '\r' && html[i + 2] == '\n') {
          i += 2;
          continue;
        }
        if (html[i + 1] == '\n') { i += 1; continue; }
        final hex = html.substring(i + 1, i + 3);
        if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(hex)) {
          bytes.add(int.parse(hex, radix: 16));
          i += 2;
        } else {
          bytes.add('='.codeUnitAt(0));
        }
      } else {
        bytes.add(html.codeUnitAt(i));
      }
    }
    html = utf8.decode(bytes);

    // Extract course info header
    final courseMatch = RegExp(r'课程名称：(.+?)(?:<|$)').firstMatch(html);
    final teacherMatch = RegExp(r'授课教师：(.+?)(?:<|$)').firstMatch(html);
    final scheduleMatch = RegExp(r'课程安排：(.+?)(?:<|$)').firstMatch(html);
    final courseName = courseMatch?.group(1)?.trim() ?? '';
    final teacher = teacherMatch?.group(1)?.trim() ?? '未知';
    final schedule = scheduleMatch?.group(1)?.trim() ?? '';

    if (!courseName.contains('移动应用开发')) return null;

    // Extract student rows: <td>序号</td><td>学号</td><td>姓名</td><td>性别</td>
    final students = <Map<String, String>>[];
    final rowRegex = RegExp(
      r'<tr[^>]*>.*?<td>\s*(\d+)\s*</td>.*?<td>\s*(\d+)\s*</td>.*?<td>(.*?)</td>.*?<td>(.*?)</td>',
      dotAll: true,
    );
    for (final m in rowRegex.allMatches(html)) {
      final name = m.group(3)!.trim();
      final gender = m.group(4)!.trim();
      if (name.isEmpty || name == '&nbsp;') continue;
      students.add({
        'seq': m.group(1)!.trim(),
        'student_id': m.group(2)!.trim(),
        'name': name,
        'gender': gender == '男' ? '男' : '女',
      });
    }

    if (students.isEmpty) return null;

    // Build markdown
    final buf = StringBuffer();
    buf.writeln('# 学生点名册\n');
    buf.writeln('**课程**：移动应用开发');
    buf.writeln('**授课教师**：$teacher');
    buf.writeln('**课程安排**：$schedule');
    buf.writeln('**学生人数**：${students.length}人\n');
    buf.writeln('| 序号 | 学号 | 姓名 | 性别 |');
    buf.writeln('|------|------|------|------|');
    for (final s in students) {
      buf.writeln('| ${s['seq']} | ${s['student_id']} | ${s['name']} | ${s['gender']} |');
    }
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 数据来源：教务系统考勤表');
    buf.writeln('> 导入时间：${DateTime.now().toString().substring(0, 16)}');
    return buf.toString();
  }

  String? _parseCourseSchedule(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.sheets.isEmpty) return null;
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return null;

    // Find column indices from header
    final header = sheet.rows[0]
        .map((c) => (c?.value?.toString() ?? '').trim())
        .toList();
    final typeIdx = header.indexOf('类型');
    final classIdx = header.indexOf('班级');
    final courseIdx = header.indexOf('课程名称');
    final dateIdx = header.indexOf('日期');
    final weekIdx = header.indexOf('周');
    final dayIdx = header.indexOf('星期');
    final periodIdx = header.indexOf('课节');
    final teacherIdx = header.indexOf('指导教师');
    final locationIdx = header.indexOf('地点');
    if (typeIdx == -1 || classIdx == -1 || courseIdx == -1) return null;

    final rows = <Map<String, String>>[];
    final allCourseNames = <String>{};
    for (var i = 1; i < sheet.rows.length; i++) {
      final r = sheet.rows[i];
      final courseName = (r.length > courseIdx && r[courseIdx]?.value != null)
          ? r[courseIdx]!.value.toString().trim()
          : '';
      if (courseName.isNotEmpty) allCourseNames.add(courseName);
      if (!courseName.contains('移动应用开发')) continue;
      final weekStr = (r.length > weekIdx && r[weekIdx]?.value != null)
          ? r[weekIdx]!.value.toString().trim()
          : '';
      rows.add({
        'type': (r.length > typeIdx && r[typeIdx]?.value != null)
            ? r[typeIdx]!.value.toString().trim()
            : '',
        'class': (r.length > classIdx && r[classIdx]?.value != null)
            ? r[classIdx]!.value.toString().trim()
            : '',
        'date': (r.length > dateIdx && r[dateIdx]?.value != null)
            ? r[dateIdx]!.value.toString().trim()
            : '',
        'week': weekStr,
        'day': (r.length > dayIdx && r[dayIdx]?.value != null)
            ? r[dayIdx]!.value.toString().trim()
            : '',
        'period': (r.length > periodIdx && r[periodIdx]?.value != null)
            ? r[periodIdx]!.value.toString().trim()
            : '',
        'teacher': (r.length > teacherIdx && r[teacherIdx]?.value != null)
            ? r[teacherIdx]!.value.toString().trim()
            : '',
        'location': (r.length > locationIdx && r[locationIdx]?.value != null)
            ? r[locationIdx]!.value.toString().trim()
            : '',
      });
    }
    if (rows.isEmpty) {
      _lastCourseScheduleNames = allCourseNames;
      return null;
    }

    // Day of week mapping
    const dayNames = {1: '星期一', 2: '星期二', 3: '星期三', 4: '星期四', 5: '星期五', 6: '星期六', 7: '星期日'};

    // Split theory vs lab
    final theory = rows.where((r) => r['type']!.contains('教务')).toList();
    final lab = rows.where((r) => r['type']!.contains('实验')).toList();

    // Extract teacher name
    final teacher = rows.firstWhere(
      (r) => r['teacher']!.isNotEmpty,
      orElse: () => {'teacher': '未知'},
    )['teacher']!;

    // Determine semester from first date
    String semester = '未知学期';
    if (rows.isNotEmpty && rows[0]['date']!.isNotEmpty) {
      final d = rows[0]['date']!;
      final year = int.tryParse(d.substring(0, 4)) ?? 0;
      final month = int.tryParse(d.substring(5, 7)) ?? 0;
      if (month >= 2 && month <= 7) {
        semester = '${year - 1}-$year学年第二学期';
      } else if (month >= 8) {
        semester = '$year-${year + 1}学年第一学期';
      }
    }

    // Helper: parse week number as int
    int? w(Map<String, String> r) => int.tryParse(r['week']!);

    final buf = StringBuffer();
    buf.writeln('# 课程课表：移动应用开发\n');
    buf.writeln('**教师**：$teacher');
    buf.writeln('**学期**：$semester');
    buf.writeln('**班级**：软件231,软件232（85人）\n');

    // Theory
    theory.sort((a, b) => (w(a) ?? 0).compareTo(w(b) ?? 0));
    buf.writeln('## 一、理论课\n');
    buf.writeln('| 周次 | 日期 | 星期 | 节次 | 地点 |');
    buf.writeln('|------|------|------|------|------|');
    for (final r in theory) {
      final dayNum = int.tryParse(r['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : r['day']!;
      buf.writeln('| ${r['week']} | ${r['date']} | $dayName | ${r['period']} | ${r['location']} |');
    }
    buf.writeln('');

    // Lab - group by group name
    final groups = <String, List<Map<String, String>>>{};
    for (final r in lab) {
      // Extract group info from class column: "软件232,软件231(班组1:29人)"
      final groupMatch = RegExp(r'班组(\d)[：:]\d+人').firstMatch(r['class']!);
      final grpKey = groupMatch != null
          ? '班组${groupMatch.group(1)}'
          : '综合组';
      groups.putIfAbsent(grpKey, () => []).add(r);
    }

    buf.writeln('## 二、实验课\n');
    for (final entry in groups.entries) {
      entry.value.sort((a, b) => (w(a) ?? 0).compareTo(w(b) ?? 0));
      // Extract people count from first row
      final peopleMatch = RegExp(r'班组\d[：:](\d+)人').firstMatch(entry.value.first['class']!);
      final people = peopleMatch?.group(1) ?? '';
      final dayNum = int.tryParse(entry.value.first['day']!);
      final dayName = (dayNum != null && dayNames.containsKey(dayNum))
          ? dayNames[dayNum]!
          : entry.value.first['day'] ?? '';
      final periodInfo = entry.value.first['period'] ?? '';
      buf.writeln('### $entry.key（$people人）— $dayName $periodInfo\n');
      buf.writeln('| 周次 | 日期 | 地点 |');
      buf.writeln('|------|------|------|');
      for (final r in entry.value) {
        buf.writeln('| ${r['week']} | ${r['date']} | ${r['location']} |');
      }
      buf.writeln('');
    }

    // Statistics
    buf.writeln('## 三、统计\n');
    final theoryWeeks = theory.map((r) => r['week']!).toSet().length;
    final labWeeks = lab.map((r) => r['week']!).toSet().length;
    final groupCount = groups.length;
    final totalTheoryHours = theory.length * 2;
    final totalLabHours = lab.length * 2;
    buf.writeln('- 理论课：$theoryWeeks周 × 2学时 = ${theoryWeeks * 2}学时（实际$totalTheoryHours课时）');
    buf.writeln('- 实验课：${groups.length}组 × $labWeeks周 × 2学时 = ${groupCount * labWeeks * 2}学时（实际$totalLabHours课时）');
    buf.writeln('- 总学时：${totalTheoryHours + totalLabHours}课时\n');
    buf.writeln('---');
    buf.writeln('> 数据来源：教务系统课表（Excel）');
    buf.writeln('> 导入时间：${DateTime.now().toString().substring(0, 16)}');
    return buf.toString();
  }

  /// Extract HTML content from MHTML multipart wrapper
  String _extractHtmlFromMhtml(String raw) {
    final boundaryMatch = RegExp(r'boundary="(.*?)"').firstMatch(raw);
    if (boundaryMatch != null) {
      final boundary = '--${boundaryMatch.group(1)}';
      final parts = raw.split(boundary);
      for (final part in parts) {
        if (part.contains('Content-Type: text/html')) {
          final contentStart = part.indexOf('Content-Location:');
          if (contentStart == -1) continue;
          final content = part.substring(contentStart);
          final lineEnd = content.indexOf('\n');
          if (lineEnd == -1) continue;
          return content.substring(lineEnd + 1).trim();
        }
      }
    }
    return raw;
  }

  /// Decode quoted-printable text to UTF-8 string
  String _decodeQuotedPrintable(String input) {
    final bytes = <int>[];
    for (var i = 0; i < input.length; i++) {
      if (input[i] == '=' && i + 2 < input.length) {
        if (input[i + 1] == '\r' && input[i + 2] == '\n') {
          i += 2;
          continue;
        }
        if (input[i + 1] == '\n') {
          i += 1;
          continue;
        }
        final hex = input.substring(i + 1, i + 3);
        if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(hex)) {
          bytes.add(int.parse(hex, radix: 16));
          i += 2;
        } else {
          bytes.add('='.codeUnitAt(0));
        }
      } else {
        bytes.add(input.codeUnitAt(i));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String? _parseCalendar(String raw) {
    String html = _extractHtmlFromMhtml(raw);
    html = _decodeQuotedPrintable(html);

    // Parse table rows
    final rowRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    final cellTextRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false);
    final tagStrip = RegExp(r'<[^>]*>', dotAll: true);

    final parsedRows = <List<String>>[];
    for (final rowMatch in rowRegex.allMatches(html)) {
      final rowHtml = rowMatch.group(1)!;
      final cells = <String>[];
      for (final cellMatch in cellTextRegex.allMatches(rowHtml)) {
        // Extract text from cell, merge p.dp1 + p.dp2 sibling text
        var cellContent = cellMatch.group(1)!;
        // Extract dp1 (day number) and dp2 (label) text
        final dp1 = RegExp(r'class="dp1"[^>]*>(.*?)</p>', dotAll: true)
            .firstMatch(cellContent)
            ?.group(1)
            ?.trim() ?? '';
        final dp2 = RegExp(r'class="dp2"[^>]*>(.*?)</p>', dotAll: true)
            .firstMatch(cellContent)
            ?.group(1)
            ?.trim() ?? '';
        final combined = (dp1 + dp2).trim();
        // Fallback: extract all visible text
        final text = combined.isNotEmpty
            ? combined
            : cellContent.replaceAll(tagStrip, '').trim();
        if (text.isNotEmpty) cells.add(text);
      }
      if (cells.isNotEmpty) parsedRows.add(cells);
    }

    if (parsedRows.isEmpty) return null;

    // Skip header row (周次 | 一 二 三 四 五 六 日)
    // Month rows have 1 cell (just month name)
    // Week rows have 7 cells (Mon-Sun dates) + optional week number

    // Build weekly calendar starting from March 2, 2026 (Monday)
    final startDate = DateTime(2026, 3, 2);
    final holidayMap = <String, String>{
      '清明': '清明节',
      '劳动': '劳动节',
      '端午': '端午节',
    };
    final phaseMap = <String, String>{
      '缓补': '缓补考试周',
      '期末': '期末考试周',
      '暑假': '暑假',
    };

    // Collect all day cells across all data rows
    final weeks = <List<_CalDay>>[];
    List<_CalDay>? currentWeek;

    for (final cells in parsedRows) {
      if (cells.length <= 2) continue; // month header or empty
      // Cells could be: [week_no?] + [7 days]
      // Or just [7 days] with colspan merging
      final dayCells = cells.length >= 8 ? cells.sublist(cells.length - 7) : cells;
      if (dayCells.length != 7) continue;

      currentWeek = [];
      for (var d = 0; d < 7; d++) {
        final raw = dayCells[d];
        // Extract day number and label
        final numMatch = RegExp(r'^(\d+)').firstMatch(raw);
        final dayNum = numMatch != null ? int.parse(numMatch.group(1)!) : 0;
        String label = '';
        for (final entry in holidayMap.entries) {
          if (raw.contains(entry.key)) {
            label = entry.value;
            break;
          }
        }
        if (label.isEmpty) {
          for (final entry in phaseMap.entries) {
            if (raw.contains(entry.key)) {
              label = entry.value;
              break;
            }
          }
        }
        currentWeek.add(_CalDay(date: dayNum, label: label));
      }
      weeks.add(currentWeek);
    }

    // Deduplicate: if two consecutive weeks have same Monday date, skip
    final uniqueWeeks = <List<_CalDay>>[];
    for (var i = 0; i < weeks.length; i++) {
      if (i > 0 && weeks[i][0].date == weeks[i - 1][0].date) continue;
      uniqueWeeks.add(weeks[i]);
    }

    // Generate markdown - SCHOOL calendar, NOT course-specific
    final buf = StringBuffer();
    buf.writeln('# 校 历\n');
    buf.writeln('**学年学期：** 2025-2026学年第二学期\n');
    buf.writeln('**起始日期：** ${startDate.toString().substring(0, 10)}（周一）\n');
    buf.writeln('## 校历总览\n');
    buf.writeln('| 周次 | 起止日期 | 周一 | 周二 | 周三 | 周四 | 周五 | 周六 | 周日 | 备注 |');
    buf.writeln('|------|----------|------|------|------|------|------|------|------|------|');

    for (var w = 0; w < uniqueWeeks.length; w++) {
      final wk = uniqueWeeks[w];
      final monDate = startDate.add(Duration(days: w * 7));
      final sunDate = monDate.add(const Duration(days: 6));
      final dateRange = '${monDate.month}/${monDate.day}-${sunDate.month}/${sunDate.day}';

      // Determine week label
      String weekLabel = '';
      final holidays = <String>[];
      for (final day in wk) {
        if (day.label.isNotEmpty && !day.label.contains('周')) {
          holidays.add(day.label);
        }
        if (day.label == '缓补考试周') weekLabel = '缓补';
        if (day.label == '期末考试周') weekLabel = '期末';
        if (day.label == '暑假') weekLabel = '暑假';
      }

      final weekNum = weekLabel.isNotEmpty ? weekLabel : '${w + 1}';
      final note = holidays.isNotEmpty
          ? holidays.toSet().join('、')
          : (weekLabel.isNotEmpty ? '（$weekLabel）' : '');

      // Day columns (show date number, mark holidays)
      final dayCols = <String>[];
      for (var d = 0; d < 7; d++) {
        final day = wk[d];
        if (day.label == '清明节' || day.label == '劳动节' || day.label == '端午节') {
          dayCols.add('🎉${day.date}');
        } else if (day.label == '缓补考试周' || day.label == '期末考试周' || day.label == '暑假') {
          dayCols.add('📌${day.date}');
        } else {
          dayCols.add('${day.date}');
        }
      }

      // Mark holiday weeks
      String noteStr = note;
      if (note.contains('清明')) {
        noteStr = '清明节放假';
      } else if (note.contains('劳动')) {
        noteStr = '劳动节放假';
      } else if (note.contains('端午')) {
        noteStr = '端午节放假';
      }

      buf.writeln(
          '| $weekNum | $dateRange | ${dayCols[0]} | ${dayCols[1]} | ${dayCols[2]} | ${dayCols[3]} | ${dayCols[4]} | ${dayCols[5]} | ${dayCols[6]} | $noteStr |');
    }

    buf.writeln('');
    buf.writeln('## 节假日安排\n');
    buf.writeln('| 节日 | 日期 | 天数 | 说明 |');
    buf.writeln('|------|------|------|------|');
    buf.writeln('| 清明节 | 4月5日（周日） | 4月4-6日放假 | 调休安排以学校通知为准 |');
    buf.writeln('| 劳动节 | 5月1日（周五） | 5月1-5日放假 | 调休安排以学校通知为准 |');
    buf.writeln('| 端午节 | 6月19日（周五） | 6月12-14日放假 | 调休安排以学校通知为准 |');
    buf.writeln('');
    buf.writeln('## 作息时间\n');
    buf.writeln('| 时段 | 冬季作息（第1-10周） | 夏季作息（第11周起） |');
    buf.writeln('|------|----------------------|----------------------|');
    buf.writeln('| 上午 | 8:00-11:50 | 8:00-11:50 |');
    buf.writeln('| 下午 | 14:00-17:30 | 14:30-18:00 |');
    buf.writeln('| 晚上 | 19:00-21:00 | 19:00-21:00 |');
    buf.writeln('');
    buf.writeln('## 关键节点\n');
    buf.writeln('- **缓补考试**：第1周（3月2-8日）');
    buf.writeln('- **期末考试**：第19-20周（7月6-19日）');
    buf.writeln('- **暑假**：第21周起（7月20日起）');
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('> 数据来源：滁州学院校历系统');
    buf.writeln('> 导入时间：${DateTime.now().toString().substring(0, 16)}');
    buf.writeln('> 注：本日历为全校通用校历，具体教学安排以课表为准');
    return buf.toString();
  }

  String? _extractDocxText(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final file = archive.findFile('word/document.xml');
      if (file == null) return null;
      final xml = utf8.decode(file.content);
      final doc = XmlDocument.parse(xml);
      final texts = doc.findAllElements('w:t').map((e) => e.innerText).join('');
      return texts.replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (_) {
      return null;
    }
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
            Expanded(child: Text('${def.label} — 来源说明', style: const TextStyle(fontSize: 16))),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
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
          child: Text('$label：', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
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
          'description': '课表查询 → 课表查询（实时课表）→ 打印教学任务书 → 浏览器另存为HTML文件。Beangle教务管理系统，打印页面URL: courseTableForTeacher!printLessonBook.action',
        };
      case 'syllabus':
        return {
          'system': '学院 / 教师编写（Markdown）',
          'description': '教师根据学院规范编写的Markdown教学大纲，课程编码 d203010351/d203010092，含7章教学内容、4项课程目标及考核标准',
        };
      case 'syllabus_evaluation':
        return {
          'system': '学院课程群建设工作组',
          'description': '计算机与信息工程学院课程教学大纲合理性评价表，含10项评价指标、课程群建设工作组意见、学院教学指导委员会意见，docx格式',
        };
      case 'syllabus_review':
        return {
          'system': '学院教学指导委员会',
          'description': '移动应用开发课程过程性考核合理性审核表，依据2023版人才培养方案，含课程目标-毕业要求对应关系、考核方式及成绩评定对照表（平时20%+实验30%+期末50%），docx格式',
        };
      case 'calendar':
        return {
          'system': '校历系统（webvpn.chzu.edu.cn）',
          'description': '滁州学院校历（2025-2026第二学期），通过学校WebVPN网关访问的React SPA页面，从浏览器保存为MHTML/HTML文件',
        };
      case 'course_schedule':
        return {
          'system': '实验教学服务平台',
          'description': '实验教学服务平台 → 实践教学 → 课表查询 → 我的课表 导出XLSX文件。含★教务（排课）和○实验两种类型标记',
        };
      case 'teaching_schedule':
        return {
          'system': '教师编写（Markdown）',
          'description': '教师根据教学大纲编写的16周教学进度表（2026年3月2日-6月21日），含6个实验项目及平时20%+实验30%+期末50%考核比例',
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
          'description': '从 homeExt.action# 进入 → 打印点名册 → 浏览器另存为MHTML文件。URL路径: courseTableForTeacher!printAttendanceCheckList.action，含85名学生（软件231/232）考勤记录',
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
          'description': '学院编制的综合考核方案docx文档（V1.0版），以SmartCampus智慧校园项目为载体，含4种技术栈的团队项目考核（每组6人，15天）',
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
      case 'teaching_task': return '教务系统';
      case 'syllabus': return '学院';
      case 'syllabus_evaluation': return '学院';
      case 'syllabus_review': return '学院';
      case 'calendar': return '校历';
      case 'course_schedule': return '实验教学服务平台';
      case 'teaching_schedule': return '外部系统';
      case 'lesson_plan': return '外部系统';
      case 'courseware': return '课件库';
      case 'roll_call': return '教务系统';
      case 'teacher_guide': return '学院';
      case 'student_guide': return '学院';
      case 'assessment_plan': return '学院';
      default: return '外部系统';
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
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
    final order = widget.periodKey == 'beginning'
        ? ['calendar', 'teaching_schedule', 'lesson_plan']
        : _expectedDocs.where((d) => d.needsGeneration).map((d) => d.key).toList();
    final toGenerate = order
        .map((key) => _expectedDocs.where((d) => d.key == key).firstOrNull)
        .whereType<DocumentTypeDef>()
        .where((d) => _findDoc(d) == null)
        .toList();
    if (toGenerate.isEmpty) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    int success = 0;
    for (final def in toGenerate) {
      final doc = await _doGenerate(def);
      if (doc != null) success++;
    }
    if (mounted) {
      Navigator.of(context).pop();
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成 $success/${toGenerate.length} 份文档')),
      );
    }
  }

  Future<void> _reviewAll() async {
    final toReview =
        _documents.where((d) => d.content != null && d.content!.isNotEmpty).toList();
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
        final review = await widget.agent.reviewDocument(doc);
        results.add('### ${doc.title}\n\n$review');
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
                Icon(Icons.rate_review, color: Theme.of(context).colorScheme.primary),
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _printAll() async {
    final toPrint = _expectedDocs
        .where((d) => d.canPrint && _findDoc(d) != null)
        .toList();
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

    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
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
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
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
            ? 'zip 已生成，路径已复制。粘贴到 QQ 群即可分享，或拖动文件到群窗口。'
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

  Widget _buildActionBar() {
    final primary = Theme.of(context).colorScheme.primary;
    final hasUnfinished = _expectedDocs.any((d) => d.needsGeneration && _findDoc(d) == null);
    final hasUnreviewed = _documents.any((d) => d.content != null && d.content!.isNotEmpty);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final docs = _expectedDocs;
    return Column(
      children: [
        if (docs.isNotEmpty) _buildActionBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: docs.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    Center(
                        child: Text('暂无配置的文档类型',
                            style: TextStyle(color: Colors.grey))),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final def = docs[i];
                      final doc = _findDoc(def);
                      return DocCard(
                        def: def,
                        doc: doc,
                        source: _importSource(def.key),
                        onShowSource: () => _showSourceInfo(def),
                        onDownloadTemplate: def.canImport ? () => _downloadTemplate(def) : null,
                        onImport: def.canImport ? () => _importDoc(def) : null,
                        onCreate: def.canCreate ? () => _createDoc(def) : null,
                        onGenerate: def.needsGeneration
                            ? () => _generateDoc(def)
                            : null,
                        onReview: doc != null ? () => _reviewDoc(doc) : null,
                        onPreview: doc != null ? () => _previewDoc(doc) : null,
                        onPrint: (doc != null && def.canPrint)
                            ? () => _printDoc(doc)
                            : null,
                        onArchive: doc != null && doc.status != 'archived'
                            ? () => _archiveDoc(doc)
                            : null,
                        onDelete: doc != null ? () => _deleteDoc(doc) : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class DocCard extends StatelessWidget {
  final DocumentTypeDef def;
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.description_outlined, size: 26, color: primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(def.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onShowSource,
                        child: Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                      ),
                      const SizedBox(width: 6),
                      badge.build(),
                    ],
                  ),
                  if (badge.subtitle != null)
                    Text(badge.subtitle!,
                        style: TextStyle(fontSize: 11, color: badge.subtitleColor ?? Colors.grey)),
                ],
              ),
            ),
            if (onDownloadTemplate != null)
              ActionBtn(icon: Icons.download, tooltip: '下载模板', color: Colors.orange, onTap: onDownloadTemplate),
            if (onImport != null)
              ActionBtn(icon: Icons.file_download_outlined, tooltip: '导入', color: Colors.blue, onTap: onImport),
            if (onCreate != null)
              ActionBtn(icon: Icons.add_circle_outline, tooltip: '新建', color: Colors.deepPurple, onTap: onCreate),
            if (onGenerate != null)
              ActionBtn(icon: Icons.auto_awesome, tooltip: '生成', color: Colors.deepPurple, onTap: onGenerate),
            if (onReview != null)
              ActionBtn(icon: Icons.rate_review_outlined, tooltip: '审核', color: Colors.teal, onTap: onReview),
            if (onPreview != null)
              ActionBtn(icon: Icons.visibility, tooltip: '预览', onTap: onPreview),
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
              ActionBtn(icon: Icons.delete_outline, tooltip: '删除', color: Colors.red.shade300, onTap: onDelete),
          ],
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
          subtitle: warnCount > 0
              ? '$warnCount 项建议（可忽略）'
              : '等待审核',
          subtitleColor: Colors.orange.shade700,
        );
      default: // draft
        return _StatusBadge(
          label: doc.isGenerated ? '已生成' : '草稿',
          color: Colors.blue,
          icon: doc.isGenerated ? Icons.auto_awesome : Icons.edit_note,
          subtitle: doc.isGenerated
              ? '由 AI 起草，待审核'
              : '已创建，待审核',
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
  const ActionBtn({super.key, required this.icon, required this.tooltip, this.color, this.onTap});
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
  const _DocumentPreviewSheet({required this.doc});

  @override
  Widget build(BuildContext context) {
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
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(doc.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                // 注：审核 / 打印 / 归档 操作请在卡片上的快捷按钮处发起，
                //    走 ArchivePackageService 完整路径（生成 docx/PDF + 打包 + 复制路径）。
                //    预览面板只负责"看内容"，不再提供伪操作按钮。
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
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

class _CalDay {
  final int date;
  final String label;
  const _CalDay({required this.date, this.label = ''});
}
