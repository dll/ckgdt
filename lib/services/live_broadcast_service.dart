import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/error_handler.dart';
import 'auth_service.dart';
import 'gitee_service.dart';
import 'live_stream_service.dart';
import 'sync_service.dart';

/// 一场正在进行（或刚结束）的直播会话，来自 Gitee `live/{userId}/status.json`。
class LiveSession {
  final String userId;
  final String userName;
  final String role;
  final bool isLive;
  final DateTime updatedAt;
  final String snapshotPath; // Gitee 仓库内路径，用 getRawUrl 取图

  const LiveSession({
    required this.userId,
    required this.userName,
    required this.role,
    required this.isLive,
    required this.updatedAt,
    required this.snapshotPath,
  });

  /// 超过此时长未刷新即视为已下播（防止异常退出后僵尸会话长挂）。
  static const staleAfter = Duration(seconds: 30);
  bool get isFresh => DateTime.now().difference(updatedAt) < staleAfter;
  bool get isActive => isLive && isFresh;

  static LiveSession? fromJson(String userId, String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      return LiveSession(
        userId: userId,
        userName: m['name'] as String? ?? userId,
        role: m['role'] as String? ?? 'student',
        isLive: m['isLive'] as bool? ?? false,
        updatedAt:
            DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime(2000),
        snapshotPath: m['snapshotPath'] as String? ?? 'live/$userId/snapshot.jpg',
      );
    } catch (e) {
      swallow(e, tag: 'LiveSession.fromJson');
      return null;
    }
  }
}

/// 快照广播直播 — 基于 Gitee 仓库文件的"准实时"直播。
///
/// 受限于无实时服务器（仅 Gitee 仓库同步），无法推真实视频流。改为：
/// - **开播端**：每 [_broadcastInterval] 抓一帧摄像头快照，连同 status.json
///   覆盖写到 `live/{userId}/`（单文件覆盖，不堆积，省仓库空间）。
/// - **观看端**：每 [_pollInterval] 列 `live/` 目录、读各 status.json，
///   汇总"正在直播"的会话，通过 [sessionsNotifier] 推给 UI（横幅 + 快照查看）。
/// - **授权**：教师把允许开播的 userId 写入 `live/authorized.json`；开播端开播前
///   校验自己在册（管理员/教师本身始终可开播）。
class LiveBroadcastService {
  LiveBroadcastService._();
  static final LiveBroadcastService instance = LiveBroadcastService._();

  final _gitee = GiteeService();
  final _auth = AuthService();

  static const _broadcastInterval = Duration(seconds: 4);
  static const _pollInterval = Duration(seconds: 6);
  static const _liveDir = 'live';

  // ── 观看端 ────────────────────────────────────────────────────────────
  /// 当前活跃直播会话列表（已按 isActive 过滤），供横幅/列表订阅。
  final ValueNotifier<List<LiveSession>> sessionsNotifier =
      ValueNotifier<List<LiveSession>>(const []);
  Timer? _pollTimer;

  // ── 开播端 ────────────────────────────────────────────────────────────
  /// 当前设备是否正在开播。
  final ValueNotifier<bool> broadcastingNotifier = ValueNotifier<bool>(false);
  Timer? _broadcastTimer;
  bool _uploading = false;

  String get _owner => SyncService.repoOwner;
  String get _repo => SyncService.repoName;
  String get _branch => SyncService.repoBranch;

  // ════════════════════════════════════════════════════════════════════
  // 观看端：轮询
  // ════════════════════════════════════════════════════════════════════

