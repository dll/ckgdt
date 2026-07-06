# CKGDT 审核报告（GPT5.5-第六轮）

- 审核日期：2026-07-06
- 审核对象：`D:\FlutterProjects\knowledge_graph_app`
- 审核重点：平台化闭环、一键生课资源包、CKGDT 内置课程、图谱与智能体能力、项目组织规范
- 审核方式：代码扫描 + 配置抽查 + 聚焦测试 + 静态分析

## 总体结论

第六轮结论：**平台化主线已形成，但仍不能判定为“完全闭环”。**

已通过的关键能力包括：

1. `data/CKGDT` 已作为内置课程存在，未再发现 `移动技术栈`、`教育技术栈` 目录残留。
2. 一键生课已具备课程画像、平台化检测、实验/作业/考核/达成/归档资源输出的基础能力。
3. 文学、体育、艺术、经管法、技能、通用课程类型的子图谱生成已有测试覆盖。
4. 项目结构整理文档和脚本已补齐，根目录污染已有治理方案。

仍需优先处理的问题集中在三类：

1. **新课程生成资源包的图谱分类结构与导入器不一致**，会影响新课程图谱资源按清单导入。
2. **运行时仍存在部分 MAD/Gitee 仓库硬编码入口**，对通用课程和私有部署不够平台化。
3. **Flutter 兼容债务较大**，`withOpacity()` 仍有 1588 处，与 `CLAUDE.md` 规范不一致。

## 第六轮发现

### P1. 一键生课输出的 `graph_categories.json` 与导入器契约不一致

证据：

- `lib/services/resource_persistence_service.dart:413` 写入：

```dart
await _writeJson('$courseDir/配置/graph_categories.json', {
  'categories': result.graphs.map((g) => g['category']).toList(),
});
```

- `lib/services/graph_import_service.dart:23` 读取 `categories` 后，按对象访问 `c['dir']`、`c['label']`、`c['color']`。
- `lib/services/course_subgraph_service.dart:204` 已经提供了正确的 `graphCategoriesJson()`，但当前资源持久化流程没有使用它。

影响：

- 新课程生成后，`graph_categories.json` 中的 `categories` 是字符串列表，而图谱导入器期望对象列表。
- 导入器异常会被捕获并退回章节兜底分类，表面不一定崩溃，但资源包清单与图谱目录不能完整一致。
- 这会削弱“一键生课 -> 资源清单 -> 图谱导入 -> 页面演示”的闭环。

建议修复：

1. `ResourcePersistenceService` 写 `graph_categories.json` 时复用 `CourseSubgraphService.graphCategoriesJson()` 的结构。
2. 同步生成 `graph_files.json`，确保每个分类目录能定位实际 Markdown 图谱文件。
3. 增加测试：生成文学/体育/工程课程资源包后，校验 `graph_categories.json.categories[0].dir/label/color` 均存在，并可被 `GraphImportService` 消费。

### P1. 仓库同步与课件下载仍有 MAD 运行时硬编码

证据：

- `lib/services/courseware_download_service.dart:24` 固定 `chzcldl`。
- `lib/services/courseware_download_service.dart:25` 固定 `mad-data`。
- `lib/services/sync_service.dart:32` 固定 `osgisOne`。
- `lib/services/sync_service.dart:33` 固定 `mad-fd`。
- `lib/core/constants/app_urls.dart:15` 固定 `chzcldl/mad-kgdt`。
- `lib/services/course_resource_service.dart:20`、`:21` 仍以内置 `chzcldl/mad-data` 作为默认系统资源仓库。

影响：

- CKGDT 作为演示课程可以运行，但新课程、离线部署、学校私有仓库或教师个人仓库仍会被默认仓库绑住。
- 课件下载、同步、隐私说明、仓库统计等功能难以统一切换到课程级配置。

建议修复：

1. 把系统资源仓、课程同步仓、教师/班级仓全部收敛到 `CourseResourceService` 或统一 `RepositoryConfigService`。
2. 保留 CKGDT/MAD 作为演示默认值，但默认值必须来自配置文件或数据库，不应散落在服务类常量中。
3. 新增平台化测试：创建 `SEB`、`文学鉴赏` 两门课程，设置不同仓库配置，验证下载、同步、仓库统计不会访问 MAD 仓库。

### P2. 图谱编辑能力仍是“节点编辑为主”，不是完整图谱编辑

证据：

- `CLAUDE.md:25` 要求“图谱必须可生成、可编辑、可复用”。
- `CLAUDE.md:33` 明确当前已支持新增、编辑、删除节点。
- `lib/presentation/pages/graph/graph_detail_page.dart` 可新增子节点并插入 `EdgeModel`，但未看到独立的边新增、边编辑、边删除 UI 闭环。

影响：

- 教师能调整节点，但不能完整调整知识关系。
- 对文学研读、体育训练、案例分析等非工程课程，关系类型往往比节点本身更重要，例如“证据支撑”“动作纠错”“案例适用”“评价达成”。

