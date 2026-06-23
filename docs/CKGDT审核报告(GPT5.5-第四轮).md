# CKGDT 课程知识图谱与数字孪生平台审核报告（GPT5.5 第四轮）

- 审核日期：2026-06-23
- 审核对象：`D:\FlutterProjects\knowledge_graph_app`
- 当前分支：`master`
- 当前提交：`cb264c3 chore: 统一平台品牌为 CKGDT`
- 应用版本：`2.1.0+1`
- Flutter / Dart：`Flutter 3.35.1` / `Dart 3.9.0`
- 本轮重点：平台化命名、学生 AI Key 与 AI 批阅提交链路、归档文档链路、归档班级隔离、发布脚本与回归验证。

## 总体结论

本轮原始结论：**内测可继续，公开发布前仍有 3 个高优先级问题需要处理**。

主要功能链路已有明显收敛：CKGDT 平台化命名在运行端基本完成；学生可以在系统设置进入 AI 配置并填写自己的 Key；实验、考核、作品的提交逻辑均为“先提交成功，再后台生成 AI 批阅草稿”，没有发现学生提交被 AI 预审阻断；归档模块已具备多格式导入、审核、预览、打印、归档和 zip 打包链路，且相关测试覆盖较完整。

原始剩余风险集中在三处：部分统计/通知兜底查询仍可能混入只属于归档班级的学生；Gitee 发布脚本仍硬编码旧版本；讯飞语音默认凭据仍写在代码里且没有发布开关。

## 修复记录

本报告形成后已针对三项高优先级问题完成修复：

- 归档班级隔离：`TwinService`、`NotificationDao`、`ClassroomDao`、`ClassDao`、管理员数据导出页已统一接入 `ActiveStudentScope` 或等效未归档班级过滤；新增 `active_student_scope_test.dart` 覆盖全体通知、无指定班级签到、班级待添加学生、批量同步学生到班级四个入口。
- Gitee 发布脚本：`scripts/gitee_create_release.py` 不再硬编码 `2.0.2`，改为从 `pubspec.yaml` 读取当前版本，也可通过 `GITEE_RELEASE_VERSION` 临时覆盖。
- 讯飞语音凭据：新增 `USE_BUILTIN_TRIAL_VOICE_KEYS` dart-define，默认保留课堂试用凭据，公开发布时可关闭内置凭据并要求用户在系统设置填写。

说明：`《移动应用开发》` 按项目要求继续作为默认课程保留；后续课程可在课程管理中创建或切换为 `《软件工程》` 及其它平台课程。

## 高优先级问题

### P1：归档班级隔离尚未全局收口（已修复）

项目已经新增 `ActiveStudentScope`，规则明确：学生活跃且未分班，或至少属于一个未归档班级，才应进入当前教学统计。该规则已用于学情分析、平时成绩、达成度、实验统计等关键链路，但仍有若干入口绕过了它。

证据：

- `lib/data/local/active_student_scope.dart:1` 定义了排除“只属于归档班级学生”的共享 SQL 条件。
- `lib/services/twin_service.dart:299` 班级人数仍直接统计 `users WHERE role='student' AND is_active=1`。
- `lib/services/twin_service.dart:771`、`lib/services/twin_service.dart:794`、`lib/services/twin_service.dart:816` 的学情预警仍直接从所有活跃学生中抽取。
- `lib/data/local/notification_dao.dart:55` 的 `targetType='all'` 会把通知发给所有活跃学生，未排除只属于归档班级的学生。
- `lib/data/local/classroom_dao.dart:238`、`lib/data/local/classroom_dao.dart:311`、`lib/data/local/classroom_dao.dart:644` 在 `classId == null` 兜底路径仍取所有活跃学生。

影响：

归档班级学生可能继续出现在数字孪生预警、群发通知、课堂兜底统计中。此前“学情分析/学情预警显示计科22归档学生”的问题在部分页面已经修复，但尚未形成全局保障。

建议：

统一将上述查询改为 `ActiveStudentScope.where(alias: 'u')`，并补一组回归测试：构造一个只属于归档班级的学生、一个属于未归档班级的学生、一个未分班学生，断言数字孪生预警、通知群发、课堂兜底列表均只包含后两类。

### P1：Gitee 发布脚本仍硬编码旧版本 2.0.2（已修复）

当前项目版本为 `2.1.0+1`，主发布服务和上传脚本已跟随 CKGDT 命名，但 `scripts/gitee_create_release.py` 仍会创建 `v2.0.2` release 并上传 `v2.0.2` 资产。

证据：

