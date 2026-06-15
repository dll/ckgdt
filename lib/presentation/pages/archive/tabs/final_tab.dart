import 'package:flutter/material.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import 'period_tab.dart';

/// 期末 tab —— 复用 [ArchivePeriodTab] 的完整文档流水线（生成 / 结构化审核 /
/// 一键打印 / docx 归档 + zip + 剪贴板分享 / 5 态徽标）。
///
/// 期末资料按学校课程档案袋目录组织为 00-12 正式材料，避免顶部统计面板与
/// 下方归档文档卡片重复。
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
    );
  }
}
