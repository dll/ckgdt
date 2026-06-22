---
title: MAD-KGDT 课程知识图谱与数字孪生平台审核报告
date: 2026-06-22
reviewer: GPT5.5 第二轮
target: D:\FlutterProjects\knowledge_graph_app
head: 47bbe09 完善平时成绩统计与学生成绩入口
version: 2.0.3+1
scope: 第二轮全项目横切审核，重点覆盖第一轮后大改动：作品提交/播放/批阅链路、考核终稿审核打印、达成报告导出、平时成绩、学生成绩入口、课程目标、同步与发布门禁
reference: docs\MAD-KGDT审核报告(GPT5.5-第一轮).md
---

# MAD-KGDT 审核报告（GPT5.5-第二轮）

## 一、结论

第二轮审核时，项目已经从第一轮的“外测前修复期”继续推进到更完整的教学评价闭环。全量测试已经从第一轮失败状态改善为通过，达成模块、考核终稿、作品视频链路、平时成绩和学生成绩入口都有实质性进展。

当前不建议直接打正式发布包。主要拦截点从“测试失败”转移为“发布构建验证、同步闭环和新成绩体系的数据一致性”。其中最需要优先处理的是作品教师评分回传学生端不完整、平时成绩部分数据源未同步或未按课程隔离、Windows release 构建本轮被运行中应用锁文件阻断。

如果目标是校内继续试用：可以作为候选版本继续演示，但应明确“作品成绩回传、平时 AI 学习量、Windows 打包复测”为已知风险。如果目标是公开发布或大规模外测：需要先修复 P0/P1 项并重新跑构建。

## 二、审核基线

| 项目 | 本轮实测 |
| --- | --- |
| 当前日期 | 2026-06-22 |
| Git 分支 | `master` |
| HEAD | `47bbe09` |
| 上游 | `origin/master`，本地与远端一致 |
| 工作区 | 仅有未跟踪 `docs/开发笔记/Codex问题.md`；本报告为本轮新增 |
| 应用版本 | `2.0.3+1` |
| Dart 源码规模 | `lib` 下 385 个 Dart 文件 |
| 页面规模 | `lib/presentation/pages` 下 159 个 Dart 文件 |
| 服务规模 | `lib/services` 下 131 个 Dart 文件 |
| DAO 规模 | `lib/data/local` 下 34 个 DAO 文件 |
| 数据库版本 | `DatabaseHelper` 打开版本 `31` |
| 数据表规模 | `database_helper.dart` 中 67 个 `CREATE TABLE IF NOT EXISTS` 去重表定义 |
| 测试规模 | `test` 下 40 个 Dart 测试文件 |

## 三、验证结果

### 3.1 静态分析

命令：

```powershell
flutter analyze
```

结果：失败，发现 78 个 issue。

其中只有 1 条 warning：

- `lib/presentation/pages/lab/tabs/task_list_tab.dart:875`：`_triggerAiGradingDraft` 未被引用。

其余主要是 info 级别：

- Flutter/Dart API deprecated，如 `Color.alpha/red/green/blue`、`Radio.groupValue/onChanged`、`Matrix4.scale/translate`。
- 多处 `use_build_context_synchronously`。
- 少量 `curly_braces_in_flow_control_structures`。

判断：静态分析相比第一轮 564 个 issue 明显收敛，但仍不是发布级门禁。至少应清掉 warning，并逐步处理 `BuildContext` async gap。

### 3.2 全量测试

命令：

```powershell
flutter test
```

结果：通过。

摘要：`+280 ~2: All tests passed!`

第一轮失败的 `test/widgets/home_page_widget_test.dart` 已通过。新增的平时成绩 DAO 测试也通过，说明平时成绩的基本聚合公式、20/30/50 展示和达成度百分制输出已有回归保护。

### 3.3 Windows release 构建

命令：

```powershell
flutter build windows --release
```

结果：失败，但失败原因是本机正在运行的应用锁住了 release 目录中的 WebView2 DLL。

关键日志：

- 进程：`课程图谱与数字孪生v2.0.3 (PID 32628)`
- 被锁文件：`build\windows\x64\runner\Release\WebView2Loader.dll`
- MSBuild 错误：`MSB3027` / `MSB3021`，复制 `WebView2Loader.dll` 超出重试次数。

