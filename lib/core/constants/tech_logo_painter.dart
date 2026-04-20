// lib/core/constants/tech_logo_painter.dart
//
// Mini official-style tech-stack logos drawn with CustomPainter.
// Designed for chip selectors at 18–24 px.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'mask_shapes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────

/// Displays an official-style tech logo for the given [shape].
///
/// Pass [selected] = true when the chip is active so that logos with dark
/// colours switch to a lighter / white palette for legibility.
class TechLogoWidget extends StatelessWidget {
  final MaskShape shape;
  final double size;

  /// When true the painter uses a lighter / white colour variant.
  final bool selected;

  const TechLogoWidget({
    required this.shape,
    this.size = 22,
    this.selected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TechLogoPainter(shape: shape, selected: selected),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal CustomPainter
// ─────────────────────────────────────────────────────────────────────────────

class _TechLogoPainter extends CustomPainter {
  final MaskShape shape;
  final bool selected;

  const _TechLogoPainter({required this.shape, this.selected = false});

  // ── Dispatch ────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    switch (shape) {
      case MaskShape.none:
        break; // intentionally empty
      case MaskShape.android:
        _paintAndroid(canvas, size);
      case MaskShape.apple:
        _paintApple(canvas, size);
      case MaskShape.flutter:
        _paintFlutter(canvas, size);
      case MaskShape.harmonyOS:
        _paintHarmonyOS(canvas, size);
      case MaskShape.wechat:
        _paintWeChat(canvas, size);
      case MaskShape.dart:
        _paintDart(canvas, size);
      case MaskShape.kotlin:
        _paintKotlin(canvas, size);
      case MaskShape.swift:
        _paintSwift(canvas, size);
      case MaskShape.uniapp:
        _paintUniApp(canvas, size);
      case MaskShape.maui:
        _paintMAUI(canvas, size);
      case MaskShape.cordova:
        _paintCordova(canvas, size);
      case MaskShape.reactNative:
        _paintReactNative(canvas, size);
      case MaskShape.python:
        _paintPython(canvas, size);
      case MaskShape.java:
        _paintJava(canvas, size);
      case MaskShape.typeScript:
        _paintTypeScript(canvas, size);
      case MaskShape.docker:
        _paintDocker(canvas, size);
      case MaskShape.gitHub:
        _paintGitHub(canvas, size);
      case MaskShape.vsCode:
        _paintVSCode(canvas, size);
      case MaskShape.golang:
        _paintGolang(canvas, size);
      case MaskShape.linux:
        _paintLinux(canvas, size);
      case MaskShape.avatar:
        _paintAvatar(canvas, size);
      case MaskShape.brain:
        _paintBrain(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _TechLogoPainter old) =>
      old.shape != shape || old.selected != selected;

  // ══════════════════════════════════════════════════════════════════════════
  // Individual logo painters
  // ══════════════════════════════════════════════════════════════════════════

  // ── Android (#3DDC84) ─────────────────────────────────────────────────────
  //
  //  Head : upper-semicircle arc (dome) + fill rect to close gap
  //  Body : rounded-bottom RRect
  //  Extras: antennas (stroked lines), white eye dots, arm & leg RRects

  void _paintAndroid(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = const Color(0xFF3DDC84)
      ..style = PaintingStyle.fill;

    // ── Head dome ──────────────────────────────────────────────────────
    // Upper semicircle: arc from π (left edge), sweep −π CCW → through top
    // to right edge.  useCenter=false fills the arc-segment (dome shape).
    final headCx = w * 0.50;
    final headCy = h * 0.30; // centre of the full oval
    final headW  = w * 0.64;
    final headH  = h * 0.30;

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(headCx, headCy),
        width:  headW,
        height: headH,
      ),
      math.pi,  // start at left edge of oval
      -math.pi, // sweep CCW through top → upper dome shape
      false,
      paint,
    );

    // Thin rectangle seals the gap between dome bottom and body top
    canvas.drawRect(
      Rect.fromLTWH(headCx - headW * 0.50, headCy, headW, h * 0.09),
      paint,
    );

    // ── Antennas ───────────────────────────────────────────────────────
    final antPaint = Paint()
      ..color = const Color(0xFF3DDC84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.10
      ..strokeCap = StrokeCap.round;

    // Left antenna: from (w*0.33, h*0.30) to (w*0.18, h*0.08)
    canvas.drawLine(
      Offset(w * 0.33, h * 0.30),
      Offset(w * 0.18, h * 0.08),
      antPaint,
    );
    // Right antenna: from (w*0.67, h*0.30) to (w*0.82, h*0.08)
    canvas.drawLine(
      Offset(w * 0.67, h * 0.30),
      Offset(w * 0.82, h * 0.08),
      antPaint,
    );

    // ── Body (rounded bottom corners only) ─────────────────────────────
    final bodyTop    = h * 0.38;
    final bodyBottom = h * 0.75;
    final bodyW      = w * 0.70;

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          headCx - bodyW * 0.50,
          bodyTop,
          headCx + bodyW * 0.50,
          bodyBottom,
        ),
        bottomLeft:  Radius.circular(w * 0.08),
        bottomRight: Radius.circular(w * 0.08),
      ),
      paint,
    );

