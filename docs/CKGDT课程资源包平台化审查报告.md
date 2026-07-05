# CKGDT 课程资源包平台化审查报告

- 审查日期：2026-07-05
- 审查对象：`data/配置/` 资源包 + `assets/` 种子数据
- 审查维度：**平台化**（是否适用于任意高校课程）

---

## 总体结论

**课程资源包高度绑定"移动应用开发"课程，不具备平台化能力。`data/配置/` 下 6 个 JSON 文件全部硬编码移动开发内容；`assets/` 下知识种子、图谱、教师手册等均为 MAD 专属。非软件类课程（文学、体育、艺术、经管法等）无法直接使用。**

### 严重度统计

| 级别 | 数量 | 说明 |
|------|------|------|
| **CRITICAL** | 5 | manifest/chapters/lab_tasks/assessment/资源索引 全部硬编码 |
| **HIGH** | 3 | scoring_dimensions 软件专属、缺少 course_profile/platform_readiness/平台化检测报告 |
| **MEDIUM** | 2 | report_templates 部分软件专属、CKGDT 图谱缺少通用模板 |
| **LOW** | 1 | 深度实践种子数据 MAD 专属 |

---

## 一、CRITICAL 级问题（资源包完全不可移植）

### C1. manifest.json — 全部硬编码

**文件**：`data/配置/manifest.json`

```json
{
  "course_name": "移动应用开发",                    // ❌ 硬编码
  "description": "《移动应用开发》课程资源配置清单",  // ❌ 硬编码
  "repositories": {
    "system": {
      "owner": "osgisOne",                         // ❌ 已废弃仓库
      "repo": "mad-fd"                             // ❌ 已废弃仓库
    },
    "enterprise": {
      "path": "chzuczldl",                         // ❌ 硬编码企业
      "name": "滁州学院-刘东良"                     // ❌ 硬编码机构/教师
    }
  }
}
```

**修复**：`course_name` 应从 `courses` 表动态读取；`repositories` 应从 `CourseResourceService` 配置读取；描述应为通用模板。

### C2. chapters.json — 章节全部移动开发

**文件**：`data/配置/chapters.json`

| 章节 | 标题 | 问题 |
|------|------|------|
| 第1章 | 移动应用开发技术体系全景 | ❌ 课程专属 |
| 第2章 | Android 与 iOS 原生开发基础 | ❌ 平台专属 |
| 第3章 | Flutter、React Native 等混合开发技术 | ❌ 框架专属 |
| 第4章 | 微信小程序开发流程 | ❌ 平台专属 |
| 第5章 | 华为 HarmonyOS 多端应用开发 | ❌ 平台专属 |
| 第6章 | 综合开发实践 | ⚠️ 通用但上下文绑定 |

**修复**：章节配置应由"一键生课"根据课程类型动态生成，或由教师在管理页编辑。

### C3. lab_tasks.json — 6 个实验全部移动开发

**文件**：`data/配置/lab_tasks.json`