判断：本轮不能声称 Windows release 构建通过。需要关闭正在运行的应用后重新构建；这不是明确的源码编译错误，但仍是发布门禁未通过。

### 3.4 依赖状态

`flutter` 输出显示：

- 1 个包 discontinued：`flutter_markdown` 已提示替代包。
- 91 个包存在与当前约束不兼容的新版本。

判断：短期不构成阻塞，但 Flutter 3.32+ 相关 deprecated API 已开始出现在 analyzer 输出中，后续升级 Flutter 时会放大维护成本。

## 四、第一轮问题回归

| 第一轮问题 | 第二轮状态 |
| --- | --- |
| 全量测试失败 | 已改善。`flutter test` 全量通过 |
| Windows release 构建未验证 | 仍未通过。本轮失败原因是运行中应用锁定 DLL |
| 内置 AI key / Gitee token 发布治理风险 | 仍存在。当前仍有默认 DeepSeek key 和共享 Gitee token 设计 |
| 答辩直播局域网端点无鉴权 | 未见本轮根治，仍建议 session token |
| 平台化内容资产强绑定《移动应用开发》 | 部分改善，新增课程目标模块；资产和 prompt 仍需继续课程化 |
| 归档处理器清单漂移风险 | 第一轮后已有测试覆盖部分 registry，但归档资料清单与处理器清单仍建议 SSOT 化 |
| 结课归档 filePath-only 文档漏出 | 未作为本轮重点验证，仍需专项确认 |
| 达成无实验课程仍显示实验达成 | 已改善。`AchievementPage` 会按课程目标 `experiment_ratio` 动态隐藏实验达成 Tab |
| AI 课件生成 warning / 测试不足 | 部分 analyzer warning 已下降，但 AI 课件生成仍缺更细测试 |

## 五、关键发现

### P0-1 Windows release 构建本轮未通过，正式发布门禁仍未闭合

位置：构建链路

现象：`flutter build windows --release` 在 282.7 秒后失败。MSBuild 无法覆盖 `WebView2Loader.dll`，文件被运行中的 `课程图谱与数字孪生v2.0.3 (32628)` 锁定。

影响：当前不能确认 Windows release 包可重新构建。第一轮已经指出 Windows 是核心交付端，本轮仍没有获得通过结论。

建议：

1. 关闭正在运行的 `课程图谱与数字孪生v2.0.3`。
2. 重新执行 `flutter build windows --release`。
3. 构建通过后做启动、登录、学习、实验、考核、作品、达成、归档的冒烟验证。
4. 发布脚本增加构建前检查：如果 release 目录 DLL 被当前应用进程锁定，提前提示而不是等 MSBuild 重试失败。

### P1-1 作品教师评分 / AI 批阅评分不能可靠回传到学生端

位置：

- `lib/presentation/pages/works/ai_grading_tab.dart:556`
- `lib/presentation/pages/works/tabs/work_detail_sheet.dart:1358`
- `lib/services/sync_service.dart:641`
- `lib/data/local/works_dao.dart:438`

问题：

1. 作品 AI 批阅通过后取 `work['student_id']`，但 `student_works` 主字段是 `user_id`，`WorksDao` 也一直用 `user_id`。因此 `studentId` 大概率为 null，通知和后续回传动作不会触发。
2. 作品手动评分路径只调用 `WorksDao.scoreWork()`，没有通知学生，也没有把学生数据重新上传。
3. 即便补上 `uploadStudentData(studentId)`，当前同步收集 `work_scores` 的逻辑只收集 `scorer_id == userId` 的记录，也就是学生作为评分人的互评记录；教师/admin 对该学生作品的评分记录不会进入该学生 JSON。

影响：学生端新增“作品 → 成绩”Tab 后，教师已经评分的作品仍可能显示未评或只有状态更新，没有教师分数和评语。这与用户此前截图里的“有提交、有批阅、分数/播放矛盾”是同类数据链路问题。

建议：

