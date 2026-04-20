import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// TTS 语音合成服务
/// 使用 edge_tts (Python 包) 或 pyttsx3 生成中文语音
class TtsService {
  // 默认中文女声
  static const defaultVoice = 'zh-CN-XiaoxiaoNeural';
  static const defaultRate = '-5%';

  /// 可用的中文语音列表
  static const voices = {
    'zh-CN-XiaoxiaoNeural': '晓晓（女声·推荐）',
    'zh-CN-YunxiNeural': '云希（男声）',
    'zh-CN-YunjianNeural': '云健（男声·浑厚）',
    'zh-CN-XiaoyiNeural': '晓伊（女声·温柔）',
    'zh-CN-YunyangNeural': '云扬（男声·新闻）',
  };

  // ── 环境检查 ──────────────────────────────────────────────────────────────

  /// 检查 edge_tts 是否已安装
  Future<bool> isEdgeTtsInstalled() async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
        'pip', ['show', 'edge-tts'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 安装 edge_tts
  Future<bool> installEdgeTts() async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
        'pip', ['install', 'edge-tts'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── TTS 生成 ──────────────────────────────────────────────────────────────

  /// 生成单段语音 MP3
  /// [text] 朗读文本
  /// [outputPath] 输出 MP3 路径
  /// [voice] 语音名称
  /// [rate] 语速 (如 '-5%', '+10%')
  Future<bool> generateAudio({
    required String text,
    required String outputPath,
    String voice = defaultVoice,
    String rate = defaultRate,
  }) async {
    if (kIsWeb) return false;
    try {
      // 创建临时文本文件（避免命令行转义问题）
      final dir = await getTemporaryDirectory();
      final textFile = File('${dir.path}/tts_input.txt');
      await textFile.writeAsString(text);

      // 使用 edge-tts 命令
      final result = await Process.run(
        'edge-tts',
        [
          '--voice', voice,
          '--rate', rate,
          '--file', textFile.path,
          '--write-media', outputPath,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 120));

      // 清理临时文件
      if (textFile.existsSync()) textFile.deleteSync();

      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        final fileSize = File(outputPath).lengthSync();
        return fileSize > 100; // 确保不是空文件
      }

      // 如果 edge-tts 命令失败，尝试 Python 脚本方式
      debugPrint('TtsService: edge-tts command failed, trying Python...');
      return _generateViaPython(text, outputPath, voice, rate);
    } catch (e) {
      debugPrint('TtsService: generateAudio error: $e');
      return false;
    }
  }

  /// 批量生成语音（按段落）
  /// 返回生成的 MP3 文件路径列表（与 scripts 一一对应，空旁白返回空字符串占位）
  Future<List<String>> generateBatchAudio({
    required List<Map<String, String>> scripts,
    required String outputDir,
    String voice = defaultVoice,
    String rate = defaultRate,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <String>[];
    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (var i = 0; i < scripts.length; i++) {
      final script = scripts[i];
      final narration = script['narration'] ?? '';
      if (narration.trim().isEmpty) {
        // 空旁白保留占位，保证索引与幻灯片对齐
        results.add('');
        onProgress?.call(i + 1, scripts.length);
        continue;
      }

      final fileName = 'audio_${(i + 1).toString().padLeft(2, '0')}.mp3';
      final outputPath = '${dir.path}/$fileName';

      // 跳过已存在的有效音频
      if (File(outputPath).existsSync() &&
          File(outputPath).lengthSync() > 1000) {
        results.add(outputPath);
        onProgress?.call(i + 1, scripts.length);
        continue;
      }

      final success = await generateAudio(
        text: narration,
        outputPath: outputPath,
        voice: voice,
        rate: rate,
      );

      if (success) {
        results.add(outputPath);
      } else {
        // 生成失败也保留占位
        results.add('');
      }
      onProgress?.call(i + 1, scripts.length);
    }
    return results;
  }

  // ── 内部方法 ──────────────────────────────────────────────────────────────

  /// 通过 Python 脚本调用 edge_tts
  Future<bool> _generateViaPython(
      String text, String outputPath, String voice, String rate) async {
    try {
      final script = '''
import asyncio
import edge_tts

async def main():
    tts = edge_tts.Communicate(
        text="""${text.replaceAll('"', '\\"')}""",
        voice="$voice",
        rate="$rate"
    )
    await tts.save("${outputPath.replaceAll('\\', '/')}")

asyncio.run(main())
''';

      final dir = await getTemporaryDirectory();
      final scriptFile = File('${dir.path}/tts_gen.py');
      await scriptFile.writeAsString(script);

      final result = await Process.run(
        'python', [scriptFile.path],
        runInShell: true,
      ).timeout(const Duration(seconds: 120));

      if (scriptFile.existsSync()) scriptFile.deleteSync();

      return result.exitCode == 0 && File(outputPath).existsSync();
    } catch (e) {
      debugPrint('TtsService: _generateViaPython error: $e');
      return false;
    }
  }

  /// 获取音频时长（需要 ffprobe）
  Future<double?> getAudioDuration(String audioPath) async {
    try {
      final result = await Process.run(
        'ffprobe',
        [
          '-v', 'error',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          audioPath,
        ],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        return double.tryParse(result.stdout.toString().trim());
      }
    } catch (_) {}
    return null;
  }
}
