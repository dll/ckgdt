# CLAUDE.md — 移动图谱与数字孪生教学系统（MAD-KG）

## 项目概述

**移动图谱与数字孪生教学系统（MAD-KG）** 是面向《移动应用开发》课程的 Flutter 全平台教学平台。系统围绕"教—学—练—评—管"五个维度构建：知识图谱浏览、章节测验、视频教程、课程资料、实验管理、作品展示、成绩达成、AI 多智能体辅助。支持教师端和学生端差异化导航，通过 Gitee 仓库实现师生数据双向同步。

- **仓库**：https://gitee.com/osgisOne/mad-fd
- **当前版本**：`0.10.0`（`pubspec.yaml` → `version: 0.10.0+11`）
- **Flutter SDK**：`>=3.0.0 <4.0.0`
- **主题色**：`#667eea`（紫蓝渐变 `[0xFF667eea, 0xFF764ba2]`）
- **用户角色**：学生 / 教师 / 管理员
- **目标平台**：Android、Windows、Web、HarmonyOS（OHOS）

---

## 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | Flutter 3 + Material Design 3 |
| 本地数据库 | sqflite + 自定义 DAO（59 张表） |
| AI 服务 | DeepSeek / 智谱 GLM-4（多 provider） |
| 多智能体 | 24 个专业 Agent + RAG 检索增强 |
| 语音交互 | 讯飞 WebSocket STT + AI 意图识别 |
| 数据同步 | Gitee 仓库 JSON 双向同步 |
| 图谱绘制 | CustomPainter + InteractiveViewer |
| 图表 | fl_chart（折线图/雷达图） |
| 视频生成 | Python 3 + moviepy + edge-tts |

---

## 课程内容（6 章）

| 章节 | 主题 |
|------|------|
| 第 1 章 | 移动应用开发技术体系全景 |
| 第 2 章 | Android 与 iOS 原生开发基础 |
| 第 3 章 | Flutter、React Native 等混合开发技术 |
| 第 4 章 | 微信小程序开发流程 |
| 第 5 章 | 华为 HarmonyOS 多端应用开发 |
| 第 6 章 | 综合开发实践 |

支持通过"一键生课"功能切换到其他课程（`courses` 表 + `CourseGeneratorSheet`）。

---

## 导航结构（角色差异化）

`HomePage` 根据用户角色动态构建 `NavigationBar`：

### 教师/管理员导航

| 索引 | Tab | Widget |
|------|-----|--------|
| 0 | 首页 | `_buildHome()` |
| 1 | 图谱 | `KnowledgeGraphPage` |
| 2 | 教学 | `LearningHubPage` |
| 3 | 课堂 | `ClassroomPage` |
| 4 | 实验 | `LabTasksPage` |
| 5 | 考核 | `AssessmentPage` |
| 6 | 作品 | `WorksPage` |
| 7 | 达成 | `AchievementPage` |
| 8 | 管理 | `_AdminToolsPage`（仅管理员） |

### 学生导航

| 索引 | Tab | Widget |
|------|-----|--------|
| 0 | 首页 | `_buildHome()` |
| 1 | 图谱 | `KnowledgeGraphPage` |
| 2 | 学习 | `LearningHubPage` |
| 3 | 实验 | `StudentLabPage` |
| 4 | 考核 | `AssessmentPage` |
| 5 | 作品 | `WorksPage` |

### AppBar 全局入口

- 搜索（`SearchPage`）、通知铃铛（`NotificationListPage`，带未读 Badge）、用户菜单（设置/进度/学习中心/登出）

### 二级页面（Navigator.push）

通过 `NavigationService.resolveSubPage(routeId)` 统一路由，支持 30+ 子页面：
`QuizPage`、`WrongAnswersPage`、`VideoListPage`、`DocumentListPage`、`FavoritesPage`、`GraphDetailPage`、`LearningPlanPage`、`ProgressPage`、`HandbookPage`、`AiSkillPage`、`DataSyncPage`、`VoiceSettingsPage`、`CourseManagePage`、`StudentCenterPage`、`TeacherWorkspacePage`、`ChatHistoryPage` 等。

