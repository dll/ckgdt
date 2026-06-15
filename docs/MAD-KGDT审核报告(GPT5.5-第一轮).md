---
title: MAD-KGDT 课程知识图谱与数字孪生平台审核报告
date: 2026-06-15
reviewer: GPT5.5 第一轮
target: D:\FlutterProjects\knowledge_graph_app
head: 35be4307 chore: 重新追踪达成度操作指南视频 + gitignore 例外
version: 1.21.2+2
scope: 全项目横切审核，覆盖架构、依赖、角色、图谱、教学、评价、达成、归档、直播、智能体、平台化、测试与发布风险
---

# MAD-KGDT 审核报告（GPT5.5-第一轮）

## 一、结论

本项目已经从“移动应用开发单课程工具”演进为“课程知识图谱与数字孪生教学平台”的中大型 Flutter 教学系统。当前代码具备完整教学闭环：学生侧覆盖图谱、学习、实验、考核、作品；教师侧覆盖图谱、教学、评价、达成、归档；管理员侧覆盖用户、班级、课程、数据、发布和统计。

从功能完整度看，项目可以进入小范围外测；从公开发布质量看，还不应直接打最终包。主要拦截点是：全量测试当前失败、`flutter analyze` 仍有 warning、Windows release 构建本轮未完成、直播能力缺少实机矩阵验证、内置 AI/Gitee 凭据属于明确的发布治理风险。

需要注意：用户此前明确要求 AI key “留给新用户使用，保留不改”。因此本报告不建议简单删除 key，而建议把它纳入教育版发布策略：明确额度、轮换、日志、用户告知和构建开关。

## 二、审核基线

| 项目 | 本轮实测 |
| --- | --- |
| 当前日期 | 2026-06-15 |
| Git 分支 | `master` |
| HEAD | `35be4307` |
| 工作区 | 干净 |
| 应用版本 | `1.21.2+2` |
| Dart 源码规模 | `lib` 下 379 个 Dart 文件，约 176,016 行 |
| 页面规模 | `lib/presentation/pages` 下 156 个 Dart 文件 |
| 服务规模 | `lib/services` 下 129 个 Dart 文件 |
| 数据层规模 | 33 个 DAO，`database_helper.dart` 中 66 张表，DB version 30 |
| 智能体数量 | 18 个注册智能体 |
| 测试规模 | 36 个测试文件，约 4,215 行 |
| 本地资源 | `assets` 约 52MB；本地 `data` 约 1.33GB，大部分被 `.gitignore` 控制 |

## 三、验证结果

### 3.1 静态分析

命令：

```powershell
flutter analyze --no-pub
```

结果：未发现 Dart 编译级 error，但发现 564 个 issue，其中至少 14 条 warning。主要 warning：

- `lib/presentation/pages/materials/courseware_workshop_page.dart:137`：`_selectedModelLabel` 未使用。
- `lib/presentation/pages/materials/courseware_workshop_page.dart:3321`：恒真 null 比较。
- `lib/presentation/pages/notification/notification_manage_page.dart:171`：恒真 null 比较。
- 多处未使用变量、未使用 import、未使用私有方法。

判断：这不是当前最严重的运行风险，但发布前应至少清空 warning，保留 info 级别技术债可以接受。

### 3.2 全量测试

命令：

```powershell
flutter test --no-pub
```

结果：`+263 ~2 -3`，存在 3 个失败。失败集中在 `test/widgets/home_page_widget_test.dart`，单独复测确认关键失败是“can switch from home tab to graph tab”。

失败原因：

- 测试环境未初始化 `sqflite_common_ffi` 的 `databaseFactory`，首页切到图谱页时触发真实数据库路径。
- 图谱空状态布局在测试视口下溢出：`lib/presentation/pages/graph/knowledge_graph_page.dart:2232` 附近的 `Column` 底部 overflow 14px。

判断：这更像测试环境和空状态布局问题，不一定影响真实用户启动，但它会让 CI 失去发布门禁价值。发布前必须修复。

### 3.3 Windows 构建

命令：

```powershell
flutter build windows --release --no-pub
```

结果：5 分钟超时，未得到成功或失败结论。超时后残留的 `dart/cmake` 进程已停止。

判断：本轮不能声称 Windows release 构建通过。外测前需要重新单独执行 release 构建，记录完整日志；Android APK、Web、HarmonyOS、iOS 也需要各自构建验证。

## 四、关键发现

### P0-1 全量测试失败，发布门禁不可信

位置：`test/widgets/home_page_widget_test.dart:34`、`lib/presentation/pages/graph/knowledge_graph_page.dart:2232`

