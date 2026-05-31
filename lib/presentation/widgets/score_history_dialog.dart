import 'package:flutter/material.dart';
import '../../data/local/score_audit_dao.dart';

/// 通用 "成绩修改历史" 弹窗。
///
/// 取 `score_audit_log` 表里某条记录的全部变更记录，按时间倒序展示。
/// 谁、何时、改了什么字段、原因是什么。
class ScoreHistoryDialog extends StatelessWidget {
  final String tableName;
  final int rowId;
  final String? title;

  const ScoreHistoryDialog({
    super.key,
    required this.tableName,
    required this.rowId,
    this.title,
  });

  static Future<void> show(
    BuildContext context, {
    required String tableName,
    required int rowId,
    String? title,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ScoreHistoryDialog(
        tableName: tableName,
        rowId: rowId,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.history, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title ?? '修改历史', style: const TextStyle(fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: ScoreAuditDao.instance.getHistory(tableName, rowId),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Text('加载失败：${snap.error}',
                  style: const TextStyle(color: Colors.red));
            }
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return const Center(
                child: Text('暂无修改记录',
                    style: TextStyle(color: Colors.grey)),
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _buildRow(rows[i]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭')),
      ],
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final ts = row['changed_at'] as String? ?? '';
    final scorer = row['scorer_name'] ?? row['scorer_id'] ?? '?';
    final field = row['field'] as String? ?? '';
    final oldV = row['old_value'] as String? ?? '∅';
    final newV = row['new_value'] as String? ?? '∅';
    final reason = row['reason'] as String? ?? '';
    final op = row['op'] as String? ?? 'update';

    final opChip = switch (op) {
      'create' => _chip('录入', Colors.green),
      'delete' => _chip('删除', Colors.red),
      _ => _chip('修改', Colors.blue),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              opChip,
              const SizedBox(width: 8),
              Expanded(
                child: Text('$scorer · $field',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(_formatTs(ts),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$oldV  →  $newV',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '原因：$reason',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _formatTs(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
