import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import 'agent_chat_overlay.dart';
import '../pages/profile/virtual_twin_page.dart';
import '../pages/admin/teacher_application_page.dart';

/// CKGDT 助手悬浮菜单 — 展开式 FAB，集成智能体对话 + 数字孪生入口
///
/// 点击展开两个子按钮：
/// - 数字孪生仪表盘（虚拟教师/虚拟学生）
/// - AI 智能体对话
class MadMascotButton extends StatefulWidget {
  const MadMascotButton({super.key});

  @override
  State<MadMascotButton> createState() => _MadMascotButtonState();
}

class _MadMascotButtonState extends State<MadMascotButton>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late final AnimationController _animController;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  void _collapse() {
    if (_isExpanded) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final isTeacher = authService.isTeacher || authService.isAdmin;
    final agentId = isTeacher ? 'virtual_teacher' : 'virtual_student';
    const twinLabel = '美德';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── 子按钮：教师申请（仅学生可见） ──
        if (!isTeacher)
          _buildSubButton(
            heroTag: 'mad_apply',
            icon: Icons.how_to_reg,
            label: '申请教师',
            color: Colors.teal,
            onPressed: () {
              _collapse();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TeacherApplicationPage()),
              );
            },
          ),
        if (!isTeacher) const SizedBox(height: 8),
        // ── 子按钮：数字孪生 ──
        _buildSubButton(
          heroTag: 'mad_twin',
          icon: isTeacher ? Icons.school : Icons.face,
          label: twinLabel,
          color: isTeacher ? Colors.indigo : Colors.cyan,
          onPressed: () {
            _collapse();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VirtualTwinPage()),
            );
          },
        ),
        const SizedBox(height: 8),
        // ── 子按钮：AI 对话 ──
        _buildSubButton(
          heroTag: 'mad_chat',
          icon: Icons.chat_bubble_outline,
          label: 'AI 对话',
          color: Colors.deepPurple,
          onPressed: () {
            _collapse();
            AgentChatOverlay.show(context, agentId: agentId);
          },
        ),
        const SizedBox(height: 10),
        // ── 主按钮 ──
        FloatingActionButton(
          mini: true,
          heroTag: 'mad_mascot',
          backgroundColor: Theme.of(context).colorScheme.primary,
          tooltip: 'CKGDT 助手',
          onPressed: _toggle,
          child: AnimatedBuilder(
            animation: _animController,
            builder: (_, __) => Transform.rotate(
              angle: _expandAnimation.value * 0.5,
              child: Text(
                _isExpanded ? '✕' : 'CK',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubButton({
    required String heroTag,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizeTransition(
      sizeFactor: _expandAnimation,
      axisAlignment: -1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              mini: true,
              heroTag: heroTag,
              backgroundColor: color.withValues(alpha: 0.9),
              onPressed: onPressed,
              child: Icon(icon, size: 20, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
