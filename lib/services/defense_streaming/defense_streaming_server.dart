import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/error_handler.dart';

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

  void Function(String ip, int port)? onServerReady;

  Future<void> start({int port = 8766}) async {
    if (_running) {
      debugPrint('DefenseStreamingServer: already running, skipping start');
      return;
    }
    debugPrint('DefenseStreamingServer: getting local IP...');
    _host = await _localIp();
    debugPrint('DefenseStreamingServer: local IP = $_host');
    _port = port;
    for (int i = 0; i < 20; i++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, _port, shared: true);
        debugPrint('DefenseStreamingServer: bound to port $_port');
        break;
      } on SocketException {
        _port++;
      }
    }
    if (_server == null) {
      debugPrint('DefenseStreamingServer: FAILED to bind server after 20 attempts');
      return;
    }
    _running = true;
    _host ??= '127.0.0.1';
    debugPrint('DefenseStreamingServer: starting at http://$_host:$_port');
    _server!.listen(_onRequest, onError: (_) {});
    debugPrint('DefenseStreamingServer: calling onServerReady callback with ip=$_host, port=$_port');
    onServerReady?.call(_host!, _port);
  }

  Future<void> stop() async {
    _running = false;
    final sessionsToClose = List.of(_sessions);
    _sessions.clear();
    for (final s in sessionsToClose) {
      try { await s.response.close(); } catch (e, st) { swallowDebug(e, tag: 'DefenseStreaming.stop', stack: st); }
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
      if (p == '/status' && req.method == 'GET') _status(req);
      else if (p == '/frame/win' && req.method == 'POST') _recvFrame(req, 'win');
      else if (p == '/frame/phone' && req.method == 'POST') _recvFrame(req, 'phone');
      else if (p == '/frame/camera' && req.method == 'POST') _recvFrame(req, 'camera');
      else if (p == '/stream/feed' && req.method == 'GET') _stream(req);
      else if (p == '/raw/win' && req.method == 'GET') _stream(req, 'win');
      else if (p == '/raw/phone' && req.method == 'GET') _stream(req, 'phone');
      else if (p == '/raw/camera' && req.method == 'GET') _stream(req, 'camera');
      else _json(req, 404, {'error': 'unknown'});
    } catch (e) {
      _json(req, 500, {'error': '$e'});
    }
  }

  Future<void> _recvFrame(HttpRequest req, String source) async {
    final bytes = await req.fold<Uint8List>(Uint8List(0),
        (p, c) => Uint8List.fromList([...p, ...c]));
    if (bytes.isEmpty) { _json(req, 400, {'error': 'empty'}); return; }
    if (source == 'win') pushWinFrame(bytes);
    else if (source == 'phone') pushPhoneFrame(bytes);
    else pushCameraFrame(bytes);
    _json(req, 200, {'ok': true, 'bytes': bytes.length});
  }

  void _stream(HttpRequest req, [String? source]) {
    final r = req.response;
    r.headers.contentType = ContentType.parse('multipart/x-mixed-replace; boundary=frame');
    r.headers.add('Cache-Control', 'no-cache');
    r.headers.add('Connection', 'keep-alive');

    // 立即发送初始边界帧，避免客户端等待超时
    try {
      r.add(utf8.encode('\r\n--frame\r\n'));
    } catch (e) {
      swallowDebug(e, tag: 'DefenseStreaming.stream.init');
    }

    final session = _Session(response: r, source: source);
    _sessions.add(session);
    r.done.then((_) => _sessions.remove(session));
  }

  void _broadcast() {
    if (_sessions.isEmpty) return;
    final stale = <_Session>[];
    for (final s in _sessions) {
      try {
        Uint8List? frame;
        if (s.source != null) {
          // 特定源请求：优先返回指定源，如果没有则回退到其他可用源
          if (s.source == 'win') {
            frame = _latestWinFrame ?? _latestPhoneFrame ?? _latestCameraFrame;
          } else if (s.source == 'phone') {
            frame = _latestPhoneFrame ?? _latestWinFrame ?? _latestCameraFrame;
          } else {
            frame = _latestCameraFrame;
          }
        } else {
          // 通用流：返回任何可用的帧
          frame = _latestWinFrame ?? _latestPhoneFrame ?? _latestCameraFrame;
        }
        if (frame == null) continue;
        final b = utf8.encode('\r\n--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n');
        s.response.add(b);
        s.response.add(frame);
      } catch (e, st) { swallowDebug(e, tag: 'DefenseStreaming.bcast', stack: st); stale.add(s); }
    }
    for (final s in stale) _sessions.remove(s);
  }

  void _status(HttpRequest req) {
    _json(req, 200, {
      'running': _running, 'host': _host, 'port': _port,
      'viewers': _sessions.length,
      'frames': {
        'win': _latestWinFrame != null,
        'winAge': DateTime.now().difference(_lastWinAt).inMilliseconds,
        'phone': _latestPhoneFrame != null,
        'phoneAge': DateTime.now().difference(_lastPhoneAt).inMilliseconds,
        'camera': _latestCameraFrame != null,
        'cameraAge': DateTime.now().difference(_lastCameraAt).inMilliseconds,
      },
      'layout': _layoutMode.name,
    });
  }

  Future<String?> _localIp() async {
    try {
      debugPrint('DefenseStreamingServer: listing network interfaces...');
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      debugPrint('DefenseStreamingServer: found ${ifs.length} interfaces');
      for (final i in ifs) {
        debugPrint('DefenseStreamingServer: interface ${i.name} has ${i.addresses.length} addresses');
        for (final a in i.addresses) {
          debugPrint('DefenseStreamingServer: checking address ${a.address}');
          if (a.address.startsWith('192.168') || a.address.startsWith('10.') || a.address.startsWith('172.')) {
            debugPrint('DefenseStreamingServer: selected private IP ${a.address}');
            return a.address;
          }
        }
      }
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback) {
            debugPrint('DefenseStreamingServer: fallback to non-loopback IP ${a.address}');
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
    req.response..statusCode = c..headers.contentType = ContentType.json..write(jsonEncode(b));
    req.response.close();
  }
}

class _Session {
  final HttpResponse response;
  final String? source;
  _Session({required this.response, this.source});
}
