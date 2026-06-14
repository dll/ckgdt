import 'dart:convert';
import 'dart:typed_data';

/// Incremental parser for the MJPEG stream emitted by [DefenseStreamingServer].
///
/// A single JPEG frame is often split across multiple TCP chunks. The parser
/// keeps partial frame bytes until the declared Content-Length is available.
class MjpegFrameParser {
  static const boundary = '--FRAME';
  static final List<int> _boundaryBytes = utf8.encode(boundary);
  static final List<int> _headerEndBytes = utf8.encode('\r\n\r\n');

  final BytesBuilder _buf = BytesBuilder(copy: false);
  int _state = 0;
  int _contentLen = 0;

  void reset() {
    _buf.clear();
    _state = 0;
    _contentLen = 0;
  }

  List<Uint8List> add(List<int> chunk) {
    _buf.add(chunk);
    final frames = <Uint8List>[];

    while (true) {
      if (_state == 0) {
        final data = _buf.toBytes();
        final idx = _indexOf(data, _boundaryBytes);
        if (idx < 0) {
          if (data.length > 1024 * 1024) {
            reset();
          } else if (data.length > _boundaryBytes.length) {
            _buf.clear();
            _buf.add(data.sublist(data.length - _boundaryBytes.length + 1));
          }
          break;
        }
        _buf.clear();
        if (idx + _boundaryBytes.length < data.length) {
          _buf.add(data.sublist(idx + _boundaryBytes.length));
        }
        _state = 1;
        continue;
      }

      if (_state == 1) {
        final data = _buf.toBytes();
        final end = _indexOf(data, _headerEndBytes);
        if (end < 0) break;
        final header = utf8.decode(data.sublist(0, end), allowMalformed: true);
        _buf.clear();
        _buf.add(data.sublist(end + _headerEndBytes.length));
        _contentLen = _parseContentLength(header);
        _state = 2;
        continue;
      }

      if (_state == 2) {
        final data = _buf.toBytes();
        if (_contentLen <= 0) {
          _state = 0;
          continue;
        }
        if (data.length < _contentLen) break;
        frames.add(Uint8List.fromList(data.sublist(0, _contentLen)));
        _buf.clear();
        if (data.length > _contentLen) {
          _buf.add(data.sublist(_contentLen));
        }
        _state = 0;
        continue;
      }

      break;
    }

    return frames;
  }

  int _parseContentLength(String header) {
    for (final line in header.split('\r\n')) {
      if (line.toLowerCase().startsWith('content-length:')) {
        return int.tryParse(line.split(':').last.trim()) ?? 0;
      }
    }
    return 0;
  }

  int _indexOf(List<int> haystack, List<int> needle, [int start = 0]) {
    if (needle.isEmpty) return 0;
    for (var i = start; i <= haystack.length - needle.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
