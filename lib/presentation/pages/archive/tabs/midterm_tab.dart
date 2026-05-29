import 'package:flutter/material.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import '../widgets/midterm_special_panels.dart';
import 'period_tab.dart';

/// 期中 tab —— 复用 [ArchivePeriodTab] 的完整文档流水线（生成 / 结构化审核 /
/// 一键打印 / docx 归档 + zip + 剪贴板分享 / 5 态徽标），并在文档列表上方附加
/// 期中特有的"进度一致性检查 + 作业/批阅统计"面板。
class MidtermTab extends StatelessWidget {
  final String courseType;
  final ArchiveDao dao;
  final ArchiveAgent agent;

  const MidtermTab({
    super.key,
    required this.courseType,
    required this.dao,
    required this.agent,
  });

  @override
  Widget build(BuildContext context) {
    return ArchivePeriodTab(
      periodKey: 'midterm',
      courseType: courseType,
      dao: dao,
      agent: agent,
      extraHeader: const [MidtermSpecialPanels()],
    );
  }
}
