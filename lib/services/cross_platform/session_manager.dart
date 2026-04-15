import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// 会话管理器 — 生成/验证连接令牌，管理已连接设备
class SessionManager {
  static final SessionManager _instance = SessionManager._();
  factory SessionManager() => _instance;
  SessionManager._();

  /// 已发放的 API token → 用户信息
  final Map<String, ConnectedDevice> _devices = {};

  /// 当前活跃的 QR 登录请求  qrToken → QrSession
  final Map<String, QrSession> _qrSessions = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Token 管理
  // ─────────────────────────────────────────────────────────────────────────

  /// 生成 32 字符随机令牌
  String generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).substring(0, 32);
  }

  /// 为已认证设备颁发令牌
  String issueDeviceToken({
    required String userId,
    required String deviceName,
    required String platform,
  }) {
    final token = generateToken();
    _devices[token] = ConnectedDevice(
      token: token,
      userId: userId,
      deviceName: deviceName,
      platform: platform,
      connectedAt: DateTime.now(),
      lastSeen: DateTime.now(),
    );
    return token;
  }

  /// 验证令牌
  ConnectedDevice? validateToken(String token) {
    final device = _devices[token];
    if (device != null) {
      device.lastSeen = DateTime.now();
    }
    return device;
  }

  /// 撤销令牌
  void revokeToken(String token) => _devices.remove(token);

  /// 获取所有已连接设备
  List<ConnectedDevice> get connectedDevices => _devices.values.toList();

  /// 清理超时设备（默认30分钟）
  void cleanupStale({Duration timeout = const Duration(minutes: 30)}) {
    final now = DateTime.now();
    _devices.removeWhere((_, d) => now.difference(d.lastSeen) > timeout);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QR 登录流程
  // ─────────────────────────────────────────────────────────────────────────

  /// 创建 QR 登录会话（桌面端调用）
  QrSession createQrSession() {
    // 清理过期 QR 会话（5分钟有效）
    final now = DateTime.now();
    _qrSessions.removeWhere(
        (_, s) => now.difference(s.createdAt) > const Duration(minutes: 5));

    final qrToken = generateToken();
    final session = QrSession(
      qrToken: qrToken,
      createdAt: now,
    );
    _qrSessions[qrToken] = session;
    return session;
  }

  /// 确认 QR 登录（移动端扫码后调用）
  bool confirmQrLogin({
    required String qrToken,
    required String userId,
    required String realName,
    required String role,
  }) {
    final session = _qrSessions[qrToken];
    if (session == null || session.isConfirmed) return false;

    // 检查是否过期（5分钟）
    if (DateTime.now().difference(session.createdAt) >
        const Duration(minutes: 5)) {
      _qrSessions.remove(qrToken);
      return false;
    }

    session.confirmedUserId = userId;
    session.confirmedRealName = realName;
    session.confirmedRole = role;
    session.confirmedAt = DateTime.now();
    return true;
  }

  /// 查询 QR 登录状态（桌面端轮询）
  QrSession? checkQrSession(String qrToken) => _qrSessions[qrToken];

  /// 消费 QR 会话（登录成功后清理）
  void consumeQrSession(String qrToken) => _qrSessions.remove(qrToken);

  // ─────────────────────────────────────────────────────────────────────────
  // 密码验证辅助
  // ─────────────────────────────────────────────────────────────────────────

  /// SHA-256 哈希（与 AuthService 保持一致）
  static String hashPassword(String password, String userId) {
    final bytes = utf8.encode('$userId:$password');
    return sha256.convert(bytes).toString();
  }
}

/// 已连接的设备信息
class ConnectedDevice {
  final String token;
  final String userId;
  final String deviceName;
  final String platform; // 'android', 'windows', 'web'
  final DateTime connectedAt;
  DateTime lastSeen;

  ConnectedDevice({
    required this.token,
    required this.userId,
    required this.deviceName,
    required this.platform,
    required this.connectedAt,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'deviceName': deviceName,
        'platform': platform,
        'connectedAt': connectedAt.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
      };
}

/// QR 登录会话
class QrSession {
  final String qrToken;
  final DateTime createdAt;
  String? confirmedUserId;
  String? confirmedRealName;
  String? confirmedRole;
  DateTime? confirmedAt;

  QrSession({required this.qrToken, required this.createdAt});

  bool get isConfirmed => confirmedUserId != null;
  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 5);

  Map<String, dynamic> toJson() => {
        'qrToken': qrToken,
        'createdAt': createdAt.toIso8601String(),
        'isConfirmed': isConfirmed,
        'confirmedUserId': confirmedUserId,
        'confirmedRealName': confirmedRealName,
        'confirmedRole': confirmedRole,
      };
}
