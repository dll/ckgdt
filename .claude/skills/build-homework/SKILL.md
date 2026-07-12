---
name: build-homework
description: 作业功能完整指南：出题模板、学生提交、AI批阅、教师审核、成绩同步。涵盖模型/DAO/页面/智能体/课程包导入。触发：用户说"作业"/"作业技能"/"homework"/"布置作业"/"批改作业"。
---

# 作业功能指南（Homework）

## 数据模型（`lib/data/models/homework_model.dart`）

| 类 | 表 | 说明 |
|---|---|---|
| `HomeworkModel` | `homeworks` | 作业定义：`course_id`, `title`, `chapter`, `chapter_title`, `course_objective`, `total_score`, `deadline`, `status`(draft/published/closed) |
| `HomeworkItemModel` | `homework_items` | 题目：`item_index`, `type`(basic/practice/thinking), `type_label`(基础题/提高题/拓展题), `question`, `reference_answer`, `max_score`, `objective_mapping`(JSON → 目标贡献度) |
| `HomeworkSubmissionModel` | `homework_submissions` | 提交：`item_id`, `user_id`, `answer_text`, `answer_file_path`, `score`, `ai_comment`, `teacher_comment`, `status`(submitted/ai_graded/teacher_reviewed) |
| `ObjectiveMapping` | 嵌入 `homework_items.objective_mapping` | `objective_id` + `contribution`(0-1) |

**DDL**（`database_helper.dart:3941`）：
```sql
CREATE TABLE IF NOT EXISTS homeworks(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  course_id TEXT NOT NULL, title TEXT NOT NULL,
  description TEXT DEFAULT '', chapter TEXT DEFAULT '',
  chapter_title TEXT DEFAULT '', course_objective TEXT DEFAULT '',
  total_score INTEGER DEFAULT 100, deadline TEXT,
  status TEXT DEFAULT 'published', created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS homework_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT, homework_id INTEGER NOT NULL,
  item_index INTEGER NOT NULL, type TEXT NOT NULL,
  type_label TEXT NOT NULL, question TEXT NOT NULL,
  reference_answer TEXT, max_score INTEGER DEFAULT 100,
  objective_mapping TEXT DEFAULT '[]',
  FOREIGN KEY (homework_id) REFERENCES homeworks(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS homework_submissions(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  homework_id INTEGER NOT NULL, item_id INTEGER NOT NULL,
  user_id TEXT NOT NULL, answer_text TEXT, answer_file_path TEXT,
  score INTEGER, ai_comment TEXT, teacher_comment TEXT,
  status TEXT DEFAULT 'submitted',
  submitted_at TEXT NOT NULL, graded_at TEXT,
  FOREIGN KEY (homework_id) REFERENCES homeworks(id) ON DELETE CASCADE,
  FOREIGN KEY (item_id) REFERENCES homework_items(id) ON DELETE CASCADE
);
```

---

## DAO — `HomeworkDao`（`lib/data/local/homework_dao.dart`）

### CRUD
| 方法 | 用途 |
|---|---|
| `createHomework(hw)` | 插入作业 |
| `getHomeworks(courseId)` | 按课程列出，按 `created_at DESC` |
| `getHomework(id)` | 单个查询 |
| `updateStatus(id, status)` | draft / published / closed |
| `deleteHomework(id)` | 级联删除 items + submissions |

### 题目
| 方法 | 用途 |
|---|---|
| `insertItems(homeworkId, items)` | 批量插入，自动填入 `item_index` |
| `getItems(homeworkId)` | 按 `item_index` 排序，自动解析 `objective_mapping` JSON |

### 提交与批阅
| 方法 | 用途 |
|---|---|
| `submit(sub)` | Upsert（同 homework_id+item_id+user_id 更新已有提交） |
| `getSubmissions(homeworkId, userId)` | 学生端：获取自己的提交 |
| `getAllSubmissions(homeworkId)` | 教师端：所有学生按 `user_id, item_id` 排序 |
| `updateAiGrade(submissionId, score, comment)` | AI 批阅 → status `ai_graded` |
| `updateTeacherReview(submissionId, score, comment)` | 教师审核 → status `teacher_reviewed` |