---

## 目录结构

```
lib/
├── main.dart                              # 入口：DB 初始化、主题、竖屏锁定、语音导航
├── data/
│   ├── models/                            # 纯数据类（12 个），无 Flutter 依赖
│   │   ├── ai_config_model.dart           # AI 配置（provider/model/key）
│   │   ├── course_model.dart              # 课程定义
│   │   ├── learning_path_model.dart       # 学习路径
│   │   ├── material_model.dart            # 生成素材
│   │   ├── puml_file_model.dart           # PlantUML 图
│   │   └── user/graph/node/edge/question/quiz_result_model.dart
│   └── local/                             # DAO 层（26 个）
│       ├── database_helper.dart           # 单例 DB，59 张表
│       ├── lab_task_dao.dart              # 实验任务/提交/报告
│       ├── achievement_dao.dart           # 成绩达成（平时/实验/考试）
│       ├── assessment_dao.dart            # 项目考核/答辩
│       ├── works_dao.dart                 # 学生作品/评分/评论/点赞
│       ├── classroom_dao.dart             # 签到/课堂消息
│       ├── notification_dao.dart          # 通知/接收状态
│       ├── survey_dao.dart                # 问卷调查
│       ├── teaching_dao.dart              # 教学大纲/教案/进度
│       ├── collaboration_dao.dart         # 协作消息/同行评审
│       ├── knowledge_graph_dao.dart       # 知识概念/关系
│       ├── learning_path_dao.dart         # 学习路径/节点
│       ├── course_dao.dart                # 课程管理
│       ├── class_dao.dart                 # 班级/成员
│       ├── feedback_dao.dart              # 用户反馈
│       ├── skill_dao.dart                 # 技能评测结果
│       ├── ai_config_dao.dart / ai_history_dao.dart
│       └── user/graph/quiz/learning_record/favorite/wrong_answer/material/puml_dao.dart
├── services/
│   ├── ai_service.dart                    # 多 provider AI 调用（chat/generate/test）
│   ├── rag_service.dart                   # RAG 检索增强（课程内容知识库）
│   ├── sync_service.dart                  # Gitee 双向同步（含 task_id 重映射）
│   ├── gitee_service.dart                 # Gitee API 封装
│   ├── navigation_service.dart            # 全局导航（Tab 映射 + 子页面路由）
│   ├── notification_service.dart          # 通知触发与分发
│   ├── voice_service.dart                 # 讯飞语音识别（WebSocket STT）
│   ├── tts_service.dart / tts_flutter_service.dart  # TTS 语音合成
│   ├── auth_service.dart                  # 登录/登出/角色判断
│   ├── courseware_service.dart             # 课件管理
│   ├── courseware_download_service.dart    # 课件下载（本地优先 + Gitee mad-data 仓库远程兜底）
│   ├── output_path_service.dart            # 输出目录（桌面 → exe/out/，移动端 → 文档目录）
│   ├── file_upload_service.dart           # 文件上传
│   ├── graph_layout_service.dart          # 图谱布局算法
│   ├── knowledge_extract_service.dart     # 知识抽取
│   ├── video_service.dart                 # 视频服务
│   ├── settings_service.dart / theme_manager.dart
│   ├── data_service.dart / data_loading_service.dart / data_migration_service.dart
│   ├── cross_platform/                    # 跨平台同步协议
│   │   ├── sync_protocol.dart / sync_client.dart
│   │   └── sync_server.dart (+io/stub)
│   └── agent/                             # 多智能体框架
│       ├── agent_model.dart               # AgentConfig（persona/tools/cases）
│       ├── agent_registry.dart            # 智能体注册表
│       ├── base_agent.dart                # 基类（会话管理/AI 调用/工具执行）
│       └── agents/                        # 24 个专业智能体
│           ├── voice_agent.dart           # 语音导航（AI 意图识别）
│           ├── graph_agent.dart           # 图谱专家（含工具调用）
│           ├── tutor_agent.dart           # 智能辅导
│           ├── quiz_agent.dart            # 测验生成
│           ├── lab_agent.dart             # 实验指导
│           ├── lab_grading_agent.dart      # 实验批阅
│           ├── assessment_grading_agent.dart # 考核批阅
│           ├── works_grading_agent.dart    # 作品批阅
│           ├── safety_agent.dart           # 安全审查
│           ├── courseware_agent.dart       # 课件生成
│           ├── course_gen_agent.dart       # 一键生课
│           ├── virtual_student_agent.dart  # 数字孪生-学生
│           ├── virtual_teacher_agent.dart  # 数字孪生-教师
│           └── ... (assistant/learning/path/mobile_expert/ethics/...)
└── presentation/
    ├── widgets/                            # 可复用组件（6 个）
    │   ├── agent_chat_overlay.dart         # 智能体对话浮层（支持 7 种导航动作）
    │   ├── agent_entry_button.dart         # 智能体入口按钮
    │   ├── voice_input_button.dart         # 语音输入按钮
    │   ├── markdown_bubble.dart            # Markdown 气泡渲染
    │   ├── mad_mascot_button.dart          # 吉祥物悬浮按钮
    │   └── course_generator_sheet.dart     # 一键生课表单
    └── pages/                              # 88 个页面
        ├── home/                           # 首页/搜索/设置
        ├── graph/                          # 图谱列表/详情/收藏/属性/知识图谱
        ├── quiz/                           # 测验/错题本
        ├── learning/                       # 学习中心/视频/文档/进度/计划/实验
        ├── lab/                            # 实验任务管理/协作/产品化指南
        ├── materials/                      # 素材中心/AI助手/课件/PlantUML/设置
        ├── admin/                          # 学生/教师/班级/题库/实验/问卷/教学管理
        ├── assessment/                     # 项目考核
        ├── works/                          # 学生作品展示
        ├── achievement/                    # 成绩达成
        ├── classroom/                      # 课堂互动（签到/消息）
        ├── notification/                   # 通知列表/发送
        ├── profile/                        # 学生中心/教师工作台/聊天历史
        ├── practice/                       # 深度实践/成长曲线
        ├── feedback/                       # 反馈/AI帮助
        ├── survey/                         # 问卷调查
        ├── repo/                           # Git 仓库管理/学生仓库
        ├── sync/                           # 数据同步页面
        ├── settings/                       # AI数据/课程管理/语音设置
        ├── skill/                          # AI 技能页面
        ├── analytics/                      # 学习分析
        ├── help/                           # 使用手册
        ├── cross_platform/                 # 跨平台同步/扫码
        └── login/                          # 登录页
```