- `pubspec.yaml:4` 为 `version: 2.1.0+1`。
- `scripts/gitee_upload_assets.py:9` 使用 `v = '2.1.0'`。
- `scripts/gitee_create_release.py:5` 使用 `VER = '2.0.2'`。
- `scripts/gitee_create_release.py:30` 到 `scripts/gitee_create_release.py:32` 写死 `CKGDT+...+v2.0.2.zip`。

影响：

如果直接运行该脚本，会生成错误 tag、错误 release 名称，且大概率跳过或上传旧资产。发布材料会与当前 `2.1.0` 包不一致。

建议：

删除脚本内固定版本，改为从 `pubspec.yaml` 或 `BuildInfo.appVersion` 读取；资产路径使用同一个版本变量拼接。最好把 create release 和 upload assets 合并为一个只读当前版本的脚本，避免两处版本漂移。

### P1：讯飞语音默认凭据仍硬编码在代码中（已按课堂试用开关处理）

AI 课堂试用 Key 按用户要求保留，并且已有 `USE_BUILTIN_TRIAL_API_KEYS=false` 发布开关；但讯飞语音 AppID/APIKey/APISecret 仍以默认值形式写入 `SettingsService`，且用户未填写时自动回退到默认凭据。

证据：

- `lib/services/settings_service.dart:183` 到 `lib/services/settings_service.dart:185` 定义默认讯飞 AppID/APIKey/APISecret。
- `lib/services/settings_service.dart:188` 到 `lib/services/settings_service.dart:213` 在本地配置为空时返回默认值。
- 这条链路目前没有类似 `USE_BUILTIN_TRIAL_API_KEYS=false` 的发布期开关。

影响：

课堂内测可控，但公开发布会造成第三方语音服务凭据泄露和滥用风险。与 AI 试用 Key 不同，这个凭据没有显式“试用保留、发布关闭”的机制。

建议：

按 AI Key 的模式处理：新增 `USE_BUILTIN_TRIAL_VOICE_KEYS` 或直接移除默认值；系统设置仍保留讯飞参数输入。公开发布包必须要求用户自行填写语音凭据。

## 中优先级问题

### P2：教师 AI 批阅开关是本机设置，不是课程级同步设置

学生提交实验、考核、作品时会在学生端读取 `SettingsService.isTeacherAiGradingEnabled()`。这保证了学生本机默认可后台生成 AI 草稿，但教师在自己设备关闭“教师 AI 批阅”并不会天然同步到学生设备。

证据：

- `lib/presentation/pages/lab/tabs/task_list_tab.dart:757` 提交实验时读取本机开关。
- `lib/presentation/pages/assessment/tabs/report_tab.dart:855` 提交考核时读取本机开关。
- `lib/presentation/pages/works/tabs/work_detail_sheet.dart:97` 提交作品时读取本机开关。
- `lib/presentation/pages/home/settings_page.dart:184` 学生也能进入 AI 配置，但“教师 AI 批阅”开关仅教师/管理员可见。

影响：

如果后续要求“教师统一控制当前课程是否自动生成 AI 草稿”，目前实现不够。现在更像“各终端本机策略”。

建议：

若业务需要统一控制，应把该开关迁移为课程级配置表字段，并通过同步链路分发；如果保持本机策略，则建议 UI 文案改成“本机 AI 批阅策略”，避免教师误以为已统一控制全班。

### P2：平台化仍保留《移动应用开发》默认种子课程

产品品牌已经更新为 `CKGDT` / `课程知识图谱与数字孪生平台`，但默认课程和默认图谱仍是《移动应用开发》。这不属于品牌替换错误，更多是平台化阶段的默认数据策略问题。

证据：

- `lib/services/course_context_service.dart:8` 到 `lib/services/course_context_service.dart:24` 默认课程仍为 `mad` / `移动应用开发`。
- `lib/services/graph_import_service.dart:80` 到 `lib/services/graph_import_service.dart:88` 默认导入图谱标题和根节点仍为移动应用开发。
- `lib/presentation/pages/settings/course_manage_page.dart:9` 已有课程管理页面，说明多课程入口已经具备。

影响：

对于现有真实课程数据是合理兼容；但如果作为“多课程平台”首次交付，打开即看到移动应用开发种子课程，仍会让新用户误以为系统只面向该课程。

建议：

保留《移动应用开发》作为默认课程；后续新增《软件工程》等课程时，应通过课程管理独立创建课程、初始化课程目标和图谱，避免新课程复用默认课程的图谱、章节或归档材料。

### P2：部分文档链接与版本说明已漂移

运行端品牌搜索基本干净，但文档区仍存在历史名称、旧版本和失效链接。

证据：

