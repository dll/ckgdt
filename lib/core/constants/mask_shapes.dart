import 'dart:math' as math;
import 'dart:ui';

/// 图谱蒙版形状 — 节点按官方 Logo 轮廓分布（词云蒙版效果）
enum MaskShape {
  none('默认布局', '无蒙版'),
  android('Android', 'Android 机器人'),
  apple('Apple', '苹果 Logo'),
  flutter('Flutter', 'Flutter 双翼'),
  harmonyOS('HarmonyOS', '鸿蒙 同心圆环'),
  wechat('WeChat', '微信 双气泡'),
  dart('Dart', 'Dart 盾形'),
  kotlin('Kotlin', 'Kotlin K形'),
  swift('Swift', 'Swift 飞鸟'),
  uniapp('uni-app', 'uni-app U形'),
  maui('MAUI', '.NET MAUI 花瓣'),
  cordova('Cordova', 'Cordova 盾牌'),
  reactNative('React Native', 'React 原子'),
  python('Python', 'Python 双蛇'),
  java('Java', 'Java 咖啡杯'),
  typeScript('TypeScript', 'TS 方块'),
  docker('Docker', 'Docker 鲸鱼'),
  gitHub('GitHub', 'GitHub 章鱼猫'),
  vsCode('VS Code', 'VS Code 编辑器'),
  golang('Go', 'Go 地鼠'),
  linux('Linux', 'Linux 企鹅'),
  avatar('我的画像', '个人知识画像'),
  brain('知识脑图', '大脑思维图谱');

  final String label;
  final String description;
  const MaskShape(this.label, this.description);
}

/// 蒙版形状路径生成器
class MaskShapeBuilder {
  MaskShapeBuilder._();

