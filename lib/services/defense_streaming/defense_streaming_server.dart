import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/error_handler.dart';
import '../output_path_service.dart';
import 'lan_discovery.dart';

/// 布局模式
enum LayoutMode { dual, winOnly, phoneOnly, cameraOnly }

/// 局域网答辩直播流服务器。
class DefenseStreamingServer {
  DefenseStreamingServer._();
  static final DefenseStreamingServer instance = DefenseStreamingServer._();

  HttpServer? _server;
  String? _host;
  int _port = 8766;
  bool _running = false;
  String _role = 'presenter';

  String? get host => _host;
  int get port => _port;
  bool get isRunning => _running;
  String get serverUrl => isRunning ? 'http://$_host:$_port' : '';

  Uint8List? _latestWinFrame;
  Uint8List? _latestPhoneFrame;
  Uint8List? _latestCameraFrame;
  DateTime _lastWinAt = DateTime(2000);
  DateTime _lastPhoneAt = DateTime(2000);
  DateTime _lastCameraAt = DateTime(2000);

  final List<_Session> _sessions = [];
  LayoutMode _layoutMode = LayoutMode.dual;
  LayoutMode get layoutMode => _layoutMode;

  final Set<String> _authorizedStudents = {};
  File? _authFile;

  // 最近活跃的答辩学生（教师端据此显示答辩项目信息）
  String? _activeDefenderId;
  DateTime _lastDefenderAt = DateTime(2000);

  void Function(String ip, int port)? onServerReady;

  // 局域网 UDP 自动发现信标：start() 后广播本机服务器地址，学生/观看端免输 IP。
  final LanDiscoveryBeacon _beacon = LanDiscoveryBeacon();

  void authorizeStudents(Set<String> ids) {
    _authorizedStudents.clear();
    _authorizedStudents.addAll(ids);
    _saveAuth();
  }

  bool isAuthorized(String studentId) =>
      _authorizedStudents.contains(studentId);

  void _saveAuth() {
    try {
      if (_authFile != null) {
        _authFile!.writeAsStringSync(jsonEncode({
          'authorized': _authorizedStudents.toList(),
          'timestamp': DateTime.now().toIso8601String(),
        }));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'DefenseStreaming.saveAuth', stack: st);
    }
  }

  void _loadAuth() {
    try {
      if (_authFile != null && _authFile!.existsSync()) {
        final data =
            jsonDecode(_authFile!.readAsStringSync()) as Map<String, dynamic>;
        final list = (data['authorized'] as List).cast<String>();
        _authorizedStudents.addAll(list);
        debugPrint(
            'DefenseStreamingServer: loaded ${list.length} authorized students from cache');
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'DefenseStreaming.loadAuth', stack: st);
    }
  }

  Future<void> start({int port = 8766, String role = 'presenter'}) async {
    if (_running) {
      debugPrint('DefenseStreamingServer: already running, skipping start');
      _role = role;
      if (_host != null) {
        onServerReady?.call(_host!, _port);
        await _beacon.start(ip: _host!, port: _port, role: role);
      }
      return;
    }
    debugPrint('DefenseStreamingServer: getting local IP...');
    _host = await _localIp();
    debugPrint('DefenseStreamingServer: local IP = $_host');
    _port = port;
    _role = role;

    // 设置授权缓存文件并加载历史授权（支持服务端重启后无需重授权）
    try {
      final dir = await OutputPathService.getOutputDirectory();
      _authFile = File('${dir.path}/mad_defense_auth.json');
      _loadAuth();
    } catch (e, st) {
      swallowDebug(e, tag: 'DefenseStreaming.authFile', stack: st);
    }

    for (int i = 0; i < 20; i++) {
      try {
        _server =
            await HttpServer.bind(InternetAddress.anyIPv4, _port, shared: true);
        debugPrint('DefenseStreamingServer: bound to port $_port');
        break;
      } on SocketException {
        _port++;
      }
    }
    if (_server == null) {
      debugPrint(
          'DefenseStreamingServer: FAILED to bind server after 20 attempts');
      return;
    }
    _running = true;
    _host ??= '127.0.0.1';
    debugPrint('DefenseStreamingServer: starting at http://$_host:$_port');
    _server!.listen(_onRequest,
        onError: (e, st) =>
            swallowDebug(e, tag: 'DefenseStreaming.listen', stack: st));
    debugPrint(
        'DefenseStreamingServer: calling onServerReady callback with ip=$_host, port=$_port');
    onServerReady?.call(_host!, _port);

    // 启动局域网信标，让学生/观看端自动发现本服务器（免输 IP）。
    await _beacon.start(ip: _host!, port: _port, role: role);
  }

  Future<void> stop() async {
    _running = false;
    _beacon.stop();
    clearFrames();
    final sessionsToClose = List.of(_sessions);
    _sessions.clear();
    for (final s in sessionsToClose) {
      try {
        await s.response.close();
      } catch (e, st) {
        swallowDebug(e, tag: 'DefenseStreaming.stop', stack: st);
      }
    }
    await _server?.close(force: true);
    _server = null;
  }

