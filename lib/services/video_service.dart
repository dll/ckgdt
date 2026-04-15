import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 视频合成服务
/// 使用 FFmpeg 将幻灯片图片 + 音频合成为 MP4 教学视频
class VideoService {
  // ── 环境检查 ──────────────────────────────────────────────────────────────

  /// 检查 FFmpeg 是否可用
  Future<bool> isFfmpegInstalled() async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
        'ffmpeg', ['-version'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── 视频生成 ──────────────────────────────────────────────────────────────

  /// 从单张图片 + 音频生成一个视频片段
  /// [imagePath] 幻灯片图片
  /// [audioPath] 配音 MP3
  /// [outputPath] 输出 MP4
  /// [extraDuration] 音频结束后额外停留秒数
  Future<bool> createSlideClip({
    required String imagePath,
    required String audioPath,
    required String outputPath,
    double extraDuration = 1.5,
  }) async {
    if (kIsWeb) return false;
    try {
      // 获取音频时长
      final duration = await _getAudioDuration(audioPath);
      if (duration == null) return false;

      final totalDuration = duration + extraDuration;

      // ffmpeg: 将静态图片 + 音频合成视频
      // Windows 路径需转为正斜杠
      final safeImagePath = imagePath.replaceAll('\\', '/');
      final safeAudioPath = audioPath.replaceAll('\\', '/');
      final safeOutputPath = outputPath.replaceAll('\\', '/');
      final result = await Process.run(
        'ffmpeg',
        [
          '-y', // 覆盖输出
          '-loop', '1', // 循环图片
          '-i', safeImagePath, // 输入图片
          '-i', safeAudioPath, // 输入音频
          '-c:v', 'libx264',
          '-tune', 'stillimage',
          '-c:a', 'aac',
          '-b:a', '192k',
          '-pix_fmt', 'yuv420p',
          '-b:v', '3000k',
          '-t', totalDuration.toStringAsFixed(2),
          '-shortest',
          '-vf', 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2',
          safeOutputPath,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 120));

      return result.exitCode == 0 && File(outputPath).existsSync();
    } catch (e) {
      debugPrint('VideoService: createSlideClip error: $e');
      return false;
    }
  }

  /// 合并多个视频片段为一个完整视频
  /// [clipPaths] 视频片段路径列表
  /// [outputPath] 输出 MP4 路径
  Future<bool> concatenateClips({
    required List<String> clipPaths,
    required String outputPath,
  }) async {
    if (kIsWeb || clipPaths.isEmpty) return false;
    try {
      // 创建 FFmpeg concat 文件（Windows 路径需要正斜杠）
      final dir = await getTemporaryDirectory();
      final listFile = File('${dir.path}/concat_list.txt');
      final content = clipPaths
          .map((p) {
            final safePath = p.replaceAll('\\', '/');
            return "file '$safePath'";
          })
          .join('\n');
      await listFile.writeAsString(content);

      final safeListPath = listFile.path.replaceAll('\\', '/');
      final safeOutput = outputPath.replaceAll('\\', '/');
      final result = await Process.run(
        'ffmpeg',
        [
          '-y',
          '-f', 'concat',
          '-safe', '0',
          '-i', safeListPath,
          '-c:v', 'libx264',
          '-preset', 'medium',
          '-crf', '23',
          '-c:a', 'aac',
          '-b:a', '192k',
          '-b:v', '5000k',
          '-movflags', '+faststart',
          safeOutput,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 600));

      // 清理临时文件
      if (listFile.existsSync()) listFile.deleteSync();

      return result.exitCode == 0 && File(outputPath).existsSync();
    } catch (e) {
      debugPrint('VideoService: concatenateClips error: $e');
      return false;
    }
  }

  /// 完整流水线：幻灯片图片列表 + 音频列表 → 合成视频
  /// [slides] 幻灯片图片路径列表
  /// [audios] 对应的音频路径列表（可以比 slides 少，缺少的用静音代替）
  /// [outputPath] 最终输出视频路径
  /// [onProgress] 进度回调 (current, total)
  Future<bool> generateVideo({
    required List<String> slides,
    required List<String> audios,
    required String outputPath,
    double defaultDuration = 5.0,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    if (kIsWeb) return false;

    debugPrint('VideoService: generateVideo start — '
        '${slides.length} slides, ${audios.length} audios');

    final total = slides.length + 1; // +1 for concatenation step
    final dir = await getTemporaryDirectory();
    final clipDir = Directory('${dir.path}/video_clips');
    if (clipDir.existsSync()) {
      clipDir.deleteSync(recursive: true);
    }
    clipDir.createSync(recursive: true);

    final clipPaths = <String>[];

    // Step 1: 为每张幻灯片生成视频片段
    for (var i = 0; i < slides.length; i++) {
      final slidePath = slides[i];
      final clipPath = '${clipDir.path}/clip_${(i + 1).toString().padLeft(3, '0')}.mp4';

      onProgress?.call(i + 1, total, '正在合成片段 ${i + 1}/${slides.length}');

      if (i < audios.length && File(audios[i]).existsSync()) {
        // 有音频: 图片+音频 → 视频
        debugPrint('VideoService: clip ${i + 1} with audio: ${audios[i]}');
        final success = await createSlideClip(
          imagePath: slidePath,
          audioPath: audios[i],
          outputPath: clipPath,
        );
        if (success) {
          clipPaths.add(clipPath);
        } else {
          debugPrint('VideoService: clip ${i + 1} createSlideClip FAILED, '
              'falling back to silent clip');
          // 有音频但合成失败时回退为静音片段，确保不丢页
          final fallback = await _createSilentClip(
            imagePath: slidePath,
            outputPath: clipPath,
            duration: defaultDuration,
          );
          if (fallback) clipPaths.add(clipPath);
        }
      } else {
        // 无音频: 生成静态幻灯片视频（默认时长）
        debugPrint('VideoService: clip ${i + 1} silent (no audio)');
        final success = await _createSilentClip(
          imagePath: slidePath,
          outputPath: clipPath,
          duration: defaultDuration,
        );
        if (success) clipPaths.add(clipPath);
      }
    }

    debugPrint('VideoService: ${clipPaths.length}/${slides.length} clips created');

    if (clipPaths.isEmpty) return false;

    // Step 2: 合并所有片段
    onProgress?.call(total, total, '正在合并视频...');
    final success = await concatenateClips(
      clipPaths: clipPaths,
      outputPath: outputPath,
    );

    // 清理临时片段
    try {
      if (clipDir.existsSync()) clipDir.deleteSync(recursive: true);
    } catch (_) {}

    return success;
  }

  // ── 将 PDF 页面导出为图片 ──────────────────────────────────────────────────

  /// 使用 Python/Pillow 将 PDF 的每一页导出为 PNG 图片
  /// 返回生成的 PNG 路径列表
  Future<List<String>> pdfToImages({
    required String pdfPath,
    required String outputDir,
  }) async {
    if (kIsWeb) return [];

    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    try {
      // 使用 Python + pdf2image (poppler) 或 PyMuPDF
      final script = '''
import sys
try:
    import fitz  # PyMuPDF
    doc = fitz.open("${pdfPath.replaceAll('\\', '/')}")
    for i, page in enumerate(doc):
        mat = fitz.Matrix(2, 2)  # 2x zoom for 1920px
        pix = page.get_pixmap(matrix=mat)
        out = "${outputDir.replaceAll('\\', '/')}/slide_{:03d}.png".format(i + 1)
        pix.save(out)
        print(out)
    doc.close()
except ImportError:
    try:
        from pdf2image import convert_from_path
        images = convert_from_path("${pdfPath.replaceAll('\\', '/')}", dpi=200)
        for i, img in enumerate(images):
            out = "${outputDir.replaceAll('\\', '/')}/slide_{:03d}.png".format(i + 1)
            img.save(out, 'PNG')
            print(out)
    except ImportError:
        print("ERROR: Please install PyMuPDF or pdf2image", file=sys.stderr)
        sys.exit(1)
''';

      final tempDir = await getTemporaryDirectory();
      final scriptFile = File('${tempDir.path}/pdf2img.py');
      await scriptFile.writeAsString(script);

      final result = await Process.run(
        'python', [scriptFile.path],
        runInShell: true,
      ).timeout(const Duration(seconds: 120));

      if (scriptFile.existsSync()) scriptFile.deleteSync();

      if (result.exitCode == 0) {
        final paths = result.stdout
            .toString()
            .trim()
            .split('\n')
            .map((l) => l.trim())  // 去除 \r（Windows 换行符）
            .where((l) => l.isNotEmpty && l.endsWith('.png'))
            .toList();
        debugPrint('VideoService: pdfToImages got ${paths.length} images');
        return paths;
      }
      debugPrint('VideoService: pdfToImages exitCode=${result.exitCode}, stderr=${result.stderr}');
      return [];
    } catch (e) {
      debugPrint('VideoService: pdfToImages error: $e');
      return [];
    }
  }

  // ── 内部方法 ──────────────────────────────────────────────────────────────

  Future<double?> _getAudioDuration(String audioPath) async {
    try {
      final safePath = audioPath.replaceAll('\\', '/');
      final result = await Process.run(
        'ffprobe',
        [
          '-v', 'error',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          safePath,
        ],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        return double.tryParse(result.stdout.toString().trim());
      }
    } catch (_) {}
    return null;
  }

  /// 生成无声的幻灯片视频
  Future<bool> _createSilentClip({
    required String imagePath,
    required String outputPath,
    double duration = 5.0,
  }) async {
    try {
      final safeImage = imagePath.replaceAll('\\', '/');
      final safeOutput = outputPath.replaceAll('\\', '/');
      final result = await Process.run(
        'ffmpeg',
        [
          '-y',
          '-loop', '1',
          '-i', safeImage,
          '-f', 'lavfi',
          '-i', 'anullsrc=r=44100:cl=stereo',
          '-c:v', 'libx264',
          '-tune', 'stillimage',
          '-c:a', 'aac',
          '-b:a', '192k',
          '-b:v', '3000k',
          '-pix_fmt', 'yuv420p',
          '-t', duration.toStringAsFixed(2),
          '-shortest',
          '-vf', 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2',
          safeOutput,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 60));

      return result.exitCode == 0 && File(outputPath).existsSync();
    } catch (e) {
      debugPrint('VideoService: _createSilentClip error: $e');
      return false;
    }
  }

  // ── SRT 字幕生成 ──────────────────────────────────────────────────────────

  /// 从旁白脚本和音频时长列表生成 SRT 字幕文件
  /// [narrations] 每张幻灯片的旁白文本列表（与 slides 一一对应）
  /// [audioPaths] 对应的音频路径列表（用于获取精确时长）
  /// [outputPath] 输出 SRT 文件路径
  /// [defaultDuration] 无音频时的默认时长
  Future<String?> generateSrt({
    required List<String> narrations,
    required List<String> audioPaths,
    required String outputPath,
    double defaultDuration = 5.0,
    double extraDuration = 1.5,
  }) async {
    if (kIsWeb) return null;
    try {
      final buf = StringBuffer();
      double currentTime = 0.0;

      for (var i = 0; i < narrations.length; i++) {
        final text = narrations[i].trim();
        if (text.isEmpty) {
          currentTime += defaultDuration;
          continue;
        }

        // 获取音频时长
        double duration = defaultDuration;
        if (i < audioPaths.length && File(audioPaths[i]).existsSync()) {
          final d = await _getAudioDuration(audioPaths[i]);
          if (d != null) duration = d + extraDuration;
        }

        final startTime = currentTime;
        final endTime = currentTime + duration;

        // 将旁白文本按句号/分号分段，每段不超过40字
        final segments = _splitNarration(text, 40);
        final segDuration = duration / segments.length;

        for (var j = 0; j < segments.length; j++) {
          final segStart = startTime + j * segDuration;
          final segEnd = startTime + (j + 1) * segDuration;

          buf.writeln('${i * 10 + j + 1}');
          buf.writeln('${_formatSrtTime(segStart)} --> ${_formatSrtTime(segEnd)}');
          buf.writeln(segments[j]);
          buf.writeln();
        }

        currentTime = endTime;
      }

      final file = File(outputPath);
      await file.writeAsString(buf.toString(), flush: true);
      return outputPath;
    } catch (e) {
      debugPrint('VideoService: generateSrt error: $e');
      return null;
    }
  }

  /// 将旁白文本按句号/分号/句号分割，每段不超过 maxLen 字
  List<String> _splitNarration(String text, int maxLen) {
    // 先按句号、分号、问号分割
    final sentences = text.split(RegExp(r'[。；！？]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return [text];

    // 合并短句，确保每段不超过 maxLen
    final result = <String>[];
    var current = '';
    for (final s in sentences) {
      if (current.isEmpty) {
        current = s;
      } else if (current.length + s.length + 1 <= maxLen) {
        current = '$current，$s';
      } else {
        result.add(current);
        current = s;
      }
    }
    if (current.isNotEmpty) result.add(current);

    return result.isEmpty ? [text] : result;
  }

  /// 格式化时间为 SRT 时间戳 (HH:MM:SS,mmm)
  String _formatSrtTime(double seconds) {
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    final s = (seconds % 60).floor();
    final ms = ((seconds - seconds.floor()) * 1000).round();
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')},'
        '${ms.toString().padLeft(3, '0')}';
  }

  /// 将 SRT 字幕烧录到视频中（可选，需要 FFmpeg）
  Future<String?> burnSubtitles({
    required String videoPath,
    required String srtPath,
    required String outputPath,
  }) async {
    if (kIsWeb) return null;
    try {
      final safeVideo = videoPath.replaceAll('\\', '/');
      final safeSrt = srtPath.replaceAll('\\', '/');
      final safeOutput = outputPath.replaceAll('\\', '/');

      // 使用 subtitles filter 烧录字幕
      final result = await Process.run(
        'ffmpeg',
        [
          '-y',
          '-i', safeVideo,
          '-vf', "subtitles='$safeSrt':force_style='FontName=Microsoft YaHei,FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2,Shadow=1,MarginV=30'",
          '-c:v', 'libx264',
          '-preset', 'medium',
          '-crf', '23',
          '-c:a', 'copy',
          '-movflags', '+faststart',
          safeOutput,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 600));

      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        return outputPath;
      }
      debugPrint('VideoService: burnSubtitles stderr: ${result.stderr}');
      return null;
    } catch (e) {
      debugPrint('VideoService: burnSubtitles error: $e');
      return null;
    }
  }
}
