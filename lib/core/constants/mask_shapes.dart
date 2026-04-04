import 'dart:math' as math;
import 'dart:ui';

/// 图谱蒙版形状 — 节点按Logo轮廓分布（词云蒙版效果）
enum MaskShape {
  none('默认布局', '无蒙版'),
  android('Android', '安卓机器人'),
  apple('Apple', '苹果Logo'),
  flutter('Flutter', '菱形盾牌'),
  harmonyOS('HarmonyOS', '鸿蒙Logo'),
  wechat('WeChat', '微信气泡'),
  dart('Dart', '飞镖形状');

  final String label;
  final String description;
  const MaskShape(this.label, this.description);
}

/// 蒙版形状路径生成器
class MaskShapeBuilder {
  MaskShapeBuilder._();

  /// 获取归一化路径（坐标范围 0~1），然后缩放到画布大小
  static Path getPath(MaskShape shape, double width, double height) {
    // 留 margin 让节点不贴边
    final margin = math.min(width, height) * 0.08;
    final w = width - margin * 2;
    final h = height - margin * 2;
    final ox = margin + (width - margin * 2 - w) / 2;
    final oy = margin + (height - margin * 2 - h) / 2;

    switch (shape) {
      case MaskShape.none:
        return Path()..addRect(Rect.fromLTWH(0, 0, width, height));
      case MaskShape.android:
        return _buildAndroid(ox, oy, w, h);
      case MaskShape.apple:
        return _buildApple(ox, oy, w, h);
      case MaskShape.flutter:
        return _buildFlutter(ox, oy, w, h);
      case MaskShape.harmonyOS:
        return _buildHarmonyOS(ox, oy, w, h);
      case MaskShape.wechat:
        return _buildWeChat(ox, oy, w, h);
      case MaskShape.dart:
        return _buildDart(ox, oy, w, h);
    }
  }

  /// 在蒙版内均匀采样N个点（用拒绝采样法）
  static List<Offset> samplePoints(
      MaskShape shape, double width, double height, int count) {
    if (shape == MaskShape.none) {
      // 无蒙版时随机分布
      final rng = math.Random(42);
      return List.generate(
        count,
        (_) => Offset(
          80 + rng.nextDouble() * (width - 160),
          80 + rng.nextDouble() * (height - 160),
        ),
      );
    }

    final path = getPath(shape, width, height);
    final bounds = path.getBounds();
    final rng = math.Random(42);
    final points = <Offset>[];
    int attempts = 0;
    final maxAttempts = count * 50;

    while (points.length < count && attempts < maxAttempts) {
      attempts++;
      final x = bounds.left + rng.nextDouble() * bounds.width;
      final y = bounds.top + rng.nextDouble() * bounds.height;
      final p = Offset(x, y);
      if (path.contains(p)) {
        // 检查与已有点距离足够
        bool tooClose = false;
        for (final existing in points) {
          if ((existing - p).distance < 30) {
            tooClose = true;
            break;
          }
        }
        if (!tooClose) {
          points.add(p);
        }
      }
    }

    // 如果采样不够，放宽距离约束
    if (points.length < count) {
      attempts = 0;
      while (points.length < count && attempts < maxAttempts) {
        attempts++;
        final x = bounds.left + rng.nextDouble() * bounds.width;
        final y = bounds.top + rng.nextDouble() * bounds.height;
        final p = Offset(x, y);
        if (path.contains(p)) {
          points.add(p);
        }
      }
    }

    return points;
  }

