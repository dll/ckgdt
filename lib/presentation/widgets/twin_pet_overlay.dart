import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/constants/app_theme.dart';
import '../../services/auth_service.dart';
import 'agent_chat_overlay.dart';

/// 🐾 数字孪生悬浮宠物 — 登录后常驻的"虚拟人身"。
///
/// 纯 Flutter 绘制（无外部图片/Lottie/Rive 资源）：
/// - 角色 emoji（教师 🧑‍🏫 / 学生 🧑‍🎓）置于渐变圆形头身中
/// - 持续"呼吸"缩放 + 轻微上下浮动，像宠物一样有生命感
/// - 可拖拽并贴边吸附（手感与 main.dart 的 _FloatingHelpFab 一致）
/// - 点击 → 打开数字孪生对话（AgentChatOverlay，agentId='digital_twin'）
/// - 挂载时淡入"现身"，由外层 ValueListenableBuilder 在退出登录时移除（淡出隐身）
///
/// 由 main.dart 的 MaterialApp.builder Stack 在登录态为 true 时挂载。
class TwinPetOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const TwinPetOverlay({super.key, required this.navigatorKey});

  @override
  State<TwinPetOverlay> createState() => _TwinPetOverlayState();
}

class _TwinPetOverlayState extends State<TwinPetOverlay>
    with TickerProviderStateMixin {
  static const double _petSize = 52;

  // 位置（默认左下角，避开右侧的 _FloatingHelpFab）
  double _dx = -1;
  double _dy = -1;
  bool _dragging = false;

  // 呼吸 + 浮动动画
  late final AnimationController _breathController;
  // 现身淡入
  late final AnimationController _appearController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      duration: const Duration(milliseconds: 2600),
      vsync: this,
    )..repeat(reverse: true);
    _appearController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _breathController.dispose();
    _appearController.dispose();
    super.dispose();
  }

  bool get _isTeacher {
    final auth = AuthService();
    return auth.isTeacher || auth.isAdmin;
  }

  String get _avatarEmoji => _isTeacher ? '🧑‍🏫' : '🧑‍🎓';

  void _openTwinChat() {
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) {
      AgentChatOverlay.show(navContext, agentId: 'digital_twin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // 初始位置：左下角（避开右下角的帮助悬浮球）
    if (_dx < 0) _dx = 8;
    if (_dy < 0) _dy = size.height - 220;

    // 不超出屏幕
    _dx = _dx.clamp(0.0, size.width - _petSize);
    _dy = _dy.clamp(40.0, size.height - _petSize - 16);

    final gradient = AppGradientTheme.of(context).linearGradient;

    return Positioned(
      left: _dx,
      top: _dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (details) {
          setState(() {
            _dx += details.delta.dx;
            _dy += details.delta.dy;
          });
        },
        onPanEnd: (_) {
          setState(() {
            _dragging = false;
            // 吸附到最近边缘
            if (_dx + _petSize / 2 < size.width / 2) {
              _dx = 8;
            } else {
              _dx = size.width - _petSize - 8;
            }
          });
        },
        onTap: _openTwinChat,
        child: FadeTransition(
          opacity: _appearController,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(
                  parent: _appearController, curve: Curves.elasticOut),
            ),
            child: AnimatedBuilder(
              animation: _breathController,
              builder: (context, child) {
                // 呼吸：缩放 0.94~1.06；浮动：上下 ±4px
                final t = _breathController.value; // 0..1
                final breathe = 0.94 + 0.12 * t;
                final floatY = -4.0 * math.sin(t * math.pi);
                return Transform.translate(
                  offset: Offset(0, floatY),
                  child: Transform.scale(scale: breathe, child: child),
                );
              },
              child: _buildPet(gradient),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPet(LinearGradient gradient) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _dragging ? 1.0 : 0.92,
      child: Container(
        width: _petSize,
        height: _petSize,
        decoration: BoxDecoration(
          gradient: gradient,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.45),
              blurRadius: 12,
              spreadRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            _avatarEmoji,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}