---

## 数据库设计（59 张表）

数据库由 `DatabaseHelper`（单例）管理，首次启动从 `assets/learning_data.db` 复制。

### 种子数据库初始化流程（关键）

种子 DB `assets/learning_data.db` 已预置 `user_version = 20`，包含 52 道测验题、23 个图谱等种子数据。初始化流程为三层防御：

```
1. 复制 seed DB → assets/learning_data.db → knowledge_graph.db（仅首次）
2. 打开 DB（version: 20）→ 若 seed DB 已设置 user_version=20，则跳过 onCreate/onUpgrade
3. _ensureAllTables() → 始终执行，确保 59 张表存在
4. _verifyAndRepairSeedData() → 检查 questions/graphs 是否为空，若空则从 seed DB 重新导入
```

**关键点**：
- 种子 DB 的 `user_version = 20` 是核心：匹配 `openDatabase(version: 20)` 时，sqflite 不会触发 `onCreate`/`onUpgrade`，种子数据得以完整保留
- `_importTableSafe()` 方法会对比目标表列名，只迁移匹配的列（处理 seed DB 与应用 DB 的 schema 差异）
- 三层防御确保：正常复制 → 版本匹配跳过迁移 → 异常时自动修复空数据

### 核心表

| 表名 | 说明 | 关键字段 |
|------|------|---------|
| `users` | 用户 | `user_id`, `role`(student/teacher/admin), `is_active` |
| `current_session` | 登录会话（单行 id=1） | `user_id`, `machine_code` |
| `graphs` / `nodes` / `edges` | 知识图谱 | `graph_id`, `node_type`, `level`, `x`, `y`, `parent_id` |
| `questions` | 测验题（四选一） | `source`(章节), `answer_index`(0-3) |
| `quiz_results` | 测验成绩 | `user_id`, `score`, `chapter` |
| `learning_records` | 学习记录 | `user_id`, `node_id`, `study_time` |
| `wrong_answers` | 错题本 | `times`（累加）, `last_wrong_time` |
| `favorites` | 收藏 | `node_id`, `node_title` |
| `resource_files` | 课程资料(pdf/ppt/video) | `file_type`, `chapter` |

