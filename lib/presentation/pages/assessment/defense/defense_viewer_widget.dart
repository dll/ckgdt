import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/design/noir_tokens.dart';
import '../../../../services/defense_streaming/mjpeg_frame_parser.dart';

/// MJPEG 流播放组件。15fps 限流，无 AspectRatio 防抖动，支持全屏。
class DefenseViewerWidget extends StatefulWidget {
  final String? url;
  final String label;
  final Widget? placeholder;
  final VoidCallback? onFullscreenToggle;
  final bool isFullscreen;

  const DefenseViewerWidget({
    super.key,
    this.url,
    this.label = '',
    this.placeholder,
    this.onFullscreenToggle,
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

  final _parser = MjpegFrameParser();

  Uri? _cachedUri;
  String? _lastValidatedUrl;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(DefenseViewerWidget old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _disconnect();
      _connect();
    }
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

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
      if (mounted) {
        setState(() {
          _status = '未配置服务器';
        });
      }
      return;
    }
    if (url != _lastValidatedUrl) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
        if (mounted) {
          setState(() {
            _error = true;
            _status = 'URL 格式错误';
          });
        }
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
        setState(() {
          _error = true;
          _status = '${res.statusCode}';
        });
        res.drain();
        _schedule();
        return;
      }
      setState(() {
        _connected = true;
        _error = false;
        _status = '已连接';
      });
      _parser.reset();
      _sub = res.listen(_parse, onDone: () {
        if (mounted) {
          setState(() {
            _connected = false;
            _status = '断开';
          });
        }
        _schedule();
      }, onError: (e) {
        if (mounted) {
          setState(() {
            _error = true;
            _status = '$e';
          });
        }
        _schedule();
      });
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _error = true;
          _status = '连接失败';
        });
      }
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
    for (final frame in _parser.add(chunk)) {
      final now = DateTime.now();
      if (now.difference(_lastFrameAt) >= _frameMinInterval && mounted) {
        _lastFrameAt = now;
        setState(() {
          _frame = frame;
          _status = '直播中';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.isFullscreen ? 0 : 8),
      child: Container(
        color: NoirTokens.inkDeep,
        child: _frame != null
            ? LayoutBuilder(builder: (context, constraints) {
                return Stack(fit: StackFit.expand, children: [
                  Image.memory(_frame!,
                      fit: BoxFit.contain, gaplessPlayback: true),
                  // 标签
                  if (widget.label.isNotEmpty && !widget.isFullscreen)
                    Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(widget.label,
                                style: const TextStyle(
                                    color: NoirTokens.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)))),
                  // LIVE 指示
                  Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                              color: _connected
                                  ? Colors.green.withValues(alpha: 0.6)
                                  : Colors.red.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(_connected ? 'LIVE' : 'OFF',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)))),
                  // 全屏按钮
                  if (widget.onFullscreenToggle != null)
                    Positioned(
                        right: 6,
                        top: 6,
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
                                  widget.isFullscreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  color: Colors.white,
                                  size: 16),
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
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_error ? Icons.error_outline : Icons.hourglass_empty,
            size: 32, color: NoirTokens.paper.withValues(alpha: 0.3)),
        const SizedBox(height: 8),
        Text(_status,
            style: TextStyle(
                color: NoirTokens.paper.withValues(alpha: 0.4), fontSize: 12)),
      ]));
    });
  }
}
