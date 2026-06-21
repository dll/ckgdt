/// 同步服务器 — 条件导入门面
///
/// - 非 Web 平台（Windows/Android/macOS/Linux）：使用 dart:io 实现
/// - Web 平台：使用空壳实现（不支持运行服务器）
library;
export 'sync_server_stub.dart'
    if (dart.library.io) 'sync_server_io.dart';