### 实验与作品

| 表名 | 说明 |
|------|------|
| `lab_tasks` | 实验任务定义 |
| `lab_submissions` | 学生实验提交 |
| `report_templates` / `student_reports` | 实验报告模板与提交 |
| `student_works` / `work_scores` | 学生作品与评分 |
| `work_comments` / `work_likes` / `work_views` | 作品互动 |

### 考核与成绩

| 表名 | 说明 |
|------|------|
| `assessment_groups` / `assessment_projects` / `project_scores` / `defense_records` | 项目考核 |
| `achievement_batches` / `achievement_scores` | 成绩批次 |
| `achievement_pingshi_scores` / `achievement_experiment_scores` / `achievement_exam_scores` | 三维成绩 |
| `contribution_scores` | 贡献分 |

### 教学管理

| 表名 | 说明 |
|------|------|
| `courses` | 课程定义 |
| `classes` / `class_members` | 班级管理 |
| `syllabus_items` / `lesson_plans` / `teaching_progress` | 教学大纲/教案/进度 |
| `surveys` / `survey_questions` / `survey_responses` | 问卷调查 |
| `checkin_sessions` / `checkin_records` | 签到 |
| `classroom_messages` | 课堂消息 |

### AI 与协作

| 表名 | 说明 |
|------|------|
| `ai_configs` | AI 配置（provider/key/model） |
| `ai_chat_history` | 智能体对话记录 |
| `notifications` / `notification_recipients` | 通知系统 |
| `collaboration_messages` / `peer_reviews` | 协作 |
| `feedback` | 用户反馈 |
| `knowledge_concepts` / `concept_relations` / `concept_progress` | 知识概念 |
| `learning_paths` / `path_nodes` | 学习路径 |
| `generated_materials` / `puml_files` / `skill_results` / `graph_analysis` / `resource_chapter_mapping` | 其他 |

### 默认账号

- 管理员：`user_id = '419116'`，密码 = `'419116'`
- **密码规则**：所有用户密码 = `userId.substring(userId.length - 6)`，**不可更改**

---

## 多智能体系统

### 架构

```
AgentRegistry (单例)
  ├── BaseAgent (抽象基类)
  │   ├── AgentConfig (persona/tools/cases/usageSteps)
  │   ├── AgentSession (多轮对话上下文)
  │   └── handleMessage() → AI 推理 + 工具调用
  └── 24 个专业 Agent
```

### 智能体列表

