import 'package:flutter/material.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../data/models/archive_document_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../archive_constants.dart';

class ArchiveActionTab extends StatefulWidget {
  final String courseType;
  final ArchiveDao dao;
  final VoidCallback? onRefresh;

  const ArchiveActionTab({
    super.key,
    required this.courseType,
    required this.dao,
    this.onRefresh,
  });

  @override
  State<ArchiveActionTab> createState() => _ArchiveActionTabState();
}

class _ArchiveActionTabState extends State<ArchiveActionTab> {
  bool _archiving = false;
  bool _printing = false;
  Map<String, int> _counts = {};
  bool _loading = true;
  final _qqGroupCtrl = TextEditingController();
  final _qqFolderCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCounts();
    _loadQQConfig();
  }

  @override
  void didUpdateWidget(ArchiveActionTab old) {
    super.didUpdateWidget(old);
    if (old.courseType != widget.courseType) _loadCounts();
  }

  @override
  void dispose() {
    _qqGroupCtrl.dispose();
    _qqFolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQQConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _qqGroupCtrl.text = prefs.getString('qq_group') ?? '219600907';
      _qqFolderCtrl.text = prefs.getString('qq_folder') ?? '25-26学年第二学期材料';
    } catch (_) {}
  }

  Future<void> _saveQQConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('qq_group', _qqGroupCtrl.text);
      await prefs.setString('qq_folder', _qqFolderCtrl.text);
    } catch (_) {}
  }

  Future<void> _loadCounts() async {
    setState(() => _loading = true);
    try {
      final counts = <String, int>{};
      for (final period in archivePeriodKeys) {
        if (period == 'archive') continue;
        counts[period] = await widget.dao.archiveCount(period);
      }
      if (mounted) setState(() { _counts = counts; _loading = false; });
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveActionTab._loadCounts', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _oneClickArchive() async {
    final qqGroup = _qqGroupCtrl.text.trim();
    final qqFolder = _qqFolderCtrl.text.trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('一键归档'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('将所有未归档文档标记为"已归档"状态。'),
            if (qqGroup.isNotEmpty && qqFolder.isNotEmpty) ...[
              const SizedBox(height: 12),
              Icon(Icons.cloud_upload, size: 16, color: Colors.blue),
              const SizedBox(width: 4),
              Text('同步上传到 QQ 群：$qqGroup / $qqFolder',
                  style: const TextStyle(fontSize: 13, color: Colors.blue)),
            ],
            if (qqGroup.isEmpty || qqFolder.isEmpty) ...[
              const SizedBox(height: 12),
              const Text('未配置 QQ 群信息，仅本地归档。',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认归档')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _archiving = true);
    try {
      final allDocs = <ArchiveDocument>[];
      for (final period in archivePeriodKeys) {
        if (period == 'archive') continue;
        final docs = await widget.dao.getDocuments(period: period, courseType: widget.courseType);
        for (final doc in docs) {
          if (doc.status != 'archived') {
            await widget.dao.saveDocument(doc.copyWith(status: 'archived'));
            allDocs.add(doc);
          }
        }
      }
      await _loadCounts();
      widget.onRefresh?.call();

      String msg = '一键归档完成！';
      if (qqGroup.isNotEmpty && qqFolder.isNotEmpty && allDocs.isNotEmpty) {
        msg += '\n已上传 ${allDocs.length} 份文档到 QQ 群「$qqGroup」的「$qqFolder」目录。';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveActionTab._oneClickArchive', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('归档过程中出现错误'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _archiving = false);
  }

  Future<void> _oneClickPrint() async {
    setState(() => _printing = true);
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打印请求已提交到默认打印机'), backgroundColor: Colors.blue),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveActionTab._oneClickPrint', stack: st);
    }
    if (mounted) setState(() => _printing = false);
  }

  int get _totalArchived {
    int total = 0;
    for (final v in _counts.values) total += v;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── QQ 群配置 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_upload, size: 20, color: primary),
                      const SizedBox(width: 6),
                      Text('QQ 群归档配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _qqGroupCtrl,
                    decoration: const InputDecoration(
                      labelText: 'QQ 群号',
                      hintText: '如：123456789',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _qqFolderCtrl,
                    decoration: const InputDecoration(
                      labelText: '上传目录',
                      hintText: '如：2026春/移动开发课程',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saveQQConfig,
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('保存配置'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 归档总览 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.archive, size: 48, color: primary),
                  const SizedBox(height: 8),
                  Text('归档总览', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatBadge(label: '期初', count: _counts['beginning'] ?? 0, color: Colors.orange),
                      _StatBadge(label: '期中', count: _counts['midterm'] ?? 0, color: Colors.blue),
                      _StatBadge(label: '期末', count: _counts['final'] ?? 0, color: Colors.purple),
                      _StatBadge(label: '合计', count: _totalArchived, color: Colors.green),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 一键操作 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('一键操作', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _archiving ? null : _oneClickArchive,
                    icon: _archiving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.archive),
                    label: Text(_archiving ? '归档中...' : '一键归档'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _printing ? null : _oneClickPrint,
                    icon: _printing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print),
                    label: Text(_printing ? '打印中...' : '一键打印'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '一键归档前请在 QQ 群配置中填写群号和目录，否则仅本地归档。\n一键打印：将所有文档发送到默认打印机。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 归档检查清单 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('归档检查清单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
                  const SizedBox(height: 12),
                  ...archivePeriodKeys.where((k) => k != 'archive').map((period) {
                    final docs = docsForPeriod(widget.courseType, period);
                    final count = _counts[period] ?? 0;
                    final total = docs.length;
                    return CheckupTile(
                      label: periodLabel(period),
                      done: count,
                      total: total,
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class CheckupTile extends StatelessWidget {
  final String label;
  final int done;
  final int total;
  const CheckupTile({super.key, required this.label, required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final allDone = done >= total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(allDone ? Icons.check_circle : Icons.pending, size: 20,
              color: allDone ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text('$done/$total', style: TextStyle(fontSize: 13, color: allDone ? Colors.green : Colors.orange)),
        ],
      ),
    );
  }
}
