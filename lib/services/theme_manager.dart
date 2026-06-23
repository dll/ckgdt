import 'package:flutter/material.dart';
import '../core/constants/app_theme.dart';
import '../core/design/noir_tokens.dart';

/// Editorial Tech-Noir 全局主题 —— 在 ThemeData 层下沉视觉语言，
/// 让所有 Material 默认组件（AppBar / Card / Button / Dialog / SnackBar /
/// Divider / TextField / Chip 等）在 88 个页面自动获得统一外观，
/// 不必为每个页面手动套 Noir 组件。
///
/// 用户选择的主题色（[colorIndex]）只参与 [colorScheme.primary] 与
/// [AppGradientTheme]，作为强调点；底层结构色（背景 / 卡片 / 边框 / 按钮）
/// 全部走 [NoirTokens]。
class ThemeManager {
  ThemeManager._();

  static ThemeData light(int colorIndex) =>
      _build(colorIndex, brightness: Brightness.light);

  static ThemeData dark(int colorIndex) =>
      _build(colorIndex, brightness: Brightness.dark);

  // ───────────────────────────────────────────────────────────────────────────
  static ThemeData _build(int colorIndex, {required Brightness brightness}) {
    final preset = AppColors.preset(colorIndex);
    final isDark = brightness == Brightness.dark;

    final pageBg = isDark ? NoirTokens.ink : const Color(0xFFF1ECE2);
    final cardBg = isDark ? const Color(0xFF181C24) : NoirTokens.paper;
    final onCard = isDark ? NoirTokens.paper : NoirTokens.ink;
    final hairline = isDark
        ? const Color(0x33F7F4EE)
        : NoirTokens.ink.withValues(alpha: 0.10);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: preset.primary,
      brightness: brightness,
    ).copyWith(
      surface: cardBg,
      onSurface: onCard,
      outline: hairline,
      primary: preset.primary,
    );

    final radius = BorderRadius.circular(NoirTokens.radius);

    // 主题色驱动的可视强调位（用户切色后立即可见的位置）
    // 同时混入琥珀，让色彩切换不破坏 noir 编辑感整体氛围。
    final accent = preset.primary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: pageBg,
      canvasColor: pageBg,
      dividerColor: hairline,
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 24,
      ),

      // ── AppBar：主题色填充 + 白字 + 居中 ─────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
        toolbarHeight: 56,
      ),

      // ── 卡片：1px hairline + 极小圆角 + 0 elevation ────────────────────
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: hairline),
        ),
      ),

      // ── 主按钮：主题色底 + 白字 ──────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.6), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),

      // ── 浮动按钮：主题色底 + 白色图标 ────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 4,
        focusElevation: 6,
        hoverElevation: 6,
        highlightElevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),

      // ── 输入框：浮动小标 + 单线下划线 + focus 加粗 ───────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
        labelStyle: TextStyle(
          color: onCard.withValues(alpha: 0.55),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
        floatingLabelStyle: TextStyle(
          color: onCard.withValues(alpha: 0.7),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
        hintStyle: TextStyle(
          color: onCard.withValues(alpha: 0.35),
          fontSize: 13,
        ),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: onCard.withValues(alpha: 0.25)),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: onCard.withValues(alpha: 0.25)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: onCard, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: NoirTokens.danger, width: 1),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: NoirTokens.danger, width: 1.5),
        ),
        errorStyle: const TextStyle(fontSize: 11, height: 1.2),
      ),

      // ── 弹窗 ─────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: hairline),
        ),
        titleTextStyle: TextStyle(
          color: onCard,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
        contentTextStyle: TextStyle(
          color: onCard.withValues(alpha: 0.85),
          fontSize: 13,
          height: 1.5,
        ),
      ),

      // ── SnackBar ─────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NoirTokens.ink,
        contentTextStyle: const TextStyle(
          color: NoirTokens.paper,
          fontSize: 13,
          letterSpacing: 0.8,
        ),
        actionTextColor: NoirTokens.accent,
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),

      // ── Tab ──────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: onCard,
        unselectedLabelColor: onCard.withValues(alpha: 0.45),
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: hairline,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.5,
        ),
      ),

      // ── BottomNavigation / NavigationBar ────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardBg,
        elevation: 0,
        height: 64,
        indicatorColor: accent.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? accent : onCard.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 1.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? accent : onCard.withValues(alpha: 0.6),
            size: 22,
          );
        }),
      ),

      // ── Chip ─────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(
          color: onCard,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),

      // ── ListTile ─────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        iconColor: onCard.withValues(alpha: 0.7),
        textColor: onCard,
        titleTextStyle: TextStyle(
          color: onCard,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        subtitleTextStyle: TextStyle(
          color: onCard.withValues(alpha: 0.6),
          fontSize: 12,
          letterSpacing: 0.5,
          height: 1.4,
        ),
      ),

      // ── 选择控件 ─────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: hairline, width: 1),
        shape: RoundedRectangleBorder(borderRadius: radius),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? NoirTokens.ink
                : Colors.transparent),
        checkColor: WidgetStateProperty.all(NoirTokens.accent),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? NoirTokens.ink
                : onCard.withValues(alpha: 0.2)),
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? NoirTokens.accent
                : NoirTokens.paper),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? NoirTokens.ink : hairline),
      ),

      // ── 进度 ─────────────────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: accent.withValues(alpha: 0.15),
      ),

      // ── 文本基础 ────────────────────────────────────────────────────
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            color: onCard,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15),
        headlineMedium: TextStyle(
            color: onCard,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.2),
        titleLarge: TextStyle(
            color: onCard,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5),
        titleMedium: TextStyle(
            color: onCard,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5),
        bodyLarge: TextStyle(color: onCard, fontSize: 14, height: 1.5),
        bodyMedium: TextStyle(color: onCard, fontSize: 13, height: 1.5),
        labelLarge: TextStyle(
            color: onCard,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5),
        labelSmall: TextStyle(
            color: onCard.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5),
      ).apply(
        bodyColor: onCard,
        displayColor: onCard,
      ),

      extensions: [
        AppGradientTheme.fromPreset(colorIndex),
      ],
    );
  }
}
