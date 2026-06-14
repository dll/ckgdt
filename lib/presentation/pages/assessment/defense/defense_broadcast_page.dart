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
import '../../../../services/defense_streaming/lan_discovery.dart';
import '../../../../services/defense_streaming/phone_screen_capturer.dart';
import '../../../../services/defense_streaming/win_screen_capturer.dart';
import '../../../../services/gitee_service.dart';
import '../../../../services/live_stream_service.dart';
import '../../../../services/sync_service.dart';
import '../../../widgets/live_stream_panel.dart';
import 'defense_controls_panel.dart';
import 'defense_project_info_panel.dart';
import 'defense_viewer_widget.dart';

class DefenseBroadcastPage extends StatefulWidget {
  final String initialRole;
  final String? serverIp;
  static GlobalKey? screenCaptureKey;
  final int serverPort;
  const DefenseBroadcastPage(
      {super.key,
      this.initialRole = 'auto',
      this.serverIp,
      this.serverPort = 8766});

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
  String? _activeDefenderId;
  String _screenFrameStatus = '屏幕: 等待投屏';
  String _cameraFrameStatus = '摄像头: 等待';
  bool _screenFrameLive = false;
  bool _cameraFrameLive = false;
  bool _winOn = false;
  bool _winCaptureBusy = false;
  bool _cameraOn = false;
  String _layoutMode = 'dual';
  bool _isFullscreen = false;

  final _ipCtrl = TextEditingController();
  String? _viewerServerUrl;
  String? _viewerSourceRole;
  String? _remoteServerUrl;
  String? _presentPhoneTargetUrl;
  bool _viewerHasWin = false;
  bool _viewerHasPhone = false;
  bool _serverHasWin = false;
  bool _serverHasPhone = false;

  Timer? _winTimer,
      _camTimer,
      _statusTimer,
      _heartbeatTimer,
      _viewerStatusTimer;
  bool _isScanning = false;

  // 局域网自动发现：defender 找 presenter，viewer 找 presenter/present。
  LanDiscoveryListener? _discovery;
  List<LanDiscoveryEntry> _discovered = [];
  bool _connecting = false; // defender 连接中（同步守卫，防多教师信标并发重连泄漏定时器）

  bool get _recording => _live.currentState.isRecording;

  bool get _isConnectedToServer =>
      _remoteServerUrl != null && _remoteServerUrl!.isNotEmpty;
  bool get _isTeacherOrAdmin => _auth.isTeacher || _auth.isAdmin;
  bool get _isHostRole => _role == 'presenter' || _role == 'present';

  @override
  void initState() {
    super.initState();
    _role = _normalizeInitialRole(widget.initialRole);
    _ipCtrl.text = widget.serverIp ?? '192.168.';
    if (widget.serverPort > 0) _serverPort = widget.serverPort;

    // 初始化屏幕捕获 key（用于手机投屏）
    DefenseBroadcastPage.screenCaptureKey ??= GlobalKey();

    if (_role == 'select') return;
    _startRole(_role);
  }

  String _normalizeInitialRole(String role) {
    if (role == 'auto' || role == 'select') return 'select';
    if (_isTeacherOrAdmin) {
      return {'presenter', 'viewer', 'present'}.contains(role)
          ? role
          : 'select';
    }
    return {'viewer', 'defender'}.contains(role) ? role : 'select';
  }

