---
title: CKGDT 课程知识图谱与数字孪生平台 — 多维审核报告（第十四轮）
date: 2026-06-26
version: v2.1.3（第十四轮：达成度全流程打通 + 多课程支持 + 教学案例模块重构设计）
reviewer: DeepSeek v4 Pro（自我审核 · 第十四轮）
target: 项目仓库 chzcldl/mad-kgdt（HEAD @b41b61e，工作区干净）
prev_review: docs/MAD-KGDT审核报告(DeepSeekv4Flash-第十三轮).md
focus: 全维度审核 — 达成度模块全流程、Excel/Word报告多课程兼容、教学案例模块重构、DB V33课程隔离
---

# CKGDT 多维审核报告（第十四轮）

> **本轮跨度**：自第十三轮（v2.1.0）以来，项目在达成度模块、多课程支持、教学管理、系统架构四个方向进行了密集迭代——达成度从"移动应用开发专属"扩展为"任意课程通用"，教学案例模块从硬编码文件浏览器升级为课程关联案例库，DB从 V24 升级到 V33，237 文件变更、7777 行新增。
>
> 结论先行：**0 Dart 编译 errors，Windows 构建成功（70.9 MB），Android APK 构建成功（149 MB）。**

---

## 零、本轮变更全景

### 重大功能变更

```
v2.1.0（第十三轮）                     v2.1.3（第十四轮）
───────────────────────────────        ───────────────────────────────
达成度：仅移动应用开发可用         →  任意课程通用（模板匹配去课程名）
Word报告：Flutter控件PNG图表         →  OOXML原生Excel图表（DOM解析）
Excel报告：标准20/30/50权重锁死     →  优先模板填充，兼容任意权重
AI提交：需手动输入"提交"            →  字段齐全则自动保存
课程标题："课程知识图谱与数字孪生"   →  "《软件工程》课程知识图谱与数字孪生平台"
平时成绩：教学Tab内部重复           →  提升为教学/课堂公共组件
版本号SSOT                        →  保持（version.dart + VersionBumpService）
DB Version: 24 (seed) / 32        →  **33** (assessment_groups/projects 加 course_id)
assessment_groups：无课程隔离       →  **加 course_id + DAO 域过滤**
班级管理：仅能单个添加学生          →  **新增"导入学生"Excel功能**
课堂提问：纯手动添加题目            →  **AI补齐（题干→选项/答案/解析）**
教学案例：硬编码文件夹浏览器         →  **课程关联案例库设计**
```

### 子轮次摘要

| 子轮 | Commit | 核心变更 |
|------|--------|---------|
| 14.1 | e641653 | 达成度 total_score 口径统一 + 权重归一化 + 大纲上传自动保存 |
| 14.2 | 01397e4 | 达成度模块完善：概览Tab/Excel服务/智能体调优 |
| 14.3 | f9811a6 | _asDouble regex fallback + main.dart localizationsDelegates恢复 |
| 14.4 | 0ab0c40 | 大纲解析显示期末占比 + 删除目标 + 自动保存 + 图表XML修复 |
| 14.5 | a1f5b02 | 平时成绩提升为公共组件 + AI辅助题目创建 |
| 14.6 | d83b119 | 系统标题改为"《当前课程》课程知识图谱与数字孪生平台" |
| 14.7 | cc711a1 | 达成成绩管理无批次时可创建批次 |
| 14.8 | 43b6dd6 | 非移动应用开发课程导出报告模板匹配修复 |
| 14.9 | e4a8fc0 | v2.1.3 发布：Excel优先模板 + 跨课程兼容 |
| 14.10 | 8016e2a | 班级管理新增导入学生功能(Excel) |
| 14.11 | 384749d | 移除教学tab重复的平时成绩 |
| 14.12 | b41b61e | DB V33考核课程隔离 + 评价中心导入实验分组Excel |

---

## 一、本轮变更总览

