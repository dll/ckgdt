import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/init_logger.dart';

class VoicePcmCapture {
  VoicePcmCapture._(this._controller) {
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _drainNativeBuffer(),
    );
  }

  static const MethodChannel _channel = MethodChannel('mad_voice_pcm');

  final StreamController<List<int>> _controller;
  Timer? _pollTimer;
  bool _reading = false;
  bool _stopped = false;
  bool _loggedFirstData = false;

  static bool get shouldUseExternalCapture => Platform.isWindows;

  static Future<VoicePcmCapture> start() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Native PCM capture is only available on Windows');
    }

    InitLogger.logFlush('voice', 'native pcm capture start');
    await _channel.invokeMethod<bool>('start');
    return VoicePcmCapture._(StreamController<List<int>>());
  }

  Stream<List<int>> get stream => _controller.stream;

  Future<void> _drainNativeBuffer() async {
    if (_stopped || _reading) return;
    _reading = true;
    try {
      final data = await _channel.invokeMethod<Uint8List>('read');
      if (!_stopped && data != null && data.isNotEmpty) {
        if (!_loggedFirstData) {
          _loggedFirstData = true;
          InitLogger.log(
              'voice', 'native pcm capture first bytes=${data.length}');
        }
        _controller.add(data);
      }
    } catch (e, st) {
      InitLogger.error('voice', 'native pcm capture read failed: $e\n$st');
    } finally {
      _reading = false;
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    InitLogger.logFlush('voice', 'native pcm capture stop enter');
    _pollTimer?.cancel();
    _pollTimer = null;

    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e, st) {
      InitLogger.error('voice', 'native pcm capture stop failed: $e\n$st');
    }

    await _controller.close();
    InitLogger.logFlush('voice', 'native pcm capture stop done');
  }
}
