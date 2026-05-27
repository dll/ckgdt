import 'package:flutter/material.dart';

import '../../services/navigation_service.dart';
import '../../services/voice_assistant_controller.dart';

/// 顶层 page 接收语音 → 内层 Tab 切换的标准订阅 mixin。
///
/// 用法（page 必须有 `late TabController _tabController` 字段）：
/// ```dart
/// class _MyPageState extends State<MyPage>
///     with SingleTickerProviderStateMixin, InnerTabRequestMixin {
///   @override String get innerTabPageKey => 'assessment';
///   @override String get innerTabSpeakLabel => '考核';
///   @override List<String> innerTabLabels() =>
///       _isStudent ? const ['分组',...] : const ['分组','项目',...,'AI批阅'];
///
///   @override
///   void initState() {
///     super.initState();
///     _tabController = TabController(...);
///     bindInnerTabRequest();   // ← 替代手写 addListener + postFrame
///   }
///   @override
///   void dispose() {
///     unbindInnerTabRequest();
///     _tabController.dispose();
///     super.dispose();
///   }
/// }
/// ```
mixin InnerTabRequestMixin<T extends StatefulWidget> on State<T> {
  /// 与 VoiceAgent prompt 中 `_innerTabs` map 的 key 对齐
  String get innerTabPageKey;

  /// 找不到 idx 时朗读"<tab> 是教师专属功能"中的"<父页>"
  String get innerTabSpeakLabel;

  /// 该 page 内层 tab label 列表（角色感知由实现自行处理）
  List<String> innerTabLabels();

  /// 找到内层 tab 后切到的 controller
  TabController get innerTabController;

  void bindInnerTabRequest() {
    NavigationService.instance.innerTabSeq.addListener(_applyInnerTabRequest);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _applyInnerTabRequest());
  }

  void unbindInnerTabRequest() {
    NavigationService.instance.innerTabSeq
        .removeListener(_applyInnerTabRequest);
  }

  void _applyInnerTabRequest() {
    if (!mounted) return;
    final req = NavigationService.instance.consumeInnerTab(innerTabPageKey);
    if (req == null) return;
    final idx = _matchTabIndex(req.tabKeyword, innerTabLabels());
    if (idx != null) {
      innerTabController.animateTo(idx);
    } else {
      VoiceAssistantController.instance.speakNoPermission(
        page: innerTabSpeakLabel,
        tab: req.tabKeyword,
      );
    }
  }

  static int? _matchTabIndex(String kw, List<String> labels) {
    for (int i = 0; i < labels.length; i++) {
      if (kw.contains(labels[i]) || labels[i].contains(kw)) return i;
    }
    return null;
  }
}