  /// 登录后调用：开始轮询 live/ 目录。重复调用安全（先停再起）。
  void startWatching() {
    _pollTimer?.cancel();
    _pollOnce();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void stopWatching() {
    _pollTimer?.cancel();
    _pollTimer = null;
    sessionsNotifier.value = const [];
  }

  Future<void> _pollOnce() async {
    try {
      final entries = await _gitee.listDir(_owner, _repo, _liveDir);
      final sessions = <LiveSession>[];
      for (final e in entries) {
        if (e['type'] != 'dir') continue;
        final uid = e['name'] as String?;
        if (uid == null) continue;
        final statusJson = await _gitee.getFileContent(
            _owner, _repo, '$_liveDir/$uid/status.json',
            ref: _branch);
        if (statusJson == null) continue;
        final session = LiveSession.fromJson(uid, statusJson);
        if (session != null && session.isActive) sessions.add(session);
      }
      // 自己正在开播的会话不展示给自己
      final myId = _auth.currentUser?.userId;
      sessions.removeWhere((s) => s.userId == myId);
      sessionsNotifier.value = sessions;
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveBroadcast.poll', stack: st);
    }
  }

  /// 取某会话最新快照的可访问 URL（带 token，私有仓库可读）。
  Future<String> snapshotUrl(LiveSession s) =>
      _gitee.getRawUrl(_owner, _repo, s.snapshotPath, ref: _branch);

  // ════════════════════════════════════════════════════════════════════
  // 授权（教师）
  // ════════════════════════════════════════════════════════════════════

  /// 读取当前被授权可开播的 userId 列表。
  Future<List<String>> getAuthorizedIds() async {
    try {
      final json = await _gitee.getFileContent(
          _owner, _repo, '$_liveDir/authorized.json',
          ref: _branch);
      if (json == null) return [];
      final list = jsonDecode(json) as List;
      return list.map((e) => e.toString()).toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveBroadcast.getAuthorized', stack: st);
      return [];
    }
  }

  /// 教师设置授权名单（覆盖写）。
  Future<bool> setAuthorizedIds(List<String> ids) async {
    if (!_auth.isTeacher && !_auth.isAdmin) return false;
    try {
      await _gitee.createOrUpdateFile(
        owner: _owner,
        repo: _repo,
        path: '$_liveDir/authorized.json',
        content: jsonEncode(ids),
        message: 'live: 更新开播授权名单 (${ids.length} 人)',
        branch: _branch,
      );
      return true;
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveBroadcast.setAuthorized', stack: st);
      return false;
    }
  }

  /// 当前用户是否有开播权限（教师/管理员恒有；学生需在授权名单内）。
  Future<bool> canBroadcast() async {
    if (_auth.isTeacher || _auth.isAdmin) return true;
    final uid = _auth.currentUser?.userId;
    if (uid == null) return false;
    final authorized = await getAuthorizedIds();
    return authorized.contains(uid);
  }

  // ════════════════════════════════════════════════════════════════════
  // 开播端：上传循环
  // ════════════════════════════════════════════════════════════════════

  /// 开始开播：先校验权限，再启动快照上传循环。返回是否成功开始。
  Future<bool> startBroadcasting() async {
    if (broadcastingNotifier.value) return true;
    if (!await canBroadcast()) return false;
    broadcastingNotifier.value = true;
    _broadcastTimer?.cancel();
    await _pushSnapshot(); // 立即推一帧，缩短观看端首帧等待
    _broadcastTimer =
        Timer.periodic(_broadcastInterval, (_) => _pushSnapshot());
    return true;
  }

  /// 停止开播：停循环 + 写一条 isLive=false 的 status，让观看端尽快移除。
  Future<void> stopBroadcasting() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    if (!broadcastingNotifier.value) return;
    broadcastingNotifier.value = false;
    await _writeStatus(isLive: false, snapshotPath: '');
  }

  Future<void> _pushSnapshot() async {
    if (_uploading) return; // 上一帧还没传完就跳过，避免堆积
    _uploading = true;
    try {
      final uid = _auth.currentUser?.userId;
      if (uid == null) return;
      final localPath = await LiveStreamService().takeSnapshot();
      final snapshotPath = '$_liveDir/$uid/snapshot.jpg';
      if (localPath != null) {
        final bytes = await File(localPath).readAsBytes();
        await _gitee.createOrUpdateBinaryFile(
          owner: _owner,
          repo: _repo,
          path: snapshotPath,
          bytes: bytes,
          message: 'live: $uid 快照',
          branch: _branch,
        );
        // 本地临时快照删掉，不堆积文档目录
        try {
          await File(localPath).delete();
        } catch (e) {
          swallow(e, tag: 'LiveBroadcast.delTmp');
        }
      }
      await _writeStatus(isLive: true, snapshotPath: snapshotPath);
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveBroadcast.pushSnapshot', stack: st);
    } finally {
      _uploading = false;
    }
  }

  Future<void> _writeStatus(
      {required bool isLive, required String snapshotPath}) async {
    final uid = _auth.currentUser?.userId;
    if (uid == null) return;
    final status = {
      'isLive': isLive,
      'name': _auth.currentUser?.realName ?? uid,
      'role': _auth.currentUser?.role ?? 'student',
      'updatedAt': DateTime.now().toIso8601String(),
      'snapshotPath': snapshotPath,
    };
    try {
      await _gitee.createOrUpdateFile(
        owner: _owner,
        repo: _repo,
        path: '$_liveDir/$uid/status.json',
        content: jsonEncode(status),
        message: 'live: $uid 状态 ${isLive ? "开播" : "下播"}',
        branch: _branch,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveBroadcast.writeStatus', stack: st);
    }
  }
}
