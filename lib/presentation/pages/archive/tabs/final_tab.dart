import 'package:flutter/material.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import '../widgets/final_assessment_panel.dart';
import 'period_tab.dart';

/// 期末 tab —— 复用 [ArchivePeriodTab] 的完整文档流水线（生成 / 结构化审核 /
/// 一键打印 / docx 归档 + zip + 剪贴板分享 / 5 态徽标），并在文档列表上方附加
/// 期末特有的"考核材料统计"面板（分组 / 项目 / 答辩 + 报告完成度清单）。
class FinalTab extends StatelessWidget {
  final String courseType;
  final ArchiveDao dao;
  final ArchiveAgent agent;

  const FinalTab({
    super.key,
    required this.courseType,
    required this.dao,
    required this.agent,
  });

  @override
  Widget build(BuildContext context) {
    return ArchivePeriodTab(
      periodKey: 'final',
      courseType: courseType,
      dao: dao,
      agent: agent,
      extraHeader: const [FinalAssessmentPanel()],
    );
  }
}
