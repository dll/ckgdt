/// 集中管理对外发布的 URL 与 API 端点。
///
/// 部署 URL（[webApp]）变更只需改这里，所有引用点同步生效。
class AppUrls {
  AppUrls._();

  /// 公网 Web 版部署地址（GitHub Pages）。
  /// 多端互通页"Web 访问"区、登录页公网入口提示、二维码内容均使用此 URL。
  static const String webApp = 'https://dll.github.io/mad-fd/';

  /// Gitee API v5 基础地址 — `GiteeService` 用来发同步请求。
  static const String giteeApi = 'https://gitee.com/api/v5';

  /// 项目 Gitee 仓库主页 — 课程同步、issue 提交时引用。
  static const String giteeRepo = 'https://gitee.com/osgisOne/mad-fd';
}

/// 集中管理 Gitee 凭据。
///
/// **设计权衡**：本项目是教学场景，所有学生需要往 osgisOne/mad-fd 仓库提交作业。
/// 不可能让 88 个学生每人申请一把 access_token，因此采用"全班共享一把预置 Token"
/// 模式 — 这是教学产品的标准取舍，不是安全漏洞。
///
/// 如果泄漏到课程外，作废重发即可（去 Gitee 后台 revoke 旧 token，把 [syncToken]
/// 改为新值，重新构建发版给学生）。
///
/// 上一次旧 Token: `64a07762f8a3ab4415b8c943651bfb91`（已 revoke，仅用于检测旧
/// SharedPreferences 缓存值并自动覆盖更新）。
class GiteeCredentials {
  GiteeCredentials._();

  /// 当前预置同步 Token（osgisOne/mad-fd 仓库读写权限）。
  static const String syncToken = '17d6948aabc0764e4f18bb7b215fa32c';

  /// 已作废的旧 Token — 检测到学生本地仍存这个值时自动替换为 [syncToken]。
  static const String legacyTokenForMigration =
      '64a07762f8a3ab4415b8c943651bfb91';
}
