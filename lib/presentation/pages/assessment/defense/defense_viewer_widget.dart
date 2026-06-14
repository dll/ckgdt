import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/noir_tokens.dart';

/// MJPEG 流播放组件。15fps 限流，无 AspectRatio 防抖动，支持全屏。
class DefenseViewerWidget extends StatefulWidget {
  final String? url;
  final String label;
  final Widget? placeholder;
  final VoidCallback? onFullscreenToggle;
  final bool isFullscreen;

  const DefenseViewerWidget({
    super.key, this.url, this.label = '',
    this.placeholder, this.onFullscreenToggle,
    this.isFullscreen = false,
  });

  @override
  State<DefenseViewerWidget> createState() => _DefenseViewerWidgetState();
}

class _DefenseViewerWidgetState extends State<DefenseViewerWidget> {
  Uint8List? _frame;
  DateTime _lastFrameAt = DateTime(2000);
  static const _frameMinInterval = Duration(milliseconds: 67); // ~15fps
  bool _connected = false;
  bool _error = false;
  String _status = '等待连接…';
  HttpClient? _client;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  final _buf = BytesBuilder();
  int _state = 0;
  int _contentLen = 0;
  int _readBytes = 0;

  Uri? _cachedUri;
  String? _lastValidatedUrl;

  static const _boundary = '--FRAME';

  @override
  void initState() { super.initState(); _connect(); }

  @override
  void didUpdateWidget(DefenseViewerWidget old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) { _disconnect(); _connect(); }
  }

  @override
  void dispose() { _disconnect(); super.dispose(); }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _client?.close(force: true);
    _client = null;
    _sub = null;
    _cachedUri = null;
    _lastValidatedUrl = null;
  }

  void _connect() {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() { _status = '未配置服务器'; });
      return;
    }
    if (url != _lastValidatedUrl) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
        if (mounted) setState(() { _error = true; _status = 'URL 格式错误'; });
        return;
      }
      _cachedUri = uri;
      _lastValidatedUrl = url;
    }
    if (_cachedUri == null) return;

    _client = HttpClient();
    _client!.getUrl(_cachedUri!).then((req) {
      req.headers.set('Accept', 'multipart/x-mixed-replace');
      return req.close();
    }).then((res) {
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() { _error = true; _status = '${res.statusCode}'; });
        res.drain(); _schedule(); return;
      }
      setState(() { _connected = true; _error = false; _status = '已连接'; });
      _buf.clear(); _state = 0; _contentLen = 0; _readBytes = 0;
      _sub = res.listen(_parse, onDone: () {
        if (mounted) setState(() { _connected = false; _status = '断开'; });
        _schedule();
      }, onError: (e) {
        if (mounted) setState(() { _error = true; _status = '$e'; });
        _schedule();
      });
    }).catchError((e) {
      if (mounted) setState(() { _error = true; _status = '连接失败'; });
      _schedule();
    });
  }

  void _schedule() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _connect();
    });
  }

  void _parse(List<int> chunk) {
    _buf.add(chunk);
    while (true) {
      if (_state == 0) {
        final data = _buf.toBytes();
        final idx = _indexOf(data, utf8.encode(_boundary));
        if (idx < 0) {
          if (data.length > 1024 * 1024) {
            _buf.clear(); _disconnect();
            if (mounted) setState(() { _error = true; _status = '流数据损坏'; });
            break;
          }
          if (data.length > _boundary.length) {
            _buf.clear(); _buf.add(data.sublist(data.length - _boundary.length + 1));
          }
          break;
        }
        _buf.clear();
        if (idx + _boundary.length < data.length) {
          _buf.add(data.sublist(idx + _boundary.length));
        }
        _state = 1; continue;
      }
      if (_state == 1) {
        final data = _buf.toBytes();
        final end = _indexOf(data, utf8.encode('\r\n\r\n'));
        if (end < 0) break;
        final hdr = utf8.decode(data.sublist(0, end));
        _buf.clear(); _buf.add(data.sublist(end + 4));
        _contentLen = 0;
        for (final l in hdr.split('\r\n')) {
          if (l.toLowerCase().startsWith('content-length:')) {
            _contentLen = int.tryParse(l.split(':').last.trim()) ?? 0; break;
          }
        }
        _readBytes = 0; _state = 2; continue;
      }
      if (_state == 2) {
        final data = _buf.toBytes();
        final need = _contentLen - _readBytes;
        if (data.length < need) { _readBytes += data.length; _buf.clear(); break; }
        final frame = data.sublist(0, _contentLen);
        _buf.clear();
        if (data.length > _contentLen) _buf.add(data.sublist(_contentLen));
        if (_contentLen > 0) {
          final now = DateTime.now();
          if (now.difference(_lastFrameAt) >= _frameMinInterval && mounted) {
            _lastFrameAt = now;
            setState(() { _frame = frame; _status = '直播中'; });
          }
        }
        _state = 0; continue;
      }
      break;
    }
  }

  int _indexOf(List<int> h, List<int> n, [int start = 0]) {
    if (n.isEmpty) return 0;
    for (int i = start; i <= h.length - n.length; i++) {
      bool m = true;
      for (int j = 0; j < n.length; j++) { if (h[i + j] != n[j]) { m = false; break; } }
      if (m) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.isFullscreen ? 0 : 8),
      child: Container(color: NoirTokens.inkDeep,
        child: _frame != null
          ? LayoutBuilder(builder: (context, constraints) {
              return Stack(fit: StackFit.expand, children: [
                Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true),
                // 标签
                if (widget.label.isNotEmpty && !widget.isFullscreen)
                  Positioned(left: 6, top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(widget.label,
                          style: const TextStyle(
                              color: NoirTokens.accent, fontSize: 10, fontWeight: FontWeight.w600)))),
                // LIVE 指示
                Positioned(left: 6, bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                        color: _connected ? Colors.green.withValues(alpha: 0.6) : Colors.red.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(_connected ? 'LIVE' : 'OFF',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
                // 全屏按钮
                if (widget.onFullscreenToggle != null)
                  Positioned(right: 6, top: 6,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: widget.onFullscreenToggle,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4)),
                          child: Icon(
                            widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            color: Colors.white, size: 16),
                        ),
                      ),
                    )),
              ]);
            })
          : widget.placeholder ?? _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return LayoutBuilder(builder: (context, constraints) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_error ? Icons.error_outline : Icons.hourglass_empty,
            size: 32, color: NoirTokens.paper.withValues(alpha: 0.3)),
        const SizedBox(height: 8),
        Text(_status,
            style: TextStyle(color: NoirTokens.paper.withValues(alpha: 0.4), fontSize: 12)),
      ]));
    });
  }
}
