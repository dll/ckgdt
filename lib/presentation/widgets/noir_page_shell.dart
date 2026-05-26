import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/design/noir_tokens.dart';
import '../../core/design/noir_components.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 静态知识图谱背景画师 —— 无动画，轻量，每页可复用
// 16 个节点（4×4 抖动）+ 邻近连边 + 3 个琥珀强调节点 + 恒定发光
// ─────────────────────────────────────────────────────────────────────────────

const _cols = 4;
const _rows = 4;

class _StaticGraphPainter extends CustomPainter {
  final Color lineColor;
  final Color nodeColor;
  final Color accentColor;

  static final _layoutCache = <Size, List<Offset>>{};
  static final _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  static final _glowPaint = Paint()..style = PaintingStyle.fill;
  static final _corePaint = Paint();
  static final _horizontalPaint = Paint()..strokeWidth = 0.5;

  _StaticGraphPainter({
    required this.lineColor,
    required this.nodeColor,
    required this.accentColor,
  });

  List<Offset> _getNodes(Size size) {
    final cached = _layoutCache[size];
    if (cached != null) return cached;

    final rng = math.Random(42);
    final w = size.width;
    final h = size.height;
    final nodes = <Offset>[];
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final x = (c + 0.5) / _cols * w + (rng.nextDouble() - 0.5) * w * 0.18;
        final y = (r + 0.5) / _rows * h + (rng.nextDouble() - 0.5) * h * 0.18;
        nodes.add(Offset(x, y));
      }
    }
    if (_layoutCache.length >= 2) _layoutCache.remove(_layoutCache.keys.first);
    _layoutCache[size] = nodes;
    return nodes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final nodes = _getNodes(size);
    final w = size.width;
    final h = size.height;

    // 边
    _linePaint.color = lineColor.withValues(alpha: 0.15);
    for (var i = 0; i < nodes.length; i++) {
      final dists = <(int, double)>[];
      for (var j = 0; j < nodes.length; j++) {
        if (i == j) continue;
        dists.add((j, (nodes[i] - nodes[j]).distance));
      }
      dists.sort((a, b) => a.$2.compareTo(b.$2));
      for (final (j, _) in dists.take(2)) {
        canvas.drawLine(nodes[i], nodes[j], _linePaint);
      }
    }

    // 节点
    for (var i = 0; i < nodes.length; i++) {
      final isAccent = i == 5 || i == 10 || i == 13;
      final base = isAccent ? accentColor : nodeColor;

      _glowPaint.color = base.withValues(alpha: 0.10);
      canvas.drawCircle(nodes[i], 6, _glowPaint);

      _corePaint.color = base.withValues(alpha: isAccent ? 0.9 : 0.7);
      canvas.drawCircle(nodes[i], isAccent ? 2.8 : 2.0, _corePaint);
    }

    // 水平参考线
    _horizontalPaint.color = lineColor.withValues(alpha: 0.06);
    canvas.drawLine(const Offset(40, 80), Offset(w - 40, 80), _horizontalPaint);
    canvas.drawLine(Offset(40, h - 80), Offset(w - 40, h - 80), _horizontalPaint);
  }

  @override
  bool shouldRepaint(covariant _StaticGraphPainter old) =>
      old.lineColor != lineColor ||
      old.nodeColor != nodeColor ||
      old.accentColor != accentColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// 登录页式背景层 —— 径向渐变 + 静态节点 + 暗角
// ─────────────────────────────────────────────────────────────────────────────

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
        Positioned.fill(
          child: const DecoratedBox(
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

        // ── 第 2 层：静态图谱节点 ──
        if (showBackdrop)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: _StaticGraphPainter(
                  lineColor: NoirTokens.paper,
                  nodeColor: NoirTokens.paper,
                  accentColor: NoirTokens.accent,
                ),
              ),
            ),
          ),

        // ── 第 3 层：暗角 ──
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    NoirTokens.inkDeep.withValues(alpha: 0.55),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
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
