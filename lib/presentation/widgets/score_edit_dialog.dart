import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 成绩录入/修改弹窗的维度配置。
class ScoreDimension {
  final String key; // DB 字段名（如 'score_functionality'）
  final String label; // 显示名（如 '功能完整性'）
  final int max; // 满分（如 25）

  const ScoreDimension({
    required this.key,
    required this.label,
    required this.max,
  });
}

/// 通用录入/修改成绩弹窗。
///
/// **使用场景**：作品评分（5 维度）、考核打分（5 维度）、答辩（1 维度）、
/// 贡献分（1 维度）共用此组件，参数化维度列表。
///
/// **修改模式**（[currentScores] != null）会强制要求填 "修改原因"。
/// 录入模式则可填可不填。
///
/// **保存回调**：调用方负责实际写入 DAO + 写 audit log，本组件只是 UI。
/// 返回非空 ScoreEditResult 表示用户点了保存；null 表示取消。
class ScoreEditResult {
  final Map<String, int> scores; // {dimensionKey: score}
  final String comment; // 评语
  final String reason; // 修改原因（修改模式必填，录入模式可空）
  ScoreEditResult({
    required this.scores,
    required this.comment,
    required this.reason,
  });
}

class ScoreEditDialog extends StatefulWidget {
  final String title; // 弹窗标题（如 "录入项目成绩 — 张三"）
  final List<ScoreDimension> dimensions;
  final Map<String, int>? currentScores; // null = 录入模式；非空 = 修改模式
  final String? currentComment;

  const ScoreEditDialog({
    super.key,
    required this.title,
    required this.dimensions,
    this.currentScores,
    this.currentComment,
  });

  static Future<ScoreEditResult?> show(
    BuildContext context, {
    required String title,
    required List<ScoreDimension> dimensions,
    Map<String, int>? currentScores,
    String? currentComment,
  }) {
    return showDialog<ScoreEditResult>(
      context: context,
      builder: (_) => ScoreEditDialog(
        title: title,
        dimensions: dimensions,
        currentScores: currentScores,
        currentComment: currentComment,
      ),
    );
  }

  @override
  State<ScoreEditDialog> createState() => _ScoreEditDialogState();
}

class _ScoreEditDialogState extends State<ScoreEditDialog> {
  late final Map<String, TextEditingController> _scoreCtls;
  late final TextEditingController _commentCtl;
  late final TextEditingController _reasonCtl;
  String? _formError;

  bool get _isModify => widget.currentScores != null;

  @override
  void initState() {
    super.initState();
    _scoreCtls = {
      for (final d in widget.dimensions)
        d.key: TextEditingController(
          text: (widget.currentScores?[d.key] ?? 0).toString(),
        ),
    };
    _commentCtl = TextEditingController(text: widget.currentComment ?? '');
    _reasonCtl = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in _scoreCtls.values) {
      c.dispose();
    }
    _commentCtl.dispose();
    _reasonCtl.dispose();
    super.dispose();
  }

  void _save() {
    // 校验分数
    final scores = <String, int>{};
    for (final d in widget.dimensions) {
      final raw = _scoreCtls[d.key]!.text.trim();
      final v = int.tryParse(raw);
      if (v == null || v < 0 || v > d.max) {
        setState(() => _formError = '${d.label} 必须是 0~${d.max} 的整数');
        return;
      }
      scores[d.key] = v;
    }
    // 修改模式必填 reason
    final reason = _reasonCtl.text.trim();
    if (_isModify && reason.isEmpty) {
      setState(() => _formError = '修改成绩必须填写 "修改原因"');
      return;
    }
    Navigator.of(context).pop(ScoreEditResult(
      scores: scores,
      comment: _commentCtl.text.trim(),
      reason: reason,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _scoreCtls.entries.fold<int>(
      0,
      (sum, e) => sum + (int.tryParse(e.value.text) ?? 0),
    );
    final maxTotal = widget.dimensions.fold<int>(0, (s, d) => s + d.max);

    return AlertDialog(
      title: Row(
        children: [
          Icon(_isModify ? Icons.edit : Icons.fact_check,
              color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 18))),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 维度分数
              for (final d in widget.dimensions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(d.label,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _scoreCtls[d.key],
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixText: '/ ${d.max}',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              // 总分汇总
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('合计：',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('$total / $maxTotal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: total >= maxTotal * 0.6
                              ? Colors.green
                              : Colors.orange,
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 评语
              TextField(
                controller: _commentCtl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '评语 / 反馈（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // 修改原因（修改模式必填，录入模式可隐藏）
              if (_isModify)
                TextField(
                  controller: _reasonCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '修改原因 *',
                    helperText: '说明为什么改分（审计日志要求）',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (_formError != null) ...[
                const SizedBox(height: 8),
                Text(_formError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
            onPressed: _save,
            child: Text(_isModify ? '保存修改' : '录入')),
      ],
    );
  }
}
