import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_win_floating/webview_win_floating.dart'
    show WindowsWebViewControllerCreationParams;

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

class TeachingTaskAuthorizedFetchPage extends StatefulWidget {
  final String initialUrl;

  const TeachingTaskAuthorizedFetchPage({
    super.key,
    this.initialUrl = TeachingTaskSourceService.printLessonBookUrl,
  });

  @override
  State<TeachingTaskAuthorizedFetchPage> createState() =>
      _TeachingTaskAuthorizedFetchPageState();
}

class _TeachingTaskAuthorizedFetchPageState
    extends State<TeachingTaskAuthorizedFetchPage> {
  WebViewController? _controller;
  String _currentUrl = TeachingTaskSourceService.printLessonBookUrl;
  String _status = '请在教务网页中完成登录，然后进入教学任务书打印页。';
  bool _loading = true;
  bool _extracting = false;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = await _createController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _currentUrl = url;
              _status = '正在打开教务系统...';
            });
          },
          onUrlChange: (change) {
            if (!mounted || change.url == null) return;
            setState(() => _currentUrl = change.url!);
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _currentUrl = url;
              _status = url.contains('printLessonBook')
                  ? '已进入教学任务书打印页，可提取当前页。'
                  : '请登录后进入教学任务书打印页，或点击右上角“任务书页”。';
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _status = '网页加载异常：${error.description}';
            });
          },
        ),
      );
      await controller.loadRequest(Uri.parse(widget.initialUrl));
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = e;
        _loading = false;
      });
    }
  }

  Future<WebViewController> _createController() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      final supportDir = await getApplicationSupportDirectory();
      final params = WindowsWebViewControllerCreationParams(
        userDataFolder: p.join(supportDir.path, 'jwgl_webview'),
        profileName: 'archive-teaching-task',
      );
      return WebViewController.fromPlatformCreationParams(params);
    }
    return WebViewController();
  }

  Future<void> _loadPrintPage() async {
    await _controller?.loadRequest(
      Uri.parse(TeachingTaskSourceService.printLessonBookUrl),
    );
  }

  Future<void> _extractCurrentPage() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _extracting = true;
      _status = '正在提取当前页面 HTML...';
    });
    try {
      final value = await controller.runJavaScriptReturningResult('''
(() => JSON.stringify({
  url: window.location.href,
  title: document.title || '',
  html: '<!DOCTYPE html>\\n' + document.documentElement.outerHTML
}))()
''');
      final payload = _decodeJsString(value);
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final html = (data['html'] as String? ?? '').trim();
      final url = data['url'] as String? ?? _currentUrl;
      final title = data['title'] as String? ?? '';
      if (html.isEmpty || !html.contains('<html')) {
        throw const FormatException('当前页面 HTML 为空');
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        TeachingTaskAuthorizedFetchResult(
          html: html,
          url: url,
          title: title,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _status = '提取失败：$e。请确认当前页是教学任务书打印页。';
      });
    }
  }

  String _decodeJsString(Object value) {
    var text = value.toString();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      final decoded = jsonDecode(text);
      if (decoded is String) text = decoded;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('教务授权获取教学任务单'),
        actions: [
          IconButton(
            tooltip: '任务书页',
            onPressed: controller == null ? null : () => _loadPrintPage(),
            icon: const Icon(Icons.assignment_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: controller?.reload,
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.icon(
            onPressed:
                controller == null || _extracting ? null : _extractCurrentPage,
            icon: _extracting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done_outlined, size: 18),
            label: const Text('提取当前页'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(
            url: _currentUrl,
            status: _initError?.toString() ?? _status,
            loading: _loading || _extracting,
          ),
          Expanded(
            child: _initError != null
                ? _ErrorPanel(error: _initError!)
                : controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String url;
  final String status;
  final bool loading;

  const _StatusBar({
    required this.url,
    required this.status,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: color.surfaceContainerHighest.withValues(alpha: 0.65),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (loading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final Object error;

  const _ErrorPanel({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '无法打开内嵌教务网页',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  '$error',
                  style: TextStyle(color: Colors.red.shade700),
                ),
                const SizedBox(height: 12),
                const Text(
                  '请确认当前平台支持 WebView，且已安装系统 WebView/Edge WebView2 运行时；也可以继续使用手动导入兜底。',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
