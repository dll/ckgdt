import 'package:flutter/material.dart';

import '../../../../core/design/noir_tokens.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/assessment_dao.dart';

/// 答辩项目信息面板：展示某学生的班级/小组/项目/技术栈与四项报告评分。
/// 学生答辩页用当前登录 userId，教师主播页用当前活跃答辩学生 userId。
class DefenseProjectInfoPanel extends StatefulWidget {
  final String userId;
  final bool compact;

  const DefenseProjectInfoPanel({super.key, required this.userId, this.compact = false});

  @override
  State<DefenseProjectInfoPanel> createState() => _DefenseProjectInfoPanelState();
}

class _DefenseProjectInfoPanelState extends State<DefenseProjectInfoPanel> {
  final _dao = AssessmentDao();
  Map<String, dynamic>? _cover;
  Map<String, String?>? _tech;
  bool _loading = true;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DefenseProjectInfoPanel old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    if (widget.userId.isEmpty) {
      if (mounted) setState(() { _loading = false; });
      return;
    }
    if (_loadedFor == widget.userId) return;
    _loadedFor = widget.userId;
    if (mounted) setState(() { _loading = true; });
    try {
      final cover = await _dao.getCoverData(widget.userId);
      final tech = await _dao.getStudentGroupTechInfo(widget.userId);
      if (!mounted) return;
      setState(() { _cover = cover; _tech = tech; _loading = false; });
    } catch (e, st) {
      swallowDebug(e, tag: 'DefenseProjectInfo.load', stack: st);
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _wrap(const Center(
        child: Padding(padding: EdgeInsets.all(16),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))));
    }
    final cover = _cover;
    if (cover == null) {
      return _wrap(Padding(padding: const EdgeInsets.all(12),
        child: Text('暂无答辩项目信息',
          style: TextStyle(fontSize: 12, color: NoirTokens.paper.withValues(alpha: 0.4)))));
    }

    final className = cover['className'] as String? ?? '';
    final groupName = cover['groupName'] as String? ?? '';
    final projectName = cover['projectName'] as String? ?? '';
    final scores = (cover['scores'] as Map?)?.cast<String, int>() ?? const <String, int>{};
    final techStack = _tech?['techStack'];

    return _wrap(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Icon(Icons.assignment_ind, size: 16, color: NoirTokens.accent),
          const SizedBox(width: 6),
          Text('答辩项目',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NoirTokens.paper)),
        ]),
        const SizedBox(height: 8),
        if (projectName.isNotEmpty)
          _line(Icons.folder_special, projectName, bold: true),
        if (groupName.isNotEmpty) _line(Icons.groups, groupName),
        if (className.isNotEmpty) _line(Icons.class_, className),
        if (techStack != null && techStack.isNotEmpty) _line(Icons.code, techStack),
        if (scores.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6,
            children: scores.entries.map((e) => _scoreChip(e.key, e.value)).toList()),
        ],
      ],
    ));
  }

  Widget _wrap(Widget child) => Container(
    padding: EdgeInsets.all(widget.compact ? 10 : 14),
    decoration: BoxDecoration(
      color: NoirTokens.ink.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: NoirTokens.accent.withValues(alpha: 0.2)),
    ),
    child: child,
  );

  Widget _line(IconData icon, String text, {bool bold = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: NoirTokens.paper.withValues(alpha: 0.5)),
      const SizedBox(width: 6),
      Expanded(child: Text(text,
        style: TextStyle(fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: NoirTokens.paper.withValues(alpha: bold ? 0.95 : 0.7)))),
    ]),
  );

  Widget _scoreChip(String label, int score) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: NoirTokens.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: NoirTokens.accent.withValues(alpha: 0.25)),
    ),
    child: Text('$label $score',
      style: const TextStyle(fontSize: 11, color: NoirTokens.accent, fontWeight: FontWeight.w600)),
  );
}
