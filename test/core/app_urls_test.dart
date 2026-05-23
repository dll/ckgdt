import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/constants/app_urls.dart';

/// 验证 URL/Token 中央常量的稳定性。
/// 这些值被多个文件引用，被改错会引起远程同步全班崩。
void main() {
  group('AppUrls', () {
    test('webApp 是 GitHub Pages 形式', () {
      expect(AppUrls.webApp, startsWith('https://'));
      expect(AppUrls.webApp.endsWith('/'), isTrue,
          reason: 'base href 末尾必须是 / 否则 Flutter web 资源加载 404');
    });

    test('giteeApi 指向 v5', () {
      expect(AppUrls.giteeApi, equals('https://gitee.com/api/v5'));
    });

    test('giteeRepo 与 webApp 不同', () {
      expect(AppUrls.giteeRepo, isNot(equals(AppUrls.webApp)));
    });
  });

  group('GiteeCredentials', () {
    test('syncToken 是 32 位十六进制', () {
      expect(GiteeCredentials.syncToken.length, 32);
      expect(GiteeCredentials.syncToken,
          matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('legacyTokenForMigration 与 syncToken 不同', () {
      expect(GiteeCredentials.legacyTokenForMigration,
          isNot(equals(GiteeCredentials.syncToken)),
          reason: '迁移检测要靠两者不同');
    });
  });
}
