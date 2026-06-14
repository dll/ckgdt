/// 应用品牌与版本号 — **单一来源 (SSOT)**。
///
/// 全项目所有需要"显示版本号 / 显示品牌名"的代码都从这里读，**不准再硬编码**。
/// 升版只改 `lib/core/version.dart`（由 `scripts/version_bump.dart` 自动管理）；
/// 其他平台清单（pubspec/strings.xml/Runner.rc/...）
/// 通过 [VersionBumpService.applyVersion] 同步对齐。
///
/// 为什么不用 package_info_plus 直接读 pubspec：
/// - 桌面/Web 启动早期（DB 初始化失败页）连 PluginRegistrar 都还没到，
///   读不到 package_info；
/// - 登录页 / 关于页 都是同步 build()，不能等 future；
/// - 同步常量编译期写死，零 IO，零异常路径。
///
/// 注：构建发布相关的"项目根路径"放在 [DevPaths]（`lib/core/dev_paths.dart`），
/// 那里需要 dart:io，**不能**在本文件引入——本文件被 web 端的登录/关于页面引用。
library;

import 'version.dart';

class BuildInfo {
  BuildInfo._();

  /// 主版本号。从 [Version] SSOT 读取，**不再硬编码**。
  /// 平台原生清单（CMakeLists / Runner.rc / strings.xml / web 元数据 / ohos app.json5）
  /// 通过 `scripts/version_bump.dart` 自动同步 — 见 CLAUDE.md "升版同步表"。
  static const String appVersion = Version.display;

  /// 窗体标题用简称（窗口边框、任务栏、浏览器标签页）。
  static const String appBrand = '课程图谱与数字孪生';

  /// 完整产品名（登录页 Logo 下方、关于对话框标题）。
  static const String appFullName = '课程知识图谱与数字孪生平台';

  /// 登录页落款年份（年份每年元旦更新一次，与版本号解耦）。
  static const String appEdition = 'EDITION 2026';

  /// 拼成 "移动图谱与数字孪生v{version}"，给窗体标题 / 文件名用。
  static const String appBrandWithVersion = '${appBrand}v$appVersion';

  /// 拼成 "V{version}  ·  EDITION 2026"，给登录页副标题用。
  static const String appVersionLine = 'V$appVersion  ·  $appEdition';
}
