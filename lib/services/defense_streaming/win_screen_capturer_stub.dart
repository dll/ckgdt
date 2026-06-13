import 'dart:typed_data';

/// Stub — Windows-only, always returns null on other platforms.
class WinScreenCapturer {
  WinScreenCapturer._();
  static final WinScreenCapturer instance = WinScreenCapturer._();

  final bool _ready = false;
  bool get isReady => _ready;

  void initialize({int width = 1280, int height = 720, int quality = 80}) {}
  void minimizeForegroundWindow() {}
  Future<Uint8List?> capture() async => null;
  void updateSize({int? width, int? height, int? quality}) {}
}
