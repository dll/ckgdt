import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'sync_protocol.dart';

/// 同步客户端 — 连接到同步服务器进行认证和数据传输
///
/// 用于移动端/Web 端连接到桌面端服务器。
class SyncClient {
  String? _serverUrl;
  String? _token;
  WebSocketChannel? _wsChannel;
  Timer? _heartbeatTimer;

  String? get serverUrl => _serverUrl;
  String? get token => _token;
  bool get isConnected => _serverUrl != null;

  /// 连接状态回调
  void Function(bool connected)? onConnectionChanged;
  /// 接收到同步事件回调
  void Function(String event, Map<String, dynamic> data)? onEvent;

  // ─────────────────────────────────────────────────────────────────────────
  // 连接管理
  // ─────────────────────────────────────────────────────────────────────────

  /// 连接到服务器并登录
  Future<Map<String, dynamic>> connect({
    required String serverUrl,
    required String userId,
    String platform = 'android',
    String deviceName = 'Mobile',
  }) async {
    _serverUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;

    try {
      // 登录获取 Token
      final response = await http.post(
        Uri.parse('$_serverUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'platform': platform,
          'deviceName': deviceName,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _token = data['token'] as String?;
        _connectWebSocket();
        onConnectionChanged?.call(true);
        return {'success': true, 'data': data};
      } else {
        _serverUrl = null;
        return {
          'success': false,
          'error': '登录失败: ${response.statusCode}',
        };
      }
    } catch (e) {
      _serverUrl = null;
      return {'success': false, 'error': '连接失败: $e'};
    }
  }

  /// 断开连接
  void disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    _serverUrl = null;
    _token = null;
    onConnectionChanged?.call(false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 服务器状态检测
  // ─────────────────────────────────────────────────────────────────────────

  /// 测试服务器是否可达
  static Future<Map<String, dynamic>?> checkServer(String serverUrl) async {
    try {
      final url = serverUrl.endsWith('/')
          ? '${serverUrl}api/status'
          : '$serverUrl/api/status';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QR 码扫描登录
  // ─────────────────────────────────────────────────────────────────────────

  /// 确认 QR 登录（移动端扫码后调用）
  ///
  /// [qrData] 从 QR 码解析出的 JSON：{ host, port, qrToken }
  /// [userId] / [realName] / [role] 移动端当前登录用户信息
  /// [syncData] 可选，随登录一起推送的同步数据
  Future<Map<String, dynamic>> confirmQrLogin({
    required String serverUrl,
    required String qrToken,
    required String userId,
    required String realName,
    required String role,
    Map<String, dynamic>? syncData,
  }) async {
    try {
      final url = serverUrl.endsWith('/')
          ? '${serverUrl}api/auth/qr-confirm'
          : '$serverUrl/api/auth/qr-confirm';

      final body = <String, dynamic>{
        'qrToken': qrToken,
        'userId': userId,
        'realName': realName,
        'role': role,
      };
      if (syncData != null) {
        body['syncData'] = syncData;
      }

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // 自动连接到服务器
        _serverUrl = serverUrl;
        return {'success': true};
      } else {
        final err = jsonDecode(response.body);
        return {
          'success': false,
          'error': err['error'] ?? '确认失败',
        };
      }
    } catch (e) {
      return {'success': false, 'error': '请求失败: $e'};
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 数据同步
  // ─────────────────────────────────────────────────────────────────────────

  /// 从服务器拉取用户数据
  Future<Map<String, dynamic>?> pullUserData(String userId) async {
    if (_serverUrl == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/sync/pull?userId=$userId'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('SyncClient: pull error: $e');
    }
    return null;
  }

  /// 从服务器拉取公共数据（图谱、题库等）
  Future<Map<String, dynamic>?> pullSharedData() async {
    if (_serverUrl == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/sync/pull-shared'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('SyncClient: pull-shared error: $e');
    }
    return null;
  }

  /// 从服务器拉取全量数据（管理员）
  Future<Map<String, dynamic>?> pullFullData() async {
    if (_serverUrl == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/sync/pull-full'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('SyncClient: pull-full error: $e');
    }
    return null;
  }

  /// 向服务器推送用户数据
  Future<bool> pushUserData(String userId) async {
    if (_serverUrl == null) return false;
    try {
      final data = await SyncProtocol.exportUserData(userId);
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/sync/push'),
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SyncClient: push error: $e');
      return false;
    }
  }

  /// 向服务器推送全量数据（管理员）
  Future<bool> pushFullData() async {
    if (_serverUrl == null) return false;
    try {
      final data = await SyncProtocol.exportFullData();
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/sync/push'),
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 60));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SyncClient: push-full error: $e');
      return false;
    }
  }

  /// 获取已连接设备列表
  Future<List<Map<String, dynamic>>> getDevices() async {
    if (_serverUrl == null) return [];
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/devices'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final devices = data['devices'] as List<dynamic>? ?? [];
        return devices.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WebSocket 实时通道
  // ─────────────────────────────────────────────────────────────────────────

  void _connectWebSocket() {
    if (_serverUrl == null) return;
    try {
      final wsUrl = '${_serverUrl!.replaceFirst('http', 'ws')}/api/ws';
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _wsChannel!.stream.listen(
        (message) {
          try {
            if (message == 'pong') return;
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            final event = data['event'] as String? ?? '';
            final payload =
                data['data'] as Map<String, dynamic>? ?? {};
            onEvent?.call(event, payload);
          } catch (_) {}
        },
        onError: (_) => _reconnectWebSocket(),
        onDone: () => _reconnectWebSocket(),
      );

      // 心跳
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          try {
            _wsChannel?.sink.add('ping');
          } catch (_) {
            _reconnectWebSocket();
          }
        },
      );
    } catch (e) {
      debugPrint('SyncClient: WebSocket 连接失败: $e');
    }
  }

  void _reconnectWebSocket() {
    _heartbeatTimer?.cancel();
    Future.delayed(const Duration(seconds: 3), () {
      if (_serverUrl != null) _connectWebSocket();
    });
  }

  Map<String, String> get _authHeaders => {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
}
