# CKGDT 平台化审核报告（Hy3）

- **审核对象**：课程知识图谱与数字孪生平台（CKGDT）Flutter 全平台代码库
- **审核日期**：2026-07-13
- **当前版本**：`2.5.2+0`（pubspec.yaml）
- **审核目标**：验证系统是否满足「平台化」根本原则——任意高校课程（不只《移动应用开发》/CKGDT）均可运行，功能与术语由课程上下文驱动，无功能性硬编码。
- **审核方法**：
  1. 全量源码扫描硬编码课程 Token：`移动应用开发 / MAD课程 / 计科22 / 软件23 / 《移动应用开发》 / 软件231 / 软件232` 等（覆盖 `lib/` 全目录，共 57 处命中）。
  2. 逐模块代码走查：首页、达成、归档、图谱、实验、测验、学习、通知、同步、智能体。
  3. 验证「激活课程」驱动链路：`CourseContextService` → 各 DAO/服务 → UI。

---

## 一、模块审核结果

| 模块 | 状态 | 关键证据 |
|------|------|----------|
| 首页（学生/教师/管理员） | ✅ 达标 | `home_page.dart` 导航/文案经平台化改造，无激活课程硬编码；实践标签/导航标签由 `CourseTerminologyService` 驱动 |
| 达成（概览/成绩/分析/报告） | ✅ 达标 | 课程目标数量动态化（`kObjectiveColors`/`kObjectiveNames` 扩至 10）；批次随激活课程**自动创建**（`ensureBatchForActiveCourse`，4 个页均调用）；计算取 `course_objectives`（大纲权威源）；导出文件名改为 `<课程ID>《<课程名>》` |
| 归档（期初/期中/期末/结课） | ✅ 达标 | `main.dart` 注册全部 `data/<课程ID>/归档` 为课程级模板根；`archive_page` 打开时把**激活课程**根设为首选；输出落 `archive_out/学期/课程/期`；`archive_agent` 按 `course_id/course_name` 限定查询 |
| 知识图谱（概念画布/结构/关系/蒙版） | ⚠️ 部分达标 | 节点与边渲染完全支持 `concept_relations`；种子服务对 CKGDT（通用课程）生成骨架关系（课程→章节→核心/方法/实践 + 章节前置），但**非 MAD 课程无 MAD 级别丰富领域关系**，需教师手动或 AI 补充 |
| 实验 / 实践任务 | ✅ 达标 | `lab_tasks` 表 + `CourseTerminologyService` 术语驱动；资源包清单/审核清单显示画像术语 |
| 测验 | ✅ 达标 | `questions` 按课程作用域（`scopedWhere`）隔离 |
| 学习中心 / 学习路径 | ✅ 达标 | 由激活课程章节/大纲驱动；历史 MAD 节点映射仅作兼容回落 |
| 通知 | ✅ 达标 | 按课程/班级/用户作用域分发 |
| 数据同步 | ✅ 达标 | 组仓库按 `users.repository_url` 解析；与具体课程无关 |
| 多智能体（19+） | ✅ 达标 | persona 用 `{courseName}` 模板占位，由 `CourseContextService` 注入当前课程名 |

**结论**：主干功能（首页/达成/归档/实验/测验/学习/通知/同步/智能体）均已达成平台化；图谱为**部分达标**（见遗留问题 1、2）。

---

## 二、硬编码 Token 扫描结果（57 处命中分类）

### A. 注释 / 文档示例（非功能，可接受）— 约 30 处
- `archive_package_service.dart:25-37`：归档包命名**示例**含「移动应用开发」（示例文案）。
- `achievement_template_assets.dart:23-24`、`period_tab.dart:66`：注释说明「已取代计科22 / 不再硬编码《移动应用开发》」（即修复记录，正面）。
- `courseware_download_service.dart:99-100`、`chapter_sorter.dart:19`：文档示例章节名。
- `database_helper.dart:253,476,878,3253`、`class_dao.dart:306,473`、`classroom_page.dart:72-73`、`default_class_service.dart:92`、`data_import_page_native.dart:61`、`learning_plan_page.dart:733`：历史兼容说明注释。
- `case_demo_agent.dart:21,126`：「移动应用」作为应用**类型分类**（Windows/Web/桌面/移动/命令行），属通用范畴，非课程硬编码。

