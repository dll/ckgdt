import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Pandoc 子进程封装。
///
/// **职责**：把 markdown 文本通过 pandoc 转成 docx / pdf 字节，让归档管线
/// 输出符合学校排版规范的 Office 原版文件（不是 markdown 渲染的近似版）。
///
/// **平台**：仅 Windows 教师端（其它平台 [isAvailable] 返回 false）。
/// 项目预设 pandoc 已装且在 PATH 中（CLAUDE.md 升版同步表第 8 项的"环境准备"
/// 部分会要求装）。
///
/// **失败模式**：pandoc 不在 PATH / 异常退出 → 抛 [PandocException]，调用方
/// 应回退到 markdown 直显或提示用户安装 pandoc。
///
/// **样式继承**：[referenceDocPath] 给定时走 pandoc 的 `--reference-doc` 选项，
/// 输出 docx 的字体 / 页边距 / 标题样式继承该参考 docx——这是把生成 docx
/// 接近"学校原版样式"的关键。一般指向 `data/归档/<期>/模板/<docType>.docx`。
class PandocService {
  PandocService._();
  static final instance = PandocService._();

  /// 检测当前平台是否支持 pandoc 调用。
  /// 仅 Windows / macOS / Linux 桌面端可用，移动端 (Android/iOS/鸿蒙) 和 Web 不可用。
  bool get isAvailable {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 检查 pandoc 可执行文件是否真在 PATH 中。
  /// **第一次调用会真起一个 pandoc --version 子进程**，后续走缓存。
  Future<bool> get isInstalled async {
    if (_isInstalledCache != null) return _isInstalledCache!;
    if (!isAvailable) return _isInstalledCache = false;
    try {
      final result = await Process.run(
        'pandoc',
        ['--version'],
        runInShell: true,
      ).timeout(const Duration(seconds: 5));
      _isInstalledCache = result.exitCode == 0;
      if (kDebugMode) {
        debugPrint('[PandocService] pandoc installed: $_isInstalledCache');
      }
      return _isInstalledCache!;
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[PandocService] pandoc check failed: $e');
      return _isInstalledCache = false;
    }
  }

  bool? _isInstalledCache;

  /// markdown → docx 字节。
  ///
  /// [referenceDocPath] 指向学校 docx 模板（如教学大纲样式），
  /// pandoc 会继承其字体 / 页边距 / 标题样式。
  Future<Uint8List> markdownToDocx(
    String markdown, {
    String? referenceDocPath,
  }) async {
    return _convert(
      input: markdown,
      fromFormat: 'markdown',
      toFormat: 'docx',
      extraArgs: [
        if (referenceDocPath != null && File(referenceDocPath).existsSync())
          '--reference-doc=$referenceDocPath',
      ],
    );
  }

  /// markdown → PDF 字节。
  ///
  /// 由于 pandoc 直接 markdown → pdf 需要 LaTeX 引擎（笨重），
  /// 改走两步：先 md → docx（带 reference-doc 样式），再 docx → pdf。
  ///
  /// 但 pandoc docx → pdf 依赖 LibreOffice/Word。Windows 上若有 Word，
  /// 优先用 Word COM；没有则提示用户。
  ///
  /// 当前简化实现：直接 pandoc markdown → docx，再让调用方用
  /// `Printing.layoutPdf` + 自己绘制 markdown，或者通过外部转换。
  ///
  /// **本方法当前抛 UnimplementedError**——commit 5 实现一键打印时再补全。
  Future<Uint8List> markdownToPdf(
    String markdown, {
    String? referenceDocPath,
  }) async {
    throw UnimplementedError(
        '[PandocService] markdownToPdf 在 commit 5 实现。'
        '当前请通过 markdownToDocx + 外部 Word/LibreOffice 转 PDF。');
  }

  /// 通用：调 pandoc 子进程，stdin 喂 [input]，stdout 收字节。
  Future<Uint8List> _convert({
    required String input,
    required String fromFormat,
    required String toFormat,
    List<String> extraArgs = const [],
  }) async {
    if (!await isInstalled) {
      throw PandocException(
        'pandoc 不在 PATH 或未安装。请到 https://pandoc.org/installing.html 安装。',
      );
    }

    // 用临时文件避免 stdin/stdout 在 Windows 下编码问题。
    // 用 Directory.systemTemp（pure Dart 标准库），不走 path_provider 插件
    // ——本服务在测试 / 早期初始化场景下也能用，不依赖 plugin channel。
    final tmpDir = Directory.systemTemp;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final inputFile = File(p.join(tmpDir.path, 'pandoc_in_$stamp.$fromFormat'));
    final outputFile = File(p.join(tmpDir.path, 'pandoc_out_$stamp.$toFormat'));

    try {
      await inputFile.writeAsString(input, flush: true);

      final args = <String>[
        '-f', fromFormat,
        '-t', toFormat,
        '-o', outputFile.path,
        ...extraArgs,
        inputFile.path,
      ];

      if (kDebugMode) {
        debugPrint('[PandocService] pandoc ${args.join(' ')}');
      }

      final result = await Process.run(
        'pandoc',
        args,
        runInShell: true,
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode != 0) {
        throw PandocException(
          'pandoc 退出码 ${result.exitCode}: ${result.stderr}',
        );
      }
      if (!outputFile.existsSync()) {
        throw PandocException('pandoc 转换完成但未生成输出文件: ${outputFile.path}');
      }

      return await outputFile.readAsBytes();
    } finally {
      // 清理临时文件
      try {
        if (inputFile.existsSync()) await inputFile.delete();
      } catch (_) {/* ignore */}
      try {
        if (outputFile.existsSync()) await outputFile.delete();
      } catch (_) {/* ignore */}
    }
  }

  /// 测试用：清空安装状态缓存
  @visibleForTesting
  void resetCacheForTest() => _isInstalledCache = null;
}

class PandocException implements Exception {
  final String message;
  const PandocException(this.message);
  @override
  String toString() => 'PandocException: $message';
}
