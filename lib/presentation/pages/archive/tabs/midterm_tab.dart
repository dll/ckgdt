import 'package:flutter/material.dart';
import '../../../../data/local/archive_dao.dart';
import '../../../../services/agent/agents/archive_agent.dart';
import '../widgets/midterm_check_panel.dart';
import 'period_tab.dart';

/// 期中 tab —— 复用 [ArchivePeriodTab] 的完整文档流水线（生成 / 结构化审核 /
/// 一键打印 / docx 归档 + zip + 剪贴板分享 / 5 态徽标）。
///
/// 期中资料保留正式文档入口，同时提供顶部勾选式核查面板。
/// 教师勾选进度、作业、期中考试材料后，可一键生成/更新 08、15、16 三份归档文档。
class MidtermTab extends StatefulWidget {
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
  State<MidtermTab> createState() => _MidtermTabState();
}

class _MidtermTabState extends State<MidtermTab> {
  int _refreshTick = 0;

  @override
  Widget build(BuildContext context) {
    return ArchivePeriodTab(
      key: ValueKey('midterm-$_refreshTick-${widget.courseType}'),
      periodKey: 'midterm',
      courseType: widget.courseType,
      dao: widget.dao,
      agent: widget.agent,
      extraHeader: [
        MidtermCheckPanel(
          courseType: widget.courseType,
          dao: widget.dao,
          onSaved: () => setState(() => _refreshTick++),
        ),
      ],
    );
  }
}
