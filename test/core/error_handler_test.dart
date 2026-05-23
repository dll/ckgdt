import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

void main() {
  group('error_handler', () {
    test('swallow 不抛异常 / 不影响后续', () {
      var ran = false;
      try {
        throw Exception('boom');
      } catch (e) {
        swallow(e, tag: 'test');
        ran = true;
      }
      expect(ran, isTrue);
    });

    test('swallowDebug debug 模式下打 print，调用不抛错', () {
      // 测试本身是 debug 模式 — 函数应安全跑过且不抛
      try {
        throw StateError('test-state');
      } catch (e, st) {
        swallowDebug(e, tag: 'test', stack: st);
      }
      // 没崩就 OK；具体 print 内容用 IO 拦截太重，不在此层验
    });

    test('report 永远打 print，调用不抛错', () {
      try {
        throw 'report-test';
      } catch (e, st) {
        report(e, tag: 'test', stack: st);
      }
    });

    test('三个函数都接受 null 或缺省 tag', () {
      swallow('x');
      swallowDebug('x');
      report('x');
    });
  });
}
