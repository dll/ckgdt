/// Stub 实现 — Web 平台（无 ZLibEncoder，返回原始数据）
List<int> deflate(List<int> data) {
  // Web 平台没有 dart:io 的 ZLibEncoder，直接返回原始数据
  return data;
}