  /// 获取归一化路径（坐标范围由画布大小决定）
  static Path getPath(MaskShape shape, double width, double height) {
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
      case MaskShape.kotlin:
        return _buildKotlin(ox, oy, w, h);
      case MaskShape.swift:
        return _buildSwift(ox, oy, w, h);
      case MaskShape.uniapp:
        return _buildUniApp(ox, oy, w, h);
      case MaskShape.maui:
        return _buildMAUI(ox, oy, w, h);
      case MaskShape.cordova:
        return _buildCordova(ox, oy, w, h);
      case MaskShape.reactNative:
        return _buildReactNative(ox, oy, w, h);
      case MaskShape.python:
        return _buildPython(ox, oy, w, h);
      case MaskShape.java:
        return _buildJava(ox, oy, w, h);
      case MaskShape.typeScript:
        return _buildTypeScript(ox, oy, w, h);
      case MaskShape.docker:
        return _buildDocker(ox, oy, w, h);
      case MaskShape.gitHub:
        return _buildGitHub(ox, oy, w, h);
      case MaskShape.vsCode:
        return _buildVSCode(ox, oy, w, h);
      case MaskShape.golang:
        return _buildGolang(ox, oy, w, h);
      case MaskShape.linux:
        return _buildLinux(ox, oy, w, h);
      case MaskShape.avatar:
        return _buildAvatar(ox, oy, w, h);
      case MaskShape.brain:
        return _buildBrain(ox, oy, w, h);
    }
  }

  /// 在蒙版内均匀采样 N 个点（拒绝采样法）
  static List<Offset> samplePoints(
      MaskShape shape, double width, double height, int count) {
    if (shape == MaskShape.none) {
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
        bool tooClose = false;
        for (final existing in points) {
          if ((existing - p).distance < 30) {
            tooClose = true;
            break;
          }
        }
        if (!tooClose) points.add(p);
      }
    }

    if (points.length < count) {
      attempts = 0;
      while (points.length < count && attempts < maxAttempts) {
        attempts++;
        final x = bounds.left + rng.nextDouble() * bounds.width;
        final y = bounds.top + rng.nextDouble() * bounds.height;
        final p = Offset(x, y);
        if (path.contains(p)) points.add(p);
      }
    }

    return points;
  }

  /// 将点约束到蒙版内
  static Offset constrainToMask(
      Offset point, Path maskPath, Rect bounds) {
    if (maskPath.contains(point)) return point;
    final center = bounds.center;
    final dir = center - point;
    final dist = dir.distance;
    if (dist < 1) return center;
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
  // Android — 机器人头部 + 身体 + 四肢 + 天线
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildAndroid(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 天线（粗圆角矩形，左右各一）
    final antennaW = w * 0.07;
    final antennaH = h * 0.12;
    // 左天线（向左倾斜：矩形 + 旋转用平行四边形近似）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.30, oy, antennaW, antennaH),
      Radius.circular(antennaW / 2),
    ));
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.23, oy, antennaW, antennaH),
      Radius.circular(antennaW / 2),
    ));

    // 头部 — 半圆顶 + 矩形底（拼出完整圆角头部）
    final headCY = oy + h * 0.30;
    final headRX = w * 0.34;
    final headRY = h * 0.20;
    path.addArc(
      Rect.fromCenter(
        center: Offset(cx, headCY),
        width: headRX * 2,
        height: headRY * 2,
      ),
      math.pi,
      math.pi,
    );
    // 头部下半矩形（让头部饱满）
    path.addRect(Rect.fromLTWH(
      cx - headRX, headCY, headRX * 2, headRY * 0.6,
    ));

    // 身体
    final bodyTop = headCY + headRY * 0.6 + h * 0.02;
    final bodyBottom = oy + h * 0.76;
    final bodyW = w * 0.62;
    path.addRRect(RRect.fromRectAndCorners(
      Rect.fromCenter(
        center: Offset(cx, (bodyTop + bodyBottom) / 2),
        width: bodyW,
        height: bodyBottom - bodyTop,
      ),
      bottomLeft: Radius.circular(w * 0.06),
      bottomRight: Radius.circular(w * 0.06),
    ));

    // 左臂
    final armW = w * 0.09;
    final armH = h * 0.26;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(
          cx - bodyW / 2 - armW - w * 0.02, bodyTop + h * 0.02, armW, armH),
      Radius.circular(armW / 2),
    ));
    // 右臂
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(
          cx + bodyW / 2 + w * 0.02, bodyTop + h * 0.02, armW, armH),
      Radius.circular(armW / 2),
    ));

    // 左腿
    final legW = w * 0.10;
    final legH = h * 0.17;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - bodyW * 0.28, bodyBottom + h * 0.005, legW, legH),
      Radius.circular(legW / 2),
    ));
    // 右腿
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + bodyW * 0.18, bodyBottom + h * 0.005, legW, legH),
      Radius.circular(legW / 2),
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Apple — 苹果形状（含右上咬痕 + 叶子）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildApple(double ox, double oy, double w, double h) {
    final cx = ox + w / 2;

    // 主体：bezier 曲线拼出苹果轮廓
    final body = Path();
    body.moveTo(cx, oy + h * 0.24);
    // 左侧曲线
    body.cubicTo(
      cx - w * 0.42, oy + h * 0.20,
      ox,             oy + h * 0.40,
      ox,             oy + h * 0.62,
    );
    body.cubicTo(
      ox,             oy + h * 0.84,
      cx - w * 0.24,  oy + h,
      cx,             oy + h,
    );
    // 右侧曲线
    body.cubicTo(
      cx + w * 0.24,  oy + h,
      ox + w,         oy + h * 0.84,
      ox + w,         oy + h * 0.62,
    );
    body.cubicTo(
      ox + w,         oy + h * 0.40,
      cx + w * 0.42,  oy + h * 0.20,
      cx,             oy + h * 0.24,
    );
    body.close();

    // 咬痕（右上角椭圆）
    final bite = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(cx + w * 0.28, oy + h * 0.22),
        width:  w * 0.40,
        height: h * 0.28,
      ));

    // 差集：苹果 - 咬痕
    final apple = Path.combine(PathOperation.difference, body, bite);

    // 叶子（小椭圆，偏右上）
    final leaf = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(cx + w * 0.08, oy + h * 0.10),
        width:  w * 0.22,
        height: h * 0.12,
      ));

    // 茎（细圆角矩形）
    final stem = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, oy + h * 0.14),
          width:  w * 0.05,
          height: h * 0.12,
        ),
        Radius.circular(w * 0.025),
      ));

    return Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, apple, leaf),
      stem,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Flutter — 官方 Flutter "鸟形" 双翼（两个平行四边形）
  //   上翼（浅蓝）+ 下翼（深蓝），左侧呈倾斜边，整体像字母 F 的飞鸟轮廓
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildFlutter(double ox, double oy, double w, double h) {
    final path = Path();

    // 上翼：左侧倾斜，右侧垂直
    path.moveTo(ox,           oy + h * 0.32); // 左入口
    path.lineTo(ox + w * 0.30, oy);            // 左上斜角
    path.lineTo(ox + w,        oy);            // 右上
    path.lineTo(ox + w,        oy + h * 0.44); // 右下
    path.lineTo(ox + w * 0.30, oy + h * 0.44); // 内切角
    path.close();

    // 过渡三角（两翼之间的阴影区，增加厚度感）
    path.moveTo(ox + w * 0.30, oy + h * 0.44);
    path.lineTo(ox + w,        oy + h * 0.44);
    path.lineTo(ox + w * 0.68, oy + h * 0.52);
    path.lineTo(ox + w * 0.30, oy + h * 0.52);
    path.close();

    // 下翼：与上翼平行，略小
    path.moveTo(ox,            oy + h * 0.60); // 左入口
    path.lineTo(ox + w * 0.30, oy + h * 0.52); // 左上斜角
    path.lineTo(ox + w,        oy + h * 0.52); // 右上
    path.lineTo(ox + w,        oy + h);        // 右下
    path.lineTo(ox + w * 0.30, oy + h);        // 内切角
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HarmonyOS — 同心圆环（鸿蒙标志性圆环设计）+ 三花瓣
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildHarmonyOS(double ox, double oy, double w, double h) {
    final path = Path()..fillType = PathFillType.evenOdd;
    final cx = ox + w / 2;
    final cy = oy + h / 2;
    final outerR = math.min(w, h) * 0.44;
    final innerR = outerR * 0.52; // 圆环厚度约 48%

    // 外圆
    path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outerR));
    // 内圆（挖空 → 形成圆环）
    path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: innerR));

    // 三个花瓣小圆（均布在圆环外沿，增加辨识度）
    // 花瓣用 evenOdd：位于外圆外 → 为填充区域
    final petalR = outerR * 0.14;
    for (int i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 3;
      final px = cx + (outerR + petalR * 0.6) * math.cos(angle);
      final py = cy + (outerR + petalR * 0.6) * math.sin(angle);
      path.addOval(
          Rect.fromCircle(center: Offset(px, py), radius: petalR));
    }

    // 中心小圆（作为圆心标记）
    path.addOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: innerR * 0.28));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WeChat — 大小双气泡（正宗微信图标形态）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildWeChat(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;

    // 大气泡（偏左下）
    final bigR = math.min(w, h) * 0.34;
    final bigCX = cx - bigR * 0.18;
    final bigCY = cy + bigR * 0.05;
    path.addOval(Rect.fromCircle(center: Offset(bigCX, bigCY), radius: bigR));

    // 大气泡尾巴
    path.moveTo(bigCX - bigR * 0.15, bigCY + bigR * 0.72);
    path.lineTo(bigCX - bigR * 0.65, bigCY + bigR * 1.20);
    path.lineTo(bigCX + bigR * 0.35, bigCY + bigR * 0.85);
    path.close();

    // 小气泡（偏右上）
    final smallR = bigR * 0.64;
    final smallCX = cx + bigR * 0.52;
    final smallCY = cy - bigR * 0.22;
    path.addOval(
        Rect.fromCircle(center: Offset(smallCX, smallCY), radius: smallR));

    // 小气泡尾巴
    path.moveTo(smallCX + smallR * 0.20, smallCY + smallR * 0.78);
    path.lineTo(smallCX + smallR * 0.62, smallCY + smallR * 1.20);
    path.lineTo(smallCX - smallR * 0.20, smallCY + smallR * 0.88);
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dart — 八角盾形（Dart 语言标志性盾牌轮廓）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildDart(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    path.moveTo(cx,           oy);               // 顶
    path.lineTo(ox + w * 0.85, oy + h * 0.18);  // 右上斜
    path.lineTo(ox + w,        oy + h * 0.50);  // 右
    path.lineTo(ox + w * 0.85, oy + h * 0.82);  // 右下斜
    path.lineTo(cx,            oy + h);          // 底
    path.lineTo(ox + w * 0.15, oy + h * 0.82);  // 左下斜
    path.lineTo(ox,            oy + h * 0.50);  // 左
    path.lineTo(ox + w * 0.15, oy + h * 0.18);  // 左上斜
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Kotlin — 字母 K（垂直竖条 + 上下两斜翼）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildKotlin(double ox, double oy, double w, double h) {
    final path = Path();
    final barW = w * 0.22;

    // 左竖条
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox, oy, barW, h),
      Radius.circular(barW * 0.3),
    ));

    // 上斜翼：竖条顶部 → 右上角 → 右上1/4 → 回到竖条中线
    path.moveTo(ox + barW,         oy + h * 0.50);
    path.lineTo(ox + barW * 1.2,   oy + h * 0.50);
    path.lineTo(ox + w,            oy);
    path.lineTo(ox + w,            oy + h * 0.22);
    path.lineTo(ox + barW * 1.5,   oy + h * 0.50);
    path.close();

    // 下斜翼：竖条中线 → 右下1/4 → 右下角 → 回
    path.moveTo(ox + barW,         oy + h * 0.50);
    path.lineTo(ox + barW * 1.5,   oy + h * 0.50);
    path.lineTo(ox + w,            oy + h * 0.78);
    path.lineTo(ox + w,            oy + h);
    path.lineTo(ox + barW * 1.2,   oy + h * 0.50);
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Swift — Swift 飞鸟（仿官方 Swift Logo 中的鸟形曲线轮廓）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildSwift(double ox, double oy, double w, double h) {
    final path = Path();

    // 鸟形曲线：顺时针描述整体轮廓
    path.moveTo(ox + w * 0.82, oy + h * 0.32);
    // 顶部弧（鸟背）
    path.cubicTo(
      ox + w * 0.82, oy + h * 0.08,
      ox + w * 0.58, oy + h * 0.02,
      ox + w * 0.32, oy + h * 0.14,
    );
    // 左侧弧（翅膀根部到腹部）
    path.cubicTo(
      ox + w * 0.08, oy + h * 0.26,
      ox + w * 0.02, oy + h * 0.46,
      ox + w * 0.08, oy + h * 0.56,
    );
    // 腹部弧（向右下）
    path.cubicTo(
      ox + w * 0.14, oy + h * 0.66,
      ox + w * 0.28, oy + h * 0.74,
      ox + w * 0.28, oy + h * 0.84,
    );
    // 尾部弧（尾巴尖）
    path.cubicTo(
      ox + w * 0.28, oy + h * 0.95,
      ox + w * 0.44, oy + h * 0.99,
      ox + w * 0.54, oy + h * 0.88,
    );
    // 内翻（鸟腹内侧到翅膀）
    path.cubicTo(
      ox + w * 0.42, oy + h * 0.78,
      ox + w * 0.36, oy + h * 0.65,
      ox + w * 0.42, oy + h * 0.54,
    );
    // 右翼（回到起点）
    path.cubicTo(
      ox + w * 0.56, oy + h * 0.60,
      ox + w * 0.72, oy + h * 0.54,
      ox + w * 0.82, oy + h * 0.40,
    );
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UniApp — 字母 U（拱形，两竖 + 半圆底）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildUniApp(double ox, double oy, double w, double h) {
    final path = Path();
    final armW = w * 0.22;

    // 左竖臂
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox + w * 0.10, oy, armW, h * 0.65),
      Radius.circular(armW * 0.4),
    ));
    // 右竖臂
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox + w * 0.68, oy, armW, h * 0.65),
      Radius.circular(armW * 0.4),
    ));

    // U 形底半圆（弧长连接两臂）
    // 用大椭圆的下半部分填充（arcTo 方式）
    final arcRect = Rect.fromLTWH(ox + w * 0.10, oy + h * 0.30, w * 0.80, h * 0.65);
    path.moveTo(ox + w * 0.10, oy + h * 0.65);
    path.arcTo(arcRect, math.pi, math.pi, false);
    path.lineTo(ox + w * 0.90, oy + h * 0.65);
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAUI — 四花瓣菱形（.NET MAUI 多平台感）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildMAUI(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;
    final petalW = w * 0.52;
    final petalH = h * 0.72;
    final offset = math.min(w, h) * 0.22;

    // 四个椭圆花瓣（上下左右）
    path.addOval(Rect.fromCenter(
      center: Offset(cx, cy - offset),
      width: petalW,
      height: petalH,
    ));
    path.addOval(Rect.fromCenter(
      center: Offset(cx, cy + offset),
      width: petalW,
      height: petalH,
    ));
    path.addOval(Rect.fromCenter(
      center: Offset(cx - offset, cy),
      width: petalH,
      height: petalW,
    ));
    path.addOval(Rect.fromCenter(
      center: Offset(cx + offset, cy),
      width: petalH,
      height: petalW,
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cordova — 五边形盾牌（Apache Cordova 盾牌 Logo 形态）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildCordova(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    path.moveTo(cx,           oy);               // 顶
    path.lineTo(ox + w,       oy + h * 0.38);    // 右上
    path.lineTo(ox + w * 0.82, oy + h);          // 右下
    path.lineTo(ox + w * 0.18, oy + h);          // 左下
    path.lineTo(ox,           oy + h * 0.38);    // 左上
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // React Native — 三轨道椭圆（原子模型）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildReactNative(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;
    final rx = w * 0.46; // 轨道长半轴
    final ry = h * 0.18; // 轨道短半轴
    const pts = 48;      // 多边形精度

    // 三条轨道，旋转角度分别为 0°、60°、120°
    for (int orbit = 0; orbit < 3; orbit++) {
      final rot = orbit * math.pi / 3;
      for (int i = 0; i <= pts; i++) {
        final t = i * 2 * math.pi / pts;
        final lx = rx * math.cos(t);
        final ly = ry * math.sin(t);
        // 旋转
        final rx2 = lx * math.cos(rot) - ly * math.sin(rot);
        final ry2 = lx * math.sin(rot) + ly * math.cos(rot);
        if (i == 0) {
          path.moveTo(cx + rx2, cy + ry2);
        } else {
          path.lineTo(cx + rx2, cy + ry2);
        }
      }
      path.close();
    }

    // 中心核（圆点）
    path.addOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: math.min(w, h) * 0.10));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Python — 双蛇交缠（两个蛇头 + S 形身体）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildPython(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;

    // 上蛇（蓝色蛇）— 占据上半部分
    // 蛇头（圆角矩形）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.30, oy, w * 0.60, h * 0.18),
      Radius.circular(w * 0.09),
    ));
    // 蛇身左半（从头往下弯到中线）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox + w * 0.10, oy + h * 0.10, w * 0.24, h * 0.44),
      Radius.circular(w * 0.08),
    ));
    // 蛇身横中段（中线）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox + w * 0.10, cy - h * 0.06, w * 0.80, h * 0.12),
      Radius.circular(w * 0.06),
    ));

    // 下蛇（黄色蛇）— 占据下半部分
    // 蛇头
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.30, oy + h * 0.82, w * 0.60, h * 0.18),
      Radius.circular(w * 0.09),
    ));
    // 蛇身右半
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox + w * 0.66, oy + h * 0.46, w * 0.24, h * 0.44),
      Radius.circular(w * 0.08),
    ));

    // 眼睛位置的小圆（蒙版装饰）
    path.addOval(Rect.fromCircle(
      center: Offset(cx - w * 0.10, oy + h * 0.09),
      radius: w * 0.04,
    ));
    path.addOval(Rect.fromCircle(
      center: Offset(cx + w * 0.10, oy + h * 0.91),
      radius: w * 0.04,
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Java — 咖啡杯（杯身 + 杯把 + 蒸汽）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildJava(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 杯身（上窄下宽的梯形，用圆角矩形近似）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(
        ox + w * 0.14, oy + h * 0.32,
        w * 0.54, h * 0.50,
      ),
      Radius.circular(w * 0.06),
    ));

    // 杯把（右侧半圆环）— 用大小两圆差集
    final handleOuter = Path()..addOval(Rect.fromCenter(
      center: Offset(ox + w * 0.68, oy + h * 0.52),
      width: w * 0.28, height: h * 0.30,
    ));
    final handleInner = Path()..addOval(Rect.fromCenter(
      center: Offset(ox + w * 0.68, oy + h * 0.52),
      width: w * 0.14, height: h * 0.16,
    ));
    final handle = Path.combine(PathOperation.difference, handleOuter, handleInner);
    // 只保留右半部分
    final rightClip = Path()..addRect(
      Rect.fromLTWH(ox + w * 0.68, oy + h * 0.35, w * 0.30, h * 0.34),
    );
    path.addPath(
      Path.combine(PathOperation.intersect, handle, rightClip),
      Offset.zero,
    );

    // 杯底盘
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox + w * 0.08, oy + h * 0.82, w * 0.66, h * 0.08),
      Radius.circular(w * 0.04),
    ));

    // 蒸汽（三条波浪弧线用圆角矩形近似）
    for (int i = 0; i < 3; i++) {
      final sx = cx - w * 0.12 + i * w * 0.12;
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(sx, oy + h * 0.06, w * 0.05, h * 0.20),
        Radius.circular(w * 0.025),
      ));
    }

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TypeScript — TS 圆角方块（像官方蓝色方块 + TS 字母区域）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildTypeScript(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;

    // 外部圆角方块
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(ox + w * 0.05, oy + h * 0.05, w * 0.90, h * 0.90),
      Radius.circular(w * 0.10),
    ));

    // T 字竖条（居中偏左）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.32, cy - h * 0.24, w * 0.12, h * 0.48),
      Radius.circular(w * 0.03),
    ));
    // T 字横条
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.42, cy - h * 0.28, w * 0.38, h * 0.10),
      Radius.circular(w * 0.03),
    ));

    // S 字（居中偏右，用三段矩形拼接）
    // S 上横
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.06, cy - h * 0.28, w * 0.28, h * 0.10),
      Radius.circular(w * 0.03),
    ));
    // S 中横
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.06, cy - h * 0.04, w * 0.28, h * 0.10),
      Radius.circular(w * 0.03),
    ));
    // S 下横
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.06, cy + h * 0.18, w * 0.28, h * 0.10),
      Radius.circular(w * 0.03),
    ));
    // S 左竖（上半段）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.06, cy - h * 0.28, w * 0.10, h * 0.20),
      Radius.circular(w * 0.03),
    ));
    // S 右竖（下半段）
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.24, cy + h * 0.06, w * 0.10, h * 0.22),
      Radius.circular(w * 0.03),
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Docker — 鲸鱼（身体 + 尾巴 + 集装箱方块）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildDocker(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 鲸鱼身体（椭圆形，偏右）
    path.addOval(Rect.fromCenter(
      center: Offset(cx + w * 0.06, oy + h * 0.58),
      width: w * 0.70, height: h * 0.44,
    ));

    // 鲸鱼头部（前方突出的弧）
    path.addOval(Rect.fromCenter(
      center: Offset(cx + w * 0.38, oy + h * 0.54),
      width: w * 0.22, height: h * 0.28,
    ));

    // 尾巴（左侧向上翘的三角形）
    path.moveTo(ox + w * 0.10, oy + h * 0.56);
    path.lineTo(ox, oy + h * 0.26);
    path.lineTo(ox + w * 0.18, oy + h * 0.36);
    path.lineTo(ox + w * 0.24, oy + h * 0.50);
    path.close();

    // 甲板上的集装箱（5 个小方块）
    final boxW = w * 0.10;
    final boxH = h * 0.09;
    final deckY = oy + h * 0.32;
    for (int i = 0; i < 5; i++) {
      final bx = cx - w * 0.16 + i * (boxW + w * 0.02);
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, deckY, boxW, boxH),
        Radius.circular(w * 0.015),
      ));
    }
    // 第二层集装箱（3 个）
    for (int i = 0; i < 3; i++) {
      final bx = cx - w * 0.10 + i * (boxW + w * 0.02);
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, deckY - boxH - h * 0.02, boxW, boxH),
        Radius.circular(w * 0.015),
      ));
    }

    // 水花（下方的三条波纹弧线）
    for (int i = 0; i < 3; i++) {
      final wy = oy + h * 0.84 + i * h * 0.06;
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(
          ox + w * 0.04 + i * w * 0.04,
          wy, w * 0.80 - i * w * 0.08, h * 0.03,
        ),
        Radius.circular(h * 0.015),
      ));
    }

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GitHub — 章鱼猫 Octocat（圆形头 + 触须）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildGitHub(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;
    final r = math.min(w, h) * 0.38;

    // 圆形头
    path.addOval(Rect.fromCircle(center: Offset(cx, cy - h * 0.06), radius: r));

    // 耳朵（两个三角形在头顶）
    // 左耳
    path.moveTo(cx - r * 0.70, cy - h * 0.06 - r * 0.62);
    path.lineTo(cx - r * 1.10, cy - h * 0.06 - r * 1.30);
    path.lineTo(cx - r * 0.20, cy - h * 0.06 - r * 0.88);
    path.close();
    // 右耳
    path.moveTo(cx + r * 0.70, cy - h * 0.06 - r * 0.62);
    path.lineTo(cx + r * 1.10, cy - h * 0.06 - r * 1.30);
    path.lineTo(cx + r * 0.20, cy - h * 0.06 - r * 0.88);
    path.close();

    // 身体（下半部分椭圆）
    path.addOval(Rect.fromCenter(
      center: Offset(cx, cy + h * 0.28),
      width: w * 0.50, height: h * 0.30,
    ));

    // 触须/手臂（左右各一，圆角矩形向外延伸）
    final armW = w * 0.10;
    final armH = h * 0.22;
    // 左臂
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.40, cy + h * 0.10, armW, armH),
      Radius.circular(armW / 2),
    ));
    // 右臂
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.30, cy + h * 0.10, armW, armH),
      Radius.circular(armW / 2),
    ));

    // 腿（两个短粗的圆角矩形）
    final legW = w * 0.11;
    final legH = h * 0.12;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.16, cy + h * 0.40, legW, legH),
      Radius.circular(legW / 2),
    ));
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.05, cy + h * 0.40, legW, legH),
      Radius.circular(legW / 2),
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VS Code — 编辑器图标（侧边栏 + 编辑区 + 括号）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildVSCode(double ox, double oy, double w, double h) {
    final path = Path();

    // 主体盾形（倾斜平行四边形 → 类似 VS Code 官方 logo）
    path.moveTo(ox + w * 0.26, oy);
    path.lineTo(ox + w,         oy);
    path.lineTo(ox + w,         oy + h);
    path.lineTo(ox + w * 0.26, oy + h);
    path.close();

    // 左侧三角（向左延伸）
    path.moveTo(ox + w * 0.26, oy);
    path.lineTo(ox,             oy + h * 0.24);
    path.lineTo(ox,             oy + h * 0.76);
    path.lineTo(ox + w * 0.26, oy + h);
    path.close();

    // 中间折线装饰（> 形状）
    final bracketW = w * 0.06;
    // 上半 >
    path.moveTo(ox + w * 0.22, oy + h * 0.18);
    path.lineTo(ox + w * 0.58, oy + h * 0.50);
    path.lineTo(ox + w * 0.22, oy + h * 0.82);
    path.lineTo(ox + w * 0.22 + bracketW, oy + h * 0.82);
    path.lineTo(ox + w * 0.58 + bracketW, oy + h * 0.50);
    path.lineTo(ox + w * 0.22 + bracketW, oy + h * 0.18);
    path.close();

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Go — Go 地鼠（圆头 + 身体 + 耳朵 + 大眼睛）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildGolang(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 头部（大圆）
    final headR = math.min(w, h) * 0.28;
    final headCy = oy + h * 0.28;
    path.addOval(Rect.fromCircle(
      center: Offset(cx, headCy), radius: headR,
    ));

    // 耳朵（两个小椭圆在头顶）
    final earW = w * 0.12;
    final earH = h * 0.14;
    path.addOval(Rect.fromCenter(
      center: Offset(cx - headR * 0.62, headCy - headR * 0.76),
      width: earW, height: earH,
    ));
    path.addOval(Rect.fromCenter(
      center: Offset(cx + headR * 0.62, headCy - headR * 0.76),
      width: earW, height: earH,
    ));

    // 眼睛（两个大圆）
    final eyeR = headR * 0.32;
    path.addOval(Rect.fromCircle(
      center: Offset(cx - headR * 0.36, headCy - headR * 0.10),
      radius: eyeR,
    ));
    path.addOval(Rect.fromCircle(
      center: Offset(cx + headR * 0.36, headCy - headR * 0.10),
      radius: eyeR,
    ));

    // 身体（大椭圆）
    path.addOval(Rect.fromCenter(
      center: Offset(cx, oy + h * 0.62),
      width: w * 0.56, height: h * 0.42,
    ));

    // 手臂（两侧圆角矩形）
    final armW = w * 0.10;
    final armH = h * 0.22;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.38, oy + h * 0.50, armW, armH),
      Radius.circular(armW / 2),
    ));
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.28, oy + h * 0.50, armW, armH),
      Radius.circular(armW / 2),
    ));

    // 脚（两个短圆角矩形）
    final footW = w * 0.14;
    final footH = h * 0.10;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.20, oy + h * 0.82, footW, footH),
      Radius.circular(footW * 0.4),
    ));
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + w * 0.06, oy + h * 0.82, footW, footH),
      Radius.circular(footW * 0.4),
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Linux — 企鹅 Tux（圆头 + 椭圆身体 + 翅膀 + 脚）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildLinux(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 头部（圆形）
    final headR = math.min(w, h) * 0.22;
    final headCy = oy + h * 0.20;
    path.addOval(Rect.fromCircle(
      center: Offset(cx, headCy), radius: headR,
    ));

    // 喙（小三角形在头部下方正中）
    path.moveTo(cx - w * 0.06, headCy + headR * 0.50);
    path.lineTo(cx, headCy + headR * 0.90);
    path.lineTo(cx + w * 0.06, headCy + headR * 0.50);
    path.close();

    // 身体（大椭圆，白色肚皮区域统一用椭圆）
    path.addOval(Rect.fromCenter(
      center: Offset(cx, oy + h * 0.56),
      width: w * 0.56, height: h * 0.46,
    ));

    // 翅膀（左右各一个倾斜的椭圆）
    // 左翅膀
    path.addOval(Rect.fromCenter(
      center: Offset(cx - w * 0.30, oy + h * 0.50),
      width: w * 0.16, height: h * 0.34,
    ));
    // 右翅膀
    path.addOval(Rect.fromCenter(
      center: Offset(cx + w * 0.30, oy + h * 0.50),
      width: w * 0.16, height: h * 0.34,
    ));

    // 脚（两个扁椭圆在底部）
    path.addOval(Rect.fromCenter(
      center: Offset(cx - w * 0.16, oy + h * 0.86),
      width: w * 0.22, height: h * 0.10,
    ));
    path.addOval(Rect.fromCenter(
      center: Offset(cx + w * 0.16, oy + h * 0.86),
      width: w * 0.22, height: h * 0.10,
    ));

    // 眼睛（两个小圆）
    path.addOval(Rect.fromCircle(
      center: Offset(cx - headR * 0.38, headCy - headR * 0.10),
      radius: headR * 0.22,
    ));
    path.addOval(Rect.fromCircle(
      center: Offset(cx + headR * 0.38, headCy - headR * 0.10),
      radius: headR * 0.22,
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Avatar — 人物半身剪影（头 + 肩）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildAvatar(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;

    // 头部（圆形）
    final headR = math.min(w, h) * 0.22;
    final headCy = oy + h * 0.26;
    path.addOval(Rect.fromCircle(
      center: Offset(cx, headCy), radius: headR,
    ));

    // 脖子（连接头和肩）
    path.addRect(Rect.fromLTWH(
      cx - w * 0.07, headCy + headR * 0.80,
      w * 0.14, h * 0.08,
    ));

    // 肩膀+身体（大圆弧顶 + 矩形底部）
    // 用一个宽椭圆的上半做肩膀弧线
    final shoulderTop = headCy + headR + h * 0.06;
    path.addOval(Rect.fromCenter(
      center: Offset(cx, shoulderTop + h * 0.14),
      width: w * 0.88, height: h * 0.40,
    ));

    // 身体矩形（从肩膀到底部）
    path.addRRect(RRect.fromRectAndCorners(
      Rect.fromLTWH(
        ox + w * 0.06, shoulderTop + h * 0.14,
        w * 0.88, h * 0.40,
      ),
      bottomLeft: Radius.circular(w * 0.06),
      bottomRight: Radius.circular(w * 0.06),
    ));

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Brain — 大脑轮廓（左右脑半球 + 褶皱）
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildBrain(double ox, double oy, double w, double h) {
    final path = Path();
    final cx = ox + w / 2;
    final cy = oy + h / 2;

    // 左脑半球
    path.addOval(Rect.fromCenter(
      center: Offset(cx - w * 0.16, cy - h * 0.06),
      width: w * 0.52, height: h * 0.70,
    ));
    // 左脑上部突起
    path.addOval(Rect.fromCenter(
      center: Offset(cx - w * 0.22, cy - h * 0.26),
      width: w * 0.34, height: h * 0.32,
    ));
    // 左脑下部
    path.addOval(Rect.fromCenter(
      center: Offset(cx - w * 0.20, cy + h * 0.18),
      width: w * 0.36, height: h * 0.30,
    ));

    // 右脑半球
    path.addOval(Rect.fromCenter(
      center: Offset(cx + w * 0.16, cy - h * 0.06),
      width: w * 0.52, height: h * 0.70,
    ));
    // 右脑上部突起
    path.addOval(Rect.fromCenter(
      center: Offset(cx + w * 0.22, cy - h * 0.26),
      width: w * 0.34, height: h * 0.32,
    ));
    // 右脑下部
    path.addOval(Rect.fromCenter(
      center: Offset(cx + w * 0.20, cy + h * 0.18),
      width: w * 0.36, height: h * 0.30,
    ));

    // 脑干（底部小椭圆）
    path.addOval(Rect.fromCenter(
      center: Offset(cx, cy + h * 0.40),
      width: w * 0.18, height: h * 0.16,
    ));

    return path;
  }
}
