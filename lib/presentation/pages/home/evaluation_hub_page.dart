import 'package:flutter/material.dart';
import '../lab/lab_tasks_page.dart';
import '../assessment/assessment_page.dart';
import '../works/works_page.dart';
import '../../../services/navigation_service.dart';

/// 评价中心 — 聚合实验、考核、作品三个模块（教师端 Tab 精简）
class EvaluationHubPage extends StatefulWidget {
  const EvaluationHubPage({super.key});

  @override
  State<EvaluationHubPage> createState() => _EvaluationHubPageState();
}

class _EvaluationHubPageState extends State<EvaluationHubPage> {
  int _subIndex = 0;

  static const _subLabels = ['实验', '考核', '作品'];

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
    final req = NavigationService.instance.consumeInnerTab('evaluation');
    if (req == null) return;
    for (int i = 0; i < _subLabels.length; i++) {
      if (req.tabKeyword.contains(_subLabels[i]) ||
          _subLabels[i].contains(req.tabKeyword)) {
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
          color: primary.withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.science, size: 16),
                        label: Text('实验')),
                    ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.assessment, size: 16),
                        label: Text('考核')),
                    ButtonSegment(
                        value: 2,
                        icon: Icon(Icons.workspace_premium, size: 16),
                        label: Text('作品')),
                  ],
                  selected: {_subIndex},
                  onSelectionChanged: (s) =>
                      setState(() => _subIndex = s.first),
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
              LabTasksPage(),
              AssessmentPage(),
              WorksPage(),
            ],
          ),
        ),
      ],
    );
  }
}
