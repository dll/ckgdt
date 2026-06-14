part of '../knowledge_graph_page.dart';

class _LegendLinePainter extends CustomPainter {
  final Color color;
  final bool dashed;

  _LegendLinePainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (dashed) {
      const dashWidth = 3.0;
      const dashSpace = 2.0;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset((x + dashWidth).clamp(0, size.width), size.height / 2),
          paint,
        );
        x += dashWidth + dashSpace;
      }
    } else {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter old) =>
      old.color != color || old.dashed != dashed;
}

// ══════════════════════════════════════════════════════════════════════════════
// KnowledgeGraphPainter — 自定义绘制知识图谱
// ══════════════════════════════════════════════════════════════════════════════

class _KnowledgeGraphPainter extends CustomPainter {
  final List<_ConceptNode> nodes;
  final List<_ConceptEdge> edges;
  final _ConceptNode? selectedNode;
  final Set<int> highlightedNodeIds;
  final Set<int> adjacentNodeIds;
  final Set<int> adjacentEdgeIds;
  final _ConceptNode? focusedNode;
  final _ViewMode viewMode;
  final MaskShape maskShape;
  final Path? maskPath;
  final String? userName;
  final Map<int, String>? progressMap;
  final Map<int, double>? progressRatioMap;

  _KnowledgeGraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    this.highlightedNodeIds = const {},
    this.adjacentNodeIds = const {},
    this.adjacentEdgeIds = const {},
    this.focusedNode,
    this.viewMode = _ViewMode.global,
    this.maskShape = MaskShape.none,
    this.maskPath,
    this.userName,
    this.progressMap,
    this.progressRatioMap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final nodeMap = {for (final n in nodes) n.id: n};

    // ── 章节视图：绘制章节分组背景 ────────────────────────────────────────
    if (viewMode == _ViewMode.chapter || viewMode == _ViewMode.achievement) {
      _drawChapterBackgrounds(canvas, nodeMap);
    } else if (viewMode == _ViewMode.mask && maskPath != null) {
      // 蒙版视图：绘制蒙版轮廓
      _drawMaskOutline(canvas, size);
    } else {
      // 全局视图：绘制分散的技术Logo水印
      _drawGlobalWatermarks(canvas, size);
    }

