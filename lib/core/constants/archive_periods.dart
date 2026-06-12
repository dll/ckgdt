/// 归档期间常量 — 服务层 / UI 层共享。
///
/// 历史上 `{'beginning': '期初', 'midterm': '期中', ...}` 这张映射在 6 处复制
/// （services/* + presentation/*）。services 不能依赖 presentation，所以独立成
/// 这个 core 文件。新增 period 在此一处加，全项目同步。
library;

const Map<String, String> _periodLabels = {
  'beginning': '期初',
  'midterm': '期中',
  'final': '期末',
  'archive': '结课',
};

const List<String> archivePeriodKeys = ['beginning', 'midterm', 'final', 'archive'];
const List<String> archivePeriodLabels = ['期初', '期中', '期末', '结课'];

String periodLabel(String key) => _periodLabels[key] ?? key;
