# CKGDT 平台化完整性审核报告

审核日期：2026-07-04  
审核对象：CKGDT 平台功能、内置课程包、一键生课、MAD/SEB 多课程适配  
审核结论：具备平台化骨架，但尚未达到“任意新课程一键生成并完整演示所有功能”的交付状态。

## 一、总评

CKGDT 当前已经从单课程系统演进为课程平台：默认课程 ID 已切到 `ckgdt`，课程上下文、课程作用域查询、课程资源目录、AI 一键生课、课程包读取服务、部分启动导入器都已经存在。CKGDT 资源包本身也最完整，覆盖配置、大纲、进度、理论、课件、实验、考核、达成、归档、图谱、用户、项目、文档、输出模板等。

但平台化闭环还没有打通。核心缺口是：课程包清单已经设计出来，运行时却没有统一的 `CoursePackageLoader` 把 `data/{courseId}` 的全部资源幂等导入数据库并绑定到各功能模块。现在只有测验和部分课件资源有导入链路，实验、归档、达成、试卷分析、用户班级、学习路径、项目作品、智能体技能上下文仍然是局部平台化。

因此当前状态可定义为：

- **CKGDT 作为内置演示课程：部分可用，不是完整自动加载。**
- **新课程一键生课：能生成基础资源包和部分数据库数据，不足以对齐 CKGDT 完整模板清单。**
- **MAD：真实资料丰富，兼容价值高，但仍带旧课程专属结构。**
- **SEB：目录存在，但当前不是完整课程包，不能认为与 CKGDT/MAD 一样有效。**

## 二、证据

### 1. 默认课程存在，但章节不一致

`CourseContextService` 默认课程是：

- `course_id = ckgdt`
- 课程名：课程知识图谱与数字孪生
- 默认章节：6 章

`database_helper.dart` 的默认课程种子同样写入 6 章。  
但 `data/CKGDT/配置/chapters.json` 是 8 章课程结构。也就是说，启动时如果只依赖数据库默认课程，会出现“课程包 8 章、系统上下文 6 章”的不一致。

### 2. 课程包读取服务存在，但不是完整导入器

`CourseDataService` 可以按优先级读取：

1. Flutter assets：`data/{courseId}/配置/manifest.json`
2. 本地文档目录：一键生课生成的课程目录
3. Gitee：`courses-{courseId}` 仓库

但它目前主要返回 `CourseDataPackage`，没有负责把所有资源写入数据库表。启动服务 `DataLoadingService` 调用了：

- `CkgdtQuizImporter.importCkgdtQuizzes()`
- `CkgdtResourceImporter.importCkgdtResources()`

这只覆盖测验和部分教学资源，不覆盖完整课程包。

### 3. 一键生课服务存在，但生成清单不完整

`CourseGenerationService.generateAll()` 能生成：

- 基础配置
- 章节配置
- 测验题目
- 视频脚本
- 课件内容
- 7 类图谱定义
- 实验任务
- 报告模板
- 达成配置
- 考核配置

`ResourcePersistenceService.saveLocally()` 能落盘到：

- `配置/`
- `理论/`
- `视频/`
- `课件/`
- `图谱/`

但相对 CKGDT 课程包清单仍缺：

- `大纲/`
- `进度/`
- `实验/实验教程/`
- `实验/报告模板/` 的 Markdown 正文
- `实验/实验指导/`
- `实验/平台技术栈/`
- `归档/期初、期中、期末、结课/`
- `达成/` 的报告模板与样例记录
- `考核/` 的完整考核材料
- `用户/`、班级、分组、角色样例
- `项目/`、作品任务、案例演示信息
- `推荐/`、学习路径、智能体/技能上下文
- 试卷分析样例数据
- Word/Excel/PDF 原格式模板

所以“一键生课”目前是“生成课程基础资源”，还不是“生成完整数智课程包”。

### 4. CKGDT 是最完整模板，MAD 是历史真实课程，SEB 尚不完整

当前目录审查结果：

- `data/CKGDT`：目录最完整，`配置` 下有 16 个 JSON，包括 `manifest.json`、`course_gen_input.json`、`chapters.json`、`lab_tasks.json`、`quiz_config.json`、`achievement_calc.json`、`roles.json`、`mock_data.json`、`course_settings.json` 等。
- `data/MAD`：资料量丰富，尤其是真实移动应用开发课程资料、图谱、归档、达成和考核材料；但 `配置` 只有 6 个基础 JSON，仍偏历史课程包。
- `data/SEB`：目录存在，但当前没有看到完整资源包内容，不能支撑完整演示。

### 5. 多课程路径仍有硬编码残留

部分页面已经使用当前课程上下文或 CKGDT 分支，比如实验材料页对 CKGDT 使用 `data/CKGDT/实验/...`。但非 CKGDT 课程仍回退到旧路径 `data/实验/...` 或远程 `mad-data`。这能兼容 MAD，却不能自然支持 SEB 或新课程包。

平台化目标应该是统一使用：

```text
data/{courseId}/配置
data/{courseId}/大纲
data/{courseId}/进度
data/{courseId}/理论
data/{courseId}/课件
data/{courseId}/实验
data/{courseId}/考核
data/{courseId}/达成
data/{courseId}/归档
data/{courseId}/图谱
data/{courseId}/用户
data/{courseId}/项目
```

旧 `data/实验`、`data/考核`、`data/归档` 只能作为 MAD 兼容层。

## 三、平台化能力评价

