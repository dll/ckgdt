import 'package:flutter/material.dart';

/// 全局导航服务 — 跨页面 Tab 切换 + 页面跳转
///
/// 单例模式，由 HomePage 注册回调，供智能体等模块触发导航。
class NavigationService {
  static final NavigationService instance = NavigationService._();
  NavigationService._();

  /// HomePage 注册的 Tab 切换回调
  void Function(int tabIndex)? onSwitchTab;

  /// 全局 NavigatorState key（由 main.dart 提供）
  GlobalKey<NavigatorState>? navigatorKey;

  /// 关键词 → Tab 索引映射（角色感知）
  /// 由 HomePage 在 build 时动态注册
  Map<String, int> _tabMapping = {};

  /// 注册 Tab 映射
  void registerTabMapping(Map<String, int> mapping) {
    _tabMapping = mapping;
  }

  /// 切换到指定 Tab
  void switchToTab(int index) {
    onSwitchTab?.call(index);
  }

  /// 根据关键词导航到对应 Tab
  /// 返回 true 表示成功匹配并导航
  bool navigateByKeyword(String keyword) {
    final normalized = keyword.toLowerCase();

    // 先在 Tab 映射中查找
    for (final entry in _tabMapping.entries) {
      if (normalized.contains(entry.key)) {
        switchToTab(entry.value);
        return true;
      }
    }

    // 通用关键词映射（不依赖角色的固定映射）
    final generalMap = <String, int>{
      '首页': 0, '主页': 0, '回家': 0,
      '图谱': 1, '知识图谱': 1,
    };

    for (final entry in generalMap.entries) {
      if (normalized.contains(entry.key)) {
        switchToTab(entry.value);
        return true;
      }
    }

    return false;
  }

  /// 推送新页面
  Future<T?> pushPage<T>(Widget page) async {
    final nav = navigatorKey?.currentState;
    if (nav == null) return null;
    return nav.push<T>(MaterialPageRoute(builder: (_) => page));
  }

  /// 返回到根路由（首页）
  void popToRoot() {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
  }

  /// 导航到登录页（退出登录后）
  void navigateToLogin(Widget loginPage) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => loginPage),
      (route) => false,
    );
  }

  /// 清理回调（HomePage dispose 时调用）
  void dispose() {
    onSwitchTab = null;
    _tabMapping = {};
  }
}
