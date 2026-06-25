import 'package:flutter/material.dart';
import '../../core/design/noir_tokens.dart';
import '../../core/design/noir_components.dart';
import '../pages/login/knowledge_graph_backdrop.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 登录页式背景层 —— 径向渐变 + 静态知识图谱节点 + 暗角
//
// 节点画师复用 [KnowledgeGraphBackdrop]，传 `breath: null` 即静态模式
// （之前一份 _StaticGraphPainter 内部副本已删除，避免与 backdrop 重复）。
// ─────────────────────────────────────────────────────────────────────────────

/// 顶层 final 暗角装饰：[NoirTokens.inkDeep] 的 alpha 0.55 副本只构造一次，
/// 父 widget 重建时不再重复 `withValues` 分配。
final _vignetteDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      NoirTokens.inkDeep.withValues(alpha: 0.55),
    ],
    stops: const [0.55, 1.0],
  ),
);

class NoirBackground extends StatelessWidget {
  final Widget child;
  final bool showBackdrop;

  const NoirBackground({
    super.key,
    required this.child,
    this.showBackdrop = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── 第 1 层：径向深色渐变（顶部微亮，底部深） ──
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.4, -0.6),
                radius: 1.4,
                colors: [NoirTokens.ink, NoirTokens.inkDeep],
                stops: [0.0, 0.85],
              ),
            ),
          ),
        ),

        // ── 第 2 层：静态图谱节点（复用 KnowledgeGraphBackdrop 的静态模式） ──
        if (showBackdrop)
          const Positioned.fill(
            child: IgnorePointer(
              child: KnowledgeGraphBackdrop(
                breath: null,
                lineColor: NoirTokens.paper,
                nodeColor: NoirTokens.paper,
                accentColor: NoirTokens.accent,
              ),
            ),
          ),

        // ── 第 3 层：暗角 ──
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(decoration: _vignetteDecoration),
          ),
        ),

        // ── 第 4 层：内容 ──
        child,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 完整页面外壳（含 NoirAppBar + 可选底部导航）
// ─────────────────────────────────────────────────────────────────────────────

class NoirPageShell extends StatelessWidget {
  final Widget body;
  final String? title;
  final String? eyebrow;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final bool showBackdrop;

  const NoirPageShell({
    super.key,
    required this.body,
    this.title,
    this.eyebrow,
    this.actions,
    this.leading,
    this.bottom,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.showBackdrop = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NoirTokens.ink,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: _buildAppBar(),
      bottomNavigationBar: bottomNavigationBar,
      body: NoirBackground(
        showBackdrop: showBackdrop,
        child: body is ScrollView
            ? body
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  child: body,
                ),
              ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    if (title == null && leading == null) return null;
    return NoirAppBar(
      title: title ?? '',
      eyebrow: eyebrow,
      actions: actions,
      leading: leading,
      bottom: bottom,
    );
  }
}