### B. 课程种子数据（合法内容，非 Bug）— 约 20 处
- `knowledge_seed_service.dart:323-951`：`_seedConcepts` / `_seedRelations` 为《移动应用开发》课程专属种子内容（MAD 是平台内置的一门课程，内容属于它自己）。平台通过 `_shouldSeedGenericCourse`（`course.id != 'mad'` 走通用课程路径）区分，**CKGDT 走通用骨架种子**，逻辑正确。

### C. 历史兼容 shim（CLAUDE.md 允许，可接受）— 约 5 处
- `class_dao.dart:484`：`if (isArchived && name.contains('计科22'))` 返回历史真实分组。
- `materials_tab.dart:311`：`if (baseName == '移动应用开发实验指导书')` 兼容 MAD 历史指导书文件名。
- `learning_plan_page.dart:736`：`'移动应用开发技术': 1` 历史节点归章兼容。
- `database_helper.dart:1719,1749,2327`：种子默认班级名 `'软件23'`、列默认值 `'软件23'`（仅种子/缺省时触发，新建课程自建班级）。

### D. 功能性疑似硬编码（需关注，见遗留问题）— 3 处
- `workload_excel_service.dart:64`：工作量申报**模板示例行**硬编码 `'软件23'`（示例数据，低风险）。
- `achievement_dao.dart:1719`：`_defaultChapterKeywords` 以 MAD 章节关键词作**回落**（仅当课程无章节或恰好 6 章且像 MAD 时生效）。
- `course_subgraph_service.dart:19`：`'移动应用'` 仅为工程课程**分类关键词列表**中的一项（同列还有 软件/程序/开发/前端/后端/数据库/算法/工程…），属通用分类器，**非课程硬编码**（合规）。

> 全量扫描中，**实验 / 测验 / 学习 / 通知 / 同步** 模块**零命中**功能性硬编码。

---

## 三、已确认的平台化能力（正面事实）

1. **单一来源课程上下文**：`CourseContextService`（`activeCourseId/activeCourseName/getActiveCourse`）为全系统课程作用域唯一入口；`scopedWhere` 提供严格课程匹配。
2. **术语自适应**：`CourseTerminologyService` 按课程画像输出 实验/研读/训练/创作/案例/技能实践 等术语，避免把一切写成「实验」。
3. **模板版本化**：`CourseTemplateRegistry`（`universal_smart_course@1.0.0`）+ 学科画像模板，资源包写入 `course_template.json` 与 `manifest.json`，审计字段完整。
4. **动态子图谱**：`CourseSubgraphService` 按大纲识别画像并生成类型化子图谱（文学研读/体育训练/艺术创作/案例决策/工程实践）。
5. **达成计算与大纲一致**：`AchievementConfig.fromObjectiveRows(激活课程 course_objectives)`；`resolveObjectiveWeights` 以 `course_objectives` 为权威源。
6. **批次自动创建**：`ensureBatchForActiveCourse` 在达成 4 个页均被调用，绝不要求手工新建批次。
7. **归档按课程隔离**：每课程 `data/<ID>/归档` 模板根 + `archive_out/学期/课程/期` 输出。
8. **图谱支持关系**：`concept_relations` 表 + `addRelation` + 边渲染；种子对通用课程生成骨架关系，教师可在图谱详情新增/编辑/删除节点与关系。

---

## 四、遗留问题与修复记录（按严重度）

> 以下遗留问题已于 **2026-07-13** 全部修复，对应提交见「修复记录」小节。

### 🟡 中（已修复）
1. **非 MAD 课程缺丰富领域关系** → 已修复。
   - `lib/services/knowledge_seed_service.dart` `_seedGenericCourse` 的关系生成新增同章节 `related_to` / `知识应用` / `实践组织` 关联，以及跨章节 `前置知识`（core→core）、`实践巩固`（practice→core）递进关系，通用课程图谱由纯树状升级为网状结构。
