/// 内层 Tab 单一来源（SSOT）— 顶层 page 内部 TabController 标签清单。
///
/// **背景**：语音导航需要识别"打开评价的报告页"这类"父页面 + 内层 Tab"指令，
/// VoiceAgent 把每个 page 的内层 tab 清单嵌进 AI prompt。历史上这份清单在
/// VoiceAgent 里用一张 `static const _innerTabs` 手抄，而每个页面又通过
/// `InnerTabRequestMixin.innerTabLabels()` 各自声明一遍 —— 两处靠人肉同步，
/// 已经发生漂移（archive 页四个期间 tab 在 prompt 里整段缺失，语音永远点不开）。
///
/// **本文件是唯一真源**：
/// - VoiceAgent 读这里生成 prompt（不再自己抄一份）；
/// - 每个页面挂载时，[InnerTabRequestMixin] 在 debug 模式断言其
///   `innerTabLabels()` 是这里登记 label 全集的子集，pageKey 必须登记。
///   任何一方漂移，开发期第一时间 assert 失败，而非线上语音静默失灵。
///
/// **维护**：page 的 key 必须与 `NavigationService` 内层 tab 总线、
/// `pageKeyToTabLabel` 的 pageKey 一致。labels 存"全集"（教师 + 学生角色并集），
/// 因为 `innerTabLabels()` 按角色返回不同子集。
library;

/// pageKey → 该页内层 tab 标签全集（教师/学生角色并集，顺序无要求）。
///
/// 新增内层 tab 或新页面接入语音内层导航时，在此登记。
const Map<String, List<String>> kInnerTabRegistry = <String, List<String>>{
  // 评价中心（教师）/ 考核（学生）：学生无 AI批阅
  'assessment': ['分组', '项目', '贡献', '材料', '答辩', '报告', '成绩', 'AI批阅'],
  // 作品展评：学生多"我的作品"
  'works': ['我的作品', '作品展示', '作品记录', '排行榜', 'AI批阅'],
  // 达成度
  'achievement': [
    '达成度概览', '成绩管理', '平时达成', '实验达成',
    '考核达成', '计算过程', '报告生成', '持续改进',
  ],
  // 课堂互动
  'classroom': ['在线状态', '课堂签到', '课堂互动', '课堂工具', '课堂提问'],
  // 实验：教师/学生 tab 名略有差异，存并集
  'lab': [
    '任务列表', '我的提交', '提交管理', '实验报告',
    '实验材料', '任务管理', 'AI批阅', '仓库报表',
  ],
  // 学习中心
  'learning': ['视频', 'PPT', 'PDF', '测验', '助手'],
  // 归档（教师）：四个学期阶段（末阶段已更名 归档→结课）
  'archive': ['期初', '期中', '期末', '结课'],
};

/// 供 AI prompt 引用的中文页面名（pageKey → 朗读友好名）。
const Map<String, String> kInnerTabPageLabels = <String, String>{
  'assessment': '考核（评价中心）',
  'works': '作品展评',
  'achievement': '达成度',
  'classroom': '课堂',
  'lab': '实验',
  'learning': '学习中心',
  'archive': '归档',
};

/// 校验某页声明的内层 tab labels 是否都登记在册。
///
/// 返回未登记的 label 列表（空表示全部合法）。[InnerTabRequestMixin] 在
/// debug 模式用它做运行时断言；单测也用它守护注册表与各页一致。
List<String> unregisteredInnerTabs(String pageKey, List<String> labels) {
  final registered = kInnerTabRegistry[pageKey];
  if (registered == null) return labels; // 整个 page 未登记
  return labels.where((l) => !registered.contains(l)).toList();
}
