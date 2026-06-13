import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../core/error_handler.dart';

/// 手机端屏幕捕获 — 优先原生全屏捕获（Android MediaProjection），
/// 降级为 RepaintBoundary 抓取自身 App 内容。
class PhoneScreenCapturer {
  PhoneScreenCapturer._();
  static final PhoneScreenCapturer instance = PhoneScreenCapturer._();

  Timer? _timer;
  String? _serverUrl;
  GlobalKey? _captureKey;
  bool _active = false;
  int _quality = 75;
  int _capW = 720;
  int _capH = 1280;
  bool _busy = false;

  // 原生全屏捕获
  final MethodChannel _methodChannel =
      const MethodChannel('madkg/screen_capture');
  final EventChannel _eventChannel =
      const EventChannel('madkg/screen_capture_events');
  final EventChannel _cameraEventChannel =
      const EventChannel('madkg/camera_capture_events');
  StreamSubscription? _nativeSub;
  StreamSubscription? _cameraSub;
  bool _useNative = false;
  Uint8List? _nativeFrame;
  bool _cameraSending = false;
  bool _allowAppFallback = false;

  bool get isActive => _active;

  void start(
    String baseUrl,
    GlobalKey captureKey, {
    int fps = 10,
    int quality = 75,
    int width = 720,
    int height = 1280,
    bool allowAppFallback = false,
  }) {
    if (_active) return;
    _serverUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
    _captureKey = captureKey;
    _quality = quality.clamp(10, 100);
    _capW = width;
    _capH = height;
    _allowAppFallback = allowAppFallback;
    _active = true;
    _useNative = false;

    if (Platform.isAndroid) {
      unawaited(_tryNativeStart(fps));
    } else if (_allowAppFallback) {
      _fallbackToRepaintBoundary(fps);
    } else {
      _stopWithoutCapture();
    }
  }

  Future<void> _tryNativeStart(int fps) async {
    if (!Platform.isAndroid) return;
    try {
      debugPrint(
          'PhoneScreenCapturer: requesting native screen capture permission...');

      // 先订阅事件流，以便接收权限拒绝的错误
      _nativeSub = _eventChannel.receiveBroadcastStream().listen((event) {
        if (event is Uint8List) {
          _nativeFrame = event;
        } else if (event == null) {
          // null 表示原生端已启动成功
          debugPrint(
              'PhoneScreenCapturer: native capture started successfully');
        }
      }, onError: (e) {
        debugPrint('PhoneScreenCapturer: native error - $e');
        swallowDebug(e, tag: 'PhoneScreenCapturer.native');
        _useNative = false;
        _nativeSub?.cancel();
        _nativeSub = null;
        _handleNativeUnavailable(fps);
      });

      // 调用原生方法启动屏幕捕获（会弹出系统授权对话框）
      final directUpload = _serverUrl != null && _serverUrl!.isNotEmpty;
      final started = await _methodChannel.invokeMethod<bool>('start', {
            'serverUrl': _serverUrl,
          }) ??
          false;
      if (!started || !_active) {
        _handleNativeUnavailable(fps);
        return;
      }
      _useNative = true;

      if (!directUpload) {
        // 老原生端兜底：通过 EventChannel 回传，再由 Dart 转推。
        _cameraSub =
            _cameraEventChannel.receiveBroadcastStream().listen((event) {
          if (event is Uint8List) _sendCameraFrame(event);
        }, onError: (e) {
          swallowDebug(e, tag: 'PhoneScreenCapturer.cameraEvent');
        });
      }

      // 等待用户授权结果（通过 EventChannel 返回）
      await Future.delayed(const Duration(milliseconds: 500));

      // 如果用户授权成功，启动定时器推送帧
      if (_useNative && _active && !directUpload) {
        _timer?.cancel();
        _timer = Timer.periodic(Duration(milliseconds: (1000 / fps).round()),
            (_) => _sendNativeFrame());
        debugPrint('PhoneScreenCapturer: native capture timer started');
      } else if (_useNative && _active) {
        debugPrint('PhoneScreenCapturer: native direct upload started');
      }
    } on MissingPluginException {
      debugPrint('PhoneScreenCapturer: native plugin not available');
      _handleNativeUnavailable(fps);
    } catch (e, st) {
      debugPrint('PhoneScreenCapturer: native start failed - $e');
      swallowDebug(e, tag: 'PhoneScreenCapturer.nativeStart', stack: st);
      _handleNativeUnavailable(fps);
    }
  }

