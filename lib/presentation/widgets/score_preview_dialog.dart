import 'package:flutter/material.dart';

/// 成绩预览对话框：以 DataTable 形式展示成绩列表。
///
/// [title] — 对话框标题
/// [columns] — 列定义（标签 + 宽度占比）
/// [rows] — 数据行，每行对应 [columns] 的值列表
/// [exportCallback] — 可选，「导出CSV」按钮回调
class ScorePreviewDialog extends StatelessWidget {
  final String title;
  final List<ScoreColumn> columns;
  final List<List<dynamic>> rows;
  final VoidCallback? onExport;
  final String? subtitle;

  const ScorePreviewDialog({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.onExport,
    this.subtitle,
  });

  /// 工厂：实验成绩
  factory ScorePreviewDialog.lab(List<Map<String, dynamic>> data,
      {VoidCallback? onExport}) {
    final columns = [
      const ScoreColumn('学号', flex: 2),
      const ScoreColumn('姓名', flex: 2),
      const ScoreColumn('章节', flex: 2),
      const ScoreColumn('实验任务', flex: 3),
      const ScoreColumn('满分', flex: 1),
      const ScoreColumn('得分', flex: 1),
      const ScoreColumn('状态', flex: 1),
    ];
    final rows = data.map((r) => [
      r['user_id'] ?? '',
      r['real_name'] ?? '',
      r['chapter'] ?? '',
      r['task_title'] ?? '',
      r['max_score']?.toString() ?? '',
      r['score']?.toString() ?? '-',
      r['status'] ?? '',
    ]).toList();
    return ScorePreviewDialog(
      title: '实验成绩预览',
      subtitle: '共 ${data.length} 条记录',
      columns: columns,
      rows: rows,
      onExport: onExport,
    );
  }

  /// 工厂：考核成绩
  factory ScorePreviewDialog.assessment(List<Map<String, dynamic>> data,
      {VoidCallback? onExport}) {
    final columns = [
      const ScoreColumn('小组', flex: 2),
      const ScoreColumn('项目', flex: 2),
      const ScoreColumn('功能(25)', flex: 1),
      const ScoreColumn('技术(20)', flex: 1),
      const ScoreColumn('整合(25)', flex: 1),
      const ScoreColumn('质量(15)', flex: 1),
      const ScoreColumn('文档(15)', flex: 1),
      const ScoreColumn('总分', flex: 1),
    ];
    final rows = data.map((r) => [
      r['group_name'] ?? '',
      r['project_name'] ?? '',
      r['score_functionality']?.toString() ?? '',
      r['score_tech_depth']?.toString() ?? '',
      r['score_integration']?.toString() ?? '',
      r['score_quality']?.toString() ?? '',
      r['score_documentation']?.toString() ?? '',
      r['total_score']?.toString() ?? '',
    ]).toList();
    return ScorePreviewDialog(
      title: '考核成绩预览',
      subtitle: '共 ${data.length} 条记录',
      columns: columns,
      rows: rows,
      onExport: onExport,
    );
  }

  /// 工厂：作品成绩
  factory ScorePreviewDialog.works(List<Map<String, dynamic>> data,
      {VoidCallback? onExport}) {
    final columns = [
      const ScoreColumn('学生', flex: 2),
      const ScoreColumn('仓库', flex: 2),
      const ScoreColumn('作品', flex: 2),
      const ScoreColumn('功能(25)', flex: 1),
      const ScoreColumn('技术(20)', flex: 1),
      const ScoreColumn('整合(25)', flex: 1),
      const ScoreColumn('质量(15)', flex: 1),
      const ScoreColumn('文档(15)', flex: 1),
      const ScoreColumn('总分', flex: 1),
      const ScoreColumn('评分人', flex: 2),
    ];
    final rows = data.map((r) => [
      r['student_name'] ?? '',
      r['repo'] ?? '',
      r['work_title'] ?? '',
      r['score_functionality']?.toString() ?? '',
      r['score_tech_depth']?.toString() ?? '',
      r['score_integration']?.toString() ?? '',
      r['score_quality']?.toString() ?? '',
      r['score_documentation']?.toString() ?? '',
      r['total_score']?.toString() ?? '',
      r['scorer_name'] ?? '',
    ]).toList();
    return ScorePreviewDialog(
      title: '作品成绩预览',
      subtitle: '共 ${data.length} 条记录',
      columns: columns,
      rows: rows,
      onExport: onExport,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final totalFlex = columns.fold<int>(0, (sum, c) => sum + c.flex);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.table_chart, color: primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: primary)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                if (onExport != null)
                  _ActionChip(
                    icon: Icons.file_download,
                    label: '导出CSV',
                    color: Colors.teal,
                    onTap: onExport,
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: Colors.grey[500]),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // 表体
          Flexible(
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('暂无成绩数据',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 15)),
                      ],
                    ),
                  )
                : Scrollbar(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: columns.length * 80.0,
                        ),
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor:
                                WidgetStatePropertyAll(Colors.grey[50]),
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 48,
                            headingRowHeight: 40,
                            horizontalMargin: 12,
                            columnSpacing: 8,
                            columns: columns
                                .map((c) => DataColumn(
                                      label: SizedBox(
                                        width:
                                            (c.flex / totalFlex) * 400 + 40,
                                        child: Text(c.label,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ))
                                .toList(),
                            rows: List.generate(rows.length, (i) {
                              final row = rows[i];
                              return DataRow(
                                color: WidgetStateProperty.resolveWith(
                                    (states) => i.isEven
                                        ? Colors.grey.withValues(alpha: 0.03)
                                        : null),
                                cells: List.generate(
                                  columns.length,
                                  (j) => DataCell(
                                    Text(
                                      j < row.length
                                          ? row[j].toString()
                                          : '',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[800]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ScoreColumn {
  final String label;
  final int flex;
  const ScoreColumn(this.label, {this.flex = 1});
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
