/// 构建发布中心 — admin 一键发布 4 端 + 双仓库 Release。
///
/// **运行场景**：仅装了完整工具链的 dev/admin 机器（Flutter SDK / Android SDK /
/// DevEco Studio / Git / gh CLI / Python+requests）。生产部署的普通学生/教师
/// 机器跑这页会失败。
///
/// **关键 UX**：
/// - 顶部 Hero 显示当前版本 + 目标版本（默认 patch +1，admin 可改）
/// - 中段 step 列表：10 步状态（pending/running/success/failed/skipped）
/// - 底部控制台：实时 stdout/stderr 流
/// - 凭证区：GitHub PAT + Gitee Token + 仓库 slug 配置入口
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/release_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/version_bump_service.dart';

class ReleaseCenterPage extends StatefulWidget {
  const ReleaseCenterPage({super.key});

  @override
  State<ReleaseCenterPage> createState() => _ReleaseCenterPageState();
}

class _ReleaseCenterPageState extends State<ReleaseCenterPage> {
  // ── 常量 ────────────────────────────────────────────────────────
  /// 控制台日志环形缓冲上限，超出截掉前面的。
  /// HAP 构建期 Hvigor 一秒能吐数百行，5000 行约 1MB，不会爆内存。
  static const int _kLogBufferMax = 5000;

  /// 日志合批刷 UI 的间隔（ms）。
  /// Hvigor / Gradle 高峰每秒 1000+ 行，逐行 setState 会卡 UI。
  /// 50ms ~ 20fps，肉眼几乎察觉不到延迟，但帧数稳定。
  static const Duration _kLogFlushInterval = Duration(milliseconds: 50);

  final ReleaseService _service = ReleaseService();
  final ScrollController _logScroll = ScrollController();
  final List<String> _logs = [];
  final List<String> _pendingLogs = [];
  Timer? _flushTimer;
  StreamSubscription<String>? _logSub;
  StreamSubscription<void>? _stepSub;

  String _currentVersion = '?';
  String _githubPat = '';
  String _giteeToken = '';
  String _githubRepo = '';
  String _giteeRepo = '';

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _logSub = _service.logStream.listen(_onLog);
    _stepSub = _service.stepStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// 收到一行日志：先入 pending 缓冲，[_kLogFlushInterval] 内合批一次 setState。
  void _onLog(String line) {
    _pendingLogs.add(line);
    _flushTimer ??= Timer(_kLogFlushInterval, _flushLogs);
  }

  void _flushLogs() {
    _flushTimer = null;
    if (_pendingLogs.isEmpty || !mounted) return;
    setState(() {
      _logs.addAll(_pendingLogs);
      _pendingLogs.clear();
      if (_logs.length > _kLogBufferMax) {
        _logs.removeRange(0, _logs.length - _kLogBufferMax);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _stepSub?.cancel();
    _flushTimer?.cancel();
    _logScroll.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final ver = await VersionBumpService.readCurrentVersion();
    final pat = await SettingsService.getReleaseGithubPat();
    final tok = await SettingsService.getReleaseGiteeToken();
    final ghRepo = await SettingsService.getReleaseGithubRepo();
    final geRepo = await SettingsService.getReleaseGiteeRepo();
    if (!mounted) return;
    setState(() {
      _currentVersion = ver;
      _githubPat = pat;
      _giteeToken = tok;
      _githubRepo = ghRepo;
      _giteeRepo = geRepo;
    });
  }

  Future<void> _runAll() async {
    setState(() => _logs.clear());
    final ok = await _service.runAll();
    if (!mounted) return;
    final color = ok ? Colors.green : Colors.red;
    final msg = ok
        ? '✓ 一键发布完成 (v${_service.targetVersion})'
        : '✗ 发布中断，请查看失败步骤的日志';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 5),
    ));
    if (ok) await _loadInitial();
  }

