import 'package:flutter/material.dart';
import '../../services/screenshot_service.dart';

/// 自动截图页面包装器
///
/// 包装在任何页面的 Scaffold 外部，首次渲染后自动截取页面截图并缓存。
/// 截图 key 由 [captureKey] 指定，供首页菜单卡加载缩略图使用。
class ScreenshotCapturePage extends StatefulWidget {
  final String captureKey;
  final Widget child;

  const ScreenshotCapturePage({
    super.key,
    required this.captureKey,
    required this.child,
  });

  @override
  State<ScreenshotCapturePage> createState() => _ScreenshotCapturePageState();
}

class _ScreenshotCapturePageState extends State<ScreenshotCapturePage> {
  final _repaintKey = GlobalKey();
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    if (_captured) return;
    _captured = true;
    // 等待一帧确保页面完全渲染
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await ScreenshotService.instance.capture(widget.captureKey, _repaintKey);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _repaintKey,
      child: widget.child,
    );
  }
}
