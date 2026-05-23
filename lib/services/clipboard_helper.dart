import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 剪贴板助手 — 写入剪贴板并显示统一的 toast 提示。
///
/// 替代散落各处的 `Clipboard.setData(...) + ScaffoldMessenger.showSnackBar(...)`
/// 模板，并统一处理 `context.mounted` 检查避免 use_build_context_synchronously。
class ClipboardHelper {
  ClipboardHelper._();

  /// 把 [text] 写入剪贴板，成功后用浮动 SnackBar 提示。
  /// [message] 默认"已复制到剪贴板"，调用方可定制。
  static Future<void> copyWithToast(
    BuildContext context,
    String text, {
    String message = '已复制到剪贴板',
    Duration duration = const Duration(seconds: 2),
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: duration),
    );
  }
}