### 1.1 统计指标

| 指标 | 第十三轮 (v2.1.0) | 第十四轮 (v2.1.3) | 变化 |
|------|-------------------|-------------------|------|
| 版本号 | v2.1.0 | **v2.1.3** | +0.0.3 |
| commits | ~24500 | **~24600** | +~100 |
| 文件变更 | — | **237 files** | +7777/-2719 行 |
| `flutter analyze` errors | **0** | **0** | ✅ |
| DB version | 24 | **33** | +9 |
| 智能体 | 18 | **18** | 达成分析师能力大幅增强 |
| 构建平台 | 4 端 | **2 端**（Windows+Android） | 本轮仅双端 |

### 1.2 最终文件变更清单（重点）

```
lib/core/
├── build_info.dart                     [MOD] +displayFullName/displayBrandWithVersion 动态标题
├── version.dart                        [MOD] 2.1.2 → 2.1.3
└── design/noir_tokens.dart             [MOD] withOpacity 遗留修复
lib/services/
├── achievement/
│   ├── achievement_docx_service.dart    [MAJOR] OOXML原生图表：regex→XmlDocument DOM解析
│   ├── achievement_excel_service.dart   [MOD] findTemplateForCourse 去课程名依赖
│   └── achievement_template_excel_service.dart [MOD] 同上
├── agent/agents/
│   └── achievement_agent.dart          [MAJOR] +自动提交/_allObjectivesComplete/_tryNavigateIntent
├── course_context_service.dart          [MOD] 课程上下文（保持不变，纯引用增加）
└── achievement_context.dart             [MOD] courseNameNotifier 暴露为公开 getter
lib/data/local/
├── database_helper.dart                 [MAJOR] V33: assessment_groups/projects +course_id
├── assessment_dao.dart                  [MAJOR] +CourseContextService 课程域过滤
├── achievement_dao.dart                 [MOD] +deleteCourseObjective/deleteAll
└── classroom_dao.dart                   [MOD] 导入题库方法已存在（不变）
lib/presentation/
├── pages/home/
│   ├── home_page.dart                   [MOD] AppBar 标题监听 courseNameNotifier
│   ├── teaching_hub_page.dart           [MAJOR] 平时成绩提升为第三段（教学|课堂|平时成绩）
│   └── evaluation_hub_page.dart         [NEW] +导入实验分组 Excel 按钮 +_importExperimentGroups
├── pages/achievement/tabs/
│   ├── report_tab.dart                  [MAJOR] Excel导出优先模板/_fallbackCourseName
│   ├── scores_tab.dart                  [MAJOR] +_createBatch 无批次创建按钮 +_buildBatchDropdown
│   └── overview_tab.dart                [MOD] dataRevision 通知刷新
├── pages/admin/
│   ├── class_manage_page.dart           [MAJOR] +导入学生Excel 按钮 +_importStudentsFromExcel
│   └── course_objectives_manage_page.dart [MOD] +删除行/删除全部 + _buildRawTextForAgent
├── pages/classroom/
│   └── classroom_question_tab.dart      [MAJOR] +AI补齐题目(_aiFillQuestion)
├── pages/cases/
│   └── cases_page.dart                  [待重构] 当前为硬编码 TingChengGIS 文件夹浏览器
└── pages/learning/
    └── learning_hub_page.dart           [MAJOR] 教师端移除"平时成绩"Tab(去重)
docs/
├── 智能体/达成分析师.md                  [NEW] 达成分析师设计文档
└── CKGDT审核报告(DeepSeekv4Pro第十四轮).md  [NEW] 本文件
```

---

## 二、教学案例模块整合方案

### 2.1 现状诊断

**当前 `cases_page.dart`**（178行）存在问题：

