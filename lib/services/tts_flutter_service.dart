import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Flutter TTS 封装 — 实时语音合成（中文）
///
/// 支持 Windows / Android / iOS，用于智能体回复的语音朗读。
class TtsFlutterService {
  static final TtsFlutterService instance = TtsFlutterService._();
  TtsFlutterService._();

  FlutterTts? _tts;
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _enabled = true; // TTS 开关

  bool get isSpeaking => _isSpeaking;
  bool get isEnabled => _enabled;
  set enabled(bool value) => _enabled = value;

  /// 初始化 TTS 引擎
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _tts = FlutterTts();

      // 设置中文语音参数
      await _tts!.setLanguage('zh-CN');
      await _tts!.setSpeechRate(0.5); // 语速（0.0-1.0）
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);

      // 监听状态
      _tts!.setStartHandler(() {
        _isSpeaking = true;
      });
      _tts!.setCompletionHandler(() {
        _isSpeaking = false;
      });
      _tts!.setCancelHandler(() {
        _isSpeaking = false;
      });
      _tts!.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint('TTS error: $msg');
      });

      _initialized = true;
      debugPrint('TtsFlutterService: 初始化成功');
    } catch (e) {
      debugPrint('TtsFlutterService: 初始化失败: $e');
    }
  }

  /// 朗读文本
  Future<void> speak(String text) async {
    if (!_enabled || text.isEmpty) return;
    if (!_initialized) await initialize();
    if (_tts == null) return;

    try {
      // 如果正在朗读，先停止
      if (_isSpeaking) {
        await _tts!.stop();
      }
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  /// 停止朗读
  Future<void> stop() async {
    if (_tts == null) return;
    try {
      await _tts!.stop();
      _isSpeaking = false;
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await stop();
    _tts = null;
    _initialized = false;
  }
}
