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
      final path =
          p.join(outputDir, 'slide_${i.toString().padLeft(3, '0')}.png');
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

    // ignore: use_build_context_synchronously
    Overlay.of(context).insert(entry);
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      final boundary = key.currentContext?.findRenderObject();
      if (boundary == null || boundary is! RenderRepaintBoundary)
        return Uint8List(0);
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
  final List<String> bullets;

  const SlideData({
    required this.title,
    this.narration = '',
    required this.courseName,
    this.teacherName = '',
    this.isTitle = false,
    this.isClosing = false,
    this.index = 0,
    this.total = 0,
    this.bullets = const [],
  });
}

class _SlideWidget extends StatelessWidget {
  final SlideData data;
  const _SlideWidget({required this.data});

  static const _primary = Color(0xFF1A237E);
  static const _primaryLight = Color(0xFF3949AB);
  static const _accent = Color(0xFF667eea);
  static const _accent2 = Color(0xFF764ba2);

  @override
  Widget build(BuildContext context) {
    if (data.isTitle) return _buildTitle();
    if (data.isClosing) return _buildClosing();
    return _buildContent();
  }

  Widget _gradientBg(List<Color> colors) {
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
    return Stack(
      children: [
        _gradientBg([_primary, _primaryLight, _accent, _accent2]),
        Positioned(
          top: slideHeaderTop,
          left: 0,
          right: 0,
          child: Column(
            children: [
              if (data.teacherName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Text(data.teacherName,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 20,
                          letterSpacing: 4)),
                ),
              Text(data.courseName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2)),
              const SizedBox(height: 40),
              Container(width: 120, height: 3, color: Colors.white38),
              const SizedBox(height: 40),
              Text('说 课',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 16)),
              if (data.narration.isNotEmpty) ...[
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 300),
                  child: Text(data.narration,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 18, height: 1.6)),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Text('课程知识图谱与数字孪生平台',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 14, letterSpacing: 2)),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Container(
      color: const Color(0xFFF0F2F5),
      child: Column(
        children: [
          // Header bar
          Container(
            height: 100,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_primary, _primaryLight],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    data.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (data.total > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text('${data.index} / ${data.total}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
              ],
            ),
          ),
          Container(height: 6, color: _accent),
          // Content area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(80, 40, 80, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: bullet points
                  Expanded(
                    flex: 3,
                    child: data.bullets.isNotEmpty
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: data.bullets
                                .map(_cleanText)
                                .where((b) => b.isNotEmpty)
                                .map((b) => _bulletItem(b))
                                .toList(),
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Text(_cleanText(data.narration),
                                  style: const TextStyle(
                                      fontSize: 26,
                                      color: Color(0xFF424242),
                                      height: 1.8)),
                            ),
                          ),
                  ),
                  const SizedBox(width: 40),
                  // Right: decorative element
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        Container(
                          height: 4,
                          width: 60,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [_accent, _accent2]),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Icon(Icons.auto_awesome,
                            size: 48, color: _accent.withValues(alpha: 0.15)),
                        const SizedBox(height: 8),
                        Text('AI 生成',
                            style: TextStyle(
                                fontSize: 12,
                                color: _accent.withValues(alpha: 0.2))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Footer
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 60),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book, size: 16, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                Text(data.courseName,
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                const Spacer(),
                Text('CKGDT 说课',
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accent, _accent2]),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 24, color: Color(0xFF333333), height: 1.6)),
          ),
        ],
      ),
    );
  }

  String _cleanText(String input) {
    var text = input.trim();
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    text = text.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'^#{1,6}\s*'), '');
    text = text.replaceAll(RegExp(r'^[-*+]\s+'), '');
    text = text.replaceAll(RegExp(r'^\d+[.、)]\s*'), '');
    text = text.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    text = text.replaceAll(RegExp(r'[*_~>|#`]+'), '');
    text = text.replaceAll(RegExp(r'\s*\|\s*'), ' ');
    text = text.replaceAll(RegExp(r'[-:]{3,}'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 46) text = '${text.substring(0, 46)}…';
    return text;
  }

  static const slideHeaderTop = 180.0;

  Widget _buildClosing() {
    return Stack(
      children: [
        _gradientBg([_primaryLight, _primary]),
        Positioned(
          top: slideHeaderTop,
          left: 0,
          right: 0,
          child: Column(
            children: [
              const Text('感谢聆听',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8)),
              const SizedBox(height: 40),
              Container(width: 100, height: 2, color: Colors.white38),
              const SizedBox(height: 40),
              Text(data.courseName,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 24, letterSpacing: 2)),
              if (data.teacherName.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(data.teacherName,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 18)),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: const Text('课程知识图谱与数字孪生平台 · CKGDT',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white30, fontSize: 14)),
        ),
      ],
    );
  }
}
