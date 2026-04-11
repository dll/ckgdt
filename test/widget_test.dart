import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knowledge_graph_app/presentation/pages/login/login_page.dart';

void main() {
  testWidgets('Login page shows core UI elements', (WidgetTester tester) async {
    // 启用快速登录，使所有按钮可见
    SharedPreferences.setMockInitialValues({
      'quick_login_enabled': true,
    });

    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    // 等待异步 _loadQuickLoginSetting 完成并触发 setState
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('移动应用开发\n知识图谱教学系统'), findsOneWidget);
    expect(find.text('学号/工号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('快速登录'), findsOneWidget);
    expect(find.text('学生'), findsOneWidget);
    expect(find.text('教师'), findsOneWidget);
    expect(find.text('管理员'), findsOneWidget);

    expect(find.byIcon(Icons.school), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('Login page hides quick login when disabled', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'quick_login_enabled': false,
    });

    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();

    // 基础 UI 仍存在
    expect(find.text('移动应用开发\n知识图谱教学系统'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);

    // 快速登录按钮应被隐藏
    expect(find.text('快速登录'), findsNothing);
    expect(find.text('测试学生'), findsNothing);
  });
}
