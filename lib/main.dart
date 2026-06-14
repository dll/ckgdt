import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'core/app_keys.dart';
import 'core/build_info.dart';
import 'core/dev_paths.dart';
import 'core/init_logger.dart';
import 'presentation/pages/assessment/defense/defense_broadcast_page.dart';
import 'data/local/database_helper.dart';
import 'services/data_loading_service.dart';
import 'services/theme_manager.dart';
import 'services/settings_service.dart';
import 'presentation/pages/login/login_page.dart';
import 'presentation/pages/feedback/feedback_dialog.dart';
import 'presentation/pages/feedback/ai_help_dialog.dart';
import 'presentation/pages/cross_platform/cross_platform_hub_page.dart';
import 'presentation/widgets/agent_chat_overlay.dart';
import 'services/voice_service.dart';
import 'services/voice_assistant_controller.dart';
import 'services/tts_flutter_service.dart';
import 'services/archive/processor_registry.dart';
import 'services/archive/base_document_processor.dart';
import 'services/archive_package_service.dart';
import 'services/auth_service.dart';
import 'services/update_service.dart';
import 'services/notification_service.dart';
import 'presentation/pages/profile/virtual_twin_page.dart';

// 条件导入：Web 端使用 ffi_web，桌面端使用 ffi
import 'platform/platform_init_stub.dart'
    if (dart.library.io) 'platform/platform_init_native.dart'
    if (dart.library.html) 'platform/platform_init_web.dart'
    as platform_init;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动期文件日志器（必须最先初始化 — 后续每个 catch 都会写到日志）
  await InitLogger.init();
  InitLogger.log('main', 'app starting');

  bool dbLocked = false;
  String? dbError;

  // ── 全局错误处理：捕获 Flutter 框架异常（含原生插件崩溃）────────────────
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    InitLogger.error('flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    InitLogger.error('platform', error, stack);
    return true; // 已处理，防止应用退出
  };

  // MediaKit 仅在桌面端初始化（Android 无原生库，走系统播放器）
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      MediaKit.ensureInitialized();
    }
  } catch (e, st) {
    InitLogger.error('main', 'MediaKit init skipped: $e', st);
  }

  // 平台相关初始化（数据库工厂、屏幕方向等）
  await platform_init.initPlatform();

  // Initialize database first
  try {
    await DatabaseHelper.instance.database;
  } catch (e, st) {
    InitLogger.error('main', 'Database init error: $e', st);
    final err = e.toString();
    // 只有数据库 lock 类异常才阻塞启动；种子数据问题让应用继续起来，
    // UI 通过 DatabaseHelper.lastInitError 提示用户去看日志，而不是白屏。
    if (err.contains('locked') ||
        err.contains('database is locked') ||
        err.contains('singleInstance')) {
      dbLocked = true;
      dbError = '应用已在运行，请勿同时打开多个实例';
    } else {
      DatabaseHelper.lastInitError = 'db-init-throw: $e';
    }
  }

  // Initialize all preset data (resources, PUML samples, clean empty graphs)
  try {
    if (!dbLocked) {
      await DataLoadingService.instance.initialize();
    }
  } catch (e, st) {
    InitLogger.error('main', 'DataLoadingService init error: $e', st);
  }

  if (DatabaseHelper.lastInitError != null) {
    InitLogger.log(
        'main', 'startup with init error = ${DatabaseHelper.lastInitError}');
  }
  InitLogger.log('main', 'runApp');

  // 预初始化 TTS — 不阻塞冷启动；首次 speak 时不再有 init 延迟
  unawaited(TtsFlutterService.instance.initialize());

  // 注册归档文档处理器
  ProcessorRegistry.instance.registerAll();
  // 注入归档模板 / 输出根目录（reference-doc 自动发现 + 打包输出）。
  // 用 unawaited 避开冷启动关键路径——首次需要这两条路径的代码（打开归档页）
  // 不会先于 main 完成。
  unawaited(_initArchivePaths());
  unawaited(_checkAppUpdate());

  runApp(MyApp(dbLocked: dbLocked, dbError: dbError));
}

/// 后台检查应用更新 — 每日一次，发现新版本时通知所有用户
Future<void> _checkAppUpdate() async {
  try {
    final hasUpdate = await UpdateService().backgroundCheck();
    if (hasUpdate) {
      final info = await UpdateService().checkForUpdate();
      if (info != null) {
        await NotificationService().notifyAppUpdate(
          newVersion: info.version,
          releaseNotes: info.releaseNotes,
        );
        InitLogger.log('update', '发现新版本 v${info.version}，已发送通知');
      }
    }
  } catch (e, st) {
    InitLogger.error('update', e, st);
  }
}

