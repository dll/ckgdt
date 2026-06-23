import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/cross_platform/sync_server.dart';
import '../../../services/cross_platform/sync_client.dart';
import '../../../services/cross_platform/sync_protocol.dart';
import '../../../services/cross_platform/session_manager.dart';
import '../../widgets/styled_qr.dart';
import '../cross_platform/qr_scan_page.dart';
import '../privacy/privacy_policy_page.dart';
import '../../widgets/voice_input_button.dart';
import '../home/home_page.dart';

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

  late TabController _tabController;

  // ── 扫码登录相关（桌面/Web 显示 QR 码；手机端扫码） ──────────────────────
  SyncServerImpl? _syncServer;
  bool _isServerStarting = false;
  bool _isServerRunning = false;
  String? _qrData;
  QrSession? _currentQrSession;
  Timer? _qrPollTimer;
  String? _scanStatus;

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
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadQuickLoginSetting();
  }

  Future<void> _loadQuickLoginSetting() async {
    final enabled = await SettingsService.isQuickLoginEnabled();
    if (mounted) setState(() => _quickLoginEnabled = enabled);
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_tabController.indexIsChanging) {
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
              builder: (_) => const HomePage(initialTabIndex: 0)),
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
        final errorMsg = e.toString();
        String userMsg = '登录出错: $e';
        if (errorMsg.contains('locked') ||
            errorMsg.contains('database is locked') ||
            errorMsg.contains('SQLiteException') ||
            errorMsg.contains('singleInstance')) {
          userMsg = '应用已在运行，请勿同时打开多个实例';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _startVoiceLogin() async {
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VoiceNavigationDialog(continuousMode: false),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未识别到学号，请重试或手动输入'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _userIdController.text = digits;
    _passwordController.text = digits.length >= 6
        ? digits.substring(digits.length - 6)
        : digits;
    _login();
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
      'app': 'CKGDT',
    });
    setState(() {
      _qrData = qrJson;
      _currentQrSession = session;
      _scanStatus = '等待手机扫码...';
    });
    _qrPollTimer?.cancel();
    _qrPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentQrSession == null) return;
      final updated = _syncServer!.sessionManager
          .checkQrSession(_currentQrSession!.qrToken);
      if (updated != null && updated.isConfirmed) {
        _qrPollTimer?.cancel();
        _syncServer!.sessionManager.consumeQrSession(updated.qrToken);
      }
      if (updated == null || updated.isExpired) {
        _generateQrCode();
      }
    });
  }

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
              builder: (_) => const HomePage(initialTabIndex: 0)),
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

  Future<void> _processQrDataForLogin(String rawData) async {
    try {
      Map<String, dynamic> data;
      String? serverUrl;
      String? qrToken;
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
        serverUrl = rawData;
      } else {
        _showError('无法识别的扫码内容');
        return;
      }
      setState(() => _scanStatus = '正在连接服务器...');
      final status = await SyncClient.checkServer(serverUrl);
      if (status == null) {
        setState(() => _scanStatus = null);
        _showError('无法连接到服务器 $serverUrl');
        return;
      }
      if (!mounted) return;
      final loginInfo = await _showMobileLoginDialog();
      if (loginInfo == null) {
        setState(() => _scanStatus = null);
        return;
      }
      setState(() => _scanStatus = '正在登录...');
      final userId = loginInfo['userId']!;
      final password = loginInfo['password']!;
      final loginOk = await _authService.login(userId, password);
      if (!loginOk) {
        setState(() => _scanStatus = null);
        _showError('账号或密码错误');
        return;
      }
      final user = _authService.currentUser;
      if (user == null) {
        setState(() => _scanStatus = null);
        return;
      }
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => const HomePage(initialTabIndex: 0)),
      );
    } catch (e) {
      setState(() => _scanStatus = null);
      _showError('扫码登录失败: $e');
    }
  }

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
            Icon(Icons.login),
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
  // UI — 紫蓝渐变登录页
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── 图标 ────────────────────────────────────
                    const Icon(Icons.school, size: 72, color: Colors.white),
                    const SizedBox(height: 12),
                    // ── 标题 ────────────────────────────────────
                    const Text(
                      '移动应用开发\n知识图谱教学系统',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // ── 登录卡片 ────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Material(
                        color: Colors.white,
                        elevation: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Tab bar
                            Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.withValues(alpha: 0.2),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _buildTab(0, '账号密码'),
                                  Container(
                                    width: 1,
                                    height: 28,
                                    color: Colors.grey.withValues(alpha: 0.2),
                                  ),
                                  _buildTab(1, '扫码登录'),
                                ],
                              ),
                            ),
                            // Tab content
                            AnimatedBuilder(
                              animation: _tabController,
                              builder: (context, _) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _tabController.index == 0
                                    ? _buildPasswordTab()
                                    : _buildQrScanTab(),
                              ),
                            ),
                            // Privacy footer
                            _buildPolicyFooter(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ── 快速登录 ────────────────────────────────
                    if (_quickLoginEnabled) _buildQuickLoginRow(),
                    const SizedBox(height: 12),
                    // ── 语音登录 ────────────────────────────────
                    GestureDetector(
                      onTap: _startVoiceLogin,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white24,
                            ),
                            child: const Icon(
                              Icons.record_voice_over,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '语音登录（说出学号）',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── 提示 ────────────────────────────────────
                    const Text(
                      '提示：密码为账号后 6 位',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index, String label) {
    final selected = _tabController.index == index;
    return Expanded(
      child: InkWell(
        onTap: () => _tabController.animateTo(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF667eea)
                      : Colors.grey,
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: selected ? 40 : 0,
                height: 2,
                color: const Color(0xFF667eea),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 账号密码 Tab ──────────────────────────────────────────────
  Widget _buildPasswordTab() {
    return Padding(
      key: const ValueKey('password_tab'),
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: '学号/工号',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '请输入学号/工号' : null,
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
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '请输入密码' : null,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667eea),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('登录', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 扫码登录 Tab ──────────────────────────────────────────────
  Widget _buildQrScanTab() {
    return Padding(
      key: const ValueKey('qr_scan_tab'),
      padding: const EdgeInsets.all(24),
      child: _isMobile ? _buildMobileScanView() : _buildDesktopQrView(),
    );
  }

  Widget _buildDesktopQrView() {
    if (_isServerStarting) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('正在启动扫码服务…',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
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
              Icon(Icons.qr_code_2,
                  size: 56, color: Colors.grey.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              const Text('使用手机 APP 扫描以登录桌面端',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _startQrServer,
                icon: const Icon(Icons.qr_code, size: 16),
                label: const Text('生成二维码'),
              ),
            ],
          ),
        ),
      );
    }
    final success = _scanStatus?.contains('成功') == true;
    return Column(
      children: [
        StyledQr(
          data: _qrData!,
          size: 180,
          padding: 14,
          background: Colors.white,
          borderColor: Colors.grey.withValues(alpha: 0.3),
          eyeColor: const Color(0xFF667eea),
          moduleColor: const Color(0xFF667eea),
          cornerRadius: 4,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              success ? Icons.check_circle : Icons.smartphone,
              size: 14,
              color:
                  success ? Colors.green : const Color(0xFF667eea),
            ),
            const SizedBox(width: 6),
            Text(
              _scanStatus ?? '请使用手机 APP 扫描二维码登录',
              style: TextStyle(
                fontSize: 12,
                color: success ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _generateQrCode,
          icon: const Icon(Icons.refresh, size: 13),
          label: const Text('刷新二维码'),
        ),
      ],
    );
  }

  Widget _buildMobileScanView() {
    return SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF667eea).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.qr_code_scanner,
                size: 40,
                color: Color(0xFF667eea),
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
                        : const Color(0xFF667eea),
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
                label:
                    const Text('打开扫码', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 快速登录按钮 ─────────────────────────────────────────────
  Widget _buildQuickLoginRow() {
    Widget chip(String label, String uid, String pwd) {
      return Expanded(
        child: ElevatedButton(
          onPressed: () => _quickLogin(uid, pwd, label),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF667eea),
          ),
          child: Text(label),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          chip('学生', '2023211985', '211985'),
          const SizedBox(width: 8),
          chip('教师', '206004', '206004'),
          const SizedBox(width: 8),
          chip('管理员', '419116', '9116'),
        ],
      ),
    );
  }

  // ── 隐私协议底部 ─────────────────────────────────────────────
  Widget _buildPolicyFooter() {
    final faded = TextStyle(
      fontSize: 11,
      color: Colors.grey.withValues(alpha: 0.8),
    );
    Widget link(String label, int tab) => InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PrivacyPolicyPage(initialTab: tab)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF667eea),
                  decoration: TextDecoration.underline)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('登录即表示同意 ', style: faded),
          link('《用户协议》', 0),
          Text(' 与 ', style: faded),
          link('《隐私声明》', 1),
        ],
      ),
    );
  }
}
