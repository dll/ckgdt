import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../../core/design/noir_tokens.dart';
import '../../../../core/error_handler.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/defense_streaming/defense_streaming_server.dart';
import '../../../../services/defense_streaming/phone_screen_capturer.dart';
import '../../../../services/defense_streaming/win_screen_capturer.dart';
import '../../../../services/live_stream_service.dart';
import '../../../widgets/live_stream_panel.dart';
import 'defense_controls_panel.dart';
import 'defense_viewer_widget.dart';

class DefenseBroadcastPage extends StatefulWidget {
  final String initialRole;
  final String? serverIp;
  static GlobalKey? screenCaptureKey;
  const DefenseBroadcastPage({super.key, this.initialRole = 'viewer', this.serverIp});

  @override
  State<DefenseBroadcastPage> createState() => _DefenseBroadcastPageState();
}

class _DefenseBroadcastPageState extends State<DefenseBroadcastPage> {
  String _role = 'viewer';
  final _server = DefenseStreamingServer.instance;
  final _winCap = WinScreenCapturer.instance;
  final _phoneCap = PhoneScreenCapturer.instance;
  final _live = LiveStreamService();
  final _auth = AuthService();

  bool _serverReady = false;
  String _serverIp = '';
  int _serverPort = 8766;
  int _viewerCount = 0;
  bool _winOn = false;
  bool _cameraOn = false;
  String _layoutMode = 'dual';

  final _ipCtrl = TextEditingController();
  String? _viewerUrl;
  String? _remoteServerUrl;

