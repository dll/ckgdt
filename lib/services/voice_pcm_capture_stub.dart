class VoicePcmCapture {
  static bool get shouldUseExternalCapture => false;

  static Future<VoicePcmCapture> start() {
    throw UnsupportedError('External PCM capture is not available');
  }

  Stream<List<int>> get stream => const Stream<List<int>>.empty();

  Future<void> stop() async {}
}
