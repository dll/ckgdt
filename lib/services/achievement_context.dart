import 'package:flutter/foundation.dart';

/// 当前课程上下文 — 所有达成度相关功能共享的活动课程名。
/// 切换课程时通知所有监听者，各 Tab / 页面自动刷新。
class AchievementContext {
  AchievementContext._();
  static final AchievementContext instance = AchievementContext._();

  final ValueNotifier<String> _courseNameNotifier =
      ValueNotifier<String>('课程知识图谱与数字孪生');

  String get courseName => _courseNameNotifier.value;

  set courseName(String v) {
    if (v.trim().isEmpty) return;
    _courseNameNotifier.value = v.trim();
  }

  ValueNotifier<String> get courseNameNotifier => _courseNameNotifier;

  void addListener(VoidCallback listener) {
    _courseNameNotifier.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    _courseNameNotifier.removeListener(listener);
  }
}