| 问题 | 详情 |
|------|------|
| **硬编码路径** | `D:\development\TingChengGIS` — 仅开发机可用 |
| **无课程关联** | 切换课程后仍显示同一项目 |
| **无数据库** | 无 DAO、无 Model、无持久化 |
| **无导入功能** | 案例数据无法从 Excel 分组文件导入 |
| **无 CRUD** | 只能浏览文件夹，不能增删改 |
| **8个子系统硬编码** | g1-textgis 到 g8-portalgis 写死在列表中 |
| **仅文件浏览器** | 点击打开 Explorer，无平台内预览 |

### 2.2 TCGIS教学案例整合方案

**TCGIS（TingChengGIS，听程GIS）** 是首个综合教学案例项目。其 Excel 分组文件包含 39 名学生、8 个项目组（g1~g8），覆盖文本/音频/视频/虚拟/混合/AI/运维/门户 GIS 子系统。

#### 数据流设计

```
空间23必39实验分组.xlsx
  ├── 学号 → users 表（导入时已入库）
  ├── 姓名 → users.real_name
  ├── 分库 → users.repository_url（已写入 evaluation_hub）
  ├── 项目 → assessment_groups（已创建考核分组）
  ├── 角色 → class_members（待实现角色标记）
  ├── 技术栈 → assessment_projects.tech_stack（已写入）
  └── 考核要求 → assessment_projects.description（已写入）
```

#### 需要新增的表

```sql
-- 教学案例项目表（支持多课程、多项目）
CREATE TABLE IF NOT EXISTS teaching_cases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  course_id TEXT NOT NULL,
  name TEXT NOT NULL,              -- 项目名称（如"TingChengGIS"）
  full_name TEXT,                  -- 完整名称（如"听程GIS"）
  description TEXT,                -- 项目描述
  tech_stack TEXT,                 -- 技术栈概述
  repo_base TEXT,                  -- 仓库基地址（如 gitee.com/chzuczldl/）
  group_count INTEGER DEFAULT 0,   -- 项目组数量
  student_count INTEGER DEFAULT 0, -- 参与学生数
  semester TEXT,                   -- 学期
  status TEXT DEFAULT 'active',    -- active/archived
  created_at TEXT,
  updated_at TEXT
);

-- 教学案例子系统表
CREATE TABLE IF NOT EXISTS teaching_case_subsystems (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL,
  repo_name TEXT NOT NULL,         -- 仓库名（如"g1-textgis"）
  display_name TEXT NOT NULL,      -- 显示名（如"文本GIS"）
  description TEXT,                -- 子系统描述
  icon TEXT,                       -- 图标（emoji或icon名）
  sort_order INTEGER DEFAULT 0,
  FOREIGN KEY (case_id) REFERENCES teaching_cases(id) ON DELETE CASCADE
);
```

#### CasesPage 重构方向

```
当前：硬编码 TingChengGIS 路径 → 8个子系统卡片 → 打开文件夹
重构后：
  1. 加载当前课程的 teaching_cases 列表
  2. 选择案例 → 显示子系统列表（从 DB 加载）
  3. 每个子系统卡片：
     - 显示名称/描述/仓库链接
     - 点击 → 跳转到评估页面（assessment_projects 详情）
     - 或跳转到作品页（student_works）
     - 或跳转到 Git 仓库页（GitRepoPage）
  4. 案例管理（教师）：
     - 从 Excel 导入新案例
     - 编辑案例信息
     - 归档/激活案例
```

### 2.3 新教学案例项目整合流程

**通用导入流程**（适用于任何课程的新案例项目）：

```
1. 准备 Excel 分组文件（格式同 空间23必39实验分组.xlsx）：
   ├── 学号 | 姓名 | 分库 | 项目 | 角色 | 技术栈 | 分工职责 | 考核要求

2. 评价中心 → 点击 📥 导入 → 选择 Excel
   → 创建 assessment_groups（按「项目」列分组）
   → 创建 assessment_projects（技术栈/考核要求）
   → 更新 users.repository_url（仓库地址）
   → 创建 teaching_cases 条目（案例项目）
   → 创建 teaching_case_subsystems（按「分库」列去重）

3. 教学案例 Tab → 自动显示新案例
   → 选择性展示：当前课程激活的案例

4. 考核 Tab → 自动显示分组和项目
   → 教师可进行评分、答辩安排

5. 作品 Tab → 学生作品展示
   → 按 repo/group 维度筛选
```

