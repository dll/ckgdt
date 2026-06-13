import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/error_handler.dart';

/// 局域网答辩直播自动发现：UDP 广播（信标）+ 监听（发现）。
///
/// 教师主播/演示端用 [LanDiscoveryBeacon] 每 2s 向广播地址发一条 JSON，
/// 学生/观看端用 [LanDiscoveryListener] 在固定端口监听，自动得到教师 IP+端口，
/// 免去手动输 IP、免依赖公网 Gitee。
///
/// 纯 dart:io，无新依赖。被交换机/AP client-isolation 拦截时上层仍可回退手动输 IP。
const int kLanDiscoveryPort = 8767;
const String _kBroadcastAddr = '255.255.255.255';

/// 一条被发现的直播源记录。
class LanDiscoveryEntry {
  final String ip;
  final int port;
  String role; // presenter / present — 可被后续信标更新（教师切换主播/演示）
  String hostName;
  DateTime lastSeen;

  LanDiscoveryEntry({
    required this.ip,
    required this.port,
    required this.role,
    required this.hostName,
    required this.lastSeen,
  });

  String get serverUrl => 'http://$ip:$port';
  String get feedUrl => '$serverUrl/stream/feed';
  String get roleLabel => role == 'present' ? '教师演示' : '主播';
  String get displayName => hostName.isNotEmpty ? hostName : ip;
}

/// 教师端信标：周期性向局域网广播自己的服务器信息。
class LanDiscoveryBeacon {
  RawDatagramSocket? _socket;
  Timer? _timer;
  bool _running = false;

  String _ip = '';
  int _port = 8766;
  String _role = 'presenter';
  String _hostName = '';

  bool get isRunning => _running;

  /// 开始广播。[ip]/[port] 为本机答辩服务器地址，[role] = presenter / present。
  Future<void> start({
    required String ip,
    required int port,
    required String role,
    String hostName = '',
  }) async {
    if (_running) {
      // 已在跑：更新参数即可（教师从主播切到演示等）。
      _ip = ip;
      _port = port;
      _role = role;
      if (hostName.isNotEmpty) _hostName = hostName;
      return;
    }
    _ip = ip;
    _port = port;
    _role = role;
    _hostName = hostName.isNotEmpty ? hostName : Platform.localHostname;

    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
      _running = true;
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _send());
      _send();
      debugPrint('LanDiscoveryBeacon: broadcasting $role at $ip:$port');
    } catch (e, st) {
      swallowDebug(e, tag: 'LanDiscovery.beacon.start', stack: st);
      _running = false;
    }
  }

  void _send() {
    final s = _socket;
    if (s == null || !_running) return;
    try {
      final payload = jsonEncode({
        'mad': 'defense', // 标识本应用的发现报文，过滤无关 UDP
        'role': _role,
        'ip': _ip,
        'port': _port,
        'hostName': _hostName,
        'ts': DateTime.now().toIso8601String(),
      });
      s.send(utf8.encode(payload), InternetAddress(_kBroadcastAddr), kLanDiscoveryPort);
    } catch (e, st) {
      swallowDebug(e, tag: 'LanDiscovery.beacon.send', stack: st);
    }
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// 学生/观看端监听器：在固定端口收信标，去重 + 过期清理后回调当前直播源列表。
class LanDiscoveryListener {
  RawDatagramSocket? _socket;
  Timer? _sweepTimer;
  bool _running = false;

  final Map<String, LanDiscoveryEntry> _entries = {}; // key = ip:port
  void Function(List<LanDiscoveryEntry> entries)? onUpdate;

  /// 仅关心这些角色（空 = 全部）。学生答辩通常只关心 presenter。
  final Set<String> roleFilter;

  /// 超过此时长未再收到信标即视为下线。
  static const _ttl = Duration(seconds: 8);

  LanDiscoveryListener({this.roleFilter = const {}});

  bool get isRunning => _running;
  List<LanDiscoveryEntry> get entries => _entries.values.toList();

  Future<void> start() async {
    if (_running) return;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kLanDiscoveryPort,
        reuseAddress: true,
        // SO_REUSEPORT 在 Windows 不支持，开了会 bind 抛错导致发现静默失效。
        reusePort: !Platform.isWindows,
      );
      _running = true;
      _socket!.listen(_onEvent, onError: (e, st) => swallowDebug(e, tag: 'LanDiscovery.listen.err', stack: st));
      _sweepTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sweep());
      debugPrint('LanDiscoveryListener: listening on $kLanDiscoveryPort, filter=$roleFilter');
    } catch (e, st) {
      swallowDebug(e, tag: 'LanDiscovery.listen.start', stack: st);
      _running = false;
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final data = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (data['mad'] != 'defense') return;
      final role = (data['role'] as String?) ?? '';
      if (roleFilter.isNotEmpty && !roleFilter.contains(role)) return;
      final ip = (data['ip'] as String?) ?? dg.address.address;
      final port = (data['port'] as int?) ?? 8766;
      if (ip.isEmpty) return;
      final key = '$ip:$port';
      final existing = _entries[key];
      if (existing != null) {
        existing.lastSeen = DateTime.now();
        // 教师可能切换 presenter↔present，刷新缓存避免标签/过滤用旧角色。
        if (existing.role != role) {
          existing.role = role;
          onUpdate?.call(entries);
        }
      } else {
        _entries[key] = LanDiscoveryEntry(
          ip: ip,
          port: port,
          role: role,
          hostName: (data['hostName'] as String?) ?? '',
          lastSeen: DateTime.now(),
        );
        onUpdate?.call(entries);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LanDiscovery.listen.parse', stack: st);
    }
  }

  void _sweep() {
    final now = DateTime.now();
    final dead = _entries.entries
        .where((e) => now.difference(e.value.lastSeen) > _ttl)
        .map((e) => e.key)
        .toList();
    if (dead.isEmpty) return;
    for (final k in dead) {
      _entries.remove(k);
    }
    onUpdate?.call(entries);
  }

  void stop() {
    _running = false;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _socket?.close();
    _socket = null;
    _entries.clear();
  }
}
