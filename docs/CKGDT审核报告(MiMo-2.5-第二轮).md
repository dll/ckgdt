# CKGDT 平台第二轮审核报告

- 审核日期：2026-07-05
- 审核对象：`D:\FlutterProjects\knowledge_graph_app`
- 审核模型：MiMo-2.5-Free（4个并行子代理）
- 审核范围：**平台化**（核心）、智能体/技能、全角色功能模块
- 依据：`CKGDT审核报告(MiMo-2.5-第一轮).md` 遗留项 + 新增发现

---

## 总体结论

**第一轮修复了 5 个 CRITICAL + 3 个 HIGH（本地化、V34迁移、密钥清理、catch清理），但平台化仍是最大短板。第二轮发现 ~152 处硬编码，涉及 40+ 文件，其中 8 个 CRITICAL 级阻断非软件类课程的部署。**

### 严重度统计

| 级别 | 数量 | 说明 |
|------|------|------|
| **CRITICAL** | 8 | AI技能页全部Flutter化 + 17个Agent人设写死 + 课程目标页简介 + 默认课程名 + 资源仓库 + 实验下拉 + 文件列表 |
| **HIGH** | 12 | Agent案例Flutter化 + 实验分类 + 成绩维度 + 考核维度 + Gitee仓库引用 + 产品化指南 |
| **MEDIUM** | 15 | 章节关键词 + 手册比例 + 评估进度 + 导出隐私 + 默认模板 + 知识种子 |
| **LOW** | 8 | 品牌名 + 评论引用 + 系统默认值 |

---

## 一、CRITICAL 级问题（阻断非软件课程部署）

### C1. AI技能页全部 Flutter/Android 硬编码

**文件**：`lib/presentation/pages/skill/ai_skill_page.dart`

9个技能的示例、系统提示、快捷命令全部写死 Flutter/Android 内容：

| 技能 | 硬编码示例 | 影响 |
|------|-----------|------|
| 图谱 | `'Flutter 跨平台开发技术体系'`, `'Android 四大组件'` | 文学/体育课程看到这些示例完全无关 |
| 路径 | `'零基础学 Flutter'`, `'Android 开发者转型鸿蒙'` | 同上 |
| 学习 | `'Flutter Widget 生命周期'`, `'Dart 异步编程'` + 系统提示强制 `'代码使用 Dart/Flutter'` | **Critical**: AI 被强制用 Dart/Flutter 回答 |
| 测验 | `'第1章 移动开发技术体系'`, `'第3章 Flutter 混合开发'` | 章节名写死 |
| 仓库 | `'Flutter 知识图谱 App'`, `'Android 天气预报 App'` | 项目类型写死 |
| 实验 | `'Flutter 计数器 App 入门实验'` + 系统提示 `'代码使用 Dart/Flutter'` | **Critical**: 同上 |
| 课件 | `'生成 Flutter Widget 体系的教案'` | 教案内容写死 |
| 作品 | `'Flutter + Firebase 技术选型'` | 技术栈写死 |

**修复**：所有示例改为动态生成（从课程章节/知识点），系统提示移除语言约束。

### C2. 17个 Agent 人设写死 "CKGDT"

**文件**：`lib/services/agent/agents/*.dart`

所有 agent 的 persona 包含字面量 `'CKGDT 课程知识图谱与数字孪生平台'`。`base_agent.dart:41-53` 的 `promptWithCourse()` 已支持 `{courseName}` 替换，但 agent 人设未使用该占位符。

**涉及文件**：
safety_agent, works_agent, tutor_agent, repo_agent, quiz_agent, lab_agent, graph_agent, grading_agent, ethics_agent, doc_converter_agent, digital_twin_agent, courseware_agent, assistant_agent, assessment_agent, achievement_agent, voice_agent（16个）

**修复**：所有人设字符串用 `{courseName}` 替换字面量。

### C3. course_objectives_page.dart 移动应用开发简介

**文件**：`lib/presentation/pages/course/course_objectives_page.dart:58-59`

```dart
_intro = '通过本课程的学习，掌握移动应用开发的多元技术体系（原生/混合/小程序/多端）...'
```

100% 移动应用开发专属描述，文学/体育课程显示此文本完全错误。

**修复**：从 `courses` 表的 `description` 字段加载，或用通用模板。

### C4. achievement_context.dart 默认课程名

**文件**：`lib/services/achievement_context.dart:10`

```dart
ValueNotifier<String> _courseNameNotifier = ValueNotifier<String>('移动应用开发')
```

**修复**：改为 `CourseContextService.defaultCourseName`。

### C5. course_resource_service.dart 硬编码仓库

**文件**：`lib/services/course_resource_service.dart:20-28`

```dart
static const String sysOwner = 'chzcldl';
static const String sysRepo = 'mad-data';
static const String enterprise = 'chzuczldl';
static const List<String> cgPrefixes = ['cg1-', 'cg2-', 'cg3-'];
```

**修复**：从 `courses` 表或配置文件读取。

### C6. lab 实验下拉菜单硬编码 6 个实验

**文件**：`lib/presentation/pages/lab/tabs/task_manage_tab.dart:325,377`

固定 `['实验一', '实验二', ..., '实验六']`，3 实验或 10 实验的课程看到错误选项。

