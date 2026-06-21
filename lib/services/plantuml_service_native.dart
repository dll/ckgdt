/// 原生平台 deflate 压缩实现
library;
import 'dart:io' show ZLibEncoder;

List<int> deflate(List<int> data) {
  try {
    return ZLibEncoder(raw: true).convert(data);
  } catch (_) {
    return data;
  }
}
