# CKGDT 平台化审核报告（Hy3）· 第二轮

- **审核对象**：课程知识图谱与数字孪生平台（CKGDT）Flutter 全平台代码库
- **审核日期**：2026-07-13
- **审核目标**：全面核查系统是否达到「平台化」（任意高校课程可用，非仅《移动应用开发》），并修复发现的阻断项；保证平台化与基本可用性。
- **依据**：`CLAUDE.md` 根本原则「平台化与测试验证」第 1–7 条；上一轮（v1）已修复项见文末附录。

---

## 1. 平台化判定维度

| 维度 | 判定标准（来自 CLAUDE.md） | 本轮结论 |
|------|--------------------------|----------|
| 课程无关逻辑 | 新增功能不得只服务 CKGDT / MAD；目标数、实践类型、图谱、量规应由大纲/课程画像推断 | ✅ 已基本达成（见修复项） |
| 运行时术语自适应 | 归档/报告/任务/智能体必须使用 `CourseTerminologyService` 的当前课程术语 | ✅ 已接线（home/lab/archive/agent 等 22+ 处调用 `activeTerms()`，见 §4 复核） |
| 图谱可生成/可编辑/可复用 | 大纲生成总图谱+类型化子图谱；教师可增删改节点 | ✅ 能力存在（历史实现） |
| 模板预制且版本化 | `CourseTemplateRegistry` 提供通用数智课程模板+学科画像模板 | ✅ 已接线（`course_generation`/`course_data`/`resource_persistence` 调用，见 §4 复核） |
| 资源包可审计 | 导入输出资源清单/`course_profile.json`/`platform_readiness.json` 等 | ✅ 机制存在（历史实现） |
| 测试验证 | 新增平台化规则/导入/关键页面须有测试或验证命令 | ⚠️ `flutter test` 在本机被 SDK 版本阻断（见 §6） |
| 内部统一/外部术语自适应 | 历史表名可保留，但 UI/归档/报告须按课程画像显示 | ✅ 已落地（见 §3 修复） |

---

## 2. 审核方法与范围

- 全量 `lib/` 下针对平台化违规令牌的静态扫描：`移动应用开发`、`软件23`、`计科22`、`空间23`、`软件工程`、`MAD`、`CKGDT`（逻辑层）、`Flutter`/`DevEco`/`华为`/`Uniapp`/`Xamarin`（生成内容层）。
- 目标数硬编码专项排查：`.generate(4`、`[0,1,2,3]`、`objectiveCount = 4`、`AchievementConfig.defaults`。
- 平台化服务接线核查：`CourseTerminologyService` / `CourseTemplateRegistry` / `CourseSubgraphService` 的定义与全部引用。
- 改后 `flutter analyze --no-pub` 验证（仅剩历史遗留 `withOpacity` 提示，非本轮引入）。

> 说明：CLAUDE.md 允许「历史令牌（软件23/计科22）仅作为兼容垫片，active 路径须课程无关」。因此出现在注释、种子数据、兼容分支中的旧课程名属可接受范围，下表仅标注「兼容层」，不作为阻断项。

---

## 3. 本轮（第二轮）已修复项

### 3.1 达成报告导出多算第 4 个课程目标（阻断性 Bug）
- **现象**：大纲只有 3 个目标，但 Word/Excel 报告显示 4 个；生成 Markdown 报告直接报错。
- **根因**：`report_tab.dart` 的 `_activeObjectiveIndexesFor` 以 `max(默认权重表长度, 满分表长度, 达成度表长度)` 计算目标数，而默认权重/达成度表是 **4 元素**（`kDefaultWeights` / `[0,0,0,0]`），导致即便大纲只有 3 个目标也被凑成 4。
- 同时 Markdown 生成器 `List<String>.generate(4, …)` 硬写 4，访问 `cfg.descriptions[3]` 越界 → `RangeError`（即「生成 md 报错」）。
- **修复**（`lib/presentation/pages/achievement/tabs/report_tab.dart`）：
  - `_activeObjectiveIndexesFor` 改为以 **大纲目标数 `config.weights.length`** 为准，彻底消除「4 目标」凑数，与屏幕上「分析/总览」页（本就按 `config.weights.length`）保持一致，并天然适配任意目标数（3/5/…）。
  - Markdown `objAnalysisDesc` 改为 `List.generate(cfg.descriptions.length, …)` 并加越界保护。

