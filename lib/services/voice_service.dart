import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/init_logger.dart';
import '../services/settings_service.dart';

/// 讯飞语音听写（IAT）服务
///
/// 通过 WebSocket 流式将麦克风音频发送到讯飞云端，实时返回识别文本。
/// 音频格式：16kHz / 16bit / 单声道 PCM。
///
/// 注意：
/// - Web 平台不支持 `record` 包的流式录音
/// - Windows 桌面端需要麦克风驱动，新电脑可能缺少
/// - 所有平台异常均通过 onError 回调通知 UI，不会崩溃
class VoiceService {
  static final VoiceService _instance = VoiceService._();
  factory VoiceService() => _instance;
  VoiceService._();

  // ── 讯飞 IAT WebSocket 地址 ───────────────────────────────────────────
  static const _iatHost = 'iat-api.xfyun.cn';
  static const _iatPath = '/v2/iat';

  // ── 录音器 ────────────────────────────────────────────────────────────
  AudioRecorder? _recorder;
  StreamSubscription<List<int>>? _audioSub;
  WebSocketChannel? _wsChannel;
  bool _isListening = false;
  bool _firstFrame = true;
  final StringBuffer _fullText = StringBuffer();

  bool get isListening => _isListening;

  // ── 回调 ──────────────────────────────────────────────────────────────
  /// 每收到一段识别结果时调用（累积全文）
  void Function(String text)? onResult;
  /// 识别结束
  void Function(String finalText)? onComplete;
  /// 错误
  void Function(String error)? onError;
  /// 状态变化（录音中 / 停止）
  void Function(bool listening)? onStateChanged;

  // ═══════════════════════════════════════════════════════════════════════
  // 平台支持检查
  // ═══════════════════════════════════════════════════════════════════════

  /// 检查当前平台是否支持语音录制
  static bool get isPlatformSupported {
    if (kIsWeb) return false; // Web 不支持流式录音
    // Windows / Android / iOS / macOS / Linux 均支持 record 包
    return true;
  }