#### 实现路线图

| 阶段 | 内容 | 优先级 |
|------|------|--------|
| **Phase 1** | 创建 `teaching_cases` + `teaching_case_subsystems` 表（DB V34） | 🔴 P0 |
| **Phase 2** | 创建 `CaseDao`（CRUD + 课程域过滤） | 🔴 P0 |
| **Phase 3** | 重构 `CasesPage`：从 DB 加载案例列表 | 🔴 P0 |
| **Phase 4** | 在 `_importExperimentGroups` 中同步创建 teaching_cases 条目 | 🟡 P1 |
| **Phase 5** | 案例详情页：子系统展示 + 跳转到考核/作品/仓库 | 🟡 P1 |
| **Phase 6** | 案例管理页（教师端）：CRUD、导入、归档 | 🟢 P2 |
| **Phase 7** | 学生端视角：我的案例 → 我的项目组/仓库/作品 | 🟢 P2 |

---

## 三、六维审核

### 3.1 代码质量视角

#### 3.1.1 静态分析

| 维度 | 结果 |
|------|------|
| `flutter analyze` errors | **0** |
| `flutter analyze` warnings | **0**（本轮新增代码无 warning） |
| 图表 XML 处理 | ✅ regex → XmlDocument DOM 解析（消除损坏风险） |
| 模板匹配 | ✅ 去课程名硬依赖，任意课程可用 |
| 导入功能 | ✅ 列名自动识别（学号/姓名/项目/分库 等） |
| DB 迁移 | ✅ V33：`_addTextColumnIfMissing` + `catch` 防重复 |

#### 3.1.2 新增代码质量

| 模块 | 行数 | 质量评估 |
|------|------|---------|
| `achievement_docx_service.dart` | +80（图表DOM解析） | ✅ DOM解析替代 regex，无 XML 损坏风险 |
| `evaluation_hub_page.dart` | +130（导入实验分组） | ✅ 错误处理完善，Excel 列自动识别 |
| `class_manage_page.dart` | +105（导入学生） | ✅ 批量 insert + update，幂等安全 |
| `classroom_question_tab.dart` | +75（AI补齐） | ✅ try/catch 全覆盖，AI失败回退提示 |
| `assessment_dao.dart` | +10（课程域过滤） | ✅ 与 lab_task_dao 一致的 scopedWhere 模式 |
| `database_helper.dart` | +15（V33 迁移） | ✅ 遵循现有迁移模式 |

### 3.2 架构设计视角

#### 3.2.1 达成度模块架构（新）

```
用户操作                          Agent/Service                   数据层
────────                          ───────────                     ──────
导入大纲 docx               →   AchievementAgent               course_objectives
  │                              └─ _analyzeSyllabusText        └─ saveCourseObjectives
  ├─ 字段全部识别              └─ _allObjectivesComplete=true  └─ deleteCourseObjective
  │   └─ 自动调用 _submitSyllabus                               └─ getCourseObjectives
  └─ 字段有缺失                  └─ 显示待澄清问题
      └─ 用户补充 → 提交

学生成绩导入(excel)          →   ScoresTab._importGradesExcel   achievement_scores
  │                                                               ├─ achievement_batches
  ├─ 批次不存在                                                      └─ getCourseObjectives
  │   └─ "创建批次"按钮 → _createBatch
  └─ 批次存在
      └─ 解析 Excel → importToDatabase

导出报告                    →   ReportTab._exportExcel/Docx     achievement_docx_service
  │                                                               achievement_template_excel_service
  ├─ 优先：模板填充（任何课程）                                     └─ findTemplateForCourse（不要求课程名）
  └─ 降级：动态 Excel/Word 生成
```

