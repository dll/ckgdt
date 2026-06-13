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
  int _screenX = 0;
  int _screenY = 0;
  int _captureW = 1280;
  int _captureH = 720;
  int _quality = 80;
  bool _ready = false;
  bool _lastFrameLooksBlack = false;

  void initialize({int width = 1280, int height = 720, int quality = 80}) {
    if (!Platform.isWindows) return;
    _screenX = GetSystemMetrics(SM_XVIRTUALSCREEN);
    _screenY = GetSystemMetrics(SM_YVIRTUALSCREEN);
    _screenW = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    _screenH = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (_screenW <= 0 || _screenH <= 0) {
      _screenX = 0;
      _screenY = 0;
      _screenW = GetSystemMetrics(SM_CXSCREEN);
      _screenH = GetSystemMetrics(SM_CYSCREEN);
    }
    _captureW = width.clamp(320, _screenW);
    _captureH = height.clamp(240, _screenH);
    _quality = quality.clamp(10, 100);
    _lastFrameLooksBlack = false;
    _ready = true;
    debugPrint(
        'WinScreenCapturer: virtual=$_screenX,$_screenY ${_screenW}x$_screenH -> $_captureW x$_captureH q$_quality');
  }

  bool get isReady => _ready;
  bool get lastFrameLooksBlack => _lastFrameLooksBlack;

  void minimizeForegroundWindow() {
    if (!Platform.isWindows) return;
    final hwnd = GetForegroundWindow();
    if (hwnd != 0) {
      // Do not minimize: some Flutter desktop builds throttle Dart timers when
      // minimized, which freezes the capture loop. Keep the window alive but
      // move it to a small corner so it no longer covers the demonstrated app.
      ShowWindowAsync(hwnd, SW_RESTORE);
      const w = 360;
      const h = 220;
      final x = _screenX + _screenW - w - 24;
      final y = _screenY + _screenH - h - 72;
      MoveWindow(hwnd, x, y, w, h, 1);
      SetWindowPos(hwnd, HWND_BOTTOM, x, y, w, h, SWP_NOACTIVATE);
    }
  }

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

    final bmi = calloc<BITMAPINFO>();
    final bits = calloc<Pointer>();
    bmi.ref.bmiHeader.biSize = 40;
    bmi.ref.bmiHeader.biWidth = _captureW;
    // Top-down DIB: memory order matches the screen's top-to-bottom order.
    bmi.ref.bmiHeader.biHeight = -_captureH;
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;

    final hBmp = CreateDIBSection(
      hdcScreen,
      bmi,
      0, // DIB_RGB_COLORS
      bits,
      0,
      0,
    );
    if (hBmp == 0) {
      free(bits);
      free(bmi);
      DeleteDC(hdcMem);
      ReleaseDC(0, hdcScreen);
      return null;
    }

    final oldObj = SelectObject(hdcMem, hBmp);
    SetStretchBltMode(hdcMem, HALFTONE);
    final copied = StretchBlt(
      hdcMem,
      0,
      0,
      _captureW,
      _captureH,
      hdcScreen,
      _screenX,
      _screenY,
      _screenW,
      _screenH,
      SRCCOPY | CAPTUREBLT,
    );

    if (copied == 0 || bits.value == nullptr) {
      if (oldObj != 0) SelectObject(hdcMem, oldObj);
      DeleteObject(hBmp);
      free(bits);
      free(bmi);
      DeleteDC(hdcMem);
      ReleaseDC(0, hdcScreen);
      return null;
    }

    // BGRA → RGB
    final rgb = Uint8List(_captureW * _captureH * 3);
    final pixels = bits.value.cast<Uint8>();
    var brightSamples = 0;
    final sampleStep = (_captureW * _captureH ~/ 4096).clamp(1, 4096);
    for (int i = 0; i < _captureW * _captureH; i++) {
      final off = i * 4;
      final rgbOff = i * 3;
      final b = pixels[off];
      final g = pixels[off + 1];
      final r = pixels[off + 2];
      rgb[rgbOff] = r;
      rgb[rgbOff + 1] = g;
      rgb[rgbOff + 2] = b;
      if (i % sampleStep == 0 && (r > 12 || g > 12 || b > 12)) {
        brightSamples++;
      }
    }

    if (oldObj != 0) SelectObject(hdcMem, oldObj);
    DeleteObject(hBmp);
    free(bits);
    free(bmi);
    DeleteDC(hdcMem);
    ReleaseDC(0, hdcScreen);

    _lastFrameLooksBlack = brightSamples == 0;
    if (_lastFrameLooksBlack) {
      debugPrint('WinScreenCapturer: captured a fully black frame');
      return null;
    }

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
