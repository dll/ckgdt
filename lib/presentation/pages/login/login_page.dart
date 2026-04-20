import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/voice_service.dart';
import '../../../services/cross_platform/sync_server.dart';
import '../../../services/cross_platform/sync_client.dart';
import '../../../services/cross_platform/sync_protocol.dart';
import '../../../services/cross_platform/session_manager.dart';
import '../cross_platform/qr_scan_page.dart';
import '../../widgets/voice_input_button.dart';
import '../home/home_page.dart';
import '../../../data/local/course_dao.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _quickLoginEnabled = false;
  String _platformName = '移动应用开发';

  // Tab 控制
  late TabController _tabController;

  // ── 扫码登录相关（桌面/Web 显示 QR 码；手机端扫码） ──────────────────────
  SyncServerImpl? _syncServer;
  bool _isServerStarting = false;
  bool _isServerRunning = false;
  String? _qrData;
  QrSession? _currentQrSession;
  Timer? _qrPollTimer;
  String? _scanStatus;

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

  // ── 语音唤醒（"卖得" = MAD）──────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadQuickLoginSetting();
    _loadPlatformName();
  }

  Future<void> _loadQuickLoginSetting() async {
    final enabled = await SettingsService.isQuickLoginEnabled();
    if (mounted) setState(() => _quickLoginEnabled = enabled);
  }

  Future<void> _loadPlatformName() async {
    try {
      final course = await CourseDao().getActiveCourse();
      if (mounted && course != null) {
        setState(() => _platformName = course.name);
      }
    } catch (_) {}
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_tabController.indexIsChanging) {
      // 切换到扫码 Tab 时，桌面/Web 自动启动服务器生成 QR
      if ((_isDesktop || kIsWeb) && !_isServerRunning && !_isServerStarting) {
        _startQrServer();
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    _qrPollTimer?.cancel();
    _syncServer?.stop();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 账号密码登录
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final success = await _authService.login(
        _userIdController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => const HomePage(initialTabIndex: 1)),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('登录失败，请检查账号密码'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('=== LoginPage: Login error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录出错: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _quickLogin(String userId, String password, String name) {
    _userIdController.text = userId;
    _passwordController.text = password;
    _login();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 语音登录 — 直接弹出语音对话框，说学号自动登录
  // ═══════════════════════════════════════════════════════════════════════════

  /// 点击语音登录按钮 → 直接弹出语音登录对话框
  Future<void> _startVoiceLogin() async {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VoiceLoginDialog(
        authService: _authService,
        onLoginSuccess: () {
          Navigator.of(ctx).pop(); // 关闭对话框
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const HomePage(initialTabIndex: 1)),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 扫码登录 — 桌面/Web 端：启动服务器 + 显示 QR 码
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startQrServer() async {
    if (_isDesktop) {
      setState(() => _isServerStarting = true);
      try {
        _syncServer = SyncServerImpl();
        _syncServer!.onQrLoginConfirmed = (userId, realName, role) {
          // 扫码确认 → 自动登录桌面端
          _performQrAutoLogin(userId);
        };
        await _syncServer!.start();
        _generateQrCode();
        setState(() {
          _isServerRunning = true;
          _isServerStarting = false;
        });
      } catch (e) {
        setState(() {
          _isServerStarting = false;
          _scanStatus = '启动服务失败: $e';
        });
      }
    }
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
      _scanStatus = '等待手机扫码...';
    });

    // 轮询 QR 状态
    _qrPollTimer?.cancel();
    _qrPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentQrSession == null) return;
      final updated = _syncServer!.sessionManager
          .checkQrSession(_currentQrSession!.qrToken);
      if (updated != null && updated.isConfirmed) {
        _qrPollTimer?.cancel();
        _syncServer!.sessionManager.consumeQrSession(updated.qrToken);
        // 登录在 onQrLoginConfirmed 回调中处理
      }
      // QR 过期自动刷新
      if (updated == null || updated.isExpired) {
        _generateQrCode();
      }
    });
  }

  /// 扫码确认后，桌面端自动用该 userId 登录
  Future<void> _performQrAutoLogin(String userId) async {
    if (!mounted) return;
    setState(() => _scanStatus = '扫码成功，正在登录...');

    try {
      final success = await _authService.loginById(userId);
      if (!mounted) return;

      if (success) {
        _qrPollTimer?.cancel();
        await _syncServer?.stop();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => const HomePage(initialTabIndex: 1)),
        );
      } else {
        setState(() => _scanStatus = '用户 $userId 不存在，登录失败');
      }
    } catch (e) {
      if (mounted) setState(() => _scanStatus = '登录出错: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 扫码登录 — 移动端：扫码 → 确认 → 自身也登录
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _scanQrCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (result == null || result.isEmpty) return;
    await _processQrDataForLogin(result);
  }

  /// 处理移动端扫码结果：先弹出用户选择框，再确认 QR 登录
  Future<void> _processQrDataForLogin(String rawData) async {
    try {
      Map<String, dynamic> data;
      String? serverUrl;
      String? qrToken;

      // 尝试解析 JSON QR 码
      if (rawData.startsWith('{')) {
        data = jsonDecode(rawData) as Map<String, dynamic>;
        final host = data['host'] as String?;
        final port = data['port'] as int?;
        qrToken = data['qrToken'] as String?;
        if (host == null || port == null || qrToken == null) {
          _showError('QR 码格式无效');
          return;
        }
        serverUrl = 'http://$host:$port';
      } else if (rawData.startsWith('http')) {
        // 手动输入的 URL
        serverUrl = rawData;
      } else {
        _showError('无法识别的扫码内容');
        return;
      }

      setState(() => _scanStatus = '正在连接服务器...');

      // 检查服务器可达
      final status = await SyncClient.checkServer(serverUrl);
      if (status == null) {
        setState(() => _scanStatus = null);
        _showError('无法连接到服务器 $serverUrl');
        return;
      }

      // 弹出输入学号对话框让用户确认身份
      if (!mounted) return;
      final loginInfo = await _showMobileLoginDialog();
      if (loginInfo == null) {
        setState(() => _scanStatus = null);
        return;
      }

      setState(() => _scanStatus = '正在登录...');

      final userId = loginInfo['userId']!;
      final password = loginInfo['password']!;

      // 先验证本地登录
      final loginOk = await _authService.login(userId, password);
      if (!loginOk) {
        setState(() => _scanStatus = null);
        _showError('账号或密码错误');
        return;
      }

      // 获取登录后的用户信息
      final user = _authService.currentUser;
      if (user == null) {
        setState(() => _scanStatus = null);
        return;
      }

      // 如果有 QR Token，确认桌面端的 QR 登录
      if (qrToken != null) {
        final syncData = await SyncProtocol.exportUserData(user.userId);
        final syncClient = SyncClient();
        await syncClient.confirmQrLogin(
          serverUrl: serverUrl,
          qrToken: qrToken,
          userId: user.userId,
          realName: user.realName ?? '',
          role: user.role,
          syncData: syncData,
        );
      }

      if (!mounted) return;
      // 移动端登录成功，跳转首页
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => const HomePage(initialTabIndex: 1)),
      );
    } catch (e) {
      setState(() => _scanStatus = null);
      _showError('扫码登录失败: $e');
    }
  }

  /// 移动端扫码后弹出的登录确认对话框
  Future<Map<String, String>?> _showMobileLoginDialog() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.login, color: Color(0xFF667eea)),
            SizedBox(width: 8),
            Text('确认身份', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请输入你的学号/工号和密码来完成扫码登录',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextFormField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: '学号/工号',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? '请输入学号/工号' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? '请输入密码' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, {
                  'userId': userCtrl.text.trim(),
                  'password': passCtrl.text,
                });
              }
            },
            child: const Text('确认登录'),
          ),
        ],
      ),
    );
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
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppGradientTheme.of(context).verticalGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Logo + 标题 ────────────────────────────────────
                  const Icon(Icons.school, size: 80, color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    '$_platformName\n知识图谱教学平台',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── 双 Tab 登录卡片 ────────────────────────────────
                  _buildLoginCard(),

                  const SizedBox(height: 24),

                  // ── 快速登录按钮 ───────────────────────────────────
                  if (_quickLoginEnabled &&
                      _tabController.index == 0) ...[
                    const Text('快速登录',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () =>
                              _quickLogin('2023211985', '211985', '学生'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('学生'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () =>
                              _quickLogin('206004', '206004', '刘东良'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('教师'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () =>
                              _quickLogin('419116', '9116', '管理员'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('管理员'),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Text(
                    '提示：密码为账号后6位',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),

                  // ── 语音登录 ────────────────────────────────────
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _startVoiceLogin,
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.record_voice_over,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '语音登录（说出学号）',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 双 Tab 登录卡片
  Widget _buildLoginCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── TabBar ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}), // 刷新快速登录可见性
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Theme.of(context).colorScheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
                dividerHeight: 0,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.password, size: 20),
                    text: '账号登录',
                  ),
                  Tab(
                    icon: Icon(Icons.qr_code_scanner, size: 20),
                    text: '扫码登录',
                  ),
                ],
              ),
            ),

            // ── TabBarView ──────────────────────────────────────
            AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                // 使用 index 作为 key 触发动画切换
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _tabController.index == 0
                      ? _buildPasswordTab()
                      : _buildQrScanTab(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Tab1：账号密码登录表单
  Widget _buildPasswordTab() {
    return Padding(
      key: const ValueKey('password_tab'),
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _userIdController,
                    decoration: const InputDecoration(
                      labelText: '学号/工号',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return '请输入学号/工号';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: VoiceInputButton(
                    controller: _userIdController,
                    tooltip: '语音输入学号',
                    size: 40,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入密码';
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('登录', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab2：扫码登录
  Widget _buildQrScanTab() {
    return Padding(
      key: const ValueKey('qr_scan_tab'),
      padding: const EdgeInsets.all(24),
      child: _isMobile ? _buildMobileScanView() : _buildDesktopQrView(),
    );
  }

  // ── 桌面端/Web 端：显示 QR 码等待手机扫描 ──────────────────────────────
  Widget _buildDesktopQrView() {
    final theme = Theme.of(context);

    if (_isServerStarting) {
      return const SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在启动扫码服务...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (!_isServerRunning || _qrData == null) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_2, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('点击下方按钮生成登录二维码',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _startQrServer,
                icon: const Icon(Icons.qr_code),
                label: const Text('生成二维码'),
              ),
            ],
          ),
        ),
      );
    }

    // QR 码显示
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: QrImageView(
            data: _qrData!,
            version: QrVersions.auto,
            size: 180,
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
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _scanStatus?.contains('成功') == true
                  ? Icons.check_circle
                  : Icons.phone_android,
              size: 16,
              color: _scanStatus?.contains('成功') == true
                  ? Colors.green
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              _scanStatus ?? '请使用手机 APP 扫描二维码登录',
              style: TextStyle(
                fontSize: 13,
                color: _scanStatus?.contains('成功') == true
                    ? Colors.green
                    : Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _generateQrCode,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('刷新二维码', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── 移动端：扫码按钮 ──────────────────────────────────────────────────
  Widget _buildMobileScanView() {
    return SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.qr_code_scanner,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '扫描桌面端显示的二维码即可登录',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (_scanStatus != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _scanStatus!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _scanStatus!.contains('失败') ||
                            _scanStatus!.contains('错误')
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _scanQrCode,
                icon: const Icon(Icons.camera_alt),
                label: const Text('打开扫码', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _showManualConnectDialog,
              child: const Text('手动输入连接地址',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  /// 手动输入服务器地址（移动端备用）
  Future<void> _showManualConnectDialog() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动连接'),
        content: TextField(
          controller: ctrl,
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
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('连接'),
          ),
        ],
      ),
    );

    if (url != null && url.isNotEmpty) {
      await _processQrDataForLogin(url);
    }
  }
}

/// 语音登录对话框 — 说出学号自动登录，支持手动输入兜底
class _VoiceLoginDialog extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLoginSuccess;

  const _VoiceLoginDialog({
    required this.authService,
    required this.onLoginSuccess,
  });

  @override
  State<_VoiceLoginDialog> createState() => _VoiceLoginDialogState();
}

class _VoiceLoginDialogState extends State<_VoiceLoginDialog>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  final TextEditingController _manualController = TextEditingController();
  String _statusText = '请说出你的学号/工号';
  String _recognizedText = '';
  bool _isListening = false;
  bool _isLoggingIn = false;
  bool _showManualInput = false;
  bool _voiceAvailable = true;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _voiceService.onResult = (text) {
      if (mounted) setState(() => _recognizedText = text);
    };
    _voiceService.onComplete = (text) {
      if (mounted) {
        setState(() {
          _recognizedText = text;
          _isListening = false;
        });
        _pulseController.stop();
        _tryVoiceLogin(text);
      }
    };
    _voiceService.onError = (error) {
      if (mounted) {
        setState(() {
          _statusText = '语音识别出错: $error';
          _isListening = false;
          _voiceAvailable = false;
          _showManualInput = true;
        });
        _pulseController.stop();
      }
    };
    _voiceService.onStateChanged = (listening) {
      if (mounted) setState(() => _isListening = listening);
    };

    // 自动开始录音
    _startListening();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _manualController.dispose();
    if (_isListening) _voiceService.stopListening();
    super.dispose();
  }

  Future<void> _startListening() async {
    // 检查讯飞配置
    final configured = await VoiceService.isConfigured();
    if (!configured) {
      if (mounted) {
        setState(() {
          _statusText = '语音服务未配置，请手动输入学号';
          _voiceAvailable = false;
          _showManualInput = true;
        });
      }
      return;
    }

    setState(() {
      _statusText = '请说出你的学号/工号';
      _recognizedText = '';
    });
    final ok = await _voiceService.startListening();
    if (ok) {
      _pulseController.repeat(reverse: true);
    } else {
      if (mounted) {
        setState(() {
          _statusText = '无法启动语音，请手动输入学号';
          _voiceAvailable = false;
          _showManualInput = true;
        });
      }
    }
  }

  /// 中文数字转阿拉伯数字
  static String _chineseToDigits(String text) {
    const chineseDigits = {
      '零': '0', '〇': '0', 'O': '0', 'o': '0',
      '一': '1', '壹': '1',
      '二': '2', '贰': '2', '两': '2',
      '三': '3', '叁': '3',
      '四': '4', '肆': '4',
      '五': '5', '伍': '5',
      '六': '6', '陆': '6',
      '七': '7', '柒': '7',
      '八': '8', '捌': '8',
      '九': '9', '玖': '9',
    };

    var result = text;
    for (final entry in chineseDigits.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  /// 从语音文本中提取学号数字
  static String _extractDigits(String text) {
    // 先转换中文数字
    final converted = _chineseToDigits(text);
    // 提取所有阿拉伯数字
    return converted.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// 尝试从语音中提取数字并登录
  void _tryVoiceLogin(String text) async {
    final digits = _extractDigits(text);
    if (digits.isEmpty) {
      setState(() {
        _statusText = '未识别到学号数字，请重试或手动输入';
        _showManualInput = true;
      });
      return;
    }

    await _doLogin(digits);
  }

  /// 手动输入登录
  void _manualLogin() {
    final text = _manualController.text.trim();
    if (text.isEmpty) return;
    _doLogin(text);
  }

  /// 执行登录
  Future<void> _doLogin(String userId) async {
    setState(() {
      _statusText = '正在登录: $userId ...';
      _isLoggingIn = true;
    });

    try {
      // 使用默认密码（后6位）尝试登录
      final password = userId.length >= 6
          ? userId.substring(userId.length - 6)
          : userId;
      final success = await widget.authService.login(userId, password);

      if (success) {
        widget.onLoginSuccess();
      } else {
        // 尝试用完整学号作为密码
        final success2 = await widget.authService.login(userId, userId);
        if (success2) {
          widget.onLoginSuccess();
        } else {
          if (mounted) {
            setState(() {
              _statusText = '学号 $userId 登录失败，请检查后重试';
              _isLoggingIn = false;
              _showManualInput = true;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = '登录出错: $e';
          _isLoggingIn = false;
          _showManualInput = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.record_voice_over, color: primary),
          const SizedBox(width: 8),
          const Text('语音登录', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _statusText,
              style: TextStyle(
                fontSize: 13,
                color: _statusText.contains('失败') || _statusText.contains('出错')
                    ? Colors.red
                    : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // ── 语音录制按钮 ──
            if (_voiceAvailable) ...[
              GestureDetector(
                onTap: _isLoggingIn
                    ? null
                    : (_isListening
                        ? () => _voiceService.stopListening()
                        : _startListening),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale =
                        _isListening ? 1.0 + _pulseController.value * 0.15 : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isLoggingIn
                              ? Colors.grey
                              : (_isListening ? Colors.red : primary),
                          boxShadow: _isListening
                              ? [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.3),
                                    blurRadius: 20 * _pulseController.value,
                                    spreadRadius: 5 * _pulseController.value,
                                  ),
                                ]
                              : null,
                        ),
                        child: _isLoggingIn
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Icon(
                                _isListening ? Icons.stop : Icons.mic,
                                color: Colors.white,
                                size: 32,
                              ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isListening ? '正在聆听...' : '点击麦克风开始',
                style: TextStyle(
                  fontSize: 11,
                  color: _isListening ? Colors.red : Colors.grey,
                ),
              ),
            ],

            // ── 识别结果 ──
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _recognizedText,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '提取学号: ${_extractDigits(_recognizedText).isEmpty ? "无" : _extractDigits(_recognizedText)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── 手动输入区域 ──
            if (_showManualInput) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '手动输入学号登录',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      decoration: const InputDecoration(
                        hintText: '输入学号/工号',
                        prefixIcon: Icon(Icons.person, size: 20),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _manualLogin(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isLoggingIn ? null : _manualLogin,
                    child: _isLoggingIn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('登录'),
                  ),
                ],
              ),
            ],

            // ── 切换手动输入 ──
            if (!_showManualInput) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _showManualInput = true),
                child: const Text(
                  '手动输入学号',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
