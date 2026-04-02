/// 平台初始化 — Web 平台
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';

Future<void> initPlatform() async {
  // Web 平台使用 sqflite_common_ffi_web（基于 sql.js WASM）
  databaseFactory = databaseFactoryFfiWeb;
  debugPrint('=== main: sqflite FFI Web initialized for web platform');
}