1. AI 批阅通过处改用 `work['user_id']`。
2. 手动评分和 AI 批阅通过后统一调用通知与同步。
3. 同步协议需要增加“作品归属人维度的教师评分”：
   - 上传学生 JSON 时，包含 `work_scores` 中 `work_id` 属于该学生作品且评分人为 teacher/admin 的记录；或
   - 将教师总分、评语、评分时间冗余写入 `student_works` 的稳定字段，再同步学生作品行。
4. 增加回归测试：教师评分作品后，导出学生同步数据，再导入学生端，`WorksDao.getWorks(userId:)` 必须能读到教师分数。

### P1-2 平时成绩“AI 自主学习 / 推荐收藏”数据源未完整同步，教师端统计会低估

位置：

- `lib/data/local/ordinary_score_dao.dart:410`
- `lib/data/local/ordinary_score_dao.dart:429`
- `lib/services/sync_service.dart:558`
- `lib/services/sync_service.dart:1054`

问题：平时成绩的课外学习项读取了 `ai_chat_history` 和 `hot_video_favorites`，但学生同步包目前没有收集/导入这两张表。同步包收集的核心表包括 `learning_records`、`quiz_results`、`checkin_records` 等，不含 AI 聊天历史和推荐视频收藏。

影响：如果学生在自己设备上大量使用 AI 自主学习或收藏推荐视频，教师端“平时成绩”汇总可能看不到这些行为，导致课外学习 50 分中的相关权重长期偏低。学生本机“学习 → 成绩”看到的分数与教师端统计也可能不一致。

建议：

1. 将 `ai_chat_history` 中当前用户的 assistant 记录纳入学生同步包。
2. 将 `hot_video_favorites` 纳入学生同步包，或把推荐视频学习统一沉淀到 `learning_records` 后只以 `learning_records` 为准。
3. 给 `ai_chat_history` 增加 `course_id`，否则新课程之间 AI 学习量无法隔离。
4. 增加测试：学生端产生 AI 记录和推荐收藏后，上传/下载同步包，教师端 `OrdinaryScoreDao.loadSnapshot()` 的 AI/推荐指标应一致。

### P1-3 平时成绩“课堂表现”没有按课程隔离，平台化后会串课

位置：

- `lib/data/local/ordinary_score_dao.dart:262`
- `lib/data/local/ordinary_score_dao.dart:272`
- `lib/data/local/ordinary_score_dao.dart:298`
- `lib/data/local/ordinary_score_dao.dart:312`
- `lib/data/local/classroom_dao.dart:43`
- `lib/data/local/classroom_dao.dart:81`

问题：平时成绩课堂表现直接从 `roll_call_records`、`checkin_records`、`classroom_messages` 汇总，查询没有当前课程过滤。课堂表本身也主要按 `class_id/session_id/user_id` 组织，缺少稳定 `course_id`。同时 `OrdinaryScoreDao` 自己创建课堂表结构，和 `ClassroomDao` 对同名表的结构保障重复。

影响：只要平台同时服务多个课程，同一个学生在其它课程中的点名、签到、课堂回答都可能计入当前课程的“课堂表现”。这会直接影响达成度中的平时成绩。

建议：

1. 课堂会话表增加 `course_id`，`roll_call_records/checkin_records/classroom_messages` 通过 session 或字段可追溯课程。
2. `OrdinaryScoreDao._loadClassroomMetrics()` 按当前课程过滤。
3. 课堂相关表结构只由 `ClassroomDao` 或数据库迁移层维护，`OrdinaryScoreDao` 不再重复定义业务表，只创建自己的 `ordinary_score_settings`。
4. 增加多课程测试：同一学生在课程 A 与课程 B 有课堂记录，切换当前课程后只统计当前课程。

### P1-4 实验“学生提交后台触发 AI 批阅草稿”代码未接入

位置：`lib/presentation/pages/lab/tabs/task_list_tab.dart:875`

问题：`_triggerAiGradingDraft` 的注释说明“学生提交后台触发 AI 批阅草稿”，但 analyzer 显示该方法未被引用。也就是说学生提交实验后，不会自动生成待教师审核的 AI 批阅草稿。

影响：如果产品预期是“学生一提交，教师 AI 批阅 Tab 就有 pending 草稿”，当前实现不满足；教师仍需要手动批量或单条触发 AI 批阅。用户看到“AI 批阅有结果但分数未更新”的场景也需要避免这种半链路状态。

