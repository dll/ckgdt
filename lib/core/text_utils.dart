/// 通用文本工具——简单的字符串清洗工具放这里。
library;

/// 删除字符串里所有非数字字符，返回纯数字串。
///
/// 用例：从语音识别 / 用户输入中提取学号或电话号码。
/// 三处历史调用过 `replaceAll(RegExp(r'[^0-9]'), '')` 同款逻辑。
///
/// `null` 安全：传 null 返回空串。
String extractDigits(String? input) {
  if (input == null || input.isEmpty) return '';
  return input.replaceAll(_digitsOnly, '');
}

final RegExp _digitsOnly = RegExp(r'[^0-9]');
