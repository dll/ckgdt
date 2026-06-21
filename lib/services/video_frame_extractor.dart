/// 视频帧抽取 — 给作品 AI 批阅 / GLM-4V 视觉模型用。
///
/// **运行场景**：dev/admin 机器（生产 EXE 也跑得动，只要 ffmpeg 在 PATH 或
/// 装机 D:/development/ffmpeg-…）。普通学生机器没装 ffmpeg → 调用方需 fallback。
///
/// **设计取舍**：
/// - 用 ffmpeg subprocess 而不是 dart 视频库，省一个原生依赖；
/// - 抽帧用均匀采样（select 滤镜按时间间隔），覆盖整段视频，不光看开头；
/// - 输出 base64 直喂 GLM-4V 的 `image_url: data:image/jpeg;base64,...`；
/// - 失败不抛错，返回空列表，让上层 fallback 到 text-only。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/dev_paths.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

class VideoFrameExtractor {
  VideoFrameExtractor._();

  /// 从视频 [videoPath] 均匀抽 [frameCount] 帧（默认 5），
  /// 每帧缩到 [maxWidth] 像素宽（默认 768）以控制 base64 体积。
  ///
  /// 返回 base64 字符串列表（不含 data: 前缀，调用方拼）。
  /// 失败 → 返回空列表 + 在 stderr 上打日志。
  static Future<List<String>> extractKeyFrames(
    String videoPath, {
    int frameCount = 5,
    int maxWidth = 768,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!File(videoPath).existsSync()) {
      stderr.writeln('[VideoFrameExtractor] 视频不存在: $videoPath');
      return [];
    }

    // 先拿视频时长，便于计算均匀采样的时间戳
    final duration = await _probeDurationSeconds(videoPath);
    if (duration <= 0) {
      stderr.writeln('[VideoFrameExtractor] 无法读取时长: $videoPath');
      return [];
    }

    final tmpDir = await Directory.systemTemp.createTemp('frame_extract_');
    try {
      final outPattern = p.join(tmpDir.path, 'frame_%03d.jpg');

      // 均匀采样：从 0.5s 开始（避开黑屏开头），到 duration-0.5s 结束
      // ffmpeg select 滤镜 + fps 实现：select='not(mod(n,K))' 不够精确，
      // 直接用 -vf "fps=N/duration" 然后 -frames:v frameCount。
      final fpsRatio = (frameCount / (duration > 1 ? duration - 0.5 : duration))
          .toStringAsFixed(4);

      final args = [
        '-y',
        '-ss', '0.5',
        '-i', videoPath,
        '-vf', 'fps=$fpsRatio,scale=$maxWidth:-2',
        '-frames:v', '$frameCount',
        '-q:v', '4', // jpeg 质量 1(最佳)~31(最差)，4 = 较好且体积小
        outPattern,
      ];

      final proc = await Process.run(
        DevPaths.ffmpegPath,
        args,
        runInShell: true,
      ).timeout(timeout, onTimeout: () {
        return ProcessResult(0, -1, '', 'timeout');
      });

      if (proc.exitCode != 0) {
        stderr.writeln(
            '[VideoFrameExtractor] ffmpeg 失败 [${proc.exitCode}]: ${proc.stderr}');
        return [];
      }

      // 读所有产出的 jpg 转 base64
      final results = <String>[];
      for (var i = 1; i <= frameCount; i++) {
        final f = File(p.join(
            tmpDir.path, 'frame_${i.toString().padLeft(3, '0')}.jpg'));
        if (!await f.exists()) break;
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        results.add(base64Encode(bytes));
      }
      return results;
    } catch (e) {
      stderr.writeln('[VideoFrameExtractor] 异常: $e');
      return [];
    } finally {
      try {
        await tmpDir.delete(recursive: true);
      } catch (e) { swallowDebug(e, tag: 'video_frame_extractor'); }
    }
  }

  /// 用 ffprobe 拿视频秒数。失败返回 0。
  static Future<double> _probeDurationSeconds(String videoPath) async {
    try {
      // ffprobe 通常和 ffmpeg 同目录
      final ffmpegPath = DevPaths.ffmpegPath;
      final ffprobe = ffmpegPath.endsWith('.exe')
          ? ffmpegPath.replaceFirst(
              RegExp(r'ffmpeg\.exe$'), 'ffprobe.exe')
          : ffmpegPath.replaceFirst(RegExp(r'ffmpeg$'), 'ffprobe');

      final r = await Process.run(
        ffprobe,
        [
          '-v', 'error',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          videoPath,
        ],
        runInShell: true,
      );
      if (r.exitCode != 0) return 0;
      return double.tryParse((r.stdout as String).trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
