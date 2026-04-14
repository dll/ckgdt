import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 使用系统安装的 PowerPoint / WPS 将 PPTX 幻灯片导出为高清 PNG 图片
///
/// 仅 Windows 平台可用，通过 PowerShell 调用 COM 自动化接口。
/// 导出结果会按 文件路径+修改时间+大小 进行缓存，重复打开秒开。
class PptExportService {
  // ── 公开 API ──────────────────────────────────────────────────────────

  /// 导出 PPTX 每页为 PNG，返回按页码排序的文件列表；失败返回 null
  static Future<List<File>?> exportSlides(String pptxPath) async {
    if (!Platform.isWindows) return null;

    final pptFile = File(pptxPath);
    if (!await pptFile.exists()) return null;

    // 缓存目录：基于文件路径 + 修改时间 + 大小
    final stat = await pptFile.stat();
    final cacheKey = '${pptxPath.hashCode.toRadixString(16)}'
        '_${stat.modified.millisecondsSinceEpoch}'
        '_${stat.size}';

    final tempDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tempDir.path, 'ppt_slides', cacheKey));

    // 命中缓存
    if (await outDir.exists()) {
      final cached = await _loadImages(outDir);
      if (cached.isNotEmpty) {
        debugPrint('PptExport: 缓存命中 (${cached.length} 页)');
        return cached;
      }
    }

    // 创建输出目录
    await outDir.create(recursive: true);

    // 构建 PowerShell 脚本
    final absPath = pptFile.absolute.path;
    final script = _buildScript(absPath, outDir.path);

    debugPrint('PptExport: 正在通过 COM 导出幻灯片...');

    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 120));

      if (result.exitCode == 0) {
        final images = await _loadImages(outDir);
        if (images.isNotEmpty) {
          debugPrint('PptExport: 成功导出 ${images.length} 页');
          return images;
        }
      }

      debugPrint('PptExport: 导出失败 (exit=${result.exitCode})\n'
          'stderr: ${result.stderr}');
    } catch (e) {
      debugPrint('PptExport: 导出异常: $e');
    }

    // 清理失败的导出目录
    try {
      await outDir.delete(recursive: true);
    } catch (_) {}
    return null;
  }

  /// 清空所有缓存
  static Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'ppt_slides'));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  // ── 内部实现 ──────────────────────────────────────────────────────────

  /// 构建 PowerShell 脚本：先尝试 PowerPoint COM，失败再试 WPS COM
  static String _buildScript(String pptxPath, String outDir) {
    // 转义 PowerShell 单引号
    final ePath = pptxPath.replaceAll("'", "''");
    final eOut = outDir.replaceAll("'", "''");

    // 脚本说明：
    // 1) 尝试创建 PowerPoint.Application COM 对象
    // 2) 失败则尝试 KWPP.Application（WPS 演示）
    // 3) 以只读、无窗口方式打开演示文稿
    // 4) 逐页导出为 1920×1080 PNG
    // 5) 关闭并释放 COM 对象
    return '''
\$ErrorActionPreference = 'Stop'
\$pptApp = \$null
try { \$pptApp = New-Object -ComObject PowerPoint.Application } catch {}
if (\$pptApp -eq \$null) {
  try { \$pptApp = New-Object -ComObject KWPP.Application } catch { exit 1 }
}
try {
  \$pres = \$pptApp.Presentations.Open('$ePath', -1, 0, 0)
  for (\$i = 1; \$i -le \$pres.Slides.Count; \$i++) {
    \$outFile = '$eOut\\slide_' + \$i.ToString().PadLeft(3,'0') + '.png'
    \$pres.Slides.Item(\$i).Export(\$outFile, 'PNG', 1920, 1080)
  }
  \$pres.Close()
} finally {
  if (\$pptApp -ne \$null) {
    \$pptApp.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$pptApp) | Out-Null
  }
}
''';
  }

  /// 从目录加载 PNG 文件，按文件名排序
  static Future<List<File>> _loadImages(Directory dir) async {
    if (!await dir.exists()) return [];
    final entries = await dir.list().toList();
    final images = entries
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return images;
  }
}