    // ── Eyes (white filled circles on the dome) ────────────────────────
    final eyePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final eyeR = w * 0.06;
    final eyeY = headCy - h * 0.04;

    canvas.drawCircle(Offset(headCx - headW * 0.22, eyeY), eyeR, eyePaint);
    canvas.drawCircle(Offset(headCx + headW * 0.22, eyeY), eyeR, eyePaint);

    // ── Arms (horizontal rounded rects, one each side of body) ─────────
    final armW = w * 0.09;
    final armH = h * 0.25;
    final armY = bodyTop + h * 0.04;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          headCx - bodyW * 0.50 - armW - w * 0.02,
          armY, armW, armH,
        ),
        Radius.circular(armW * 0.50),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          headCx + bodyW * 0.50 + w * 0.02,
          armY, armW, armH,
        ),
        Radius.circular(armW * 0.50),
      ),
      paint,
    );

    // ── Legs (vertical rounded rects at body bottom) ───────────────────
    final legW = w * 0.11;
    final legH = h * 0.18;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(headCx - bodyW * 0.30, bodyBottom, legW, legH),
        Radius.circular(legW * 0.50),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(headCx + bodyW * 0.30 - legW, bodyBottom, legW, legH),
        Radius.circular(legW * 0.50),
      ),
      paint,
    );
  }

  // ── Apple (#555555 / white when selected) ─────────────────────────────────
  //
  //  Body : Path with cubicTo strokes → Path.combine(difference, body, bite)
  //  Leaf : small oval, rotated ~−0.4 rad
  //  Stem : short stroked line

  void _paintApple(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final baseColor = selected ? Colors.white : const Color(0xFF555555);
    final fillPaint = Paint()..color = baseColor;

    // Main body
    final body = Path()
      ..moveTo(w * 0.50, h * 0.22)
      ..cubicTo(w * 0.12, h * 0.22,  0,         h * 0.40,  0,         h * 0.62)
      ..cubicTo(0,         h * 0.86,  w * 0.22,  h,         w * 0.50,  h)
      ..cubicTo(w * 0.78,  h,         w,          h * 0.86,  w,         h * 0.62)
      ..cubicTo(w,          h * 0.40,  w * 0.88,  h * 0.22,  w * 0.50,  h * 0.22)
      ..close();

    // Bite (oval subtracted from upper-right)
    final bite = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(w * 0.76, h * 0.21),
        width:  w * 0.36,
        height: h * 0.26,
      ));

    // Apple = body − bite
    canvas.drawPath(
      Path.combine(PathOperation.difference, body, bite),
      fillPaint,
    );

    // Leaf — small oval rotated slightly counterclockwise
    canvas.save();
    canvas.translate(w * 0.56, h * 0.10);
    canvas.rotate(-0.40);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.20, height: h * 0.12),
      fillPaint,
    );
    canvas.restore();

    // Stem — thin stroked line from body top to leaf
    canvas.drawLine(
      Offset(w * 0.52, h * 0.22),
      Offset(w * 0.55, h * 0.13),
      Paint()
        ..color = baseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── Flutter (3 layered chevron paths) ────────────────────────────────────

  void _paintFlutter(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Upper chevron — light blue #54C5F8 ─────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(0,         h * 0.32)
        ..lineTo(w * 0.30,  0)
        ..lineTo(w,         0)
        ..lineTo(w,         h * 0.44)
        ..lineTo(w * 0.30,  h * 0.44)
        ..close(),
      Paint()..color = const Color(0xFF54C5F8),
    );

    // ── Diagonal connector / shadow — #1565C0 @ 50 % alpha ────────────
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.30,  h * 0.44)
        ..lineTo(w,         h * 0.44)
        ..lineTo(w * 0.68,  h * 0.52)
        ..lineTo(w * 0.30,  h * 0.52)
        ..close(),
      Paint()..color = const Color(0xFF1565C0).withValues(alpha: 0.50),
    );

    // ── Lower chevron — dark blue #0175C2 ─────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(0,         h * 0.60)
        ..lineTo(w * 0.30,  h * 0.52)
        ..lineTo(w,         h * 0.52)
        ..lineTo(w,         h)
        ..lineTo(w * 0.30,  h)
        ..close(),
      Paint()..color = const Color(0xFF0175C2),
    );
  }

  // ── HarmonyOS (5-segment colour ring + white centre dot) ─────────────────

  void _paintHarmonyOS(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r       = math.min(w, h) * 0.42;
    final strokeW = math.min(w, h) * 0.28;

    // Red → orange → yellow gradient colours for each arc segment
    const arcColors = <Color>[
      Color(0xFFCF1322),
      Color(0xFFE83A14),
      Color(0xFFFF6B00),
      Color(0xFFFF9500),
      Color(0xFFFFBF00),
    ];

    const gapRad  = 0.06; // radians of gap between segments
    const arcSpan = (math.pi * 2 - 5 * gapRad) / 5;
    var startAngle = -math.pi / 2; // begin at 12 o'clock

    for (int i = 0; i < 5; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle,
        arcSpan,
        false,
        Paint()
          ..color = arcColors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.butt,
      );
      startAngle += arcSpan + gapRad;
    }

    // Small white dot at centre
    canvas.drawCircle(
      Offset(cx, cy),
      w * 0.08,
      Paint()..color = Colors.white,
    );
  }

  // ── WeChat (dual bubble + eyes) ───────────────────────────────────────────

  void _paintWeChat(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Large bubble — centred left-of-centre, lower half
    final bigCx = w * 0.38;
    final bigCy = h * 0.44;
    final bigRx = w * 0.33;
    final bigRy = h * 0.33;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bigCx, bigCy),
        width:  bigRx * 2,
        height: bigRy * 2,
      ),
      Paint()..color = const Color(0xFF07C160),
    );

    // Large bubble tail — filled triangle pointing lower-left
    canvas.drawPath(
      Path()
        ..moveTo(bigCx - bigRx * 0.30, bigCy + bigRy * 0.85)
        ..lineTo(bigCx - bigRx * 0.85, bigCy + bigRy * 1.28)
        ..lineTo(bigCx - bigRx * 0.05, bigCy + bigRy * 0.95)
        ..close(),
      Paint()..color = const Color(0xFF07C160),
    );

    // Small bubble — upper-right, slightly more transparent for depth
    final smallCx = w * 0.67;
    final smallCy = h * 0.34;
    final smallRx = w * 0.22;
    final smallRy = h * 0.22;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(smallCx, smallCy),
        width:  smallRx * 2,
        height: smallRy * 2,
      ),
      Paint()..color = const Color(0xFF07C160).withValues(alpha: 0.85),
    );

    // White dot eyes
    final eyeR    = math.min(w, h) * 0.052;
    final eyePaint = Paint()..color = Colors.white;

    // Large bubble — two eyes at (cx_large ± bigRx*0.28, cy_large)
    canvas.drawCircle(Offset(bigCx - bigRx * 0.28, bigCy), eyeR, eyePaint);
    canvas.drawCircle(Offset(bigCx + bigRx * 0.28, bigCy), eyeR, eyePaint);

    // Small bubble — single eye at its centre
    canvas.drawCircle(Offset(smallCx, smallCy), eyeR, eyePaint);
  }

  // ── Dart (split hexagon teal/blue + white D highlight) ───────────────────

  void _paintDart(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Standard Dart hexagon
    final hex = Path()
      ..moveTo(w * 0.50, 0)
      ..lineTo(w * 0.88, h * 0.20)
      ..lineTo(w,         h * 0.50)
      ..lineTo(w * 0.88, h * 0.80)
      ..lineTo(w * 0.50, h)
      ..lineTo(w * 0.12, h * 0.80)
      ..lineTo(0,         h * 0.50)
      ..lineTo(w * 0.12, h * 0.20)
      ..close();

    // Upper half — teal #00B4AB
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h * 0.50));
    canvas.drawPath(hex, Paint()..color = const Color(0xFF00B4AB));
    canvas.restore();

    // Lower half — blue #0175C2
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, h * 0.50, w, h * 0.50));
    canvas.drawPath(hex, Paint()..color = const Color(0xFF0175C2));
    canvas.restore();

    // White "D" inner highlight (filled path on top of both halves)
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.28, h * 0.22)
        ..lineTo(w * 0.28, h * 0.78)
        ..cubicTo(
            w * 0.65, h * 0.78,
            w * 0.82, h * 0.65,
            w * 0.82, h * 0.50)
        ..cubicTo(
            w * 0.82, h * 0.35,
            w * 0.65, h * 0.22,
            w * 0.28, h * 0.22)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  // ── Kotlin (purple→red gradient rounded-rect + white K) ──────────────────

  void _paintKotlin(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // Gradient background: #7F52FF (top-left) → #E44857 (bottom-right)
    final gradPaint = Paint()
      ..shader = const LinearGradient(
        begin:  Alignment.topLeft,
        end:    Alignment.bottomRight,
        colors: [Color(0xFF7F52FF), Color(0xFFE44857)],
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.15)),
      gradPaint,
    );

    // White K letter components
    final kPaint = Paint()..color = Colors.white;

    // Left vertical bar of K
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.12, w * 0.17, h * 0.76),
        Radius.circular(w * 0.04),
      ),
      kPaint,
    );

    // Upper-right diagonal arm of K
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.35, h * 0.47)
        ..lineTo(w * 0.80, h * 0.12)
        ..lineTo(w * 0.97, h * 0.12)
        ..lineTo(w * 0.52, h * 0.51)
        ..close(),
      kPaint,
    );

    // Lower-right diagonal arm of K
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.35, h * 0.55)
        ..lineTo(w * 0.97, h * 0.88)
        ..lineTo(w * 0.80, h * 0.88)
        ..lineTo(w * 0.52, h * 0.53)
        ..close(),
      kPaint,
    );
  }

  // ── Swift (#F05138 rounded-rect + white bird silhouette) ─────────────────

  void _paintSwift(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Orange-red background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(w * 0.20),
      ),
      Paint()..color = const Color(0xFFF05138),
    );

    // White Swift bird path (filled)
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.82, h * 0.32)
        ..cubicTo(
            w * 0.82, h * 0.10,
            w * 0.58, h * 0.04,
            w * 0.34, h * 0.16)
        ..cubicTo(
            w * 0.10, h * 0.28,
            w * 0.04, h * 0.48,
            w * 0.10, h * 0.58)
        ..cubicTo(
            w * 0.16, h * 0.68,
            w * 0.30, h * 0.76,
            w * 0.30, h * 0.84)
        ..cubicTo(
            w * 0.30, h * 0.94,
            w * 0.44, h * 0.98,
            w * 0.54, h * 0.88)
        ..cubicTo(
            w * 0.42, h * 0.78,
            w * 0.36, h * 0.66,
            w * 0.42, h * 0.56)
        ..cubicTo(
            w * 0.56, h * 0.62,
            w * 0.72, h * 0.56,
            w * 0.82, h * 0.42)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  // ── UniApp (#2B9939 rounded-rect + white U stroke) ───────────────────────

  void _paintUniApp(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Green background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(w * 0.20),
      ),
      Paint()..color = const Color(0xFF2B9939),
    );

    // White "U": two verticals joined by a bottom arc
    final uPath = Path()
      ..moveTo(w * 0.28, h * 0.18)
      ..lineTo(w * 0.28, h * 0.65)
      ..arcToPoint(
        Offset(w * 0.72, h * 0.65),
        radius: Radius.circular(w * 0.22),
        clockwise: true,
      )
      ..lineTo(w * 0.72, h * 0.18);

    canvas.drawPath(
      uPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // ── MAUI (deep-purple disc + 4 coloured dots at diamond positions) ────────

  void _paintMAUI(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final bgR = math.min(w, h) * 0.44;

    // Deep-purple background circle
    canvas.drawCircle(
      Offset(cx, cy),
      bgR,
      Paint()..color = const Color(0xFF3B0086),
    );

    // 4 coloured satellite dots (diamond / compass layout)
    final dotOffset = bgR * 0.56;
    final dotR      = bgR * 0.26;

    const dotColors = <Color>[
      Color(0xFF2585D9), // top    – blue
      Color(0xFF8B5CF6), // right  – purple
      Color(0xFFF97316), // bottom – orange
      Color(0xFFEC4899), // left   – pink
    ];
    final dotPositions = <Offset>[
      Offset(cx,             cy - dotOffset), // top
      Offset(cx + dotOffset, cy),              // right
      Offset(cx,             cy + dotOffset), // bottom
      Offset(cx - dotOffset, cy),              // left
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawCircle(
        dotPositions[i],
        dotR,
        Paint()..color = dotColors[i],
      );
    }
  }

  // ── Cordova (#4D9FF0 hexagon + white C arc) ───────────────────────────────
  //
  //  C arc: start π/4 (45°, lower-right), sweep +3π/2 CW (270°).
  //  The arc ends at 315° (upper-right).
  //  The 90° gap runs from 315° → 45° through 0° (right side) → C faces right.

  void _paintCordova(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r  = math.min(w, h) * 0.46;

    // Blue hexagon background (flat-top: first vertex at π/6 = 30°)
    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? hexPath.moveTo(x, y) : hexPath.lineTo(x, y);
    }
    hexPath.close();
    canvas.drawPath(hexPath, Paint()..color = const Color(0xFF4D9FF0));

    // White "C" arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.55),
      math.pi / 4,      // start at 45° (lower-right screen direction)
      3 * math.pi / 2,  // sweep 270° clockwise → gap on right = "C" opening
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.20
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── React Native (3 rotated atom ellipses + nucleus dot) ─────────────────

  void _paintReactNative(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    final ellipsePaint = Paint()
      ..color = const Color(0xFF61DAFB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07;

    // Three ellipses rotated 0°, 60°, 120° (atom orbital pattern)
    for (int i = 0; i < 3; i++) {
      final angle = i * math.pi / 3; // 0°, 60°, 120°
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      canvas.translate(-cx, -cy);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width:  w * 0.96,
          height: h * 0.36,
        ),
        ellipsePaint,
      );
      canvas.restore();
    }

    // Nucleus — filled centre circle
    canvas.drawCircle(
      Offset(cx, cy),
      math.min(w, h) * 0.11,
      Paint()..color = const Color(0xFF61DAFB),
    );
  }

  // ── Python (blue #306998 upper + yellow #FFD43B lower) ──────────────────────

  void _paintPython(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Upper half — blue snake head + body
    final blueSnake = Path()
      ..moveTo(cx, 0)
      ..cubicTo(w * 0.76, 0, w * 0.76, h * 0.16, w * 0.76, h * 0.24)
      ..lineTo(w * 0.76, cy * 0.80)
      ..lineTo(cx, cy * 0.80)
      ..cubicTo(w * 0.30, cy * 0.80, w * 0.24, cy, w * 0.24, cy)
      ..lineTo(w * 0.24, h * 0.24)
      ..cubicTo(w * 0.24, h * 0.16, w * 0.24, 0, cx, 0)
      ..close();

    canvas.drawPath(blueSnake, Paint()..color = const Color(0xFF306998));

    // Lower half — yellow snake body + head
    final yellowSnake = Path()
      ..moveTo(cx, h)
      ..cubicTo(w * 0.24, h, w * 0.24, h * 0.84, w * 0.24, h * 0.76)
      ..lineTo(w * 0.24, cy * 1.20)
      ..lineTo(cx, cy * 1.20)
      ..cubicTo(w * 0.70, cy * 1.20, w * 0.76, cy, w * 0.76, cy)
      ..lineTo(w * 0.76, h * 0.76)
      ..cubicTo(w * 0.76, h * 0.84, w * 0.76, h, cx, h)
      ..close();

    canvas.drawPath(yellowSnake, Paint()..color = const Color(0xFFFFD43B));

    // Eyes — white dots
    final eyeR = w * 0.06;
    final eyePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - w * 0.10, h * 0.14), eyeR, eyePaint);
    canvas.drawCircle(Offset(cx + w * 0.10, h * 0.86), eyeR, eyePaint);
  }

  // ── Java (#E76F00 orange + #5382A1 blue coffee cup) ─────────────────────────

  void _paintJava(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Cup body (trapezoid + rounded bottom)
    final cupPath = Path()
      ..moveTo(w * 0.22, h * 0.32)
      ..lineTo(w * 0.70, h * 0.32)
      ..lineTo(w * 0.66, h * 0.74)
      ..cubicTo(w * 0.66, h * 0.82, w * 0.26, h * 0.82, w * 0.26, h * 0.74)
      ..close();
    canvas.drawPath(cupPath, Paint()..color = const Color(0xFFE76F00));

    // Cup handle — right side arc
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.70, h * 0.52),
        width: w * 0.24, height: h * 0.24,
      ),
      -math.pi / 2, math.pi, false,
      Paint()
        ..color = const Color(0xFF5382A1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.08
        ..strokeCap = StrokeCap.round,
    );

    // Saucer
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.82, w * 0.64, h * 0.06),
        Radius.circular(h * 0.03),
      ),
      Paint()..color = const Color(0xFF5382A1),
    );

    // Steam — 3 wavy strokes
    final steamPaint = Paint()
      ..color = const Color(0xFFE76F00).withValues(alpha: 0.60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final sx = cx - w * 0.12 + i * w * 0.12;
      final steam = Path()
        ..moveTo(sx, h * 0.28)
        ..cubicTo(sx - w * 0.06, h * 0.18, sx + w * 0.06, h * 0.10, sx, h * 0.02);
      canvas.drawPath(steam, steamPaint);
    }
  }

  // ── TypeScript (#3178C6 blue square + white TS) ─────────────────────────────

  void _paintTypeScript(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Blue rounded-rect background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(w * 0.15),
      ),
      Paint()..color = const Color(0xFF3178C6),
    );

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // "T" letter — left side
    // Horizontal bar
    canvas.drawLine(
      Offset(w * 0.08, h * 0.30),
      Offset(w * 0.48, h * 0.30),
      strokePaint,
    );
    // Vertical bar
    canvas.drawLine(
      Offset(w * 0.28, h * 0.30),
      Offset(w * 0.28, h * 0.78),
      strokePaint,
    );

    // "S" letter — right side (simplified S curve)
    final sPath = Path()
      ..moveTo(w * 0.80, h * 0.34)
      ..cubicTo(w * 0.80, h * 0.26, w * 0.54, h * 0.26, w * 0.54, h * 0.38)
      ..cubicTo(w * 0.54, h * 0.50, w * 0.80, h * 0.50, w * 0.80, h * 0.62)
      ..cubicTo(w * 0.80, h * 0.76, w * 0.54, h * 0.76, w * 0.54, h * 0.68);
    canvas.drawPath(sPath, strokePaint);
  }

  // ── Docker (#2496ED blue whale + containers) ────────────────────────────────

  void _paintDocker(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final whalePaint = Paint()..color = const Color(0xFF2496ED);

    // Whale body — ellipse
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + w * 0.04, h * 0.60),
        width: w * 0.66, height: h * 0.34,
      ),
      whalePaint,
    );

    // Tail
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.12, h * 0.58)
        ..cubicTo(w * 0.06, h * 0.40, w * 0.02, h * 0.30, w * 0.10, h * 0.28)
        ..cubicTo(w * 0.18, h * 0.26, w * 0.22, h * 0.38, w * 0.22, h * 0.52)
        ..close(),
      whalePaint,
    );

    // Containers on deck (5 small squares)
    final boxW = w * 0.10;
    final boxH = h * 0.08;
    final bPaint = Paint()..color = const Color(0xFF2496ED);
    for (int i = 0; i < 5; i++) {
      final bx = cx - w * 0.22 + i * (boxW + w * 0.02);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, h * 0.36, boxW, boxH),
          Radius.circular(w * 0.01),
        ),
        bPaint,
      );
    }
    // Row 2 (3 containers)
    for (int i = 0; i < 3; i++) {
      final bx = cx - w * 0.14 + i * (boxW + w * 0.02);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, h * 0.26, boxW, boxH),
          Radius.circular(w * 0.01),
        ),
        bPaint,
      );
    }

    // Water waves
    final wavePaint = Paint()
      ..color = const Color(0xFF2496ED).withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.025
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final wy = h * 0.82 + i * h * 0.06;
      final wave = Path()..moveTo(w * 0.02, wy);
      for (double x = 0; x < w; x += w * 0.12) {
        wave.cubicTo(
          x + w * 0.03, wy - h * 0.02,
          x + w * 0.09, wy + h * 0.02,
          x + w * 0.12, wy,
        );
      }
      canvas.drawPath(wave, wavePaint);
    }
  }

  // ── GitHub (#24292E dark / white when selected — Octocat silhouette) ────────

  void _paintGitHub(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final baseColor = selected ? Colors.white : const Color(0xFF24292E);
    final paint = Paint()..color = baseColor;

    // Head circle
    final headR = w * 0.36;
    final headCy = h * 0.36;
    canvas.drawCircle(Offset(cx, headCy), headR, paint);

    // Ears (pointed triangles at top)
    canvas.drawPath(
      Path()
        ..moveTo(cx - headR * 0.68, headCy - headR * 0.60)
        ..lineTo(cx - headR * 0.96, headCy - headR * 1.28)
        ..lineTo(cx - headR * 0.18, headCy - headR * 0.86)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx + headR * 0.68, headCy - headR * 0.60)
        ..lineTo(cx + headR * 0.96, headCy - headR * 1.28)
        ..lineTo(cx + headR * 0.18, headCy - headR * 0.86)
        ..close(),
      paint,
    );

    // Body (lower ellipse)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.76),
        width: w * 0.52, height: h * 0.36,
      ),
      paint,
    );

    // Eyes — small filled circles (inverted colour)
    final eyeColor = selected ? const Color(0xFF24292E) : Colors.white;
    final eyeR = w * 0.06;
    canvas.drawCircle(
      Offset(cx - headR * 0.30, headCy - headR * 0.06),
      eyeR,
      Paint()..color = eyeColor,
    );
    canvas.drawCircle(
      Offset(cx + headR * 0.30, headCy - headR * 0.06),
      eyeR,
      Paint()..color = eyeColor,
    );
  }

  // ── VS Code (#007ACC blue — shield with code bracket) ──────────────────────

  void _paintVSCode(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shield shape — right trapezoid
    final shield = Path()
      ..moveTo(w * 0.30, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.30, h)
      ..lineTo(0, h * 0.76)
      ..lineTo(0, h * 0.24)
      ..close();
    canvas.drawPath(shield, Paint()..color = const Color(0xFF007ACC));

    // White "<" bracket
    final bracketPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(w * 0.62, h * 0.20)
        ..lineTo(w * 0.28, h * 0.50)
        ..lineTo(w * 0.62, h * 0.80),
      bracketPaint,
    );
  }

  // ── Go (#00ADD8 cyan — cute gopher face) ───────────────────────────────────

  void _paintGolang(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final goPaint = Paint()..color = const Color(0xFF00ADD8);

    // Head — large circle
    final headR = w * 0.34;
    final headCy = h * 0.38;
    canvas.drawCircle(Offset(cx, headCy), headR, goPaint);

    // Ears — two small circles at top
    final earR = headR * 0.24;
    canvas.drawCircle(
      Offset(cx - headR * 0.68, headCy - headR * 0.68),
      earR, goPaint,
    );
    canvas.drawCircle(
      Offset(cx + headR * 0.68, headCy - headR * 0.68),
      earR, goPaint,
    );

    // Eyes — large white circles with black pupils
    final eyeR = headR * 0.30;
    final eyeY = headCy - headR * 0.10;
    final eyePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = const Color(0xFF24292E);

    canvas.drawCircle(Offset(cx - headR * 0.34, eyeY), eyeR, eyePaint);
    canvas.drawCircle(Offset(cx + headR * 0.34, eyeY), eyeR, eyePaint);
    canvas.drawCircle(Offset(cx - headR * 0.28, eyeY), eyeR * 0.50, pupilPaint);
    canvas.drawCircle(Offset(cx + headR * 0.28, eyeY), eyeR * 0.50, pupilPaint);

    // Nose — tiny dot
    canvas.drawCircle(
      Offset(cx, headCy + headR * 0.20),
      headR * 0.08,
      Paint()..color = const Color(0xFF24292E),
    );

    // Body
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.72),
        width: w * 0.48, height: h * 0.30,
      ),
      goPaint,
    );
  }

  // ── Linux (#FCC624 yellow Tux penguin) ──────────────────────────────────────

  void _paintLinux(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Body — black ellipse
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.58),
        width: w * 0.64, height: h * 0.52,
      ),
      Paint()..color = const Color(0xFF333333),
    );

    // Belly — white ellipse (inner)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.60),
        width: w * 0.36, height: h * 0.36,
      ),
      Paint()..color = Colors.white,
    );

    // Head — black circle on top
    final headR = w * 0.22;
    final headCy = h * 0.22;
    canvas.drawCircle(Offset(cx, headCy), headR, Paint()..color = const Color(0xFF333333));

    // Eyes — white with black pupils
    final eyeR = headR * 0.34;
    final eyeY = headCy - headR * 0.06;
    canvas.drawCircle(Offset(cx - headR * 0.40, eyeY), eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx + headR * 0.40, eyeY), eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx - headR * 0.36, eyeY), eyeR * 0.54, Paint()..color = const Color(0xFF333333));
    canvas.drawCircle(Offset(cx + headR * 0.36, eyeY), eyeR * 0.54, Paint()..color = const Color(0xFF333333));

    // Beak — orange triangle
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.08, headCy + headR * 0.30)
        ..lineTo(cx, headCy + headR * 0.75)
        ..lineTo(cx + w * 0.08, headCy + headR * 0.30)
        ..close(),
      Paint()..color = const Color(0xFFFCC624),
    );

    // Feet — orange ovals
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - w * 0.14, h * 0.88),
        width: w * 0.22, height: h * 0.08,
      ),
      Paint()..color = const Color(0xFFFCC624),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + w * 0.14, h * 0.88),
        width: w * 0.22, height: h * 0.08,
      ),
      Paint()..color = const Color(0xFFFCC624),
    );
  }

  // ── Avatar (个人画像 — 人物剪影 #667eea 紫蓝渐变) ───────────────────────

  void _paintAvatar(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final color = selected ? Colors.white : const Color(0xFF667eea);
    final paint = Paint()..color = color;

    // Head
    final headR = w * 0.24;
    final headCy = h * 0.28;
    canvas.drawCircle(Offset(cx, headCy), headR, paint);

    // Shoulders + body (arc shape)
    final bodyPath = Path()
      ..moveTo(w * 0.04, h * 0.95)
      ..cubicTo(w * 0.04, h * 0.58, w * 0.20, h * 0.48, cx, h * 0.48)
      ..cubicTo(w * 0.80, h * 0.48, w * 0.96, h * 0.58, w * 0.96, h * 0.95)
      ..close();
    canvas.drawPath(bodyPath, paint);
  }

  // ── Brain (知识脑图 — 粉色大脑 #FF6B9D) ────────────────────────────────

  void _paintBrain(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    final color = selected ? Colors.white : const Color(0xFFFF6B9D);
    final paint = Paint()..color = color;

    // Left hemisphere
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - w * 0.14, cy - h * 0.04),
        width: w * 0.50, height: h * 0.64,
      ),
      paint,
    );
    // Left upper bump
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - w * 0.20, cy - h * 0.22),
        width: w * 0.32, height: h * 0.28,
      ),
      paint,
    );

    // Right hemisphere
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + w * 0.14, cy - h * 0.04),
        width: w * 0.50, height: h * 0.64,
      ),
      paint,
    );
    // Right upper bump
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + w * 0.20, cy - h * 0.22),
        width: w * 0.32, height: h * 0.28,
      ),
      paint,
    );

    // Brain stem
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + h * 0.36),
        width: w * 0.16, height: h * 0.14,
      ),
      paint,
    );

    // Center line (white divider between hemispheres)
    canvas.drawLine(
      Offset(cx, cy - h * 0.36),
      Offset(cx, cy + h * 0.28),
      Paint()
        ..color = (selected ? const Color(0xFFFF6B9D) : Colors.white)
            .withValues(alpha: 0.6)
        ..strokeWidth = w * 0.04
        ..strokeCap = StrokeCap.round,
    );
  }
}
