import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/build_info.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/text_utils.dart';
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
import 'knowledge_graph_backdrop.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _quickLoginEnabled = false;

  // Tab 控制
  late TabController _tabController;

  // ── 视觉动画控制器 ────────────────────────────────────────────────────────
  late final AnimationController _breathController;
  late final AnimationController _entryController;

  // ── 编辑级配色（覆盖底层主题） ────────────────────────────────────────────
  static const Color _ink = Color(0xFF0A0E1A); // 深夜墨蓝
  static const Color _inkDeep = Color(0xFF050811);
  static const Color _accent = Color(0xFFF4B942); // 琥珀
  static const Color _paper = Color(0xFFF7F4EE); // 米白

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

    // 节点呼吸 8s 周期循环
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // 入场 1.2s 一次
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  Future<void> _loadQuickLoginSetting() async {
    final enabled = await SettingsService.isQuickLoginEnabled();
    if (mounted) setState(() => _quickLoginEnabled = enabled);
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
    _breathController.dispose();
    _entryController.dispose();
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
          MaterialPageRoute(builder: (_) => const HomePage(initialTabIndex: 0)),
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

  /// 语音登录 — 显示语音对话框，含失败重试 + 手动输入兜底
  Future<void> _startVoiceLogin() async {
    if (!mounted) return;

    // 循环尝试，直到成功、取消或选择手动输入
    while (mounted) {
      final text = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const VoiceNavigationDialog(continuousMode: false),
      );

      if (text == null || text.trim().isEmpty) {
        if (!mounted) return;
        // 语音识别失败→弹出重试/手动选择
        final action = await _showVoiceRetryDialog();
        if (action == null || action == 'cancel' || !mounted) return;
        if (action == 'manual') {
          // 用户选择手动输入，弹出学号输入框
          final manualId = await _showManualIdDialog();
          if (manualId == null || manualId.isEmpty || !mounted) return;
          _userIdController.text = manualId;
          _passwordController.text = manualId.length >= 6
              ? manualId.substring(manualId.length - 6)
              : manualId;
          _login();
          return;
        }
        // 'retry' → 继续循环，重新语音识别
        continue;
      }

      // 提取学号数字
      final digits = extractDigits(text);
      if (digits.isEmpty) {
        final action = await _showVoiceRetryDialog();
        if (action == null || action == 'cancel' || !mounted) return;
        if (action == 'manual') {
          final manualId = await _showManualIdDialog();
          if (manualId == null || manualId.isEmpty || !mounted) return;
          _userIdController.text = manualId;
          _passwordController.text = manualId.length >= 6
              ? manualId.substring(manualId.length - 6)
              : manualId;
          _login();
          return;
        }
        continue;
      }

      // 自动填充表单并登录
      _userIdController.text = digits;
      _passwordController.text =
          digits.length >= 6 ? digits.substring(digits.length - 6) : digits;
      _login();
      return;
    }
  }

  /// 语音识别失败后弹出重试/手动选择对话框
  Future<String?> _showVoiceRetryDialog() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _paper,
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: _accent, size: 20),
            SizedBox(width: 8),
            Text('语音未识别',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
          ],
        ),
        content: const Text('未识别到学号，请选择操作：',
            style: TextStyle(color: _ink, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text('取消',
                style: TextStyle(color: _ink.withValues(alpha: 0.6))),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'retry'),
            child: const Text('重试', style: TextStyle(color: _ink)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'manual'),
            style: FilledButton.styleFrom(backgroundColor: _ink),
            child: const Text('手动输入', style: TextStyle(color: _paper)),
          ),
        ],
      ),
    );
  }

  /// 手动输入学号对话框（语音失败兜底）
  Future<String?> _showManualIdDialog() async {
    if (!mounted) return null;
    final idCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _paper,
        title: const Row(
          children: [
            Icon(Icons.person, color: _accent, size: 20),
            SizedBox(width: 8),
            Text('手动输入学号',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('语音识别失败，请手动输入学号/工号：',
                style: TextStyle(color: _ink, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: idCtrl,
              autofocus: true,
              style:
                  const TextStyle(color: _ink, fontSize: 16, letterSpacing: 2),
              decoration: InputDecoration(
                hintText: '输入学号/工号',
                hintStyle: TextStyle(color: _ink.withValues(alpha: 0.3)),
                prefixIcon:
                    Icon(Icons.badge, color: _ink.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: _ink.withValues(alpha: 0.25))),
                focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _ink, width: 1.5)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: _ink.withValues(alpha: 0.6))),
          ),
          FilledButton(
            onPressed: () {
              final v = idCtrl.text.trim();
              if (v.isNotEmpty) {
                Navigator.pop(ctx, v);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: _ink),
            child: const Text('确认', style: TextStyle(color: _paper)),
          ),
        ],
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
          MaterialPageRoute(builder: (_) => const HomePage(initialTabIndex: 0)),
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
        MaterialPageRoute(builder: (_) => const HomePage(initialTabIndex: 0)),
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
            Icon(Icons.login, color: _accent),
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
                validator: (v) => (v == null || v.isEmpty) ? '请输入学号/工号' : null,
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
                validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
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
  // UI — Editorial Tech-Noir × Knowledge Cartography
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final accentLine = AppGradientTheme.of(context).gradientStart;
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 880;

    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 第 1 层：径向墨色（顶亮底深） ────────────────────────
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.4, -0.6),
                radius: 1.4,
                colors: [_ink, _inkDeep],
                stops: [0.0, 0.85],
              ),
            ),
          ),

          // ── 第 2 层：知识图谱节点-边背景 ─────────────────────────
          Positioned.fill(
            child: KnowledgeGraphBackdrop(
              breath: _breathController,
              lineColor: accentLine,
              nodeColor: _paper,
              accentColor: _accent,
            ),
          ),

          // ── 第 3 层：暗角 vignette ───────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      _inkDeep.withValues(alpha: 0.55),
                    ],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── 第 4 层：内容 ────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: media.size.height -
                      media.padding.top -
                      media.padding.bottom,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 64 : 22,
                    vertical: isWide ? 40 : 28,
                  ),
                  child: isWide
                      ? _buildWideLayout(accentLine)
                      : _buildNarrowLayout(accentLine),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 桌面/Web 宽屏：左叙事 + 右卡片 ───────────────────────────
  Widget _buildWideLayout(Color accent) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 6, child: _buildBranding(accent, wide: true)),
            const SizedBox(width: 56),
            Expanded(flex: 5, child: _buildLoginCard(accent)),
          ],
        ),
      ),
    );
  }

  // ── 手机/窄屏：上叙事 + 下卡片 ───────────────────────────────
  Widget _buildNarrowLayout(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBranding(accent, wide: false),
        const SizedBox(height: 28),
        _buildLoginCard(accent),
        const SizedBox(height: 24),
        _buildSecondaryActions(),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  品牌叙事区
  // ─────────────────────────────────────────────────────────────
  Widget _buildBranding(Color accent, {required bool wide}) {
    final entry = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    Widget animated(Widget child, {double startOffset = 24, double delay = 0}) {
      return AnimatedBuilder(
        animation: entry,
        builder: (_, __) {
          final raw = (entry.value - delay).clamp(0.0, 1.0) / (1.0 - delay);
          final eased = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
          return Opacity(
            opacity: eased,
            child: Transform.translate(
              offset: Offset(0, startOffset * (1 - eased)),
              child: child,
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        animated(
          Row(
            mainAxisAlignment:
                wide ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Container(width: 28, height: 1, color: _accent),
              const SizedBox(width: 10),
              const Text(
                BuildInfo.appVersionLine,
                style: TextStyle(
                  color: _accent,
                  fontSize: 11,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          delay: 0.0,
        ),
        const SizedBox(height: 22),
        animated(
          Text(
            wide ? '知识图谱\n与数字孪生' : '知识图谱 · 数字孪生',
            textAlign: wide ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              color: _paper,
              fontSize: wide ? 56 : 34,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: wide ? -0.5 : 0,
            ),
          ),
          delay: 0.08,
        ),
        const SizedBox(height: 18),
        animated(
          SizedBox(
            width: wide ? 200 : 140,
            child: Column(
              crossAxisAlignment:
                  wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Container(
                    width: double.infinity,
                    height: 1,
                    color: _paper.withValues(alpha: 0.35)),
                const SizedBox(height: 3),
                Container(
                    width: double.infinity,
                    height: 1,
                    color: _paper.withValues(alpha: 0.15)),
              ],
            ),
          ),
          delay: 0.18,
        ),
        const SizedBox(height: 18),
        animated(
          Text(
            'Knowledge Graph & Digital Twin Platform\nfor Course Teaching and Learning',
            textAlign: wide ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              color: _paper.withValues(alpha: 0.62),
              fontSize: 12,
              letterSpacing: 2.2,
              height: 1.7,
              fontWeight: FontWeight.w400,
            ),
          ),
          delay: 0.26,
        ),
        const SizedBox(height: 28),
        if (wide)
          animated(
            Row(
              children: [
                _buildPillar('01', '多课', '课程图谱体系'),
                const SizedBox(width: 28),
                _buildPillar('02', '24', '协作智能体'),
                const SizedBox(width: 28),
                _buildPillar('03', '∞', '师生数字孪生'),
              ],
            ),
            delay: 0.34,
          ),
      ],
    );
  }

  Widget _buildPillar(String num, String n, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          num,
          style: const TextStyle(
            color: _accent,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Container(width: 24, height: 1, color: _paper.withValues(alpha: 0.4)),
        const SizedBox(height: 8),
        Text(
          n,
          style: const TextStyle(
            color: _paper,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: _paper.withValues(alpha: 0.55),
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  登录卡片（玻璃/纸感）
  // ─────────────────────────────────────────────────────────────
  Widget _buildLoginCard(Color accent) {
    final entry = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: entry,
      builder: (_, child) => Opacity(
        opacity: entry.value,
        child: Transform.translate(
          offset: Offset(0, 32 * (1 - entry.value)),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: _paper.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: _ink.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _inkDeep.withValues(alpha: 0.55),
                    blurRadius: 50,
                    offset: const Offset(0, 24),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCardHeader(accent),
                  _buildEditorialTabs(accent),
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(a),
                          child: c,
                        ),
                      ),
                      child: _tabController.index == 0
                          ? _buildPasswordTab()
                          : _buildQrScanTab(),
                    ),
                  ),
                  _buildPolicyFooter(accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 登录卡底部协议链接 — 满足"用户使用前可阅读用户协议 / 隐私声明"的合规要求
  Widget _buildPolicyFooter(Color accent) {
    final faded = TextStyle(fontSize: 11, color: _ink.withValues(alpha: 0.6));
    Widget link(String label, int tab) => InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PrivacyPolicyPage(initialTab: tab)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: accent,
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

  Widget _buildCardHeader(Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _ink,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Center(
              child: Text(
                'M',
                style: TextStyle(
                  color: _accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MAD-KGDT',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  '请验证身份以继续',
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.55),
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${DateTime.now().year}',
            style: TextStyle(
              color: _ink.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorialTabs(Color accent) {
    Widget tab(int idx, String num, String label) {
      final selected = _tabController.index == idx;
      return Expanded(
        child: InkWell(
          onTap: () {
            _tabController.animateTo(idx);
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      num,
                      style: TextStyle(
                        color:
                            selected ? _accent : _ink.withValues(alpha: 0.35),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? _ink : _ink.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  width: selected ? 36 : 0,
                  height: 1.5,
                  color: _ink,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _ink.withValues(alpha: 0.08)),
          bottom: BorderSide(color: _ink.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          tab(0, '01', '账号'),
          Container(width: 1, height: 26, color: _ink.withValues(alpha: 0.08)),
          tab(1, '02', '扫码'),
        ],
      ),
    );
  }

  /// Tab1：账号密码登录表单
  Widget _buildPasswordTab() {
    return Padding(
      key: const ValueKey('password_tab'),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _editorialField(
              controller: _userIdController,
              label: '学号 / 工号',
              hint: 'e.g. 2023210001',
              validator: (v) => (v == null || v.isEmpty) ? '请输入学号 / 工号' : null,
              suffix: VoiceInputButton(
                controller: _userIdController,
                tooltip: '语音输入学号',
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            _editorialField(
              controller: _passwordController,
              label: '密  码',
              hint: '账号后 6 位',
              obscure: _obscurePassword,
              validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
              suffix: IconButton(
                visualDensity: VisualDensity.compact,
                splashRadius: 18,
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: _ink.withValues(alpha: 0.5),
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: Material(
                color: _isLoading ? _ink.withValues(alpha: 0.6) : _ink,
                borderRadius: BorderRadius.circular(2),
                child: InkWell(
                  onTap: _isLoading ? null : _login,
                  borderRadius: BorderRadius.circular(2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isLoading ? '正在验证…' : '进 入 系 统',
                          style: const TextStyle(
                            color: _paper,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                          ),
                        ),
                        _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _accent,
                                ),
                              )
                            : Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: const Icon(Icons.arrow_forward,
                                    size: 14, color: _ink),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_quickLoginEnabled) _buildQuickLoginRow(),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '密码默认 = 账号后 6 位',
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.5),
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
                GestureDetector(
                  onTap: _startVoiceLogin,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.graphic_eq,
                          size: 13, color: _ink.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        '语音登录',
                        style: TextStyle(
                          color: _ink.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorialField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              color: _ink.withValues(alpha: 0.55),
              fontSize: 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: _ink.withValues(alpha: 0.3),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: _ink.withValues(alpha: 0.25)),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _ink.withValues(alpha: 0.25)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _ink, width: 1.5),
            ),
            errorStyle: const TextStyle(fontSize: 11, height: 1.2),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickLoginRow() {
    Widget chip(String label, String uid, String pwd) {
      return Expanded(
        child: InkWell(
          onTap: () => _quickLogin(uid, pwd, label),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: _ink.withValues(alpha: 0.15)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        children: [
          chip('学  生', '2023211985', '211985'),
          const SizedBox(width: 8),
          chip('教  师', '206004', '206004'),
          const SizedBox(width: 8),
          chip('管理员', '419116', '9116'),
        ],
      ),
    );
  }

  Widget _buildSecondaryActions() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 1,
          color: _paper.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 18),
        Text(
          'CALMNESS · CRAFT · CONNECTION',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _paper.withValues(alpha: 0.4),
            fontSize: 9,
            letterSpacing: 4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
    if (_isServerStarting) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _ink.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text('正在启动扫码服务…',
                  style: TextStyle(
                      color: _ink.withValues(alpha: 0.6),
                      fontSize: 12,
                      letterSpacing: 1.5)),
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
                  size: 56, color: _ink.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text('使用手机 APP 扫描以登录桌面端',
                  style: TextStyle(
                      color: _ink.withValues(alpha: 0.55),
                      fontSize: 12,
                      letterSpacing: 1)),
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: Material(
                  color: _ink,
                  borderRadius: BorderRadius.circular(2),
                  child: InkWell(
                    onTap: _startQrServer,
                    borderRadius: BorderRadius.circular(2),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code, size: 14, color: _accent),
                          SizedBox(width: 8),
                          Text('生 成 二 维 码',
                              style: TextStyle(
                                  color: _paper,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // QR 码显示
    final success = _scanStatus?.contains('成功') == true;
    return Column(
      children: [
        StyledQr(
          data: _qrData!,
          size: 180,
          padding: 14,
          background: _paper,
          borderColor: _ink.withValues(alpha: 0.15),
          eyeColor: _ink,
          moduleColor: _ink,
          cornerRadius: 2,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              success ? Icons.check_circle : Icons.smartphone,
              size: 14,
              color: success ? const Color(0xFF2E7D32) : _accent,
            ),
            const SizedBox(width: 6),
            Text(
              _scanStatus ?? '请使用手机 APP 扫描二维码登录',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1,
                color: success
                    ? const Color(0xFF2E7D32)
                    : _ink.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _generateQrCode,
          icon:
              Icon(Icons.refresh, size: 13, color: _ink.withValues(alpha: 0.6)),
          label: Text('刷新二维码',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: _ink.withValues(alpha: 0.6))),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
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
