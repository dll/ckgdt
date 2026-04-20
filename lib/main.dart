import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'data/local/database_helper.dart';
import 'services/data_loading_service.dart';
import 'services/theme_manager.dart';
import 'services/settings_service.dart';
import 'presentation/pages/login/login_page.dart';
import 'presentation/pages/feedback/feedback_dialog.dart';
import 'presentation/pages/feedback/ai_help_dialog.dart';
import 'presentation/pages/cross_platform/cross_platform_hub_page.dart';
import 'presentation/widgets/voice_input_button.dart';
import 'presentation/widgets/agent_chat_overlay.dart';
import 'services/voice_service.dart';
import 'services/navigation_service.dart';
import 'services/agent/agent_registry.dart';

// 条件导入：Web 端使用 ffi_web，桌面端使用 ffi
import 'platform/platform_init_stub.dart'
    if (dart.library.io) 'platform/platform_init_native.dart'
    if (dart.library.html) 'platform/platform_init_web.dart'
    as platform_init;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 全局错误处理：捕获 Flutter 框架异常（含原生插件崩溃）────────────────
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('=== FlutterError: ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== PlatformError: $error\n$stack');
    return true; // 已处理，防止应用退出
  };

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

  // 全局 Navigator Key — 用于悬浮按钮获取正确 context
  final _navigatorKey = GlobalKey<NavigatorState>();

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
      navigatorKey: _navigatorKey,
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
                _FloatingHelpFab(navigatorKey: _navigatorKey),
            ],
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
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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

  Future<void> _showVoiceNavigation() async {
    _collapse();
    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;

    // 检查语音配置
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

    if (!navContext.mounted) return;
    final result = await showDialog<String>(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) => const VoiceNavigationDialog(),
    );

    if (result != null && result.isNotEmpty && navContext.mounted) {
      _navigateByVoiceText(navContext, result);
    }
  }

  void _showAgentChat() {
    _collapse();
    final navContext = widget.navigatorKey.currentContext;
    if (navContext != null) {
      AgentChatOverlay.show(navContext);
    }
  }

  /// 根据语音文本进行全局页面导航
  ///
  /// 优先通过 NavigationService 的 Tab 映射快速导航，
  /// 若匹配失败则分发给 AI 智能体进行自然语言理解。
  void _navigateByVoiceText(BuildContext context, String text) {
    final navService = NavigationService.instance;

    // 先 popUntil 回到首页（全局 FAB 可能在任何页面触发）
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);

    // 使用完整的关键词 → Tab 索引映射进行快速导航
    final normalized =
        text.replaceAll(RegExp(r'[，。！？、\s]'), '').toLowerCase();

    // 使用 NavigationService 动态 Tab 映射（角色感知，索引始终正确）
    if (navService.navigateByKeyword(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('语音导航: "$text"'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 检查二级页面导航（通过 Navigator.push）
    final Map<String, String> secondaryPages = {
      '测验': 'quiz', '做题': 'quiz', '答题': 'quiz',
      '视频': 'video', '教程': 'video', '播放': 'video',
      '资料': 'document', '文档': 'document', '课件': 'courseware',
      '进度': 'progress', '统计': 'progress', '成绩': 'progress',
      '计划': 'plan', '学习计划': 'plan', '路径': 'plan',
      '设置': 'settings', '配置': 'settings',
      '错题': 'wrong_answers', '错题本': 'wrong_answers',
      '收藏': 'favorites',
      '搜索': 'search', '查找': 'search',
      '同步': 'sync', '数据同步': 'sync',
      '三端': 'crossplatform', '互通': 'crossplatform', '跨平台': 'crossplatform',
      '通知': 'notification', '消息': 'notification',
      '仓库': 'repo', 'git': 'repo',
    };

    final sortedSecondary = secondaryPages.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in sortedSecondary) {
      if (normalized.contains(entry.key)) {
        // 先切换到首页 tab
        navService.switchToTab(0);
        // 分发给智能体系统执行导航动作
        final registry = AgentRegistry.instance;
        registry.dispatch(text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('语音导航: "$text" → ${entry.key}'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    // 都没匹配 → 分发给 AI 智能体进行自然语言理解
    final registry = AgentRegistry.instance;
    registry.dispatch(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('AI 正在理解: "$text"'),
        duration: const Duration(seconds: 2),
      ),
    );
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

        // 子按钮：三端互通
        _buildPositionedSubButton(
          offset: 168,
          isOnRight: isOnRight,
          size: size,
          icon: Icons.devices,
          label: '三端',
          color: Colors.deepPurple,
          onTap: _showCrossPlatform,
        ),

        // 子按钮：语音导航（最上方）
        _buildPositionedSubButton(
          offset: 224,
          isOnRight: isOnRight,
          size: size,
          icon: Icons.mic,
          label: '语音',
          color: Colors.teal,
          onTap: _showVoiceNavigation,
        ),

        // 子按钮：多智能体助手
        _buildPositionedSubButton(
          offset: 280,
          isOnRight: isOnRight,
          size: size,
          icon: Icons.smart_toy,
          label: '助手',
          color: Colors.indigo,
          onTap: _showAgentChat,
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
