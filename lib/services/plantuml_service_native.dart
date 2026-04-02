/// 原生平台 deflate 压缩实现
import 'dart:io' show ZLibEncoder;

List<int> deflate(List<int> data) {
  try {
    return ZLibEncoder(raw: true).convert(data);
  } catch (_) {
    return data;
  }
}