建议：

1. 明确产品策略：学生提交后是否自动生成 AI 草稿。
2. 如果需要自动草稿，在提交成功后调用该方法，并只写 `grading_results.status='pending'`，不直接写正式分数。
3. 如果不需要自动草稿，删除该方法和误导性注释，清掉 analyzer warning。
4. 增加测试：提交实验后 pending 草稿数量符合预期；教师审核通过后才回写 `lab_submissions.score`。

### P1-5 内置 AI key 与共享 Gitee token 仍是发布治理风险

位置：

- `lib/data/models/ai_config_model.dart:30`
- `lib/data/local/database_helper.dart:839`
- `lib/data/local/database_helper.dart:1996`
- `lib/core/constants/app_urls.dart:21`
- `lib/services/sync_service.dart:50`

现状：项目仍保留默认 DeepSeek key 和共享 Gitee 同步 token 设计。第一轮已经说明：用户要求为新用户保留开箱即用能力，因此本报告不建议简单删除，而建议治理。

影响：校内课堂分发可接受，但公开仓库、公开安装包、公开 release 会扩散凭据。同步 token 如果具备写权限，还会影响学生数据仓库安全。

建议：

1. 将共享 key/token 明确标注为“课堂试用版凭据”，不要写“正式发布时移除”这类与产品策略冲突的注释。
2. 给共享 key/token 做额度限制、轮换、日志和禁用开关。
3. 对公开发布包使用服务端代理或首次启动引导配置，不直接内置高权限 token。

### P2-1 内层 Tab 注册表测试已漂移，不能完全守护新增成绩 Tab

位置：

- `lib/core/constants/inner_tab_registry.dart:27`
- `lib/core/constants/inner_tab_registry.dart:42`
- `lib/core/constants/inner_tab_registry.dart:54`
- `test/core/inner_tab_registry_test.dart:20`
- `test/core/inner_tab_registry_test.dart:26`
- `test/core/inner_tab_registry_test.dart:30`

问题：注册表已经加入 `works` 的“成绩”、`lab` 的“成绩”、`learning` 的“成绩/平时成绩”，但测试里的 `pageDeclaredLabels` 仍是旧清单。测试目前只检查“测试清单中的 label 是否登记”，没有检查“注册表新增 label 是否真的来自页面声明”，所以仍然通过。

影响：语音导航和内层 Tab 注册表的 SSOT 测试可信度下降。未来新增/改名 Tab 时，测试可能漏报。

建议：

1. 更新测试清单，加入新增成绩 Tab。
2. 增加反向断言：注册表中的角色相关 label 必须被测试清单覆盖，或从页面静态常量导出真实 labels，避免手抄。

### P2-2 平时成绩指标设置已有功能，但需要更强的业务边界提示

位置：

- `lib/presentation/pages/learning/ordinary_score_tab.dart`
- `lib/data/local/ordinary_score_dao.dart`

现状：教师端“平时成绩”可以设置课堂表现、期间测验、课外学习的主权重和细项权重，并同步达成度。

风险：当前主权重保存时会归一化到 100，这符合达成度总分，但 UI 上如果教师把三项改成非 100 的组合，保存后数值会被归一化，可能与教师直觉不一致。

建议：保存前显示“将按 100 分归一化”的提示，或将主权重输入限制为课堂 20、测验 30、课外 50 的默认框架，只允许调细项权重。

## 六、模块审核

### 6.1 首页、课程目标与平台化

本轮新增“课程目标”首页公共模块，教师、学生、管理员均可见，内容覆盖课程目标与毕业要求支撑关系，并补充平时/实验/考核评价方式。方向正确，能把达成度计算的依据显性化。

风险仍在平台化深层：课程目标页面目前是移动应用开发课程的静态内容，适合当前课程，但如果切换到其它课程，需要从 `courses/course_objectives` 或大纲解析结果动态读取，否则会出现“课程已切换但目标仍是移动应用开发”的情况。

### 6.2 学习与平时成绩

学习中心新增教师“平时成绩”和学生“成绩”Tab，课堂表现 20、期间测验 30、课外学习 50 的框架已经落地。`OrdinaryScoreDao` 的单测覆盖了核心聚合。