    // ── 绘制边 ─────────────────────────────────────────────────────────────
    for (final edge in edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      final isAdjacentEdge = adjacentEdgeIds.contains(edge.id);
      final isHighlightedEdge = highlightedNodeIds.contains(edge.sourceId) &&
          highlightedNodeIds.contains(edge.targetId);

      final rStyle = edge.style;
      Color edgeColor;
      double edgeWidth;

      if (isAdjacentEdge) {
        edgeColor = rStyle.color;
        edgeWidth = 2.5;
      } else if (isHighlightedEdge) {
        edgeColor = rStyle.color;
        edgeWidth = 2.0;
      } else if (selectedNode != null || highlightedNodeIds.isNotEmpty) {
        // 有选中或高亮时，非相关边减淡
        edgeColor = rStyle.color.withValues(alpha: 0.15);
        edgeWidth = 1.0;
      } else {
        edgeColor = rStyle.color.withValues(alpha: 0.5);
        edgeWidth = 1.5;
      }

      final edgePaint = Paint()
        ..color = edgeColor
        ..strokeWidth = edgeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final srcOff = Offset(src.x, src.y);
      final tgtOff = Offset(tgt.x, tgt.y);

      // 贝塞尔曲线（微弧）
      final mid = Offset((src.x + tgt.x) / 2, (src.y + tgt.y) / 2);
      final dx = tgt.x - src.x;
      final dy = tgt.y - src.y;
      final perpX = -dy * 0.12;
      final perpY = dx * 0.12;
      final ctrl = Offset(mid.dx + perpX, mid.dy + perpY);

      if (rStyle.dashed) {
        _drawDashedQuadBezier(canvas, srcOff, ctrl, tgtOff, edgePaint);
      } else {
        final path = Path()
          ..moveTo(srcOff.dx, srcOff.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, tgtOff.dx, tgtOff.dy);
        canvas.drawPath(path, edgePaint);
      }

      // 箭头
      final dist = (tgtOff - srcOff).distance;
      if (dist > (src.radius + tgt.radius + 10)) {
        final tgtRadius = tgt.radius;
        final t = 1 - (tgtRadius + 4) / dist;
        final arrowEnd = Offset(
          srcOff.dx + (tgtOff.dx - srcOff.dx) * t,
          srcOff.dy + (tgtOff.dy - srcOff.dy) * t,
        );
        _drawArrowHead(canvas, ctrl, arrowEnd, edgePaint);

        // 双向箭头
        if (edge.bidirectional) {
          final srcRadius = src.radius;
          final t2 = (srcRadius + 4) / dist;
          final arrowStart = Offset(
            srcOff.dx + (tgtOff.dx - srcOff.dx) * t2,
            srcOff.dy + (tgtOff.dy - srcOff.dy) * t2,
          );
          _drawArrowHead(canvas, ctrl, arrowStart, edgePaint);
        }
      }

      // 边标签
      if (isAdjacentEdge || (!_hasSelection() && !_hasHighlight())) {
        final labelText = edge.label ?? rStyle.label;
        if (labelText.isNotEmpty) {
          final labelBg = Paint()..color = Colors.white.withValues(alpha: 0.85);
          final tp = TextPainter(
            text: TextSpan(
              text: labelText,
              style: TextStyle(
                fontSize: 9,
                color: edgeColor.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final labelPos =
              Offset(ctrl.dx - tp.width / 2, ctrl.dy - tp.height / 2);
          final labelRect = Rect.fromLTWH(
            labelPos.dx - 3,
            labelPos.dy - 1,
            tp.width + 6,
            tp.height + 2,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
            labelBg,
          );
          tp.paint(canvas, labelPos);
        }
      }
    }

    // ── 绘制节点 ──────────────────────────────────────────────────────────
    for (final node in nodes) {
      final isSelected = selectedNode?.id == node.id;
      final isHighlighted = highlightedNodeIds.contains(node.id);
      final isAdjacent = adjacentNodeIds.contains(node.id);
      final isFocusCenter = focusedNode?.id == node.id;

      final radius = node.radius;
      final center = Offset(node.x, node.y);

      // 达成度模式：根据进度着色
      final Color nodeColor;
      if (progressRatioMap != null && progressRatioMap!.containsKey(node.id)) {
        // 达成度热力图：<60% 红，60-79% 橙，≥80% 绿
        final ratio = (progressRatioMap![node.id] ?? 0.0).clamp(0.0, 1.0);
        nodeColor = ratio >= 0.8
            ? const Color(0xFF4CAF50)
            : ratio >= 0.6
                ? const Color(0xFFFF9800)
                : const Color(0xFFE53935);
      } else if (progressMap != null) {
        final status = progressMap![node.id] ?? 'not_started';
        switch (status) {
          case 'completed':
            nodeColor = const Color(0xFF4CAF50); // 绿色
            break;
          case 'in_progress':
            nodeColor = const Color(0xFFFF9800); // 黄/橙色
            break;
          default:
            nodeColor = const Color(0xFFE53935); // 红色
        }
      } else {
        nodeColor = node.color;
      }

      // 判断是否应该减淡（有选中/高亮时，非相关节点减淡）
      final dimmed = (_hasSelection() || _hasHighlight()) &&
          !isSelected &&
          !isHighlighted &&
          !isAdjacent &&
          !isFocusCenter;

      // 搜索高亮光晕（黄色）
      if (isHighlighted && !isSelected) {
        final glowPaint = Paint()
          ..color = const Color(0xFFFFF176).withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
        canvas.drawCircle(center, radius + 12, glowPaint);
      }

      // 邻居高亮光晕
      if (isAdjacent && !isSelected) {
        final adjGlow = Paint()
          ..color = nodeColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(center, radius + 8, adjGlow);
      }

      // 选中光晕
      if (isSelected) {
        final selGlow = Paint()
          ..color = const Color(0xFF1677FF).withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
        canvas.drawCircle(center, radius + 14, selGlow);
      }

      // 焦点中心标记
      if (isFocusCenter) {
        final focusGlow = Paint()
          ..color = const Color(0xFF1677FF).withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
        canvas.drawCircle(center, radius + 20, focusGlow);

        // 双圈指示
        canvas.drawCircle(
          center,
          radius + 6,
          Paint()
            ..color = const Color(0xFF1677FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }

      // 阴影
      if (!dimmed) {
        final shadowPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(
            Offset(center.dx + 1.5, center.dy + 2.5), radius, shadowPaint);
      }

      // 节点圆
      final fillColor = dimmed ? nodeColor.withValues(alpha: 0.2) : nodeColor;
      final nodePaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;

      // 根据概念类型绘制不同形状
      switch (node.type) {
        case 'framework':
          // 圆角矩形
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: center, width: radius * 2, height: radius * 1.7),
            Radius.circular(radius * 0.35),
          );
          canvas.drawRRect(rect, nodePaint);
          break;
        case 'platform':
          // 六边形
          _drawPolygon(canvas, center, radius, 6, nodePaint);
          break;
        case 'pattern':
          // 菱形
          _drawPolygon(canvas, center, radius, 4, nodePaint);
          break;
        default:
          // 默认圆形
          canvas.drawCircle(center, radius, nodePaint);
      }

      // 选中边框环
      if (isSelected) {
        final selRing = Paint()
          ..color = const Color(0xFF1677FF)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;

        switch (node.type) {
          case 'framework':
            final rect = RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: center,
                  width: radius * 2 + 6,
                  height: radius * 1.7 + 6),
              Radius.circular(radius * 0.35 + 3),
            );
            canvas.drawRRect(rect, selRing);
            break;
          case 'platform':
            _drawPolygon(canvas, center, radius + 3, 6, selRing);
            break;
          case 'pattern':
            _drawPolygon(canvas, center, radius + 3, 4, selRing);
            break;
          default:
            canvas.drawCircle(center, radius + 3, selRing);
        }
      }

      // 节点文本
      final displayName =
          node.name.length > 6 ? '${node.name.substring(0, 6)}...' : node.name;
      final textColor = dimmed
          ? Colors.grey.shade400
          : _isLightColor(nodeColor)
              ? Colors.black87
              : Colors.white;

      final textPainter = TextPainter(
        text: TextSpan(
          text: displayName,
          style: TextStyle(
            color: textColor,
            fontSize: node.importance == 'core'
                ? 11
                : node.importance == 'important'
                    ? 10
                    : 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 2 - 6);

      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2,
            center.dy - textPainter.height / 2),
      );

      // 章节标注（章节视图下不显示，因为有背景标注）
      if (viewMode != _ViewMode.chapter &&
          viewMode != _ViewMode.achievement &&
          node.chapter != null &&
          !dimmed) {
        final chTp = TextPainter(
          text: TextSpan(
            text: 'Ch${node.chapter}',
            style: TextStyle(
              fontSize: 8,
              color: dimmed ? Colors.transparent : Colors.grey.shade500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        chTp.paint(
          canvas,
          Offset(center.dx - chTp.width / 2, center.dy + radius + 4),
        );
      }
    }
  }

  // ── 章节背景绘制 ────────────────────────────────────────────────────────

  void _drawChapterBackgrounds(Canvas canvas, Map<int, _ConceptNode> nodeMap) {
    // 按章节分组
    final byChapter = <int, List<_ConceptNode>>{};
    for (final node in nodes) {
      final ch = node.chapter ?? 0;
      byChapter.putIfAbsent(ch, () => []).add(node);
    }

    for (final entry in byChapter.entries) {
      if (entry.value.isEmpty) continue;
      final ch = entry.key;
      final color = ChapterHelper.chapterColors[ch] ?? const Color(0xFF1677FF);

      // 找边界
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final n in entry.value) {
        if (n.x - n.radius < minX) minX = n.x - n.radius;
        if (n.y - n.radius < minY) minY = n.y - n.radius;
        if (n.x + n.radius > maxX) maxX = n.x + n.radius;
        if (n.y + n.radius > maxY) maxY = n.y + n.radius;
      }

      final margin = 40.0;
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
            minX - margin, minY - margin - 25, maxX + margin, maxY + margin),
        const Radius.circular(20),
      );

      // 背景
      canvas.drawRRect(
        bgRect,
        Paint()..color = color.withValues(alpha: 0.05),
      );
      // 边框
      canvas.drawRRect(
        bgRect,
        Paint()
          ..color = color.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // ── 技术 Logo 水印 ────────────────────────────────────────────────
      _drawChapterLogoWatermarks(canvas, ch, bgRect.outerRect, color);

      // 章节标题（含简称）
      final shortName = ChapterHelper.chapterShortNames[ch] ?? '';
      final titleText = ch == 0 ? '未分类' : '第 $ch 章 $shortName';
      final tp = TextPainter(
        text: TextSpan(
          text: titleText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color.withValues(alpha: 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(minX - margin + 12, minY - margin - 18));
    }
  }

  /// 在章节背景中绘制技术 Logo 水印（半透明文字 + 图标）
  void _drawChapterLogoWatermarks(
      Canvas canvas, int chapter, Rect rect, Color color) {
    final logos = ChapterHelper.chapterLogos[chapter];
    if (logos == null || logos.isEmpty) return;

    // 裁剪区域防溢出
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)));

    // 计算布局：Logo 分散在背景区域中
    final rng = math.Random(chapter * 1337);
    final areaW = rect.width;
    final areaH = rect.height;

    // 大号文字水印 — 每个logo绘制一次
    for (int i = 0; i < logos.length; i++) {
      final logo = logos[i];
      // 使用确定性随机位置，分散在区域内
      final col = i % 2;
      final row = i ~/ 2;
      final cellW = areaW / 2;
      final cellH = areaH / math.max(((logos.length + 1) ~/ 2), 1);

      final cx = rect.left +
          cellW * col +
          cellW * 0.5 +
          (rng.nextDouble() - 0.5) * cellW * 0.4;
      final cy = rect.top +
          cellH * row +
          cellH * 0.5 +
          (rng.nextDouble() - 0.5) * cellH * 0.3;

      // 旋转角度（轻微倾斜）
      final angle = (rng.nextDouble() - 0.5) * 0.3; // -0.15 ~ +0.15 rad

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);

      // 绘制文字水印
      final fontSize =
          logo.length <= 3 ? 42.0 : (logo.length <= 5 ? 34.0 : 26.0);
      final textPainter = TextPainter(
        text: TextSpan(
          text: logo,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: color.withValues(alpha: 0.06),
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }

    // 绘制章节主图标水印（居中大图标）
    final iconData = ChapterHelper.chapterIcons[chapter];
    if (iconData != null) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(iconData.codePoint),
          style: TextStyle(
            fontSize: 120,
            fontFamily: iconData.fontFamily,
            package: iconData.fontPackage,
            color: color.withValues(alpha: 0.04),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        Offset(
          rect.center.dx - iconPainter.width / 2,
          rect.center.dy - iconPainter.height / 2,
        ),
      );
    }

    canvas.restore();
  }

