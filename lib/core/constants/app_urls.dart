/// 集中管理对外发布的 URL 与 API 端点。
///
/// 部署 URL（[webApp]）变更只需改这里，所有引用点同步生效。
class AppUrls {
  AppUrls._();

  /// 公网 Web 版部署地址（GitHub Pages）。
  /// 三端互通页"Web 访问"区、登录页公网入口提示、二维码内容均使用此 URL。
  static const String webApp = 'https://dll.github.io/mad-fd/';

  /// Gitee API v5 基础地址 — `GiteeService` 用来发同步请求。
  static const String giteeApi = 'https://gitee.com/api/v5';

  /// 项目 Gitee 仓库主页 — 课程同步、issue 提交时引用。
  static const String giteeRepo = 'https://gitee.com/osgisOne/mad-fd';
}