建议修复：

1. 在图谱详情页增加边编辑面板：源节点、目标节点、关系类型、标签、权重、是否双向。
2. 增加关系类型模板：通用、文学、体育、艺术、经管法、技能课程分别提供默认关系词。
3. 图谱编辑测试覆盖节点和边的 CRUD。

### P2. `withOpacity()` 兼容债务与项目规范冲突

证据：

- `CLAUDE.md:468` 要求使用 `color.withValues(alpha: 0.x)` 替代废弃的 `withOpacity()`。
- 扫描 `lib/` 下仍有 **1588** 处 `.withOpacity(`。
- 聚焦分析中，图谱页面也存在大量 `DEPRECATED_MEMBER_USE` 信息级提示。

影响：

- 当前不是编译错误，但 Flutter 新版本持续升级后会扩大技术债。
- 用户已多次要求“不要反复失败”，这类规范偏差会增加后续构建和跨端迁移的不确定性。

建议修复：

1. 不建议一次性手改 1588 处，容易引入视觉回归。
2. 先新增自动化迁移脚本或 codemod，按模块分批替换并截图验证关键页面。
3. 新增 CI 检查：新增代码禁止出现 `.withOpacity(`。

### P2. 历史 MAD 示例数据仍大量存在，但大多不阻断平台化

证据：

- `test/`、`data/MAD/`、`data/达成/` 中存在大量《移动应用开发》、Flutter、Android、HarmonyOS 示例。
- `lib/services/knowledge_seed_service.dart` 仍保留 MAD 知识种子。
- 视频源 mock provider 中仍有 Flutter/Android 示例内容。

判断：

- `data/MAD/` 和测试数据可以作为历史课程样例保留。
- 不能把历史样例删除，否则会破坏达成、归档、导入器等回归测试。
- 真正要治理的是运行时默认路径、默认仓库、默认课程上下文，而不是样例文本本身。

建议修复：

1. 在文档中明确 `data/MAD` 是历史样例课程，不是平台默认课程。
2. 视频 mock 数据增加文学、体育、艺术、经管法样例，避免演示时呈现单一工程课程倾向。
3. `knowledge_seed_service.dart` 增加课程类型种子分发，MAD 种子只在 MAD 课程启用。

## 已验证项目

### 通过

```powershell
flutter test test\services\course_subgraph_service_test.dart test\services\resource_persistence_service_test.dart --concurrency=1
```

结果：3 个测试通过。

```powershell
git diff --check
```

结果：通过，无空白错误。

```powershell
dart analyze --format=machine --no-fatal-warnings lib\presentation\pages\graph\knowledge_graph_page.dart lib\presentation\pages\graph\parts\graph_painters.dart
```

结果：无 error；存在信息级 deprecated/use_build_context_synchronously 提示。

### 未完整验证

未进行完整 Windows Release 构建。本轮是审核任务，且当前工作区已有图谱相关未提交修改，未扩大构建范围。

## 当前工作区状态

审核时发现以下文件处于修改状态：

- `lib/presentation/pages/graph/knowledge_graph_page.dart`
- `lib/presentation/pages/graph/parts/concept_model.dart`
- `lib/presentation/pages/graph/parts/graph_painters.dart`

这些改动主要是图谱节点类型颜色扩展、默认颜色兜底和绘制颜色解析，不属于本报告新增修复内容。本轮没有回退这些改动。

## 第六轮整改优先级

1. 立即修复 `graph_categories.json` 写入结构，并补 `graph_files.json` 测试。
2. 把仓库地址配置从服务常量迁移到课程/系统配置，保留演示默认但禁止散落硬编码。
3. 完整补齐图谱边编辑能力，使“可编辑图谱”从节点级提升到关系级。
4. 分批治理 `withOpacity()`，先禁止新增，再逐模块替换。
5. 给视频 mock、知识种子增加多课程类型示例，提升文科、体育、艺术课程演示可信度。

## 平台化判定

| 维度 | 第六轮判定 | 说明 |
|---|---|---|
| CKGDT 内置演示课程 | 通过 | 课程目录存在，未发现移动/教育技术栈目录残留 |
| 一键生课基础能力 | 基本通过 | 已输出课程画像、就绪度、资源包，但图谱分类契约需修复 |
| 新课程平台化 | 部分通过 | 课程类型推断和子图谱已覆盖，仓库配置仍需收敛 |
| 图谱能力 | 部分通过 | 节点编辑已具备，边编辑未完整闭环 |
| 数智课程特色 | 通过但可增强 | 知识图谱、数字孪生、智能体主线已具备 |
| 工程规范 | 部分通过 | 项目结构文档完善，但 Flutter deprecated 债务较大 |

最终结论：**第六轮建议进入“闭环修复阶段”，不是继续扩展新功能。先修资源包导入契约和仓库配置，再补图谱边编辑与兼容债务。**
