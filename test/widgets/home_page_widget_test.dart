import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/presentation/pages/home/home_page.dart';

void main() {
  group('HomePage widget tests', () {
    testWidgets('shows bottom navigation labels', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('首页'), findsAtLeastNWidgets(1));
      expect(find.text('图谱'), findsAtLeastNWidgets(1));
      expect(find.text('测验'), findsAtLeastNWidgets(1));
      expect(find.text('视频'), findsAtLeastNWidgets(1));
      expect(find.text('资料'), findsAtLeastNWidgets(1));
      expect(find.text('进度'), findsAtLeastNWidgets(1));
      expect(find.text('计划'), findsAtLeastNWidgets(1));
      expect(find.text('设置'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows feature menu on home tab', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(initialTabIndex: 0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('功能菜单'), findsOneWidget);
      expect(find.text('知识图谱'), findsOneWidget);
      expect(find.text('章节测验'), findsOneWidget);
      expect(find.text('视频教程'), findsOneWidget);
      expect(find.text('课程资料'), findsOneWidget);
    });

    testWidgets('can switch from home tab to graph tab', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(initialTabIndex: 0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('功能菜单'), findsOneWidget);

      await tester.tap(find.text('图谱'));
      await tester.pumpAndSettle();

      expect(find.text('功能菜单'), findsNothing);
      expect(find.text('知识图谱'), findsNothing);
      expect(find.text('章节测验'), findsNothing);
      expect(find.text('视频教程'), findsNothing);
      expect(find.text('课程资料'), findsNothing);
    });
  });
}
