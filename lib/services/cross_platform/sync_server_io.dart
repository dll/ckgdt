import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'session_manager.dart';
import 'sync_protocol.dart';

/// 嵌入式同步服务器 — 基于 dart:io HttpServer
///
/// 功能：
/// - REST API：认证、数据同步、QR 登录
/// - WebSocket：实时通知已连接客户端
/// - 静态文件：（可选）提供 Flutter Web 构建产物
///
/// 路由表：
/// ```
/// GET  /api/status                      → 服务器状态
/// POST /api/auth/login                  → 账号密码登录
/// POST /api/auth/qr-confirm             → 移动端确认 QR 登录
/// GET  /api/auth/qr-check/:token        → 桌面端轮询 QR 状态
/// GET  /api/sync/pull?userId=X          → 拉取用户数据
/// GET  /api/sync/pull-shared            → 拉取公共数据
/// GET  /api/sync/pull-full              → 拉取全量数据（管理员）
/// POST /api/sync/push                   → 推送数据到服务器
/// GET  /api/devices                     → 已连接设备列表
/// WS   /api/ws                          → WebSocket 实时通道
/// ```
class SyncServerImpl {
  HttpServer? _server;
  final SessionManager _sessionManager = SessionManager();
  final List<WebSocket> _wsClients = [];

  bool get isRunning => _server != null;
  String? _host;
  String? get host => _host;
  int _port = 8765;
  int get port => _port;
  String? get serverUrl => isRunning ? 'http://$_host:$_port' : null;

  SessionManager get sessionManager => _sessionManager;

  // 登录回调：服务端收到 QR 确认后通知 UI
  void Function(String userId, String realName, String role)? onQrLoginConfirmed;
  // 数据推送回调：客户端推送数据后通知 UI 刷新
  void Function(String userId)? onDataPushed;