问题：Widget 测试没有注入测试数据库工厂和内存数据库；切换到图谱页时触发真实数据库初始化异常，同时空状态布局溢出。

影响：CI 即使接入全量测试也会失败；如果忽略失败继续发布，会降低后续回归验证可信度。

建议：

- 在 `home_page_widget_test.dart` 的 `setUpAll` 中初始化 `sqfliteFfiInit()` 和 `databaseFactory = databaseFactoryFfi`，或把 HomePage 的数据依赖抽成可注入 mock。
- 图谱空状态改为 `SingleChildScrollView` 或给说明区加 `Flexible`，避免小视口溢出。
- 修复后重新跑 `flutter test --no-pub`。

### P0-2 Windows release 构建未验证通过

位置：构建链路

问题：本轮 `flutter build windows --release --no-pub` 超时，未产出 Release 目录结果。

影响：教师 Windows 端是当前核心交付端，未完成构建验证会直接影响外测可交付性。

建议：

- 单独运行 Windows release 构建，保留完整日志。
- 若仍超时，检查 CMake/Ninja 是否卡在插件编译、文件锁、杀毒扫描或 build 缓存。
- 构建通过后再做一次启动、登录、直播、达成、归档的冒烟测试。

### P1-1 内置 AI key 与 Gitee token 是产品策略风险

位置：`lib/data/models/ai_config_model.dart`、`lib/core/constants/app_urls.dart`、`lib/services/data_loading_service.dart`

现状：

- AI provider 默认 key 明文内置，支持新用户开箱即用。
- Gitee 同步 token 明文内置，并在启动时自动写入本地配置。

影响：

- 对课堂内部分发有实用价值，但公开仓库、公开 APK、公开 Windows 包都会扩散凭据。
- 如果额度被滥用，会影响新用户使用和教师账号安全。

建议：

- 保留“新用户可用”的产品目标，但改成可治理模式：教育版共享 key、每日额度限制、服务端代理、定期轮换、使用日志和禁用开关。
- 更新代码注释。当前 `AiConfigModel` 注释仍写“正式发布时移除”，与用户要求的“保留给新用户使用”冲突，容易让维护者误删。
- Gitee token 至少限制仓库权限，不应复用个人高权限 token。

### P1-2 答辩直播基本实现完整，但局域网 HTTP/MJPEG 无鉴权

位置：`lib/services/defense_streaming/defense_streaming_server.dart`

现状：

- 已实现 UDP 自动发现、HTTP 服务、MJPEG 流、Windows GDI 桌面抓取、Android MediaProjection 全屏录制、CameraX 摄像头推流。
- 有 `mjpeg_frame_parser_test.dart` 覆盖 TCP 分片、多帧解析和同一连接连续推送。

问题：

- `/frame/phone`、`/frame/camera`、`/raw/*`、`/stream/feed` 等端点没有会话 token。
- Android `network_security_config.xml` 全局允许 cleartext，符合局域网直播需要，但放大了网络内被旁路访问的风险。

影响：

- 同一局域网内任何知道 IP/端口的人理论上可以看流或 POST 帧。
- 外测环境如开启 AP 隔离、组播限制、防火墙阻断，自动发现和直播稳定性会受影响。

建议：

- 给每次直播生成一次性 session token，学生扫码/通知获取 token，所有 GET/POST 都校验。
- 教师端显示“本机 IP、端口、当前 viewer、最近帧时间、网络诊断”。
- 发布前做实机矩阵：Windows 教师演示、Android 学生答辩、Android 学生观看、Windows 教师观看、同 Wi-Fi/热点/AP 隔离三种网络。

### P1-3 平台化完成了数据骨架，但内容资产仍强绑定《移动应用开发》

位置：`assets/graphs`、`assets/agent_prompts`、`assets/syllabus`、`CourseContextService`

现状：

- 已有 `courses` 表、激活课程、`CourseContextService.scopedWhere`、稳定课程 ID、课程管理页面。
- 达成、归档、课件生成等新功能开始使用当前激活课程。

问题：

- 大量图谱 Markdown、提示词、教学指导手册仍写死《移动应用开发》。
- 默认课程 ID `mad` 用于兼容历史数据，合理，但容易让新课程混入旧内容。

影响：

- 软件工程等课程可以创建和部分使用，但内容层会出现移动应用开发话术、图谱和案例污染。

建议：

- 新课程创建时生成独立 course_id 下的图谱、实验、考核、达成模板，不直接复用 `mad` 内容。
- Agent prompt 中课程名必须从当前课程上下文注入，避免硬编码课程。
- 把默认移动应用开发资产标注为“示例课程包”，新课程默认空白或 AI 初始化。

### P1-4 归档模块结构正确，但处理器注册清单存在漂移风险

