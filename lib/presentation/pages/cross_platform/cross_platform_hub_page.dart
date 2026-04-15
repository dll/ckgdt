import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/auth_service.dart';
import '../../../services/cross_platform/sync_server.dart';
import '../../../services/cross_platform/sync_client.dart';
import '../../../services/cross_platform/sync_protocol.dart';
import '../../../services/cross_platform/session_manager.dart';
import 'qr_scan_page.dart';

/// 三端互通 Hub 页面
///
/// 根据平台角色自动展示不同功能区：
/// - **桌面端**（服务器模式）：启动服务器 → 显示 QR 码 → 管理连接 → 打开 Web
/// - **移动端**（客户端模式）：扫码连接 → 数据同步 → 显示连接状态
/// - **Web 端**（客户端模式）：手动输入地址连接 → 数据同步
class CrossPlatformHubPage extends StatefulWidget {
  const CrossPlatformHubPage({super.key});

  @override
  State<CrossPlatformHubPage> createState() => _CrossPlatformHubPageState();
}

class _CrossPlatformHubPageState extends State<CrossPlatformHubPage> {
  final _authService = AuthService();
  final _syncClient = SyncClient();

  // 服务器（仅桌面端使用）
  SyncServerImpl? _syncServer;
  bool _isServerRunning = false;
  String? _qrData;
  QrSession? _currentQrSession;
  Timer? _qrPollTimer;

  // 客户端（移动端/Web 使用）
  bool _isConnected = false;
  String? _connectedServerUrl;
  bool _isSyncing = false;
  String? _syncMessage;

  // 连接设备列表
  List<Map<String, dynamic>> _devices = [];

