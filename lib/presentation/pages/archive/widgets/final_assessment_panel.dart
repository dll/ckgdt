import 'package:flutter/material.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/assessment_dao.dart';

/// 期末特有面板：考核材料统计（分组 / 项目 / 答辩记录）+ 报告完成度清单。
///
/// 自包含状态：懒加载经 [AssessmentDao]，不依赖父 [ArchivePeriodTab]。
/// 作为 extraHeader 注入到期末 tab 文档列表上方。
class FinalAssessmentPanel extends StatefulWidget {
  const FinalAssessmentPanel({super.key});

  @override
  State<FinalAssessmentPanel> createState() => _FinalAssessmentPanelState();
}

class _FinalAssessmentPanelState extends State<FinalAssessmentPanel> {
  final _dao = AssessmentDao();

  int _groupCount = 0;
  int _projectCount = 0;
  int _defenseCount = 0;
  bool _loading = false;

  Future<void> _loadAssessmentData() async {
    setState(() => _loading = true);
    try {
      final groups = await _dao.getGroups();
      final projects = await _dao.getProjects();
      final defenses = await _dao.getDefenseRecords();
      _groupCount = groups.length;
      _projectCount = projects.length;
      _defenseCount = defenses.length;
      if (mounted) setState(() => _loading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'FinalAssessmentPanel._load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.folder_special, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(child: Text('考核材料',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary))),
              TextButton.icon(
                onPressed: _loadAssessmentData,
                icon: Icon(Icons.refresh, size: 16, color: primary),
                label: Text('加载', style: TextStyle(fontSize: 12, color: primary)),
              ),
            ]),
            const SizedBox(height: 8),
            Text('来自主菜单"考核"模块：四个过程报告、四个最终报告、两个审核打印报告',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 12),
            if (_loading)
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              _materialCard(Icons.group, '考核分组', '$_groupCount 组', Colors.blue),
              const SizedBox(height: 6),
              _materialCard(Icons.assignment, '考核项目', '$_projectCount 个', Colors.purple),
              const SizedBox(height: 6),
              _materialCard(Icons.record_voice_over, '答辩记录', '$_defenseCount 条', Colors.teal),
              const SizedBox(height: 12),
              if (_groupCount == 0 && _projectCount == 0)
                Text('点击"加载"从考核模块读取分组 / 项目 / 答辩数据',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]))
              else ...[
                const Divider(),
                const Text('报告类型', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _checkRow('四个过程报告', _projectCount >= 4),
                _checkRow('四个最终报告', _defenseCount >= 4),
                _checkRow('两个审核打印报告', _groupCount >= 2),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _materialCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _checkRow(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(done ? Icons.check_circle : Icons.pending, size: 16,
            color: done ? Colors.green : Colors.orange),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, color: done ? Colors.green[700] : Colors.orange[700])),
        const Spacer(),
        Text(done ? '已完成' : '未完成', style: TextStyle(fontSize: 12, color: done ? Colors.green : Colors.orange)),
      ]),
    );
  }
}
