import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Flutter TTS 封装 — 实时语音合成（中文）
///
/// 支持 Windows / Android / iOS，用于智能体回复的语音朗读。
/// 新电脑可能缺少 TTS 引擎（如 Windows SAPI5 中文语音），
/// 此服务会在初始化失败时安全降级，不会导致应用崩溃。
class TtsFlutterService {
  static final TtsFlutterService instance = TtsFlutterService._();
  TtsFlutterService._();

  FlutterTts? _tts;
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _enabled = true; // TTS 开关
  bool _available = true; // TTS 引擎是否可用

  bool get isSpeaking => _isSpeaking;
  bool get isEnabled => _enabled;
  bool get isAvailable => _available;
  set enabled(bool value) => _enabled = value;

  /// 获取上次初始化失败的原因（供 UI 显示）
  String? _lastError;
  String? get lastError => _lastError;

  /// 初始化 TTS 引擎
  ///
  /// 在 Windows 上需要安装 SAPI5 语音引擎（中文或英文均可）。
  /// 初始化失败时标记为不可用，后续 speak() 静默跳过。
  Future<void> initialize() async {
    if (_initialized) return;

    // Web 平台不支持 flutter_tts
    if (kIsWeb) {
      _available = false;
      _lastError = 'Web 平台暂不支持语音合成';
      _initialized = true;
      debugPrint('TtsFlutterService: Web 平台，TTS 不可用');
      return;
    }

    try {
      _tts = FlutterTts();

      // Windows: 先检查可用引擎/语言
      if (defaultTargetPlatform == TargetPlatform.windows) {
        try {
          final languages = await _tts!.getLanguages;
          final langList = languages is List ? languages.cast<String>() : <String>[];
          debugPrint('TtsFlutterService: 可用语言: $langList');

          if (langList.isEmpty) {
            _available = false;
            _lastError = '未检测到 TTS 语音引擎，请安装 Windows 语音包';
            _initialized = true;
            _tts = null;
            debugPrint('TtsFlutterService: Windows 无可用 TTS 语音');
            return;
          }

          // 优先中文，降级到英文，再降级到任意可用语言
          final hasChinese = langList.any(
              (l) => l.toLowerCase().contains('zh') || l.toLowerCase().contains('chinese'));
          final hasEnglish = langList.any(
              (l) => l.toLowerCase().contains('en'));

          if (hasChinese) {
            await _tts!.setLanguage('zh-CN');
          } else if (hasEnglish) {
            await _tts!.setLanguage('en-US');
            _lastError = '未安装中文语音包，将使用英文语音';
            debugPrint('TtsFlutterService: 无中文语音，降级为英文');
          } else {
            await _tts!.setLanguage(langList.first);
            _lastError = '未找到中文/英文语音，使用: ${langList.first}';
            debugPrint('TtsFlutterService: 降级为 ${langList.first}');
          }
        } catch (e) {
          debugPrint('TtsFlutterService: 获取语言列表失败: $e');
          // 仍然尝试初始化
          try {
            await _tts!.setLanguage('zh-CN');
          } catch (_) {
            // 忽略语言设置失败
          }
        }
      } else {
        // Android / iOS / macOS / Linux
        await _tts!.setLanguage('zh-CN');
      }

      // 设置语音参数
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

      _available = true;
      _initialized = true;
      debugPrint('TtsFlutterService: 初始化成功');
    } catch (e) {
      _available = false;
      _lastError = '语音合成引擎初始化失败: $e';
      _initialized = true;
      _tts = null;
      debugPrint('TtsFlutterService: 初始化失败: $e');
    }
  }

  /// 朗读文本
  ///
  /// 如果 TTS 引擎不可用，静默返回不会崩溃。
  Future<void> speak(String text) async {
    if (!_enabled || text.isEmpty) return;
    if (!_initialized) await initialize();
    if (!_available || _tts == null) return;

    try {
      // 如果正在朗读，先停止
      if (_isSpeaking) {
        await _tts!.stop();
      }
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      // 标记为不可用，避免后续重复失败
      _available = false;
      _lastError = '语音合成失败: $e';
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

  /// 重新初始化（用户安装语音包后重试）
  Future<void> reinitialize() async {
    await dispose();
    _available = true;
    _lastError = null;
    await initialize();
  }
}
