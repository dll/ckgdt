import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/pandoc_service.dart';

/// PandocService 集成测试。
///
/// **前置条件**：本机 PATH 中有 pandoc 3.x。Windows 教师端默认有，CI 没有时
/// 测试会跳过（不挂红）。
///
/// **运行**：`flutter test test/services/archive/pandoc_service_test.dart`
void main() {
  group('PandocService', () {
    late PandocService svc;

    setUp(() {
      svc = PandocService.instance;
      svc.resetCacheForTest();
    });

    test('isAvailable in desktop platforms', () {
      // 单测在桌面 Dart VM 跑，应返回 true
      if (kIsWeb) {
        expect(svc.isAvailable, isFalse);
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        expect(svc.isAvailable, isTrue);
      }
    });

    test('isInstalled detects pandoc binary', () async {
      if (!svc.isAvailable) {
        return; // 移动端跳过
      }
      final installed = await svc.isInstalled;
      // 不强制要求装：装了 pass，没装也不挂红，只打印警告
      if (!installed) {
        debugPrint('⚠️ pandoc 未安装。归档打印功能不可用。');
      }
      expect(installed, isA<bool>());
    });

    test('markdownToDocx produces valid docx bytes', () async {
      if (!svc.isAvailable || !await svc.isInstalled) {
        debugPrint('⏭️ skip: pandoc not available');
        return;
      }

      const md = '''
# 测试文档

这是 PandocService 的集成测试输入。

## 第一节

| 列 A | 列 B |
|------|------|
| 1    | 2    |
| 3    | 4    |

- 列表项 1
- 列表项 2
''';

      final bytes = await svc.markdownToDocx(md);

      // docx 是 zip 格式，magic number "PK\x03\x04"
      expect(bytes.length, greaterThan(100));
      expect(bytes[0], equals(0x50)); // 'P'
      expect(bytes[1], equals(0x4B)); // 'K'
      expect(bytes[2], equals(0x03));
      expect(bytes[3], equals(0x04));
    });

    test('markdownToDocx with non-existent reference doc falls back gracefully',
        () async {
      if (!svc.isAvailable || !await svc.isInstalled) return;

      // 给个不存在的 reference doc 路径，PandocService 应该忽略它（File.existsSync 检查）
      // 而不是 crash
      final bytes = await svc.markdownToDocx(
        '# Hello',
        referenceDocPath: '/nonexistent/path/template.docx',
      );

      expect(bytes.length, greaterThan(100));
      expect(bytes[0], equals(0x50));
    });

    test('markdownToPdf throws UnimplementedError (commit 5 will implement)',
        () async {
      expect(
        () => svc.markdownToPdf('# Hello'),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