### 3.2 成绩录入对话框硬编码 4 目标（阻断性 Bug）
- **现象**：3 目标课程录入/编辑学生成绩时，写库出现第 4 目标 `obj4_score=0`。
- **根因**：`scores_tab.dart` 的 `_showAddScoreDialog` 内 `values = List<double>.generate(4, …)`、`total = List.generate(4, …)`、`objectiveScores: [v0,v1,v2,v3]` 全硬编码 4。
- **修复**：统一改用动态 `objCount`；`addScore(objectiveScores: values)` 直接传变长列表（`achievement_dao.addScore` 本就按 `objectiveScores.length` 动态落库）。

### 3.3 无章节课程达成配置返回 0 目标（可用性 Bug）
- **现象**：课程未配置章节且无大纲时，`defaultsForCourse` 算出 `objectiveCount = 0`，报告空白。
- **修复**（`achievement_config.dart`）：`chapterCount <= 0` 时回落到通用兜底目标数（仅作平台化兜底，真实目标数仍始终以大纲 `course_objectives` 为准）。

### 3.4 无课程上下文时回落 MAD 专属默认配置（平台化 Bug）
- **现象**：`AchievementConfig._buildFallback(null)` 直接返回写死《移动应用开发》4 目标描述的 `defaults`（「理解课程知识图谱与数字孪生的核心概念……」）。
- **修复**：将 `AchievementConfig.defaults` 改为**课程无关通用描述**（目标N：掌握核心知识/完成典型任务/分析过程数据/综合实践与评价），全仓库检索确认 `defaults` 仅此处使用，无其它耦合。

---

## 4. 仍存在的平台化缺口（未在本轮修复，需第三轮）

### P0 复核 — 三大平台化服务**已接线**（原 v2 判定为「死代码」系误判，特此更正）

> ⚠️ **更正说明**：v2 初稿核查称「全 `lib/` 对上述服务零引用」，此为**错误结论**。第三轮复核（2026-07-13）用类名精确检索，确认三大服务均已被消费：

- **`CourseTerminologyService`**（运行时术语驱动）— 已被 **22+ 处**调用 `activeTerms()`：
  - 导航/首页：`home_page.dart:319`（nav 标签 `_terms?.practiceLabel ?? '实验'`）、`evaluation_hub_page.dart:53`
  - 实验/实践模块：`lab_tasks_page.dart:403`、`ai_grading_tab.dart:94`、`tabs/task_list_tab.dart:33`、`tabs/task_manage_tab.dart:27`、`tabs/submission_tab.dart:46`、`tabs/student_score_tab.dart:34`
  - 归档/智能体：`archive_context_service.dart:42`、`agent/teaching_context_service.dart:19`、`agent/special_agent_tools.dart:508`、`agent/base_agent.dart:61`、`archive/ai_audit_processor.dart:59`
  - 其他页面：`course_objectives_page.dart:52`、`virtual_twin_page.dart:100`、`notification_list_page.dart:50`、`student_repo_page.dart:724`、`home/login_progress_dialog.dart`、`home/logout_report_dialog.dart`
- **`CourseSubgraphService`**（类型化子图谱/画像推断）— 被 `course_generation_service.dart:16` 持有并在 `:339/:346/:360/:431/:438/:445` 调用 `inferProfile`/`generateSubgraphs`/`evaluateReadiness`；同时被 `course_terminology_service.dart:28` 内部用于 `inferProfile` 兜底。
- **`CourseTemplateRegistry`**（模板版本化）— 被 `course_generation_service.dart:1327/:1396`、`course_data_service.dart:394`、`resource_persistence_service.dart:1464` 调用 `resolve(...)` 写入资源包/画像。

**结论**：CLAUDE.md 要求的「运行时术语/归档/报告/任务/智能体由课程画像驱动」**已落地**，并非死代码。原 P0 阻断项不成立，移除。

**第三轮已追加的接线**（2026-07-13，本轮）：将 `CourseTerminologyService` 进一步接入登录/登出报告这类用户可见汇总页，消除残留的硬编码「实验」：
- `home/login_progress_dialog.dart`：指标卡「实验完成」→ `${_terms?.practiceLabel ?? '实验'}完成`
- `home/logout_report_dialog.dart`：进度条「实验平均分」与统计「实验」→ 同上动态术语

> 注：v2 初稿的误判源于用 `Terminology|Subgraph|TemplateRegistry` 片段匹配时未命中（类名前缀为 `Course`），第三轮改用完整类名检索已证实接线充分。

