/// Web 平台桩文件 — dart:io 不可用时提供空实现
///
/// 在 Web 上 SyncServer 所有方法均为空操作。
library;
import 'session_manager.dart';

class SyncServerImpl {
  bool get isRunning => false;
  String? get host => null;
  int get port => 0;
  String? get serverUrl => null;

  final SessionManager sessionManager = SessionManager();

  /// 登录回调
  void Function(String userId, String realName, String role)? onQrLoginConfirmed;
  /// 数据推送回调
  void Function(String userId)? onDataPushed;

  Future<void> start({int port = 8765}) async {
    throw UnsupportedError('SyncServer 不支持 Web 平台');
  }

  Future<void> stop() async {}

  Future<String?> getLocalIp() async => null;

  void broadcast(String event, [Map<String, dynamic>? data]) {}
}