  /// 将点约束到蒙版内（找最近的蒙版内点）
  static Offset constrainToMask(
      Offset point, Path maskPath, Rect bounds) {
    if (maskPath.contains(point)) return point;

    // 将点拉回到蒙版中心方向直到进入蒙版
    final center = bounds.center;
    final dir = center - point;
    final dist = dir.distance;
    if (dist < 1) return center;

    // 二分搜索找边界点
    double lo = 0, hi = 1;
    for (int i = 0; i < 20; i++) {
      final mid = (lo + hi) / 2;
      final test = Offset(
        point.dx + dir.dx * mid,
        point.dy + dir.dy * mid,
      );
      if (maskPath.contains(test)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return Offset(
      point.dx + dir.dx * hi,
      point.dy + dir.dy * hi,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Android 机器人（简化头部+身体）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildAndroid(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 头部 — 半圆
    final headTop = oy + h * 0.1;
    final headBottom = oy + h * 0.35;
    final headR = w * 0.32;
    path.addArc(
      Rect.fromCenter(
        center: Offset(cx, headBottom),
        width: headR * 2,
        height: (headBottom - headTop) * 2,
      ),
      math.pi,
      math.pi,
    );

    // 身体 — 圆角矩形
    final bodyTop = headBottom + h * 0.03;
    final bodyBottom = oy + h * 0.75;
    final bodyW = w * 0.6;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, (bodyTop + bodyBottom) / 2),
        width: bodyW,
        height: bodyBottom - bodyTop,
      ),
      Radius.circular(w * 0.05),
    ));

    // 左臂
    final armW = w * 0.08;
    final armH = h * 0.25;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - bodyW / 2 - armW - w * 0.02, bodyTop + h * 0.03, armW, armH),
      Radius.circular(armW / 2),
    ));

    // 右臂
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + bodyW / 2 + w * 0.02, bodyTop + h * 0.03, armW, armH),
      Radius.circular(armW / 2),
    ));

    // 左腿
    final legW = w * 0.09;
    final legH = h * 0.18;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - bodyW * 0.3, bodyBottom, legW, legH),
      Radius.circular(legW / 2),
    ));

    // 右腿
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + bodyW * 0.3 - legW, bodyBottom, legW, legH),
      Radius.circular(legW / 2),
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Apple Logo（苹果形状，简化曲线版）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildApple(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 叶子
    final leafW = w * 0.12;
    final leafH = h * 0.1;
    path.addOval(Rect.fromCenter(
      center: Offset(cx + leafW * 0.3, oy + h * 0.08),
      width: leafW * 2,
      height: leafH,
    ));

    // 苹果主体 — 用两个大椭圆拼合
    final bodyTop = oy + h * 0.15;
    final bodyH = h * 0.7;
    final bodyW = w * 0.7;

    // 左半边
    path.addOval(Rect.fromCenter(
      center: Offset(cx - bodyW * 0.18, bodyTop + bodyH * 0.45),
      width: bodyW * 0.65,
      height: bodyH,
    ));

    // 右半边
    path.addOval(Rect.fromCenter(
      center: Offset(cx + bodyW * 0.18, bodyTop + bodyH * 0.45),
      width: bodyW * 0.65,
      height: bodyH,
    ));

    // 底部凹陷（反向切除效果用小椭圆模拟底部收窄）
    // 直接用 fill rule evenOdd 不太好控制，所以简化为整体苹果形状

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Flutter Logo — 菱形 + 平行四边形组合（类盾牌）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildFlutter(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;

    // 大菱形（外轮廓）
    final dw = w * 0.45;
    final dh = h * 0.45;
    path.moveTo(cx, cy - dh);      // 上
    path.lineTo(cx + dw, cy);      // 右
    path.lineTo(cx, cy + dh);      // 下
    path.lineTo(cx - dw, cy);      // 左
    path.close();

    // 右侧平行四边形（Flutter的蓝色部分）
    final pw = w * 0.22;
    final ph = h * 0.28;
    path.moveTo(cx + dw * 0.1, cy - ph);
    path.lineTo(cx + dw * 0.1 + pw, cy - ph + ph * 0.4);
    path.lineTo(cx + dw * 0.1 + pw, cy + ph * 0.4);
    path.lineTo(cx + dw * 0.1, cy);
    path.close();

    // 下方三角形延伸
    final triH = h * 0.15;
    path.moveTo(cx - dw * 0.5, cy + dh * 0.6);
    path.lineTo(cx + dw * 0.5, cy + dh * 0.6);
    path.lineTo(cx, cy + dh + triH);
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HarmonyOS — 圆环 + H字母
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildHarmonyOS(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;
    final r = math.min(w, h) * 0.42;

    // 外圆
    path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    // H字母的三个笔画（矩形）
    final hW = r * 0.2;
    final hH = r * 1.1;

    // 左竖
    path.addRect(Rect.fromCenter(
      center: Offset(cx - r * 0.35, cy),
      width: hW,
      height: hH,
    ));

    // 右竖
    path.addRect(Rect.fromCenter(
      center: Offset(cx + r * 0.35, cy),
      width: hW,
      height: hH,
    ));

    // 中横
    path.addRect(Rect.fromCenter(
      center: Offset(cx, cy),
      width: r * 0.9,
      height: hW * 0.8,
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WeChat — 双气泡
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildWeChat(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;

    // 大气泡 (左)
    final bigR = math.min(w, h) * 0.35;
    path.addOval(Rect.fromCircle(
      center: Offset(cx - bigR * 0.2, cy - bigR * 0.1),
      radius: bigR,
    ));

    // 大气泡尾巴
    final tailX = cx - bigR * 0.2 - bigR * 0.5;
    final tailY = cy + bigR * 0.6;
    path.moveTo(tailX + bigR * 0.3, tailY - bigR * 0.15);
    path.lineTo(tailX, tailY + bigR * 0.25);
    path.lineTo(tailX + bigR * 0.45, tailY);
    path.close();

    // 小气泡 (右上)
    final smallR = bigR * 0.65;
    path.addOval(Rect.fromCircle(
      center: Offset(cx + bigR * 0.5, cy - bigR * 0.15),
      radius: smallR,
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dart — 飞镖/箭头形状
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildDart(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;
    final dw = w * 0.4;
    final dh = h * 0.45;

    // 主箭头形状
    path.moveTo(cx + dw, cy);               // 右尖
    path.lineTo(cx, cy - dh);               // 上
    path.lineTo(cx - dw * 0.6, cy - dh * 0.3);  // 左上凹
    path.lineTo(cx - dw * 0.1, cy);         // 中心左
    path.lineTo(cx - dw * 0.6, cy + dh * 0.3);  // 左下凹
    path.lineTo(cx, cy + dh);               // 下
    path.close();

    // 左侧尾翼
    path.moveTo(cx - dw * 0.6, cy - dh * 0.3);
    path.lineTo(cx - dw, cy - dh * 0.6);
    path.lineTo(cx - dw * 0.8, cy);
    path.lineTo(cx - dw, cy + dh * 0.6);
    path.lineTo(cx - dw * 0.6, cy + dh * 0.3);
    path.lineTo(cx - dw * 0.1, cy);
    path.close();

    return path;
  }
}