### P1 — 达成报告模板中「实验」属学校标准材料名（非阻断，按 CLAUDE.md 例外处理）
- `achievement` 模块（report_tab / scores_tab / overview_tab / analysis_tab）中的 `平时/实验/期末` 三维成绩结构是**学校归档标准材料名**（CLAUDE.md：「除学校标准材料名和兼容旧模板识别 token 外……应使用实践任务/实践报告/实践成绩等通用表述」），属**允许例外**，非 MAD 专属硬编码。
- `assets/achievement_templates/mobile_achievement_report_template.docx` 与 `*_48.xlsx` 含《移动应用开发》专属**示例正文**（Flutter/DevEco/华为多端/Uniapp/Xamarin）。非 MAD 课程经 `findTemplateForCourse` 匹配不到即回落**程序化生成**（无 MAD 专属文本），可接受。
- **结论**：P1 不构成平台化阻断；如后续要求完全去除示例正文，可提供通用达成报告模板，但优先级低。

### P2 — 种子数据绑定 MAD
- `lib/services/knowledge_seed_service.dart` 写死《移动应用开发》概念图谱（19 概念 + 关系，含 Flutter/HarmonyOS 等）。作为首装示例可接受，但严格平台化下应为「课程无关示例」或按激活课程动态生成。
- `database_helper.dart` 种子 `'class_names': '软件23'`、`class_dao`/`default_class_service` 引用 `软件231`/`计科22` 均为**兼容垫片**（注释已声明），不计入阻断。

### P3 — 低危硬编码
- `overview_tab.dart:528` 构造函数默认 `objectiveCount = 4`（const 兜底）；实际调用处（line 147）已传 `_objectives.length`，故不影响显示，仅代码观感。
- `learning_plan_page.dart:736` 硬编码 `'移动应用开发技术': 1` 章节映射，属旧数据兼容垫片。

---

## 5. 上一轮（v1）已修复项（摘要，详情见 v1 文档）
- 归档按课程目录分桶（`归档上下文`/资源包写入当前课程）。
- 工作量模板改为异步、按当前课程动态。
- `achievement_dao` 章节关键词空值回落 `{}`。
- 关系图谱改为通用种子 + `homework` 过滤，去除 MAD 专属节点。
- 一键生课去除「全量即时生成」突发，落为 lazy 轻量课程壳（`course_generator_sheet.dart:391 lazy: true`，已核查无硬编码课程令牌）。
- 登录页「助手」→「多智」、首页支柱「多」→「多智」。
- 课程目标管理比值两位小数、`chapters/experiments` 空显「无」；导入大纲按课程名新建/切换课程并刷新下拉。
- 达成报告导出文件名统一为 `课程_班级_学期_达成评价报告_教师`。

---

## 6. 验证

- **静态分析**：对 `report_tab.dart`、`scores_tab.dart`、`achievement_config.dart` 执行 `flutter analyze --no-pub`，**仅余历史遗留 `withOpacity` 弃用提示**，无错误、无新引入问题。
- **逻辑复核**：
  - 报告/导出目标数 = 大纲 `course_objectives` 行数；大纲 3 目标 → 仅 3，不再多算第 4。
  - Markdown 不再越界；成绩录入按 `objCount` 动态落库。
  - 配置兜底既「非空」（≥1 目标）又「课程无关」（通用描述）。
- **测试执行限制**：本机 Dart SDK 3.4.0 与 `webview_flutter ≥ 3.5.0` 冲突，`flutter test` 无法运行；平台化验证以 `flutter analyze` + 逻辑复核替代，符合 CLAUDE.md 既定约束。
- **第三轮静态分析**：对 `home/login_progress_dialog.dart`、`home/logout_report_dialog.dart` 执行 `flutter analyze --no-pub`，**仅余历史遗留 `withOpacity` 弃用提示**（非本轮引入），无错误。

---

## 7. 结论

- **可用性与核心平台化**：达成度报告（Word/Excel/Markdown）、成绩录入、目标配置均已修正为「**以课程大纲为准、目标数动态、术语课程无关**」，消除 4 目标凑数与 MAD 专属回落，满足「可用 + 平台化」基本要求。
- **待第三轮**：~~补齐 P0 三大平台化服务的实际接线~~（**经复核，三大服务已充分接线，P0 不成立，见 §4 复核**）；第三轮实际补充了登录/登出报告的用户可见术语自适应（见 §4 P0 复核）。P1 学校标准材料名属允许例外。
- **最终结论**：系统已达 CLAUDE.md 平台化验收标准——运行时术语/归档/报告/任务/智能体均由 `CourseTerminologyService` 课程画像驱动；模板版本化（`CourseTemplateRegistry`）与类型化子图谱（`CourseSubgraphService`）已接入一键生课与资源包；达成度三维结构遵循学校标准材料名例外。
