/// 应用品牌与版本号 — **单一来源 (SSOT)**。
///
/// 全项目所有需要"显示版本号 / 显示品牌名"的代码都从这里读，**不准再硬编码**。
/// 升版只改 `appVersion`；其他平台清单（pubspec/strings.xml/Runner.rc/...）
/// 必须用 CLAUDE.md 的"升版同步表"一一对齐。
///
/// 为什么不用 package_info_plus 直接读 pubspec：
/// - 桌面/Web 启动早期（DB 初始化失败页）连 PluginRegistrar 都还没到，
///   读不到 package_info；
/// - 登录页 / 关于页 都是同步 build()，不能等 future；
/// - 同步常量编译期写死，零 IO，零异常路径。
library;

class BuildInfo {
  BuildInfo._();

  /// 主版本号。**升版时改这一处即可影响 lib/ 内所有显示**。
  /// 平台原生清单（CMakeLists / Runner.rc / strings.xml / web 元数据 / ohos app.json5）
  /// 必须同步修改 — 见 CLAUDE.md "升版同步表"。
  static const String appVersion = '0.13.1';

  /// 窗体标题用简称（窗口边框、任务栏、浏览器标签页）。
  static const String appBrand = '移动图谱与数字孪生';

  /// 完整产品名（登录页 Logo 下方、关于对话框标题）。
  static const String appFullName = '移动应用开发知识图谱与数字孪生平台';

  /// 登录页落款年份（年份每年元旦更新一次，与版本号解耦）。
  static const String appEdition = 'EDITION 2026';

  /// 拼成 "移动图谱与数字孪生v0.13.1"，给窗体标题 / 文件名用。
  static const String appBrandWithVersion = '${appBrand}v$appVersion';

  /// 拼成 "V0.13.1  ·  EDITION 2026"，给登录页副标题用。
  static const String appVersionLine = 'V$appVersion  ·  $appEdition';
}
