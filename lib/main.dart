import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/local/database_helper.dart';
import 'services/theme_manager.dart';
import 'services/settings_service.dart';
import 'presentation/pages/login/login_page.dart';
import 'services/theme_manager.dart';
import 'services/settings_service.dart';
import 'presentation/pages/login/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Initialize database first
  await DatabaseHelper.instance.database;
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final isDark = await SettingsService.isDarkMode();
    setState(() => _isDarkMode = isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '移动应用开发知识图谱',
      debugShowCheckedModeBanner: false,
      theme: _isDarkMode ? ThemeManager.darkTheme : ThemeManager.lightTheme,
      home: LoginPage(),
    );
  }
}
