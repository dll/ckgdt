# Plan: Fix Platform Issues + Resource Versioning

## Context

Three platform issues need fixing:
1. **Mask types hardcoded** — Categories ('移动平台', '跨平台框架', etc.) are static in `mask_widgets.dart:117-137`, not driven by config
2. **Graph content is MAD-specific** — `assets/graphs/` has 33 .md files about "移动应用开发" (Android/iOS/Flutter), not CKGDT. `GraphImportService` hardcodes 6 categories with MAD file names
3. **Experiment materials show MAD** — `materials_tab.dart` and `student_lab_page.dart` display MAD experiments ("开发环境搭建", "原生应用开发") even when CKGDT is active

Additionally, resource versioning from the previous plan needs implementation.

---

## Issue 1: Mask Types — Config-Driven Categories

### Current State
- `lib/core/constants/mask_shapes.dart` — enum `MaskShape` with 22 values, each with hardcoded `MaskShapeBuilder.getPath()` (1183 lines of path math)
- `lib/presentation/pages/graph/parts/mask_widgets.dart:117-137` — categories hardcoded as `Map<String, List<MaskShape>>`

### Approach
Create `data/CKGDT/配置/mask_shapes.json` with category definitions. The enum + path builders stay in code (they need `dart:ui` Path math), but the **grouping** loads from JSON.

### Files to Change

**New: `data/CKGDT/配置/mask_shapes.json`**
```json
{
  "version": "1.0.0",
  "categories": [
    {
      "name": "教育平台",
      "shapes": ["none", "avatar", "brain"]
    },
    {
      "name": "知识工具",
      "shapes": ["dart", "python", "java", "typeScript", "golang"]
    },
    {
      "name": "开发框架",
      "shapes": ["flutter", "reactNative", "uniapp", "maui", "cordova"]
    },
    {
      "name": "平台与工具",
      "shapes": ["android", "apple", "harmonyOS", "docker", "gitHub", "vsCode", "linux", "wechat"]
    }
  ]
}
```

**Modified: `lib/core/constants/mask_shapes.dart`**
- Add `MaskShapeCategory` model class (name + shape list)
- Add `static Future<List<MaskShapeCategory>> loadCategories(String courseId)` that reads JSON and maps string names to enum values
- Keep existing enum and `MaskShapeBuilder` unchanged

**Modified: `lib/presentation/pages/graph/parts/mask_widgets.dart`**
- Replace hardcoded `groups` map with async load from `MaskShape.loadCategories()`
- Cache result in `_MaskGridPanelState`

**Modified: `lib/core/constants/mask_shapes.dart`**
- Add `static const Map<String, MaskShape> nameMap` for string→enum lookup

---

## Issue 2: Graph Content — CKGDT + 思政图谱

### Current State
- `assets/graphs/` has 6 categories × MAD .md files (33 total)
- `GraphImportService` hardcodes `_categories` (6 items) and `_categoryFiles` (MAD file names)
- `GraphListPage` hardcodes 6 default colors/icons

### Changes

**Step A: Create CKGDT graph .md files**

Create `assets/graphs/ckgdt/` with 7 categories. Each category gets CKGDT-specific .md files:

| # | Category Dir | Label | Color | Files |
|---|---|---|---|---|
| 1 | `01-课程图谱` | 课程图谱 | #E53935 | 知识体系图谱.md, 课程目标图谱.md, 学习问题图谱.md, 能力培养图谱.md |
| 2 | `02-平台技术图谱` | 平台技术图谱 | #1E88E5 | 知识图谱技术.md, 数字孪生技术.md, 学习分析技术.md, 多智能体系统.md |
| 3 | `03-实验图谱` | 实验图谱 | #FB8C00 | 实验一 平台基础操作.md, 实验二 知识图谱建模.md, 实验三 数字孪生场景设计.md, 实验四 学习分析仪表盘.md, 实验五 实验管理与AI批阅.md, 实验六 综合项目.md, 实验七 教师端教学管理.md, 实验八 学生端自主学习.md |
| 4 | `04-项目图谱` | 项目图谱 | #43A047 | 课程知识图谱构建项目.md, 数字孪生教学设计项目.md, 学习分析实践项目.md |
| 5 | `05-教学图谱` | 教学图谱 | #8E24AA | 教学内容体系图谱.md, 教学方法策略图谱.md, 考核实施指导图谱.md, 教学资源配置图谱.md |
| 6 | `06-学习图谱` | 学习图谱 | #00897B | 学习内容导航图谱.md, 实验学习指导图谱.md, 考核应对策略图谱.md, 学习方法指导图谱.md |
| 7 | `07-思政图谱` | 思政图谱 | #C62828 | 课程思政图谱.md |

**Step B: 思政图谱 content** — Extract from syllabus "课程思政元素" sections:

Ch1: 科技自立自强意识与知识体系化思维
Ch2: 信息安全意识与数据伦理观念
Ch3: 终身学习意识与自我管理能力
Ch4: 教育强国意识与技术创新精神
Ch5: 数据驱动的教育决策意识
Ch6: 严谨的科学态度与工匠精神
Ch7: 教育公平意识与质量保障理念
Ch8: 教育管理现代化意识与数据驱动的教学决策思维