  void pushWinFrame(Uint8List jpeg) {
    _latestWinFrame = jpeg;
    _lastWinAt = DateTime.now();
    _broadcast();
  }

  void pushPhoneFrame(Uint8List jpeg) {
    _latestPhoneFrame = jpeg;
    _lastPhoneAt = DateTime.now();
    _broadcast();
  }

  void pushCameraFrame(Uint8List jpeg) {
    _latestCameraFrame = jpeg;
    _lastCameraAt = DateTime.now();
    _broadcast();
  }

  Uint8List? get _latestScreenFrame {
    if (_latestWinFrame == null) return _latestPhoneFrame;
    if (_latestPhoneFrame == null) return _latestWinFrame;
    return _lastWinAt.isAfter(_lastPhoneAt)
        ? _latestWinFrame
        : _latestPhoneFrame;
  }

  Uint8List? get _latestAnyFrame {
    Uint8List? frame;
    var at = DateTime(2000);
    void pick(Uint8List? candidate, DateTime candidateAt) {
      if (candidate != null && candidateAt.isAfter(at)) {
        frame = candidate;
        at = candidateAt;
      }
    }

    pick(_latestWinFrame, _lastWinAt);
    pick(_latestPhoneFrame, _lastPhoneAt);
    pick(_latestCameraFrame, _lastCameraAt);
    return frame;
  }

  String? get _latestScreenSource {
    if (_latestWinFrame == null && _latestPhoneFrame == null) return null;
    if (_latestWinFrame != null && _latestPhoneFrame == null) return 'win';
    if (_latestPhoneFrame != null && _latestWinFrame == null) return 'phone';
    return _lastWinAt.isAfter(_lastPhoneAt) ? 'win' : 'phone';
  }

  int get _screenAgeMs {
    final source = _latestScreenSource;
    if (source == null) return -1;
    final at = source == 'win' ? _lastWinAt : _lastPhoneAt;
    return DateTime.now().difference(at).inMilliseconds;
  }

  void clearFrames() {
    _latestWinFrame = null;
    _latestPhoneFrame = null;
    _latestCameraFrame = null;
    _lastWinAt = DateTime(2000);
    _lastPhoneAt = DateTime(2000);
    _lastCameraAt = DateTime(2000);
  }

  void setLayoutMode(LayoutMode mode) => _layoutMode = mode;

  void _onRequest(HttpRequest req) {
    final p = req.uri.path;
    req.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..add('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = 200;
      req.response.close();
      return;
    }
    try {
      if (p == '/status' && req.method == 'GET') {
        _status(req);
      } else if (p == '/frame/win' && req.method == 'POST') {
        _recvFrame(req, 'win');
      } else if (p == '/frame/phone' && req.method == 'POST') {
        _recvFrame(req, 'phone');
      } else if (p == '/frame/camera' && req.method == 'POST') {
        _recvFrame(req, 'camera');
      } else if (p == '/stream/feed' && req.method == 'GET') {
        _stream(req);
      } else if (p == '/raw/win' && req.method == 'GET') {
        _stream(req, 'win');
      } else if (p == '/raw/phone' && req.method == 'GET') {
        _stream(req, 'phone');
      } else if (p == '/raw/screen' && req.method == 'GET') {
        _stream(req, 'screen');
      } else if (p == '/raw/camera' && req.method == 'GET') {
        _stream(req, 'camera');
      } else if (p == '/api/authorized' && req.method == 'GET') {
        _authorizedEndpoint(req);
      } else if (p == '/heartbeat' && req.method == 'POST') {
        _heartbeat(req);
      } else {
        _json(req, 404, {'error': 'unknown'});
      }
    } catch (e) {
      _json(req, 500, {'error': '$e'});
    }
  }