  void _handleNativeUnavailable(int fps) {
    if (_allowAppFallback) {
      _fallbackToRepaintBoundary(fps);
    } else {
      _stopWithoutCapture();
    }
  }

  void _stopWithoutCapture() {
    _timer?.cancel();
    _timer = null;
    _nativeSub?.cancel();
    _nativeSub = null;
    _cameraSub?.cancel();
    _cameraSub = null;
    _nativeFrame = null;
    _useNative = false;
    _active = false;
  }

  void _fallbackToRepaintBoundary(int fps) {
    if (!_active) return;
    debugPrint('PhoneScreenCapturer: falling back to RepaintBoundary capture');
    _useNative = false;
    _nativeSub?.cancel();
    _nativeSub = null;
    _cameraSub?.cancel();
    _cameraSub = null;
    _timer?.cancel();
    final ms = (1000 / fps).round().clamp(50, 1000);
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _grabAndSend());
  }

  void stop() {
    final wasNative = _useNative;
    _active = false;
    _timer?.cancel();
    _timer = null;
    _nativeSub?.cancel();
    _nativeSub = null;
    _cameraSub?.cancel();
    _cameraSub = null;
    _nativeFrame = null;
    _useNative = false;
    if (wasNative) {
      try {
        _methodChannel.invokeMethod('stop');
      } catch (e, st) {
        swallowDebug(e, tag: 'PhoneScreenCapturer.stop', stack: st);
      }
    }
  }

  Future<void> _sendCameraFrame(Uint8List frame) async {
    if (_cameraSending || !_active || _serverUrl == null) return;
    _cameraSending = true;
    try {
      await http.post(
        Uri.parse('$_serverUrl/frame/camera'),
        body: frame,
        headers: {'Content-Type': 'image/jpeg'},
      ).timeout(const Duration(seconds: 2));
    } catch (e, st) {
      swallowDebug(e, tag: 'PhoneScreenCapturer.cameraSend', stack: st);
    } finally {
      _cameraSending = false;
    }
  }

  Future<void> _sendNativeFrame() async {
    if (!_active || _serverUrl == null) return;
    final frame = _nativeFrame;
    if (frame == null) return;
    try {
      await http.post(
        Uri.parse('$_serverUrl/frame/phone'),
        body: frame,
        headers: {'Content-Type': 'image/jpeg'},
      ).timeout(const Duration(seconds: 2));
    } catch (e, st) {
      swallowDebug(e, tag: 'PhoneScreenCapturer.native.send', stack: st);
    }
  }

  Future<void> _grabAndSend() async {
    if (_busy || !_active || _serverUrl == null) return;
    _busy = true;
    try {
      final jpeg = await _captureApp();
      if (jpeg != null && _active) {
        await http.post(
          Uri.parse('$_serverUrl/frame/phone'),
          body: jpeg,
          headers: {'Content-Type': 'image/jpeg'},
        ).timeout(const Duration(seconds: 2));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'PhoneScreenCapturer', stack: st);
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List?> _captureApp() async {
    final key = _captureKey;
    if (key == null) return null;
    try {
      final b =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (b == null) return null;
      final image = await b.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      final decoded = img.decodeImage(data.buffer.asUint8List());
      if (decoded == null) return null;
      final resized = img.copyResize(decoded, width: _capW, height: _capH);
      return img.encodeJpg(resized, quality: _quality);
    } catch (e, st) {
      swallowDebug(e, tag: 'PhoneScreenCapturer.cap', stack: st);
      return null;
    }
  }
}