  // ─────────────────────────────────────────────────────────────────────────
  // 服务器生命周期
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> start({int port = 8765}) async {
    if (_server != null) return;

    _host = await getLocalIp() ?? '127.0.0.1';
    _port = port;

    // 尝试绑定端口（失败自动递增，最多尝试20次）
    for (int attempt = 0; attempt < 20; attempt++) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          _port,
          shared: true,
        );
        break;
      } on SocketException {
        _port++;
      }
    }

    if (_server == null) {
      throw StateError('无法绑定任何端口（$port–${_port}）');
    }

    debugPrint('SyncServer: 启动于 http://$_host:$_port');
    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('SyncServer: 连接错误 $e');
    });
  }

  Future<void> stop() async {
    for (final ws in _wsClients) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _wsClients.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint('SyncServer: 已停止');
  }

  /// 获取本机局域网 IP
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      // 兜底：返回第一个非回环地址
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      debugPrint('SyncServer: 获取本机 IP 失败 $e');
    }
    return null;
  }

  /// 广播 WebSocket 消息给所有已连接客户端
  void broadcast(String event, [Map<String, dynamic>? data]) {
    final msg = jsonEncode({'event': event, 'data': data ?? {}});
    final stale = <WebSocket>[];
    for (final ws in _wsClients) {
      try {
        ws.add(msg);
      } catch (_) {
        stale.add(ws);
      }
    }
    for (final ws in stale) {
      _wsClients.remove(ws);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 请求路由
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    // CORS 头
    request.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..add('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (path == '/api/ws') {
        await _handleWebSocket(request);
      } else if (path.startsWith('/api/')) {
        await _handleApi(request);
      } else {
        // 静态文件或 404
        await _handleStatic(request);
      }
    } catch (e) {
      debugPrint('SyncServer: 处理请求错误 $path: $e');
      _jsonResponse(request.response, 500, {'error': '$e'});
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // API 路由处理
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleApi(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // GET /api/status
    if (path == '/api/status' && method == 'GET') {
      _jsonResponse(request.response, 200, {
        'status': 'online',
        'version': SyncProtocol.protocolVersion,
        'connectedDevices': _sessionManager.connectedDevices.length,
        'wsClients': _wsClients.length,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    // POST /api/auth/login
    if (path == '/api/auth/login' && method == 'POST') {
      await _handleLogin(request);
      return;
    }

    // POST /api/auth/qr-confirm
    if (path == '/api/auth/qr-confirm' && method == 'POST') {
      await _handleQrConfirm(request);
      return;
    }

    // GET /api/auth/qr-check/:token
    if (path.startsWith('/api/auth/qr-check/') && method == 'GET') {
      final qrToken = path.substring('/api/auth/qr-check/'.length);
      final session = _sessionManager.checkQrSession(qrToken);
      if (session == null) {
        _jsonResponse(request.response, 404, {'error': 'QR 会话不存在或已过期'});
      } else {
        _jsonResponse(request.response, 200, session.toJson());
      }
      return;
    }

    // ── 以下接口需要 Token 认证 ──

    final authHeader = request.headers.value('Authorization');
    final token = authHeader?.replaceFirst('Bearer ', '');
    _sessionManager.validateToken(token ?? '');

    // GET /api/devices
    if (path == '/api/devices' && method == 'GET') {
      _jsonResponse(request.response, 200, {
        'devices': _sessionManager.connectedDevices
            .map((d) => d.toJson())
            .toList(),
      });
      return;
    }

    // GET /api/sync/pull?userId=X
    if (path == '/api/sync/pull' && method == 'GET') {
      final userId = request.uri.queryParameters['userId'];
      if (userId == null || userId.isEmpty) {
        _jsonResponse(request.response, 400, {'error': '缺少 userId 参数'});
        return;
      }
      final data = await SyncProtocol.exportUserData(userId);
      _jsonResponse(request.response, 200, data);
      return;
    }

    // GET /api/sync/pull-shared
    if (path == '/api/sync/pull-shared' && method == 'GET') {
      final data = await SyncProtocol.exportSharedData();
      _jsonResponse(request.response, 200, data);
      return;
    }

    // GET /api/sync/pull-full
    if (path == '/api/sync/pull-full' && method == 'GET') {
      final data = await SyncProtocol.exportFullData();
      _jsonResponse(request.response, 200, data);
      return;
    }

    // POST /api/sync/push
    if (path == '/api/sync/push' && method == 'POST') {
      await _handlePush(request);
      return;
    }

    _jsonResponse(request.response, 404, {'error': '未知接口: $path'});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 认证处理
  // ─────────────────────────────────────────────────────────────────────────

  /// 账号密码登录
  Future<void> _handleLogin(HttpRequest request) async {
    final body = await _readJsonBody(request);
    if (body == null) {
      _jsonResponse(request.response, 400, {'error': '无效的 JSON 请求体'});
      return;
    }

    final userId = body['userId'] as String? ?? '';
    final platform = body['platform'] as String? ?? 'unknown';
    final deviceName = body['deviceName'] as String? ?? 'unknown';

    if (userId.isEmpty) {
      _jsonResponse(request.response, 400, {'error': '缺少 userId'});
      return;
    }

    // 颁发 Token
    final token = _sessionManager.issueDeviceToken(
      userId: userId,
      deviceName: deviceName,
      platform: platform,
    );

    broadcast('device_connected', {
      'userId': userId,
      'platform': platform,
      'deviceName': deviceName,
    });

    _jsonResponse(request.response, 200, {
      'token': token,
      'userId': userId,
    });
  }

  /// 移动端确认 QR 登录
  Future<void> _handleQrConfirm(HttpRequest request) async {
    final body = await _readJsonBody(request);
    if (body == null) {
      _jsonResponse(request.response, 400, {'error': '无效请求体'});
      return;
    }

    final qrToken = body['qrToken'] as String? ?? '';
    final userId = body['userId'] as String? ?? '';
    final realName = body['realName'] as String? ?? '';
    final role = body['role'] as String? ?? 'student';

    if (qrToken.isEmpty || userId.isEmpty) {
      _jsonResponse(request.response, 400, {'error': '缺少 qrToken 或 userId'});
      return;
    }

    final ok = _sessionManager.confirmQrLogin(
      qrToken: qrToken,
      userId: userId,
      realName: realName,
      role: role,
    );

    if (ok) {
      // 通知桌面端 QR 已确认
      broadcast('qr_login_confirmed', {
        'userId': userId,
        'realName': realName,
        'role': role,
      });

      onQrLoginConfirmed?.call(userId, realName, role);

      // 同时推送移动端的数据到服务器
      if (body.containsKey('syncData')) {
        try {
          final syncData = body['syncData'] as Map<String, dynamic>;
          await SyncProtocol.importData(syncData);
          broadcast('data_synced', {'userId': userId});
          onDataPushed?.call(userId);
        } catch (e) {
          debugPrint('SyncServer: QR 登录数据同步错误: $e');
        }
      }

      _jsonResponse(request.response, 200, {'success': true});
    } else {
      _jsonResponse(
          request.response, 400, {'error': 'QR 会话无效、已过期或已使用'});
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 数据同步处理
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handlePush(HttpRequest request) async {
    final body = await _readJsonBody(request);
    if (body == null) {
      _jsonResponse(request.response, 400, {'error': '无效请求体'});
      return;
    }

    try {
      final stats = await SyncProtocol.importData(body);
      final userId = body['userId'] as String?;
      if (userId != null) {
        broadcast('data_synced', {'userId': userId});
        onDataPushed?.call(userId);
      }
      _jsonResponse(request.response, 200, {
        'success': true,
        'imported': stats,
      });
    } catch (e) {
      _jsonResponse(request.response, 500, {'error': '导入失败: $e'});
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WebSocket
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleWebSocket(HttpRequest request) async {
    try {
      final ws = await WebSocketTransformer.upgrade(request);
      _wsClients.add(ws);
      debugPrint('SyncServer: WebSocket 客户端连接 (${_wsClients.length} total)');

      ws.listen(
        (data) {
          // 收到心跳或指令
          if (data == 'ping') {
            ws.add('pong');
          }
        },
        onDone: () {
          _wsClients.remove(ws);
          debugPrint(
              'SyncServer: WebSocket 客户端断开 (${_wsClients.length} total)');
        },
        onError: (_) => _wsClients.remove(ws),
      );
    } catch (e) {
      debugPrint('SyncServer: WebSocket 升级失败: $e');
      _jsonResponse(request.response, 400, {'error': 'WebSocket 升级失败'});
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 静态文件服务（Flutter Web 构建产物）
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleStatic(HttpRequest request) async {
    // 尝试在多个可能的位置查找 Flutter Web 构建产物
    var filePath = request.uri.path;
    if (filePath == '/') filePath = '/index.html';

    // 按优先级搜索 web 构建目录
    final webDir = await _findWebBuildDir();
    if (webDir == null) {
      _jsonResponse(request.response, 404, {
        'error': 'Flutter Web 尚未构建',
        'hint': '请先运行 flutter build web',
      });
      return;
    }

    final file = File('${webDir.path}$filePath');
    if (await file.exists()) {
      final ext = filePath.split('.').last.toLowerCase();
      request.response.headers.contentType = _mimeType(ext);
      await file.openRead().pipe(request.response);
    } else {
      // SPA fallback → index.html
      final index = File('${webDir.path}/index.html');
      if (await index.exists()) {
        request.response.headers.contentType = ContentType.html;
        await index.openRead().pipe(request.response);
      } else {
        _jsonResponse(request.response, 404, {'error': 'Not Found'});
      }
    }
  }

  /// 在多个路径中查找 Flutter Web 构建目录
  Future<Directory?> _findWebBuildDir() async {
    // 1) 相对于当前工作目录（开发模式: flutter run）
    final cwd = Directory('build/web');
    if (await cwd.exists()) return cwd;

    // 2) 相对于可执行文件所在目录（发布模式: build/windows/.../Release/web/）
    final exeDir = File(Platform.resolvedExecutable).parent;
    final nearExe = Directory('${exeDir.path}/web');
    if (await nearExe.exists()) return nearExe;

    // 3) 从可执行文件路径向上查找 build/web
    //    Release exe 路径: <project>/build/windows/x64/runner/Release/
    //    Web build 路径:   <project>/build/web/
    var searchDir = exeDir;
    for (int i = 0; i < 6; i++) {
      final candidate = Directory('${searchDir.path}/build/web');
      if (await candidate.exists()) return candidate;
      final webDirect = Directory('${searchDir.path}/web');
      if (await webDirect.exists()) return webDirect;
      final parent = searchDir.parent;
      if (parent.path == searchDir.path) break; // root
      searchDir = parent;
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _jsonResponse(
      HttpResponse response, int statusCode, Map<String, dynamic> body) {
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    response.close();
  }

  ContentType _mimeType(String ext) {
    const types = {
      'html': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'json': 'application/json',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'gif': 'image/gif',
      'svg': 'image/svg+xml',
      'ico': 'image/x-icon',
      'woff': 'font/woff',
      'woff2': 'font/woff2',
      'ttf': 'font/ttf',
      'wasm': 'application/wasm',
    };
    final mime = types[ext] ?? 'application/octet-stream';
    final parts = mime.split('/');
    return ContentType(parts[0], parts[1]);
  }
}
