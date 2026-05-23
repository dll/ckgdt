import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 知识图谱节点-边背景画布。
///
/// 在登录页底层绘制一张稀疏的图谱：12-18 个节点 + 沿德劳内式邻近规则连边，
/// 节点带呼吸式发光（[t] 0..1 周期），主题色作为线条颜色，琥珀色为强调节点。
///
/// 完全 stateless 的 [CustomPainter] —— 调用方负责动画驱动 [t]。
class KnowledgeGraphBackdrop extends StatelessWidget {
  final Animation<double> breath;
  final Color lineColor;
  final Color nodeColor;
  final Color accentColor;

  const KnowledgeGraphBackdrop({
    super.key,
    required this.breath,
    required this.lineColor,
    required this.nodeColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: breath,
      builder: (_, __) => CustomPaint(
        size: Size.infinite,
        painter: _GraphPainter(
          t: breath.value,
          lineColor: lineColor,
          nodeColor: nodeColor,
          accentColor: accentColor,
        ),
      ),
    );
  }
}

/// 一次性计算的图谱布局（节点位置 + 邻接边），按画布 [Size] 缓存避免每帧 O(n²) 重算。
typedef _GraphLayout = ({
  Size size,
  List<Offset> nodes,
  List<(int, int)> edges,
});

class _GraphPainter extends CustomPainter {
  final double t;
  final Color lineColor;
  final Color nodeColor;
  final Color accentColor;

  /// 按画布 Size 索引的小 LRU 缓存（cap=2）。
  /// 多个 [KnowledgeGraphBackdrop] 同时存在时（比如登录页 + 弹窗背景）每个尺寸独占一份，
  /// 不再因 last-write-wins 导致 60 fps 抖动。
  static final _layoutCache = <Size, _GraphLayout>{};
  static const _layoutCacheCap = 2;

  // 复用的 Paint 对象（避免每帧 new）。Paint 对象设计为可变 + 复用。
  static final _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  static final _glowPaint = Paint()..style = PaintingStyle.fill;
  static final _corePaint = Paint();
  static final _refPaint = Paint()..strokeWidth = 0.5;

  _GraphPainter({
    required this.t,
    required this.lineColor,
    required this.nodeColor,
    required this.accentColor,
  });

  static _GraphLayout _computeLayout(Size size) {
    final cached = _layoutCache[size];
    if (cached != null) return cached;

    final rng = math.Random(42);
    final w = size.width;
    final h = size.height;
    const cols = 4;
    const rows = 4;

    final nodes = <Offset>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = (c + 0.5) / cols * w + (rng.nextDouble() - 0.5) * w * 0.18;
        final y = (r + 0.5) / rows * h + (rng.nextDouble() - 0.5) * h * 0.18;
        nodes.add(Offset(x, y));
      }
    }

    final edgeSet = <(int, int)>{};
    for (var i = 0; i < nodes.length; i++) {
      final dists = <(int, double)>[];
      for (var j = 0; j < nodes.length; j++) {
        if (i == j) continue;
        dists.add((j, (nodes[i] - nodes[j]).distance));
      }
      dists.sort((a, b) => a.$2.compareTo(b.$2));
      for (final (j, _) in dists.take(2 + rng.nextInt(2))) {
        edgeSet.add(i < j ? (i, j) : (j, i));
      }
    }

    final layout = (
      size: size,
      nodes: nodes,
      edges: edgeSet.toList(growable: false),
    );

    if (_layoutCache.length >= _layoutCacheCap) {
      _layoutCache.remove(_layoutCache.keys.first);
    }
    _layoutCache[size] = layout;
    return layout;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = _computeLayout(size);
    final nodes = layout.nodes;
    final edges = layout.edges;
    final w = size.width;
    final h = size.height;

    final breath = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    _linePaint.color = lineColor.withValues(alpha: 0.18 + 0.10 * breath);
    for (final (a, b) in edges) {
      canvas.drawLine(nodes[a], nodes[b], _linePaint);
    }

    for (var i = 0; i < nodes.length; i++) {
      final isAccent = i == 5 || i == 10 || i == 13;
      final base = isAccent ? accentColor : nodeColor;
      final phase = (i * 0.137 + t) % 1.0;
      final pulse = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);

      _glowPaint.color = base.withValues(alpha: 0.10 + 0.10 * pulse);
      canvas.drawCircle(nodes[i], 5 + pulse * 5, _glowPaint);

      _corePaint.color = base.withValues(alpha: 0.85);
      canvas.drawCircle(nodes[i], 2.0 + (isAccent ? 0.8 : 0), _corePaint);
    }

    _refPaint.color = lineColor.withValues(alpha: 0.10);
    canvas.drawLine(const Offset(40, 80), Offset(w - 40, 80), _refPaint);
    canvas.drawLine(Offset(40, h - 80), Offset(w - 40, h - 80), _refPaint);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      old.t != t ||
      old.lineColor != lineColor ||
      old.nodeColor != nodeColor ||
      old.accentColor != accentColor;
}
