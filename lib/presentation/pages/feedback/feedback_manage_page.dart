import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../data/local/feedback_dao.dart';

/// 管理员 — 问题反馈管理页面
class FeedbackManagePage extends StatefulWidget {
  const FeedbackManagePage({super.key});

  @override
  State<FeedbackManagePage> createState() => _FeedbackManagePageState();
}

class _FeedbackManagePageState extends State<FeedbackManagePage> {
  final _feedbackDao = FeedbackDao();
  List<Map<String, dynamic>> _feedbackList = [];
  Map<String, int> _stats = {'total': 0, 'pending': 0, 'resolved': 0};
  bool _isLoading = true;
  String _filter = 'all'; // all, pending, resolved

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _feedbackDao.getStats();
      final list = await _feedbackDao.getAllFeedback(
        status: _filter == 'all' ? null : _filter,
      );
      if (mounted) {
        setState(() {
          _stats = stats;
          _feedbackList = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('问题反馈管理'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          if (_feedbackList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空已处理',
              onPressed: _clearResolved,
            ),
        ],
      ),
      body: Column(
        children: [
          // 统计卡片
          _buildStatsBar(primary),

          // 筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'all',
                    label: Text('全部 (${_stats['total']})')),
                ButtonSegment(
                    value: 'pending',
                    label: Text('待处理 (${_stats['pending']})')),
                ButtonSegment(
                    value: 'resolved',
                    label: Text('已处理 (${_stats['resolved']})')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) {
                setState(() => _filter = s.first);
                _loadData();
              },
            ),
          ),

          // 列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _feedbackList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('暂无反馈',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _feedbackList.length,
                          itemBuilder: (context, index) {
                            return _buildFeedbackCard(
                                _feedbackList[index], primary);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(Color primary) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem('总反馈', _stats['total'] ?? 0, Icons.feedback),
          Container(width: 1, height: 30, color: Colors.white30),
          _statItem('待处理', _stats['pending'] ?? 0, Icons.pending_actions),
          Container(width: 1, height: 30, color: Colors.white30),
          _statItem('已处理', _stats['resolved'] ?? 0, Icons.check_circle),
        ],
      ),
    );
  }

  Widget _statItem(String label, int value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> fb, Color primary) {
    final isPending = fb['status'] == 'pending';
    final createdAt = fb['created_at'] as String? ?? '';
    final timeStr = createdAt.length >= 16 ? createdAt.substring(0, 16) : createdAt;
    final screenshots = (fb['screenshot_path'] as String?)?.split('|') ?? [];
    final roleStr = fb['user_role'] == 'admin'
        ? '管理员'
        : fb['user_role'] == 'teacher'
            ? '教师'
            : '学生';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isPending ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPending
            ? BorderSide(color: Colors.orange.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：用户 + 状态
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: primary.withValues(alpha: 0.1),
                  child: Text(
                    (fb['user_name'] as String? ?? 'U').substring(0, 1),
                    style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fb['user_name'] as String? ?? fb['user_id'] as String? ?? '未知',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '$roleStr  |  $timeStr',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                // 状态标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isPending ? '待处理' : '已处理',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPending ? Colors.orange : Colors.green,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 问题内容
            Text(
              fb['content'] as String? ?? '',
              style: const TextStyle(fontSize: 14),
            ),

            // 改进建议
            if (fb['suggestion'] != null &&
                (fb['suggestion'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 16, color: Colors.blue[400]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        fb['suggestion'] as String,
                        style: TextStyle(
                            fontSize: 13, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 截图预览
            if (screenshots.isNotEmpty &&
                screenshots.first.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: screenshots.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final path = screenshots[i];
                    return GestureDetector(
                      onTap: () => _showFullScreenImage(path),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(path),
                          width: 100,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 100,
                            height: 80,
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image, size: 24),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // 管理员回复
            if (fb['admin_reply'] != null &&
                (fb['admin_reply'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.reply,
                        size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '回复: ${fb['admin_reply']}',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isPending && !kIsWeb)
                  TextButton.icon(
                    onPressed: () => _handleAiFix(fb),
                    icon: Icon(Icons.auto_fix_high,
                        size: 16, color: Colors.purple[400]),
                    label: Text('AI修复',
                        style: TextStyle(fontSize: 12, color: Colors.purple[400])),
                  ),
                if (isPending)
                  TextButton.icon(
                    onPressed: () => _showReplyDialog(fb),
                    icon: const Icon(Icons.reply, size: 16),
                    label: const Text('回复处理', style: TextStyle(fontSize: 12)),
                  ),
                TextButton.icon(
                  onPressed: () => _deleteFeedback(fb),
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: Colors.red[300]),
                  label: Text('删除',
                      style: TextStyle(fontSize: 12, color: Colors.red[300])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// AI 自动修复 — 调用 Claude Code CLI 读取问题、修改代码、构建应用
  Future<void> _handleAiFix(Map<String, dynamic> fb) async {
    final content = fb['content'] as String? ?? '';
    final suggestion = fb['suggestion'] as String? ?? '';
    if (content.isEmpty) return;

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high, color: Colors.purple, size: 22),
            SizedBox(width: 8),
            Text('AI 自动修复'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('将调用 Claude Code 自动分析并修复此问题：',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(content,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 12),
            Text('修复完成后将自动重新构建应用。',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('开始修复'),
            style: FilledButton.styleFrom(backgroundColor: Colors.purple),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 构造修复 prompt
    final prompt = StringBuffer();
    prompt.writeln('用户反馈了以下问题，请阅读代码修复它：');
    prompt.writeln('');
    prompt.writeln('【问题描述】$content');
    if (suggestion.isNotEmpty) {
      prompt.writeln('【改进建议】$suggestion');
    }
    prompt.writeln('');
    prompt.writeln('请：1) 分析问题根因  2) 修改相关代码  3) 执行 flutter build windows --release 重新构建应用');

    // 显示进度对话框
    await _showAiFixProgress(fb, prompt.toString());
  }

  /// 显示 AI 修复进度对话框并执行
  Future<void> _showAiFixProgress(Map<String, dynamic> fb, String prompt) async {
    final outputLines = <String>[];
    var isRunning = true;
    Process? process;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 首次启动时执行 claude 命令
            if (process == null) {
              _runClaudeFixProcess(
                prompt: prompt,
                onOutput: (line) {
                  if (context.mounted) {
                    setDialogState(() => outputLines.add(line));
                  }
                },
                onDone: (exitCode) {
                  if (context.mounted) {
                    setDialogState(() {
                      isRunning = false;
                      outputLines.add(exitCode == 0
                          ? '\n===  AI 修复完成 ==='
                          : '\n===  AI 修复异常退出 (code=$exitCode) ===');
                    });
                  }
                  // 标记反馈为已处理
                  _feedbackDao.updateStatus(
                    fb['id'] as int,
                    'resolved',
                    reply: '[AI 自动修复] ${exitCode == 0 ? "已完成修复并重新构建" : "修复过程异常退出"}',
                  );
                  _loadData();
                },
              ).then((p) => process = p);
            }

            return AlertDialog(
              title: Row(
                children: [
                  if (isRunning)
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 10),
                  Text(isRunning ? 'AI 正在修复...' : '修复完成',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 500,
                height: 350,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    reverse: true,
                    itemCount: outputLines.length,
                    itemBuilder: (_, i) {
                      final line = outputLines[outputLines.length - 1 - i];
                      final isErr = line.startsWith('===') || line.contains('error') || line.contains('Error');
                      return Text(
                        line,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isErr ? Colors.redAccent : Colors.greenAccent,
                        ),
                      );
                    },
                  ),
                ),
              ),
              actions: [
                if (!isRunning)
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'),
                  ),
                if (isRunning)
                  TextButton(
                    onPressed: () {
                      process?.kill();
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('取消', style: TextStyle(color: Colors.red)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// 启动 Claude CLI 进程
  Future<Process> _runClaudeFixProcess({
    required String prompt,
    required void Function(String line) onOutput,
    required void Function(int exitCode) onDone,
  }) async {
    // 获取项目根目录（向上查找 pubspec.yaml）
    var projectDir = Directory.current.path;
    // 在 release 模式下 cwd 可能不是项目目录，硬编码已知路径作为兜底
    if (!File('$projectDir/pubspec.yaml').existsSync()) {
      projectDir = r'D:\FlutterProjects\knowledge_graph_app';
    }

    onOutput('[工作目录] $projectDir');
    onOutput('[启动 Claude Code ...]');
    onOutput('');

    final process = await Process.start(
      'claude',
      ['-p', '--output-format', 'text', prompt],
      workingDirectory: projectDir,
      runInShell: true,
    );

    // 读取 stdout
    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen(
          (chunk) {
            for (final line in chunk.split('\n')) {
              if (line.trim().isNotEmpty) onOutput(line);
            }
          },
          onDone: () {},
        );

    // 读取 stderr
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen(
          (chunk) {
            for (final line in chunk.split('\n')) {
              if (line.trim().isNotEmpty) onOutput('[stderr] $line');
            }
          },
        );

    // 等待完成
    process.exitCode.then(onDone);

    return process;
  }

  /// 回复并标记为已处理
  Future<void> _showReplyDialog(Map<String, dynamic> fb) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回复反馈'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '输入回复内容（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('标记已处理')),
        ],
      ),
    );

    if (result == true) {
      await _feedbackDao.updateStatus(
        fb['id'] as int,
        'resolved',
        reply: controller.text.trim().isNotEmpty ? controller.text.trim() : null,
      );
      _loadData();
    }
    controller.dispose();
  }

  /// 删除反馈
  Future<void> _deleteFeedback(Map<String, dynamic> fb) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除反馈'),
        content: const Text('确定要删除这条反馈吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      await _feedbackDao.deleteFeedback(fb['id'] as int);
      _loadData();
    }
  }

  /// 清空已处理的反馈
  Future<void> _clearResolved() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空已处理'),
        content: const Text('确定要删除所有"已处理"的反馈吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      final list = await _feedbackDao.getAllFeedback(status: 'resolved');
      for (final fb in list) {
        await _feedbackDao.deleteFeedback(fb['id'] as int);
      }
      _loadData();
    }
  }

  /// 全屏查看图片
  void _showFullScreenImage(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('截图'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(path),
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image,
                      size: 64, color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
