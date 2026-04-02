/// 平台初始化 — 原生平台（Windows/macOS/Linux/Android/iOS）
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

Future<void> initPlatform() async {
  // Windows/Linux/macOS 桌面端需要 FFI 初始化 sqflite
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint('=== main: sqflite FFI initialized for desktop platform');
  }

  // 仅在移动端锁定竖屏，桌面端不限制
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
}
