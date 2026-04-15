import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'data/local/database_helper.dart';
import 'services/data_loading_service.dart';
import 'services/theme_manager.dart';
import 'services/settings_service.dart';
import 'presentation/pages/login/login_page.dart';
import 'presentation/pages/feedback/feedback_dialog.dart';

// 条件导入：Web 端使用 ffi_web，桌面端使用 ffi
import 'platform/platform_init_stub.dart'
    if (dart.library.io) 'platform/platform_init_native.dart'
    if (dart.library.html) 'platform/platform_init_web.dart'
    as platform_init;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // MediaKit 仅在桌面端初始化（Android 无原生库，走系统播放器）
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      MediaKit.ensureInitialized();
    }
  } catch (e) {
    debugPrint('=== main: MediaKit init skipped: $e');
  }

  // 平台相关初始化（数据库工厂、屏幕方向等）
  await platform_init.initPlatform();

  // Initialize database first
  try {
    await DatabaseHelper.instance.database;
  } catch (e) {
    debugPrint('=== main: Database init error: $e');
  }

  // Initialize all preset data (resources, PUML samples, clean empty graphs)
  try {
    await DataLoadingService.instance.initialize();
  } catch (e) {
    debugPrint('=== main: DataLoadingService init error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  /// 供 SettingsPage 调用，主题修改后立即刷新整个应用
  static _MyAppState? _state;
  static void refreshTheme() => _state?._loadTheme();

  /// 供外部通知反馈开关变更
  static void refreshFeedback() => _state?._loadFeedbackSetting();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  int _colorIndex = 0;
  bool _feedbackEnabled = true;

  @override
  void initState() {
    super.initState();
    MyApp._state = this;
    _loadTheme();
    _loadFeedbackSetting();
  }

  @override
  void dispose() {
    if (MyApp._state == this) MyApp._state = null;
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final mode = await SettingsService.getThemeMode();
    final index = await SettingsService.getColorIndex();
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _colorIndex = index;
      });
    }
  }

  Future<void> _loadFeedbackSetting() async {
    final enabled = await SettingsService.isFeedbackEnabled();
    if (mounted) setState(() => _feedbackEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MADKG',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeManager.light(_colorIndex),
      darkTheme: ThemeManager.dark(_colorIndex),
      home: const LoginPage(),
      builder: (context, child) {
        // 用 RepaintBoundary 包裹，供截图用
        // 用 Stack + Positioned 添加全局反馈浮动按钮
        return RepaintBoundary(
          key: feedbackScreenshotKey,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (_feedbackEnabled)
                const _FeedbackFab(),
            ],
          ),
        );
      },
    );
  }
}

/// 全局悬浮反馈按钮
class _FeedbackFab extends StatefulWidget {
  const _FeedbackFab();

  @override
  State<_FeedbackFab> createState() => _FeedbackFabState();
}

class _FeedbackFabState extends State<_FeedbackFab> {
  // 按钮位置（默认右下角）
  double _dx = -1;
  double _dy = -1;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 初始位置：右下角（距底部 120, 距右 16）
    if (_dx < 0) _dx = size.width - 60;
    if (_dy < 0) _dy = size.height - 160;

    // 确保不超出屏幕
    _dx = _dx.clamp(0, size.width - 48);
    _dy = _dy.clamp(40, size.height - 80);

    return Positioned(
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
        onTap: () {
          FeedbackDialog.show(context);
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _dragging ? 1.0 : 0.7,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.feedback_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
