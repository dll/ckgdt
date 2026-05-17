import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<String?> extractFromFile(String filePath,
    {int maxChars = 20000}) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return _extract(bytes, maxChars);
  } catch (e) {
    debugPrint('PdfTextService: extractFromFile error: $e');
    return null;
  }
}

Future<String?> extractFromBytes(List<int> bytes,
    {int maxChars = 20000}) async {
  try {
    return _extract(bytes, maxChars);
  } catch (e) {
    debugPrint('PdfTextService: extractFromBytes error: $e');
    return null;
  }
}

String? _extract(List<int> bytes, int maxChars) {
  PdfDocument? doc;
  try {
    doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final raw = extractor.extractText();
    final cleaned = _normalize(raw);
    if (cleaned.isEmpty) return null;
    return cleaned.length > maxChars
        ? '${cleaned.substring(0, maxChars)}\n\n[...内容已截断，原始长度 ${cleaned.length} 字符]'
        : cleaned;
  } finally {
    doc?.dispose();
  }
}

/// 规范化提取的文本：合并多余空行、去除每行首尾空白
String _normalize(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.replaceAll('\r', '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines.join('\n');
}