位置：`lib/presentation/pages/archive/archive_constants.dart`、`lib/services/archive/processor_registry.dart`

现状：

- 期初、期中、期末、结课复用 `ArchivePeriodTab` 流水线。
- 生成、审核、预览、打印、归档、打包已经统一到 Processor/Package 服务。
- 教学任务书支持教务 MHTML/PDF 版式继承，方向正确。

问题：

- `archive_constants.dart` 的文档清单与 `ProcessorRegistry.registerAll()` 的 AI 起草处理器清单是两份白名单。
- 新增资料时，如果只改 UI 清单，不补注册处理器，就会走回退路径，状态统计和处理能力不一致。

影响：

- 期初 14 类资料继续扩展时，容易出现“页面有卡片，但审核/打印/归档体验不完整”。

建议：

- 将 `DocumentTypeDef` 增加 processor kind / generation mode 字段，由同一清单驱动 UI 和 ProcessorRegistry。
- 对每个 period 建立“应有资料清单 vs 已注册处理器 vs 可导入/可生成/可打印”测试。

### P1-5 结课归档清单可能漏掉 filePath-only 文档

位置：`lib/presentation/pages/archive/widgets/archive_materials_checklist.dart:39`

问题：结课归档清单当前筛选 `(d.content ?? '').trim().isNotEmpty`，如果某些资料是直接导入原始文件，只保存 `filePath` 而 `content` 为空，清单会漏掉。

影响：用户认为“期初/期中/期末已积累材料”，但结课清单未显示，造成归档不完整。

建议：筛选条件改为 `content` 非空或 `filePath` 存在，并在 `ArchivePackageService.archiveDocxOf` 中继续优先复制原始文件。

### P1-6 达成模块数据逻辑进步明显，但 UI 仍固定展示实验达成

位置：`lib/presentation/pages/achievement/achievement_page.dart`

现状：

- 测试已覆盖无实验课程：动态成绩模板不生成实验列、报告不暴露目标4、改进建议不出现实验建议。
- 解决了“实验没有还显示 0”的关键计算问题。

问题：页面 Tab 仍固定包含“实验达成”。对大学英语、软件工程理论课等无实验课程，空 Tab 会降低可信度。

建议：根据课程目标对照表或 `course_objectives.experiment_ratio` 动态隐藏实验达成 Tab；若为 0，只在计算过程里说明“本课程无实验评价项”。

### P1-7 AI 课件生成重构方向正确，但新增路径缺少测试

位置：`lib/services/courseware_service.dart:138`、`lib/presentation/pages/materials/courseware_workshop_page.dart`

现状：

- 新增高质量课件流水线：课程上下文、知识图谱节点注入、结构化 slides、speaker notes、二次审查、Markdown/PPTX 兼容。
- 智能体课件生成已走新接口。

问题：

- 新增路径引入 analyzer warning：`_selectedModelLabel` 未使用、恒真 null 判断。
- 没有针对 JSON 解析失败、兜底课件、slides 转 Markdown/PPTX 的单元测试。

建议：

- 先清理 warning。
- 增加纯 Dart 测试：`_jsonObjectFromText` 风格的公开 wrapper 或间接测试、fallback package、`generateCoursewareMarkdown`。
- UI 文案仍有“教案已导入/教案生成失败”等旧词，可逐步统一为“课件/教学设计”。

## 五、模块审核

### 5.1 角色与导航

优点：

- 首页已按角色区分底部导航：教师/管理员为首页、图谱、教学、评价、达成、归档，管理员额外管理；学生为首页、图谱、学习、实验、考核、作品。
- `RoleGuard` 有权限矩阵测试，语音/智能体子页面导航也调用权限守卫。
- 教师名单从 `data/用户/管理员教师名单.xlsx` 导入，适合外测前发教师账号。

风险：

- 默认密码仍是工号/学号后 6 位或完整账号，外测可用，但正式发布应强制首次修改密码。
- `loginById` 用于扫码跳过密码，必须只在可信局域网/已授权 token 场景使用。

### 5.2 图谱模块

优点：

- 图谱已与课程上下文、学习记录、达成度热力图、教师聚合视图关联。
- 支持知识图谱和结构图谱双视图，具备教师教学与学生学习两种视角。

风险：

- `knowledge_graph_page.dart` 体量大，测试中暴露空状态布局溢出。
- 图谱资产仍以移动应用开发为主，新课程需要独立图谱生成流程。

### 5.3 教学、学习、实验、考核、作品

优点：

- 教师端“教学”和“评价”聚合页降低了导航复杂度。
- 实验、考核、作品均存在教师批阅/AI 批阅路径，能形成评价闭环。

风险：