  // 平台判断
  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _syncServer = SyncServerImpl();
    }
  }

  @override
  void dispose() {
    _qrPollTimer?.cancel();
    _syncServer?.stop();
    _syncClient.disconnect();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 服务器管理（桌面端）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startServer() async {
    try {
      _syncServer!.onQrLoginConfirmed = (userId, realName, role) {
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ $realName ($userId) 已通过扫码登录')),
          );
        }
      };
      _syncServer!.onDataPushed = (userId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📥 收到 $userId 的同步数据')),
          );
        }
      };

      await _syncServer!.start();
      _generateQrCode();
      setState(() => _isServerRunning = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动服务器失败: $e')),
        );
      }
    }
  }

  Future<void> _stopServer() async {
    _qrPollTimer?.cancel();
    await _syncServer?.stop();
    setState(() {
      _isServerRunning = false;
      _qrData = null;
      _currentQrSession = null;
      _devices = [];
    });
  }

  void _generateQrCode() {
    if (_syncServer == null || !_syncServer!.isRunning) return;

    final session = _syncServer!.sessionManager.createQrSession();
    final qrJson = jsonEncode({
      'host': _syncServer!.host,
      'port': _syncServer!.port,
      'qrToken': session.qrToken,
      'app': 'MADKG',
    });

    setState(() {
      _qrData = qrJson;
      _currentQrSession = session;
    });

    // 轮询 QR 状态（每秒检查）
    _qrPollTimer?.cancel();
    _qrPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentQrSession == null) return;
      final updated =
          _syncServer!.sessionManager.checkQrSession(_currentQrSession!.qrToken);
      if (updated != null && updated.isConfirmed) {
        _qrPollTimer?.cancel();
        _syncServer!.sessionManager.consumeQrSession(updated.qrToken);
        if (mounted) {
          setState(() {
            _currentQrSession = null;
            _qrData = null;
          });
          _refreshDevices();
        }
      }
      // QR 过期自动刷新
      if (updated == null || updated.isExpired) {
        _generateQrCode();
      }
    });
  }

  Future<void> _refreshDevices() async {
    if (_syncServer != null && _syncServer!.isRunning) {
      setState(() {
        _devices = _syncServer!.sessionManager.connectedDevices
            .map((d) => d.toJson())
            .toList();
      });
    } else if (_isConnected) {
      final devices = await _syncClient.getDevices();
      if (mounted) setState(() => _devices = devices);
    }
  }

  Future<void> _openWebVersion() async {
    if (_syncServer == null || !_syncServer!.isRunning) return;
    final url = Uri.parse(_syncServer!.serverUrl!);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开浏览器: $e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 客户端操作（移动端/Web）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _scanQrCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (result != null && result.isNotEmpty) {
      await _processQrData(result);
    }
  }

  Future<void> _processQrData(String rawData) async {
    try {
      final data = jsonDecode(rawData) as Map<String, dynamic>;
      final host = data['host'] as String?;
      final port = data['port'] as int?;
      final qrToken = data['qrToken'] as String?;

      if (host == null || port == null || qrToken == null) {
        _showError('QR 码格式无效');
        return;
      }

      final serverUrl = 'http://$host:$port';

      // 先检查服务器可达性
      setState(() => _isSyncing = true);
      final status = await SyncClient.checkServer(serverUrl);
      if (status == null) {
        setState(() => _isSyncing = false);
        _showError('无法连接到服务器 $serverUrl');
        return;
      }

      // 获取当前用户信息
      final user = _authService.currentUser;
      if (user == null) {
        setState(() => _isSyncing = false);
        _showError('请先登录');
        return;
      }

      // 导出当前用户数据用于同步
      final syncData = await SyncProtocol.exportUserData(user.userId);

      // 确认 QR 登录
      final result = await _syncClient.confirmQrLogin(
        serverUrl: serverUrl,
        qrToken: qrToken,
        userId: user.userId,
        realName: user.realName ?? '',
        role: user.role,
        syncData: syncData,
      );

      if (result['success'] == true) {
        // 连接成功
        await _syncClient.connect(
          serverUrl: serverUrl,
          userId: user.userId,
          platform: defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : 'ios',
          deviceName: '${user.realName ?? user.userId} 的手机',
        );

        setState(() {
          _isConnected = true;
          _connectedServerUrl = serverUrl;
          _isSyncing = false;
          _syncMessage = '已连接到桌面端，数据同步完成';
        });
        _refreshDevices();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 扫码登录成功，数据已同步')),
          );
        }
      } else {
        setState(() {
          _isSyncing = false;
          _syncMessage = result['error'] as String? ?? '连接失败';
        });
        _showError(result['error'] as String? ?? '连接失败');
      }
    } catch (e) {
      setState(() => _isSyncing = false);
      _showError('处理 QR 码失败: $e');
    }
  }

  Future<void> _manualConnect() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动连接'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: 'http://192.168.1.x:8765',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('连接'),
          ),
        ],
      ),
    );

    if (url != null && url.isNotEmpty) {
      final user = _authService.currentUser;
      if (user == null) return;

      setState(() => _isSyncing = true);

      final status = await SyncClient.checkServer(url);
      if (status == null) {
        setState(() => _isSyncing = false);
        _showError('无法连接到 $url');
        return;
      }

      final result = await _syncClient.connect(
        serverUrl: url,
        userId: user.userId,
        platform: kIsWeb
            ? 'web'
            : defaultTargetPlatform == TargetPlatform.android
                ? 'android'
                : 'unknown',
        deviceName: '${user.realName ?? user.userId} 的设备',
      );

      if (result['success'] == true) {
        setState(() {
          _isConnected = true;
          _connectedServerUrl = url;
          _isSyncing = false;
          _syncMessage = '已连接到服务器';
        });
        _refreshDevices();
      } else {
        setState(() => _isSyncing = false);
        _showError(result['error'] as String? ?? '连接失败');
      }
    }
  }

  Future<void> _syncData() async {
    if (!_isConnected) return;
    final user = _authService.currentUser;
    if (user == null) return;

    setState(() {
      _isSyncing = true;
      _syncMessage = '正在同步数据...';
    });

    try {
      // 1) 推送本地数据
      final pushed = await _syncClient.pushUserData(user.userId);
      if (!pushed) {
        setState(() {
          _isSyncing = false;
          _syncMessage = '推送数据失败';
        });
        return;
      }

      // 2) 拉取服务器数据
      final remoteData = await _syncClient.pullSharedData();
      if (remoteData != null) {
        await SyncProtocol.importData(remoteData);
      }

      final userData = await _syncClient.pullUserData(user.userId);
      if (userData != null) {
        await SyncProtocol.importData(userData);
      }

      setState(() {
        _isSyncing = false;
        _syncMessage = '同步完成 (${DateTime.now().toString().substring(11, 19)})';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 数据同步完成')),
        );
      }
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _syncMessage = '同步出错: $e';
      });
    }
  }

  void _disconnectClient() {
    _syncClient.disconnect();
    setState(() {
      _isConnected = false;
      _connectedServerUrl = null;
      _syncMessage = null;
      _devices = [];
    });
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('三端互通'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refreshDevices,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 顶部信息头 ────────────────────────────────────────────
            _buildHeader(theme),
            const SizedBox(height: 16),

            // ── 平台对应的主功能区 ────────────────────────────────────
            if (_isDesktop) ...[
              _buildServerSection(theme),
              const SizedBox(height: 16),
              if (_isServerRunning && _qrData != null)
                _buildQrCodeSection(theme),
              if (_isServerRunning) ...[
                const SizedBox(height: 16),
                _buildWebAccessSection(theme),
              ],
            ] else ...[
              _buildClientSection(theme),
            ],

            // ── 已连接设备列表 ─────────────────────────────────────────
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildDeviceList(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final platformName = _isDesktop
        ? '桌面端'
        : _isMobile
            ? '移动端'
            : 'Web 端';
    final platformIcon = _isDesktop
        ? Icons.desktop_windows
        : _isMobile
            ? Icons.phone_android
            : Icons.language;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(platformIcon, size: 40, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前：$platformName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isDesktop
                      ? '启动服务器 → 手机扫码或浏览器访问'
                      : '扫描桌面端 QR 码或手动输入地址',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          // 状态标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (_isServerRunning || _isConnected)
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  (_isServerRunning || _isConnected)
                      ? Icons.circle
                      : Icons.circle_outlined,
                  size: 10,
                  color: (_isServerRunning || _isConnected)
                      ? Colors.greenAccent
                      : Colors.white54,
                ),
                const SizedBox(width: 4),
                Text(
                  (_isServerRunning || _isConnected) ? '在线' : '离线',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 桌面端：服务器控制
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildServerSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('同步服务器',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Switch(
                  value: _isServerRunning,
                  onChanged: (v) => v ? _startServer() : _stopServer(),
                ),
              ],
            ),
            if (_isServerRunning) ...[
              const Divider(),
              Row(
                children: [
                  const Icon(Icons.circle, size: 10, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    '服务器运行中：${_syncServer!.serverUrl}',
                    style: TextStyle(
                        fontSize: 13, color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '启动服务器后，移动端和 Web 端可扫码或输入地址连接',
                  style:
                      TextStyle(fontSize: 13, color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCodeSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('扫码连接',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _generateQrCode,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: QrImageView(
                data: _qrData!,
                version: QrVersions.auto,
                size: 200,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF667eea),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF333333),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '使用手机 APP 扫描二维码连接',
              style: TextStyle(
                  fontSize: 13, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _syncServer?.serverUrl ?? '',
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebAccessSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Web 访问',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '在浏览器中打开 Web 版应用（需先构建 Flutter Web）',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openWebVersion,
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('在浏览器中打开'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    // 复制 URL
                    final url = _syncServer?.serverUrl ?? '';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('地址已复制：$url')),
                    );
                  },
                  child: const Text('复制地址'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 移动端/Web：客户端连接
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildClientSection(ThemeData theme) {
    if (_isConnected) {
      return _buildConnectedView(theme);
    }
    return _buildConnectOptions(theme);
  }

  Widget _buildConnectOptions(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.devices, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('连接到桌面端',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),

            // 扫码连接（仅移动端）
            if (_isMobile) ...[
              FilledButton.icon(
                onPressed: _isSyncing ? null : _scanQrCode,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫码连接'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('或', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // 手动输入地址
            OutlinedButton.icon(
              onPressed: _isSyncing ? null : _manualConnect,
              icon: const Icon(Icons.link),
              label: const Text('手动输入地址'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

            if (_isSyncing) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '正在连接...',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedView(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('已连接',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: _disconnectClient,
                  child: const Text('断开', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '服务器：$_connectedServerUrl',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
            ),
            if (_syncMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                _syncMessage!,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
              ),
            ],
            const Divider(height: 24),

            // 同步操作
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSyncing ? null : _syncData,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync),
                    label: Text(_isSyncing ? '同步中...' : '立即同步'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 已连接设备列表
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDeviceList(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('已连接设备 (${_devices.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            ..._devices.map((d) {
              final platform = d['platform'] as String? ?? '';
              final icon = platform == 'android'
                  ? Icons.phone_android
                  : platform == 'ios'
                      ? Icons.phone_iphone
                      : platform == 'web'
                          ? Icons.language
                          : Icons.desktop_windows;
              return ListTile(
                leading: Icon(icon, color: theme.colorScheme.primary),
                title: Text(d['deviceName'] as String? ?? '未知设备'),
                subtitle: Text(
                  '${d['userId'] ?? ''} • $platform',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  _formatTime(d['lastSeen'] as String?),
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline),
                ),
                dense: true,
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      return '${diff.inHours}小时前';
    } catch (_) {
      return '';
    }
  }
}
