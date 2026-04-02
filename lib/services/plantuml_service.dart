import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// 条件导入用于 deflate 压缩
import 'plantuml_service_stub.dart'
    if (dart.library.io) 'plantuml_service_native.dart' as impl;

class PlantUmlService {
  // Kroki 服务（POST，直接发 PUML 文本，无需编码）
  static const _krokiUrl = 'https://kroki.io/plantuml/png';
  // PlantUML 官方（备用，需要编码）
  static const _plantUmlUrl = 'https://www.plantuml.com/plantuml/png/';

  /// 渲染 PUML 内容为 PNG 字节（优先 Kroki，失败后尝试 PlantUML）
  Future<Uint8List?> render(String pumlContent) async {
    // 尝试 Kroki POST
    try {
      debugPrint('=== PlantUmlService: Trying Kroki POST...');
      final bytes = await _renderKroki(pumlContent);
      if (bytes != null && bytes.isNotEmpty) {
        debugPrint('=== PlantUmlService: Kroki POST success, ${bytes.length} bytes');
        return bytes;
      }
    } catch (e) {
      debugPrint('=== PlantUmlService: Kroki POST failed: $e');
    }
    // 尝试 PlantUML GET
    try {
      debugPrint('=== PlantUmlService: Trying PlantUML GET...');
      final bytes = await _renderPlantUml(pumlContent);
      if (bytes != null && bytes.isNotEmpty) {
        debugPrint('=== PlantUmlService: PlantUML GET success, ${bytes.length} bytes');
        return bytes;
      }
    } catch (e) {
      debugPrint('=== PlantUmlService: PlantUML GET failed: $e');
    }
    debugPrint('=== PlantUmlService: All render methods failed');
    return null;
  }

  /// 获取 Kroki GET 渲染 URL（需要 deflate + base64url 编码）
  String getKrokiUrl(String pumlContent) {
    try {
      final deflated = impl.deflate(utf8.encode(pumlContent));
      final encoded = base64Url.encode(Uint8List.fromList(deflated));
      return 'https://kroki.io/plantuml/png/$encoded';
    } catch (_) {
      // fallback to PlantUML encoding
      final encoded = _encodePlantUml(pumlContent);
      return '$_plantUmlUrl$encoded';
    }
  }

  Future<Uint8List?> _renderKroki(String pumlContent) async {
    final response = await http
        .post(
          Uri.parse(_krokiUrl),
          headers: {
            'Content-Type': 'text/plain; charset=utf-8',
            'Accept': 'image/png',
          },
          body: utf8.encode(pumlContent),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) return response.bodyBytes;
    debugPrint('=== PlantUmlService: Kroki status=${response.statusCode}');
    return null;
  }

  Future<Uint8List?> _renderPlantUml(String pumlContent) async {
    // PlantUML 使用自定义编码
    final encoded = _encodePlantUml(pumlContent);
    final url = '$_plantUmlUrl$encoded';
    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'Mozilla/5.0 (compatible; knowledge-graph-app)'},
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) return response.bodyBytes;
    debugPrint('=== PlantUmlService: PlantUML status=${response.statusCode}');
    return null;
  }

  // PlantUML 特有编码（压缩 + base64 变体）
  String _encodePlantUml(String content) {
    final compressed = impl.deflate(utf8.encode(content));
    return _encode64(compressed);
  }

  // PlantUML 自定义 base64 字符表
  static const _b64 =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_';

  String _encode64(List<int> data) {
    final sb = StringBuffer();
    for (var i = 0; i < data.length; i += 3) {
      final b1 = data[i];
      final b2 = i + 1 < data.length ? data[i + 1] : 0;
      final b3 = i + 2 < data.length ? data[i + 2] : 0;
      sb.write(_b64[(b1 >> 2) & 0x3F]);
      sb.write(_b64[((b1 << 4) | (b2 >> 4)) & 0x3F]);
      sb.write(_b64[((b2 << 2) | (b3 >> 6)) & 0x3F]);
      sb.write(_b64[b3 & 0x3F]);
    }
    return sb.toString();
  }
}
