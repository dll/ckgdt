import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/init_logger.dart';
import '../../services/navigation_service.dart';
import '../../services/voice_service.dart';
import '../pages/settings/voice_settings_page.dart';

/// 通用语音输入按钮
///
/// 放在 TextField 旁边，点击后弹出录音弹窗，将识别文本填入指定 controller。
/// 也可单独使用，通过 [onTextRecognized] 获取识别结果。
class VoiceInputButton extends StatefulWidget {
  /// 要填充识别结果的文本控制器（可选）
  final TextEditingController? controller;

  /// 识别到文字时的回调（可选）
  final void Function(String text)? onTextRecognized;

  /// 按钮大小
  final double size;

  /// 提示文字
  final String tooltip;

  /// 图标颜色（null 时使用 primary）
  final Color? iconColor;

  const VoiceInputButton({
    super.key,
    this.controller,
    this.onTextRecognized,
    this.size = 40,
    this.tooltip = '语音输入',
    this.iconColor,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  @override
  Widget build(BuildContext context) {
    final color = widget.iconColor ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: IconButton(
        tooltip: widget.tooltip,
        icon: Icon(Icons.mic, color: color, size: widget.size * 0.55),
        onPressed: () => _showVoiceDialog(context),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Future<void> _showVoiceDialog(BuildContext context) async {
    // Web 平台不支持语音录制
    if (kIsWeb) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web 平台暂不支持语音输入，请使用桌面端或移动端'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 检查配置
    final configured = await VoiceService.isConfigured();
    if (!configured) {
      if (!context.mounted) return;
      final goSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.mic_off, color: Colors.orange),
              SizedBox(width: 8),
              Text('未配置语音服务', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: const Text('请先在系统设置中配置讯飞语音参数（AppID/APIKey/APISecret）'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
      if (goSettings == true && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VoiceSettingsPage()),
        );
      }
      return;
    }

    if (!context.mounted) return;

    // 弹出录音对话框
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _VoiceRecordDialog(),
    );

    if (result != null && result.isNotEmpty) {
      // 关键：语音识别完成后、使用结果导航之前，必须等待 native 录音器完全释放。
      // dispose() 不能 await，调用方在这里显式等待 native AudioRecorder 停止+释放。
      // 否则 native 销毁与页面并发 => record_windows 原生崩溃。
      await VoiceService().forceStop();
      widget.controller?.text = result;
      widget.onTextRecognized?.call(result);
    }
  }
}

/// 语音导航对话框（公开版，供 HomePage / 登录页 / 全局 FAB 调用）。
///
/// **两种模式**（构造时选定，dialog 期间不变）：
///
/// 1. **持续模式（默认）**——"小度"式：每识别完一句调 [onSentence]
///    （通常做导航），dialog **不关闭**，自动重启监听等下一句。
///    用户点"完成"才关。适合多次连续语音操作。
///
/// 2. **单句模式**（[continuousMode]=false）——识别完一句立即
///    `Navigator.pop(text)` 返回。适合登录场景（说一次学号即结束）。
///
/// 之前 dialog 内部统一调 `Navigator.maybePop`，曾在双重 status==2 等
/// 边缘场景把根页面也 pop 掉，触发"语音导航后自动退出系统"。
/// 持续模式从架构上禁止这条路径——dialog 自闭环管理生命周期。
class VoiceNavigationDialog extends StatefulWidget {
  /// 持续模式（默认）vs 单句模式
  final bool continuousMode;

  /// 持续模式下，每识别完一句的回调（可选）。
  /// 调用方在此触发导航/操作，本 dialog 不关。
  /// 回调时 dialog 仍 mounted，可放心调 SnackBar / NavigationService。
  final void Function(String sentence)? onSentence;

  const VoiceNavigationDialog({
    super.key,
    this.continuousMode = true,
    this.onSentence,
  });

  @override
  State<VoiceNavigationDialog> createState() => _VoiceNavigationDialogState();
}

class _VoiceNavigationDialogState extends State<VoiceNavigationDialog>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  String _recognizedText = '';
  final List<String> _history = []; // 持续模式下已识别的历史句
  bool _isListening = false;
  bool _restarting = false;
  String? _errorMsg;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _voiceService.onResult = (text) {
      if (mounted) setState(() => _recognizedText = text);
    };
    _voiceService.onComplete = (text) {
      unawaited(_handleComplete(text));
    };
    _voiceService.onError = (error) {
      if (mounted) {
        setState(() {
          _errorMsg = error;
          _isListening = false;
        });
        _pulseController.stop();
      }
    };
    _voiceService.onStateChanged = (listening) {
      if (mounted) setState(() => _isListening = listening);
    };

    _startListening();
  }

  @override
  void dispose() {
    InitLogger.logFlush('voice', 'VoiceNavigationDialogState.dispose');
    _voiceService.onResult = null;
    _voiceService.onComplete = null;
    _voiceService.onError = null;
    _voiceService.onStateChanged = null;
    _pulseController.dispose();
    unawaited(_voiceService.forceStop());
    super.dispose();
  }

