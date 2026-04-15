import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/settings_service.dart';

/// 讯飞语音听写（IAT）服务
///
/// 通过 WebSocket 流式将麦克风音频发送到讯飞云端，实时返回识别文本。
/// 音频格式：16kHz / 16bit / 单声道 PCM。
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
  // 公开 API
  // ═══════════════════════════════════════════════════════════════════════

  /// 开始语音识别
  Future<bool> startListening() async {
    if (_isListening) return true;

    // 读取讯飞配置
    final appId = await SettingsService.getXunfeiAppId();
    final apiKey = await SettingsService.getXunfeiApiKey();
    final apiSecret = await SettingsService.getXunfeiApiSecret();

    if (appId.isEmpty || apiKey.isEmpty || apiSecret.isEmpty) {
      onError?.call('请先在系统设置中配置讯飞语音参数');
      return false;
    }

    try {
      // 1) 连接讯飞 WebSocket
      final authUrl = _generateAuthUrl(apiKey, apiSecret);
      _wsChannel = WebSocketChannel.connect(Uri.parse(authUrl));
      _fullText.clear();
      _firstFrame = true;

      _wsChannel!.stream.listen(
        _onWsMessage,
        onError: (e) {
          onError?.call('WebSocket 错误: $e');
          stopListening();
        },
        onDone: () {
          if (_isListening) stopListening();
        },
      );

      // 2) 开始录音
      _recorder = AudioRecorder();
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        onError?.call('未授予麦克风权限');
        _cleanup();
        return false;
      }

      final stream = await _recorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
      );

      _isListening = true;
      onStateChanged?.call(true);

      // 3) 流式发送音频到讯飞
      _audioSub = stream.listen((audioData) {
        _sendAudioFrame(audioData, appId);
      });

      return true;
    } catch (e) {
      onError?.call('启动语音识别失败: $e');
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
      await _recorder?.stop();

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

  /// 检查讯飞配置是否完整
  static Future<bool> isConfigured() async {
    final appId = await SettingsService.getXunfeiAppId();
    final apiKey = await SettingsService.getXunfeiApiKey();
    final apiSecret = await SettingsService.getXunfeiApiSecret();
    return appId.isNotEmpty && apiKey.isNotEmpty && apiSecret.isNotEmpty;
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
    _audioSub?.cancel();
    _audioSub = null;
    _recorder?.stop();
    _recorder?.dispose();
    _recorder = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    _isListening = false;
    _firstFrame = true;
    onStateChanged?.call(false);
  }
}