  Timer? _winTimer, _camTimer, _statusTimer, _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _ipCtrl.text = widget.serverIp ?? '192.168.';
    if (_role == 'presenter') {
      _initPresenter();
    } else if (_role == 'defender') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initDefender());
    }
  }

  @override
  void dispose() {
    _stopWin();
    _stopCam();
    _stopDefender();
    _statusTimer?.cancel();
    _heartbeatTimer?.cancel();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _initPresenter() async {
    _server.onServerReady = (ip, port) {
      if (mounted) setState(() { _serverReady = true; _serverIp = ip; _serverPort = port; });
    };
    await _server.start();
    if (Platform.isWindows) _winCap.initialize();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || !_server.isRunning) return;
      try {
        final resp = await http.get(Uri.parse('http://$_serverIp:$_serverPort/status'))
            .timeout(const Duration(seconds: 2));
        if (resp.statusCode == 200 && mounted) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final newCount = (data['viewers'] as int?) ?? 0;
          if (_viewerCount != newCount) {
            setState(() { _viewerCount = newCount; });
          }
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'Defense.status', stack: st);
      }
    });
  }

  Future<void> _initDefender() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('教师服务器 IP 不能为空')));
      }
      return;
    }
    _remoteServerUrl = 'http://$ip:8766';
    _startDefenderStreaming();
    _startHeartbeat();
  }

  void _startDefenderStreaming() {
    if (Platform.isWindows) {
      _winCap.initialize();
      _startWinToRemote();
    } else if (Platform.isAndroid) {
      if (DefenseBroadcastPage.screenCaptureKey != null) {
        _phoneCap.start(_remoteServerUrl!, DefenseBroadcastPage.screenCaptureKey!);
      }
    }
    _startCamToRemote();
  }

  void _startWinToRemote() {
    _winOn = true;
    _winTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_winOn || _remoteServerUrl == null) return;
      try {
        final j = await _winCap.capture();
        if (j != null) {
          await http.post(
            Uri.parse('$_remoteServerUrl/frame/win'),
            body: j,
            headers: {'Content-Type': 'image/jpeg'},
          ).timeout(const Duration(seconds: 2));
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'Defender.win', stack: st);
      }
    });
    if (mounted) setState(() {});
  }

  void _startCamToRemote() {
    _cameraOn = true;
    _live.initializeCamera();
    _camTimer = Timer.periodic(const Duration(milliseconds: 330), (_) async {
      if (!_cameraOn || _remoteServerUrl == null) return;
      try {
        final b = await _live.takeSnapshotBytes();
        if (b != null) {
          await http.post(
            Uri.parse('$_remoteServerUrl/frame/camera'),
            body: b,
            headers: {'Content-Type': 'image/jpeg'},
          ).timeout(const Duration(seconds: 2));
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'Defender.cam', stack: st);
      }
    });
    if (mounted) setState(() {});
  }

  void _startHeartbeat() {
    final userId = _auth.getCurrentUserId() ?? 'unknown';
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_remoteServerUrl == null) return;
      try {
        await http.post(
          Uri.parse('$_remoteServerUrl/heartbeat'),
          body: jsonEncode({
            'deviceName': '答辩学生 $userId',
            'source': 'defender',
          }),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 2));
      } catch (e, st) {
        swallowDebug(e, tag: 'Defender.heartbeat', stack: st);
      }
    });
  }

  void _stopDefender() {
    _stopWin();
    _stopCam();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_phoneCap.isActive) _phoneCap.stop();
  }

  void _toggleWin() {
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('仅 Windows 支持桌面抓取')));
      return;
    }
    _winOn ? _stopWin() : _startWin();
  }

  void _startWin() {
    _winOn = true;
    _winTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_winOn) return;
      try {
        final j = await _winCap.capture();
        if (j != null) _server.pushWinFrame(j);
      } catch (e, st) {
        swallowDebug(e, tag: 'Defense.win', stack: st);
      }
    });
    setState(() {});
  }

  void _stopWin() {
    _winOn = false;
    _winTimer?.cancel();
    _winTimer = null;
    setState(() {});
  }

  void _toggleCam() {
    _cameraOn ? _stopCam() : _startCam();
  }

  void _startCam() {
    _cameraOn = true;
    _live.initializeCamera();
    _camTimer = Timer.periodic(const Duration(milliseconds: 330), (_) async {
      if (!_cameraOn) return;
      try {
        final p = await _live.takeSnapshot();
        if (p != null) {
          final f = File(p);
          final b = await f.readAsBytes();
          try { await f.delete(); } catch (e) { swallow(e, tag: 'Defense.cam.del'); }
          _server.pushCameraFrame(b);
        }
      } catch (e) {
        swallow(e, tag: 'Defense.cam');
      }
    });
    setState(() {});
  }

  void _stopCam() {
    _cameraOn = false;
    _camTimer?.cancel();
    _camTimer = null;
    _live.shutdownCamera();
    setState(() {});
  }

  void _onLayoutChanged(String m) {
    setState(() => _layoutMode = m);
  }

  void _toggleBroadcast() {
    if (_serverReady) {
      _server.stop();
      _stopWin();
      _stopCam();
      setState(() { _serverReady = false; });
    } else {
      _initPresenter();
    }
  }

  void _connectViewer() {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() => _viewerUrl = 'http://$ip:8766/stream/feed');
  }

  void _startPhoneShare() {
    if (_phoneCap.isActive) {
      _phoneCap.stop();
      setState(() {});
      return;
    }
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入教师机 IP')));
      return;
    }
    if (DefenseBroadcastPage.screenCaptureKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('屏幕捕获未就绪')));
      return;
    }
    _phoneCap.start('http://$ip:8766', DefenseBroadcastPage.screenCaptureKey!);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已连接 $ip，手机屏幕正在共享')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_role == 'defender' ? '开始答辩' : '答辩直播'),
        actions: [
          if (_role != 'defender') ...[
            _chip('presenter', '主播'),
            _chip('viewer', '观看'),
            _chip('phone', '手机投屏'),
          ],
        ]),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _role == 'presenter'
              ? _buildPresenter()
              : _role == 'defender'
                  ? _buildDefender()
                  : _role == 'phone'
                      ? _buildPhone()
                      : _buildViewer())),
    );
  }

  Widget _chip(String role, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _role == role,
        selectedColor: NoirTokens.accent.withValues(alpha: 0.3),
        onSelected: (_) {
          setState(() => _role = role);
          if (role == 'presenter') _initPresenter();
        },
        visualDensity: VisualDensity.compact));
  }

  Widget _buildPresenter() => Column(children: [
    DefenseControlsPanel(
      isBroadcasting: _serverReady,
      isWinCaptureOn: _winOn,
      isPhoneCaptureOn: false,
      isCameraOn: _cameraOn,
      layoutMode: _layoutMode,
      serverIp: _serverIp,
      serverPort: _serverPort,
      viewerCount: _viewerCount,
      onToggleBroadcast: _toggleBroadcast,
      onToggleWinCapture: _toggleWin,
      onToggleCamera: _toggleCam,
      onLayoutChanged: _onLayoutChanged),
    const SizedBox(height: 12),
    Expanded(child: _buildPreview()),
  ]);

  Widget _buildDefender() => Column(children: [
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [NoirTokens.accent.withValues(alpha: 0.8), NoirTokens.accent]),
        borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.live_tv, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('答辩中',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8)),
              child: Text('教师机: $_remoteServerUrl',
                  style: const TextStyle(color: Colors.white, fontSize: 11))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _statusBadge('桌面', _winOn, Platform.isWindows),
            const SizedBox(width: 8),
            _statusBadge('摄像头', _cameraOn, true),
            const SizedBox(width: 8),
            _statusBadge('手机', _phoneCap.isActive, Platform.isAndroid),
          ]),
        ])),
    const SizedBox(height: 12),
    Expanded(child: _buildDefenderPreview()),
    const SizedBox(height: 12),
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.stop),
        label: const Text('结束答辩'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red,
          padding: const EdgeInsets.symmetric(vertical: 14)),
      )),
  ]);

  Widget _statusBadge(String label, bool active, bool available) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: !available
            ? Colors.grey.withValues(alpha: 0.3)
            : active
                ? Colors.green.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: !available
              ? Colors.grey
              : active
                  ? Colors.green
                  : Colors.white.withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            !available
                ? Icons.not_interested
                : active
                    ? Icons.check_circle
                    : Icons.circle_outlined,
            size: 14,
            color: !available
                ? Colors.grey
                : active
                    ? Colors.green
                    : Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: !available
                    ? Colors.grey
                    : active
                        ? Colors.green
                        : Colors.white)),
        ]));
  }

  Widget _buildDefenderPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: NoirTokens.inkDeep,
        child: Row(children: [
          if (Platform.isWindows || Platform.isAndroid)
            Expanded(
              child: _remoteServerUrl != null
                  ? DefenseViewerWidget(
                      url: '$_remoteServerUrl/raw/${Platform.isWindows ? 'win' : 'phone'}',
                      label: Platform.isWindows ? 'Windows 桌面' : 'Android 屏幕')
                  : _empty('连接中...')),
          if (Platform.isWindows || Platform.isAndroid)
            Container(width: 2, color: NoirTokens.paper.withValues(alpha: 0.1)),
          Expanded(
            child: _remoteServerUrl != null
                ? DefenseViewerWidget(
                    url: '$_remoteServerUrl/raw/camera',
                    label: '摄像头')
                : _empty('连接中...')),
        ])));
  }

  Widget _buildPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: NoirTokens.inkDeep,
        child: _winOn || _cameraOn
          ? Row(children: [
              Expanded(
                child: _layoutMode != 'phoneOnly'
                  ? DefenseViewerWidget(
                      url: _server.isRunning
                          ? 'http://$_serverIp:$_serverPort/raw/win'
                          : null,
                      label: 'Win 桌面')
                  : _empty('手机画面')),
              if (_layoutMode == 'dual') ...[
                Container(width: 2, color: NoirTokens.paper.withValues(alpha: 0.1)),
                Expanded(
                  child: DefenseViewerWidget(
                    url: _server.isRunning
                        ? 'http://$_serverIp:$_serverPort/raw/camera'
                        : null,
                    label: '摄像头')),
              ],
            ])
          : _empty('开始桌面或摄像头抓取以预览'),
      ),
    );
  }

  Widget _empty(String t) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.live_tv,
            size: 48,
            color: NoirTokens.paper.withValues(alpha: 0.15)),
        const SizedBox(height: 8),
        Text(t,
            style: TextStyle(
              color: NoirTokens.paper.withValues(alpha: 0.3),
              fontSize: 14)),
      ]));

  Widget _buildViewer() => Column(children: [
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirTokens.ink.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NoirTokens.accent.withValues(alpha: 0.2))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ipCtrl,
            decoration: InputDecoration(
              labelText: '服务器 IP',
              hintText: '192.168.x.x',
              prefixIcon: const Icon(Icons.cast, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true),
            style: const TextStyle(fontSize: 14),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))])),
        const SizedBox(width: 8),
        FilledButton(onPressed: _connectViewer, child: const Text('连接')),
      ])),
    const SizedBox(height: 12),
    Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: NoirTokens.inkDeep,
          child: DefenseViewerWidget(
            url: _viewerUrl,
            label: '答辩直播')))),
  ]);

  Widget _buildPhone() => Column(children: [
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirTokens.ink.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NoirTokens.accent.withValues(alpha: 0.2))),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ipCtrl,
              decoration: InputDecoration(
                labelText: '教师机 IP',
                hintText: '192.168.x.x',
                prefixIcon: const Icon(Icons.cast, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true),
              style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _startPhoneShare,
            icon: Icon(_phoneCap.isActive ? Icons.stop : Icons.screen_share, size: 16),
            label: Text(_phoneCap.isActive ? '停止' : '投屏'),
            style: FilledButton.styleFrom(
              backgroundColor: _phoneCap.isActive ? Colors.red : NoirTokens.accent)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _dot(_phoneCap.isActive),
          const SizedBox(width: 4),
          Text(
            _phoneCap.isActive ? '已连接' : '未连接',
            style: TextStyle(
              color: _phoneCap.isActive ? Colors.green : Colors.grey,
              fontSize: 11)),
          const SizedBox(width: 16),
          Text(
            '手机屏幕将显示在教师机直播画面中',
            style: TextStyle(
              fontSize: 11,
              color: NoirTokens.paper.withValues(alpha: 0.4))),
        ]),
      ])),
    const SizedBox(height: 12),
    Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: NoirTokens.inkDeep,
          borderRadius: BorderRadius.circular(12)),
        child: _cameraOn
          ? LiveStreamPanel(
              onClose: _stopCam,
              onMinimize: () {},
              onFullscreen: () {},
              onLock: () {},
              compact: true)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_android,
                      size: 48,
                      color: NoirTokens.paper.withValues(alpha: 0.15)),
                  const SizedBox(height: 8),
                  Text(
                    '连接教师机后输入 IP 点击"投屏"',
                    style: TextStyle(
                      color: NoirTokens.paper.withValues(alpha: 0.3),
                      fontSize: 13)),
                ])))),
  ]);

  Widget _dot(bool on) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? Colors.green : Colors.grey));
}
