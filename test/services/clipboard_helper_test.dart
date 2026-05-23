import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/clipboard_helper.dart';

/// 验证 ClipboardHelper.copyWithToast 同时做了两件事：
/// 1. 写入系统剪贴板
/// 2. 显示 SnackBar 提示
///
/// 全局 16 处 setData+SnackBar 重复代码已替换为该 helper（部分），
/// 此 test 防止后续重构破坏行为。
void main() {
  // 拦截系统 Clipboard 通道
  String? lastClipText;
  setUp(() {
    lastClipText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          lastClipText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
  });

  testWidgets('copyWithToast 写剪贴板 + 弹默认提示', (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldKey,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => ClipboardHelper.copyWithToast(ctx, 'hello'),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump(); // 触发 setData
    await tester.pump(); // 触发 SnackBar

    expect(lastClipText, 'hello');
    expect(find.text('已复制到剪贴板'), findsOneWidget);
  });

  testWidgets('copyWithToast 自定义 message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () =>
                ClipboardHelper.copyWithToast(ctx, 'x', message: '自定义提示'),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();

    expect(find.text('自定义提示'), findsOneWidget);
  });
}
