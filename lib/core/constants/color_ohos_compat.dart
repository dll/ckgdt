import 'dart:ui';

/// OHOS Flutter SDK 3.4.0 兼容垫片
///
/// 标准 Flutter 3.27+ 在 [Color] 上提供 instance method `withValues({double? alpha, ...})`,
/// 但 OHOS Flutter fork 3.4.0 仍只有 `withOpacity`。
///
/// 此 extension 提供同名同签名实现作为 fallback。
/// 在标准 Flutter 上，dart:ui 的 instance method 优先匹配，extension 不被调用。
/// 在 OHOS 上，instance method 不存在，extension 兜底。
extension ColorOhosCompat on Color {
  /// alpha 0.0~1.0；其它通道暂忽略（项目内未使用 red/green/blue 重写）
  Color withValues({double? alpha, double? red, double? green, double? blue}) {
    final a = alpha != null ? (alpha.clamp(0.0, 1.0) * 255).round() : this.alpha;
    return Color.fromARGB(a, this.red, this.green, this.blue);
  }
}