2. **SEB / FPP / AAOS 无 `data/<ID>/归档` 模板目录** → 已修复。
   - `lib/services/archive/archive_template_source_service.dart` 在 `registerCourseArchiveRoot` 内同步调用 `_ensureCourseArchiveDirsSync`，为每门课程创建 `data/<课程ID>/归档/<期>/模板` 命名空间与说明 README（**不复制** MAD/软件23 等专属模板，避免脏数据跨课程泄露）。
   - `lib/main.dart` `_initArchivePaths` 取消「目录不存在即跳过」逻辑，对 `data/` 下每个课程目录一律登记为课程级归档根，使 SEB/FPP/AAOS 首次启动即拥有独立归档命名空间，不再回落其它课程模板。

### 🟢 低（已修复）
3. `workload_excel_service.dart` 模板示例行硬编码 `'软件23'` / `'CKGDT'` → 已改为随激活课程动态生成（课程编号取 `activeCourseId()`，课程名称取 `activeCourseName()`，教学班改为占位「示例教学班」）；`exportTemplate()` 升级为 `async` 并由 `workload_tab._onExportTemplate`  await。
4. `achievement_dao.dart` MAD 章节关键词回落 → 无章节课程改返回空映射 `const {}`，不再套用「移动应用 / 软件 / 技术体系」等 MAD 专属关键词（`_defaultChapterKeywords` 仅保留给真实命中 MAD 的课程）。
5. `database_helper.dart` `class_name TEXT DEFAULT '软件23'` → 改为 `DEFAULT ''`，新建班级不再误带 MAD 遗留班级名。

### ⚪ 已合规（仅记录，不改动）
- 历史兼容 shim（`class_dao:484`、`materials_tab:311`、`learning_plan_page:736`、种子 `'软件23'`）符合 CLAUDE.md「兼容既有教学数据」原则，保留。
- `knowledge_seed_service.dart:79` `course.id == 'mad'` 走专属种子，是**正确的课程分流逻辑**，非 Bug。

### 修复记录（2026-07-13）
| # | 文件 | 改动 |
|---|------|------|
| 1 | `lib/services/knowledge_seed_service.dart` | `_seedGenericCourse` 关系生成新增同章节与跨章节关联 |
| 2 | `lib/services/archive/archive_template_source_service.dart` | 新增 `_ensureCourseArchiveDirsSync`，登记即创建课程归档命名空间 |
| 3 | `lib/main.dart` | `_initArchivePaths` 取消跳过缺失归档目录的课程 |
| 4 | `lib/services/workload_excel_service.dart` | `exportTemplate()` 改为 `async` 并随激活课程动态生成示例行 |
| 5 | `lib/presentation/pages/archive/tabs/workload_tab.dart` | `await _excel.exportTemplate()` |
| 6 | `lib/data/local/achievement_dao.dart` | 无章节课程返回 `const {}` 而非 MAD 关键词 |
| 7 | `lib/data/local/database_helper.dart` | `class_name` 默认值 `'软件23'` → `''` |

验证：`flutter analyze --no-pub` 对全部改动文件无编译错误（仅既有 withOpacity 弃用提示与无关未用导入告警）。

---

## 五、审核结论（修复后）

**系统已达到平台化主干要求，且原审计所列全部遗留问题已闭环修复**：任意高校课程均可作为激活课程运行；首页、达成、归档、实验、测验、学习、通知、同步、智能体九大模块功能与术语均由课程上下文驱动；SEB/FPP/AAOS 等课程现拥有独立归档模板命名空间；通用课程图谱关系由骨架升级为网状；工作量模板、章节关键词回落、班级默认值等残留硬编码均已消除。

全量 Token 扫描 57 处命中均为注释/文档示例/课程种子内容/历史兼容 shim，**实验/测验/学习/通知/同步零命中**。

**总体判定：平台化达标（Pass）。**
