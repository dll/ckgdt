import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/defense_streaming/defense_streaming_server.dart';
import 'package:knowledge_graph_app/services/defense_streaming/mjpeg_frame_parser.dart';

void main() {
  List<int> part(Uint8List frame) => [
        ...utf8.encode(
          '\r\n--FRAME\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n',
        ),
        ...frame,
      ];

  test('parses frames split across TCP chunks', () {
    final parser = MjpegFrameParser();
    final frame1 = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final frame2 = Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));

    expect(parser.add(part(frame1)), [frame1]);

    final message = part(frame2);
    final frames = <Uint8List>[];
    for (var offset = 0; offset < message.length; offset += 37) {
      final end = (offset + 37).clamp(0, message.length);
      frames.addAll(parser.add(message.sublist(offset, end)));
    }

    expect(frames.length, 1);
    expect(frames.single, frame2);
  });

  test('parses multiple frames from one chunk', () {
    final parser = MjpegFrameParser();
    final frame1 = Uint8List.fromList([1, 2, 3]);
    final frame2 = Uint8List.fromList([4, 5, 6, 7]);

    final frames = parser.add([...part(frame1), ...part(frame2)]);

    expect(frames, [frame1, frame2]);
  });

  test('server streams subsequent win frames on the same connection', () async {
    final server = DefenseStreamingServer.instance;
    await server.stop();
    await server.start(port: 18766, role: 'present');
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final parser = MjpegFrameParser();
    final frames = <Uint8List>[];
    final frame1 = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final frame2 = Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));
    final frame3 = Uint8List.fromList(List<int>.generate(96, (i) => 255 - i));

    server.pushWinFrame(frame1);

    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/raw/win'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    expect(response.statusCode, 200);

    final subscription = response.listen((chunk) {
      frames.addAll(parser.add(chunk));
    });
    addTearDown(subscription.cancel);

    await _waitFor(() => frames.isNotEmpty);
    server.pushWinFrame(frame2);
    server.pushWinFrame(frame3);

    await _waitFor(() => _containsFrame(frames, frame3));
    expect(frames.first, frame1);
    expect(frames.length, greaterThanOrEqualTo(2));
  });
}

bool _containsFrame(List<Uint8List> frames, Uint8List expected) =>
    frames.any((frame) => _sameBytes(frame, expected));

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
