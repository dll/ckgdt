import 'package:flutter/material.dart';

/// Editorial Tech-Noir 设计系统 — 全局 tokens
///
/// 整个应用的视觉语言：深夜墨蓝 + 米白纸感 + 琥珀强调 + 编辑级字距/分隔线。
/// 所有 noir 组件从这里读颜色与排版常量；颜色 hex 不在组件里散落。
class NoirTokens {
  NoirTokens._();

  // ── 主色板 ────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF0A0E1A);
  static const Color inkDeep = Color(0xFF050811);
  static const Color paper = Color(0xFFF7F4EE);
  static const Color accent = Color(0xFFF4B942);
  static const Color success = Color(0xFF2E7D32);
  static const Color danger = Color(0xFFB71C1C);

  static Color inkAlpha(double a) => ink.withValues(alpha: a);
  static Color paperAlpha(double a) => paper.withValues(alpha: a);

  // ── 字距 ──────────────────────────────────────────────────────────
  static const double letterCaps = 4.0;
  static const double letterTitle = -0.5;
  static const double letterSerial = 1.5;
  static const double letterBody = 0.5;
  static const double letterCapsLoose = 2.2;

  // ── 字号 ──────────────────────────────────────────────────────────
  static const double fsSerial = 10;
  static const double fsCaption = 11;
  static const double fsBody = 13;
  static const double fsTitle = 16;
  static const double fsSection = 22;
  static const double fsHero = 56;

  // ── 间距 ──────────────────────────────────────────────────────────
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 14;
  static const double spaceLg = 22;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  // ── 边框/圆角 ────────────────────────────────────────────────────
  static Color get hairline => ink.withValues(alpha: 0.10);
  static const double radius = 2.0;

  // ── 投影 ──────────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: inkDeep.withValues(alpha: 0.55),
          blurRadius: 50,
          offset: const Offset(0, 24),
        ),
      ];

  static List<BoxShadow> get smallShadow => [
        BoxShadow(
          color: inkDeep.withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  // ── 文本样式预设 ──────────────────────────────────────────────────
  static TextStyle caps({Color color = accent, double size = fsCaption}) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: letterCaps,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle serial({Color? color}) => TextStyle(
        color: color ?? accent,
        fontSize: fsSerial,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSerial,
      );

  static TextStyle section({Color color = ink}) => TextStyle(
        color: color,
        fontSize: fsSection,
        fontWeight: FontWeight.w800,
        letterSpacing: letterTitle,
        height: 1.15,
      );

  static TextStyle title({Color color = ink}) => TextStyle(
        color: color,
        fontSize: fsTitle,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      );

  static TextStyle body({Color? color}) => TextStyle(
        color: color ?? ink,
        fontSize: fsBody,
        fontWeight: FontWeight.w500,
        letterSpacing: letterBody,
        height: 1.5,
      );

  static TextStyle muted({double size = fsCaption}) => TextStyle(
        color: ink.withValues(alpha: 0.5),
        fontSize: size,
        letterSpacing: 1,
      );

  static TextStyle button({Color color = paper}) => TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 4,
      );
}