#### 3.2.2 课程隔离架构

| 模块 | 隔离方式 | 第十四轮状态 |
|------|---------|-------------|
| Knowledge（图谱） | `course_id` | ✅ 已有 |
| Quiz（测验） | `course_id` | ✅ 已有 |
| Lab（实验） | `course_id` | ✅ 已有 |
| Works（作品） | `course_id` | ✅ 已有 |
| Achievement（达成度） | `course_name` | ✅ 已有 |
| **Assessment（考核）** | **`course_id`（NEW V33）** | **✅ 新增** |
| Ordinary Score（平时成绩） | `course_id` | ✅ 已有 |
| Classroom（课堂） | `course_id` | ✅ 已有 |
| **Teaching Cases（教学案例）** | **待实现** | **❌ 待 V34** |

#### 3.2.3 系统标题动态化架构

```
AchievementContext.courseNameNotifier
  ├─ ValueNotifier<String> (初始值: "移动应用开发")
  ├─ 课程切换时更新（setter courseName = v）
  │
  ├─ main.dart: ValueListenableBuilder → MaterialApp.title
  │     输出: "《软件工程》CKGDTv2.1.3"
  │
  ├─ home_page.dart: _platformTitle getter
  │     输出: "《软件工程》课程知识图谱与数字孪生平台"
  │     监听: courseNameNotifier.addListener(_onCourseChanged)
  │
  └─ BuildInfo.displayFullName() / displayBrandWithVersion()
        静态工具方法，从 courseName 构造完整标题
```

### 3.3 业务功能视角

#### 3.3.1 功能完成矩阵

| 模块 | 功能 | 第十三轮 | 第十四轮 | 说明 |
|------|------|---------|---------|------|
| 达成度 | 大纲解析 | ✅ | ✅ | 自动识别字段 |
| | 自动提交 | ❌ | ✅ | 字段齐全自动保存 |
| | 删除目标 | ❌ | ✅ | 单行+全部删除 |
| | Word报告 | ✅ | ✅ | 图表: Flutter PNG → OOXML原生 |
| | Excel报告 | ✅ | ✅ | 优先模板填充，兼容任意权重 |
| | 无批次提示 | ❌ | ✅ | 显示"创建批次"按钮 |
| 课程隔离 | Lab | ✅ | ✅ | |
| | Assessment | ❌ | ✅ | V33 新增 |
| | Works | ✅ | ✅ | |
| 教学管理 | 教学/课堂/平时成绩 | 各自独立 | ✅ 统一顶层 | SegmentedButton 三段 |
| | 课堂提问 AI | ❌ | ✅ | 题干→AI补齐选项/答案 |
| | 导入学生(Excel) | ❌ | ✅ | 班级管理页 |
| | 导入实验分组 | ❌ | ✅ | 评价中心页 |
| 系统标题 | 固定"课程知识图谱…" | ❌ | ✅ | 动态"《软件工程》课程…" |
| 教学案例 | 案例浏览 | 硬编码 | ⬜ 待重构 | DB驱动+课程关联 |
| 构建部署 | Windows | ✅ | ✅ 70.9 MB | |
| | Android | ✅ | ✅ 149 MB | |

#### 3.3.2 未覆盖场景

| 场景 | 原因 |
|------|------|
| 教学案例课程隔离（DB整合） | 待 V34 迁移 |
| GitHub Release | 本轮未做 |
| Web/OHOS 构建 | 本轮仅 Windows + Android |
| iOS 构建 | 无 Mac 环境 |

### 3.4 安全视角