所有实验绑定特定技术栈：
- 实验一：Android Studio、Flutter、DevEco Studio、HBuilderX、Visual Studio
- 实验二：Kotlin、SwiftUI、Activity、ViewController
- 实验三：Flutter(Dart)、React Native(JSX)、Uniapp(Vue)、MAUI(C#)
- 实验四：微信小程序、微信开发者工具
- 实验五：DevEco Studio、ArkUI、鸿蒙
- 实验六：多技术栈综合项目

**修复**：实验定义应由 `CourseSubgraphService` 根据课程类型动态生成，或从 `data/{courseId}/配置/lab_tasks.json` 按课程加载。

### C4. assessment.json — 评分维度软件专属

**文件**：`data/配置/assessment.json`

```json
"scoring_dimensions": [
  {"name": "功能完整性", "max_score": 25, ...},      // ❌ 软件专属
  {"name": "技术实现深度", "max_score": 20, ...},    // ❌ 软件专属
  {"name": "跨框架整合", "max_score": 25, ...},      // ❌ 软件专属
  {"name": "性能与质量", "max_score": 15, ...},      // ❌ 软件专属
  {"name": "文档与协作", "max_score": 15, ...}       // ❌ 软件专属
]
```

文学课程应为"论证深度、文献广度、逻辑严密性"；体育课程应为"动作规范性、战术理解、体能表现"。

**修复**：评分维度应从课程配置动态加载，或由 `CourseSubgraphService` 根据课程类型生成。

### C5. 资源索引.json — 引用废弃仓库 + 章节硬编码

**文件**：`data/配置/资源索引.json`

```json
"resource_base": {
  "pdf": {"owner": "osgisOne", "repo": "mad-data", ...},  // ❌ 硬编码
  "ppt": {"owner": "osgisOne", "repo": "mad-data", ...},  // ❌ 硬编码
  "video": {"owner": "osgisOne", "repo": "mad-data", ...} // ❌ 硬编码
},
"chapters": [
  "第一章 移动应用开发技术体系1",     // ❌ 硬编码
  "第二章 原生开发基础1",            // ❌ 硬编码
  ...
]
```

**修复**：`resource_base` 应从 `CourseResourceService` 读取；`chapters` 应从 `courses` 表动态生成。

---

## 二、HIGH 级问题

### H1. 缺少 course_profile.json

CLAUDE.md 要求一键生课必须输出 `course_profile.json`，但 `data/配置/` 下不存在此文件。

**course_profile.json 应包含**：
```json
{
  "course_id": "ckgdt",
  "course_name": "课程知识图谱与数字孪生",
  "course_type": "engineering",          // engineering/literature/sports/art/business/medical/general
  "chapter_count": 6,
  "lab_count": 3,
  "assessment_type": "exam",            // exam/assignment/project
  "scoring_dimensions": [...],          // 课程类型自适应
  "technology_stack": [...],            // 课程涉及的技术栈
  "subgraph_types": [...]               // 生成的子图谱类型
}
```

### H2. 缺少 platform_readiness.json

CLAUDE.md 要求一键生课必须输出 `platform_readiness.json`，但不存在。

**platform_readiness.json 应包含**：
```json
{
  "chapters_ready": true,
  "lab_tasks_ready": true,
  "assessment_ready": true,
  "knowledge_graph_ready": true,
  "scoring_dimensions_ready": true,
  "report_templates_ready": true,
  "missing_resources": []
}
```

### H3. 缺少平台化检测报告

CLAUDE.md 要求一键生课必须输出 `文档/平台化检测报告.md`，但不存在。

---

## 三、MEDIUM 级问题

### M1. report_templates.json 部分软件专属

`项目开发文档模板` 包含"技术选型"、"系统设计"、"部署说明"等软件工程专属章节。文学/体育课程不需要这些。

**修复**：模板应按课程类型提供变体，或标注为"可选章节"。

### M2. CKGDT 图谱缺少通用模板

`assets/graphs/ckgdt/` 下 7 类图谱（课程图谱、学习图谱、作业图谱、作品图谱、考核图谱、思政图谱）内容均为 CKGDT 课程专属。

**修复**：应提供空模板或通用示例，教师可通过"一键生课"填充具体内容。

---

## 四、LOW 级问题

### L1. 深度实践种子数据 MAD 专属

`assets/deep_practice/mad.json` 包含移动应用开发专属的深度实践配置。`default.json` 为通用模板但内容较少。

---

## 五、修复优先级建议

### 立即修复（P0 — 阻断平台化部署）

1. **C1-C5**：`data/配置/` 下所有 JSON 文件改为通用模板或课程类型自适应
2. **H1-H3**：生成 `course_profile.json`、`platform_readiness.json`、`平台化检测报告.md`

### 短期修复（P1 — 1-2 周内）

3. **M1**：report_templates 按课程类型提供变体
4. **M2**：图谱模板通用化

### 长期优化（P2）

5. **L1**：深度实践种子数据通用化

---

## 六、资源包平台化架构建议

### 当前架构（不可移植）

```
data/配置/
├── manifest.json          ← 硬编码 MAD
├── chapters.json          ← 硬编码 MAD
├── lab_tasks.json         ← 硬编码 MAD
├── assessment.json        ← 硬编码 MAD
├── report_templates.json  ← 部分通用
└── 资源索引.json          ← 硬编码 MAD
```

### 目标架构（平台化）

```
data/配置/
├── manifest.json          ← 通用模板，course_name 从 DB 读取
├── chapters.json          ← 由 CourseSubgraphService 生成
├── lab_tasks.json         ← 由 CourseSubgraphService 生成
├── assessment.json        ← scoring_dimensions 从课程配置读取
├── report_templates.json  ← 按课程类型提供变体
├── 资源索引.json          ← owner/repo 从 CourseResourceService 读取
├── course_profile.json    ← 课程画像（新增）
├── platform_readiness.json← 平台就绪度（新增）
└── materials_manifest.json← 材料清单（新增）

data/{courseId}/           ← 按课程隔离（新增）
├── 配置/
│   ├── course_profile.json
│   ├── lab_tasks.json     ← 课程专属实验定义
│   └── materials_manifest.json
├── 实验/
│   ├── 实验教程/
│   ├── 技术资源/
│   ├── 实验指导/
│   └── 报告模板/
└── 文档/
    └── 平台化检测报告.md
```

---

## 七、一键生课流程（待实现）

根据 CLAUDE.md 的 `CourseSubgraphService` 设计，一键生课应：

1. **识别课程画像**：从课程名、章节、大纲推断课程类型
2. **生成子图谱**：根据课程类型生成对应的知识图谱结构
3. **生成实验定义**：根据课程类型生成实验任务模板
4. **生成评分维度**：根据课程类型生成适配的评分体系
5. **输出资源清单**：生成 `course_profile.json`、`platform_readiness.json`、`平台化检测报告.md`

**当前状态**：`CourseSubgraphService` 已有基础实现，但资源包生成流程尚未完全集成。

---

*报告生成：MiMo-2.5-Free · 2026-07-05 · 课程资源包平台化审查*