  Future<void> _recvFrame(HttpRequest req, String source) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in req) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      _json(req, 400, {'error': 'empty'});
      return;
    }
    if (source == 'win') {
      pushWinFrame(bytes);
    } else if (source == 'phone') {
      pushPhoneFrame(bytes);
    } else {
      pushCameraFrame(bytes);
    }
    _json(req, 200, {'ok': true, 'bytes': bytes.length});
  }

  void _stream(HttpRequest req, [String? source]) {
    final r = req.response;
    r.bufferOutput = false;
    r.headers.contentType =
        ContentType.parse('multipart/x-mixed-replace; boundary=FRAME');
    r.headers.add('Cache-Control', 'no-cache');
    r.headers.add('Pragma', 'no-cache');
    r.headers.add('Expires', '0');
    r.headers.add('Connection', 'keep-alive');

    final session = _Session(response: r, source: source);
    _sessions.add(session);
    r.done.then((_) => _removeSession(session));
    _queueLatestFrameToSession(session);
  }

  void _broadcast() {
    if (_sessions.isEmpty) return;
    for (final s in List<_Session>.of(_sessions)) {
      _queueLatestFrameToSession(s);
    }
  }

  Uint8List? _frameForSource(String? source) {
    if (source != null) {
      // 特定源请求：只返回对应源，绝不回退到摄像头（否则桌面分区会串到人脸画面）
      if (source == 'win') return _latestWinFrame;
      if (source == 'phone') return _latestPhoneFrame;
      if (source == 'screen') {
        // 桌面分区：Windows/手机谁更新取谁，避免历史 win 帧压住当前 phone 帧。
        return _latestScreenFrame;
      }
      return _latestCameraFrame;
    }
    // 通用流：返回最近更新的任意帧，避免旧屏幕帧压住摄像头/手机帧。
    return _latestAnyFrame;
  }

  void _queueLatestFrameToSession(_Session s) {
    if (!_sessions.contains(s) || s.closed) return;
    final frame = _frameForSource(s.source);
    if (frame == null) return;
    s.pendingFrame = frame;
    if (s.sending) return;
    s.sending = true;
    unawaited(_drainSession(s));
  }

  Future<void> _drainSession(_Session s) async {
    try {
      while (_sessions.contains(s) && !s.closed) {
        final frame = s.pendingFrame;
        if (frame == null) break;
        s.pendingFrame = null;
        final header = utf8.encode(
            '\r\n--FRAME\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n');
        s.response.add(header);
        s.response.add(frame);
        await s.response.flush();
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'DefenseStreaming.bcast', stack: st);
      _removeSession(s);
    } finally {
      s.sending = false;
      if (_sessions.contains(s) && !s.closed && s.pendingFrame != null) {
        _queueLatestFrameToSession(s);
      }
    }
  }

  void _removeSession(_Session s) {
    _sessions.remove(s);
    s.pendingFrame = null;
    s.closed = true;
  }

  void _status(HttpRequest req) {
    _json(req, 200, {
      'running': _running,
      'host': _host,
      'port': _port,
      'viewers': _sessions.length,
      'frames': {
        'screen': _latestScreenFrame != null,
        'screenAge': _screenAgeMs,
        'screenSource': _latestScreenSource,
        'win': _latestWinFrame != null,
        'winAge': DateTime.now().difference(_lastWinAt).inMilliseconds,
        'phone': _latestPhoneFrame != null,
        'phoneAge': DateTime.now().difference(_lastPhoneAt).inMilliseconds,
        'camera': _latestCameraFrame != null,
        'cameraAge': DateTime.now().difference(_lastCameraAt).inMilliseconds,
      },
      'layout': _layoutMode.name,
      'role': _role,
      'activeDefenderId': activeDefenderId,
    });
  }

  Future<String?> _localIp() async {
    try {
      debugPrint('DefenseStreamingServer: listing network interfaces...');
      final ifs = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      debugPrint('DefenseStreamingServer: found ${ifs.length} interfaces');
      for (final i in ifs) {
        debugPrint(
            'DefenseStreamingServer: interface ${i.name} has ${i.addresses.length} addresses');
        for (final a in i.addresses) {
          debugPrint('DefenseStreamingServer: checking address ${a.address}');
          if (a.address.startsWith('192.168') ||
              a.address.startsWith('10.') ||
              a.address.startsWith('172.')) {
            debugPrint(
                'DefenseStreamingServer: selected private IP ${a.address}');
            return a.address;
          }
        }
      }
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback) {
            debugPrint(
                'DefenseStreamingServer: fallback to non-loopback IP ${a.address}');
            return a.address;
          }
        }
      }
    } catch (e, st) {
      debugPrint('DefenseStreamingServer: _localIp() error: $e');
      swallowDebug(e, tag: 'DefenseStreaming.localIp', stack: st);
    }
    debugPrint('DefenseStreamingServer: no suitable IP found, using 127.0.0.1');
    return '127.0.0.1';
  }

  void _json(HttpRequest req, int c, Map<String, dynamic> b) {
    req.response
      ..statusCode = c
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(b));
    req.response.close();
  }

  void _authorizedEndpoint(HttpRequest req) {
    final studentId = req.uri.queryParameters['studentId'] ?? '';
    _json(req, 200, {
      'authorized': studentId.isNotEmpty ? isAuthorized(studentId) : false,
      'host': _host,
      'port': _port,
    });
  }

  Future<void> _heartbeat(HttpRequest req) async {
    try {
      final body = await utf8.decoder.bind(req).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final sid = data['studentId'] as String?;
      if (sid != null && sid.isNotEmpty) {
        final previousActive = activeDefenderId;
        if (previousActive != sid) {
          clearFrames();
        }
        _activeDefenderId = sid;
        _lastDefenderAt = DateTime.now();
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'DefenseStreaming.heartbeat', stack: st);
    }
    _json(req, 200, {'ok': true});
  }

  /// 最近 10 秒内有心跳的答辩学生 id（无则 null）。
  String? get activeDefenderId =>
      DateTime.now().difference(_lastDefenderAt) <= const Duration(seconds: 10)
          ? _activeDefenderId
          : null;
}

class _Session {
  final HttpResponse response;
  final String? source;
  Uint8List? pendingFrame;
  bool sending = false;
  bool closed = false;
  _Session({required this.response, this.source});
}
