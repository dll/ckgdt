import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/live_stream_panel.dart';
import '../../services/live_stream_service.dart';
import 'dart:async';

/// 管理答辩直播浮窗的显示、隐藏、状态切换
class LiveStreamOverlay {
  LiveStreamOverlay._();

  static OverlayEntry? _entry;
  static bool _isVisible = false;

  static bool _minimized = false;
  static bool _fullscreen = false;
  static bool _locked = false;

  static Offset _position = const Offset(20, 80);
  static Size _size = const Size(200, 280);
  static StreamController<void>? _updateController;

  static bool get isVisible => _isVisible;
  static bool get isLocked => _locked;
  static bool get isMinimized => _minimized;
  static bool get isFullscreen => _fullscreen;
  static Size get panelSize {
    if (_fullscreen) {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      return Size(
        view.physicalSize.width / view.devicePixelRatio,
        view.physicalSize.height / view.devicePixelRatio,
      );
    }
    return _size;
  }
  static Offset get panelPosition => _fullscreen ? Offset.zero : _position;

  static void show(BuildContext context) {
    if (_isVisible) return;
    _isVisible = true;
    _updateController = StreamController<void>.broadcast();

    _entry = OverlayEntry(
      builder: (_) => _LiveStreamWrapper(
        updateStream: _updateController!.stream,
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
    _isVisible = false;
    _updateController?.close();
    _updateController = null;
    // 重置瞬态浮窗状态，避免下次打开继承上次的最小化/全屏/锁定
    _minimized = false;
    _fullscreen = false;
    _locked = false;
    // 释放摄像头：否则关闭浮窗后 webcam 指示灯常亮
    LiveStreamService().shutdownCamera();
  }

  static void toggleMinimize() {
    if (_fullscreen) return;
    _minimized = !_minimized;
    _notify();
  }

  static void toggleFullscreen() {
    _fullscreen = !_fullscreen;
    if (_fullscreen) _minimized = false;
    _notify();
  }

  static void toggleLock() {
    _locked = !_locked;
    _notify();
  }

  static void updatePosition(Offset delta) {
    if (_locked || _fullscreen) return;
    _position += delta;
    _notify();
  }

  static void setPosition(Offset newPos) {
    if (_locked || _fullscreen) return;
    _position = newPos;
    _notify();
  }

  static void updateSize(Offset delta) {
    if (_locked || _fullscreen) return;
    _size = Size(
      max(140, _size.width + delta.dx),
      max(180, _size.height + delta.dy),
    );
    _notify();
  }

  static void setSize(Size newSize) {
    if (_locked || _fullscreen) return;
    _size = newSize;
    _notify();
  }

  static void _notify() {
    _updateController?.add(null);
  }
}

class _LiveStreamWrapper extends StatefulWidget {
  final Stream<void> updateStream;
  const _LiveStreamWrapper({required this.updateStream});

  @override
  State<_LiveStreamWrapper> createState() => _LiveStreamWrapperState();
}

class _LiveStreamWrapperState extends State<_LiveStreamWrapper> {
  Offset _pos = LiveStreamOverlay.panelPosition;
  Size _size = LiveStreamOverlay.panelSize;
  bool _minimized = false;
  bool _fullscreen = false;
  bool _locked = false;

  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _pos = LiveStreamOverlay.panelPosition;
    _size = LiveStreamOverlay.panelSize;
    _sub = widget.updateStream.listen((_) {
      if (mounted) {
        setState(() {
          _pos = LiveStreamOverlay.panelPosition;
          _size = LiveStreamOverlay.panelSize;
          _minimized = LiveStreamOverlay._minimized;
          _fullscreen = LiveStreamOverlay._fullscreen;
          _locked = LiveStreamOverlay._locked;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_minimized) {
      return Positioned(
        right: 16,
        bottom: 16,
        child: _buildMinimizedChip(),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    // 窗口比面板还窄时 (width - panelWidth) 会变负，clamp 的上界须 >= 下界，
    // 否则触发 lowerLimit <= upperLimit 断言崩溃。用 max(0,...) 兜底。
    final maxX = max(0.0, screenSize.width - _size.width);
    final maxY = max(0.0, screenSize.height - _size.height);
    final clampedX = _pos.dx.clamp(0.0, maxX);
    final clampedY = _pos.dy.clamp(0.0, maxY);

    return Positioned(
      left: _fullscreen ? 0 : clampedX,
      top: _fullscreen ? 0 : clampedY,
      width: _fullscreen ? screenSize.width : _size.width,
      height: _fullscreen ? screenSize.height : _size.height,
      child: Material(
        color: Colors.transparent,
        child: _fullscreen
            ? _buildFullscreenPanel(screenSize)
            : _buildDraggablePanel(),
      ),
    );
  }

  Widget _buildMinimizedChip() {
    return GestureDetector(
      onTap: () => LiveStreamOverlay.toggleMinimize(),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E1A),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: const Color(0xFFF4B942).withValues(alpha: 0.4),
            width: 2,
          ),
        ),
        child: const Icon(Icons.videocam, color: Color(0xFFF4B942), size: 24),
      ),
    );
  }

  Widget _buildDraggablePanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onPanUpdate: _locked
            ? null
            : (d) {
                final delta = d.delta;
                final newPos = Offset(
                  _pos.dx + delta.dx,
                  _pos.dy + delta.dy,
                );
                setState(() {
                  _pos = newPos;
                  LiveStreamOverlay.setPosition(newPos);
                });
              },
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: LiveStreamPanel(
                onClose: () => LiveStreamOverlay.hide(),
                onMinimize: () => LiveStreamOverlay.toggleMinimize(),
                onFullscreen: () => LiveStreamOverlay.toggleFullscreen(),
                onLock: () => LiveStreamOverlay.toggleLock(),
                isLocked: _locked,
                isFullscreen: false,
              ),
            ),
            // 右下角缩放手柄（锁定时禁用）
            if (!_locked)
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    setState(() {
                      _size = Size(
                        max(140, _size.width + d.delta.dx),
                        max(180, _size.height + d.delta.dy),
                      );
                      LiveStreamOverlay.setSize(_size);
                    });
                  },
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: Icon(Icons.open_in_full,
                        size: 12, color: Color(0xFFF4B942)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenPanel(Size screenSize) {
    return Container(
      color: const Color(0xFF0A0E1A),
      child: LiveStreamPanel(
        onClose: () => LiveStreamOverlay.hide(),
        onMinimize: () => LiveStreamOverlay.toggleFullscreen(),
        onFullscreen: () => LiveStreamOverlay.toggleFullscreen(),
        onLock: () => LiveStreamOverlay.toggleLock(),
        isLocked: _locked,
        isFullscreen: true,
        compact: true,
      ),
    );
  }
}
