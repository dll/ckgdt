/// 本地化代理完整性测试
///
/// 此测试防止 localizationsDelegates 被清空的历史事故复发。
/// 历史事故：2026-05 至 2026-07 期间，localizationsDelegates
/// 曾被清空 6 次，导致登录页 TextField 运行时崩溃。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/app_localization.dart';

void main() {
  group('AppLocalization', () {
    test('delegates 列表不能为空', () {
      expect(AppLocalization.delegates, isNotEmpty,
          reason: 'localizationsDelegates 为空会导致 MaterialLocalizations.of(context) 返回 null，'
              '进而导致登录页 TextField 运行时崩溃（灰色错误占位）。'
              '如果此测试失败，请检查 lib/core/app_localization.dart');
    });

    test('delegates 必须包含 4 个必要代理', () {
      expect(AppLocalization.delegates.length, greaterThanOrEqualTo(4),
          reason: '需要包含：AppL10n.delegate, GlobalMaterialLocalizations, '
              'GlobalCupertinoLocalizations, GlobalWidgetsLocalizations');
    });

    test('delegates 包含 AppL10n.delegate', () {
      final hasAppL10n = AppLocalization.delegates.any(
        (d) => d.toString().contains('AppL10n') || d.runtimeType.toString().contains('AppL10n'),
      );
      expect(hasAppL10n, isTrue,
          reason: '缺少 AppL10n.delegate，中文本地化将失效');
    });

    test('delegates 包含 GlobalMaterialLocalizations', () {
      final hasMaterial = AppLocalization.delegates.any(
        (d) => d.toString().contains('GlobalMaterialLocalizations') ||
            d.runtimeType.toString().contains('GlobalMaterialLocalizations'),
      );
      expect(hasMaterial, isTrue,
          reason: '缺少 GlobalMaterialLocalizations.delegate，TextField 会崩溃');
    });

    test('supportedLocales 包含中文', () {
      final hasZh = AppLocalization.supportedLocales.any(
        (l) => l.languageCode == 'zh',
      );
      expect(hasZh, isTrue, reason: '缺少中文支持');
    });

    test('assertValid 不抛出异常', () {
      expect(() => AppLocalization.assertValid(), returnsNormally);
    });
  });
}
