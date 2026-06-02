import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../core/error_handler.dart';

/// 手机端屏幕捕获 — 捕获自身 App 内容，发送到教师流服务器。
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

  bool get isActive => _active;

  void start(String baseUrl, GlobalKey captureKey, {
    int fps = 10, int quality = 75,
    int width = 720, int height = 1280,
  }) {
    if (_active) return;
    _serverUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
    _captureKey = captureKey;
    _quality = quality.clamp(10, 100);
    _capW = width; _capH = height;
    _active = true;
    final ms = (1000 / fps).round().clamp(50, 1000);
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _grabAndSend());
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _grabAndSend() async {
    if (_busy || !_active || _serverUrl == null) return;
    _busy = true;
    try {
      final jpeg = await _capture();
      if (jpeg != null && _active) {
        await http.post(
          Uri.parse('$_serverUrl/frame/phone'),
          body: jpeg,
          headers: {'Content-Type': 'image/jpeg'},
        ).timeout(const Duration(seconds: 2));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'PhoneScreenCapturer', stack: st);
    } finally { _busy = false; }
  }

  Future<Uint8List?> _capture() async {
    final key = _captureKey;
    if (key == null) return null;
    try {
      final b = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
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
