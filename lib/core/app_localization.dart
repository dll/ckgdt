/// 本地化代理配置 — 单一来源（SSOT）
///
/// ⚠️ 警告：此文件中的 [localizationsDelegates] 和 [supportedLocales]
/// 被 main.dart 的两个 MaterialApp 引用。任何AI助手、自动重构工具、
/// 或开发者都 **绝对不能** 将 MaterialApp.localizationsDelegates
/// 改为 `const []` 或其他空列表。
///
/// 历史事故：localizationsDelegates 曾被清空 6 次（2026-05 至 2026-07），
/// 导致登录页 TextField 运行时崩溃（灰色错误占位）。
///
/// 如果你需要修改本地化配置，只改这个文件。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../l10n/gen/app_localizations.dart';

/// 本地化代理 — 统一入口
///
/// 用法：在 MaterialApp 中使用
/// ```dart
/// localizationsDelegates: AppLocalization.delegates,
/// supportedLocales: AppLocalization.supportedLocales,
/// ```
class AppLocalization {
  AppLocalization._();

  /// 本地化代理列表 — 包含 Material/Cupertino/Widgets + AppL10n
  ///
  /// ⚠️ 此列表 **不能为空**。如果为空，MaterialLocalizations.of(context)
  /// 会返回 null，导致 TextField 运行时崩溃。
  static const List<LocalizationsDelegate<dynamic>> delegates = [
    AppL10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// 支持的语言列表
  static const List<Locale> supportedLocales = [
    Locale('zh'),
    Locale('en'),
  ];

  /// 调试断言：验证 delegates 非空
  ///
  /// 在 debug 模式下，App 启动时调用此方法可确保配置正确。
  static void assertValid() {
    assert(() {
      if (delegates.isEmpty) {
        throw FlutterError(
          'AppLocalization.delegates 为空！\n'
          '这会导致登录页 TextField 崩溃（灰色错误占位）。\n'
          '请检查 lib/core/app_localization.dart 是否被正确配置。',
        );
      }
      if (delegates.length < 4) {
        throw FlutterError(
          'AppLocalization.delegates 数量不足（${delegates.length}/4）。\n'
          '需要包含：AppL10n.delegate, GlobalMaterialLocalizations, '
          'GlobalCupertinoLocalizations, GlobalWidgetsLocalizations。',
        );
      }
      return true;
    }());
  }
}