/// 注入归档相关绝对路径。仅 Windows / macOS / Linux 桌面端有意义。
///
/// - `data/归档/` 用于 reference-doc 模板查找（学校原版样式继承）
/// - `archive_out/` 用于一键归档的输出根目录（按 学期/课程/期 分目录）
Future<void> _initArchivePaths() async {
  if (kIsWeb) return;
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
  try {
    final root = DevPaths.projectRoot;
    final templates = p.join(root, 'data', '归档');
    final outDir = p.join(root, 'archive_out');
    BaseDocumentProcessor.archiveDataRoot = templates;
    ArchivePackageService.outputRoot = outDir;
    InitLogger.log('archive', 'templates=$templates outDir=$outDir');
  } catch (e, st) {
    InitLogger.error('archive', e, st);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.dbLocked = false, this.dbError});

  final bool dbLocked;
  final String? dbError;

  /// 供 SettingsPage 调用，主题修改后立即刷新整个应用
  static _MyAppState? _state;
  static void refreshTheme() => _state?._loadTheme();

  /// 供外部通知反馈开关变更
  static void refreshFeedback() => _state?._loadFeedbackSetting();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  int _colorIndex = 0;
  bool _feedbackEnabled = true;
  Locale? _locale; // null = follow system

  // 全局 Navigator Key — 用于悬浮按钮获取正确 context
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    MyApp._state = this;
    _loadTheme();
    _loadFeedbackSetting();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DefenseBroadcastPage.screenCaptureKey = broadcastCaptureKey;
    });
  }

  @override
  void dispose() {
    if (MyApp._state == this) MyApp._state = null;
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final mode = await SettingsService.getThemeMode();
    final index = await SettingsService.getColorIndex();
    final locale = await SettingsService.getLocale();
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _colorIndex = index;
        _locale = locale;
      });
    }
  }

  Future<void> _loadFeedbackSetting() async {
    final enabled = await SettingsService.isFeedbackEnabled();
    if (mounted) setState(() => _feedbackEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    // 如果数据库被锁定，显示错误页面
    if (widget.dbLocked) {
      return MaterialApp(
        title: BuildInfo.appBrandWithVersion,
        debugShowCheckedModeBanner: false,
        theme: ThemeManager.light(_colorIndex),
        darkTheme: ThemeManager.dark(_colorIndex),
        themeMode: _themeMode,
        home: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1677FF),
                  Color(0xFF0958D9).withValues(alpha: 0.9),
                ],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber, size: 80, color: Colors.white),
                    const SizedBox(height: 24),
                    const Text(
                      '应用已在运行',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.dbError ?? '请勿同时打开多个实例',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.close),
                      label: const Text('请关闭其他实例'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1677FF),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
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

    return MaterialApp(
      title: BuildInfo.appBrandWithVersion,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeManager.light(_colorIndex),
      darkTheme: ThemeManager.dark(_colorIndex),
      navigatorKey: _navigatorKey,
      locale: _locale,
      supportedLocales: const [Locale("zh"), Locale("en")],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LoginPage(),
      builder: (context, child) {
        // 用 RepaintBoundary 包裹，供截图用
        // 用 Stack + Positioned 添加全局反馈浮动按钮
        return RepaintBoundary(
          key: broadcastCaptureKey,
          child: RepaintBoundary(
            key: feedbackScreenshotKey,
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                if (_feedbackEnabled)
                  _FloatingHelpFab(navigatorKey: _navigatorKey),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 全局悬浮帮助/反馈按钮 — 展开后显示"帮助"和"反馈"两个子按钮
class _FloatingHelpFab extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const _FloatingHelpFab({required this.navigatorKey});

  @override
  State<_FloatingHelpFab> createState() => _FloatingHelpFabState();
}

class _FloatingHelpFabState extends State<_FloatingHelpFab>
    with SingleTickerProviderStateMixin {
  // 按钮位置（默认右下角）
  double _dx = -1;
  double _dy = -1;
  bool _dragging = false;
  bool _expanded = false;

  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  bool _voiceActive = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _voiceActive = VoiceAssistantController.instance.isListening.value;
    VoiceAssistantController.instance.isListening.addListener(_onVoiceChanged);
  }

  @override
  void dispose() {
    VoiceAssistantController.instance.isListening.removeListener(_onVoiceChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() => _voiceActive = VoiceAssistantController.instance.isListening.value);
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  void _collapse() {
    if (_expanded) {
      setState(() => _expanded = false);
      _animController.reverse();
    }
  }

  /// 使用 navigatorKey 获取正确的 BuildContext 来弹出对话框
  void _showHelp() {
    _collapse();
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) {
      AiHelpDialog.show(navContext);
    }
  }

  void _showFeedback() {
    _collapse();
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) {
      FeedbackDialog.show(navContext);
    }
  }

  void _showCrossPlatform() {
    _collapse();
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) {
      Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const CrossPlatformHubPage()),
      );
    }
  }

  Future<void> _toggleVoice() async {
    _collapse();
    final ctrl = VoiceAssistantController.instance;

    if (_voiceActive) {
      await ctrl.stopLoop();
      return;
    }

    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;

    final configured = await VoiceService.isConfigured();
    if (!configured) {
      if (navContext.mounted) {
        ScaffoldMessenger.of(navContext).showSnackBar(
          const SnackBar(
            content: Text('请先在系统设置中配置讯飞语音参数'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    await ctrl.startLoop();
  }

  void _showAgentChat() {
    _collapse();
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) {
      AgentChatOverlay.show(navContext);
    }
  }

  bool get _isTeacher {
    final auth = AuthService();
    return auth.isTeacher || auth.isAdmin;
  }

  void _showVirtualTwin() {
    _collapse();
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) {
      Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const VirtualTwinPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final primary = Theme.of(context).colorScheme.primary;

    // 初始位置：右下角
    if (_dx < 0) _dx = size.width - 60;
    if (_dy < 0) _dy = size.height - 160;

    // 确保不超出屏幕
    _dx = _dx.clamp(0.0, size.width - 48);
    _dy = _dy.clamp(40.0, size.height - 80);

    // 判断 FAB 在左侧还是右侧
    final bool isOnRight = _dx + 24 > size.width / 2;

    return Stack(
      children: [
        // 展开时的半透明遮罩（点击关闭）
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _collapse,
              child: Container(color: Colors.transparent),
            ),
          ),

        // 子按钮：帮助（上方）
        _buildPositionedSubButton(
          offset: 56,
          isOnRight: isOnRight,
          size: size,
          icon: Icons.support_agent,
          label: '帮助',
          color: Colors.blue,
          onTap: _showHelp,
        ),

        // 子按钮：反馈
        _buildPositionedSubButton(
          offset: 112,
          isOnRight: isOnRight,
          size: size,
          icon: Icons.feedback_outlined,
          label: '反馈',
          color: Colors.orange,
          onTap: _showFeedback,
        ),

        // 子按钮：多端互通
        _buildPositionedSubButton(
          offset: 168,
          isOnRight: isOnRight,
          size: size,
          icon: Icons.devices,
          label: '多端',
          color: Colors.deepPurple,
          onTap: _showCrossPlatform,
        ),

        // 子按钮：语音（上）— 点击开启/关闭常驻聆听
        _buildPositionedSubButton(
          offset: 224,
          isOnRight: isOnRight,
          size: size,
          icon: _voiceActive ? Icons.mic_off : Icons.mic,
          label: _voiceActive ? '关闭' : '语音',
          color: _voiceActive ? Colors.red : Colors.teal,
          onTap: _toggleVoice,
        ),

        // 子按钮：多智能体助手
        _buildPositionedSubButton(
          offset: 280,
          isOnRight: isOnRight,
          size: size,
          icon: Icons.chat_bubble_outline,
          label: '助手',
          color: Colors.indigo,
          onTap: _showAgentChat,
        ),

        // 子按钮：数字孪生
        _buildPositionedSubButton(
          offset: 336,
          isOnRight: isOnRight,
          size: size,
          icon: _isTeacher ? Icons.school : Icons.face,
          label: '美德',
          color: _isTeacher ? Colors.indigo : Colors.cyan,
          onTap: _showVirtualTwin,
        ),

        // 主按钮
        Positioned(
          left: _dx,
          top: _dy,
          child: GestureDetector(
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (details) {
              setState(() {
                _dx += details.delta.dx;
                _dy += details.delta.dy;
              });
            },
            onPanEnd: (_) {
              setState(() {
                _dragging = false;
                // 自动吸附到最近的边缘
                if (_dx + 24 < size.width / 2) {
                  _dx = 4;
                } else {
                  _dx = size.width - 52;
                }
              });
            },
            onTap: _toggle,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _dragging ? 1.0 : 0.75,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _expanded
                      ? const Icon(Icons.close, color: Colors.white,
                          size: 22, key: ValueKey('close'))
                      : const Icon(Icons.headset_mic, color: Colors.white,
                          size: 22, key: ValueKey('open')),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建带定位的子按钮（根据 FAB 位置自动调整布局方向）
  Widget _buildPositionedSubButton({
    required double offset,
    required bool isOnRight,
    required Size size,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        // 让圆形图标与主按钮对齐（主按钮48px，子按钮圆40px，居中偏移4px）
        final double iconLeft = _dx + 4;
        final double iconRight = size.width - _dx - 48 + 4;

        return Positioned(
          // 在右侧时用 right 定位，左侧时用 left 定位
          left: isOnRight ? null : iconLeft,
          right: isOnRight ? iconRight : null,
          top: _dy - offset * _expandAnimation.value,
          child: Opacity(
            opacity: _expandAnimation.value,
            child: _buildSubButton(
              icon: icon,
              label: label,
              color: color,
              onTap: onTap,
              labelOnLeft: isOnRight, // 右侧时标签在左，左侧时标签在右
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool labelOnLeft = true,
  }) {
    final labelWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color)),
    );

    final iconWidget = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: labelOnLeft
            ? [labelWidget, const SizedBox(width: 6), iconWidget]
            : [iconWidget, const SizedBox(width: 6), labelWidget],
      ),
    );
  }
}