  /// 全局视图：在画布上绘制分散的技术Logo水印
  void _drawGlobalWatermarks(Canvas canvas, Size size) {
    // 按章节收集节点中心，计算每个章节的质心
    final chapterCenters = <int, Offset>{};
    final chapterCounts = <int, int>{};
    for (final node in nodes) {
      final ch = node.chapter ?? 0;
      if (ch == 0) continue;
      final prev = chapterCenters[ch] ?? Offset.zero;
      chapterCenters[ch] = Offset(prev.dx + node.x, prev.dy + node.y);
      chapterCounts[ch] = (chapterCounts[ch] ?? 0) + 1;
    }
    // 计算质心
    for (final ch in chapterCenters.keys.toList()) {
      final count = chapterCounts[ch]!;
      chapterCenters[ch] = Offset(
        chapterCenters[ch]!.dx / count,
        chapterCenters[ch]!.dy / count,
      );
    }

    // 在每个章节质心附近绘制1-2个主Logo
    for (final ch in chapterCenters.keys) {
      final center = chapterCenters[ch]!;
      final color = ChapterHelper.chapterColors[ch] ?? const Color(0xFF1677FF);
      final logos = ChapterHelper.chapterLogos[ch];
      if (logos == null || logos.isEmpty) continue;

      // 只绘制前2个最关键的Logo
      final rng = math.Random(ch * 2023);
      for (int i = 0; i < math.min(2, logos.length); i++) {
        final logo = logos[i];
        final offsetX = (rng.nextDouble() - 0.5) * 160;
        final offsetY = (rng.nextDouble() - 0.5) * 120;
        final angle = (rng.nextDouble() - 0.5) * 0.25;

        canvas.save();
        canvas.translate(center.dx + offsetX, center.dy + offsetY);
        canvas.rotate(angle);

        final fontSize = logo.length <= 3 ? 36.0 : 28.0;
        final tp = TextPainter(
          text: TextSpan(
            text: logo,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: color.withValues(alpha: 0.05),
              letterSpacing: 2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

        canvas.restore();
      }
    }
  }

  // ── 辅助方法 ──────────────────────────────────────────────────────────

  bool _hasSelection() => selectedNode != null;
  bool _hasHighlight() => highlightedNodeIds.isNotEmpty;

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

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    const arrowSize = 8.0;
    final angle = (to - from).direction;
    final p1 = Offset(
      to.dx - arrowSize * math.cos(angle - 0.4),
      to.dy - arrowSize * math.sin(angle - 0.4),
    );
    final p2 = Offset(
      to.dx - arrowSize * math.cos(angle + 0.4),
      to.dy - arrowSize * math.sin(angle + 0.4),
    );

    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      fillPaint,
    );
  }