  void _startRole(String role) {
    if (role == 'presenter' || role == 'present') {
      if (role == 'present' && !Platform.isWindows) {
        unawaited(_initMobilePresent());
      } else {
        unawaited(_initPresenter());
      }
    } else if (role == 'defender') {
      if (widget.serverIp != null && widget.serverIp!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _initDefender());
      } else {
        // 没拿到教师 IP：启动 UDP 自动发现，发现教师后自动连接。
        _startDiscovery({'presenter'}, autoConnectDefender: true);
      }
    } else if (role == 'viewer') {
      // 观看端：自动发现主播/演示直播源。
      _startDiscovery({'presenter', 'present'});
    }
  }

  void _switchRole(String role) {
    final next = _normalizeInitialRole(role);
    if (next == _role) return;

    _discovery?.stop();
    _discovered = [];
    _viewerServerUrl = null;
    _viewerSourceRole = null;
    _viewerHasWin = false;
    _viewerHasPhone = false;
    _serverHasWin = false;
    _serverHasPhone = false;
    _presentPhoneTargetUrl = null;
    _statusTimer?.cancel();
    _statusTimer = null;
    _viewerStatusTimer?.cancel();
    _viewerStatusTimer = null;

    if (_role == 'defender') {
      _stopDefender();
      _remoteServerUrl = null;
    }
    if (_isHostRole && next != 'presenter' && next != 'present') {
      unawaited(_server.stop());
      _serverReady = false;
      _viewerCount = 0;
      _activeDefenderId = null;
    }
    if (next != 'present') {
      _stopWin();
      if (_phoneCap.isActive) {
        _phoneCap.stop();
      }
    }
    if (next != 'defender') {
      _stopCam();
    }

    setState(() {
      _role = next;
      _screenFrameStatus = '屏幕: 等待投屏';
      _cameraFrameStatus = '摄像头: 等待';
      _screenFrameLive = false;
      _cameraFrameLive = false;
    });
    if (next != 'select') {
      _startRole(next);
    }
  }

  @override
  void dispose() {
    _discovery?.stop();
    _stopWin();
    _stopCam();
    _stopDefender();
    _statusTimer?.cancel();
    _heartbeatTimer?.cancel();
    _viewerStatusTimer?.cancel();
    _ipCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _initPresenter() async {
    debugPrint('Defense: _initPresenter called');
    _server.onServerReady = (ip, port) {
      debugPrint(
          'Defense: onServerReady callback fired with ip=$ip, port=$port');
      if (mounted) {
        setState(() {
          _serverReady = true;
          _serverIp = ip;
          _serverPort = port;
        });
      }
    };
    debugPrint('Defense: calling _server.start()');
    await _server.start(role: _role);
    debugPrint(
        'Defense: _server.start() completed, isRunning=${_server.isRunning}');
    if (!_server.isRunning) {
      throw StateError('服务器启动失败：端口绑定异常，请重试');
    }
    if (mounted) {
      setState(() {
        _serverReady = true;
        _serverIp = _server.host ?? _serverIp;
        _serverPort = _server.port;
      });
    }
    _syncPresenterCaptureForRole();
    _startStatusPolling();
  }

  Future<void> _initMobilePresent() async {
    _startDiscovery({'present'});
    setState(() {
      _screenFrameStatus = '手机: 正在查找已有教师演示';
      _cameraFrameStatus = '摄像头: 未启用';
    });

    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted ||
        _role != 'present' ||
        _server.isRunning ||
        _presentPhoneTargetUrl != null) {
      return;
    }

    final existing = _firstDiscoveredRole('present');
    if (existing != null) {
      _joinPresentSource(existing);
      return;
    }

    await _initPresenter();
  }

  LanDiscoveryEntry? _firstDiscoveredRole(String role) {
    for (final entry in _discovered) {
      if (entry.role == role) return entry;
    }
    return null;
  }

  void _joinPresentSource(LanDiscoveryEntry entry) {
    _discovery?.stop();
    setState(() {
      _serverReady = true;
      _serverIp = entry.ip;
      _serverPort = entry.port;
      _viewerServerUrl = entry.serverUrl;
      _viewerSourceRole = 'present';
      _screenFrameStatus = '手机: 准备推送到教师演示';
      _cameraFrameStatus = '摄像头: 未启用';
    });
    _startViewerStatusPolling();
    _startPresentPhoneShare(entry.serverUrl);
  }

  void _syncPresenterCaptureForRole() {
    if (_role == 'present') {
      _server.clearFrames();
      if (Platform.isWindows) {
        if (!_winOn) _startWin();
      } else {
        _startPresentPhoneShare(_server.serverUrl);
      }
    } else if (_role == 'presenter') {
      _server.clearFrames();
      if (_winOn) {
        // 主播模式只接收学生流，避免教师桌面覆盖学生屏幕。
        _stopWin();
      }
      if (_phoneCap.isActive) {
        _phoneCap.stop();
      }
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    unawaited(_refreshStatus());
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _refreshStatus();
    });
  }

  Future<void> _refreshStatus() async {
    if (!mounted || !_server.isRunning || _serverIp.isEmpty) return;
    try {
      final resp = await http
          .get(Uri.parse('http://$_serverIp:$_serverPort/status'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _applyServerStatus(data);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Defense.status', stack: st);
    }
  }

  void _applyServerStatus(Map<String, dynamic> data) {
    final frames = (data['frames'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final newCount = (data['viewers'] as int?) ?? 0;
    final defId = data['activeDefenderId'] as String?;
    final screen = frames['screen'] == true;
    final camera = frames['camera'] == true;
    final screenAge = (frames['screenAge'] as num?)?.toInt() ?? -1;
    final cameraAge = (frames['cameraAge'] as num?)?.toInt() ?? -1;
    final winLive = _frameLive(frames, 'win', 'winAge');
    final phoneLive = _frameLive(frames, 'phone', 'phoneAge');
    final screenSource = frames['screenSource'] as String?;
    final screenLive = screen && screenAge >= 0 && screenAge < 5000;
    final cameraLive = camera && cameraAge >= 0 && cameraAge < 5000;
    final sourceLabel = screenSource == 'win'
        ? '桌面'
        : screenSource == 'phone'
            ? '手机'
            : '屏幕';
    final screenStatus = _role == 'present'
        ? _presentScreenStatus(winLive: winLive, phoneLive: phoneLive)
        : screen
            ? '$sourceLabel: ${screenLive ? '直播中' : '未更新'} ${_ageText(screenAge)}'
            : '屏幕: 等待投屏';
    final cameraStatus = camera
        ? '摄像头: ${cameraLive ? '直播中' : '未更新'} ${_ageText(cameraAge)}'
        : '摄像头: 等待';
    if (_viewerCount != newCount ||
        _activeDefenderId != defId ||
        _screenFrameStatus != screenStatus ||
        _cameraFrameStatus != cameraStatus ||
        _screenFrameLive != screenLive ||
        _cameraFrameLive != cameraLive ||
        _serverHasWin != winLive ||
        _serverHasPhone != phoneLive) {
      setState(() {
        _viewerCount = newCount;
        _activeDefenderId = defId;
        _screenFrameStatus = screenStatus;
        _cameraFrameStatus = cameraStatus;
        _screenFrameLive =
            _role == 'present' ? winLive || phoneLive : screenLive;
        _cameraFrameLive = cameraLive;
        _serverHasWin = winLive;
        _serverHasPhone = phoneLive;
      });
    }
  }

  bool _frameLive(Map<String, dynamic> frames, String key, String ageKey) {
    final hasFrame = frames[key] == true;
    final age = (frames[ageKey] as num?)?.toInt() ?? -1;
    return hasFrame && age >= 0 && age < 5000;
  }

  String _presentScreenStatus({
    required bool winLive,
    required bool phoneLive,
  }) {
    if (winLive && phoneLive) return '演示: Windows桌面 + 手机桌面';
    if (winLive) return '演示: Windows桌面直播中';
    if (phoneLive) return '演示: 手机桌面直播中';
    if (_role == 'present' && !Platform.isWindows && _phoneCap.isActive) {
      return '演示: 手机录屏已开启，等待首帧';
    }
    return '演示: 等待教师桌面';
  }

  String _ageText(int ms) {
    if (ms < 0) return '';
    if (ms < 1000) return '刚刚';
    return '${(ms / 1000).floor()}秒前';
  }

  /// 返回: 0=成功, 1=网络不可达, 2=未授权, -1=其他错误
  Future<int> _tryConnectDefender(String ip) async {
    if (_connecting || _isConnectedToServer) return -1;
    _connecting = true;
    try {
      final uid = _auth.getCurrentUserId();
      final resp = await http
          .get(
            Uri.parse('http://$ip:$_serverPort/api/authorized?studentId=$uid'),
          )
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return -1;
      final result = jsonDecode(resp.body) as Map<String, dynamic>;
      if (result['authorized'] != true) return 2;
      final remotePort = (result['port'] as int?) ?? _serverPort;
      final newUrl = 'http://$ip:$remotePort';
      if (mounted) {
        setState(() {
          _remoteServerUrl = newUrl;
          _serverPort = remotePort;
        });
      }
      _startHeartbeat();
      _startDefenderStreaming();
      return 0;
    } on SocketException {
      return 1;
    } on TimeoutException {
      return 1;
    } catch (e, st) {
      swallowDebug(e, tag: 'Defender.tryConnect', stack: st);
      return -1;
    } finally {
      _connecting = false;
    }
  }

  Future<void> _initDefender() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    try {
      final ip = _ipCtrl.text.trim().replaceFirst(RegExp(r'^https?://'), '');
      if (ip.isEmpty || ip == '192.168.') {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('请输入教师服务器的完整 IP 地址')));
        }
        setState(() => _isScanning = false);
        return;
      }

      final result = await _tryConnectDefender(ip);
      if (result == 0) {
        setState(() => _isScanning = false);
        return;
      }
      if (result == 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('未授权：请在教师端点击"通知学生答辩"并选择你的账号'),
              duration: Duration(seconds: 5)));
        }
        setState(() => _isScanning = false);
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('无法连接教师服务器：请确认教师已点击"开始"且在同一局域网'),
            duration: Duration(seconds: 5)));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Defender.init', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('启动答辩失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// 启动局域网 UDP 自动发现。[roles] 过滤角色；
  /// [autoConnectDefender] 为真时（学生答辩）发现首个教师即自动连接。
  void _startDiscovery(Set<String> roles, {bool autoConnectDefender = false}) {
    _discovery?.stop();
    final listener = LanDiscoveryListener(roleFilter: roles);
    listener.onUpdate = (entries) {
      if (!mounted) return;
      setState(() => _discovered = entries);
      if (autoConnectDefender &&
          !_isConnectedToServer &&
          !_isScanning &&
          entries.isNotEmpty) {
        final teacher = entries.first;
        _ipCtrl.text = teacher.ip;
        _serverPort = teacher.port;
        _tryConnectDefender(teacher.ip);
      }
      // 观看端：尚未连接任何流时，自动连上发现的第一个直播源。
      if (_role == 'viewer' && _viewerServerUrl == null && entries.isNotEmpty) {
        final src = entries.first;
        _ipCtrl.text = src.ip;
        _serverPort = src.port;
        setState(() {
          _viewerServerUrl = src.serverUrl;
          _viewerSourceRole = src.role;
        });
        _startViewerStatusPolling();
      }
    };
    _discovery = listener;
    listener.start();
  }

  void _startDefenderStreaming() {
    // 连上即自动开摄像头 + 桌面投屏（教师立刻能看到学生屏幕）。
    _startCamToRemote();
    // 桌面/手机投屏自动开启：Windows 直接抓屏（无弹窗），Android 触发录屏授权。
    if (Platform.isWindows) {
      if (!_winOn) _toggleDefenderWin();
    } else {
      if (!_phoneCap.isActive) _toggleDefenderPhoneShare();
    }
  }

  void _toggleDefenderPhoneShare() {
    if (_phoneCap.isActive) {
      _phoneCap.stop();
      // 录屏停止后恢复 Dart 端摄像头采集（CameraX 已释放前置摄像头）
      if (!_cameraOn) _startCamToRemote();
      setState(() {});
      return;
    }
    if (_remoteServerUrl == null ||
        DefenseBroadcastPage.screenCaptureKey == null) {
      return;
    }
    // 前置摄像头交给前台服务的 CameraX：先停 Dart 端摄像头独占，避免冲突。
    // 录屏期间人脸帧由原生 madkg/camera_capture_events 推送到 /frame/camera。
    _stopCam();
    _phoneCap.start(
      _remoteServerUrl!,
      DefenseBroadcastPage.screenCaptureKey!,
      allowAppFallback: false,
    );
    setState(() {});
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _phoneCap.isActive) return;
      if (!_cameraOn) _startCamToRemote();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未开启系统录屏，手机桌面不会推送给教师')),
      );
    });
  }

  void _togglePresentPhoneShare() {
    if (_phoneCap.isActive) {
      _phoneCap.stop();
      setState(() {});
      return;
    }
    final targetUrl = _presentPhoneTargetUrl ??
        (_server.isRunning ? _server.serverUrl : _viewerServerUrl);
    if (targetUrl == null || targetUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到教师演示服务器')),
      );
      return;
    }
    _startPresentPhoneShare(targetUrl);
  }

  void _startPresentPhoneShare(String targetUrl) {
    if (Platform.isWindows || _phoneCap.isActive) return;
    final key = DefenseBroadcastPage.screenCaptureKey;
    if (key == null) return;
    _presentPhoneTargetUrl = targetUrl.replaceAll(RegExp(r'/$'), '');
    _phoneCap.start(
      _presentPhoneTargetUrl!,
      key,
      allowAppFallback: false,
    );
    setState(() {
      _screenFrameStatus = '手机: 正在请求录屏授权';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _phoneCap.isActive) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未开启系统录屏，教师手机桌面不会推送给观看端')),
      );
      setState(() {
        _screenFrameStatus = '手机: 未开启录屏';
      });
    });
  }

  void _toggleDefenderWin() {
    if (_winOn) {
      _stopWin();
      return;
    }
    _winCap.initialize();
    _winOn = true;
    _winTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_winOn || _remoteServerUrl == null || _winCaptureBusy) return;
      _winCaptureBusy = true;
      try {
        final j = await _winCap.capture();
        if (j != null) {
          await http.post(Uri.parse('$_remoteServerUrl/frame/win'),
              body: j,
              headers: {
                'Content-Type': 'image/jpeg'
              }).timeout(const Duration(seconds: 2));
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'Defender.win', stack: st);
      } finally {
        _winCaptureBusy = false;
      }
    });
    setState(() {});
  }

  void _toggleDefenderCam() {
    if (_cameraOn) {
      _stopCam();
      return;
    }
    _startCamToRemote();
  }

  void _toggleDefenderSwitchCam() {
    _live.switchCamera();
  }

  void _startCamToRemote() {
    if (_cameraOn && _camTimer != null) return;
    try {
      _cameraOn = true;
      _camTimer?.cancel();
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
    _heartbeatTimer?.cancel();
    unawaited(_sendHeartbeat());
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_sendHeartbeat()),
    );
  }

  Future<void> _sendHeartbeat() async {
    final userId = _auth.getCurrentUserId() ?? 'unknown';
    if (_remoteServerUrl == null) return;
    try {
      await http.post(
        Uri.parse('$_remoteServerUrl/heartbeat'),
        body: jsonEncode({
          'deviceName': '答辩学生 $userId',
          'source': 'defender',
          'studentId': userId,
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 2));
    } catch (e, st) {
      swallowDebug(e, tag: 'Defender.heartbeat', stack: st);
    }
  }

  void _stopDefender() {
    _stopWin();
    _stopCam();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_phoneCap.isActive) _phoneCap.stop();
  }

  /// 学生答辩录屏开关。复用 LiveStreamService（Win 降级音频+计时，移动端录 mp4）。
  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _live.stopRecording();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(path != null ? '录屏已保存：$path' : '录屏已停止'),
          duration: const Duration(seconds: 5),
        ));
      }
      return;
    }
    // 录制需要摄像头已就绪
    if (!_cameraOn) _startCamToRemote();
    await _live.startRecording();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开始录屏')),
      );
    }
  }

  void _toggleWin() {
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('仅 Windows 支持桌面抓取')));
      return;
    }
    _winOn ? _stopWin() : _startWin();
  }

  void _startWin() {
    if (_winOn) return;
    _winCap.initialize(width: 960, height: 540, quality: 65);
    _winOn = true;
    if (_role == 'present') {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_winOn && mounted && _role == 'present') {
          _winCap.minimizeForegroundWindow();
        }
      });
    }
    _winTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_winOn || _winCaptureBusy) return;
      _winCaptureBusy = true;
      try {
        final j = await _winCap.capture();
        if (j != null) _server.pushWinFrame(j);
      } catch (e, st) {
        swallowDebug(e, tag: 'Defense.win', stack: st);
      } finally {
        _winCaptureBusy = false;
      }
    });
    setState(() {});
  }

  void _stopWin() {
    _winOn = false;
    _winCaptureBusy = false;
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
          try {
            await f.delete();
          } catch (e) {
            swallow(e, tag: 'Defense.cam.del');
          }
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
    if (_serverReady || _presentPhoneTargetUrl != null) {
      debugPrint('Defense: stopping server');
      if (_server.isRunning) {
        _server.stop();
      }
      _stopWin();
      _stopCam();
      if (_phoneCap.isActive) {
        _phoneCap.stop();
      }
      _statusTimer?.cancel();
      _statusTimer = null;
      _viewerStatusTimer?.cancel();
      _viewerStatusTimer = null;
      setState(() {
        _serverReady = false;
        _presentPhoneTargetUrl = null;
        _viewerServerUrl = null;
        _viewerSourceRole = null;
        _viewerHasWin = false;
        _viewerHasPhone = false;
        _serverHasWin = false;
        _serverHasPhone = false;
      });
    } else {
      debugPrint('Defense: starting presenter');
      if (_role == 'present' && !Platform.isWindows) {
        _initMobilePresent();
      } else {
        _initPresenter();
      }
    }
  }

  Future<void> _connectViewer() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    final baseUrl = ip.startsWith('http://') || ip.startsWith('https://')
        ? ip.replaceAll(RegExp(r'/$'), '')
        : 'http://$ip:$_serverPort';
    String? role;
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        role = data['role'] as String?;
        _applyViewerStatus(data);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'Viewer.connectStatus', stack: st);
    }
    if (!mounted) return;
    setState(() {
      _viewerServerUrl = baseUrl;
      _viewerSourceRole = role;
    });
    _startViewerStatusPolling();
  }

  void _startViewerStatusPolling() {
    _viewerStatusTimer?.cancel();
    unawaited(_refreshViewerStatus());
    _viewerStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refreshViewerStatus());
    });
  }

  Future<void> _refreshViewerStatus() async {
    final baseUrl = _viewerServerUrl;
    if (!mounted || baseUrl == null || baseUrl.isEmpty) return;
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200 || !mounted) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _applyViewerStatus(data);
    } catch (e, st) {
      swallowDebug(e, tag: 'Viewer.status', stack: st);
    }
  }

  void _applyViewerStatus(Map<String, dynamic> data) {
    final frames = (data['frames'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final sourceRole = data['role'] as String?;
    final hasWin = _frameLive(frames, 'win', 'winAge');
    final hasPhone = _frameLive(frames, 'phone', 'phoneAge');
    final presentStatus = _presentScreenStatus(
      winLive: hasWin,
      phoneLive: hasPhone,
    );
    if (!mounted) return;
    if (_viewerSourceRole != sourceRole ||
        _viewerHasWin != hasWin ||
        _viewerHasPhone != hasPhone ||
        (_role == 'present' && _screenFrameStatus != presentStatus)) {
      setState(() {
        _viewerSourceRole = sourceRole ?? _viewerSourceRole;
        _viewerHasWin = hasWin;
        _viewerHasPhone = hasPhone;
        if (_role == 'present') {
          _screenFrameStatus = presentStatus;
          _screenFrameLive = hasWin || hasPhone;
        }
      });
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
    final normalView = Scaffold(
      appBar: AppBar(
          title: Text(_role == 'defender'
              ? '开始答辩'
              : _role == 'present'
                  ? '教师演示'
                  : '答辩直播'),
          actions: _isTeacherOrAdmin && _role != 'select'
              ? [
                  _chip('presenter', '主播'),
                  _chip('present', '演示'),
                  _chip('viewer', '观看'),
                ]
              : null),
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: _role == 'select'
                  ? _buildRoleLanding()
                  : _role == 'presenter' || _role == 'present'
                      ? _buildPresenter()
                      : _role == 'defender'
                          ? _buildDefender()
                          : _buildViewer())),
    );

    if (!_isFullscreen) return normalView;

    return GestureDetector(
      onTap: _toggleFullscreen,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _role == 'presenter' || _role == 'present'
            ? _buildFullscreenPreview()
            : _role == 'defender'
                ? _buildDefenderPreview()
                : _buildFullscreenViewer(),
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
              _switchRole(role);
            },
            visualDensity: VisualDensity.compact));
  }

  Widget _buildRoleLanding() {
    final actions = _isTeacherOrAdmin
        ? const [
            _RoleAction(
              role: 'presenter',
              label: '主播',
              subtitle: '发起答辩活动，通知学生答辩，查看答辩学生屏幕和摄像头',
              icon: Icons.campaign,
              color: Colors.green,
            ),
            _RoleAction(
              role: 'viewer',
              label: '观看',
              subtitle: '作为非主播教师观看正在进行的答辩或演示',
              icon: Icons.visibility,
              color: Colors.blue,
            ),
            _RoleAction(
              role: 'present',
              label: '演示',
              subtitle: '展示教师 Windows/手机桌面，可与另一台教师设备合并演示',
              icon: Icons.co_present,
              color: Colors.deepPurple,
            ),
          ]
        : const [
            _RoleAction(
              role: 'viewer',
              label: '观看',
              subtitle: '观看其他同学答辩或教师演示',
              icon: Icons.visibility,
              color: Colors.blue,
            ),
            _RoleAction(
              role: 'defender',
              label: '答辩',
              subtitle: '连接教师主播，推送本机/手机屏幕和摄像头，可开启录屏',
              icon: Icons.record_voice_over,
              color: Colors.green,
            ),
          ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 760 ? actions.length : 1;
      return GridView.count(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: columns == 1 ? 3.4 : 1.75,
        children: [
          for (final action in actions) _roleActionCard(action),
        ],
      );
    });
  }

  Widget _roleActionCard(_RoleAction action) {
    return InkWell(
      onTap: () => _switchRole(action.role),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NoirTokens.ink.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: action.color.withValues(alpha: 0.28)),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(action.icon, color: action.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.label,
                    style: const TextStyle(
                        color: NoirTokens.paper,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(action.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: NoirTokens.paper.withValues(alpha: 0.55),
                        fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              color: NoirTokens.paper.withValues(alpha: 0.35)),
        ]),
      ),
    );
  }

  Widget _buildPresenter() => Column(children: [
        DefenseControlsPanel(
            isBroadcasting: _serverReady,
            isWinCaptureOn: _winOn,
            isPhoneCaptureOn: _phoneCap.isActive,
            isCameraOn: _cameraOn,
            layoutMode: _layoutMode,
            serverIp: _serverIp,
            serverPort: _serverPort,
            viewerCount: _viewerCount,
            showTeacherCaptureControls: _role == 'present',
            showWinCaptureControl: _role == 'present' && Platform.isWindows,
            showPhoneCaptureControl: _role == 'present' && !Platform.isWindows,
            onToggleBroadcast: _toggleBroadcast,
            onToggleWinCapture: _toggleWin,
            onTogglePhoneCapture: _togglePresentPhoneShare,
            onToggleCamera: _toggleCam,
            onLayoutChanged: _onLayoutChanged),
        if (_serverReady && _role == 'presenter') ...[
          const SizedBox(height: 12),
          _buildNotifyButton(),
        ],
        if (_role == 'presenter' &&
            _activeDefenderId != null &&
            _activeDefenderId!.isNotEmpty) ...[
          const SizedBox(height: 12),
          DefenseProjectInfoPanel(userId: _activeDefenderId!),
        ],
        if (_serverReady) ...[
          const SizedBox(height: 8),
          _buildStreamDiagnostics(),
        ],
        const SizedBox(height: 12),
        Expanded(child: _buildPreview()),
      ]);

  Widget _buildStreamDiagnostics() {
    return Row(children: [
      Expanded(
        child: _statusPill(
          icon: Icons.screen_share,
          text: _screenFrameStatus,
          live: _screenFrameLive,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _statusPill(
          icon: Icons.videocam,
          text: _cameraFrameStatus,
          live: _cameraFrameLive,
        ),
      ),
    ]);
  }

  Widget _statusPill({
    required IconData icon,
    required String text,
    required bool live,
  }) {
    final color = live ? Colors.green : Colors.orange;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: NoirTokens.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, color: NoirTokens.paper.withValues(alpha: 0.78)),
          ),
        ),
      ]),
    );
  }

  Widget _buildFullscreenPreview() {
    if (_role == 'present') return _buildPresentSourceStatus();
    final screenUrl = 'http://$_serverIp:$_serverPort/raw/screen';
    final cameraUrl = 'http://$_serverIp:$_serverPort/raw/camera';
    return _buildPreviewLayout(screenUrl, cameraUrl);
  }

  Widget _buildFullscreenViewer() {
    return _buildViewerStream();
  }

  String? get _viewerScreenUrl =>
      _viewerServerUrl == null ? null : '$_viewerServerUrl/raw/screen';

  String? get _viewerWinUrl =>
      _viewerServerUrl == null ? null : '$_viewerServerUrl/raw/win';

  String? get _viewerPhoneUrl =>
      _viewerServerUrl == null ? null : '$_viewerServerUrl/raw/phone';

  String? get _viewerCameraUrl =>
      _viewerServerUrl == null ? null : '$_viewerServerUrl/raw/camera';

  Widget _buildViewerStream() {
    if (_viewerServerUrl == null) {
      return DefenseViewerWidget(
        onFullscreenToggle: _toggleFullscreen,
        isFullscreen: _isFullscreen,
        url: null,
        label: '答辩直播',
      );
    }
    if (_viewerSourceRole == 'present') {
      return _buildPresentViewerStreams(
        winUrl: _viewerWinUrl,
        phoneUrl: _viewerPhoneUrl,
        hasWin: _viewerHasWin,
        hasPhone: _viewerHasPhone,
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final children = [
        Expanded(
          child: DefenseViewerWidget(
            onFullscreenToggle: _toggleFullscreen,
            isFullscreen: _isFullscreen,
            url: _viewerScreenUrl,
            label: '学生屏幕',
          ),
        ),
        Container(
          width: constraints.maxWidth < 600 ? double.infinity : 2,
          height: constraints.maxWidth < 600 ? 2 : double.infinity,
          color: NoirTokens.paper.withValues(alpha: 0.1),
        ),
        Expanded(
          child: DefenseViewerWidget(
            onFullscreenToggle: _toggleFullscreen,
            isFullscreen: _isFullscreen,
            url: _viewerCameraUrl,
            label: '学生摄像头',
          ),
        ),
      ];
      return constraints.maxWidth < 600
          ? Column(children: children)
          : Row(children: children);
    });
  }

  Widget _buildPresentViewerStreams({
    required String? winUrl,
    required String? phoneUrl,
    required bool hasWin,
    required bool hasPhone,
  }) {
    final streams = <Widget>[];
    if (hasWin) {
      streams.add(DefenseViewerWidget(
        onFullscreenToggle: _toggleFullscreen,
        isFullscreen: _isFullscreen,
        url: winUrl,
        label: '教师Windows桌面',
      ));
    }
    if (hasPhone) {
      streams.add(DefenseViewerWidget(
        onFullscreenToggle: _toggleFullscreen,
        isFullscreen: _isFullscreen,
        url: phoneUrl,
        label: '教师手机桌面',
      ));
    }
    if (streams.isEmpty) {
      return DefenseViewerWidget(
        onFullscreenToggle: _toggleFullscreen,
        isFullscreen: _isFullscreen,
        url: _viewerScreenUrl,
        label: '教师桌面',
        placeholder: _empty('等待教师演示桌面'),
      );
    }
    if (streams.length == 1) return streams.first;
    return LayoutBuilder(builder: (context, constraints) {
      final children = [
        Expanded(child: streams[0]),
        Container(
          width: constraints.maxWidth < 600 ? double.infinity : 2,
          height: constraints.maxWidth < 600 ? 2 : double.infinity,
          color: NoirTokens.paper.withValues(alpha: 0.1),
        ),
        Expanded(child: streams[1]),
      ];
      return constraints.maxWidth < 600
          ? Column(children: children)
          : Row(children: children);
    });
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
              gradient: LinearGradient(colors: [
                NoirTokens.accent.withValues(alpha: 0.8),
                NoirTokens.accent
              ]),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.red.withValues(alpha: 0.6),
                          blurRadius: 6)
                    ])),
            const SizedBox(width: 8),
            const Text('答辩直播中',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(isScreenSharing ? '投屏中' : '已连接',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          ])),
      const SizedBox(height: 10),
      DefenseProjectInfoPanel(
          userId: _auth.getCurrentUserId() ?? '', compact: true),
      const SizedBox(height: 10),
      // 主画面：摄像头（占满可用空间）
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: NoirTokens.inkDeep,
            child: _cameraOn
                ? LiveStreamPanel(
                    onClose: _toggleDefenderCam,
                    onMinimize: () {},
                    onFullscreen: () {},
                    onLock: () {})
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.videocam,
                        size: 48,
                        color: NoirTokens.paper.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Text('点击下方按钮开启摄像头',
                        style: TextStyle(
                            color: NoirTokens.paper.withValues(alpha: 0.4),
                            fontSize: 14)),
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
            icon: Platform.isWindows
                ? Icons.desktop_windows
                : Icons.phone_android,
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
        const SizedBox(width: 8),
        // 录屏
        _defenderSmallBtn(
          _recording ? Icons.stop_circle : Icons.fiber_manual_record,
          _toggleRecording,
          color: _recording ? Colors.red : null,
        ),
      ]),
      const SizedBox(height: 10),
      // 结束按钮
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
  }

  Widget _buildDefenderConnect() {
    return Column(children: [
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: NoirTokens.ink.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: NoirTokens.accent.withValues(alpha: 0.2))),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _ipCtrl,
                      decoration: InputDecoration(
                          labelText: '教师服务器 IP',
                          hintText: '192.168.x.x',
                          prefixIcon: const Icon(Icons.cast, size: 18),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          isDense: true),
                      style: const TextStyle(fontSize: 14),
                      inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ])),
              const SizedBox(width: 8),
              FilledButton.icon(
                  onPressed: _initDefender,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('开始答辩'),
                  style: FilledButton.styleFrom(
                      backgroundColor: NoirTokens.accent)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              if (_isScanning || (_discovery?.isRunning ?? false)) ...[
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _discovered.isNotEmpty
                      ? '已发现教师 ${_discovered.first.ip}，正在连接…'
                      : (_discovery?.isRunning ?? false)
                          ? '正在局域网内搜索教师…（也可手动输入 IP 后点"开始答辩"）'
                          : '请输入教师机的 IP 地址后点击"开始答辩"',
                  style: TextStyle(
                      fontSize: 11,
                      color: NoirTokens.paper.withValues(alpha: 0.4)),
                ),
              ),
            ]),
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

  Widget _defenderCtrlBtn(
      {required IconData icon,
      required String label,
      required bool active,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: active
                ? Colors.green.withValues(alpha: 0.15)
                : NoirTokens.ink.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active
                    ? Colors.green.withValues(alpha: 0.4)
                    : NoirTokens.paper.withValues(alpha: 0.15))),
        child: Column(children: [
          Icon(icon,
              color:
                  active ? Colors.green : Colors.white.withValues(alpha: 0.6),
              size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: active
                      ? Colors.green
                      : Colors.white.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }

  Widget _defenderSmallBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: NoirTokens.ink.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: (color ?? NoirTokens.paper)
                    .withValues(alpha: color != null ? 0.5 : 0.15))),
        child: Icon(icon,
            color: color ?? Colors.white.withValues(alpha: 0.6), size: 20),
      ),
    );
  }

  Widget _buildDefenderPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
          color: NoirTokens.inkDeep,
          child:
              _isConnectedToServer ? _buildLocalPreview() : _empty('连接中...')),
    );
  }

  /// 本地预览：显示摄像头 PIP + 屏幕录制状态（避免看远程流造成递归死循环）
  Widget _buildLocalPreview() {
    final isSharing = _winOn || _phoneCap.isActive;
    return Stack(fit: StackFit.expand, children: [
      // 主区域：录制状态
      Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(isSharing ? Icons.screen_share : Icons.live_tv,
            size: 64,
            color: isSharing
                ? Colors.green.withValues(alpha: 0.6)
                : NoirTokens.paper.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        Text(isSharing ? '屏幕录制中...\n请演示你的应用' : '已连接 · 点击下方按钮开始投屏',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isSharing
                    ? Colors.green.withValues(alpha: 0.8)
                    : NoirTokens.paper.withValues(alpha: 0.4),
                fontSize: 14)),
        if (isSharing) ...[
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.circle, size: 10, color: Colors.red),
            const SizedBox(width: 6),
            Text('REC',
                style: TextStyle(
                    color: Colors.red.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
          ]),
        ],
      ])),
      // PIP 摄像头（右下角）
      if (_cameraOn)
        Positioned(
          right: 8,
          bottom: 8,
          width: 160,
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: NoirTokens.accent.withValues(alpha: 0.5), width: 2),
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
      if (_role == 'present' && _presentPhoneTargetUrl != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: NoirTokens.inkDeep,
            child: _buildPresentSourceStatus(),
          ),
        );
      }
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

    final screenUrl = 'http://$_serverIp:$_serverPort/raw/screen';
    final cameraUrl = 'http://$_serverIp:$_serverPort/raw/camera';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: NoirTokens.inkDeep,
        child: _role == 'present'
            ? _buildPresentSourceStatus()
            : _buildPreviewLayout(screenUrl, cameraUrl),
      ),
    );
  }

  Widget _buildPresentSourceStatus() {
    final targetUrl = _presentPhoneTargetUrl ??
        (_server.isRunning ? _server.serverUrl : _viewerServerUrl);
    final winLive = _serverHasWin || (Platform.isWindows && _winOn);
    final phoneLive = _serverHasPhone || _viewerHasPhone || _phoneCap.isActive;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.co_present,
                size: 52,
                color: (winLive || phoneLive)
                    ? Colors.green.withValues(alpha: 0.75)
                    : NoirTokens.paper.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(
              winLive || phoneLive ? '教师演示源已开启' : '等待教师演示源',
              style: TextStyle(
                  color: NoirTokens.paper.withValues(alpha: 0.86),
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '本页不显示本机直播画面，避免桌面录制递归。观看端会看到教师 Windows 桌面、教师手机桌面或两者并排。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: NoirTokens.paper.withValues(alpha: 0.5), fontSize: 12),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final winCard = _presentSourceCard(
                icon: Icons.desktop_windows,
                title: '教师Windows桌面',
                status: winLive
                    ? '直播中'
                    : Platform.isWindows
                        ? '未开启'
                        : '未接入',
                live: winLive,
              );
              final phoneCard = _presentSourceCard(
                icon: Icons.phone_android,
                title: '教师手机桌面',
                status: phoneLive
                    ? '直播中'
                    : !Platform.isWindows
                        ? '未开启录屏'
                        : '未接入',
                live: phoneLive,
              );
              if (constraints.maxWidth < 560) {
                return Column(children: [
                  winCard,
                  const SizedBox(height: 10),
                  phoneCard,
                ]);
              }
              return Row(children: [
                Expanded(child: winCard),
                const SizedBox(width: 10),
                Expanded(child: phoneCard),
              ]);
            }),
            if (targetUrl != null && targetUrl.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                targetUrl,
                style: const TextStyle(
                    color: NoirTokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _presentSourceCard({
    required IconData icon,
    required String title,
    required String status,
    required bool live,
  }) {
    final color = live ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NoirTokens.ink.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: NoirTokens.paper,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(status,
                style: TextStyle(
                    color: color.withValues(alpha: 0.86), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildPreviewLayout(String screenUrl, String cameraUrl) {
    switch (_layoutMode) {
      case 'dual':
        // 并排模式：左桌面（win/phone 自动），右摄像头人脸
        return Row(children: [
          Expanded(
              child: DefenseViewerWidget(
            onFullscreenToggle: _toggleFullscreen,
            isFullscreen: _isFullscreen,
            url: screenUrl,
            label: '学生手机/桌面',
          )),
          Container(width: 2, color: NoirTokens.paper.withValues(alpha: 0.1)),
          Expanded(
              child: DefenseViewerWidget(
            onFullscreenToggle: _toggleFullscreen,
            isFullscreen: _isFullscreen,
            url: cameraUrl,
            label: '学生摄像头',
          )),
        ]);

      case 'phoneOnly':
        return DefenseViewerWidget(
          onFullscreenToggle: _toggleFullscreen,
          isFullscreen: _isFullscreen,
          url: screenUrl,
          label: '学生手机',
        );

      case 'winOnly':
        return DefenseViewerWidget(
          onFullscreenToggle: _toggleFullscreen,
          isFullscreen: _isFullscreen,
          url: screenUrl,
          label: '学生桌面',
        );

      case 'cameraOnly':
        return DefenseViewerWidget(
          onFullscreenToggle: _toggleFullscreen,
          isFullscreen: _isFullscreen,
          url: cameraUrl,
          label: '学生摄像头',
        );

      default:
        return _empty('未知布局模式');
    }
  }

  Widget _empty(String t) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.live_tv,
            size: 48, color: NoirTokens.paper.withValues(alpha: 0.15)),
        const SizedBox(height: 8),
        Text(t,
            style: TextStyle(
                color: NoirTokens.paper.withValues(alpha: 0.3), fontSize: 14)),
      ]));

  Widget _buildViewer() => Column(children: [
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: NoirTokens.ink.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: NoirTokens.accent.withValues(alpha: 0.2))),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _ipCtrl,
                      decoration: InputDecoration(
                          labelText: '服务器 IP',
                          hintText: '192.168.x.x',
                          prefixIcon: const Icon(Icons.cast, size: 18),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          isDense: true),
                      style: const TextStyle(fontSize: 14),
                      inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ])),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => unawaited(_connectViewer()),
                  child: const Text('连接')),
            ])),
        if (_discovered.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('发现局域网直播源（点击连接）：',
                style: TextStyle(
                    fontSize: 11,
                    color: NoirTokens.paper.withValues(alpha: 0.5))),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _discovered)
              ActionChip(
                avatar: Icon(
                    e.role == 'present' ? Icons.co_present : Icons.live_tv,
                    size: 16,
                    color: Colors.green),
                label: Text('${e.roleLabel} · ${e.displayName}',
                    style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  _ipCtrl.text = e.ip;
                  _serverPort = e.port;
                  setState(() {
                    _viewerServerUrl = e.serverUrl;
                    _viewerSourceRole = e.role;
                  });
                  _startViewerStatusPolling();
                },
              ),
          ]),
        ],
        const SizedBox(height: 12),
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                    color: NoirTokens.inkDeep, child: _buildViewerStream()))),
      ]);

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
      final notifiedStudents =
          await _getNotifiedStudents(allStudents.keys.toSet());

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

class _RoleAction {
  final String role;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _RoleAction({
    required this.role,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
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
  State<_StudentSelectionDialog> createState() =>
      _StudentSelectionDialogState();
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
              title: const Text('全选',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle,
                                    size: 12, color: Colors.green),
                                SizedBox(width: 2),
                                Text(
                                  '已通知',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.green),
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