**Step C: Make `GraphImportService` course-aware**

**Modified: `lib/services/graph_import_service.dart`**

1. Change `_categories` from `static const` to a method that loads based on course:
```dart
static Future<List<_Category>> _getCategories(String courseId) async {
  if (courseId == 'ckgdt') {
    return [
      _Category('01-课程图谱', '课程图谱', '#E53935'),
      _Category('02-平台技术图谱', '平台技术图谱', '#1E88E5'),
      _Category('03-实验图谱', '实验图谱', '#FB8C00'),
      _Category('04-项目图谱', '项目图谱', '#43A047'),
      _Category('05-教学图谱', '教学图谱', '#8E24AA'),
      _Category('06-学习图谱', '学习图谱', '#00897B'),
      _Category('07-思政图谱', '思政图谱', '#C62828'),
    ];
  }
  // Default: MAD categories (6)
  return [...];
}
```

2. Change `_categoryFiles` similarly — course-aware file lists
3. Change `_crossRefs` to include 7th category
4. Change asset path prefix: `assets/graphs/ckgdt/` for CKGDT, `assets/graphs/` for MAD
5. Add 7th color/icon to `GraphListPage._defaultColors` and `_defaultIcons`

**Step D: Update `pubspec.yaml`**

Add `assets/graphs/ckgdt/` to flutter assets section.

**Step E: Update `grading_agent.dart:677`**

Change hardcoded `'assets/graphs/06-学习图谱/实验学习指导图谱.md'` to use course-aware path.

---

## Issue 3: Experiment Materials — MAD → CKGDT

### Current State
- `materials_tab.dart:289-322` — hardcoded MAD fallback file lists
- `materials_tab.dart:90-91` — old Gitee namespace `osgisOne/mad-data`
- `student_lab_page.dart:247-254` — hardcoded `'data/实验/实验指导/'` and `'data/实验/报告模板/'` (no CKGDT variant)
- `student_lab_page.dart:847-848` — old Gitee namespace `osgisOne/mad-data`

### Changes

**Modified: `lib/presentation/pages/lab/tabs/materials_tab.dart`**

1. Lines 90-91: Change `_dataRepoOwner` from `'osgisOne'` to `'chzcldl'`, `_dataRepoName` from `'mad-data'` to `'mad-data'` (same name, different owner)

2. Lines 289-322: Update `knownFiles` fallback for `data/实验/` paths — these should remain as MAD fallback (they're the MAD course's files). The CKGDT paths at lines 263-288 are already correct.

3. Lines 42-44: The CKGDT description is already correct: `'8 个 CKGDT 实验的详细步骤教程'`

4. The real issue from screenshot: the page is showing MAD experiments because `isCkgdt` check is failing or the CKGDT asset files don't exist. Need to verify `data/CKGDT/实验/实验教程/` has the correct files.

**Modified: `lib/presentation/pages/learning/student_lab_page.dart`**

1. Lines 247-248: Change hardcoded `'data/实验/实验指导/'` to course-aware: `isCkgdt ? 'data/CKGDT/实验/实验指导/' : 'data/实验/实验指导/'`
2. Lines 254-255: Change hardcoded `'data/实验/报告模板/'` to course-aware: `isCkgdt ? 'data/CKGDT/实验/报告模板/' : 'data/实验/报告模板/'`
3. Lines 847-848: Change `_dataRepoOwner` from `'osgisOne'` to `'chzcldl'`

**Verify: `data/CKGDT/实验/` directory has all required files**

Check that these exist:
- `实验教程/` — 8 CKGDT experiment tutorial .md files
- `平台技术栈/` — README.md
- `实验指导/` — README.md
- `报告模板/` — 8 CKGDT report template .md files

---

## Issue 4: Resource Versioning

Implement from the previous plan (`docs/plan-resource-versioning.md`):

1. Create `data/CKGDT/配置/mask_shapes.json` (done in Issue 1)
2. Enhance `data/CKGDT/配置/manifest.json` with per-resource checksums
3. New DB table `resource_packages` (V37 migration)
4. New model `ResourcePackageModel`
5. New DAO `ResourcePackageDao`
6. New service `ResourceVersionService`
7. Enhance `CourseResourceService` with version comparison
8. Admin UI for resource version display
9. Python script `tools/compute_resource_checksums.py`

---

## Execution Order

1. **Issue 3 first** (experiment materials) — quickest win, fixes visible bug
2. **Issue 2** (graph content) — create CKGDT .md files + update GraphImportService
3. **Issue 1** (mask config) — create JSON config + update mask_widgets.dart
4. **Issue 4** (versioning) — larger feature, build on top of the above

## Verification

1. `flutter analyze lib/` — 0 new errors
2. Launch app → 图谱 → 结构图谱: should show 7 CKGDT categories (not 6 MAD)
3. Launch app → 图谱 → 知识图谱 → 蒙版视图: categories load from JSON
4. Launch app → 实验 → 实验材料: should show CKGDT experiments (not MAD)
5. Settings → 管理员设置 → 资源版本管理: shows package versions
6. `flutter build windows --release` — builds successfully
