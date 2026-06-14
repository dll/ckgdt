import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../core/design/noir_tokens.dart';
import '../../core/error_handler.dart';
import '../../services/live_stream_service.dart';

class LiveStreamPanel extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onFullscreen;
  final VoidCallback onLock;
  final bool isLocked;
  final bool isFullscreen;
  final bool compact;

  const LiveStreamPanel({
    super.key,
    required this.onClose,
    required this.onMinimize,
    required this.onFullscreen,
    required this.onLock,
    this.isLocked = false,
    this.isFullscreen = false,
    this.compact = false,
  });

  @override
  State<LiveStreamPanel> createState() => _LiveStreamPanelState();
}

class _LiveStreamPanelState extends State<LiveStreamPanel>
    with SingleTickerProviderStateMixin {
  final _service = LiveStreamService();
  StreamSubscription? _stateSub;
  LiveStreamState? _state;

  late AnimationController _pulseAnim;
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _state = _service.currentState;

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncPulse(_state?.status);

    _stateSub = _service.state.listen((s) {
      if (!mounted) return;
      _syncPulse(s.status);
      setState(() => _state = s);
    });

    _service.initializeCamera();
    _showControlsTemporarily();
  }

  /// 录制脉冲灯只在录制时跑，空闲时停掉，避免常驻 60fps 空转重建。
  void _syncPulse(LiveStreamStatus? status) {
    final shouldPulse = status == LiveStreamStatus.recording;
    if (shouldPulse && !_pulseAnim.isAnimating) {
      _pulseAnim.repeat(reverse: true);
    } else if (!shouldPulse && _pulseAnim.isAnimating) {
      _pulseAnim.stop();
      _pulseAnim.value = 1.0;
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _pulseAnim.dispose();
    _controlsTimer?.cancel();
    super.dispose();
  }

  void _showControlsTemporarily() {
    _controlsVisible = true;
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !widget.isLocked) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) _showControlsTemporarily();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildBody()),
        if (_controlsVisible || widget.compact) _buildControls(),
        if (widget.compact && !_controlsVisible)
          const SizedBox(height: 4),
      ],
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: NoirTokens.inkDeep,
        border: Border(
          bottom: BorderSide(
            color: NoirTokens.accent.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _statusDot(),
          const SizedBox(width: 6),
          Text(
            _buildStatusText(),
            style: TextStyle(
              color: _state?.status == LiveStreamStatus.recording
                  ? NoirTokens.accent
                  : NoirTokens.paper.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          _headerBtn(Icons.lock_outline, widget.isLocked, widget.onLock),
          if (!widget.isFullscreen)
            _headerBtn(Icons.fullscreen, false, widget.onFullscreen),
          _headerBtn(Icons.minimize, false, widget.onMinimize),
          _headerBtn(Icons.close, false, widget.onClose),
        ],
      ),
    );
  }

  Widget _statusDot() {
    final status = _state?.status ?? LiveStreamStatus.idle;
    Color dotColor;
    switch (status) {
      case LiveStreamStatus.idle:
      case LiveStreamStatus.initializing:
        dotColor = Colors.grey;
      case LiveStreamStatus.ready:
        dotColor = Colors.green;
      case LiveStreamStatus.recording:
        dotColor = Colors.red;
      case LiveStreamStatus.error:
        dotColor = Colors.orange;
    }
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) {
        final opacity = status == LiveStreamStatus.recording
            ? 0.3 + 0.7 * _pulseAnim.value
            : 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor.withValues(alpha: opacity),
            shape: BoxShape.circle,
            boxShadow: status == LiveStreamStatus.recording
                ? [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.6 * _pulseAnim.value),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }

  String _buildStatusText() {
    final s = _state;
    if (s == null) return 'LIVE';
    switch (s.status) {
      case LiveStreamStatus.idle:
        return 'OFFLINE';
      case LiveStreamStatus.initializing:
        return 'INITIALIZING…';
      case LiveStreamStatus.ready:
        return 'STANDBY';
      case LiveStreamStatus.recording:
        return 'REC ${_formatDuration(s.recordDuration)}';
      case LiveStreamStatus.error:
        return 'ERROR';
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours.toString().padLeft(2, '0')}:$m:$s';
  }

  Widget _headerBtn(IconData icon, bool active, VoidCallback onTap) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        icon: Icon(icon, size: 14),
        color: active
            ? NoirTokens.accent
            : NoirTokens.paper.withValues(alpha: 0.6),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 14,
      ),
    );
  }

  // ── Body: 摄像头预览（画中画，铺满主体）────────────────────────────
  //
  // 移动演示场景：直播浮窗悬浮在正在演示的 App 之上，学生在浮窗背后操作
  // App 演示，浮窗内只显示摄像头实时画面（人脸），实现"边演示边露脸"。

  Widget _buildBody() {
    return GestureDetector(
      onTap: _toggleControls,
      child: _buildCameraPreview(),
    );
  }

  Widget _buildCameraPreview() {
    final s = _state;
    if (s == null || s.status == LiveStreamStatus.idle) {
      return _placeholder(Icons.videocam_off_outlined, '摄像头未就绪');
    }
    if (s.status == LiveStreamStatus.initializing) {
      return _placeholder(Icons.hourglass_top, '正在启动摄像头…');
    }
    if (s.status == LiveStreamStatus.error) {
      return _placeholder(Icons.error_outline, s.error ?? '摄像头错误');
    }
    if (!s.isCameraOn || _service.cameraController == null) {
      return _placeholder(Icons.videocam_off, '摄像头已关闭');
    }

    final camCtrl = _service.cameraController!;
    if (!camCtrl.value.isInitialized) {
      return _placeholder(Icons.hourglass_top, '摄像头初始化中…');
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ScaledCameraPreview(camCtrl),
          // 水印
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _getCameraLabel(),
                style: const TextStyle(
                  color: NoirTokens.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          // 录制指示器
          if (s.status == LiveStreamStatus.recording)
            Positioned(
              right: 4,
              top: 4,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.4 + 0.6 * _pulseAnim.value),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getCameraLabel() {
    try {
      final cam = _service.cameraController?.description;
      if (cam == null) return 'CAM';
      return cam.lensDirection == CameraLensDirection.front ? 'FRONT' : 'BACK';
    } catch (e) {
      swallow(e, tag: 'LiveStreamPanel.cameraLabel');
      return 'CAM';
    }
  }

  Widget _placeholder(IconData icon, String text) {
    return Container(
      color: NoirTokens.inkDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28,
                color: NoirTokens.paper.withValues(alpha: 0.3)),
            const SizedBox(height: 6),
            Text(text,
                style: TextStyle(
                  color: NoirTokens.paper.withValues(alpha: 0.4),
                  fontSize: 10,
                )),
          ],
        ),
      ),
    );
  }

  // ── Controls ────────────────────────────────────────────────────────

  Widget _buildControls() {
    final s = _state;
    final isRec = s?.status == LiveStreamStatus.recording;

    return Container(
      height: widget.compact ? 38 : 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: NoirTokens.inkDeep,
        border: Border(
          top: BorderSide(
            color: NoirTokens.accent.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _recordBtn(isRec),
          if (!widget.compact) ...[
            const SizedBox(width: 4),
            _ctrlBtn(Icons.flip_camera_android, '翻转', _service.switchCamera),
            const SizedBox(width: 4),
            _ctrlBtn(
              s?.isMicOn == true ? Icons.mic : Icons.mic_off,
              '麦克风',
              _service.toggleMic,
              active: s?.isMicOn == true,
            ),
            const SizedBox(width: 4),
            _ctrlBtn(
              s?.isScreenSharing == true ? Icons.tv : Icons.screen_share,
              '共享屏幕',
              _service.toggleScreenShare,
              active: s?.isScreenSharing == true,
            ),
          ],
          const Spacer(),
          // 录制时间
          if (isRec)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(s!.recordDuration),
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          const SizedBox(width: 8),
          // 底部拖拽手柄
          Container(
            width: 24,
            height: 4,
            decoration: BoxDecoration(
              color: NoirTokens.paper.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordBtn(bool isRecording) {
    return GestureDetector(
      onTap: isRecording ? _service.stopRecording : _service.startRecording,
      child: Container(
        width: widget.compact ? 26 : 32,
        height: widget.compact ? 26 : 32,
        decoration: BoxDecoration(
          color: isRecording
              ? Colors.red.withValues(alpha: 0.15)
              : Colors.red.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: isRecording ? Colors.red : Colors.red.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Center(
          child: isRecording
              ? Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, String tooltip, VoidCallback onTap,
      {bool active = false}) {
    return SizedBox(
      width: widget.compact ? 28 : 34,
      height: widget.compact ? 28 : 34,
      child: IconButton(
        icon: Icon(icon, size: widget.compact ? 14 : 16),
        color: active
            ? NoirTokens.accent
            : NoirTokens.paper.withValues(alpha: 0.6),
        onPressed: onTap,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 16,
      ),
    );
  }
}

// ── CameraPreview 封装 ─────────────────────────────────────────────────

/// 缩放适配的摄像头预览，避免 CameraPreview 与系统 API 命名冲突。
///
/// 直播浮窗是小尺寸画中画，按容器实际尺寸做 cover 适配（铺满不留黑边），
/// 而不是按全屏 MediaQuery 计算（那样在小浮窗里会严重错位）。
class _ScaledCameraPreview extends StatelessWidget {
  final CameraController controller;
  const _ScaledCameraPreview(this.controller);

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container(color: Colors.black);
    }

    final previewSize = controller.value.previewSize;
    // previewSize 为传感器方向（宽高可能与显示相反），取其宽高比，
    // 用 FittedBox.cover 铺满浮窗容器。
    final double w = previewSize?.height ?? 16;
    final double h = previewSize?.width ?? 9;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: w,
          height: h,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