- `docs/case_study/README.md:21` 和 `docs/case_study/PRD.md:59` 链接到不存在的 `docs/CKGDT审核报告(Opus4.7).md`。
- `docs/用户使用手册.md:15` 仍写 `v0.13.0` Windows 下载说明。
- `docs/答辩直播完整修复报告.md:139` 仍引用系统权限弹窗中的 `MAD-KGDT`。

影响：

不影响当前构建和测试，但会影响对外资料可信度，尤其是评审材料和案例集。

建议：

将历史报告链接改为实际存在的报告文件，或统一指向本轮/最新审核报告；用户手册中的版本号改为动态占位或当前 `2.1.0`。

### P2：Analyzer 仍有大量 info 级技术债

`flutter analyze --no-pub` 没有发现 error/warning，但因 1453 条 info 级提示返回非 0。主要是 Flutter 3.35 下的 `withOpacity`、颜色通道访问、少量大括号风格提示。

影响：

当前不阻断功能，但会让 CI 难以用 analyzer 作为硬门禁，也会掩盖未来真正的 warning/error。

建议：

短期保留当前“过滤 error/warning”的门禁；中期分批处理 `deprecated_member_use`，或在 `analysis_options.yaml` 中明确当前阶段的规则策略。

## 已通过链路

### 平台化命名

- `README.md`、`BuildInfo`、Android/iOS/Web/Windows/OHOS 显示名已更新为 CKGDT。
- 登录页指标已显示 `18` 个协作智能体。
- 运行端旧品牌搜索仅发现 QR 扫描保留 `MADKG` 兼容旧二维码，属于兼容策略。

### 学生 AI Key 与 AI 批阅

- `lib/presentation/pages/home/settings_page.dart:174` 所有角色均可进入“AI 配置”。
- `lib/presentation/pages/materials/ai_settings_page.dart:263` 显示个人 API Key 输入框，提示“留空则使用课堂免费 Key”。
- `lib/data/models/ai_config_model.dart:243` 起实现“用户 Key 优先、模型专用内置 Key 次之、服务商内置 Key 兜底”。
- `lib/services/ai_service.dart:56` 起在没有有效 Key 时给出配置提示。
- 默认 AI 配置入库时 `api_key` 为 `null`，不会把课堂试用 Key 写进 SQLite。

### 学生提交与后台 AI 草稿

- 实验：`submitTask()` 成功后才 `unawaited(AutoGradingService.instance.gradeLabSubmission(...))`。
- 考核：`submitReport()` 成功后才后台触发 `gradeAssessmentReport()`，PDF 文本解析失败不影响提交。
- 作品：`submitWork()` 成功后才后台触发 `gradeWork()`，视频路径同时写入 `video_url` / `file_path`。
- `AutoGradingService` 捕获 AI 异常并返回空，不删除提交、不阻断学生。

### 作品展示与评分一致性

- `WorksDao.isSubmittedStatus()` 统一识别 `已提交` / `已评分`。
- `WorksDao.hasVideoReference()` 使用 `video_url`、`file_path`、`repo_url` 三类证据判断是否可视作已提交。
- `cleanupFakeData()` 会清理无视频、无文件、无仓库的假提交，同时把有真实证据的草稿修正为已提交。
- `works_dao_test.dart` 覆盖“保留真实提交”和“教师评分角色识别”。

### 归档文档链路

- 期初、期中、期末和结课归档均已纳入 `archive` 页面内层 tab。
- `ArchiveTemplateSourceService` 支持模板目录识别，编号只作为人工排序参考，不作为唯一匹配条件。
- `ArchiveImporters` 覆盖 MHTML/HTML、XLSX、DOCX 文本抽取、调查问卷等解析。
- `PandocService` 支持 markdown/docx/pdf 转换，并在缺少 LibreOffice 时回退到原生 PDF。
- `ArchivePackageService` 支持单文档归档、整期 zip、全期合并 zip 和结课所选材料打包，且有去重逻辑。

## 验证结果

| 命令 | 结果 |
|---|---|
| `git status --short` | 本轮修复文件待提交；另有一个非本轮生成的 DeepSeek 第十三轮报告未跟踪 |
| `git diff --check` | 通过 |
| `flutter analyze --no-pub 2>&1 \| Select-String -Pattern " error -\| warning -"` | 无输出 |
| `flutter test` | 319 passed，2 skipped |
| `python -m py_compile scripts\gitee_create_release.py` | 通过 |
| `powershell -ExecutionPolicy Bypass -File scripts\preflight_windows_release.ps1` | 通过 |

## 后续建议

1. 明确“教师 AI 批阅开关”是本机策略还是课程级策略。
2. 保留《移动应用开发》为默认课程，同时完善后续《软件工程》等课程的创建、切换和图谱初始化流程。
3. 清理案例集、用户手册和历史文档中的失效链接、旧版本说明。
