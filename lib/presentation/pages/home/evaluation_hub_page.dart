import 'package:flutter/material.dart';
import '../lab/lab_tasks_page.dart';
import '../assessment/assessment_page.dart';
import '../works/works_page.dart';
import '../../../services/navigation_service.dart';
import '../../../services/settings_service.dart';

/// 评价中心 — 聚合实验、考核、作品三个模块（教师端 Tab 精简）
class EvaluationHubPage extends StatefulWidget {
  const EvaluationHubPage({super.key});

  @override
  State<EvaluationHubPage> createState() => _EvaluationHubPageState();
}

class _EvaluationHubPageState extends State<EvaluationHubPage> {
  int _subIndex = 0;
  int _passScore = SettingsService.defaultEvaluationPassScore;

  static const _subLabels = ['实验', '考核', '作品'];

  @override
  void initState() {
    super.initState();
    _loadPassScore();
    NavigationService.instance.innerTabSeq.addListener(_applyInnerTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInnerTab());
  }

  Future<void> _loadPassScore() async {
    final score = await SettingsService.getEvaluationPassScore();
    if (!mounted) return;
    setState(() => _passScore = score);
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

  Future<void> _showPassScoreDialog() async {
    var value = _passScore.toDouble();
    final saved = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('评价达标分数线'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('学生提交实验、考核、作品时，AI 初评达到该分数线后才允许提交成功。'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('分数线'),
                    const Spacer(),
                    Text('${value.round()} 分',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: value,
                  min: 60,
                  max: 100,
                  divisions: 40,
                  label: '${value.round()}',
                  onChanged: (v) => setDialogState(() => value = v),
                ),
                Wrap(
                  spacing: 8,
                  children: [60, 70, 80, 85, 90, 95].map((score) {
                    final selected = value.round() == score;
                    return ChoiceChip(
                      label: Text('$score'),
                      selected: selected,
                      onSelected: (_) =>
                          setDialogState(() => value = score.toDouble()),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, value.round()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await SettingsService.setEvaluationPassScore(saved);
    if (!mounted) return;
    setState(() => _passScore = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('评价达标分数线已设为 $saved 分')),
    );
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
              const SizedBox(width: 8),
              Tooltip(
                message: '评价达标分数线',
                child: OutlinedButton.icon(
                  onPressed: _showPassScoreDialog,
                  icon: const Icon(Icons.tune, size: 16),
                  label: Text('达标 $_passScore'),
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