**修复**：从课程 chapters 动态加载。

### C7. materials_tab.dart 硬编码文件列表

**文件**：`lib/presentation/pages/lab/tabs/materials_tab.dart:265-300`

`knownFiles` 映射硬编码了 25+ 个 MAD 课程专属文件名（如 `'实验一 开发环境搭建_new.md'`, `'Flutter开发跨平台应用技术栈手册.md'`）。

**修复**：从 `data/$courseId/配置/materials_manifest.json` 动态加载或运行时扫描。

### C8. mobile_expert_agent.dart 全部移动开发专属

**文件**：`lib/services/agent/agents/mobile_expert_agent.dart`

整个 agent 的名称（"移动专家"）、人设、关键词（Android/iOS/Flutter/Dart/Kotlin/Swift/HarmonyOS）、示例、快捷命令全部是移动端专属。

**修复**：条件注册（仅移动开发课程启用）或重命名为通用"技术专家"。

---

## 二、HIGH 级问题

### H1. Agent 经典案例全部 Flutter/Android

~34 处 agent classicCases 和 quickCommands 包含 Flutter/Android 示例：
- `graph_agent.dart`: `'Flutter 状态管理图谱'`
- `quiz_agent.dart`: `'第3章 Flutter 的题'`
- `lab_agent.dart`: `'Flutter UI 开发'`
- `grading_agent.dart`: `'批改 Flutter 实验报告'`
- `courseware_agent.dart`: `'生成 Flutter Widget 体系的教案'`
- `works_agent.dart`: `'MVVM', '跨平台适配'`
- 等 12 个 agent

### H2. 实验分类假设软件工程课程

`materials_tab.dart` 和 `student_lab_page.dart` 分类固定为 `'实验教程'`, `'技术栈资源'`, `'实验指导'`, `'报告模板'`。文学/体育/艺术课程不会有"技术栈资源"。

### H3. 成绩维度软件工程专属

`works_dao.dart` 评分维度：`score_functionality`, `score_tech_depth`, `score_integration`, `score_quality`, `score_documentation`。`assessment_dao.dart`：`code_contribution`, `doc_contribution`。

### H4. achievement_dao.dart 硬编码4目标满分

`_kFullMarks = [15.0, 25.0, 30.0, 30.0]`，`_baseExperimentRows` 固定 7 个实验列。不同课程目标数和实验数不同。

### H5. Gitee 仓库引用分散

`courseware_download_service.dart`, `lab_material_preview_page.dart`, `pdf_viewer_page.dart`, `repo_stats_tab.dart`, `gitee_settings_tab.dart` 等 6+ 文件硬编码 `chzcldl/mad-data` 或已废弃的 `osgisOne/mad-fd`。

### H6. 产品化指南 Flutter/Android 专属

`productization_guide_page.dart` 整个检查清单是 Flutter/Dart/Android/iOS 专属（`flutter analyze`, `pub.dev`, `AndroidManifest.xml`, `Info.plist` 等）。

### H7. 考核进度表硬编码开发周期

`assessment/tabs/report_tab.dart:220-254` 硬编码 4 周开发周期：`'跨平台数据同步架构实现'`, `'API统一对接与联调'` 等。

### H8. CQI 改进建议硬编码

`achievement/tabs/report_tab.dart:2073-2085` 改进建议：`'加大跨平台开发方案的对比分析训练'` 等移动开发专属建议。

---

## 三、MEDIUM 级问题

### M1. legacyChapterKeywords 写死移动开发关键词
`learning_plan_page.dart:734-753`

### M2. 问卷调查 Demo 数据写死 Flutter/Android 选项
`survey_dao.dart:436-441`

### M3. 手册评分比例与配置不一致
`handbook_page.dart:252` 写 `'平时30% + 实验30% + 期末40%'`，但 `achievement_config.dart` 是 `20/30/50`

### M4. 知识种子服务 135 个概念全部移动开发
`knowledge_seed_service.dart:225-539`

### M5. 知识抽取允许类型软件专属
`knowledge_extract_service.dart:431-460`

### M6. 文件上传分类包含 'APK', '源码'
`file_upload_service.dart:32-43`

### M7. 教学进度模板技术课程假设
`teaching_dao.dart:163-207`

### M8. lab_task_dao 默认报告模板软件专属
`lab_task_dao.dart:652-711`

---

## 四、修复优先级建议

### 立即修复（P0 — 阻断发布）

1. **C1** — AI技能页示例/提示动态化
2. **C2** — 17个 Agent 人设用 `{courseName}` 替换
3. **C3** — 课程目标页简介从课程配置加载
4. **C4** — achievement_context 默认课程名
5. **C5** — course_resource_service 仓库可配置
6. **C6** — 实验下拉菜单动态化
7. **C7** — 材料文件列表动态化
8. **C8** — mobile_expert_agent 条件注册

### 短期修复（P1 — 1-2 周内）

9. **H1** — Agent 案例通用化
10. **H2** — 实验分类课程类型自适应
11. **H3** — 成绩/考核维度可配置
12. **H4** — 成绩目标数动态化
13. **H5** — Gitee 仓库引用统一
14. **H6** — 产品化指南课程类型自适应

---

*报告生成：MiMo-2.5-Free · 2026-07-05 · 第二轮平台化专项审核*
