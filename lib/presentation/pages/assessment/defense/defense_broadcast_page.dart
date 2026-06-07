import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../../core/design/noir_tokens.dart';
import '../../../../core/error_handler.dart';
import '../../../../data/local/class_dao.dart';
import '../../../../data/local/database_helper.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/defense_streaming/defense_streaming_server.dart';
import '../../../../services/defense_streaming/phone_screen_capturer.dart';
import '../../../../services/defense_streaming/win_screen_capturer.dart';
import '../../../../services/gitee_service.dart';
import '../../../../services/live_stream_service.dart';
import '../../../../services/sync_service.dart';
import '../../../widgets/live_stream_panel.dart';
import 'defense_controls_panel.dart';
import 'defense_viewer_widget.dart';

class DefenseBroadcastPage extends StatefulWidget {
  final String initialRole;
  final String? serverIp;
  static GlobalKey? screenCaptureKey;
  final int serverPort;
  const DefenseBroadcastPage({super.key, this.initialRole = 'viewer', this.serverIp, this.serverPort = 8766});

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
  bool _isFullscreen = false;

  final _ipCtrl = TextEditingController();
  String? _viewerUrl;
  String? _remoteServerUrl;

  Timer? _winTimer, _camTimer, _statusTimer, _heartbeatTimer;
  bool _isScanning = false;

  bool get _isConnectedToServer => _remoteServerUrl != null && _remoteServerUrl!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _ipCtrl.text = widget.serverIp ?? '192.168.';
    if (widget.serverPort > 0) _serverPort = widget.serverPort;

    // 初始化屏幕捕获 key（用于手机投屏）
    DefenseBroadcastPage.screenCaptureKey ??= GlobalKey();

    // 学生进入答辩页面时拉取最新通知
    if (_role == 'defender' || _role == 'phone') {
      _pullNotifications();
    }

    if (_role == 'presenter') {
      _initPresenter();
    } else if (_role == 'defender') {
      if (widget.serverIp != null && widget.serverIp!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _initDefender());
      }
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _initPresenter() async {
    debugPrint('Defense: _initPresenter called');
    final wasRunning = _server.isRunning;
    _server.onServerReady = (ip, port) {
      debugPrint('Defense: onServerReady callback fired with ip=$ip, port=$port');
      if (mounted) setState(() { _serverReady = true; _serverIp = ip; _serverPort = port; });
    };
    debugPrint('Defense: calling _server.start()');
    await _server.start();
    debugPrint('Defense: _server.start() completed, isRunning=${_server.isRunning}');
    // 服务端已在运行（教师退出后重进）：直接恢复就绪状态
    if (wasRunning && _server.isRunning && !_serverReady) {
      if (mounted) setState(() {
        _serverReady = true;
        _serverIp = _server.host ?? '';
        _serverPort = _server.port;
      });
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
      return;
    }
    if (!_server.isRunning) {
      throw StateError('服务器启动失败：端口绑定异常，请重试');
    }
    // 教师主播只接收转发学生流，不推自己的桌面
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

  /// 返回: 0=成功, 1=网络不可达, 2=未授权, -1=其他错误
  Future<int> _tryConnectDefender(String ip) async {
    try {
      final uid = _auth.getCurrentUserId();
      final resp = await http.get(
        Uri.parse('http://$ip:$_serverPort/api/authorized?studentId=$uid'),
      ).timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return -1;
      final result = jsonDecode(resp.body) as Map<String, dynamic>;
      if (result['authorized'] != true) return 2;
      final remotePort = (result['port'] as int?) ?? _serverPort;
      final newUrl = 'http://$ip:$remotePort';
      if (mounted) setState(() { _remoteServerUrl = newUrl; _serverPort = remotePort; });
      _startDefenderStreaming();
      _startHeartbeat();
      return 0;
    } on SocketException { return 1; }
    on TimeoutException { return 1; }
    catch (_) { return -1; }
  }

  Future<void> _initDefender() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    try {
      final ip = _ipCtrl.text.trim().replaceFirst(RegExp(r'^https?://'), '');
      if (ip.isEmpty || ip == '192.168.') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入教师服务器的完整 IP 地址')));
        }
        setState(() => _isScanning = false);
        return;
      }

