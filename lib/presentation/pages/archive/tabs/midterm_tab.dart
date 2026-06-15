import 'package:flutter/material.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import 'period_tab.dart';

/// 期中 tab —— 复用 [ArchivePeriodTab] 的完整文档流水线（生成 / 结构化审核 /
/// 一键打印 / docx 归档 + zip + 剪贴板分享 / 5 态徽标）。
///
/// 期中资料只保留正式文档入口：08 课程进度执行检查、15 作业与批阅次数统计、
/// 16 期中考试，避免顶部统计面板与下方归档文档卡片重复。
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
    );
  }
}
