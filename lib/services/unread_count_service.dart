import 'package:flutter/foundation.dart';
import '../core/error_handler.dart';
import '../data/local/notification_dao.dart';

/// 全局未读通知计数服务。
///
/// **为什么要全局：** AppBar 的未读 Badge 之前住在 `_HomePageState._unreadCount`，
/// 任何对 setState 的调用都会触发整个 `_buildHome()` 30+ 卡片重建，仅仅是为了
/// 更新一个数字。其它页面（如 assessment_page 提交后）也无法直接刷新它。
///
/// 把状态提取到这里，AppBar Badge 用 [ValueListenableBuilder] 订阅 [count]，
/// 只重建 Badge 自身。需要刷新的页面在动作完成后调用 [refresh]。
///
/// **设计权衡：** 用 Flutter 内置 [ValueNotifier] 而非引入 Riverpod —— 当前只有
/// 1 个全局状态需要这种处理，零依赖比框架优先。如果未来 themeMode / activeCourse /
/// authUser 也要类似处理，再统一升级到 Riverpod。
class UnreadCountService {
  UnreadCountService._();

  static final UnreadCountService instance = UnreadCountService._();

  /// 当前未读数。UI 应通过 ValueListenableBuilder 订阅。
  final ValueNotifier<int> count = ValueNotifier<int>(0);

  final NotificationDao _dao = NotificationDao();

  /// 刷新未读数（从 DB 拉取）。
  /// 推荐调用时机：登录后、收到通知后、查看通知列表返回后、提交动作后。
  Future<void> refresh(String? userId) async {
    if (userId == null || userId.isEmpty) {
      count.value = 0;
      return;
    }
    try {
      final n = await _dao.getUnreadCount(userId);
      // 只有真变了才赋值——ValueNotifier 默认 == 比较通过就不通知
      if (count.value != n) count.value = n;
    } catch (e, st) {
      swallowDebug(e, tag: 'UnreadCountService.refresh', stack: st);
      // 数据库异常时静默保持上次值，不打扰 UI
    }
  }

  /// 用户登出时清零。
  void clear() {
    count.value = 0;
  }
}