  Future<void> _handleComplete(String text) async {
    if (!mounted) return;
    final sentence = text.trim();
    _pulseController.stop();

    if (sentence.isEmpty) {
      await _voiceService.forceStop();
      if (!mounted) return;
      setState(() {
        _errorMsg = widget.continuousMode ? '未检测到语音，正在重新聆听…' : '未检测到语音，请点击重试';
        _isListening = false;
      });
      if (widget.continuousMode) {
        await _restartListening();
      }
      return;
    }

    if (widget.continuousMode) {
      setState(() {
        _history.add(sentence);
        _recognizedText = '';
        _isListening = false;
        _errorMsg = null;
      });
      await _voiceService.forceStop();
      if (!mounted) return;
      widget.onSentence?.call(sentence);
      await _restartListening();
      return;
    }

    await _voiceService.forceStop();
    if (!mounted) return;
    Navigator.pop(context, sentence);
  }

  Future<void> _startListening() async {
    setState(() {
      _errorMsg = null;
      _recognizedText = '';
    });
    final ok = await _voiceService.startListening();
    if (!mounted) return;
    if (ok) _pulseController.repeat(reverse: true);
  }

  Future<void> _stopListening() async {
    await _voiceService.stopListening();
    _pulseController.stop();
  }

  /// 持续模式下，一句识别完后自动启动下一轮。
  /// 等待 forceStop 完成后再启动下一轮，避免 record_windows 资源并发。
  Future<void> _restartListening() async {
    if (_restarting) return;
    _restarting = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted || !widget.continuousMode) return;
      await _startListening();
    } finally {
      _restarting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final continuous = widget.continuousMode;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over, color: primary),
                const SizedBox(width: 8),
                Text(continuous ? '语音助手' : '语音输入',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              continuous ? '说一句执行一次操作。' : '说一句话即可，识别完成自动关闭。',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _isListening ? _stopListening : _startListening,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale =
                      _isListening ? 1.0 + _pulseController.value * 0.15 : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? Colors.red : primary,
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.3),
                                  blurRadius: 20 * _pulseController.value,
                                  spreadRadius: 5 * _pulseController.value,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isListening ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isListening ? '正在聆听...' : '点击开始',
              style: TextStyle(
                  fontSize: 12, color: _isListening ? Colors.red : Colors.grey),
            ),
            const SizedBox(height: 12),
            // 当前识别中的部分文本
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _recognizedText.isNotEmpty
                      ? primary.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.2),
                ),
              ),
              child: _recognizedText.isNotEmpty
                  ? Text(_recognizedText,
                      style: const TextStyle(fontSize: 16, height: 1.4))
                  : Text(
                      _errorMsg ?? '识别结果将在这里显示',
                      style: TextStyle(
                        fontSize: 13,
                        color: _errorMsg != null ? Colors.red : Colors.grey,
                      ),
                    ),
            ),
            // 持续模式：历史已识别 + 已执行的句
            if (continuous && _history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in _history)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: primary.withOpacity(0.7), size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(s,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        if (continuous)
          // 持续模式：唯一关闭路径 = 用户主动点完成
          FilledButton.icon(
            onPressed: () async {
              await _voiceService.forceStop();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('完成'),
          )
        else ...[
          TextButton(
            onPressed: () async {
              await _voiceService.forceStop();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _recognizedText.isNotEmpty
                ? () async {
                    await _voiceService.forceStop();
                    if (context.mounted) {
                      Navigator.pop(context, _recognizedText);
                    }
                  }
                : null,
            child: const Text('确认'),
          ),
        ],
      ],
    );
  }
}

/// 语音录制对话框
class _VoiceRecordDialog extends StatefulWidget {
  const _VoiceRecordDialog();

  @override
  State<_VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends State<_VoiceRecordDialog>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  String _recognizedText = '';
  bool _isListening = false;
  String? _errorMsg;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _voiceService.onResult = (text) {
      if (mounted) setState(() => _recognizedText = text);
    };
    _voiceService.onComplete = (text) {
      unawaited(_handleComplete(text));
    };
    _voiceService.onError = (error) {
      if (mounted) {
        setState(() {
          _errorMsg = error;
          _isListening = false;
        });
        _pulseController.stop();
      }
    };
    _voiceService.onStateChanged = (listening) {
      if (mounted) setState(() => _isListening = listening);
    };

