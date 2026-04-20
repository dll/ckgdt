import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Stub RecordLinux that implements all required methods for OHOS builds.
class RecordLinux extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordLinux();
  }

  RecordState _state = RecordState.stop;
  StreamController<RecordState>? _stateStreamCtrl;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {
    _stateStreamCtrl?.close();
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) {
    return Future.value(Amplitude(current: -160.0, max: -160.0));
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = false}) {
    return Future.value(false);
  }

  @override
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder) {
    return Future.value(false);
  }

  @override
  Future<bool> isPaused(String recorderId) {
    return Future.value(_state == RecordState.pause);
  }

  @override
  Future<bool> isRecording(String recorderId) {
    return Future.value(_state == RecordState.record);
  }

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) async {
    throw UnsupportedError('Recording not supported on this platform');
  }

  @override
  Future<Stream<Uint8List>> startStream(String recorderId, RecordConfig config) async {
    throw UnsupportedError('Stream recording not supported on this platform');
  }

  @override
  Future<String?> stop(String recorderId) async {
    return null;
  }

  @override
  Future<void> cancel(String recorderId) async {}

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async {
    return [];
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    _stateStreamCtrl ??= StreamController(
      onCancel: () {
        _stateStreamCtrl?.close();
        _stateStreamCtrl = null;
      },
    );
    return _stateStreamCtrl!.stream;
  }
}
