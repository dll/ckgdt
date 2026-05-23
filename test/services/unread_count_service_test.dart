import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/unread_count_service.dart';

/// UnreadCountService 是 ValueNotifier 单例，承担"未读 Badge 全局共享"职责。
/// 这些测试不打 DB（DAO 调用要真实 sqflite），只验 ValueNotifier 行为契约。
void main() {
  group('UnreadCountService', () {
    test('单例 instance 每次返回同一实例', () {
      final a = UnreadCountService.instance;
      final b = UnreadCountService.instance;
      expect(identical(a, b), isTrue);
    });

    test('count 默认 0', () {
      // 注意：单例在测试间会共享状态，clear 一下确保 baseline
      UnreadCountService.instance.clear();
      expect(UnreadCountService.instance.count.value, 0);
    });

    test('clear() 把 count 置 0', () {
      UnreadCountService.instance.count.value = 5;
      UnreadCountService.instance.clear();
      expect(UnreadCountService.instance.count.value, 0);
    });

    test('refresh 传 null userId 则置 0（登出场景）', () async {
      UnreadCountService.instance.count.value = 7;
      await UnreadCountService.instance.refresh(null);
      expect(UnreadCountService.instance.count.value, 0);
    });

    test('refresh 传空字符串 userId 同样置 0', () async {
      UnreadCountService.instance.count.value = 3;
      await UnreadCountService.instance.refresh('');
      expect(UnreadCountService.instance.count.value, 0);
    });

    test('count 是 ValueListenable 可订阅', () {
      UnreadCountService.instance.clear();
      int notifyCount = 0;
      void listener() => notifyCount++;
      UnreadCountService.instance.count.addListener(listener);

      UnreadCountService.instance.count.value = 1;
      UnreadCountService.instance.count.value = 1; // 同值不通知
      UnreadCountService.instance.count.value = 2;

      UnreadCountService.instance.count.removeListener(listener);
      expect(notifyCount, 2);
    });

    test('count 类型是 ValueNotifier<int>', () {
      expect(UnreadCountService.instance.count, isA<ValueNotifier<int>>());
    });
  });
}