    // 自动开始录音
    _startListening();
  }

  @override
  void dispose() {
    InitLogger.logFlush('voice', 'VoiceRecordDialogState.dispose');
    _voiceService.onResult = null;
    _voiceService.onComplete = null;
    _voiceService.onError = null;
    _voiceService.onStateChanged = null;
    _pulseController.dispose();
    unawaited(_voiceService.forceStop());
    super.dispose();
  }

  Future<void> _handleComplete(String text) async {
    _pulseController.stop();
    final finalText = text.trim();
    await _voiceService.forceStop();
    if (!mounted) return;
    setState(() {
      _recognizedText = finalText;
      _isListening = false;
    });
  }

  Future<void> _startListening() async {
    setState(() {
      _errorMsg = null;
      _recognizedText = '';
    });
    final ok = await _voiceService.startListening();
    if (!mounted) return;
    if (ok) {
      _pulseController.repeat(reverse: true);
    }
  }

  Future<void> _stopListening() async {
    await _voiceService.stopListening();
    _pulseController.stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 标题 ───────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.mic, color: primary),
                const SizedBox(width: 8),
                const Text('语音输入',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),

            // ── 录音动画按钮 ───────────────────────────────────────
            GestureDetector(
              onTap: _isListening ? _stopListening : _startListening,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale =
                      _isListening ? 1.0 + _pulseController.value * 0.15 : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? Colors.red : primary,
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.3),
                                  blurRadius: 20 * _pulseController.value,
                                  spreadRadius: 5 * _pulseController.value,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isListening ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isListening ? '正在聆听，请说话...' : '点击开始录音',
              style: TextStyle(
                fontSize: 13,
                color: _isListening ? Colors.red : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),

            // ── 识别结果 ───────────────────────────────────────────
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _recognizedText.isNotEmpty
                      ? primary.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.2),
                ),
              ),
              child: _recognizedText.isNotEmpty
                  ? Text(
                      _recognizedText,
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    )
                  : Text(
                      _errorMsg ?? '识别结果将在这里显示',
                      style: TextStyle(
                        fontSize: 13,
                        color: _errorMsg != null ? Colors.red : Colors.grey,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await _voiceService.forceStop();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _recognizedText.isNotEmpty
              ? () async {
                  await _voiceService.forceStop();
                  if (context.mounted) Navigator.pop(context, _recognizedText);
                }
              : null,
          child: const Text('确认'),
        ),
      ],
    );
  }
}

/// 语音导航浮动按钮 — 全局语音指令（说出功能名跳转页面）
class VoiceNavigationFab extends StatelessWidget {
  final VoidCallback? onNavigationResult;

  const VoiceNavigationFab({super.key, this.onNavigationResult});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'voice_nav_fab',
      mini: true,
      tooltip: '语音导航',
      backgroundColor: Colors.deepPurple,
      onPressed: () => _handleVoiceNavigation(context),
      child: const Icon(Icons.mic, color: Colors.white, size: 22),
    );
  }

  Future<void> _handleVoiceNavigation(BuildContext context) async {
    // Web 平台不支持语音录制
    if (kIsWeb) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web 平台暂不支持语音导航'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final configured = await VoiceService.isConfigured();
    if (!configured) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在系统设置中配置讯飞语音'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!context.mounted) return;
    // 持续模式：识别一句即跳转，dialog 不关，用户点"完成"才结束。
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VoiceNavigationDialog(
        continuousMode: true,
        onSentence: (sentence) {
          if (ctx.mounted) {
            _navigateByVoice(ctx, sentence);
          }
        },
      ),
    );
  }

  /// 根据语音内容进行页面导航
  void _navigateByVoice(BuildContext context, String text) {
    final normalized = text.replaceAll(RegExp(r'[，。！？、\s]'), '').toLowerCase();

    // 导航映射表
    final routes = <String, String>{
      '图谱': 'graph',
      '知识图谱': 'graph',
      '测验': 'quiz',
      '考试': 'quiz',
      '答题': 'quiz',
      '学习': 'learning',
      '教学': 'learning',
      '课堂': 'classroom',
      '实验': 'lab',
      '考核': 'assessment',
      '作品': 'works',
      '成就': 'achievement',
      '达成': 'achievement',
      '设置': 'settings',
      '管理': 'admin',
      '搜索': 'search',
      '同步': 'sync',
      '三端': 'crossplatform',
      '四端': 'crossplatform',
      '多端': 'crossplatform',
      '互通': 'crossplatform',
      '通知': 'notification',
      '进度': 'progress',
      '收藏': 'favorites',
      '错题': 'wrong_answers',
      '仓库': 'repo',
      '导航': 'navigate',
    };

    String? matchedRoute;
    for (final entry in routes.entries) {
      if (normalized.contains(entry.key)) {
        matchedRoute = entry.value;
        break;
      }
    }

    if (matchedRoute != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('语音导航: $text → $matchedRoute'),
          duration: const Duration(seconds: 1),
        ),
      );
      onNavigationResult?.call();
      _doNavigate(context, matchedRoute);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('未识别到导航指令: "$text"'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _doNavigate(BuildContext context, String route) {
    // 持续模式下 dialog 必须保持打开，不能再用 maybePop 传递路由。
    // 直接通过 NavigationService 切 Tab — `route` 是已经匹配过的关键词。
    NavigationService.instance.navigateByKeyword(route);
  }
}
