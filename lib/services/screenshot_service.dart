import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import '../core/error_handler.dart';

class ScreenshotService {
  static final ScreenshotService instance = ScreenshotService._();
  ScreenshotService._();

  static const _cacheDir = 'screenshot_cache';
  Directory? _baseDir;

  Future<Directory> _getCacheDir() async {
    if (_baseDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      _baseDir = Directory('${appDir.path}/$_cacheDir');
    }
    if (!await _baseDir!.exists()) {
      await _baseDir!.create(recursive: true);
    }
    return _baseDir!;
  }

  /// 截图并缓存 — 使用 [repaintKey] 绑定的 RepaintBoundary
  Future<void> capture(String key, GlobalKey repaintKey) async {
    try {
      final boundary = repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_safeKey(key)}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
    } catch (e, st) {
      // 静默失败 — 不影响用户体验
      swallowDebug(e, tag: 'ScreenshotService.capture', stack: st);
    }
  }

  /// 即时截取 [repaintKey] 绑定的画面到一个唯一 PNG 文件，返回文件路径。
  ///
  /// 与 [capture] 不同：这里用时间戳生成唯一文件名（便于连续多次截图共享），
  /// 直接返回路径供调用方使用（如直播屏幕共享区）。失败返回 null。
  Future<String?> captureToFile(GlobalKey repaintKey,
      {String prefix = 'share', double pixelRatio = 2.0}) async {
    try {
      final boundary = repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final dir = await _getCacheDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/${prefix}_$ts.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file.path;
    } catch (e, st) {
      swallowDebug(e, tag: 'ScreenshotService.captureToFile', stack: st);
      return null;
    }
  }

  /// 获取缓存截图文件路径（不存在返回 null）
  Future<String?> getCapturedPath(String key) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_safeKey(key)}.png');
      if (await file.exists()) return file.path;
    } catch (e) {
      swallow(e, tag: 'ScreenshotService.getCapturedPath');
    }
    return null;
  }

  /// 检查是否存在缓存
  Future<bool> hasCapture(String key) async {
    final path = await getCapturedPath(key);
    return path != null;
  }

  /// 清除所有缓存截图
  Future<void> clearAll() async {
    try {
      final dir = await _getCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ScreenshotService.clearAll', stack: st);
    }
  }

  String _safeKey(String key) =>
      key.replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-]'), '_');
}
