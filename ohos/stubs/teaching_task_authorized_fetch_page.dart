// OHOS 构建专用桩：HarmonyOS 的 flutter fork（Dart 3.4）只能用 webview_flutter 3.0.4，
// 不支持本页用到的 webview_flutter 4.x API（WebViewController / WebViewWidget / NavigationDelegate）。
// 构建时由 ohos_patch.ps1 拷贝覆盖原文件，构建结束 ohos_restore.ps1 还原。
// 保持公开 API（类名/构造函数/结果类型）与原文件一致，确保调用方编译通过。
import 'package:flutter/material.dart';

import '../../../services/archive/teaching_task_source_service.dart';

class TeachingTaskAuthorizedFetchResult {
  final String html;
  final String url;
  final String title;

  const TeachingTaskAuthorizedFetchResult({
    required this.html,
    required this.url,
    required this.title,
  });
}

class TeachingTaskAuthorizedFetchPage extends StatelessWidget {
  final String initialUrl;

  const TeachingTaskAuthorizedFetchPage({
    super.key,
    this.initialUrl = TeachingTaskSourceService.printLessonBookUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('授权抓取')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '该功能依赖内嵌网页（WebView），HarmonyOS 版本暂不支持。\n请在 Windows / Android / Web 端使用此功能。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
