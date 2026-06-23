import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MaterialApp uses AppL10n delegates instead of an empty delegate list',
      () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains("import 'l10n/gen/app_localizations.dart';"));
    expect(mainSource, contains('supportedLocales: AppL10n.supportedLocales'));
    expect(
      mainSource,
      contains('localizationsDelegates: AppL10n.localizationsDelegates'),
    );
    expect(mainSource, isNot(contains('localizationsDelegates: const []')));
  });
}
