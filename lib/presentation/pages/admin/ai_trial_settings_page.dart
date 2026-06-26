import 'package:flutter/material.dart';
import '../../../data/local/ai_trial_dao.dart';

class AiTrialSettingsPage extends StatefulWidget {
  const AiTrialSettingsPage({super.key});

  @override
  State<AiTrialSettingsPage> createState() => _AiTrialSettingsPageState();
}

class _AiTrialSettingsPageState extends State<AiTrialSettingsPage> {
  final _dao = AiTrialDao();
  bool _loading = true;
  bool _trialEnabled = true;
  double _trialMaxCalls = 10;
  double _trialMaxTokens = 50000;
  int _currentCalls = 0;
  int _currentTokens = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _dao.getSettings();
    if (settings != null) {
      _trialEnabled = settings['trial_enabled'] == 1;
      _trialMaxCalls = ((settings['trial_max_calls'] as int?) ?? 10).toDouble();
      _trialMaxTokens = ((settings['trial_max_tokens'] as int?) ?? 50000).toDouble();
    }
    _currentCalls = await _dao.getCurrentCalls();
    _currentTokens = await _dao.getCurrentTokens();
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    await _dao.updateSettings(
      trialEnabled: _trialEnabled,
      trialMaxCalls: _trialMaxCalls.round(),
      trialMaxTokens: _trialMaxTokens.round(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI 试用额度设置已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 试用额度管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildUsageCard(theme),
                const SizedBox(height: 24),
                _buildTrialSwitch(theme),
                const SizedBox(height: 24),
                _buildSliderSection(
                  theme: theme,
                  title: '每日最大调用次数',
                  value: _trialMaxCalls,
                  min: 1,
                  max: 200,
                  onChanged: (v) => setState(() => _trialMaxCalls = v.round().toDouble()),
                ),
                const SizedBox(height: 16),
                _buildSliderSection(
                  theme: theme,
                  title: '每日最大 Token 用量',
                  value: _trialMaxTokens,
                  min: 1000,
                  max: 500000,
                  step: 1000,
                  format: (v) => '${v ~/ 1000}K',
                  onChanged: (v) =>
                      setState(() => _trialMaxTokens = v.round().toDouble()),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('保存设置'),
                ),
              ],
            ),
    );
  }

  Widget _buildUsageCard(ThemeData theme) {
    final remainingCalls = _trialMaxCalls - _currentCalls;
    final remainingTokens = _trialMaxTokens - _currentTokens;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日使用统计', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildStatRow('已用调用次数', '$_currentCalls / $_trialMaxCalls',
                remainingCalls <= 0 ? Colors.red : Colors.green),
            const SizedBox(height: 8),
            _buildStatRow('已用 Token 用量', '$_currentTokens / $_trialMaxTokens',
                remainingTokens <= 0 ? Colors.red : Colors.green),
            const SizedBox(height: 8),
            _buildStatRow('剩余调用次数', '$remainingCalls',
                remainingCalls <= 0 ? Colors.red : Colors.green),
            const SizedBox(height: 8),
            _buildStatRow('剩余 Token 额度', '$remainingTokens',
                remainingTokens <= 0 ? Colors.red : Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildTrialSwitch(ThemeData theme) {
    return Card(
      child: SwitchListTile(
        title: const Text('启用免费试用额度'),
        subtitle: Text(
          _trialEnabled
              ? '用户可在未配置 API Key 时使用有限次数'
              : '关闭后未配置 API Key 的用户将无法使用 AI 功能',
        ),
        value: _trialEnabled,
        onChanged: (v) => setState(() => _trialEnabled = v),
      ),
    );
  }

  Widget _buildSliderSection({
    required ThemeData theme,
    required String title,
    required double value,
    required double min,
    required double max,
    double step = 1,
    String Function(double)? format,
    required ValueChanged<double> onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: ((max - min) / step).round().clamp(1, 1000),
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  child: Text(
                    format != null ? format(value) : '${value.round()}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
