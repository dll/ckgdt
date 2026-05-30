import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/inner_tab_registry.dart';
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
    _assertRegisteredInDebug();
    NavigationService.instance.innerTabSeq.addListener(_applyInnerTabRequest);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _applyInnerTabRequest());
  }

  /// debug 期校验：本页 pageKey 必须登记在 [kInnerTabRegistry]，
  /// 且 `innerTabLabels()` 全部是注册表中该 page 的子集。
  ///
  /// 语音 prompt 的内层 tab 清单从同一注册表生成，这里 assert 失败即说明
  /// 页面 tab 与语音 prompt 已漂移（语音将点不开对应 tab），开发期立即暴露。
  void _assertRegisteredInDebug() {
    if (!kDebugMode) return;
    final pageKey = innerTabPageKey;
    final labels = innerTabLabels();
    final unregistered = unregisteredInnerTabs(pageKey, labels);
    assert(
      kInnerTabRegistry.containsKey(pageKey),
      'InnerTab 漂移：页面 pageKey="$pageKey" 未登记到 kInnerTabRegistry '
      '(lib/core/constants/inner_tab_registry.dart)，语音内层导航将无法识别该页。',
    );
    assert(
      unregistered.isEmpty,
      'InnerTab 漂移：页面 "$pageKey" 的 tab $unregistered 未登记到 '
      'kInnerTabRegistry，语音 prompt 不含这些 tab → 点不开。请在注册表补齐。',
    );
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
