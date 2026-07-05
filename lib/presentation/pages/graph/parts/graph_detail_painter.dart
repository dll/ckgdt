part of '../graph_detail_page.dart';

class GraphPainter extends CustomPainter {
  final List<NodeModel> nodes;
  final List<EdgeModel> edges;
  final NodeModel? selectedNode;
  final List<PositionedNode> positionedNodes;
  final Set<String> highlightedNodeIds;
  final Set<String> collapsedNodes;
  final Set<String> adjacentNodeIds;
  final bool Function(String) hasChildrenFn;
  final List<String> learningPathNodeIds;
  final Set<String> drillPathNodeIds;
  final List<NodeModel> ancestorPath;

  GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    required this.positionedNodes,
    this.highlightedNodeIds = const {},
    this.collapsedNodes = const {},
    this.adjacentNodeIds = const {},
    required this.hasChildrenFn,
    this.learningPathNodeIds = const [],
    this.drillPathNodeIds = const {},
    this.ancestorPath = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positionedNodes.isEmpty) return;

    final nodeMap = {for (final p in positionedNodes) p.node.id: p};

    // ── 绘制边 ───────────────────────────────────────────────────────────
    for (final edge in edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      final isSearchHighlighted = highlightedNodeIds.contains(edge.sourceId) ||
          highlightedNodeIds.contains(edge.targetId);

      // 判断边是否连接选中节点（邻居高亮）
      final isAdjacentEdge = selectedNode != null &&
          (edge.sourceId == selectedNode!.id || edge.targetId == selectedNode!.id);

      // 判断边是否在上溯/下钻路径中
      final isDrillEdge = drillPathNodeIds.isNotEmpty &&
          drillPathNodeIds.contains(edge.sourceId) &&
          drillPathNodeIds.contains(edge.targetId);

      // 交叉引用边（虚线）
      final isDashed = edge.style == 'dashed' || edge.edgeType == 'requires' ||
          edge.edgeType == 'implements' || edge.edgeType == 'supports' ||
          edge.edgeType == 'guides';

      Color edgeColor;
      double edgeWidth;
      if (isDrillEdge) {
        edgeColor = const Color(0xFFFF8F00); // 琥珀色
        edgeWidth = 3.0;
      } else if (isAdjacentEdge) {
        edgeColor = Colors.red.shade400;
        edgeWidth = 2.5;
      } else if (isSearchHighlighted) {
        edgeColor = Colors.blue.shade300;
        edgeWidth = 2.0;
      } else if (isDashed) {
        edgeColor = const Color(0xFFFF5722);
        edgeWidth = 1.5;
      } else {
        edgeColor = Colors.grey.shade300;
        edgeWidth = 1.2;
      }

      final edgePaint = Paint()
        ..color = edgeColor
        ..strokeWidth = edgeWidth
        ..style = PaintingStyle.stroke;

      final srcOff = Offset(src.x, src.y);
      final tgtOff = Offset(tgt.x, tgt.y);

      // 贝塞尔曲线替代直线
      final mid = Offset((src.x + tgt.x) / 2, (src.y + tgt.y) / 2);
      final dx = tgt.x - src.x;
      final dy = tgt.y - src.y;
      final ctrl = Offset(mid.dx - dy * 0.1, mid.dy + dx * 0.1);

      final path = Path()
        ..moveTo(srcOff.dx, srcOff.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, tgtOff.dx, tgtOff.dy);
      canvas.drawPath(path, edgePaint);

      // 箭头（调整到节点边缘而非中心）
      const nodeRadius = 28.0;
      final dist = (tgtOff - srcOff).distance;
      if (dist > nodeRadius * 2) {
        final t = 1 - nodeRadius / dist;
        final arrowEnd = Offset(
          srcOff.dx + (tgtOff.dx - srcOff.dx) * t,
          srcOff.dy + (tgtOff.dy - srcOff.dy) * t,
        );
        _drawArrow(canvas, srcOff, arrowEnd,
            edgePaint..style = PaintingStyle.fill);
      }

      // 边标签
      if (edge.label != null && edge.label!.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: edge.label,
            style: TextStyle(
                fontSize: 9, color: Colors.grey.shade500),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 2));
      }
    }

    // ── 绘制上溯/下钻路径高亮叠加 ─────────────────────────────────────────
    if (drillPathNodeIds.isNotEmpty) {
      // 绘制上溯路径连线（琥珀色粗线，带光晕）
      if (ancestorPath.length >= 2) {
        final ancestorPaint = Paint()
          ..color = const Color(0xFFFF8F00)
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final ancestorGlow = Paint()
          ..color = const Color(0xFFFF8F00).withOpacity(0.15)
          ..strokeWidth = 16.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        for (int i = 0; i < ancestorPath.length - 1; i++) {
          final fromNode = nodeMap[ancestorPath[i].id];
          final toNode = nodeMap[ancestorPath[i + 1].id];
          if (fromNode == null || toNode == null) continue;

          final start = Offset(fromNode.x, fromNode.y);
          final end = Offset(toNode.x, toNode.y);

          canvas.drawLine(start, end, ancestorGlow);
          canvas.drawLine(start, end, ancestorPaint);

          // 路径序号
          final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
          canvas.drawCircle(mid, 10, Paint()..color = Colors.white);
          canvas.drawCircle(
              mid,
              10,
              Paint()
                ..color = const Color(0xFFFF8F00)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
          final tp = TextPainter(
            text: TextSpan(
              text: '${i + 1}',
              style: const TextStyle(
                  color: Color(0xFFFF8F00),
                  fontSize: 9,
                  fontWeight: FontWeight.bold),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
        }

        // 根节点标记
        final rootNode = nodeMap[ancestorPath.first.id];
        if (rootNode != null) {
          canvas.drawCircle(
              Offset(rootNode.x, rootNode.y),
              45,
              Paint()
                ..color = Colors.deepOrange.shade700
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3);
          final rootTp = TextPainter(
            text: const TextSpan(
                text: '根',
                style: TextStyle(
                    color: Color(0xFFE65100),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
            textDirection: TextDirection.ltr,
          )..layout();
          rootTp.paint(canvas,
              Offset(rootNode.x - rootTp.width / 2, rootNode.y - 55));
        }
      }

      // 下钻路径中所有节点的琥珀色外圈
      for (final nodeId in drillPathNodeIds) {
        final pNode = nodeMap[nodeId];
        if (pNode == null) continue;
        // 不重复标记已在祖先路径中的节点
        if (ancestorPath.any((a) => a.id == nodeId)) continue;

        canvas.drawCircle(
          Offset(pNode.x, pNode.y),
          38,
          Paint()
            ..color = const Color(0xFFFF8F00).withOpacity(0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }

    // ── 绘制学习路径叠加 ─────────────────────────────────────────────────
    if (learningPathNodeIds.length >= 2) {
      final pathPaint = Paint()
        ..color = const Color(0xFF4CAF50)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final pathGlowPaint = Paint()
        ..color = const Color(0xFF4CAF50).withOpacity(0.15)
        ..strokeWidth = 14.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < learningPathNodeIds.length - 1; i++) {
        final fromNode = nodeMap[learningPathNodeIds[i]];
        final toNode = nodeMap[learningPathNodeIds[i + 1]];
        if (fromNode == null || toNode == null) continue;

        final start = Offset(fromNode.x, fromNode.y);
        final end = Offset(toNode.x, toNode.y);

        // 绿色光晕线
        canvas.drawLine(start, end, pathGlowPaint);
        // 绿色实线
        canvas.drawLine(start, end, pathPaint);

        // 路径序号标记
        final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final numPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(mid, 12, numPaint);
        canvas.drawCircle(
            mid,
            12,
            Paint()
              ..color = const Color(0xFF4CAF50)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);

        final tp = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 10,
                fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
      }

      // 起点/终点标记
      final startNode = nodeMap[learningPathNodeIds.first];
      final endNode = nodeMap[learningPathNodeIds.last];
      if (startNode != null) {
        final sp = Paint()
          ..color = Colors.green.shade700
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(Offset(startNode.x, startNode.y), 45, sp);
        // "起" 标签
        final startTp = TextPainter(
          text: const TextSpan(
              text: '起',
              style: TextStyle(
                  color: Color(0xFF2E7D32),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        startTp.paint(canvas,
            Offset(startNode.x - startTp.width / 2, startNode.y - 55));
      }
      if (endNode != null) {
        final ep = Paint()
          ..color = Colors.red.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(Offset(endNode.x, endNode.y), 45, ep);
        final endTp = TextPainter(
          text: const TextSpan(
              text: '终',
              style: TextStyle(
                  color: Color(0xFFE53935),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        endTp.paint(
            canvas, Offset(endNode.x - endTp.width / 2, endNode.y - 55));
      }
    }

    // ── 绘制节点 ─────────────────────────────────────────────────────────
    for (final pNode in positionedNodes) {
      final node = pNode.node;
      final isSelected = selectedNode?.id == node.id;
      final isHighlighted = highlightedNodeIds.contains(node.id);
      final isAdjacent = adjacentNodeIds.contains(node.id);
      final isCollapsed = collapsedNodes.contains(node.id);
      final hasChildren = hasChildrenFn(node.id);
      final isDrillNode = drillPathNodeIds.contains(node.id);

      final baseRadius = _getNodeRadius(node);
      final radius = isSelected ? baseRadius + 8 : baseRadius;
      final center = Offset(pNode.x, pNode.y);
      final nodeColor = _getNodeColor(node);

      // 上溯/下钻路径光晕（琥珀色）
      if (isDrillNode && !isSelected) {
        final drillGlow = Paint()
          ..color = const Color(0xFFFF8F00).withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(center, radius + 8, drillGlow);
        // 琥珀色边框
        canvas.drawCircle(
            center,
            radius + 3,
            Paint()
              ..color = const Color(0xFFFF8F00)
              ..strokeWidth = 2.5
              ..style = PaintingStyle.stroke);
      }

      // 搜索高亮光晕（黄色）
      if (isHighlighted) {
        final glowPaint = Paint()
          ..color = Colors.yellow.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(center, radius + 10, glowPaint);
      }

      // 邻居高亮光晕（红色/橙色）
      if (isAdjacent && !isSelected) {
        final adjGlow = Paint()
          ..color = Colors.red.withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(center, radius + 8, adjGlow);
        // 邻居虚线边框
        final adjBorder = Paint()
          ..color = Colors.red.shade300
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, radius + 3, adjBorder);
      }

      // 阴影
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(center.dx + 2, center.dy + 3), radius, shadowPaint);

      // 节点形状（按 nodeType 区分）
      _drawNodeShape(canvas, center, radius, nodeColor, node.nodeType);

      // 选中边框
      if (isSelected) {
        final selPaint = Paint()
          ..color = Colors.blue
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, radius + 2, selPaint);
      }

      // 折叠指示器
      if (hasChildren) {
        final indicator = isCollapsed ? '+' : '−';
        final indColor = isCollapsed ? Colors.orange : Colors.green;
        const indRadius = 9.0;
        final indCenter =
            Offset(center.dx + radius - 4, center.dy - radius + 4);
        canvas.drawCircle(
            indCenter, indRadius, Paint()..color = Colors.white);
        canvas.drawCircle(
            indCenter,
            indRadius,
            Paint()
              ..color = indColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
        final tp = TextPainter(
          text: TextSpan(
            text: indicator,
            style: TextStyle(
                color: indColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(indCenter.dx - tp.width / 2, indCenter.dy - tp.height / 2));
      }

      // 节点标题
      final displayTitle =
          node.title.length > 8 ? '${node.title.substring(0, 8)}…' : node.title;
      final textPainter = TextPainter(
        text: TextSpan(
          text: displayTitle,
          style: TextStyle(
            color: _isLightColor(nodeColor) ? Colors.black87 : Colors.white,
            fontSize: node.level == 0 ? 11 : 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 2 - 8);
      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2,
            center.dy - textPainter.height / 2),
      );
    }
  }

  double _getNodeRadius(NodeModel node) {
    switch (node.level) {
      case 0: return 38;
      case 1: return 32;
      case 2: return 28;
      default: return 24;
    }
  }

  void _drawNodeShape(
      Canvas canvas, Offset center, double radius, Color color, String? type) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;

    switch (type) {
      case 'root':
        // 双圆（表示根节点）
        canvas.drawCircle(center, radius, paint);
        canvas.drawCircle(
            center,
            radius - 4,
            Paint()
              ..color = Colors.white.withOpacity(0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        break;
      case 'category':
        // 圆角矩形
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: center, width: radius * 2, height: radius * 1.6),
          Radius.circular(radius * 0.4),
        );
        canvas.drawRRect(rect, paint);
        break;
      case 'section':
        // 六边形
        _drawPolygon(canvas, center, radius, 6, paint);
        break;
      default:
        // 默认圆形
        canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawPolygon(
      Canvas canvas, Offset center, double radius, int sides, Paint paint) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  Color _getNodeColor(NodeModel node) {
    // 优先使用节点自定义颜色
    if (node.color != null && node.color!.isNotEmpty) {
      try {
        return Color(int.parse(node.color!.replaceFirst('#', '0xFF')));
      } catch (e) { swallowDebug(e, tag: 'graph_detail_painter'); }
    }
    // 按层级着色
    const levelColors = [
      Color(0xFFE53935), // L0 红
      Color(0xFFFF9800), // L1 橙
      Color(0xFF4CAF50), // L2 绿
      Color(0xFF2196F3), // L3 蓝
      Color(0xFF9C27B0), // L4 紫
      Color(0xFF607D8B), // L5 灰蓝
    ];
    return node.level < levelColors.length
        ? levelColors[node.level]
        : const Color(0xFF9E9E9E);
  }

  bool _isLightColor(Color color) {
    return color.computeLuminance() > 0.5;
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    const arrowSize = 10.0;
    final angle = (end - start).direction;
    final p1 = Offset(
      end.dx - arrowSize * math.cos(angle - 0.4),
      end.dy - arrowSize * math.sin(angle - 0.4),
    );
    final p2 = Offset(
      end.dx - arrowSize * math.cos(angle + 0.4),
      end.dy - arrowSize * math.sin(angle + 0.4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant GraphPainter old) =>
      old.selectedNode != selectedNode ||
      old.positionedNodes != positionedNodes ||
      old.highlightedNodeIds != highlightedNodeIds ||
      old.collapsedNodes != collapsedNodes ||
      old.adjacentNodeIds != adjacentNodeIds ||
      old.learningPathNodeIds != learningPathNodeIds ||
      old.drillPathNodeIds != drillPathNodeIds ||
      old.ancestorPath != ancestorPath;
}
