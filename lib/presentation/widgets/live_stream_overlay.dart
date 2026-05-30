import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/live_stream_panel.dart';
import 'dart:async';

/// 管理答辩直播浮窗的显示、隐藏、状态切换
class LiveStreamOverlay {
  LiveStreamOverlay._();

  static OverlayEntry? _entry;
  static bool _isVisible = false;

  static bool _minimized = false;
  static bool _fullscreen = false;
  static bool _locked = false;

  static Offset _position = const Offset(80, 80);
  static Size _size = const Size(560, 400);
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
      max(400, _size.width + delta.dx),
      max(300, _size.height + delta.dy),
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
    final clampedX = _pos.dx.clamp(0.0, screenSize.width - _size.width);
    final clampedY = _pos.dy.clamp(0.0, screenSize.height - _size.height);

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
        child: Container(
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