      final result = await _tryConnectDefender(ip);
      if (result == 0) { setState(() => _isScanning = false); return; }
      if (result == 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未授权：请在教师端点击"通知学生答辩"并选择你的账号'),
                duration: Duration(seconds: 5)));
        }
        setState(() => _isScanning = false);
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法连接教师服务器：请确认教师已点击"开始"且在同一局域网'),
              duration: Duration(seconds: 5)));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Defender.init', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动答辩失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// 拉取最新通知（学生进入答辩页面时）
  Future<void> _pullNotifications() async {
    // 通知同步功能后续接入
  }

  void _startDefenderStreaming() {
    // 仅自动启动摄像头（无需权限弹窗，安全）；桌面/手机投屏由学生手动开关
    _startCamToRemote();
  }

  void _toggleDefenderPhoneShare() {
    if (_phoneCap.isActive) { _phoneCap.stop(); setState(() {}); return; }
    if (_remoteServerUrl == null || DefenseBroadcastPage.screenCaptureKey == null) return;
    _phoneCap.start(_remoteServerUrl!, DefenseBroadcastPage.screenCaptureKey!);
    setState(() {});
  }

  void _toggleDefenderWin() {
    if (_winOn) { _stopWin(); return; }
    _winCap.initialize();
    _winOn = true;
    _winTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_winOn || _remoteServerUrl == null) return;
      try {
        final j = await _winCap.capture();
        if (j != null) {
          await http.post(Uri.parse('$_remoteServerUrl/frame/win'),
              body: j, headers: {'Content-Type': 'image/jpeg'}).timeout(const Duration(seconds: 2));
        }
      } catch (e, st) { swallowDebug(e, tag: 'Defender.win', stack: st); }
    });
    setState(() {});
  }

  void _toggleDefenderCam() {
    if (_cameraOn) { _stopCam(); return; }
    _cameraOn = true;
    _live.initializeCamera();
    _camTimer = Timer.periodic(const Duration(milliseconds: 330), (_) async {
      if (!_cameraOn || _remoteServerUrl == null) return;
      try {
        final b = await _live.takeSnapshotBytes();
        if (b != null) {
          await http.post(Uri.parse('$_remoteServerUrl/frame/camera'),
              body: b, headers: {'Content-Type': 'image/jpeg'}).timeout(const Duration(seconds: 2));
        }
      } catch (e, st) { swallowDebug(e, tag: 'Defender.cam', stack: st); }
    });
    setState(() {});
  }

  void _toggleDefenderSwitchCam() {
    _live.switchCamera();
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
    try {
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
    } catch (e, st) {
      swallowDebug(e, tag: 'Defender.cam.init', stack: st);
      _cameraOn = false;
    }
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
    if (_winOn) return;
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
    debugPrint('Defense: _toggleBroadcast called, _serverReady=$_serverReady');
    if (_serverReady) {
      debugPrint('Defense: stopping server');
      _server.stop();
      _stopWin();
      _stopCam();
      setState(() { _serverReady = false; });
    } else {
      debugPrint('Defense: starting presenter');
      _initPresenter();
    }
  }

  void _connectViewer() {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() => _viewerUrl = 'http://$ip:$_serverPort/stream/feed');
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
    try {
      _phoneCap.start('http://$ip:$_serverPort', DefenseBroadcastPage.screenCaptureKey!);
      setState(() {});

      // 延迟检查是否启动成功，并提示用户权限情况
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _phoneCap.isActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('投屏已启动\n提示：如拒绝屏幕录制权限，将只能捕获本应用内容'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'Defense.phoneShare', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('投屏启动失败: $e')),
        );
      }
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTeacherOrAdmin = _auth.isTeacher || _auth.isAdmin;
    final normalView = Scaffold(
      appBar: AppBar(
        title: Text(_role == 'defender' ? '开始答辩' : '答辩直播'),
        actions: isTeacherOrAdmin ? [
          _chip('presenter', '主播'),
          _chip('viewer', '观看'),
          _chip('phone', '手机投屏'),
          if (_role == 'defender') _chip('defender', '答辩'),
        ] : null),
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

    if (!_isFullscreen) return normalView;

    return GestureDetector(
      onTap: _toggleFullscreen,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _role == 'presenter'
            ? _buildFullscreenPreview()
            : _buildFullscreenDefender(),
      ),
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
    if (_serverReady) ...[
      const SizedBox(height: 12),
      _buildNotifyButton(),
    ],
    const SizedBox(height: 12),
    Expanded(child: _buildPreview()),
  ]);

  Widget _buildFullscreenPreview() {
    final winUrl = 'http://$_serverIp:$_serverPort/raw/win';
    final phoneUrl = 'http://$_serverIp:$_serverPort/raw/phone';
    final cameraUrl = 'http://$_serverIp:$_serverPort/raw/camera';
    return _buildPreviewLayout(winUrl, phoneUrl, cameraUrl);
  }

  Widget _buildFullscreenDefender() {
    return _buildDefenderPreview();
  }

  Widget _buildDefender() {
    if (!_isConnectedToServer) {
      return _buildDefenderConnect();
    }
    // 已连接：简洁直播风格 UI
    final isScreenSharing = _winOn || _phoneCap.isActive;
    return Column(children: [
      // 状态栏
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [NoirTokens.accent.withValues(alpha: 0.8), NoirTokens.accent]),
          borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red,
                boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.6), blurRadius: 6)])),
          const SizedBox(width: 8),
          const Text('答辩直播中', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(isScreenSharing ? '投屏中' : '已连接',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
        ])),
      const SizedBox(height: 10),
      // 主画面：摄像头（占满可用空间）
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(color: NoirTokens.inkDeep,
            child: _cameraOn
                ? LiveStreamPanel(
                    onClose: _toggleDefenderCam,
                    onMinimize: () {},
                    onFullscreen: () {},
                    onLock: () {})
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.videocam, size: 48,
                          color: NoirTokens.paper.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text('点击下方按钮开启摄像头',
                          style: TextStyle(
                              color: NoirTokens.paper.withValues(alpha: 0.4), fontSize: 14)),
                    ])),
          ),
        ),
      ),
      const SizedBox(height: 10),
      // 底部控制栏
      Row(children: [
        // 投屏开关
        Expanded(
          child: _defenderCtrlBtn(
            icon: Platform.isWindows ? Icons.desktop_windows : Icons.phone_android,
            label: _screenShareLabel,
            active: isScreenSharing,
            onTap: _toggleDefenderScreenShare,
          ),
        ),
        const SizedBox(width: 8),
        // 摄像头开关
        Expanded(
          child: _defenderCtrlBtn(
            icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
            label: _cameraOn ? '摄像头开' : '摄像头关',
            active: _cameraOn,
            onTap: _toggleDefenderCam,
          ),
        ),
        if (_cameraOn) ...[
          const SizedBox(width: 8),
          // 翻转镜头
          _defenderSmallBtn(Icons.switch_camera, _toggleDefenderSwitchCam),
        ],
      ]),
      const SizedBox(height: 10),
      // 结束按钮
      SizedBox(width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.stop),
          label: const Text('结束答辩'),
          style: FilledButton.styleFrom(
              backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
        )),
    ]);
  }

  Widget _buildDefenderConnect() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
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
                  labelText: '教师服务器 IP',
                  hintText: '192.168.x.x',
                  prefixIcon: const Icon(Icons.cast, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true),
                style: const TextStyle(fontSize: 14),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))])),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _initDefender,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('开始答辩'),
              style: FilledButton.styleFrom(backgroundColor: NoirTokens.accent)),
          ]),
          const SizedBox(height: 8),
          Text('请输入教师机的 IP 地址后点击"开始答辩"',
            style: TextStyle(fontSize: 11, color: NoirTokens.paper.withValues(alpha: 0.4))),
        ])),
    ]);
  }

  String get _screenShareLabel {
    if (Platform.isWindows) return _winOn ? '桌面投屏中' : '桌面投屏';
    return _phoneCap.isActive ? '手机投屏中' : '手机投屏';
  }

  void _toggleDefenderScreenShare() {
    if (Platform.isWindows) {
      _toggleDefenderWin();
    } else {
      _toggleDefenderPhoneShare();
    }
  }

  Widget _defenderCtrlBtn({required IconData icon, required String label, required bool active, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.green.withValues(alpha: 0.15) : NoirTokens.ink.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.green.withValues(alpha: 0.4) : NoirTokens.paper.withValues(alpha: 0.15))),
        child: Column(children: [
          Icon(icon, color: active ? Colors.green : Colors.white.withValues(alpha: 0.6), size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.green : Colors.white.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }

  Widget _defenderSmallBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NoirTokens.ink.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.15))),
        child: Icon(icon, color: Colors.white.withValues(alpha: 0.6), size: 20),
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, IconData icon, bool available, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: !available ? Colors.grey.withValues(alpha: 0.3)
              : active ? Colors.green.withValues(alpha: 0.3)
                       : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: !available ? Colors.grey
                : active ? Colors.green : Colors.white.withValues(alpha: 0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(!available ? Icons.not_interested : active ? Icons.check_circle : icon,
              size: 14, color: !available ? Colors.grey : active ? Colors.green : Colors.white),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11,
              color: !available ? Colors.grey : active ? Colors.green : Colors.white)),
        ]),
      ),
    );
  }

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
        child: _isConnectedToServer
            ? _buildLocalPreview()
            : _empty('连接中...')),
    );
  }

  /// 本地预览：显示摄像头 PIP + 屏幕录制状态（避免看远程流造成递归死循环）
  Widget _buildLocalPreview() {
    final isSharing = _winOn || _phoneCap.isActive;
    return Stack(fit: StackFit.expand, children: [
      // 主区域：录制状态
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isSharing ? Icons.screen_share : Icons.live_tv,
            size: 64,
            color: isSharing
                ? Colors.green.withValues(alpha: 0.6)
                : NoirTokens.paper.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            isSharing ? '屏幕录制中...\n请演示你的应用' : '已连接 · 点击下方按钮开始投屏',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSharing
                  ? Colors.green.withValues(alpha: 0.8)
                  : NoirTokens.paper.withValues(alpha: 0.4),
              fontSize: 14)),
          if (isSharing) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 10, color: Colors.red),
              const SizedBox(width: 6),
              Text('REC', style: TextStyle(
                  color: Colors.red.withValues(alpha: 0.9),
                  fontSize: 12, fontWeight: FontWeight.bold,
                  letterSpacing: 2)),
            ]),
          ],
        ])),
      // PIP 摄像头（右下角）
      if (_cameraOn)
        Positioned(right: 8, bottom: 8,
          width: 160, height: 120,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NoirTokens.accent.withValues(alpha: 0.5), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LiveStreamPanel(
                onClose: _toggleDefenderCam,
                onMinimize: () {},
                onFullscreen: () {},
                onLock: () {},
                compact: true,
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _buildPreview() {
    // 调试：显示当前状态
    if (!_server.isRunning || _serverIp.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: NoirTokens.inkDeep,
          child: _empty(_server.isRunning
              ? '正在获取服务器地址...\nIP: $_serverIp, Port: $_serverPort'
              : '服务器未启动\n点击"开始"启动服务器'),
        ),
      );
    }

    final winUrl = 'http://$_serverIp:$_serverPort/raw/win';
    final phoneUrl = 'http://$_serverIp:$_serverPort/raw/phone';
    final cameraUrl = 'http://$_serverIp:$_serverPort/raw/camera';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: NoirTokens.inkDeep,
        child: _buildPreviewLayout(winUrl, phoneUrl, cameraUrl),
      ),
    );
  }

  Widget _buildPreviewLayout(String winUrl, String phoneUrl, String cameraUrl) {
    switch (_layoutMode) {
      case 'dual':
        // 并排模式：优先显示 win/phone（取决于实际推流） + camera
        // 左侧：尝试 phone，如果没有则显示 win
        // 右侧：camera
        return Row(children: [
          Expanded(
            child: DefenseViewerWidget(onFullscreenToggle: _toggleFullscreen, isFullscreen: _isFullscreen,
              url: phoneUrl,
              label: '学生手机/桌面',
            )),
          Container(width: 2, color: NoirTokens.paper.withValues(alpha: 0.1)),
          Expanded(
            child: DefenseViewerWidget(onFullscreenToggle: _toggleFullscreen, isFullscreen: _isFullscreen,
              url: cameraUrl,
              label: '学生摄像头',
            )),
        ]);

      case 'phoneOnly':
        return DefenseViewerWidget(onFullscreenToggle: _toggleFullscreen, isFullscreen: _isFullscreen,
          url: phoneUrl,
          label: '学生手机',
        );

      case 'winOnly':
        return DefenseViewerWidget(onFullscreenToggle: _toggleFullscreen, isFullscreen: _isFullscreen,
          url: winUrl,
          label: '学生桌面',
        );

      case 'cameraOnly':
        return DefenseViewerWidget(onFullscreenToggle: _toggleFullscreen, isFullscreen: _isFullscreen,
          url: cameraUrl,
          label: '学生摄像头',
        );

      default:
        return _empty('未知布局模式');
    }
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
          child: DefenseViewerWidget(onFullscreenToggle: _toggleFullscreen, isFullscreen: _isFullscreen,
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

  // ══════════════════════════════════════════════════════════════════════════════
  // 通知功能
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildNotifyButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _notifyStudents,
        icon: const Icon(Icons.notifications_active, size: 18),
        label: const Text('通知学生答辩'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.orange,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Future<void> _notifyStudents() async {
    final students = await _selectStudents();
    if (students.isEmpty) return;

    final serverUrl = 'http://$_serverIp:$_serverPort';

    // 注册授权学生到服务器内存（支持 LAN 直连验证）
    _server.authorizeStudents(students.keys.toSet());

    // 将教师服务端信息写入 Gitee 供学生发现
    try {
      final gitee = GiteeService();
      final payload = jsonEncode({
        'teacherIp': _serverIp,
        'serverPort': _serverPort,
        'authorizedStudents': students.keys.toList(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      await gitee.createOrUpdateFile(
        owner: SyncService.repoOwner,
        repo: SyncService.repoName,
        path: 'defense/teacher_server.json',
        content: payload,
        message: 'defense: 教师开播通知 (${students.length} 名学生)',
        branch: SyncService.repoBranch,
      );
      debugPrint('Defense: teacher server info written to Gitee');
    } catch (e, st) {
      swallowDebug(e, tag: 'Defense.giteeNotify', stack: st);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已授权 ${students.length} 名学生\n服务器: $serverUrl'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<Map<String, String>> _selectStudents() async {
    try {
      final teacherId = _auth.getCurrentUserId();
      if (teacherId == null) return {};

      final classDao = ClassDao();
      final classes = await classDao.getTeacherClasses(teacherId);

      final allStudents = <String, String>{}; // userId -> realName
      for (final cls in classes) {
        final classId = cls['id'] as int;
        final members = await classDao.getClassMembers(classId);
        for (final m in members) {
          final userId = m['user_id'] as String?;
          final realName = m['real_name'] as String?;
          if (userId != null && realName != null) {
            allStudents[userId] = realName;
          }
        }
      }

      if (allStudents.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有找到学生')),
          );
        }
        return {};
      }

      // 查询哪些学生已收到过答辩直播通知
      final notifiedStudents = await _getNotifiedStudents(allStudents.keys.toSet());

      if (!mounted) return {};

      final selected = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => _StudentSelectionDialog(
          students: allStudents,
          notifiedStudents: notifiedStudents,
        ),
      );
      return selected ?? {};
    } catch (e, st) {
      swallowDebug(e, tag: 'Defense.selectStudents', stack: st);
      return {};
    }
  }

  /// 查询已发送过答辩通知的学生 ID 集合
  Future<Set<String>> _getNotifiedStudents(Set<String> studentIds) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'notification_recipients',
        columns: ['recipient_id'],
        where: '''
          notification_id IN (
            SELECT id FROM notifications
            WHERE type = ? AND related_entity_type = ?
          )
          AND recipient_id IN (${studentIds.map((_) => '?').join(',')})
        ''',
        whereArgs: ['defense', 'defense_live', ...studentIds],
        distinct: true,
      );
      return result.map((r) => r['recipient_id'] as String).toSet();
    } catch (e, st) {
      swallowDebug(e, tag: 'Defense.getNotifiedStudents', stack: st);
      return {};
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 学生选择对话框
// ══════════════════════════════════════════════════════════════════════════════

class _StudentSelectionDialog extends StatefulWidget {
  final Map<String, String> students; // userId -> realName
  final Set<String> notifiedStudents; // 已发送过通知的学生 ID 集合
  const _StudentSelectionDialog({
    required this.students,
    required this.notifiedStudents,
  });

  @override
  State<_StudentSelectionDialog> createState() => _StudentSelectionDialogState();
}

class _StudentSelectionDialogState extends State<_StudentSelectionDialog> {
  final Map<String, String> _selected = {};
  bool _selectAll = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择答辩学生'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: const Text('全选', style: TextStyle(fontWeight: FontWeight.bold)),
              value: _selectAll,
              onChanged: (v) {
                setState(() {
                  _selectAll = v ?? false;
                  if (_selectAll) {
                    _selected.addAll(widget.students);
                  } else {
                    _selected.clear();
                  }
                });
              },
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.students.entries.map((e) {
                  final isNotified = widget.notifiedStudents.contains(e.key);
                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Text(e.value),
                        if (isNotified) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 12, color: Colors.green),
                                SizedBox(width: 2),
                                Text(
                                  '已通知',
                                  style: TextStyle(fontSize: 10, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(e.key, style: const TextStyle(fontSize: 11)),
                    value: _selected.containsKey(e.key),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected[e.key] = e.value;
                        } else {
                          _selected.remove(e.key);
                        }
                        _selectAll = _selected.length == widget.students.length;
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text('确定 (${_selected.length})'),
        ),
      ],
    );
  }
}