| 能力 | 当前状态 | 结论 |
|------|----------|------|
| 默认内置 CKGDT 课程 | 有默认课程记录，但与资源包 8 章不一致 | 部分达标 |
| CKGDT 资源包完整性 | 内容丰富，配置清单最完整 | 基本达标 |
| 启动自动加载 CKGDT | 只导入测验和部分资源 | 未达标 |
| 一键生课 | 可生成基础资源包 | 部分达标 |
| 生成完整数智课程 | 缺归档、达成、用户、项目、试卷分析、原格式模板 | 未达标 |
| MAD 兼容 | 资料丰富，旧路径兼容较多 | 可用但需规范化 |
| SEB 兼容 | 目录存在但资源包不足 | 未达标 |
| 多课程隔离 | 题库、达成、试卷分析等部分已 course_id 化 | 部分达标 |
| 智能体/技能服务课程 | 有课程上下文意识，但资源和工具调用未完全课程包化 | 部分达标 |
| 平台化页面体验 | 多处仍按 CKGDT 或 MAD 分支处理 | 部分达标 |

## 四、最关键的根因

当前系统的主要问题不是缺少功能页面，而是缺少统一课程包运行协议。

现在存在三套并行机制：

1. 数据库默认种子；
2. `data/{courseId}` 课程资源包；
3. 一键生课生成到用户文档目录的课程包。

这些机制没有统一收敛到一个“课程包加载、导入、同步、验证、更新”的服务。结果是：资源能生成、文件能存在、部分页面能读，但全平台不能保证当前课程的所有功能都从同一个课程包驱动。

## 五、最佳整改方案

### P0：建立统一课程包协议

新增 `CoursePackageLoader`，职责：

- 读取 `data/{courseId}/配置/manifest.json`
- 读取 `course_gen_input.json`
- 校验课程包目录和必需文件
- 创建或更新 `courses`
- 同步章节数、章节标题、课程目标
- 幂等导入题库、实验任务、资源文件、图谱、达成配置、归档模板、考核材料、用户班级、学习路径、项目案例
- 记录导入版本，避免每次启动重复导入

建议新增表：

```text
course_package_versions(
  course_id TEXT PRIMARY KEY,
  package_version TEXT,
  imported_at TEXT,
  manifest_hash TEXT,
  status TEXT
)
```

### P1：以 CKGDT 为标准模板清单

把 CKGDT 的 16 个配置文件作为新课程模板基线：

- `manifest.json`
- `course_gen_input.json`
- `chapters.json`
- `assessment.json`
- `lab_tasks.json`
- `homework.json`
- `quiz_config.json`
- `achievement_calc.json`
- `score_aggregator.json`
- `report_templates.json`
- `res_index.json`
- `graph_categories.json`
- `roles.json`
- `mock_data.json`
- `course_settings.json`
- `mask_shapes.json`

新课程一键生成时，不应只生成若干 JSON，而应生成与 CKGDT 同构的课程包。

### P2：升级“一键生课”为“一键生成数智课程”

一键生课输出应扩展为：

- 课程基本信息、章节、目标、毕业要求支撑矩阵
- 教学大纲、教学进度、教案
- 理论讲义、测验、作业
- 课件大纲、视频脚本
- 实验任务、实验教程、报告模板、评分量规
- 课程图谱、知识图谱、实验图谱、项目图谱、学习图谱、达成图谱、数字孪生图谱
- 考核方案、试卷分析模板、样例成绩
- 达成评价方案、达成报告、持续改进建议
- 期初、期中、期末、结课归档模板
- 教师/学生/管理员样例用户和班级
- 教学案例演示模板
- 智能体和技能上下文说明

这才符合“突出数智课程，一键生课”的目标。

### P3：统一 MAD/SEB/新课程适配

MAD：

- 保留真实资料；
- 补齐 CKGDT 同构配置；
- 把旧路径资料迁移或映射到 `data/MAD/{分类}`；
- `manifest.json` 升级到 2.0 结构。

SEB：

- 需要按 CKGDT 模板生成完整课程包；
- 至少补齐 `配置/大纲/进度/理论/课件/实验/考核/达成/归档/图谱/用户/项目`；
- 未补齐前不能宣称“与 CKGDT/MAD 一样有效”。

新课程：

- 一律生成 `data/{courseId}` 或用户文档目录 `courses/{courseId}`；
- 页面读取必须统一走 `CourseDataService + CoursePackageLoader`；
- 旧 MAD 路径只能作为兼容 fallback。

## 六、建议验收标准

平台化完成后，应能通过以下验收：

1. 清空数据库后启动，系统自动激活 `ckgdt`，显示 8 章而不是 6 章。
2. 教师端能看到 CKGDT 的大纲、进度、课件、实验、考核、达成、归档、图谱、案例。
3. 学生端能看到 CKGDT 学习路径、测验、实验、材料、作品任务和智能体辅助。
4. 管理员端能看到 CKGDT 用户、班级、角色、资源包导入状态。
5. 一键生课生成的新课程，不依赖 MAD 旧目录，也能完整打开教师、学生、管理员所有功能。
6. MAD 切换后仍显示移动应用开发资料。
7. SEB 生成或导入后显示软件工程基础资料，不出现 CKGDT/MAD 污染。
8. 达成、试卷分析、归档、图谱、智能体都严格使用当前课程 `course_id`。

## 七、最终结论

CKGDT 平台具备平台化基础，但还不是完整平台化产品。  
最好的方案不是继续在各页面零散判断 `ckgdt/mad/seb`，而是把 CKGDT 资源包升级为平台课程包标准，并实现统一的课程包加载器。随后让一键生课按这个标准生成完整课程包，MAD/SEB/新课程全部走同一协议。

完成这条主线后，CKGDT 才能真正做到：

- 内置 CKGDT 可完整演示；
- 新课程可一键生成完整数智课程；
- MAD、SEB 等课程同样有效；
- 教师、学生、管理员、智能体、技能、达成、归档、试卷分析都围绕当前课程运行。
