import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/workload_dao.dart';
import '../../../widgets/agent_chat_overlay.dart';

class WorkloadTab extends StatefulWidget {
  const WorkloadTab({super.key});

  @override
  State<WorkloadTab> createState() => _WorkloadTabState();
}

class _WorkloadTabState extends State<WorkloadTab> {
  final _dao = WorkloadDao();
  List<TeachingWorkload> _courseWorkloads = [];
  List<TeachingWorkload> _otherWorkloads = [];
  Map<String, double> _stats = {'total': 0, 'approved': 0, 'pending': 0};
  bool _loading = true;
  String? _currentTeacherId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await _dao.getWorkloads(semester: _currentSemester());
      _courseWorkloads = all
          .where((w) => w.workloadType == '理论工作量')
          .toList();
      _otherWorkloads = all
          .where((w) => w.workloadType != '理论工作量')
          .toList();
      _stats = await _dao.getStats();
    } catch (e, st) {
      swallowDebug(e, tag: 'WorkloadTab._load', stack: st);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _currentSemester() {
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    if (m >= 2 && m <= 7) return '$y-1';
    return '$y-2';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSummaryCards(primary),
          const SizedBox(height: 12),
          _buildActionButtons(primary),
          const SizedBox(height: 16),
          _buildSectionHeader('课程工作量', Icons.menu_book_outlined, primary),
          const SizedBox(height: 8),
          if (_courseWorkloads.isEmpty)
            _buildEmptyCard('暂无课程工作量数据')
          else
            _buildCourseWorkloadTable(primary),
          const SizedBox(height: 16),
          _buildSectionHeader('其他工作量', Icons.workspaces_outlined, primary),
          const SizedBox(height: 8),
          ..._otherWorkloads.map((w) => _buildOtherWorkloadCard(w, primary)),
          const SizedBox(height: 8),
          _buildAddOtherButton(primary),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(Color primary) {
    return Row(
      children: [
        _summaryCard('总工作量', _stats['total'] ?? 0, Colors.blue),
        const SizedBox(width: 8),
        _summaryCard('已审核', _stats['approved'] ?? 0, Colors.green),
        const SizedBox(width: 8),
        _summaryCard('待审核', _stats['pending'] ?? 0, Colors.orange),
      ],
    );
  }

  Widget _summaryCard(String label, double value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(Color primary) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _onAiReview,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI 审核'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _onTeacherConfirm,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('教师确认'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _onExport,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('导出'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color primary) {
    return Row(
      children: [
        Icon(icon, size: 18, color: primary),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
      ],
    );
  }

  Widget _buildEmptyCard(String msg) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(msg, style: const TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }

  Widget _buildCourseWorkloadTable(Color primary) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(primary.withValues(alpha: 0.08)),
          columns: const [
            DataColumn(label: Text('课程名称', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('班级', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('课时', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('系数', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('规模', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('工作量', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('状态', style: TextStyle(fontSize: 12))),
          ],
          rows: _courseWorkloads.map((w) {
            final status = _statusWidget(w.status);
            return DataRow(cells: [
              DataCell(Text(w.courseName, style: const TextStyle(fontSize: 12))),
              DataCell(Text(w.classNames ?? '-', style: const TextStyle(fontSize: 12))),
              DataCell(Text('${w.classHours}', style: const TextStyle(fontSize: 12))),
              DataCell(Text(w.courseCoefficient.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
              DataCell(Text(w.scaleCoefficient.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
              DataCell(Text(w.computedWorkload.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              DataCell(status),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _statusWidget(String status) {
    final (label, color) = switch (status) {
      'approved' => ('已审核', Colors.green),
      'submitted' => ('待审核', Colors.orange),
      'rejected' => ('已退回', Colors.red),
      _ => ('草稿', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildOtherWorkloadCard(TeachingWorkload w, Color primary) {
    return Card(
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: primary.withValues(alpha: 0.1),
          child: Text(w.otherCategory?.substring(0, 1) ?? '其',
              style: TextStyle(fontSize: 12, color: primary)),
        ),
        title: Text(w.otherCategory ?? w.workloadType,
            style: const TextStyle(fontSize: 13)),
        subtitle: Text(w.remark ?? '', style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${w.declaredWorkload.toStringAsFixed(1)} 学时',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(width: 8),
            _statusWidget(w.status),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOtherButton(Color primary) {
    return OutlinedButton.icon(
      onPressed: _showAddOtherDialog,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('添加其他工作量'),
    );
  }

  Future<void> _showAddOtherDialog() async {
    final categories = [
      '毕业论文评阅答辩',
      '三下乡',
      '大创项目',
      '开放实验项目',
      '监考工作量',
      '指导研究生工作量',
      '劳动教育（实践）',
      '公共选修课',
      '毕业设计指导',
      '其他',
    ];
    String selected = categories.first;
    final hoursCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加其他工作量'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                items: categories.map((c) {
                  return DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)));
                }).toList(),
                onChanged: (v) => setDialogState(() => selected = v ?? selected),
                decoration: const InputDecoration(
                  labelText: '工作量类型',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hoursCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                decoration: const InputDecoration(
                  labelText: '工作量（学时）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
          ],
        ),
      ),
    );

    if (result == true && hoursCtrl.text.isNotEmpty) {
      final hours = double.tryParse(hoursCtrl.text) ?? 0;
      final w = TeachingWorkload(
        teacherId: _currentTeacherId ?? '',
        teacherName: '',
        courseName: selected,
        workloadType: '其他工作量',
        otherCategory: selected,
        declaredWorkload: hours,
        remark: remarkCtrl.text,
        status: 'draft',
        semester: _currentSemester(),
      );
      await _dao.insert(w);
      await _load();
    }
  }

  Future<void> _onAiReview() async {
    if (_courseWorkloads.isEmpty && _otherWorkloads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无工作量数据可审核')),
      );
      return;
    }
    // Build review prompt
    final buffer = StringBuffer();
    buffer.writeln('请审核以下教师工作量数据，检查计算是否正确、是否有异常：\n');
    for (final w in _courseWorkloads) {
      buffer.writeln(
          '【课程】${w.courseName} | 班级: ${w.classNames} | 课时: ${w.classHours} | 课程系数: ${w.courseCoefficient} | 规模系数: ${w.scaleCoefficient} | 工作量: ${w.computedWorkload.toStringAsFixed(1)}');
    }
    for (final w in _otherWorkloads) {
      buffer.writeln(
          '【其他】${w.otherCategory} | 工作量: ${w.declaredWorkload} | 备注: ${w.remark}');
    }
    buffer.writeln('\n总工作量: ${(_stats['total'] ?? 0).toStringAsFixed(1)}');
    buffer.writeln('请给出审核意见，包括：1)计算是否正确 2)数据是否合理 3)改进建议');

    if (!mounted) return;
    AgentChatOverlay.show(
      context,
      agentId: 'archive',
      initialContext: buffer.toString(),
    );
  }

  Future<void> _onTeacherConfirm() async {
    final unconfirmed = [..._courseWorkloads, ..._otherWorkloads]
        .where((w) => w.status != 'approved')
        .toList();
    if (unconfirmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有工作量已确认')),
      );
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('教师确认'),
        content: Text('确认 ${unconfirmed.length} 条工作量记录？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (result == true) {
      for (final w in unconfirmed) {
        await _dao.update(w.copyWith(
          status: 'approved',
          verifiedWorkload: w.declaredWorkload > 0
              ? w.declaredWorkload
              : w.computedWorkload,
          teacherConfirmed: true,
        ));
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已确认 ${unconfirmed.length} 条工作量')),
        );
      }
    }
  }

  Future<void> _onExport() async {
    final buffer = StringBuffer();
    buffer.writeln('工作量报表');
    buffer.writeln('学期: ${_currentSemester()}');
    buffer.writeln('导出时间: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln('');
    buffer.writeln('=== 课程工作量 ===');
    buffer.writeln('课程名称\t班级\t课时\t系数\t规模系数\t工作量\t状态');
    for (final w in _courseWorkloads) {
      buffer.writeln(
          '${w.courseName}\t${w.classNames ?? ''}\t${w.classHours}\t${w.courseCoefficient}\t${w.scaleCoefficient}\t${w.computedWorkload.toStringAsFixed(1)}\t${w.status}');
    }
    buffer.writeln('');
    buffer.writeln('=== 其他工作量 ===');
    buffer.writeln('类型\t工作量\t备注\t状态');
    for (final w in _otherWorkloads) {
      buffer.writeln(
          '${w.otherCategory}\t${w.declaredWorkload}\t${w.remark ?? ''}\t${w.status}');
    }
    buffer.writeln('');
    buffer.writeln('总计: ${(_stats['total'] ?? 0).toStringAsFixed(1)}');
    buffer.writeln('已审核: ${(_stats['approved'] ?? 0).toStringAsFixed(1)}');
    buffer.writeln('待审核: ${(_stats['pending'] ?? 0).toStringAsFixed(1)}');

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('工作量报表已复制到剪贴板')),
      );
    }
  }
}
