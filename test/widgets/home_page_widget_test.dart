import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/presentation/pages/home/home_page.dart';

import '../helpers/test_db.dart';

void main() {
  setUpAll(setupTestSqflite);

  group('HomePage widget tests', () {
    testWidgets('shows bottom navigation labels', (WidgetTester tester) async {
      await tester.pumpWidget(_testHomePage());
      await tester.pumpAndSettle();

      // 学生角色默认导航标签
      expect(find.text('首页'), findsAtLeastNWidgets(1));
      expect(find.text('图谱'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows feature cards on home tab', (WidgetTester tester) async {
      await tester.pumpWidget(_testHomePage(initialTabIndex: 0));
      await tester.pumpAndSettle();

      // 首页应包含功能卡片
      expect(find.text('知识图谱'), findsOneWidget);
      expect(find.text('章节测验'), findsOneWidget);
    });

    testWidgets('can switch from home tab to graph tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(_testHomePage(initialTabIndex: 0));
      await tester.pumpAndSettle();

      // 首页应显示功能卡片
      expect(find.text('知识图谱'), findsOneWidget);

      // 点击底部导航栏中的 "图谱" 按钮
      final graphNavItem = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('图谱'),
      );
      await tester.tap(graphNavItem);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 切换到图谱 Tab 后，首页卡片应消失
      expect(find.text('章节测验'), findsNothing);
      expect(find.byKey(const Key('graph-tab')), findsOneWidget);
    });
  });
}

Widget _testHomePage({int initialTabIndex = 0}) {
  return MaterialApp(
    home: HomePage(
      initialTabIndex: initialTabIndex,
      enableBackgroundTasks: false,
      graphPageOverride: const SizedBox(key: Key('graph-tab')),
    ),
  );
}
