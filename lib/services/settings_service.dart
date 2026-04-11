import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  SettingsService._();

  // ── 持久化 Key ────────────────────────────────────────────────────────────
  static const String _legacyThemeKey = 'theme_mode';       // 旧 bool 键（兼容）
  static const String _themeModeKey   = 'theme_mode_index'; // 0=system 1=light 2=dark
  static const String _colorIndexKey  = 'color_index';      // 0=科技蓝 1=清新绿 2=轻奢紫
  static const String _notificationKey = 'notification_enabled';
  static const String _quickLoginKey = 'quick_login_enabled';

  // ═════════════════════════════════════════════════════════════════════════
  // 显示模式  ThemeMode（跟随系统 / 浅色 / 深色）
  // ═════════════════════════════════════════════════════════════════════════

  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();

    // 读取新键
    if (prefs.containsKey(_themeModeKey)) {
      final index = prefs.getInt(_themeModeKey) ?? 0;
      return _indexToThemeMode(index);
    }

    // 兼容旧 bool 键：true → 深色，false → 跟随系统
    if (prefs.containsKey(_legacyThemeKey)) {
      final isDark = prefs.getBool(_legacyThemeKey) ?? false;
      return isDark ? ThemeMode.dark : ThemeMode.system;
    }

    return ThemeMode.system; // 默认跟随系统
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _themeModeToIndex(mode));
  }

  // ─── 向下兼容旧接口（部分页面仍使用）────────────────────────────────────
  static Future<bool> isDarkMode() async {
    final mode = await getThemeMode();
    return mode == ThemeMode.dark;
  }

  static Future<void> setDarkMode(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 主题色索引  0=科技蓝  1=清新绿  2=轻奢紫
  // ═════════════════════════════════════════════════════════════════════════

  static Future<int> getColorIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_colorIndexKey) ?? 0).clamp(0, 2);
  }

  static Future<void> setColorIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorIndexKey, index.clamp(0, 2));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 通知开关
  // ═════════════════════════════════════════════════════════════════════════

  static Future<bool> isNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationKey) ?? true;
  }

  static Future<void> setNotificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationKey, enabled);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 快速登录开关（管理员设置，默认关闭）
  // ═════════════════════════════════════════════════════════════════════════

  static Future<bool> isQuickLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_quickLoginKey) ?? false;
  }

  static Future<void> setQuickLoginEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_quickLoginKey, enabled);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 私有工具方法
  // ═════════════════════════════════════════════════════════════════════════

  static ThemeMode _indexToThemeMode(int index) {
    switch (index) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static int _themeModeToIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
      case ThemeMode.system:
        return 0;
    }
  }
}