主要风险是同步与课程隔离：AI 自主学习、推荐收藏、课堂互动目前不是完整的课程化/同步化数据源。短期可用作移动应用开发单课程统计，长期要补 course_id 和同步协议。

### 6.3 实验

学生实验页面新增“成绩”Tab，能读取实验提交统计和得分明细；实验报告、AI 批阅、教师评分链路也已经比第一轮更完整。

需要处理的点是 `_triggerAiGradingDraft` 未接入。实验 AI 批阅应明确是“教师触发”还是“学生提交自动生成待审核草稿”，避免 UI 文案和数据状态不一致。

### 6.4 考核

考核终稿审核打印流程已有独立提交：`0ebe984 完善考核终稿审核打印流程`。学生端成绩匹配也已补 `member_ids/member_names` 查询，能解决小组成员成绩找不到的问题。

后续建议继续补端到端测试：学生提交终稿、教师不通过并给建议、学生重提、教师通过、进入打印、标识打印状态。这个流程比单纯四个子报告整合更接近用户需求，也更容易在状态机上出错。

### 6.5 作品

作品提交/播放链路已连续修复，`WorksDao.hasVideoReference()`、旧数据修复、播放前补同步等方向正确。提交、播放、评论、点赞、排行都已有更完整的数据链路。

当前剩余最大风险是评分回传：作品分数存在 `work_scores`，学生作品行只存状态和基础信息；同步协议没有把教师评分作为“作品归属人的成绩”回传。新增学生“作品 → 成绩”Tab 后，这个问题会直接暴露给学生。

### 6.6 达成与报告

达成模块在第一轮后有显著进步：

- Word/Excel/图表相关测试通过。
- 无实验课程实验 Tab 动态隐藏。
- 平时成绩可以从平台数据同步到达成度批次。
- 问卷通知可以打开学生问卷页面。

风险在于平时成绩作为新增达成数据源还不够稳定。建议先把同步、course_id、课堂数据隔离补齐，再把它作为达成度正式批次数据的默认来源。

### 6.7 归档

归档相关测试继续通过，Pandoc 可用，LibreOffice 缺失时 PDF 测试能跳过并提示。第一轮提到的处理器注册清单漂移风险仍建议继续治理。

### 6.8 直播与跨设备

本轮未做实机直播矩阵。第一轮关于局域网端点鉴权、UDP 发现、HTTP/MJPEG 明文访问的风险仍然成立。项目已经有基础测试覆盖 MJPEG 分片解析，但真实网络环境仍需验收。

## 七、发布前建议清单

### 必须完成

1. 关闭当前运行中的 Windows 应用，重新执行 `flutter build windows --release` 并保存成功日志。
2. 修复作品评分回传链路：`user_id` 字段、手动/AI评分通知、同步协议中的教师评分。
3. 补齐平时成绩依赖的数据同步：`ai_chat_history`、推荐收藏或统一学习记录。
4. 给课堂表现数据增加课程隔离，避免多课程串分。
5. 清理 analyzer 唯一 warning：未引用的 `_triggerAiGradingDraft`。

### 建议完成

1. 更新 `inner_tab_registry_test.dart`，让新增成绩 Tab 也被测试守护。
2. 平时成绩设置保存前提示归一化规则。
3. 课程目标页面改为优先读取当前课程大纲/课程目标表，静态内容仅作为移动应用开发默认模板。
4. 对考核终稿审核打印做端到端状态测试。
5. 继续治理内置凭据：额度、轮换、禁用开关、发布环境区分。
6. 答辩直播端点增加一次性 session token。

## 八、最终判断

第二轮相较第一轮，项目质量有实质提升：全量测试已通过，达成、作品、考核、平时成绩和课程目标都形成了更完整的教学闭环。

当前最核心的问题不是“功能有没有入口”，而是“入口后的跨设备数据是否一致”。作品成绩和平时成绩是新近大改动的重点，必须把同步和课程隔离补上，否则教师端、学生端、达成度报告三处会出现不同分数。

建议下一轮修复优先级：

1. 作品评分回传学生端。
2. 平时成绩同步与课程隔离。
3. Windows release 构建复测。
4. Analyzer warning 清零。
5. 考核终稿审核打印端到端测试。