| Agent | 功能 | 工具调用 |
|-------|------|---------|
| `voice` | 语音导航（AI 意图识别 → 结构化导航指令） | NavigationService |
| `graph` | 知识图谱生成与分析 | search_nodes, get_node_details |
| `tutor` | 智能辅导答疑 | RAG 检索 |
| `quiz` | 测验题生成 | DB 查询 |
| `lab` | 实验指导 | — |
| `lab_grading` | 实验报告 AI 批阅 | lab_task_dao |
| `assessment_grading` | 项目考核 AI 批阅 | assessment_dao |
| `works_grading` | 学生作品 AI 批阅 | works_dao |
| `safety` | 内容安全审查 | — |
| `courseware` | 课件生成 | slide_generator |
| `course_gen` | 一键生课 | course_dao |
| `assistant` | 通用助手 | — |
| `learning` | 学习路径推荐 | learning_path_dao |
| `path` | 学习计划制定 | — |
| `mobile_expert` | 移动开发专家 | — |
| `ethics` | 学术伦理指导 | — |
| `achievement` | 成绩分析 | achievement_dao |
| `doc_converter` | 文档格式转换 | — |
| `repo` | Git 仓库分析 | gitee_service |
| `madkg` | 系统使用指南 | — |
| `works` | 作品展示指导 | — |
| `assessment` | 考核管理（分组/答辩/成绩查询） | assessment_dao |
| `virtual_student` | 数字孪生-学生人格模拟 | — |
| `virtual_teacher` | 数字孪生-教师督导辅助 | — |

### 对话入口

- `AgentChatOverlay`：全局浮层，支持 7 种导航动作（`navigate_tab`/`navigate_sub_page`/`go_back`/`pop_to_root`/`exit_app`/`navigate_home`/`navigate_login`）
- `AgentEntryButton`：首页快捷入口
- `VoiceInputButton`：语音输入 → VoiceAgent

---

## 数据同步架构

### 同步机制

通过 Gitee 仓库实现师生数据双向同步（无服务器）：

```
学生设备 → JSON 文件 → Gitee 仓库 → JSON 文件 → 教师设备
            uploadStudentData()              downloadStudentData()
```

### 同步关键文件

- `SyncService`：`sync_service.dart` — 收集/导入学生数据
- `GiteeService`：`gitee_service.dart` — Gitee API 上传下载
- `FileUploadService`：`file_upload_service.dart` — 实验报告文件上传

### 同步注意事项

- **task_id 重映射**：每台设备的 `lab_tasks` 自增 ID 不同，同步时通过 `title` 字段做自然键匹配，构建 `Map<int,int>` 映射表
- **批改数据保护**：导入学生数据时，已批改的 `lab_submissions`（有 `score`/`feedback`）不被覆盖
- **即时同步**：学生提交实验报告后立即触发 `unawaited(SyncService().uploadStudentData(userId))`，不等定时器

---

## 语音导航

### 4 层路由

```
语音文本 → 1. 快速路径（返回/退出）
         → 2. NavigationService Tab 映射（首页/图谱/学习/...）
         → 3. NavigationService 子页面匹配（30+ 页面）
         → 4. VoiceAgent AI 兜底（自然语言意图识别）
```

### 技术栈

- STT：讯飞 WebSocket API（`voice_service.dart`）
- TTS：`tts_service.dart` / `tts_flutter_service.dart`
- 意图识别：VoiceAgent（`requiresAi: true`）→ JSON 结构化输出

---

## AI 服务

### Provider 配置

- API Key 存入 `ai_configs` 表，通过 `AiConfigDao` 读写
- 数据库初始化时插入默认配置（DeepSeek）
- 支持 DeepSeek / 智谱 GLM-4 / GLM-4.6v 多 provider 切换
- **不在代码中硬编码 API Key**（默认配置通过 DB 迁移写入）

### RAG 检索增强

`RagService`：基于课程内容构建知识库，智能体对话时自动检索相关文档片段注入 prompt。

### AI 技能

`AiSkillPage`：9 个技能（辅导/测验/课件/图谱/脚本/PPT/UML/报告/代码），内部调用对应智能体。

---

## 开发规范

### 分层原则

```
models   →  不依赖 Flutter/sqflite
dao      →  只依赖 sqflite + DatabaseHelper
services →  组合 DAO，处理业务逻辑
pages    →  只调用 services/dao，不直接操作 DB
```

