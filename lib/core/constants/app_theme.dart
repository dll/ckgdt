import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 主题色预设数据类
// ─────────────────────────────────────────────────────────────────────────────

class AppThemePreset {
  final String name;
  final String description;
  final Color primary;
  final Color gradientEnd; // 渐变结束色（比 primary 深一档）

  const AppThemePreset({
    required this.name,
    required this.description,
    required this.primary,
    required this.gradientEnd,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 三组内置主题色
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  /// 当前版本内置主题色列表（索引 0/1/2）
  static const List<AppThemePreset> presets = [
    AppThemePreset(
      name: '科技蓝',
      description: '专业 · 信任 · 清爽',
      primary: Color(0xFF1677FF), // Ant Design Blue
      gradientEnd: Color(0xFF0958D9),
    ),
    AppThemePreset(
      name: '清新绿',
      description: '干净 · 护眼 · 有活力',
      primary: Color(0xFF00B42A),
      gradientEnd: Color(0xFF008A20),
    ),
    AppThemePreset(
      name: '轻奢紫',
      description: '现代 · 精致 · 高辨识',
      primary: Color(0xFF722ED1),
      gradientEnd: Color(0xFF531DAB),
    ),
  ];

  /// 安全取预设（超出范围自动钳位）
  static AppThemePreset preset(int index) =>
      presets[index.clamp(0, presets.length - 1)];

  /// 默认预设（科技蓝）
  static AppThemePreset get defaultPreset => presets[0];
}

// ─────────────────────────────────────────────────────────────────────────────
// ThemeExtension：将渐变色注入 ThemeData，供全局 Widget 消费
// ─────────────────────────────────────────────────────────────────────────────

class AppGradientTheme extends ThemeExtension<AppGradientTheme> {
  final Color gradientStart;
  final Color gradientEnd;

  const AppGradientTheme({
    required this.gradientStart,
    required this.gradientEnd,
  });

  // ── 便捷工厂：从预设索引构建 ──────────────────────────────────────────────
  factory AppGradientTheme.fromPreset(int colorIndex) {
    final p = AppColors.preset(colorIndex);
    return AppGradientTheme(
      gradientStart: p.primary,
      gradientEnd: p.gradientEnd,
    );
  }

  // ── 从 BuildContext 安全读取（带默认值兜底） ──────────────────────────────
  static AppGradientTheme of(BuildContext context) {
    return Theme.of(context).extension<AppGradientTheme>() ??
        AppGradientTheme.fromPreset(0);
  }

  // ── 生成 LinearGradient ───────────────────────────────────────────────────
  LinearGradient get linearGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gradientStart, gradientEnd],
      );

  // ── 垂直方向渐变（用于 AppBar / Banner 背景）─────────────────────────────
  LinearGradient get verticalGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [gradientStart, gradientEnd],
      );

  // ── ThemeExtension 必要重写 ───────────────────────────────────────────────
  @override
  AppGradientTheme copyWith({Color? gradientStart, Color? gradientEnd}) {
    return AppGradientTheme(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  AppGradientTheme lerp(ThemeExtension<AppGradientTheme>? other, double t) {
    if (other is! AppGradientTheme) return this;
    return AppGradientTheme(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}