### 统计与达成
| 方法 | 用途 |
|---|---|
| `getStudentScore(homeworkId, userId)` | SUM score（单人单次作业总分） |
| `getSubmissionStats(homeworkId)` | `{total, graded}` 去重学生数 |
| `getStudentHomeworkAverage(courseId, userId)` | 课程平均分 → 达成度 |
| `getStudentHomeworkByChapter(courseId, userId)` | Map<chapter, avg> → 目标贡献度 |
| `getClassHomeworkAverages(courseId)` | Map<chapter, avg> → 班级报告 |
| `syncToAchievementScores(courseId)` | 推送至 `achievement_pingshi_scores` 表（兼容旧表两种 schema） |

### 导入
| 方法 | 用途 |
|---|---|
| `importFromJson(courseId, jsonContent)` | 从 `homework.json` 批量导入 |

---

## 页面路由

| 页面 | 文件 | 路由ID |
|---|---|---|
| 作业列表 | `lib/presentation/pages/learning/homework_list_page.dart` | `'homework'` → `HomeworkListPage()`（`navigation_service.dart:439`） |
| 作业详情/提交 | `lib/presentation/pages/learning/homework_detail_page.dart` | Navigator.push |
| 教师批阅 | `lib/presentation/pages/learning/homework_grading_page.dart` | Navigator.push |

---

## 页面功能详解

### 1. `HomeworkListPage` — 作业列表

- **学生端**（`isTeacher=false`）：我的作业 — 显示 chapter/chapterTitle/总分/状态/创建时间
- **教师端**（`isTeacher=true`）：作业管理 — 点击进入详情查看提交
- **嵌入模式**（`embedded=true`）：去掉 Scaffold/AppBar，供 TabBarView 使用
- 空状态占位：图标 + "暂无作业" + "教师布置作业后将在此显示"

### 2. `HomeworkDetailPage` — 作业详情/提交

**学生视图**（默认）：
- **题目标题栏**：题号 + 类型标签（基础题/提高题/拓展题） + 分值
- **目标映射 Chip**：`目标N: XX%`（如 `objective_mapping=[{"objective_id":1,"contribution":0.5}]`）
- **答案输入**：`TextField(maxLines:6)` —— 支持多行文本
- **答案工具栏**（4 个操作）：

| 按钮 | 功能 |
|---|---|
| 粘贴 | `Clipboard.getData` → 填入 TextField |
| 清空 | 确认弹窗后清空 |
| AI批阅 | 先保存提交 → AI 打分 `_aiGradeOne()` |
| 上传附件 | `FilePicker` → `.mdg/.md/.pdf/.docx/.txt` |

- **已提交展示区**（提交后只读）：
  1. 答案文本（绿色背景容器）
  2. 附件文件路径
  3. AI 评语（蓝色智能体图标 + 得分）
  4. 教师评语（橙色人形图标）
  5. **重新提交**按钮：清空后回到编辑状态

**教师视图**（`isTeacher=true`）：
- **参考答案**：可折叠展示 `referenceAnswer`（"查看参考答案"/"隐藏参考答案"）
- **学生答案**：灰色背景只读展示
- **AI 评语**：只读展示
- **教师评语 + 分数输入**：两个 TextField

**关键逻辑** `_submitAll()`：
1. 遍历所有题目，收集 `answer_text` + `answer_file_path`
2. `_dao.submit()` 保存到 `homework_submissions`
3. 自动调用 `_aiGradeAll()`：逐题调用 `AiService.chat()` 批阅
4. 批阅后调用 `syncToAchievementScores()` 同步达成度

**AI 批阅 Prompt 格式**：
```
你是一位严谨的教师，请批阅以下作业。

题目：${question}
类型：${typeLabel}
参考答案：${referenceAnswer}
学生答案：${answer}

满分 ${maxScore} 分。请：
1. 给出得分（0-${maxScore}）
2. 简要评语（优点+改进建议，100字以内）

返回 JSON：{"score": 分数, "comment": "评语"}
```

**JSON 解析**：`_parseJson()` 支持 `\`\`\`json ... \`\`\`` fences 和裸 JSON 两种；`_safeDecode()` 通过 `indexOf('{')` / `lastIndexOf('}')` 截取。

### 3. `HomeworkGradingPage` — 教师批量批阅

**列表页**：每张卡片显示作业标题 + chapterTitle + 提交/已批/待批 3 个统计 Chip + 截止日期
**批阅详情**（`_HomeworkGradingDetail`）：
- 按 `ExpansionTile` 按学生分组，每人一张卡片
- 每道题 inline 分数输入框（`TextFormField` + `onFieldSubmitted` → `updateAiGrade`）
- **AppBar 全部 AI 批阅**按钮：逐题/逐人调用 AI，已有分数 >0 的跳过

---

## 课程包导入导出

### `course_package_loader.dart` — `_syncHomeworks()`

