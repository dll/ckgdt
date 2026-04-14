// Knowledge Graph Web Server
// 双击运行即可启动本地 Web 服务并自动打开浏览器
// 按 Ctrl+C 停止服务

import 'dart:io';

const int defaultPort = 8080;
const int maxPortRetry = 20;

/// MIME 类型映射
const Map<String, String> mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml',
  '.pdf': 'application/pdf',
  '.mp4': 'video/mp4',
  '.mp3': 'audio/mpeg',
  '.db': 'application/octet-stream',
};

/// 获取 MIME 类型
String getMimeType(String path) {
  final ext = path.contains('.') ? '.${path.split('.').last.toLowerCase()}' : '';
  return mimeTypes[ext] ?? 'application/octet-stream';
}

/// 查找可用端口
Future<int> findAvailablePort(int startPort) async {
  for (int port = startPort; port < startPort + maxPortRetry; port++) {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await server.close();
      return port;
    } catch (_) {
      // 端口被占用，尝试下一个
    }
  }
  throw Exception('无法找到可用端口（尝试范围: $startPort - ${startPort + maxPortRetry - 1}）');
}

/// 打开默认浏览器
Future<void> openBrowser(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    }
  } catch (e) {
    print('  [!] 无法自动打开浏览器，请手动访问: $url');
  }
}

/// 获取 web 目录路径
String getWebDir() {
  // 获取可执行文件所在目录
  final exePath = Platform.resolvedExecutable;
  final exeDir = File(exePath).parent.path;

  // web 目录应与 exe 同级
  final webDir = '$exeDir${Platform.pathSeparator}web';

  if (Directory(webDir).existsSync()) {
    return webDir;
  }

  // 开发模式：尝试相对于当前目录
  final cwdWebDir = '${Directory.current.path}${Platform.pathSeparator}web';
  if (Directory(cwdWebDir).existsSync()) {
    return cwdWebDir;
  }

  // 尝试 build/web
  final buildWebDir = '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}web';
  if (Directory(buildWebDir).existsSync()) {
    return buildWebDir;
  }

  throw Exception('找不到 web 目录！请确保 web/ 文件夹与本程序在同一目录下。');
}

/// 处理 HTTP 请求
Future<void> handleRequest(HttpRequest request, String webDir) async {
  final uri = request.uri;
  var path = uri.path;

  // 默认首页
  if (path == '/' || path.isEmpty) {
    path = '/index.html';
  }

  // 安全检查：防止路径遍历
  final normalizedPath = Uri.decodeComponent(path).replaceAll('\\', '/');
  if (normalizedPath.contains('..')) {
    request.response
      ..statusCode = HttpStatus.forbidden
      ..headers.contentType = ContentType.html
      ..write('<h1>403 Forbidden</h1>')
      ..close();
    return;
  }

  // 构建文件路径
  final filePath = '$webDir${normalizedPath.replaceAll('/', Platform.pathSeparator)}';
  final file = File(filePath);

  if (await file.exists()) {
    // 文件存在，直接返回
    final mimeType = getMimeType(filePath);
    request.response.headers.set('Content-Type', mimeType);
    request.response.headers.set('Cache-Control', 'no-cache');

    // CORS 支持（本地开发用）
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    try {
      await request.response.addStream(file.openRead());
    } catch (_) {
      // 客户端可能已断开
    }
    await request.response.close();
  } else {
    // SPA 路由支持：非静态资源请求回退到 index.html
    if (!path.contains('.')) {
      final indexFile = File('$webDir${Platform.pathSeparator}index.html');
      if (await indexFile.exists()) {
        request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
        request.response.headers.set('Cache-Control', 'no-cache');
        try {
          await request.response.addStream(indexFile.openRead());
        } catch (_) {}
        await request.response.close();
        return;
      }
    }

    // 404
    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.html
      ..write('<h1>404 Not Found</h1><p>File not found: $path</p>')
      ..close();
  }
}

void main(List<String> args) async {
  print('');
  print('  ╔══════════════════════════════════════════════════╗');
  print('  ║     移动应用开发 · 知识图谱教学系统 (Web)       ║');
  print('  ╠══════════════════════════════════════════════════╣');
  print('  ║  启动中...                                      ║');
  print('  ╚══════════════════════════════════════════════════╝');
  print('');

  // 解析命令行端口参数
  int requestedPort = defaultPort;
  for (int i = 0; i < args.length; i++) {
    if ((args[i] == '-p' || args[i] == '--port') && i + 1 < args.length) {
      requestedPort = int.tryParse(args[i + 1]) ?? defaultPort;
    }
  }

  try {
    // 查找 web 目录
    final webDir = getWebDir();
    print('  [i] Web 目录: $webDir');

    // 查找可用端口
    final port = await findAvailablePort(requestedPort);

    // 启动 HTTP 服务器
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final url = 'http://localhost:$port';

    print('  [i] 服务已启动: $url');
    print('  [i] 按 Ctrl+C 停止服务');
    print('');

    // 自动打开浏览器
    await openBrowser(url);
    print('  [i] 已打开默认浏览器');
    print('');
    print('  ── 访问日志 ─────────────────────────────────────');

    // 处理请求
    await for (final request in server) {
      final timestamp = DateTime.now().toString().substring(11, 19);
      final method = request.method;
      final path = request.uri.path;

      // 简洁日志（不显示静态资源的详细日志）
      if (!path.endsWith('.js') &&
          !path.endsWith('.css') &&
          !path.endsWith('.png') &&
          !path.endsWith('.ico') &&
          !path.endsWith('.ttf') &&
          !path.endsWith('.otf') &&
          !path.endsWith('.woff') &&
          !path.endsWith('.woff2') &&
          !path.endsWith('.map')) {
        print('  [$timestamp] $method $path');
      }

      await handleRequest(request, webDir);
    }
  } catch (e) {
    print('');
    print('  [!] 错误: $e');
    print('');
    print('  按回车键退出...');
    stdin.readLineSync();
  }
}
