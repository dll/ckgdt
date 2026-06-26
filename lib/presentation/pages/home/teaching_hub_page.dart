import 'package:flutter/material.dart';
import '../learning/learning_hub_page.dart';
import '../learning/ordinary_score_tab.dart';
import '../classroom/classroom_page.dart';
import '../../../services/navigation_service.dart';

/// 教学中心 — 聚合教学、课堂、平时成绩三个模块（教师端 Tab 精简）
class TeachingHubPage extends StatefulWidget {
  const TeachingHubPage({super.key});

  @override
  State<TeachingHubPage> createState() => _TeachingHubPageState();
}

class _TeachingHubPageState extends State<TeachingHubPage> {
  int _subIndex = 0;

  static const _subLabels = ['教学', '课堂', '平时成绩'];

  @override
  void initState() {
    super.initState();
    NavigationService.instance.innerTabSeq.addListener(_applyInnerTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInnerTab());
  }

  @override
  void dispose() {
    NavigationService.instance.innerTabSeq.removeListener(_applyInnerTab);
    super.dispose();
  }

  void _applyInnerTab() {
    if (!mounted) return;
    final req = NavigationService.instance.consumeInnerTab('teaching');
    if (req == null) return;
    for (int i = 0; i < _subLabels.length; i++) {
      if (req.tabKeyword.contains(_subLabels[i]) || _subLabels[i].contains(req.tabKeyword)) {
        setState(() => _subIndex = i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Container(
          color: primary.withOpacity(0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, icon: Icon(Icons.menu_book, size: 16), label: Text('教学')),
                    ButtonSegment(value: 1, icon: Icon(Icons.cast_for_education, size: 16), label: Text('课堂')),
                    ButtonSegment(value: 2, icon: Icon(Icons.assignment_turned_in, size: 16), label: Text('平时成绩')),
                  ],
                  selected: {_subIndex},
                  onSelectionChanged: (s) => setState(() => _subIndex = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 13, color: primary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _subIndex,
            children: const [
              LearningHubPage(),
              ClassroomPage(),
              OrdinaryScoreTab(),
            ],
          ),
        ),
      ],
    );
  }
}
