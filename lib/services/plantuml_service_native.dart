/// 原生平台 deflate 压缩实现
library;
import 'dart:io' show ZLibEncoder;
import '../core/error_handler.dart';

List<int> deflate(List<int> data) {
  try {
    return ZLibEncoder(raw: true).convert(data);
  } catch (e, st) {
    swallowDebug(e, tag: 'plantuml_service_native.deflate', stack: st);
    return data;
  }
}