- 多处页面仍是大文件，后续改动容易引入局部 UI 回归。
- 直播、考核、作品与归档之间的数据汇总还需要更多端到端测试。

### 5.4 达成模块

优点：

- 8 个功能 Tab 流程完整。
- 动态指标、无实验课程、学校 Excel 导入、报告生成均有测试或代码路径。
- 视频帮助支持从 Gitee 下载，不强制打包进入安装包，符合体积控制要求。

风险：

- UI Tab 未完全动态化。
- Gitee 视频下载依赖 token/网络/仓库文件存在性，手机端需要离线失败提示和重试体验。

### 5.5 归档模块

优点：

- 从期初到期中、期末、结课已经形成统一归档流程。
- 教学任务书保留学校原始 MHTML/PDF 版式来源，价值点清晰。
- 结课清单按同一课程 ID 汇总，支持勾选打包。

风险：

- Pandoc/LibreOffice 是桌面端强依赖，新环境需要明确安装检测和一键诊断。
- 处理器清单与资料清单分离，扩展时易漂移。
- filePath-only 文档可能漏出结课清单。

### 5.6 答辩直播

优点：

- 角色模型已接近需求：学生观看/答辩，教师主播/观看/演示。
- Windows 桌面抓屏与 Android 手机全屏录制都已实现。
- 教师演示和学生答辩共用局域网实时流基础设施。

风险：

- 缺少访问 token。
- 缺少实机自动化或半自动验收脚本。
- 网络隔离会直接影响 UDP 发现和 HTTP 连接。

### 5.7 智能体与 AI

优点：

- 18 个智能体覆盖图谱、测验、学习、实验、作品、考核、达成、归档、课件、数字孪生等。
- 特殊工具已能生成图谱、达成报告、课件。
- 新课件生成流水线明显提升质量上限。

风险：

- 大模型输出 JSON 的稳定性依赖兜底逻辑，关键路径需要更多测试。
- 凭据策略需要产品化治理。

## 六、依赖与打包可用性

### 6.1 Flutter 依赖

关键依赖包括：

- 数据：`sqflite`、`sqflite_common_ffi`、`sqlite3_flutter_libs`、`excel`
- 文档：`pdf`、`printing`、`syncfusion_flutter_pdf`、`archive`、`xml`
- 媒体：`media_kit`、`camera`、`camera_windows`、`record`
- 网络：`http`、`web_socket_channel`、`network_info_plus`
- Windows：`win32`、`ffi`
- WebView：`webview_flutter`、`webview_win_floating`

整体依赖与功能需求匹配，但发布包要分别验证 Windows、Android、Web 的插件可用性。

### 6.2 资产

已跟踪的大资产主要是字体：

- `assets/fonts/msyh.ttc` 约 19.7MB
- `assets/fonts/msyhbd.ttc` 约 16.9MB
- `assets/fonts/simhei.ttf` 约 9.7MB

本地 `data/课件` 与 `data/视频` 体积很大，但多数被 `.gitignore` 排除。`data/视频/达成度评价系统操作指南.mp4` 通过例外被追踪，符合手机端下载视频的需求。

建议：发布前核对 `pubspec.yaml` 资产声明，确认教师名单、达成模板、帮助文档、图谱、agent prompt 都能进入目标平台包；对 `data/归档` 这类运行时模板目录，桌面端应随安装包外置或安装后首次同步。

## 七、发布前建议清单

### 必须完成

1. 修复 `flutter test --no-pub` 的 3 个失败，确保全量测试通过。
2. 清理 `flutter analyze` 的 warning，至少做到 0 error / 0 warning。
3. 重新完成 Windows release 构建，并记录日志。
4. 做直播实机矩阵验收：教师 Windows 演示、教师 Windows 主播、学生 Android 答辩、学生 Android 观看、教师 Android 演示。
5. 明确 AI key 与 Gitee token 的发布治理方案，不要让维护者误以为“正式发布时移除”。

### 建议完成

1. 给答辩直播端点增加一次性 session token。
2. 达成页面根据指标动态隐藏无关 Tab。
3. 归档结课清单纳入 filePath-only 文档。
4. 合并归档资料清单与 ProcessorRegistry 清单，减少漂移。
5. 给 AI 课件生成新增单元测试。
6. 更新 README，替换当前模板化内容，写明安装、角色账号、外测流程、平台限制和常见问题。

## 八、最终判断

当前项目已经具备教学闭环和外测价值，但不是“无条件发布”的状态。

如果目标是校内小范围试用：可以发布候选版，但必须附带已知问题和直播网络要求。

如果目标是公开发布或大规模外测：应先完成测试、构建、凭据治理和直播鉴权四项收口，再打正式包。