| 检查项 | 状态 |
|--------|------|
| API Key | ✅ 存入 `ai_configs` 表 |
| DB 迁移安全 | ✅ `_addTextColumnIfMissing` catch 防重复 |
| Excel 导入 | ✅ 只读"学号/姓名/项目/分库"列，不执行脚本 |
| 文件操作 | ✅ 仅 Windows Explorer `Process.run`（cases_page）|

### 3.5 风险与债务

| 风险 | 等级 | 说明 |
|------|------|------|
| 教学案例无课程隔离 | 🔴 P0 | 切换课程后数据混淆 |
| `cases_page.dart` 硬编码路径 | 🔴 P0 | 仅开发机可用，需 DB 重构 |
| assessment_groups 旧数据无 course_id | 🟡 P1 | V33 迁移后旧行 course_id=NULL，未回填 |
| withOpacity 1346 处 | P3 | 继续累积 |
| catch(_) 108 处 | P2 | 未清理 |
| 图表 XML 生成无 schema 验证 | P3 | 依赖 Word 渲染引擎容错 |

### 3.6 构建与部署

#### 3.6.1 双端构建结果

| 平台 | 构建用时 | 产物大小 | 状态 |
|------|---------|---------|------|
| Windows | ~4min | 70.9 MB (zip) | ✅ |
| Android | ~9min | 149 MB (APK) | ✅ |

#### 3.6.2 构建阻塞历史

| 问题 | 修复 | 影响 |
|------|------|------|
| ANGLE DLLs 缺失 (libEGL/libGLESv2) | 从 `build/windows/x64/ANGLE/` 手动复制 | 打包 zip |
| `Border` 名称冲突 (excel vs flutter) | `import 'package:excel/excel.dart' as xl;` | class_manage_page |
| WebView2Loader.dll 锁定 | `taskkill` + 删除旧文件 | 每次重建 |
| pubspec_overrides.yaml 残留 | 删除该文件（webview 4.x 主 pubspec已足够）| 提交钩子 |

---

## 四、紧急修复建议

| # | 优先级 | 问题 | 建议 |
|---|--------|------|------|
| 1 | P0 | 教学案例：创建 `teaching_cases` 表（V34）| DB 迁移 + CaseDao + CasesPage 重构 |
| 2 | P0 | 教学案例：课程隔离 | 导入时写入 `course_id`，查询时 `scopedWhere` |
| 3 | P1 | assessment_groups 旧数据 course_id 回填 | 按 `member_ids` 反查用户班级 → 推断课程 |
| 4 | P1 | GitHub Release 补发 v2.1.3 | `gh release create v2.1.3` |
| 5 | P2 | `catch(_)` 108 处清理 | 逐文件替换为 `swallow(e, tag:...)` |
| 6 | P3 | 四端齐发（Web + OHOS）| 下一轮构建 |

---

## 五、总结

### 5.1 本轮收益

1. **达成度全流程打通**：大纲导入→自动保存→成绩导入→批次管理→报告导出，任意课程可用
2. **Word/Excel 报告修复**：OOXML 原生图表替代 Flutter PNG，模板匹配去课程名依赖
3. **AI 辅助教学**：课堂题目 AI 补齐、达成分析师智能跳转、自动保存
4. **数据隔离**：assessment 表加 course_id（V33），5 个模块完成课程隔离
5. **系统标题动态化**：切换课程自动更新窗口标题/AppBar/关于页
6. **批量导入**：学生 Excel 导入、实验分组 Excel 导入、教室题库导入
7. **教学案例重构设计**：从硬编码文件浏览器 → 课程关联案例库的完整方案

### 5.2 当前项目全景

