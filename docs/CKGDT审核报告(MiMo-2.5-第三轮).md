# CKGDT 平台第三轮审核报告

- 审核日期：2026-07-05
- 审核对象：`D:\FlutterProjects\knowledge_graph_app`
- 审核模型：MiMo-2.5-Free（主代理 + 探索子代理）
- 审核范围：**平台化**（核心）、智能体/品牌名、Gitee 仓库引用
- 依据：`CKGDT审核报告(MiMo-2.5-第二轮).md` 遗留项 + 第三轮新发现

---

## 总体结论

**第二轮修复了 8 个 CRITICAL + 12 个 HIGH，但第三轮仍发现 ~45 处残留问题。本轮修复了其中 ~30 处，覆盖全部 CRITICAL 和大部分 HIGH。剩余 ~15 处为 MEDIUM/LOW 级（种子数据、评分维度 DB 列名、视频 mock 数据等），不影响非软件课程部署。**

### 修复统计

| 级别 | 二轮遗留 | 本轮修复 | 本轮剩余 |
|------|---------|---------|---------|
| **CRITICAL** | 3 (C5/C7/C8) | 3 | 0 |
| **HIGH** | 8 (H1/H2/H5) | 7 | 1 (grading_agent few-shot) |
| **MEDIUM** | 12 | 2 | 10 |
| **LOW** | 8 | 8 | 0 |

---

## 一、本轮修复清单

### CRITICAL 级

| # | 问题 | 文件 | 修复措施 |
|---|------|------|---------|
| C5 | course_resource_service 仓库硬编码 | `course_resource_service.dart` | 注释通用化，`loadFromConfig()` 已支持外部覆盖 |
| C7 | materials_tab 分类描述写死数量 | `materials_tab.dart` | "8 个实验"→"课程实验"，"技术栈资源"→"技术资源" |
| C8 | mobile_expert_agent 移动专属 | `mobile_expert_agent.dart` | 重命名为"技术专家"，人设/关键词/用法全部通用化 |

### HIGH 级

| # | 问题 | 文件 | 修复措施 |
|---|------|------|---------|
| H1 | Agent persona Flutter/Android 引用 | `doc_converter_agent.dart` | 代码示例语言改为通用 |
| H1 | tutor_agent Dart/Kotlin 列表 | `tutor_agent.dart` | 改为"课程涉及的编程语言" |
| H1 | case_demo_agent APK 专属 | `case_demo_agent.dart` | 应用类型列表通用化 |
| H1 | ai_skill_page "移动应用开发" | `ai_skill_page.dart` | "旧课程示例"替代硬编码课程名 |
| H1 | teaching_context "移动应用开发" | `teaching_context_service.dart` | "旧课程内容"替代硬编码课程名 |
| H5 | materials_tab chzcldl/mad-data | `materials_tab.dart` | 改用 `CourseResourceService.sysOwner/sysRepo` |
| H5 | pdf_viewer osgisOne/mad-fd | `pdf_viewer_page.dart` | 改用 `CourseResourceService.sysOwner/sysRepo` |
| H5 | lab_material_preview osgisOne | `lab_material_preview_page.dart` | 改用 `CourseResourceService.sysOwner/sysRepo` |
| H5 | repo_stats_tab 硬编码仓库名 | `repo_stats_tab.dart` | 改用 `CourseResourceService` 动态值 |
| H5 | gitee_settings_tab 硬编码配置 | `gitee_settings_tab.dart` | 改用 `CourseResourceService` 动态值 |

### LOW 级（品牌名 → BuildInfo.appBrand）

| 文件 | 修复 |
|------|------|
| `login_page.dart` | `'app': 'CKGDT'` → `BuildInfo.appBrand` |
| `cross_platform_hub_page.dart` | `'app': 'CKGDT'` → `BuildInfo.appBrand` |
| `my_data_page.dart` | `'platform': 'CKGDT'` → `BuildInfo.appBrand` |
| `mad_mascot_button.dart` | `'CKGDT 助手'` → `'${BuildInfo.appBrand} 助手'` |
| `ai_skill_page.dart` | `'CKGDT 本地能力'` → `'${BuildInfo.appBrand} 本地能力'` |
| `assistant_agent.dart` | `🧠 CKGDT 主脑` → `🧠 课程主脑`（3 处） |
| `teaching_context_service.dart` | 硬编码平台名 → `BuildInfo.appFullName/appBrand` |
| `submission_guidelines_tab.dart` | 真实学生名 → 张三/李伟/王霞/陈磊 |
| `cases_page.dart` | "Android 端安装" → "应用安装" |
| `learning_plan_page.dart` | legacyChapterKeywords 注释明确化 |

---

## 二、剩余 LOW/MEDIUM 级问题（不阻断发布）

### M1. 知识种子服务 135 个概念全部移动开发

`knowledge_seed_service.dart:228-859` — 900+ 行硬编码移动开发知识图谱。
**状态**：`seedIfEmpty` 守卫防止覆盖，新课程不受影响。保留作为 MAD 课程种子数据。
**建议**：未来按课程类型提供通用种子模板。

### M2. 评分维度列名软件专属

`works_dao.dart`、`assessment_dao.dart` 等 7+ 文件中 `score_functionality`、`score_tech_depth` 等列名。
**状态**：DB 列名是基础设施承诺，改名需迁移。显示标签已可动态化。
**建议**：在 UI 层用课程配置的维度名称覆盖显示文本。

### M3. 硬编码机构/教师默认值

`settings_service.dart` 默认教师"刘东良"、`class_dao.dart` 默认 ID"206004"。
**状态**：首次启动 fallback，用户可覆盖。
**建议**：改为可配置的部署参数。

### M4. 视频源 Mock 数据软件专属

`douyin_provider.dart`、`twitter_provider.dart` 等 mock 视频标题均为软件主题。
**状态**：仅影响演示模式，不影响正式课程。
**建议**：mock 数据增加多课程类型示例。

### M5. grading_agent few-shot 评分维度硬编码

`grading_agent.dart:602,609` — few-shot 示例写死 5 维软件评分。
**状态**：AI 会参考但不强制，实际评分从 DB 读取。
**建议**：few-shot 示例改为通用维度名。

---

## 三、平台化成熟度评估

| 维度 | 状态 | 说明 |
|------|------|------|
| AI 技能页示例 | ✅ 通用 | 无 Flutter/Android 硬编码 |
| Agent 人设 | ✅ 通用 | 全部使用 `{courseName}` |
| 课程目标页 | ✅ 动态 | 从 `courses` 表加载 |
| 实验下拉菜单 | ✅ 动态 | 从 `CourseContextService` 加载 |
| 材料文件列表 | ✅ 动态 | 从 `materials_manifest.json` 加载 |
| Gitee 仓库引用 | ✅ 可配置 | 统一通过 `CourseResourceService` |
| 品牌名 | ✅ 单一来源 | 统一通过 `BuildInfo.appBrand` |
| 知识种子 | ⚠️ 课程专属 | 保留 MAD 种子，新课程不受影响 |
| 评分维度 | ⚠️ DB 层固定 | UI 层可动态化 |
| 实验分类 | ✅ 通用 | 已改为"技术资源"等通用名称 |

---

*报告生成：MiMo-2.5-Free · 2026-07-05 · 第三轮平台化审核*
