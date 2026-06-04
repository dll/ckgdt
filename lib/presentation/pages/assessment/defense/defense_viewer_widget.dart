import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/design/noir_tokens.dart';

/// MJPEG 流播放组件。连接 multipart/x-mixed-replace，自动重连。
class DefenseViewerWidget extends StatefulWidget {
  final String? url;
  final String label;
  final double aspectRatio;
  final Widget? placeholder;

  const DefenseViewerWidget({
    super.key, this.url, this.label = '',
    this.aspectRatio = 16 / 9, this.placeholder,
  });

  @override
  State<DefenseViewerWidget> createState() => _DefenseViewerWidgetState();
}

class _DefenseViewerWidgetState extends State<DefenseViewerWidget> {
  Uint8List? _frame;
  bool _connected = false;
  bool _error = false;
  String _status = '等待连接…';
  HttpClient? _client;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  // MJPEG parser state
  final _buf = BytesBuilder();
  int _state = 0; // 0=find boundary, 1=headers, 2=data
  int _contentLen = 0;
  int _readBytes = 0;

  // Cached URI to avoid re-parsing on reconnects
  Uri? _cachedUri;
  String? _lastValidatedUrl;

  static const _boundary = '--frame';

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

  void _setError(String status) {
    if (mounted) setState(() { _error = true; _status = status; });
  }

  void _connect() {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() { _status = '未配置服务器'; });
      return;
    }

    // 只在 URL 改变时重新解析
    if (url != _lastValidatedUrl) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
        _setError('URL 格式错误');
        _cachedUri = null;
        _lastValidatedUrl = null;
        return;
      }
      _cachedUri = uri;
      _lastValidatedUrl = url;
    }

    // 确保有有效的 URI
    if (_cachedUri == null) {
      _setError('内部错误：URI 未初始化');
      return;
    }

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
      if (mounted) setState(() { _error = true; _status = '连接失败: $e'; });
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
            _buf.clear();
            if (mounted) setState(() { _error = true; _status = '流数据损坏'; });
            _disconnect();
            break;
          }
          if (data.length > _boundary.length) { _buf.clear(); _buf.add(data.sublist(data.length - _boundary.length + 1)); }
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
        if (mounted) setState(() { _frame = frame; _status = '直播中'; });
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
      borderRadius: BorderRadius.circular(8),
      child: Container(color: NoirTokens.inkDeep,
        child: _frame != null
          ? AspectRatio(aspectRatio: widget.aspectRatio,
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(_frame!, fit: BoxFit.contain),
                if (widget.label.isNotEmpty)
                  Positioned(left: 6, top: 6,
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                      child: Text(widget.label, style: const TextStyle(color: NoirTokens.accent, fontSize: 10, fontWeight: FontWeight.w600)))),
                Positioned(right: 6, bottom: 6,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: _connected ? Colors.green.withValues(alpha: 0.6) : Colors.red.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                    child: Text(_connected ? 'LIVE' : 'OFF', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
              ]))
          : widget.placeholder ?? _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return AspectRatio(aspectRatio: widget.aspectRatio,
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_error ? Icons.error_outline : Icons.hourglass_empty, size: 32, color: NoirTokens.paper.withValues(alpha: 0.3)),
        const SizedBox(height: 8),
        Text(_status, style: TextStyle(color: NoirTokens.paper.withValues(alpha: 0.4), fontSize: 12)),
      ])),
    );
  }
}
