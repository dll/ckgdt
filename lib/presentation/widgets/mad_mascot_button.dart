import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import 'agent_chat_overlay.dart';

/// MAD 卡通精灵悬浮按钮 — 集成在各功能页面
///
/// 根据用户角色自动选择对应的数字孪生智能体：
/// - 教师/管理员 → 虚拟教师 (virtual_teacher)
/// - 学生 → 虚拟学生 (virtual_student)
///
/// 用法：在 Scaffold 的 floatingActionButton 中使用：
/// ```dart
/// Scaffold(
///   floatingActionButton: const MadMascotButton(),
///   body: ...,
/// )
/// ```
/// 或在任意位置使用 MadMascotButton.overlay() 作为 Stack 中的定位组件。
class MadMascotButton extends StatelessWidget {
  /// 可选的自定义提示文字
  final String? tooltip;

  /// 是否使用迷你尺寸
  final bool mini;

  const MadMascotButton({
    super.key,
    this.tooltip,
    this.mini = true,
  });

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final isTeacher = authService.isTeacher || authService.isAdmin;
    final agentId = isTeacher ? 'virtual_teacher' : 'virtual_student';
    final label = isTeacher ? '虚拟教师' : '虚拟学生';

    return FloatingActionButton(
      mini: mini,
      heroTag: 'mad_mascot',
      backgroundColor: isTeacher
          ? Colors.indigo.withValues(alpha: 0.9)
          : Colors.cyan.withValues(alpha: 0.9),
      tooltip: tooltip ?? 'MAD $label',
      onPressed: () => AgentChatOverlay.show(context, agentId: agentId),
      child: const Text(
        'M',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
