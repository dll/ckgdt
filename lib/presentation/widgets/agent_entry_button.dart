import 'package:flutter/material.dart';
import 'agent_chat_overlay.dart';

/// 智能体快捷入口按钮 — 嵌入各功能页面的 AppBar
///
/// 用法：在 AppBar 的 actions 中添加：
/// ```dart
/// AppBar(
///   title: Text('页面标题'),
///   actions: [
///     AgentEntryButton(agentId: 'graph'),
///   ],
/// )
/// ```
class AgentEntryButton extends StatelessWidget {
  /// 对应的智能体 ID
  final String agentId;

  /// 按钮提示文字
  final String? tooltip;

  /// 自定义图标（默认 smart_toy）
  final IconData icon;

  /// 自定义颜色
  final Color? color;

  const AgentEntryButton({
    super.key,
    required this.agentId,
    this.tooltip,
    this.icon = Icons.smart_toy,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    return IconButton(
      icon: Icon(icon, size: 20),
      color: effectiveColor,
      tooltip: tooltip ?? 'AI 助手',
      onPressed: () => AgentChatOverlay.show(context, agentId: agentId),
    );
  }
}