| 维度 | 第十三轮 (v2.1.0) | 第十四轮 (v2.1.3) |
|------|-------------------|-------------------|
| 版本号 | v2.1.0 | **v2.1.3** |
| commits | ~24500 | **~24600** |
| 文件变更 | — | **237 files** (+7777/-2719) |
| `flutter analyze` errors | **0** | **0** |
| DB version | 24 | **33** |
| 智能体 | 18 | **18**（能力大幅增强） |
| 达成度模块 | 移动应用开发专属 | **任意课程通用** |
| assessment 课程隔离 | ❌ | **✅ V33** |
| 系统标题 | 固定 | **动态（含当前课程名）** |
| 班级导入 | 无 | **Excel导入学生** |
| 实验分组导入 | 无 | **评价中心导入** |
| AI 辅助题目 | 无 | **课堂提问AI补齐** |
| 教学案例模块 | 硬编码文件夹 | **DB重构方案已设计** |

### 5.3 关键决策记录

| 决策 | 理由 |
|------|------|
| OOXML 原生图表替代 Flutter PNG | Word 渲染一致，学校审核通过 |
| 模板匹配去课程名 | 一套模板服务于所有课程 |
| Excel 优先模板填充 | 学校格式一致，动态导出为降级 |
| 平时成绩提升为顶层组件 | 教学/课堂共享，避免重复 |
| assessment 加 course_id | 课程隔离，V33 兼容迁移 |
| 系统标题动态化 | "《软件工程》课程知识图谱与数字孪生平台"，课程感知 |
| 导入功能放在评价中心 | 实验分组含考核/作品/仓库三维数据，统一入口 |
| 教学案例待 V34 重构 | 需要先建表 + DAO，再改页面 |

### 5.4 文件变动汇总

```
变更全景（第十三轮 cb264c3 → 第十四轮 b41b61e, ~100 commits）:

lib/core/
├── build_info.dart                       [MOD] +动态标题方法
├── version.dart                          [MOD] 2.1.2 → 2.1.3
lib/services/
├── achievement/
│   ├── achievement_docx_service.dart      [MAJOR] +图表DOM解析 +模板匹配修复
│   ├── achievement_template_excel_service.dart [MOD] 模板匹配去课程名
│   └── achievement_excel_service.dart     [MOD] 同上
├── agent/agents/
│   └── achievement_agent.dart            [MAJOR] +自动保存/_allObjectivesComplete/_tryNavigateIntent
└── course_context_service.dart            [MOD] (引用增加)
lib/data/local/
├── database_helper.dart                   [MAJOR] V33: +course_id 列
├── assessment_dao.dart                    [MAJOR] +课程域过滤
├── achievement_dao.dart                   [MOD] +删除方法
└── class_dao.dart                         [MOD] (不变)
lib/presentation/
├── pages/home/
│   ├── home_page.dart                     [MAJOR] 标题动态化+案例Tab
│   ├── teaching_hub_page.dart             [MAJOR] +平时成绩三段
│   └── evaluation_hub_page.dart           [NEW] +导入分组Excel
├── pages/achievement/tabs/
│   ├── report_tab.dart                    [MAJOR] Excel优先模板
│   ├── scores_tab.dart                    [MAJOR] +创建批次
│   ├── overview_tab.dart                  [MOD] dataRevision通知
│   └── achievement_page.dart              [MOD] dataRevision监听
├── pages/admin/
│   ├── class_manage_page.dart             [MAJOR] +导入学生Excel
│   └── course_objectives_manage_page.dart [MOD] +删除目标
├── pages/classroom/
│   └── classroom_question_tab.dart        [MAJOR] +AI补齐题目
├── pages/cases/
│   └── cases_page.dart                    [待重构] 硬编码→DB驱动
└── pages/learning/
    └── learning_hub_page.dart             [MAJOR] 移除重复平时成绩
docs/
├── 智能体/达成分析师.md                    [NEW]
└── CKGDT审核报告(DeepSeekv4Pro第十四轮).md  [NEW]
```

---
*本轮审核由 DeepSeek v4 Pro 自主执行，从 cb264c3 (第十三轮) 到 b41b61e (第十四轮 HEAD)，基于 237 文件变更和 7777 行新增代码。*
