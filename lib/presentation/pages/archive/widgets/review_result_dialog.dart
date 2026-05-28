import 'package:flutter/material.dart';
import '../../../../data/models/archive_document_model.dart';
import '../../../../services/archive/ai_audit_processor.dart';
import '../../../../services/archive/processor_registry.dart';
import '../../../../services/archive/review_result.dart';

/// AI 审核结果展示对话框（commit 4 核心 UI）。
///
/// **能力**：
///   - 展示 errors / warnings / passed 三栏（按等级分色）
///   - 每条 finding 显示维度 + 证据 + 修订建议 + layer（粗审/细审）
///   - 教师可点 [⊘ 忽略此条] 把某条 warning 加进 ignoredKeys
///   - 教师可点 [🔄 再审] 跑一次 reviewTarget（带上 ignoredKeys）
///   - 顶部状态条：综合评级 + 置信度 + 审核耗时
///
/// **回调**：
///   - [onFindingIgnored]：教师忽略某条后调用，父级应刷新文档列表
///   - [onReviewed]：再审完成后调用，父级应刷新文档列表 + 重开本对话框
class ReviewResultDialog extends StatefulWidget {
  final ArchiveDocument target;
  final ReviewResult initial;
  final void Function(ArchiveDocument updated)? onUpdated;

  const ReviewResultDialog({
    super.key,
    required this.target,
    required this.initial,
    this.onUpdated,
  });

  @override
  State<ReviewResultDialog> createState() => _ReviewResultDialogState();
}

class _ReviewResultDialogState extends State<ReviewResultDialog> {
  late ArchiveDocument _doc;
  late ReviewResult _review;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.target;
    _review = widget.initial;
  }

  AiAuditProcessor? _findProcessor() {
    // 找指向当前 docType 的审核处理器（这里 _doc 是被审目标，如教学大纲）
    final reg = ProcessorRegistry.instance;
    for (final t in reg.registeredDocTypes) {
      final p = reg.find(t);
      if (p is AiAuditProcessor && p.targetDocType == _doc.documentType) {
        return p;
      }
    }
    return null;
  }

  Future<void> _ignore(String findingKey) async {
    final p = _findProcessor();
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final updated = await p.ignoreFinding(_doc, findingKey);
      setState(() {
        _review = updated;
        _busy = false;
      });
      // 通知父级刷新（doc 的 reviewJson 已更新）
      widget.onUpdated?.call(_doc);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('忽略失败：$e')),
        );
      }
    }
  }

  Future<void> _reAudit() async {
    final p = _findProcessor();
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final updated = await p.reviewTarget(_doc);
      setState(() {
        _review = updated;
        _busy = false;
      });
      widget.onUpdated?.call(_doc);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('再审失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
        child: Column(
          children: [
            _buildHeader(cs),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_review.errors.isNotEmpty) ...[
                      _sectionHeader('❌ 必须修改', _review.errors.length, cs.error),
                      ..._review.errors
                          .map((f) => _findingCard(f, canIgnore: false)),
                      const SizedBox(height: 16),
                    ],
                    if (_review.warnings.isNotEmpty) ...[
                      _sectionHeader('⚠️ 建议改进', _review.warnings.length,
                          Colors.orange),
                      ..._review.warnings
                          .map((f) => _findingCard(f, canIgnore: true)),
                      const SizedBox(height: 16),
                    ],
                    if (_review.passed.isNotEmpty) ...[
                      _sectionHeader(
                          '✅ 通过项', _review.passed.length, Colors.green),
                      ..._review.passed
                          .map((f) => _findingCard(f, canIgnore: false)),
                    ],
                    if (_review.totalFindings == 0)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('暂无审核结果')),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    final overallLabel = _overallLabel(_review.overall);
    final pct = (_review.confidence * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.rate_review, color: cs.primary),
          const SizedBox(width: 8),
          Text('AI 审核 — ${_doc.title}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Chip(label: Text(overallLabel)),
          const SizedBox(width: 6),
          Chip(label: Text('置信度 $pct%')),
          const SizedBox(width: 6),
          Chip(label: Text('${_review.latencyMs}ms')),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: 6),
          Text('$label ($count)',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _findingCard(Finding f, {required bool canIgnore}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${f.level}  ${f.dimension}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Chip(
                  label: Text(
                    f.layer == 'numerical' ? '细审 数字' : '粗审 结构',
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _kvRow('证据', f.evidence),
            _kvRow('建议', f.suggestion),
            if (canIgnore && !_busy)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _ignore(f.key),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('忽略此条'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
                text: '$k：',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.grey)),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (_review.ignoredKeys.isNotEmpty)
            Text('已忽略 ${_review.ignoredKeys.length} 项',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const Spacer(),
          if (_busy) ...[
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
          ],
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _reAudit,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('再审'),
          ),
        ],
      ),
    );
  }

  String _overallLabel(String overall) {
    return {
          'approved': '✅ 通过',
          'needs_revision': '⚠️ 需修订',
          'rejected': '❌ 不合格',
          'pending': '⏳ 待审核',
        }[overall] ??
        overall;
  }
}
