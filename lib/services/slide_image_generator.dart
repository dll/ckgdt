import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;

class SlideImageGenerator {
  static const slideWidth = 1920.0;
  static const slideHeight = 1080.0;

  Future<List<String>> generateSlides({
    required BuildContext context,
    required List<SlideData> slides,
    required String outputDir,
  }) async {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final paths = <String>[];
    for (var i = 0; i < slides.length; i++) {
      final bytes = await _renderSlide(context, slides[i]);
      if (bytes.isEmpty) continue;
      final path = p.join(outputDir, 'slide_${i.toString().padLeft(3, '0')}.png');
      await File(path).writeAsBytes(bytes);
      paths.add(path);
    }
    return paths;
  }

  Future<Uint8List> _renderSlide(BuildContext context, SlideData slide) async {
    final key = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => RepaintBoundary(
        key: key,
        child: SizedBox(
          width: slideWidth,
          height: slideHeight,
          child: _SlideWidget(data: slide),
        ),
      ),
    );

    Overlay.of(context).insert(entry);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return Uint8List(0);
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List() ?? Uint8List(0);
    } finally {
      entry.remove();
    }
  }
}

class SlideData {
  final String title;
  final String narration;
  final String courseName;
  final String teacherName;
  final bool isTitle;
  final bool isClosing;
  final int index;
  final int total;

  const SlideData({
    required this.title,
    this.narration = '',
    required this.courseName,
    this.teacherName = '',
    this.isTitle = false,
    this.isClosing = false,
    this.index = 0,
    this.total = 0,
  });
}

class _SlideWidget extends StatelessWidget {
  final SlideData data;
  const _SlideWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isTitle) return _buildTitle();
    if (data.isClosing) return _buildClosing();
    return _buildContent();
  }

  Widget _buildGradientBg(List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return _buildGradientBg([const Color(0xFF1A237E), const Color(0xFF3949AB)]);
  }

  Widget _buildContent() {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 80,
            color: const Color(0xFF1A237E),
            padding: const EdgeInsets.symmetric(horizontal: 40),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text(data.title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${data.index}/${data.total}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
          Container(height: 4, color: const Color(0xFF3949AB)),
          Expanded(
            child: Center(
              child: Container(
                width: SlideImageGenerator.slideWidth - 240,
                height: SlideImageGenerator.slideHeight - 320,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: data.narration.isNotEmpty
                    ? Text(data.narration,
                        style: const TextStyle(fontSize: 24, color: Color(0xFF424242), height: 1.8))
                    : null,
              ),
            ),
          ),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            alignment: Alignment.centerLeft,
            child: Text(data.courseName, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildClosing() {
    return _buildGradientBg([const Color(0xFF3949AB), const Color(0xFF1A237E)]);
  }
}
