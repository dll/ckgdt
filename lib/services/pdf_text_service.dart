import 'pdf_text_service_stub.dart'
    if (dart.library.io) 'pdf_text_service_native.dart' as impl;

/// PDF 文本提取服务（条件导入：原生支持，Web 桩实现）
class PdfTextService {
  PdfTextService._();

  /// 从 PDF 文件提取纯文本
  ///
  /// 失败返回 null（文件不存在、加密、格式错误等）
  /// [maxChars] 最多返回多少字符，超出截断（默认 20000，约 LLM 上下文 8K tokens）
  static Future<String?> extractFromFile(String filePath,
          {int maxChars = 20000}) =>
      impl.extractFromFile(filePath, maxChars: maxChars);

  /// 从 PDF 字节数据提取纯文本
  static Future<String?> extractFromBytes(List<int> bytes,
          {int maxChars = 20000}) =>
      impl.extractFromBytes(bytes, maxChars: maxChars);
}