- 从 `homework.json` 读取每章作业
- `title` = `'$chapterTitle作业'`
- 按 `course_id + title` 自然键匹配已有作业（幂等导入）
- 匹配到的更新 + 删除旧 items 重建；不匹配的新增
- 同时写入 `knowledge_concepts` 表（`concept_type: 'homework'`）

### `course_generator_sheet.dart`

- 一键生课直接写 `homeworks` / `homework_items` 表
- 清理旧数据：先删 submissions → items → homeworks
- JSON 字段 `objective_mapping` 以字符串存入

### 包文件清单

资源包 `homework.json` 格式示例：
```json
[
  {
    "chapter": "1",
    "chapter_title": "知识图谱基础",
    "course_objective": "掌握图谱基本概念",
    "items": [
      {
        "type": "基础题",
        "type_code": "basic",
        "question": "什么是知识图谱？",
        "reference_answer": "知识图谱是一种结构化的知识表示方式...",
        "max_score": 100,
        "objective_mapping": [{"objective_id": 1, "contribution": 1.0}]
      }
    ]
  }
]
```

---

## 智能体集成

### GradingAgent（`grading_agent.dart`）

已有作业相关支持：
- `keywords` 包含 `'作业'` `'批阅'` `'评分'` `'批改'`
- `matchScore()` 对含 `作业` 的消息 +0.1 boost
- **但无专用的 `gradeHomework()` 方法**（只有 `gradeSubmission`(实验) / `gradeReport`(考核) / `gradeWork`(作品)）

**需要新增的内容**（如要完善智能体作业批阅）：

#### 新增工具（`tools` 列表添加）：
```dart
AgentTool(
  name: 'get_homework_list',
  description: '获取当前课程的作业列表，返回作业ID/标题/提交统计',
  parameters: {},
  execute: (params) async { ... },
),
AgentTool(
  name: 'get_homework_submissions',
  description: '获取某次作业的所有学生提交',
  parameters: {'homeworkId': '作业ID (int)'},
  execute: (params) async { ... },
),
```

#### 新增方法：
```dart
Future<String> gradeHomework({
  required int homeworkId,
  required int itemId,
  required String question,
  required String? referenceAnswer,
  required String studentAnswer,
  int maxScore = 100,
}) async { ... }
```

#### Persona 补充段落（agent_config 的 persona 尾部追加）：
```
### 类型四：作业批阅
{type: 'homework'}
1. **参考答案对比**（40%）：是否覆盖参考答案要点
2. **逻辑与分析**（30%）：论证是否清晰、推理是否完整
3. **表达与规范**（20%）：语言表达、格式规范
4. **创新与拓展**（10%）：是否有独特见解或额外价值
```

修改位置：`grading_agent.dart` — `persona` 段落后追加，`tools` 列表添加，`handleMessage()` 添加 homework 分支。

---

## 作业生命周期

```
教师创建作业（course_generator / 直接SQL）
    ↓
作业发布（status: draft → published）
    ↓
学生提交答案（text + file）
    ↓
AI 自动批阅（逐题评分 + 评语）
    ↓
教师审核（可选：调整分数 + 教师评语）
    ↓
成绩同步 → achievement_pingshi_scores
    ↓
作业关闭（status: published → closed）
```

---

## 测试验证

```bash
# 验证 homework 表 schema
flutter analyze lib/data/models/homework_model.dart lib/data/local/homework_dao.dart

# 验证页面编译
flutter analyze lib/presentation/pages/learning/homework_list_page.dart
flutter analyze lib/presentation/pages/learning/homework_detail_page.dart
flutter analyze lib/presentation/pages/learning/homework_grading_page.dart

# 验证课程包导入
flutter test test/services/course_package_loader_test.dart

# 验证导航路由
rg -n "homework" lib/services/navigation_service.dart
```

---

## 不要做的事

❌ **不要**单独新增 `homework_agent.dart` — 作业批阅应集成到 `grading_agent.dart`，复用已有的 GradingAgent 机制
❌ **不要**修改 `homework_submissions` 的 PK/UPSERT 逻辑（`submit()` 按 `homework_id+item_id+user_id` 自然键判断）
❌ **不要**在 UI 页面直接写 SQL — 所有作业 DB 操作必须走 `HomeworkDao`
❌ **不要**删除 `syncToAchievementScores()` 调用 — 作业成绩需要同步到达成度系统
❌ **不要**在 homework.json 里写 CKGDT/MAD 等具体课程名 — 必须平台化
