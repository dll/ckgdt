import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'data/local/database_helper.dart';
import 'services/data_loading_service.dart';
import 'services/theme_manager.dart';
import 'services/settings_service.dart';
import 'presentation/pages/login/login_page.dart';

// 条件导入：Web 端使用 ffi_web，桌面端使用 ffi
import 'platform/platform_init_stub.dart'
    if (dart.library.io) 'platform/platform_init_native.dart'
    if (dart.library.html) 'platform/platform_init_web.dart'
    as platform_init;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  int _colorIndex = 0;

  @override
  void initState() {
    super.initState();
    MyApp._state = this;
    _loadTheme();
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '移动应用开发知识图谱',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeManager.light(_colorIndex),
      darkTheme: ThemeManager.dark(_colorIndex),
      home: const LoginPage(),
    );
  }
}