  /// 检查讯飞配置是否完整
  static Future<bool> isConfigured() async {
    if (!isPlatformSupported) return false;
    // 用户主动禁用语音 → 上层 UI 视为"未配置"，避免点了崩
    if (await SettingsService.isVoiceDisabled()) return false;
    final appId = await SettingsService.getXunfeiAppId();
    final apiKey = await SettingsService.getXunfeiApiKey();
    final apiSecret = await SettingsService.getXunfeiApiSecret();
    return appId.isNotEmpty && apiKey.isNotEmpty && apiSecret.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 公开 API
  // ═══════════════════════════════════════════════════════════════════════

  /// 开始语音识别
  Future<bool> startListening() async {
    InitLogger.logFlush('voice', 'startListening called isListening=$_isListening');
    if (_isListening) return true;

    // 平台检查
    if (kIsWeb) {
      onError?.call('Web 平台暂不支持语音输入');
      return false;
    }

    // 应急开关 — 用户主动关掉了语音（避开 record 包原生层偶发崩溃）
    if (await SettingsService.isVoiceDisabled()) {
      InitLogger.log('voice', 'voice disabled by user setting');
      onError?.call('语音功能已被禁用 — 系统设置 → 语音设置 中可重新开启');
      return false;
    }

    // 读取讯飞配置
    final appId = await SettingsService.getXunfeiAppId();
    final apiKey = await SettingsService.getXunfeiApiKey();
    final apiSecret = await SettingsService.getXunfeiApiSecret();

    if (appId.isEmpty || apiKey.isEmpty || apiSecret.isEmpty) {
      onError?.call('请先在系统设置中配置讯飞语音参数');
      return false;
    }

    try {
      // 1) 创建录音器（先 try，失败立即报错给 UI，避免后面的网络握手白做）
      InitLogger.logFlush('voice', 'about to: new AudioRecorder()');
      try {
        _recorder = AudioRecorder();
        InitLogger.log('voice', 'AudioRecorder() ok');
      } catch (e, st) {
        onError?.call('无法初始化录音设备，请检查麦克风驱动是否安装');
        InitLogger.error('voice', 'AudioRecorder ctor failed: $e', st);
        return false;
      }

      // 2) 检查麦克风权限（也是预检 — 没权限直接退出，不走原生 startStream）
      InitLogger.logFlush('voice', 'about to: hasPermission()');
      bool hasPermission = false;
      try {
        hasPermission = await _recorder!.hasPermission();
        InitLogger.log('voice', 'hasPermission = $hasPermission');
      } catch (e, st) {
        onError?.call('麦克风初始化失败，请检查音频驱动是否正常安装');
        InitLogger.error('voice', 'hasPermission failed: $e', st);
        _cleanup();
        return false;
      }

      if (!hasPermission) {
        onError?.call('未授予麦克风权限');
        _cleanup();
        return false;
      }

      // 3) 连接讯飞 WebSocket
      InitLogger.logFlush('voice', 'about to: WebSocket connect');
      final authUrl = _generateAuthUrl(apiKey, apiSecret);
      _wsChannel = WebSocketChannel.connect(Uri.parse(authUrl));
      InitLogger.log('voice', 'WebSocket connect returned (channel created)');
      _fullText.clear();
      _firstFrame = true;

      _wsChannel!.stream.listen(
        _onWsMessage,
        onError: (e) {
          InitLogger.log('voice', 'WS onError: $e');
          onError?.call('WebSocket 错误: $e');
          stopListening();
        },
        onDone: () {
          InitLogger.log('voice', 'WS onDone');
          if (_isListening) stopListening();
        },
      );

      // 4) 开始流式录音
      InitLogger.logFlush('voice', 'about to: startStream()');
      Stream<List<int>> stream;
      try {
        stream = await _recorder!.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 256000,
          ),
        );
        InitLogger.log('voice', 'startStream returned');
      } catch (e, st) {
        onError?.call('启动录音失败，请检查麦克风是否正常连接');
        InitLogger.error('voice', 'startStream failed: $e', st);
        _cleanup();
        return false;
      }

      _isListening = true;
      onStateChanged?.call(true);

      // 5) 流式发送音频到讯飞
      _audioSub = stream.listen(
        (audioData) {
          _sendAudioFrame(audioData, appId);
        },
        onError: (e) {
          InitLogger.log('voice', 'audio stream onError: $e');
          onError?.call('录音异常: $e');
          stopListening();
        },
      );

      InitLogger.log('voice', 'startListening complete (listening=true)');
      return true;
    } catch (e, st) {
      onError?.call('启动语音识别失败: $e');
      InitLogger.error('voice', 'startListening outer exception: $e', st);
      _cleanup();
      return false;
    }
  }

  /// 停止语音识别
  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;

    try {
      // 停止录音
      await _audioSub?.cancel();
      _audioSub = null;
      try {
        await _recorder?.stop();
      } catch (e) {
        debugPrint('VoiceService: recorder.stop error: $e');
      }

      // 发送最后一帧
      _sendLastFrame();

      // 等待识别结果回来后 WebSocket 会自动关闭
      // 设置超时兜底
      Future.delayed(const Duration(seconds: 5), () {
        _cleanup();
      });
    } catch (e) {
      debugPrint('VoiceService: stop error: $e');
      _cleanup();
    }

    onStateChanged?.call(false);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════════════════════════════════

  /// 生成讯飞鉴权 URL（HMAC-SHA256 签名）
  String _generateAuthUrl(String apiKey, String apiSecret) {
    final now = DateTime.now().toUtc();
    final dateFormat = DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
    final date = dateFormat.format(now);

    // 签名原文
    const signatureOrigin =
        'host: $_iatHost\ndate: {date}\nGET $_iatPath HTTP/1.1';
    final origin = signatureOrigin.replaceFirst('{date}', date);

    // HMAC-SHA256
    final hmacSha256 = Hmac(sha256, utf8.encode(apiSecret));
    final signatureDigest = hmacSha256.convert(utf8.encode(origin));
    final signature = base64.encode(signatureDigest.bytes);

    // authorization
    final authOrigin = 'api_key="$apiKey", algorithm="hmac-sha256", '
        'headers="host date request-line", signature="$signature"';
    final authorization = base64.encode(utf8.encode(authOrigin));

    // 拼接 URL
    final params = {
      'authorization': authorization,
      'date': date,
      'host': _iatHost,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'wss://$_iatHost$_iatPath?$query';
  }

  void _sendAudioFrame(List<int> audioData, String appId) {
    if (_wsChannel == null) return;

    if (_firstFrame) {
      _firstFrame = false;
      final frame = {
        'common': {'app_id': appId},
        'business': {
          'language': 'zh_cn',
          'domain': 'iat',
          'accent': 'mandarin',
          'vad_eos': 3000,
          'ptt': 1,
        },
        'data': {
          'status': 0,
          'format': 'audio/L16;rate=16000',
          'encoding': 'raw',
          'audio': base64.encode(audioData),
        },
      };
      _wsChannel!.sink.add(jsonEncode(frame));
    } else {
      final frame = {
        'data': {
          'status': 1,
          'format': 'audio/L16;rate=16000',
          'encoding': 'raw',
          'audio': base64.encode(audioData),
        },
      };
      _wsChannel!.sink.add(jsonEncode(frame));
    }
  }

  void _sendLastFrame() {
    if (_wsChannel == null) return;
    final frame = {
      'data': {
        'status': 2,
        'format': 'audio/L16;rate=16000',
        'encoding': 'raw',
        'audio': '',
      },
    };
    _wsChannel!.sink.add(jsonEncode(frame));
  }

  void _onWsMessage(dynamic message) {
    try {
      final response = jsonDecode(message as String) as Map<String, dynamic>;
      final code = response['code'] as int? ?? -1;

      if (code != 0) {
        final msg = response['message'] ?? '未知错误';
        onError?.call('讯飞错误 [$code]: $msg');
        _cleanup();
        return;
      }

      final data = response['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final result = data['result'] as Map<String, dynamic>?;
      final status = data['status'] as int? ?? 0;

      if (result != null) {
        final text = _parseResult(result);
        if (text.isNotEmpty) {
          _fullText.write(text);
          onResult?.call(_fullText.toString());
        }
      }

      if (status == 2) {
        onComplete?.call(_fullText.toString());
        _cleanup();
      }
    } catch (e) {
      debugPrint('VoiceService: parse error: $e');
    }
  }

  /// 解析讯飞返回的分词结果
  String _parseResult(Map<String, dynamic> result) {
    final ws = result['ws'] as List<dynamic>?;
    if (ws == null) return '';
    final buf = StringBuffer();
    for (final item in ws) {
      final cw = (item as Map<String, dynamic>)['cw'] as List<dynamic>?;
      if (cw != null && cw.isNotEmpty) {
        buf.write((cw[0] as Map<String, dynamic>)['w'] ?? '');
      }
    }
    return buf.toString();
  }

  void _cleanup() {
    try { _audioSub?.cancel(); } catch (_) {}
    _audioSub = null;
    try { _recorder?.stop(); } catch (_) {}
    try { _recorder?.dispose(); } catch (_) {}
    _recorder = null;
    try { _wsChannel?.sink.close(); } catch (_) {}
    _wsChannel = null;
    _isListening = false;
    _firstFrame = true;
    onStateChanged?.call(false);
  }
}
