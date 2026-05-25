import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/score_audit_dao.dart';
import '../../../services/auth_service.dart';
import '../assessment/assessment_page.dart';
import '../works/works_page.dart';

/// 成绩录入中心 — admin/teacher 集中管理界面。
///
/// 4 类成绩入口（项目分 / 答辩分 / 作品分 / 贡献分）+ 最近修改审计列表。
/// 不复制真正的录入逻辑，只是把"项目分→考核 Tab → 录入"等路径
/// 缩成磁贴跳转，并展示自己最近的修改记录提醒"刚改过哪些"。
class GradeEntryCenterPage extends StatefulWidget {
  const GradeEntryCenterPage({super.key});

  @override
  State<GradeEntryCenterPage> createState() => _GradeEntryCenterPageState();
}

class _GradeEntryCenterPageState extends State<GradeEntryCenterPage> {
  final _auth = AuthService();
  List<Map<String, dynamic>>? _recent;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final uid = _auth.getCurrentUserId();
    if (uid == null) return;
    final rows = await ScoreAuditDao.instance.getRecentByScorer(uid, limit: 30);
    if (!mounted) return;
    setState(() => _recent = rows);
  }

  void _go(Widget Function() pageBuilder) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pageBuilder()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩录入中心'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecent,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Hero ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppGradientTheme.of(context).verticalGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.fact_check, color: Colors.white, size: 36),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('成绩录入中心',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text(
                        '4 类成绩集中入口 · 修改可审计',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── 4 类入口磁贴 ──
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _buildTile(
                Icons.assignment_turned_in,
                Colors.deepPurple,
                '项目考核分',
                'project_scores · 5 维度',
                () => _go(() => const AssessmentPage()),
              ),
              _buildTile(
                Icons.record_voice_over,
                Colors.red,
                '答辩成绩',
                'defense_records · 状态 + 分',
                () => _go(() => const AssessmentPage()),
              ),
              _buildTile(
                Icons.collections,
                Colors.teal,
                '作品评分',
                'work_scores · 5 维度',
                () => _go(() => const WorksPage()),
              ),
              _buildTile(
                Icons.thumbs_up_down,
                Colors.amber,
                '贡献度评分',
                'contribution_scores',
                () => _go(() => const AssessmentPage()),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── 我的最近修改 ──
          Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 8),
              const Text('我的最近修改',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_recent != null)
                Text('${_recent!.length} 条',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          if (_recent == null)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_recent!.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('暂无修改记录',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ..._recent!.map(_buildAuditRow),
        ],
      ),
    );
  }

  Widget _buildTile(IconData icon, Color color, String title, String subtitle,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 2),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditRow(Map<String, dynamic> row) {
    final tableName = row['table_name'] as String? ?? '?';
    final field = row['field'] as String? ?? '';
    final oldV = row['old_value'] as String? ?? '∅';
    final newV = row['new_value'] as String? ?? '∅';
    final reason = row['reason'] as String?;
    final ts = row['changed_at'] as String? ?? '';
    final op = row['op'] as String? ?? 'update';
    final tableLabel = _tableLabel(tableName);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _opColor(op).withValues(alpha: 0.15),
          child: Icon(_opIcon(op), size: 16, color: _opColor(op)),
        ),
        title: Text('$tableLabel · $field',
            style: const TextStyle(fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$oldV → $newV',
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            if (reason != null && reason.isNotEmpty)
              Text('原因：$reason',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: Text(_formatTs(ts),
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ),
    );
  }

  static String _tableLabel(String table) => switch (table) {
        'project_scores' => '项目考核',
        'work_scores' => '作品评分',
        'defense_records' => '答辩',
        'contribution_scores' => '贡献度',
        _ => table,
      };

  static IconData _opIcon(String op) => switch (op) {
        'create' => Icons.add_circle,
        'delete' => Icons.delete,
        _ => Icons.edit,
      };

  static Color _opColor(String op) => switch (op) {
        'create' => Colors.green,
        'delete' => Colors.red,
        _ => Colors.blue,
      };

  static String _formatTs(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
