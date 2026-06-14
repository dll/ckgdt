import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/error_handler.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../services/archive/pandoc_service.dart';
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
      final materials = docs
          .where(
              (d) => const {'beginning', 'midterm', 'final'}.contains(d.period))
          .where((d) => (d.content ?? '').trim().isNotEmpty)
          .toList()
        ..sort((a, b) {
          final p = _periodOrder(a.period).compareTo(_periodOrder(b.period));
          if (p != 0) return p;
          return a.createdAt.compareTo(b.createdAt);
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

  int _periodOrder(String period) {
    const order = {'beginning': 0, 'midterm': 1, 'final': 2, 'archive': 3};
    return order[period] ?? 99;
  }

  Future<void> _archiveSelected() async {
    if (_selected.isEmpty || _archiving) return;
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结课打包仅在 Windows/macOS/Linux 桌面端可用')),
      );
      return;
    }

    final selectedDocs =
        _docs.where((d) => d.id != null && _selected.contains(d.id)).toList();
    if (selectedDocs.isEmpty) return;

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
      );
      await Clipboard.setData(ClipboardData(text: zipPath));
      await _load();
      if (!mounted) return;
      final message = failures.isEmpty
          ? '已归档并打包 ${outputPaths.length} 份材料，zip 路径已复制。'
          : '已归档 ${outputPaths.length} 份，失败 ${failures.length} 份，zip 路径已复制。';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty || _archiving
                        ? null
                        : _archiveSelected,
                    icon: _archiving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_zip, size: 18),
                    label: Text('归档打包(${_selected.length})'),
                  ),
                ],
              ),
              const Divider(height: 12),
              ..._docs.map((doc) {
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
                    '${periodLabel(doc.period)} · $label',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${doc.title} · ${doc.status == 'archived' ? '已归档' : '待归档'}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
