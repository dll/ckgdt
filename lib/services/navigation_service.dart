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

    // 先在动态 Tab 映射中精确查找（角色感知）
    for (final entry in _tabMapping.entries) {
      if (normalized.contains(entry.key)) {
        switchToTab(entry.value);
        return true;
      }
    }

    // 别名 → 标准 Tab 名映射（解析后查动态映射）
    const aliasMap = <String, String>{
      '首页': '首页', '主页': '首页', '回家': '首页',
      '知识图谱': '图谱',
      '学习中心': '学习',
      '课堂管理': '课堂',
      '实验任务': '实验',
      '考核管理': '考核', '考试': '考核',
      '作品展评': '作品',
      '成就': '达成', '达成度': '达成',
      '管理面板': '管理',
    };

    // 按别名长度降序匹配（优先匹配更精确的词）
    final sortedAliases = aliasMap.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final alias in sortedAliases) {
      if (normalized.contains(alias.key)) {
        final targetLabel = alias.value;
        if (_tabMapping.containsKey(targetLabel)) {
          switchToTab(_tabMapping[targetLabel]!);
          return true;
        }
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
