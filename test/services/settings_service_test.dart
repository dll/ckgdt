import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knowledge_graph_app/services/settings_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // SettingsService — ThemeMode
  // ═══════════════════════════════════════════════════════════════════════════

  group('SettingsService - ThemeMode', () {
    test('getThemeMode should return dark by default (Noir style)', () async {
      SharedPreferences.setMockInitialValues({});
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.dark);
    });

    test('setThemeMode and getThemeMode should round-trip light mode',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setThemeMode(ThemeMode.light);
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.light);
    });

    test('setThemeMode and getThemeMode should round-trip dark mode', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setThemeMode(ThemeMode.dark);
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.dark);
    });

    test('setThemeMode and getThemeMode should round-trip system mode',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setThemeMode(ThemeMode.system);
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.system);
    });

    test('getThemeMode should handle legacy bool key (dark=true)', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': true,
      });
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.dark);
    });

    test('getThemeMode should handle legacy bool key (dark=false)', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': false,
      });
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.system);
    });

    test('new key should take precedence over legacy key', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': true, // legacy: dark
        'theme_mode_index': 1, // new: light
      });
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.light);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SettingsService — isDarkMode / setDarkMode (向下兼容)
  // ═══════════════════════════════════════════════════════════════════════════

  group('SettingsService - isDarkMode compatibility', () {
    test('isDarkMode should return true when dark mode is set', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setThemeMode(ThemeMode.dark);
      final isDark = await SettingsService.isDarkMode();
      expect(isDark, isTrue);
    });

    test('isDarkMode should return false when light mode is set', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setThemeMode(ThemeMode.light);
      final isDark = await SettingsService.isDarkMode();
      expect(isDark, isFalse);
    });

    test('isDarkMode should return false when system mode is set', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setThemeMode(ThemeMode.system);
      final isDark = await SettingsService.isDarkMode();
      expect(isDark, isFalse);
    });

    test('setDarkMode(true) should set dark mode', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setDarkMode(true);
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.dark);
    });

    test('setDarkMode(false) should set light mode', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setDarkMode(false);
      final mode = await SettingsService.getThemeMode();
      expect(mode, ThemeMode.light);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SettingsService — Color Index
  // ═══════════════════════════════════════════════════════════════════════════

  group('SettingsService - ColorIndex', () {
    test('getColorIndex should return 0 by default', () async {
      SharedPreferences.setMockInitialValues({});
      final index = await SettingsService.getColorIndex();
      expect(index, 0);
    });

    test('setColorIndex and getColorIndex should round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setColorIndex(1);
      final index = await SettingsService.getColorIndex();
      expect(index, 1);
    });

    test('setColorIndex should clamp to valid range (0-2)', () async {
      SharedPreferences.setMockInitialValues({});

      await SettingsService.setColorIndex(5);
      final high = await SettingsService.getColorIndex();
      expect(high, 2);

      await SettingsService.setColorIndex(-1);
      final low = await SettingsService.getColorIndex();
      expect(low, 0);
    });

    test('getColorIndex should clamp stored value', () async {
      SharedPreferences.setMockInitialValues({
        'color_index': 99,
      });
      final index = await SettingsService.getColorIndex();
      expect(index, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SettingsService — Notification
  // ═══════════════════════════════════════════════════════════════════════════

  group('SettingsService - Notification', () {
    test('isNotificationEnabled should return true by default', () async {
      SharedPreferences.setMockInitialValues({});
      final enabled = await SettingsService.isNotificationEnabled();
      expect(enabled, isTrue);
    });

    test('setNotificationEnabled should persist value', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setNotificationEnabled(false);
      final enabled = await SettingsService.isNotificationEnabled();
      expect(enabled, isFalse);
    });

    test('setNotificationEnabled should toggle correctly', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setNotificationEnabled(false);
      expect(await SettingsService.isNotificationEnabled(), isFalse);

      await SettingsService.setNotificationEnabled(true);
      expect(await SettingsService.isNotificationEnabled(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SettingsService — Quick Login
  // ═══════════════════════════════════════════════════════════════════════════

  group('SettingsService - QuickLogin', () {
    test('isQuickLoginEnabled should return false by default', () async {
      SharedPreferences.setMockInitialValues({});
      final enabled = await SettingsService.isQuickLoginEnabled();
      expect(enabled, isFalse);
    });

    test('setQuickLoginEnabled should persist value', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setQuickLoginEnabled(true);
      final enabled = await SettingsService.isQuickLoginEnabled();
      expect(enabled, isTrue);
    });

    test('setQuickLoginEnabled should toggle correctly', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.setQuickLoginEnabled(true);
      expect(await SettingsService.isQuickLoginEnabled(), isTrue);

      await SettingsService.setQuickLoginEnabled(false);
      expect(await SettingsService.isQuickLoginEnabled(), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SettingsService — Xunfei voice trial keys
  // ═══════════════════════════════════════════════════════════════════════════

  group('SettingsService - Xunfei voice keys', () {
    test('builtin trial voice keys are enabled by default', () async {
      SharedPreferences.setMockInitialValues({});

      expect(kUseBuiltinTrialVoiceKeys, isTrue);
      expect(await SettingsService.getXunfeiAppId(), isNotEmpty);
      expect(await SettingsService.getXunfeiApiKey(), isNotEmpty);
      expect(await SettingsService.getXunfeiApiSecret(), isNotEmpty);
    });

    test('user configured voice keys should override trial keys', () async {
      SharedPreferences.setMockInitialValues({});

      await SettingsService.setXunfeiAppId('user-app-id');
      await SettingsService.setXunfeiApiKey('user-api-key');
      await SettingsService.setXunfeiApiSecret('user-api-secret');

      expect(await SettingsService.getXunfeiAppId(), 'user-app-id');
      expect(await SettingsService.getXunfeiApiKey(), 'user-api-key');
      expect(await SettingsService.getXunfeiApiSecret(), 'user-api-secret');
    });
  });
}