  Future<void> _retryFromStep(String stepId) async {
    final ok = await _service.runAll(fromStepId: stepId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '✓ 重试完成' : '✗ 重试失败'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  Future<void> _editTokens() async {
    final patCtl = TextEditingController(text: _githubPat);
    final tokCtl = TextEditingController(text: _giteeToken);
    final ghRepoCtl = TextEditingController(text: _githubRepo);
    final geRepoCtl = TextEditingController(text: _giteeRepo);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('凭证 / 仓库配置'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '凭证存于 SharedPreferences（与 Xunfei API key 同档次）。'
                  '仅用于 admin 一键发布到双仓库 Release。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: patCtl,
                  decoration: const InputDecoration(
                    labelText: 'GitHub PAT',
                    helperText:
                        'https://github.com/settings/tokens 生成（fine-grained 选 repo Contents R+W，或 classic 选 repo）',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokCtl,
                  decoration: const InputDecoration(
                    labelText: 'Gitee Token',
                    helperText: 'https://gitee.com/profile/personal_access_tokens',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ghRepoCtl,
                  decoration: const InputDecoration(
                    labelText: 'GitHub 仓库（owner/name）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: geRepoCtl,
                  decoration: const InputDecoration(
                    labelText: 'Gitee 仓库（owner/name）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (saved == true) {
      await SettingsService.setReleaseGithubPat(patCtl.text);
      await SettingsService.setReleaseGiteeToken(tokCtl.text);
      await SettingsService.setReleaseGithubRepo(ghRepoCtl.text);
      await SettingsService.setReleaseGiteeRepo(geRepoCtl.text);
      await _loadInitial();
    }
  }

  /// 把 [ReleaseStepStatus] 一次性映射成图标 + 颜色。
  /// 单一映射来源——之前两个并列 switch 容易漂移。
  ({IconData icon, Color color}) _statusStyle(ReleaseStepStatus s) {
    switch (s) {
      case ReleaseStepStatus.pending:
        return (icon: Icons.radio_button_unchecked, color: Colors.grey);
      case ReleaseStepStatus.running:
        return (icon: Icons.sync, color: Colors.blue);
      case ReleaseStepStatus.success:
        return (icon: Icons.check_circle, color: Colors.green);
      case ReleaseStepStatus.failed:
        return (icon: Icons.error, color: Colors.red);
      case ReleaseStepStatus.skipped:
        return (icon: Icons.skip_next, color: const Color(0xFFBDBDBD));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('构建发布中心'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '凭证 / 仓库配置',
            icon: const Icon(Icons.key),
            onPressed: _service.isRunning ? null : _editTokens,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, cons) {
        final wide = cons.maxWidth > 900;
        final stepsPanel = _buildStepsPanel(theme);
        final logPanel = _buildLogPanel(theme);

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 480, child: stepsPanel),
              const VerticalDivider(width: 1),
              Expanded(child: logPanel),
            ],
          );
        }
        return Column(children: [
          Expanded(flex: 5, child: stepsPanel),
          const Divider(height: 1),
          Expanded(flex: 4, child: logPanel),
        ]);
      }),
    );
  }

  Widget _buildStepsPanel(ThemeData theme) {
    final running = _service.isRunning;
    final tokensConfigured = _githubPat.isNotEmpty && _giteeToken.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Hero：当前版本 ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.rocket_launch,
                  size: 36, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('当前版本',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('v$_currentVersion',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      _service.targetVersion != null
                          ? '目标版本: v${_service.targetVersion} （bump 时确定）'
                          : '一键发布会自动 +patch（与已发布版本冲突时继续 +1）',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── 凭证状态 ──
        if (!tokensConfigured)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '凭证未配置（GitHub PAT / Gitee Token），无法创建 Release。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                    onPressed: _editTokens, child: const Text('去配置')),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GitHub: $_githubRepo  ·  Gitee: $_giteeRepo',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),

        // ── 一键发布 / 中止 ──
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: running ? null : _runAll,
                icon: const Icon(Icons.play_arrow),
                label: Text(running ? '正在发布…' : '一键发布全流程'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed:
                  running ? null : () => setState(() => _logs.clear()),
              icon: const Icon(Icons.clear_all),
              label: const Text('清日志'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Step 列表 ──
        const Text('发布步骤',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._service.steps.map(_buildStepRow),
      ],
    );
  }

  Widget _buildStepRow(ReleaseStep step) {
    final style = _statusStyle(step.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          step.status == ReleaseStepStatus.running
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Icon(style.icon, color: style.color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label,
                    style: TextStyle(
                        fontSize: 13,
                        color: step.status == ReleaseStepStatus.skipped
                            ? Colors.grey
                            : null,
                        fontWeight: step.status == ReleaseStepStatus.running
                            ? FontWeight.w600
                            : FontWeight.normal)),
                if (step.errorMessage != null)
                  Text(step.errorMessage!.split('\n').first,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.red)),
                if (step.duration != null)
                  Text('${step.duration!.inSeconds}s',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          if (step.status == ReleaseStepStatus.failed)
            TextButton(
              onPressed: _service.isRunning
                  ? null
                  : () => _retryFromStep(step.id),
              child: const Text('从此步重试'),
            ),
        ],
      ),
    );
  }

  Widget _buildLogPanel(ThemeData theme) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF252526),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text('控制台 (${_logs.length} lines)',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
                const Spacer(),
                IconButton(
                  tooltip: '复制全部',
                  icon: const Icon(Icons.copy, color: Colors.white70, size: 16),
                  onPressed: _logs.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(
                              ClipboardData(text: _logs.join('\n')));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('日志已复制')));
                        },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _logScroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _logs.length,
              itemBuilder: (ctx, i) {
                final line = _logs[i];
                Color c = Colors.white70;
                if (line.contains('[!]')) c = Colors.orangeAccent;
                if (line.contains('FAIL') || line.contains('✗')) c = Colors.redAccent;
                if (line.contains('✓')) c = Colors.greenAccent;
                return Text(
                  line,
                  style: TextStyle(
                    color: c,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