  void _drawDashedQuadBezier(
      Canvas canvas, Offset start, Offset control, Offset end, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    const steps = 80;

    var prevPoint = start;
    var accum = 0.0;
    var drawing = true;

    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final x = (1 - t) * (1 - t) * start.dx +
          2 * (1 - t) * t * control.dx +
          t * t * end.dx;
      final y = (1 - t) * (1 - t) * start.dy +
          2 * (1 - t) * t * control.dy +
          t * t * end.dy;
      final curPoint = Offset(x, y);
      final segLen = (curPoint - prevPoint).distance;
      accum += segLen;

      if (drawing) {
        canvas.drawLine(prevPoint, curPoint, paint);
        if (accum >= dashLen) {
          drawing = false;
          accum = 0;
        }
      } else {
        if (accum >= gapLen) {
          drawing = true;
          accum = 0;
        }
      }
      prevPoint = curPoint;
    }
  }

  bool _isLightColor(Color color) {
    return color.computeLuminance() > 0.5;
  }

  // ── 蒙版轮廓绘制 ──────────────────────────────────────────────────────

  void _drawMaskOutline(Canvas canvas, Size size) {
    if (maskPath == null) return;

    // 蒙版填充（极淡）
    canvas.drawPath(
      maskPath!,
      Paint()
        ..color = Colors.deepPurple.withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    // 蒙版轮廓虚线
    canvas.drawPath(
      maskPath!,
      Paint()
        ..color = Colors.deepPurple.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 蒙版名称标签（头像蒙版时显示用户姓名）
    final labelText = (maskShape == MaskShape.avatar && userName != null)
        ? userName!
        : maskShape.label;
    final labelFontSize =
        (maskShape == MaskShape.avatar && userName != null) ? 120.0 : 80.0;
    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          fontSize: labelFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.deepPurple.withValues(alpha: 0.05),
          letterSpacing: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter old) =>
      old.selectedNode != selectedNode ||
      old.nodes != nodes ||
      old.edges != edges ||
      old.highlightedNodeIds != highlightedNodeIds ||
      old.adjacentNodeIds != adjacentNodeIds ||
      old.adjacentEdgeIds != adjacentEdgeIds ||
      old.focusedNode != focusedNode ||
      old.viewMode != viewMode ||
      old.maskShape != maskShape ||
      old.userName != userName ||
      old.progressMap != progressMap ||
      old.progressRatioMap != progressRatioMap;
}

// ══════════════════════════════════════════════════════════════════════════════
// MinimapPainter — 鹰眼小地图绘制
// ══════════════════════════════════════════════════════════════════════════════

class _MinimapPainter extends CustomPainter {
  final List<_ConceptNode> nodes;
  final List<_ConceptEdge> edges;
  final double canvasWidth;
  final double canvasHeight;
  final Rect viewportRect;
  final Path? maskPath;

  _MinimapPainter({
    required this.nodes,
    required this.edges,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.viewportRect,
    this.maskPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / canvasWidth;
    final sy = size.height / canvasHeight;

    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF8FAFE),
    );

    // 蒙版轮廓（如果有）
    if (maskPath != null) {
      final scaledMask = maskPath!.transform(
        Matrix4.diagonal3Values(sx, sy, 1).storage,
      );
      canvas.drawPath(
        scaledMask,
        Paint()
          ..color = Colors.deepPurple.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill,
      );
    }

    // 绘制边（细线）
    final nodeMap = {for (final n in nodes) n.id: n};
    for (final edge in edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;
      canvas.drawLine(
        Offset(src.x * sx, src.y * sy),
        Offset(tgt.x * sx, tgt.y * sy),
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.25)
          ..strokeWidth = 0.5,
      );
    }

    // 绘制节点（小点）
    for (final node in nodes) {
      final center = Offset(node.x * sx, node.y * sy);
      final r = (node.radius * sx).clamp(1.5, 4.0);
      canvas.drawCircle(
        center,
        r,
        Paint()..color = node.color.withValues(alpha: 0.8),
      );
    }

    // 绘制视口矩形
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = const Color(0xFF1677FF).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = const Color(0xFF1677FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 标签
    final tp = TextPainter(
      text: TextSpan(
        text: '鹰眼',
        style: TextStyle(
          fontSize: 8,
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(3, 2));
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) =>
      old.viewportRect != viewportRect ||
      old.nodes != nodes ||
      old.edges != edges;
}

// ══════════════════════════════════════════════════════════════════════════════
// _MaskDropdownButton — 蒙版下拉选择按钮（点击弹出网格浮层）
// ══════════════════════════════════════════════════════════════════════════════
