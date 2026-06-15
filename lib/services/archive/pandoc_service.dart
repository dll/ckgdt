import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../core/error_handler.dart';

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
  /// **两步走**：pandoc md → docx（继承学校样式）→ LibreOffice headless docx → pdf。
  /// 这样保证打印产出和归档 docx 视觉一致，避免直接 pandoc + LaTeX 的字体 / 中文坑。
  ///
  /// **依赖**：用户机器上需装 LibreOffice（`soffice.exe`）。校区一般已装；
  /// 没装时抛 [PandocException] 提示安装地址。
  ///
  /// 检测顺序：PATH `soffice` → `C:\Program Files\LibreOffice\program\soffice.exe`
  /// → `C:\Program Files (x86)\LibreOffice\program\soffice.exe`。
  Future<Uint8List> markdownToPdf(
    String markdown, {
    String? referenceDocPath,
  }) async {
    if (markdown.isEmpty) {
      throw const PandocException('markdown 内容为空，无法转 PDF');
    }

    // 第 1 步：md → docx（继承样式）
    final docxBytes = await markdownToDocx(
      markdown,
      referenceDocPath: referenceDocPath,
    );

    // 第 2 步：docx → pdf
    return _docxToPdfViaSoffice(docxBytes);
  }

  /// 用 LibreOffice headless 把 docx 字节转 PDF 字节。
  Future<Uint8List> _docxToPdfViaSoffice(Uint8List docxBytes) async {
    final soffice = await _findSoffice();
    if (soffice == null) {
      throw const PandocException(
        '未找到 LibreOffice (soffice.exe)。请到 https://www.libreoffice.org/download/ '
        '下载安装，或确保 soffice 在 PATH 中。',
      );
    }

    final tmpDir = Directory.systemTemp;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final inputDocx = File(p.join(tmpDir.path, 'mad_print_$stamp.docx'));
    // soffice 输出 PDF 同名替换扩展，所以 outDir 给 tmpDir，输出文件就是 mad_print_$stamp.pdf
    final outputPdf = File(p.join(tmpDir.path, 'mad_print_$stamp.pdf'));

    try {
      await inputDocx.writeAsBytes(docxBytes, flush: true);

      if (kDebugMode) {
        debugPrint(
            '[PandocService] soffice convert: $soffice → ${inputDocx.path}');
      }

      final result = await Process.run(
        soffice,
        [
          '--headless',
          '--norestore',
          '--nologo',
          '--convert-to',
          'pdf',
          '--outdir',
          tmpDir.path,
          inputDocx.path,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 90));

      if (result.exitCode != 0) {
        throw PandocException(
          'LibreOffice 退出码 ${result.exitCode}: ${result.stderr}',
        );
      }
      if (!outputPdf.existsSync()) {
        throw PandocException(
          'LibreOffice 转换完成但未生成 PDF: ${outputPdf.path}\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
      }

      return await outputPdf.readAsBytes();
    } finally {
      try {
        if (inputDocx.existsSync()) await inputDocx.delete();
      } catch (e) {
        swallow(e, tag: 'PandocService.cleanup.inputDocx');
      }
      try {
        if (outputPdf.existsSync()) await outputPdf.delete();
      } catch (e) {
        swallow(e, tag: 'PandocService.cleanup.outputPdf');
      }
    }
  }

  /// 用 LibreOffice headless 把 Office 原件转为 PDF。
  ///
  /// 期末归档大量材料已经是学校定稿 doc/docx/xls/xlsx 原件，预览和打印应以
  /// 原件版式为准，而不是先抽取文本再走 Markdown/Pandoc。
  Future<Uint8List> officeFileToPdf(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw PandocException('原始文件不存在：$sourcePath');
    }
    final ext = p.extension(source.path).toLowerCase();
    if (ext == '.pdf') return source.readAsBytes();

    final soffice = await _findSoffice();
    if (soffice != null) {
      try {
        return await _officeFileToPdfViaSoffice(sourcePath, soffice);
      } on PandocException catch (e) {
        if (kDebugMode) {
          debugPrint(
              '[PandocService] LibreOffice 原件转 PDF 失败，尝试 Office COM: $e');
        }
      }
    }

    if (Platform.isWindows) {
      try {
        return await _officeFileToPdfViaMicrosoftOffice(sourcePath);
      } on PandocException {
        rethrow;
      } on Exception catch (e) {
        throw PandocException('Microsoft Office/WPS 转 PDF 失败：$e');
      }
    }

    throw const PandocException(
      '未找到 LibreOffice (soffice.exe)，无法预览或打印 Office 原件。'
      '请安装 LibreOffice，或在 Windows 教师端安装 Microsoft Office/WPS 后重试。',
    );
  }

  Future<Uint8List> _officeFileToPdfViaSoffice(
    String sourcePath,
    String soffice,
  ) async {
    final source = File(sourcePath);
    final ext = p.extension(source.path).toLowerCase();
    final tmpDir = await Directory.systemTemp.createTemp('mad_office_pdf_');
    final input = File(p.join(tmpDir.path, 'source$ext'));
    final output = File(p.join(tmpDir.path, 'source.pdf'));
    try {
      await source.copy(input.path);
      final result = await Process.run(
        soffice,
        [
          '--headless',
          '--norestore',
          '--nologo',
          '--convert-to',
          'pdf',
          '--outdir',
          tmpDir.path,
          input.path,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 90));

      if (result.exitCode != 0) {
        throw PandocException(
          'LibreOffice 退出码 ${result.exitCode}: ${result.stderr}',
        );
      }
      if (!output.existsSync()) {
        throw PandocException(
          'LibreOffice 转换完成但未生成 PDF: ${output.path}\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
      }
      return await output.readAsBytes();
    } finally {
      try {
        if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
      } catch (e) {
        swallow(e, tag: 'PandocService.cleanup.officePdf');
      }
    }
  }

  Future<Uint8List> _officeFileToPdfViaMicrosoftOffice(
    String sourcePath,
  ) async {
    final ext = p.extension(sourcePath).toLowerCase();
    if (!const {
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
    }.contains(ext)) {
      throw PandocException('该原件类型暂不支持转换 PDF：$ext');
    }

    final tmpDir = await Directory.systemTemp.createTemp('mad_ms_office_pdf_');
    final input = File(p.join(tmpDir.path, 'source$ext'));
    final output = File(p.join(tmpDir.path, 'source.pdf'));
    await File(sourcePath).copy(input.path);
    final script = _officeComScript(
      sourcePath: input.path,
      outputPath: output.path,
      ext: ext,
    );
    final scriptFile = File(p.join(tmpDir.path, 'convert.ps1'));
    try {
      await scriptFile.writeAsString(script, flush: true);
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 90));
      if (result.exitCode != 0) {
        throw PandocException(
          'Office COM 退出码 ${result.exitCode}: ${result.stderr}${result.stdout}',
        );
      }
      if (!output.existsSync()) {
        throw PandocException(
          'Office COM 转换完成但未生成 PDF: ${output.path}\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
      }
      return await output.readAsBytes();
    } finally {
      try {
        if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
      } catch (e) {
        swallow(e, tag: 'PandocService.cleanup.msOfficePdf');
      }
    }
  }

  String _officeComScript({
    required String sourcePath,
    required String outputPath,
    required String ext,
  }) {
    final source = _psQuote(sourcePath);
    final output = _psQuote(outputPath);
    if (ext == '.doc' || ext == '.docx') {
      return '''
\$ErrorActionPreference = 'Stop'
\$source = $source
\$output = $output
\$word = \$null
\$doc = \$null
try {
  \$word = New-Object -ComObject Word.Application
  \$word.Visible = \$false
  \$word.DisplayAlerts = 0
  \$doc = \$word.Documents.Open(\$source, \$false, \$true)
  \$doc.ExportAsFixedFormat(\$output, 17)
} finally {
  if (\$doc -ne \$null) {
    \$doc.Close(\$false) | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$doc)
  }
  if (\$word -ne \$null) {
    \$word.Quit() | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$word)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
''';
    }
    if (ext == '.xls' || ext == '.xlsx') {
      return '''
\$ErrorActionPreference = 'Stop'
\$source = $source
\$output = $output
\$excel = \$null
\$workbook = \$null
try {
  \$excel = New-Object -ComObject Excel.Application
  \$excel.Visible = \$false
  \$excel.DisplayAlerts = \$false
  \$workbook = \$excel.Workbooks.Open(\$source, 0, \$true)
  \$workbook.ExportAsFixedFormat(0, \$output)
} finally {
  if (\$workbook -ne \$null) {
    \$workbook.Close(\$false) | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$workbook)
  }
  if (\$excel -ne \$null) {
    \$excel.Quit() | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$excel)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
''';
    }
    return '''
\$ErrorActionPreference = 'Stop'
\$source = $source
\$output = $output
\$powerPoint = \$null
\$presentation = \$null
try {
  \$powerPoint = New-Object -ComObject PowerPoint.Application
  \$presentation = \$powerPoint.Presentations.Open(\$source, \$true, \$true, \$false)
  \$presentation.SaveAs(\$output, 32)
} finally {
  if (\$presentation -ne \$null) {
    \$presentation.Close() | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$presentation)
  }
  if (\$powerPoint -ne \$null) {
    \$powerPoint.Quit() | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$powerPoint)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
''';
  }

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  /// 探测 LibreOffice 可执行文件路径。命中即缓存。
  Future<String?> _findSoffice() async {
    if (_sofficePathCache != null) return _sofficePathCache;
    if (!isAvailable) return null;

    // 1) PATH 中的 soffice
    try {
      final r = await Process.run('soffice', ['--version'], runInShell: true)
          .timeout(const Duration(seconds: 5));
      if (r.exitCode == 0) return _sofficePathCache = 'soffice';
    } on Exception catch (e) {
      swallow(e, tag: 'PandocService._findSoffice.path');
    }

    // 2) Windows 默认安装路径
    if (Platform.isWindows) {
      const candidates = [
        r'C:\Program Files\LibreOffice\program\soffice.exe',
        r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) return _sofficePathCache = c;
      }
    } else if (Platform.isMacOS) {
      const mac = '/Applications/LibreOffice.app/Contents/MacOS/soffice';
      if (File(mac).existsSync()) return _sofficePathCache = mac;
    } else if (Platform.isLinux) {
      const linuxCandidates = ['/usr/bin/soffice', '/usr/bin/libreoffice'];
      for (final c in linuxCandidates) {
        if (File(c).existsSync()) return _sofficePathCache = c;
      }
    }

    return null;
  }

  String? _sofficePathCache;

  /// 通用：调 pandoc 子进程，stdin 喂 [input]，stdout 收字节。
  Future<Uint8List> _convert({
    required String input,
    required String fromFormat,
    required String toFormat,
    List<String> extraArgs = const [],
  }) async {
    if (!await isInstalled) {
      throw const PandocException(
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
        '-f',
        fromFormat,
        '-t',
        toFormat,
        '-o',
        outputFile.path,
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
      } catch (e) {
        swallow(e, tag: 'PandocService.cleanup.input');
      }
      try {
        if (outputFile.existsSync()) await outputFile.delete();
      } catch (e) {
        swallow(e, tag: 'PandocService.cleanup.output');
      }
    }
  }

  /// 测试用：清空安装状态缓存
  @visibleForTesting
  void resetCacheForTest() {
    _isInstalledCache = null;
    _sofficePathCache = null;
  }
}

class PandocException implements Exception {
  final String message;
  const PandocException(this.message);
  @override
  String toString() => 'PandocException: $message';
}
