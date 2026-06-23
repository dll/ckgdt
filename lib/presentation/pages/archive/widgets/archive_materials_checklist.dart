import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../../core/error_handler.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../services/archive/pandoc_service.dart';
import '../../../../services/archive/review_result.dart';
import '../../../../services/archive_package_service.dart';
import '../archive_constants.dart';

class ArchiveMaterialsChecklist extends StatefulWidget {
  final ArchiveDao dao;
  final String courseType;

  const ArchiveMaterialsChecklist({
    super.key,
    required this.dao,
    required this.courseType,
  });

  @override
  State<ArchiveMaterialsChecklist> createState() =>
      _ArchiveMaterialsChecklistState();
}

class _ArchiveMaterialsChecklistState extends State<ArchiveMaterialsChecklist> {
  final _selected = <int>{};
  List<ArchiveDocument> _docs = [];
  bool _loading = true;
  bool _archiving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs = await widget.dao.getDocuments();
      final materials = _dedupeDocuments(docs
          .where(
              (d) => const {'beginning', 'midterm', 'final'}.contains(d.period))
          .where(_hasMaterial)
          .toList())
        ..sort((a, b) {
          final p = _periodOrder(a.period).compareTo(_periodOrder(b.period));
          if (p != 0) return p;
          final typeOrder = _ordinalFor(a).compareTo(_ordinalFor(b));
          if (typeOrder != 0) return typeOrder;
          return _docSortKey(a).compareTo(_docSortKey(b));
        });
      if (!mounted) return;
      setState(() {
        _docs = materials;
        _selected
          ..clear()
          ..addAll(materials.where((d) => d.id != null).map((d) => d.id!));
        _loading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveMaterialsChecklist._load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ArchiveDocument> _dedupeDocuments(List<ArchiveDocument> docs) {
    final byKey = <String, ArchiveDocument>{};
    for (final doc in docs) {
      final key = _dedupeKey(doc);
      final existing = byKey[key];
      if (existing == null || _preferDoc(doc, existing)) {
        byKey[key] = doc;
      }
    }
    return byKey.values.toList();
  }

  String _dedupeKey(ArchiveDocument doc) {
    final path = _normalizedPath(doc.filePath);
    if (path.isNotEmpty) {
      return '${doc.period}|${doc.documentType}|$path';
    }
    final content = (doc.content ?? '').trim();
    final contentSig =
        content.length > 120 ? content.substring(0, 120) : content;
    return '${doc.period}|${doc.documentType}|${doc.title}|$contentSig';
  }

  bool _preferDoc(ArchiveDocument a, ArchiveDocument b) {
    final statusOrder = _statusRank(a.status).compareTo(_statusRank(b.status));
    if (statusOrder != 0) return statusOrder > 0;
    final reviewOrder =
        (_isReviewPassed(a) ? 1 : 0).compareTo(_isReviewPassed(b) ? 1 : 0);
    if (reviewOrder != 0) return reviewOrder > 0;
    return a.updatedAt.compareTo(b.updatedAt) > 0;
  }

  int _statusRank(String status) {
    switch (status) {
      case 'archived':
        return 4;
      case 'approved':
        return 3;
      case 'reviewing':
        return 2;
      default:
        return 1;
    }
  }

  String _normalizedPath(String? value) =>
      (value ?? '').trim().replaceAll('\\', '/').toLowerCase();

  String _docSortKey(ArchiveDocument doc) {
    final path = doc.filePath?.trim();
    if (path != null && path.isNotEmpty) return p.basename(path).toLowerCase();
    return doc.title.toLowerCase();
  }

  String _ordinalFor(ArchiveDocument doc) {
    final defs = docsForPeriod(widget.courseType, doc.period);
    for (var i = 0; i < defs.length; i++) {
      if (defs[i].key == doc.documentType) {
        return (i + 1).toString().padLeft(2, '0');
      }
    }
    return '99';
  }

  bool _hasMaterial(ArchiveDocument doc) {
    if ((doc.content ?? '').trim().isNotEmpty) return true;
    final filePath = (doc.filePath ?? '').trim();
    if (filePath.isEmpty) return false;
    if (kIsWeb) return true;
    try {
      return File(filePath).existsSync();
    } catch (_) {
      return true;
    }
  }

  int _periodOrder(String period) {
    const order = {'beginning': 0, 'midterm': 1, 'final': 2, 'archive': 3};
    return order[period] ?? 99;
  }

  List<DocumentTypeDef> get _expectedDefs => const [
        'beginning',
        'midterm',
        'final',
      ].expand((period) => docsForPeriod(widget.courseType, period)).toList();

  List<DocumentTypeDef> get _missingDefs {
    final existing = _docs.map((d) => d.documentType).toSet();
    return _expectedDefs.where((def) => !existing.contains(def.key)).toList();
  }

  List<DocumentTypeDef> get _closureMissingDefs {
    final selectedTypes = _selectedDocs.map((d) => d.documentType).toSet();
    return _expectedDefs
        .where((def) => !selectedTypes.contains(def.key))
        .toList();
  }

  int _docCountFor(String period) =>
      _docs.where((d) => d.period == period).length;

  int _expectedCountFor(String period) =>
      docsForPeriod(widget.courseType, period).length;

  List<ArchiveDocument> get _selectedDocs =>
      _docs.where((d) => d.id != null && _selected.contains(d.id)).toList();

  List<ArchiveDocument> get _selectedReviewBlockers =>
      _selectedDocs.where((d) => !_isReviewPassed(d)).toList();

  bool get _canCloseCourse =>
      _selectedDocs.isNotEmpty &&
      _closureMissingDefs.isEmpty &&
      _selectedReviewBlockers.isEmpty;

  bool _isReviewPassed(ArchiveDocument doc) {
    if (doc.status == 'archived') return true;
    final review = ReviewResult.fromJson(doc.reviewJson);
    if (review.hasBlockers) return false;
    if (review.isApproved) return true;
    return doc.status == 'approved';
  }

  String _reviewStateLabel(ArchiveDocument doc) {
    if (doc.status == 'archived') return '已归档';
    if (_isReviewPassed(doc)) return '审核通过';
    final review = ReviewResult.fromJson(doc.reviewJson);
    if (review.hasBlockers) return '需修订';
    return '未审核';
  }

  String _completionLabel() {
    final expected = _expectedDefs.length;
    if (expected == 0) return '0%';
    final completed = _docs.map((d) => d.documentType).toSet().length;
    final value = (completed / expected * 100).clamp(0, 100);
    return '${value.toStringAsFixed(0)}%';
  }

  Color _completionColor(BuildContext context) {
    final expected = _expectedDefs.length;
    if (expected == 0) return Theme.of(context).colorScheme.primary;
    final completed = _docs.map((d) => d.documentType).toSet().length;
    final rate = completed / expected;
    if (rate >= 0.9) return Colors.green;
    if (rate >= 0.6) return Colors.orange;
    return Colors.redAccent;
  }

  Future<void> _closeCourseSelected() async {
    if (_selected.isEmpty || _archiving) return;
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结课打包仅在 Windows/macOS/Linux 桌面端可用')),
      );
      return;
    }

    final selectedDocs = _selectedDocs;
    if (selectedDocs.isEmpty) return;
    final missing = _closureMissingDefs;
    final blockers = _selectedReviewBlockers;
    if (missing.isNotEmpty || blockers.isNotEmpty) {
      _showClosurePreview();
      return;
    }

    setState(() => _archiving = true);
    final svc = ArchivePackageService.instance;
    final outputPaths = <String>[];
    final failures = <String>[];
    try {
      final firstLabel = documentLabelForCourseType(
        widget.courseType,
        selectedDocs.first.documentType,
      );
      final naming =
          await svc.buildNaming(doc: selectedDocs.first, docLabel: firstLabel);

      for (final doc in selectedDocs) {
        try {
          final docLabel =
              documentLabelForCourseType(widget.courseType, doc.documentType);
          final path = await svc.archiveDocxOf(
            doc,
            docLabel: docLabel,
            naming: naming.copyWith(docLabel: docLabel),
          );
          outputPaths.add(path);
          await widget.dao.saveDocument(doc.copyWith(status: 'archived'));
        } on Exception catch (e, st) {
          swallowDebug(e,
              tag: 'ArchiveMaterialsChecklist.archiveOne', stack: st);
          failures.add('${doc.title}: $e');
        }
      }

      if (outputPaths.isEmpty) {
        throw ArchivePackageException(
            failures.isEmpty ? '没有成功归档的材料' : failures.join('\n'));
      }

      final zipPath = await svc.zipSelectedFiles(
        naming: naming,
        filePaths: outputPaths,
        prefix: '一键结课',
      );
      await _saveClosureForm(
        docs: selectedDocs,
        outputPaths: outputPaths,
        zipPath: zipPath,
      );
      await Clipboard.setData(ClipboardData(text: zipPath));
      await _load();
      if (!mounted) return;
      final message = failures.isEmpty
          ? '已归档并打包 ${outputPaths.length} 份材料，zip 路径已复制。'
          : '已归档 ${outputPaths.length} 份，失败 ${failures.length} 份，zip 路径已复制。';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      _showClosureFinishedDialog(zipPath, outputPaths.length, failures);
    } on ArchivePackageException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('结课打包失败：${e.message}'),
              backgroundColor: Colors.red),
        );
      }
    } on PandocException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('归档环境未就绪：${e.message}'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e, st) {
      swallowDebug(e,
          tag: 'ArchiveMaterialsChecklist.archiveSelected', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('结课打包失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  Future<void> _saveClosureForm({
    required List<ArchiveDocument> docs,
    required List<String> outputPaths,
    required String zipPath,
  }) async {
    final existing = await widget.dao.getDocuments(
      period: 'archive',
      documentType: 'archive_form',
    );
    for (final duplicate in existing.skip(1)) {
      final id = duplicate.id;
      if (id != null) await widget.dao.deleteDocument(id);
    }
    final now = DateTime.now();
    final content = _closureFormContent(
      docs: docs,
      outputPaths: outputPaths,
      zipPath: zipPath,
      now: now,
    );
    final doc = ArchiveDocument(
      id: existing.isNotEmpty ? existing.first.id : null,
      title: '结课归档确认表',
      documentType: 'archive_form',
      period: 'archive',
      courseType: widget.courseType,
      status: 'archived',
      content: content,
      isGenerated: true,
      reviewJson: ReviewResult(
        overall: 'approved',
        confidence: 1,
        passed: [
          Finding(
            key: 'closure.all_selected_reviewed',
            dimension: '结课审核',
            level: '✅ 通过',
            evidence: '所选 ${docs.length} 份材料均已审核通过或已归档。',
            suggestion: '结课包已生成，可按学校要求提交。',
          ),
        ],
      ).toJson(),
      reviewedAt: now.toIso8601String(),
      createdAt: existing.isNotEmpty ? existing.first.createdAt : null,
      updatedAt: now.toIso8601String(),
    );
    await widget.dao.saveDocument(doc);
  }

  String _closureFormContent({
    required List<ArchiveDocument> docs,
    required List<String> outputPaths,
    required String zipPath,
    required DateTime now,
  }) {
    final buf = StringBuffer()
      ..writeln('# 结课归档确认表')
      ..writeln()
      ..writeln('**结课时间**：${now.toIso8601String().substring(0, 16)}')
      ..writeln('**结课材料数**：${docs.length} 份')
      ..writeln('**归档输出数**：${outputPaths.length} 个文件')
      ..writeln('**结课压缩包**：$zipPath')
      ..writeln()
      ..writeln('## 一、审核结论')
      ..writeln()
      ..writeln('| 检查项 | 结论 | 说明 |')
      ..writeln('|--------|------|------|')
      ..writeln('| 缺项检查 | 通过 | 期初、期中、期末必备材料均已形成 |')
      ..writeln('| 重复检查 | 通过 | 已按来源路径和材料内容去重 |')
      ..writeln('| 审核检查 | 通过 | 所选材料均为审核通过或已归档状态 |')
      ..writeln('| 归档输出 | 通过 | 已按学校命名规则生成结课包 |')
      ..writeln()
      ..writeln('## 二、结课材料清单')
      ..writeln()
      ..writeln('| 序号 | 阶段 | 材料 | 状态 | 源文件/标题 |')
      ..writeln('|------|------|------|------|-------------|');
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final label = documentLabelForCourseType(
        widget.courseType,
        doc.documentType,
      );
      final source = (doc.filePath ?? '').trim().isNotEmpty
          ? p.basename(doc.filePath!)
          : doc.title;
      buf.writeln(
        '| ${(i + 1).toString().padLeft(2, '0')} | ${periodLabel(doc.period)} | $label | ${_reviewStateLabel(doc)} | $source |',
      );
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist, color: primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '课程归档清单',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading || _archiving ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '汇总同一课程 ID 下期初、期中、期末已形成的材料，可勾选后结课归档打包。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_docs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '暂无可归档材料，请先完成期初、期中或期末资料生成/导入。',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              )
            else ...[
              _buildCompletionSummary(context),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _archiving
                        ? null
                        : () => setState(() {
                              _selected
                                ..clear()
                                ..addAll(_docs
                                    .where((d) => d.id != null)
                                    .map((d) => d.id!));
                            }),
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('全选'),
                  ),
                  TextButton.icon(
                    onPressed: _archiving
                        ? null
                        : () => setState(() => _selected.clear()),
                    icon: const Icon(Icons.deselect, size: 18),
                    label: const Text('清空'),
                  ),
                  TextButton.icon(
                    onPressed: _selected.isEmpty || _archiving
                        ? null
                        : () => _showClosurePreview(),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('预览'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: !_canCloseCourse || _archiving
                        ? null
                        : () => _closeCourseSelected(),
                    icon: _archiving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.done_all, size: 18),
                    label: Text('一键结课(${_selected.length})'),
                  ),
                ],
              ),
              if (!_canCloseCourse && _selected.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _closureBlockedText(),
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Divider(height: 12),
              ..._buildGroupedDocList(),
            ],
          ],
        ),
      ),
    );
  }

  String _closureBlockedText() {
    final missing = _missingDefs.length;
    final unselected = _closureMissingDefs.length - missing;
    final blockers = _selectedReviewBlockers.length;
    if (missing > 0 || unselected > 0 || blockers > 0) {
      final parts = <String>[];
      if (missing > 0) parts.add('缺 $missing 项材料');
      if (unselected > 0) parts.add('$unselected 项必备材料未选入');
      if (blockers > 0) parts.add('$blockers 份材料未审核通过');
      return '暂不能结课：${parts.join('，')}。';
    }
    return '暂不能结课：请先选择材料。';
  }

  Future<void> _showClosurePreview() async {
    if (!mounted) return;
    final selectedDocs = _selectedDocs;
    final missing = _closureMissingDefs;
    final blockers = _selectedReviewBlockers;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('结课预览')),
            _statusChip(
              _canCloseCourse ? '可结课' : '需处理',
              _canCloseCourse ? Colors.green : Colors.orange,
            ),
          ],
        ),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewMetrics(selectedDocs, missing, blockers),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _previewSectionTitle('未进入结课包的必备材料'),
                  ...missing.map(
                    (d) => _previewLine(
                      _missingDefs.any((m) => m.key == d.key)
                          ? Icons.warning_amber_outlined
                          : Icons.check_box_outline_blank,
                      d.label,
                      _missingDefs.any((m) => m.key == d.key)
                          ? '请先在${_expectedPeriodLabel(d)}完成生成、导入和审核。'
                          : '材料已形成，但未勾选进入结课包。',
                      Colors.orange,
                    ),
                  ),
                ],
                if (blockers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _previewSectionTitle('未审核通过'),
                  ...blockers.map(
                    (d) => _previewLine(
                      Icons.error_outline,
                      documentLabelForCourseType(
                        widget.courseType,
                        d.documentType,
                      ),
                      '${d.title} · ${_reviewStateLabel(d)}',
                      Colors.redAccent,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _previewSectionTitle('将打包材料'),
                if (selectedDocs.isEmpty)
                  Text('未选择材料。',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600))
                else
                  ..._buildPreviewDocLines(selectedDocs),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: _canCloseCourse && !_archiving
                ? () {
                    Navigator.pop(context);
                    _closeCourseSelected();
                  }
                : null,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('一键结课'),
          ),
        ],
      ),
    );
  }

  Widget _previewMetrics(
    List<ArchiveDocument> selectedDocs,
    List<DocumentTypeDef> missing,
    List<ArchiveDocument> blockers,
  ) {
    Widget metric(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        metric('已选材料', '${selectedDocs.length}', Colors.blue),
        const SizedBox(width: 8),
        metric('待补材料', '${missing.length}', Colors.orange),
        const SizedBox(width: 8),
        metric('审核阻断', '${blockers.length}', Colors.redAccent),
      ],
    );
  }

  Widget _previewSectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );

  List<Widget> _buildPreviewDocLines(List<ArchiveDocument> docs) {
    final result = <Widget>[];
    String? currentPeriod;
    for (final doc in docs) {
      if (currentPeriod != doc.period) {
        currentPeriod = doc.period;
        result.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(
            '${periodLabel(doc.period)}材料',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ));
      }
      final label = documentLabelForCourseType(
        widget.courseType,
        doc.documentType,
      );
      result.add(_previewLine(
        _isReviewPassed(doc) ? Icons.task_alt : Icons.error_outline,
        label,
        '${doc.title} · ${_reviewStateLabel(doc)}',
        _isReviewPassed(doc) ? Colors.green : Colors.redAccent,
      ));
    }
    return result;
  }

  Widget _previewLine(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _expectedPeriodLabel(DocumentTypeDef def) {
    for (final period in const ['beginning', 'midterm', 'final']) {
      if (docsForPeriod(widget.courseType, period)
          .any((d) => d.key == def.key)) {
        return periodLabel(period);
      }
    }
    return '对应阶段';
  }

  void _showClosureFinishedDialog(
    String zipPath,
    int outputCount,
    List<String> failures,
  ) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('结课完成')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failures.isEmpty
                ? '已生成结课包，共 $outputCount 个归档文件。路径已复制到剪贴板。'
                : '已生成结课包，共 $outputCount 个归档文件，失败 ${failures.length} 份。路径已复制到剪贴板。'),
            const SizedBox(height: 12),
            SelectableText(
              zipPath,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (failures.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                failures.join('\n'),
                style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('打开文件夹'),
            onPressed: () async {
              await ArchivePackageService.instance.revealInFileManager(zipPath);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('再次复制'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: zipPath));
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

  Widget _buildCompletionSummary(BuildContext context) {
    final color = _completionColor(context);
    final missing = _missingDefs;
    Widget metric(String label, String value, Color metricColor) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: metricColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: metricColor.withValues(alpha: 0.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: metricColor)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            metric('结课完成度', _completionLabel(), color),
            const SizedBox(width: 8),
            metric('已形成材料', '${_docs.length}', Colors.blue),
            const SizedBox(width: 8),
            metric('待补材料', '${missing.length}', Colors.orange),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _periodChip('期初', 'beginning', Colors.blue),
            const SizedBox(width: 6),
            _periodChip('期中', 'midterm', Colors.teal),
            const SizedBox(width: 6),
            _periodChip('期末', 'final', Colors.deepPurple),
          ],
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '缺项：${missing.take(6).map((d) => d.label).join('、')}${missing.length > 6 ? '等${missing.length}项' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _periodChip(String label, String period, Color color) {
    final actual = _docCountFor(period);
    final expected = _expectedCountFor(period);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $actual/$expected',
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  List<Widget> _buildGroupedDocList() {
    final result = <Widget>[];
    for (final period in const ['beginning', 'midterm', 'final']) {
      final group = _docs.where((d) => d.period == period).toList();
      if (group.isEmpty) continue;
      result.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          '${periodLabel(period)}材料',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ));
      for (final doc in group) {
        result.add(_buildDocTile(doc));
      }
    }
    return result;
  }

  Widget _buildDocTile(ArchiveDocument doc) {
    final id = doc.id;
    final selected = id != null && _selected.contains(id);
    final label = documentLabelForCourseType(
      widget.courseType,
      doc.documentType,
    );
    return CheckboxListTile(
      value: selected,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: id == null || _archiving
          ? null
          : (value) => setState(() {
                if (value == true) {
                  _selected.add(id);
                } else {
                  _selected.remove(id);
                }
              }),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${doc.title} · ${doc.status == 'archived' ? '已归档' : '待归档'}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }
}
