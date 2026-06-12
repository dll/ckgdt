import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

/// JPEG 编码参数 — 传入 compute isolate
class _JpegEncodeParams {
  final Uint8List rgb;
  final int width;
  final int height;
  final int quality;
  const _JpegEncodeParams(this.rgb, this.width, this.height, this.quality);
}

Uint8List _encodeJpegIsolate(_JpegEncodeParams p) {
  final image = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: p.rgb.buffer,
    numChannels: 3,
  );
  return img.encodeJpg(image, quality: p.quality);
}

/// Windows 桌面抓取 — GDI `BitBlt` + `image` 包 JPEG 编码。
///
/// 捕获主显示器，缩放至目标分辨率，输出 JPEG 字节。
/// win32 5.x 的句柄类型均为 int，非 Pointer，此处已对齐。
class WinScreenCapturer {
  WinScreenCapturer._();
  static final WinScreenCapturer instance = WinScreenCapturer._();

  int _screenW = 0;
  int _screenH = 0;
  int _captureW = 1280;
  int _captureH = 720;
  int _quality = 80;
  bool _ready = false;

  void initialize({int width = 1280, int height = 720, int quality = 80}) {
    if (!Platform.isWindows) return;
    _screenW = GetSystemMetrics(SM_CXSCREEN);
    _screenH = GetSystemMetrics(SM_CYSCREEN);
    _captureW = width.clamp(320, _screenW);
    _captureH = height.clamp(240, _screenH);
    _quality = quality.clamp(10, 100);
    _ready = true;
    debugPrint('WinScreenCapturer: ${_screenW}x$_screenH → $_captureW x$_captureH q$_quality');
  }

  bool get isReady => _ready;

  /// 抓一帧桌面 → JPEG bytes。失败返回 null。
  Future<Uint8List?> capture() async {
    if (!_ready || !Platform.isWindows) return null;

    final hdcScreen = GetDC(0);
    if (hdcScreen == 0) return null;

    final hdcMem = CreateCompatibleDC(hdcScreen);
    if (hdcMem == 0) {
      ReleaseDC(0, hdcScreen);
      return null;
    }

    final hBmp = CreateCompatibleBitmap(hdcScreen, _captureW, _captureH);
    if (hBmp == 0) {
      DeleteDC(hdcMem);
      ReleaseDC(0, hdcScreen);
      return null;
    }

    SelectObject(hdcMem, hBmp);
    SetStretchBltMode(hdcMem, 4); // HALFTONE
    StretchBlt(
      hdcMem, 0, 0, _captureW, _captureH,
      hdcScreen, 0, 0, _screenW, _screenH,
      SRCCOPY,
    );

    // 分配 BITMAPINFO
    final bmi = calloc<BITMAPINFO>();
    bmi.ref.bmiHeader.biSize = 40;
    bmi.ref.bmiHeader.biWidth = _captureW;
    bmi.ref.bmiHeader.biHeight = -_captureH;
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = 0; // BI_RGB

    final pixelLen = _captureW * _captureH * 4;
    final pixels = calloc<Uint8>(pixelLen);

    final got = GetDIBits(
      hdcMem, hBmp,
      0, _captureH,
      pixels.cast<Void>(),
      bmi,
      0,
    );

    // 清理
    DeleteObject(hBmp);
    DeleteDC(hdcMem);
    ReleaseDC(0, hdcScreen);

    if (got == 0) {
      free(pixels);
      free(bmi);
      return null;
    }

    // BGRA → RGB
    final rgb = Uint8List(_captureW * _captureH * 3);
    for (int i = 0; i < _captureW * _captureH; i++) {
      final off = i * 4;
      final rgbOff = i * 3;
      rgb[rgbOff] = pixels[off + 2];
      rgb[rgbOff + 1] = pixels[off + 1];
      rgb[rgbOff + 2] = pixels[off];
    }

    free(pixels);
    free(bmi);

    return compute(_encodeJpegIsolate,
        _JpegEncodeParams(rgb, _captureW, _captureH, _quality));
  }

  void updateSize({int? width, int? height, int? quality}) {
    if (width != null && height != null) {
      _captureW = width.clamp(320, _screenW);
      _captureH = height.clamp(240, _screenH);
    }
    if (quality != null) _quality = quality.clamp(10, 100);
  }
}
