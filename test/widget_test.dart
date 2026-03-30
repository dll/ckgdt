import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knowledge_graph_app/presentation/pages/login/login_page.dart';

void main() {
  testWidgets('Login page shows core UI elements', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();

    expect(find.text('移动应用开发\n知识图谱学习系统'), findsOneWidget);
    expect(find.text('学号/工号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('快速登录'), findsOneWidget);
    expect(find.text('测试学生'), findsOneWidget);
    expect(find.text('教师'), findsOneWidget);
    expect(find.text('管理员'), findsOneWidget);

    expect(find.byIcon(Icons.school), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });
}