### 编码规范

1. **无状态管理框架**：状态在 `StatefulWidget` 内管理
2. **DAO 模式**：每张业务表对应一个 DAO
3. **命名**：文件 `snake_case.dart`，类 `PascalCase`，私有 `_camelCase`
4. **异步**：所有 DB 操作 `async/await`，UI 层 `try/catch` 静默降级
5. **透明度**：使用 `color.withValues(alpha: 0.x)` 代替废弃的 `withOpacity()`
6. **竖屏锁定**：`main()` 中 `SystemChrome.setPreferredOrientations`，不要删除
7. **跨平台兼容**：涉及文件系统的服务使用 `_native.dart` + `_stub.dart` 条件导入

### 新增页面

1. 在 `lib/presentation/pages/<模块>/` 下创建
2. 新 Tab → `home_page.dart` 的 destinations + bodyMap 同步添加
3. 新子页面 → `navigation_service.dart` 的 `resolveSubPage()` 添加 case
4. 页面间跳转使用 `Navigator.push`，不用命名路由

---

## 常用命令

```bash
flutter pub get                              # 获取依赖
flutter run                                  # 运行（连接设备）
flutter analyze                              # 静态分析
flutter test                                 # 运行测试
flutter build apk --release                  # Android APK
flutter build windows --release              # Windows 桌面
flutter build web --release                  # Web
flutter clean                                # 清理缓存
```

---

## 构建产物命名规范

**统一名称格式**：`移动图谱v{版本号}`（如 `移动图谱v0.10.0`）

升版时需同步修改以下文件（将 `X.Y.Z` 替换为新版本号）：

| 平台 | 文件 | 字段 |
|------|------|------|
| 全局 | `pubspec.yaml` | `version: X.Y.Z+N` |
| Android | `android/app/src/main/AndroidManifest.xml` | `android:label="移动图谱vX.Y.Z"` |
| Windows | `windows/CMakeLists.txt` | `set(BINARY_NAME "移动图谱vX.Y.Z")` |
| Windows | `windows/runner/main.cpp` | `window.Create(L"移动图谱vX.Y.Z", ...)` |
| Windows | `windows/runner/Runner.rc` | `FileDescription` / `InternalName` / `OriginalFilename` / `ProductName` |
| Web | `web/index.html` | `<title>` 和 `apple-mobile-web-app-title` |
| Web | `web/manifest.json` | `"name"` |

> **注意**：`windows/runner/Runner.rc` 中有 4 处 `移动图谱vX.Y.Z`，需全部替换。`short_name` 保持 `移动图谱` 不带版本号。

---

## 注意事项

1. **密码规则不可更改**：`userId.substring(userId.length - 6)`，已有数据依赖此逻辑
2. **不要手动修改预置数据库**：`assets/learning_data.db` 是种子数据
3. **同步时 task_id 不可直接用**：跨设备 ID 不同，必须通过 `title` 做自然键匹配后重映射
4. **批改数据受保护**：`_importLabSubmissions()` 和 `_importStudentReports()` 会跳过已有 score 的记录
5. **不要提交中间产物**：`docs/video/**/audio/`、`slides/`、`sent/`、`temp/`、`crops/` 已 gitignore
6. **LEFT JOIN**：`lab_task_dao.getSubmissions()` 必须用 LEFT JOIN（非 INNER JOIN），否则跨设备 task_id 不匹配时提交不可见
7. **DAO 中的 CREATE TABLE IF NOT EXISTS**：部分表在 `database_helper.dart` 和对应 DAO 中都有建表语句，靠 `IF NOT EXISTS` 防冲突

---

## Git 工作流

| 分支 | 用途 |
|------|------|
| `master` | 主分支（当前活跃） |
| `develop` | 开发集成分支 |
| `feature/xxx` | 功能开发 |

**提交消息格式**：`<类型>: <简短描述>`（类型：feat / fix / refactor / docs / style / test / chore）
