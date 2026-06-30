# CLAUDE.md — 课程知识图谱与数字孪生平台（CKGDT）

## 项目概述

**课程知识图谱与数字孪生平台（CKGDT）** 是面向多课程的 Flutter 全平台教学平台。系统围绕"教—学—练—评—管"五个维度构建：知识图谱浏览、章节测验、视频教程、课程资料、实验管理、作品展示、成绩达成、AI 多智能体辅助。支持教师端和学生端差异化导航，通过 Gitee 仓库实现师生数据双向同步。

- **代码仓库**：Gitee `https://gitee.com/chzcldl/mad-kgdt`（主） · GitHub `dll/ckgdt`（镜像 + gh-pages + Release）
- **数据仓库**：`chzcldl/mad-data`（课程资源/通知） · 学生项目组仓库 `chzuczldl/cg*-*`（**详见 `docs/项目仓库设计.md`**）
- **当前版本**：`2.1.0`（`pubspec.yaml` → `version: 2.1.0+1`）
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
| 多智能体 | 18 个专业 Agent + RAG 检索增强 |
| 语音交互 | 讯飞 WebSocket STT + AI 意图识别 |
| 数据同步 | Gitee 仓库 JSON 双向同步 |
| 图谱绘制 | CustomPainter + InteractiveViewer |
| 图表 | fl_chart（折线图/雷达图） |
| 视频生成 | Python 3 + moviepy + edge-tts |

---

## 默认平台课程（CKGDT，6 章）

| 章节 | 主题 |
|------|------|
| 第 1 章 | 课程知识图谱基础 |
| 第 2 章 | 课程数据建模与资源治理 |
| 第 3 章 | 数字孪生教学场景设计 |
| 第 4 章 | 智能学习路径与学习分析 |
| 第 5 章 | 实验实践与作品评价 |
| 第 6 章 | 课程持续改进与平台应用 |

平台支持通过"一键生课"功能创建和切换到其他课程（`courses` 表 + `CourseGeneratorSheet`）。历史种子材料中仍保留《移动应用开发》课程案例、图谱和归档模板，用于兼容既有教学数据；新功能和智能体默认应以当前课程上下文为准，不再硬编码《移动应用开发》。

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
│       └── agents/                        # 18 个专业智能体
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

种子 DB `assets/learning_data.db` 已预置 `user_version = 20`，包含 52 道测验题、23 个图谱等种子数据。**应用 DB 当前 version = 24**（migrations 21-24 是增量加表 / 加列，不删数据），seed 打开时会触发 `_onUpgrade(20→24)`，结果是 schema 升级后数据保持。初始化流程：

```
1. platform_init_native.dart 显式 setDatabasesPath = ApplicationSupportDirectory/databases
   （桌面端 sqflite_common_ffi 默认是 CWD 相对路径，不同启动场景会变成"多次首次安装"）
2. 复制 seed DB → assets/learning_data.db → <support>/databases/knowledge_graph.db（仅首次）
3. 打开 DB（version: 24）→ 触发 _onUpgrade(20→24) 增量迁移
4. _ensureAllTables() → 始终执行，确保 66 张表存在
5. _verifyAndRepairSeedData() → 检查 questions/graphs 是否低于阈值（<30/<5），若是则 SQL 级重导
```

**所有失败路径写文件日志**：`lib/core/init_logger.dart` → `<exe>/logs/mad_init.log`（写不进就退到 ApplicationSupport）。学生反馈"测验空白"时，让他把这文件发回来，立刻能看到具体异常。

**UI 兜底**：`DatabaseHelper.lastInitError` 非空时，QuizPage 不再只显示"暂无测验题目"，而是显示具体错误码 + 日志路径，引导找管理员。

**关键点**：
- 桌面端必须固化 `databasesPath`，不能依赖 `getDatabasesPath()` 默认（CWD 相对）
- 所有 catch 必须接 `InitLogger.error/log`，不能用 `debugPrint`（Release 不可见）
- `_importTableSafe()` 对比目标表列名，只迁移匹配的列
- 题库阈值 ≥30 / 图谱 ≥5 — 低于阈值即触发 SQL 级修复

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

### 编码补充规则

1. **禁止 `catch (_)`**：禁止使用 `catch (_) {}` 静默吞错。必须改写成 `catch (e, st) { swallowDebug(e, tag: 'TagName', stack: st); }`。唯一例外是确定不关心失败的 schema 探测（如 ALTER TABLE 试探列是否存在），用 `swallow(e, tag: '...')` 代替。
2. **pubspec.lock 不追踪**：`/pubspec.lock` 已加入 `.gitignore`。学生端/CI 不同 Flutter 版本会导致 lock 文件降级漂移。开发者 clone 后运行 `flutter pub get` 生成。

---

## 多智能体系统

### 架构

```
AgentRegistry (单例)
  ├── BaseAgent (抽象基类)
  │   ├── AgentConfig (persona/tools/cases/usageSteps)
  │   ├── AgentSession (多轮对话上下文)
  │   └── handleMessage() → AI 推理 + 工具调用
  └── 18 个专业 Agent
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

> 完整仓库与数据流设计（含架构图/时序图）见 **`docs/项目仓库设计.md`**。

### 同步机制（分组项目仓库模型）

学生数据**分散**存储在各自的分组项目仓库（命名空间 `chzuczldl`，**一组一仓库**，仓库名来自实验分组 Excel 的"仓库"列），教师端 App 按需拉取——不再集中到单一中心仓库（避免膨胀超配额）。

```
学生端 → 写 mad/{学号}.json + mad/files/{学号}/{实验|考核|作品}/ → 自己组仓库 chzuczldl/cg*-*
教师端 → 遍历去重组仓库读 mad/*.json                              → 合并到本地 DB
        uploadStudentData()                                       downloadAllStudentData()
```

通知广播 / 连接诊断走系统仓库 `chzcldl/mad-data`（`sync/notifications/`）。

### 同步关键文件

- `SyncService`：`sync_service.dart` — 组仓库解析(`_resolveRepoForUser`/`_allGroupRepos`/`_parseRepoSpec`) + 收集/写/拉取/导入
- `GiteeService`：`gitee_service.dart` — Gitee Contents API 读写文件 / 列目录
- 仓库映射来源：实验分组 Excel『仓库』列 → `users.repository_url`（`admin/data_import_page_native.dart` 导入）

### 同步注意事项

- **仓库解析**：`users.repository_url` 支持 完整 URL / `owner/repo` / 裸仓库名（裸名拼到命名空间 `chzuczldl` 下）
- **task_id 重映射**：每台设备 `lab_tasks` 自增 ID 不同，按 `title` 自然键匹配重映射
- **批改数据保护**：导入时已批改的 `lab_submissions`/`student_reports`/`student_works`（有 `score`）不被覆盖
- **SHA 去重**：`mad/{学号}.json` 内容无变化则跳过 commit
- **即时同步**：学生提交后立即触发 `unawaited(SyncService().uploadStudentData(userId))`，不等定时器
- 旧中心仓 `osgisOne/mad-fd:sync/students` 已**废弃**；旧同步数据已迁至 `chzcldl/mad-data` 的 `同步/sync`

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

### MaterialApp 本地化代理不可删除

`lib/main.dart` 的 `MaterialApp` 必须使用生成的 i18n 单一入口：

```dart
import 'l10n/gen/app_localizations.dart';

supportedLocales: AppL10n.supportedLocales,
localizationsDelegates: AppL10n.localizationsDelegates,
```

**禁止**改成 `localizationsDelegates: const []`，也不要手写一份不含 `AppL10n.delegate` 的代理列表。`AppL10n.localizationsDelegates` 内部已经包含 `GlobalMaterialLocalizations.delegate`、`GlobalCupertinoLocalizations.delegate`、`GlobalWidgetsLocalizations.delegate`。

历史事故（已多次出现）：

- 2026-06-02 的 `fix(critical): 恢复 i18n localizationsDelegates` 已经修过一次：第 13 轮自动改动把 `AppL10n.localizationsDelegates` 替换为空 `const []`。
- 2026-06-23 登录页再次异常：账号登录页不是样式丢失，而是 `TextField/TextFormField` 调用 `MaterialLocalizations.of(context)` 时拿到 `null`，运行期抛 `Null check operator used on a null value`，Flutter 用灰色错误占位撑满表单区域；扫码页因为几乎不渲染输入框，所以看起来正常。
- 容易误判为登录页 UI 被改坏，因为错误占位显示在登录卡片内部，同时全局悬浮帮助按钮叠在页面上，视觉上像“输入界面完全变了”。

反复发生原因：

1. 自动代理/批量重构把 `localizationsDelegates` 当作可清理的模板字段，未理解 Material 组件运行期依赖。
2. `flutter analyze` 不会发现 `localizationsDelegates: const []`，这是运行期错误，必须启动含 `TextField` 的页面才能暴露。
3. 项目有生成的 `AppL10n`，但如果不坚持单一入口，后续手写 locale/delegate 很容易漏掉 `GlobalMaterialLocalizations` 或 `AppL10n.delegate`。

排查登录页“灰色块/输入框消失/NavigationBar 崩溃”时，先看：

```bash
rg -n "localizationsDelegates|supportedLocales|AppL10n" lib/main.dart lib/l10n/gen/app_localizations.dart
Get-Content build/windows/x64/runner/Release/logs/mad_init.log -Tail 120
flutter analyze --no-pub lib/main.dart lib/presentation/pages/login
flutter test test/app_localization_contract_test.dart
```

只有确认 `MaterialLocalizations` 正常后，才继续改登录页布局。不要先重写登录页视觉。

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

### 双层命名体系

系统使用**双层命名**：窗体标题（简称 + 版本号）与窗体内标题（完整名称）。

| 位置 | 名称 | 格式 |
|------|------|------|
| **窗体标题**（窗口边框、浏览器标签、任务栏） | CKGDTv{版本号} | 简称 + v主.次.构建 |
| **窗体内标题**（登录页居中 Logo 下方） | 课程知识图谱与数字孪生平台 | 完整名称，不带版本号 |

### 版本号规则

**格式**：`主版本.次版本.构建`（如 `0.13.1`）

- **主版本**（major）：重大架构变更
- **次版本**（minor）：功能迭代
- **修订号**（patch）：bug 修复 / 文档 / 单一来源重构这类小迭代
- **构建号**（pubspec `+N`）：每次 `flutter build` 自动 +1；升 minor / major 时归零

### 单一来源（SSOT）— `lib/core/build_info.dart`

Dart 代码里**只能从** `BuildInfo` 读版本号 / 品牌名，**禁止任何硬编码字符串**：

```dart
import 'core/build_info.dart';

BuildInfo.appVersion           // '2.1.0'
BuildInfo.appBrand             // 'CKGDT'
BuildInfo.appBrandWithVersion  // 'CKGDTv2.1.0' (窗体标题 / MaterialApp.title)
BuildInfo.appVersionLine       // 'V2.1.0  ·  EDITION 2026' (登录页副标题)
BuildInfo.appFullName          // '课程知识图谱与数字孪生平台' (关于对话框 / 登录页全名)
```

**升版时改一处**（`BuildInfo.appVersion`）就同步影响 lib/ 内所有显示，包括 `MaterialApp.title`（dbLocked + 正常两条分支）、登录页副标题、设置页关于对话框。

历史教训：之前散落 3 个硬编码（`lib/main.dart` × 2、`login_page.dart`、`settings_page.dart`），每次升版都漏改，登录页停在 `V0.12.0`、关于停在 `0.11.0`。**现在 lib/ 里 grep `0\.\d+\.\d+` 应只出现在 `build_info.dart` 一个文件里**。

### 升版同步表（每次升 minor 或 patch 必逐项过一遍）

| 类别 | 文件 | 字段 |
|------|------|------|
| Dart 单一来源 | `lib/core/build_info.dart` | `appVersion` |
| pubspec | `pubspec.yaml` | `version: X.Y.Z+N`（N 归零） |
| Android | `android/app/src/main/res/values/strings.xml` | `app_name` |
| Windows | `windows/CMakeLists.txt` | `BINARY_OUTPUT_NAME` |
| Windows | `windows/runner/main.cpp` | `window.Create(L"…", ...)` |
| Windows | `windows/runner/Runner.rc` | 3 处：`FileDescription` / `OriginalFilename` / `ProductName`（`InternalName` 不带版本号） |
| Web | `web/index.html` | `<title>`、`apple-mobile-web-app-title`、`application-name` |
| Web | `web/manifest.json` | `"name"`（`short_name` 不带版本号） |
| HarmonyOS | `ohos/AppScope/app.json5` | `versionName` + `versionCode`（递增 +1） |
| i18n | `lib/l10n/app_zh.arb` | `appNameWithVersion.example`（占位符示例） |

**不要改**（Flutter 包标识符，必须保持英文 snake_case）：
- `pubspec.yaml` 顶部 `name: knowledge_graph_app`
- `windows/CMakeLists.txt` 第 3-7 行 `project(knowledge_graph_app)` / `BINARY_NAME`

### 升版后一致性 grep（推荐每次跑一遍）

```bash
grep -E "version:|app_name|BINARY_OUTPUT_NAME|window\.Create|FileDescription|InternalName|OriginalFilename|ProductName|<title>|apple-mobile-web-app-title|application-name|\"name\"|versionName|appVersion = " \
  pubspec.yaml \
  android/app/src/main/res/values/strings.xml \
  windows/CMakeLists.txt windows/runner/main.cpp windows/runner/Runner.rc \
  web/index.html web/manifest.json \
  ohos/AppScope/app.json5 \
  lib/core/build_info.dart
```

期望所有非空版本号字段都对齐到同一个 `X.Y.Z`，否则中止构建去补漏。

### 升版同步表中"必须改"的旧文件

历史上漏改过：
- 登录页 `lib/presentation/pages/login/login_page.dart` — 早期硬编码 `V0.12.0`
- 设置页 `lib/presentation/pages/home/settings_page.dart` — 关于对话框硬编码 `0.11.0`

这两处都已改为 `BuildInfo.appVersionLine` / `BuildInfo.appVersion`，**升版时不需要再单独改它们**。如果未来新增页面也要显示版本号，**必须**用 `BuildInfo`，禁止重复硬编码。

---

## 三端构建与发布流程

每次 `重新构建三端` 默认按以下规则执行，**不再每次问用户**：

### 三端命令（并行）

```bash
# Android — 注意 GRADLE_USER_HOME 环境变量已在 D:\development\cache\gradle 配置好缓存，
# 不需要 unset。如果 connection timeout，检查 D:/development/cache/gradle/wrapper/dists/
# 下是否有 gradle-8.12-all.zip.part 残留，删掉即可。
flutter build apk --release

# Windows — 包含 libmpv 视频解码（media_kit_libs_windows_video）
flutter build windows --release

# Web — 必须带 base href 适配 GitHub Pages 子路径，否则资源 404。
# bash 下需要 MSYS_NO_PATHCONV=1 防止路径转换。
MSYS_NO_PATHCONV=1 flutter build web --release --base-href "/ckgdt/"
# ⚠ 构建完成后必须改 renderer canvaskit → html（见"Web 空白"坑）
powershell -Command "(Get-Content build/web/flutter_bootstrap.js -Raw) -replace '\"renderer\":\"canvaskit\"', '\"renderer\":\"html\"' | Set-Content build/web/flutter_bootstrap.js"
```

### 产物路径

| 平台 | 路径 | 命名 |
|------|------|------|
| Android | `build/app/outputs/flutter-apk/app-release.apk` | 默认（不可改）|
| Windows | `build/windows/x64/runner/Release/CKGDTv{版本}.exe` | 由 `BINARY_OUTPUT_NAME` 控制 |
| Web | `build/web/`（base=`/ckgdt/`）| 静态站 |

### Web 公网部署（GitHub Pages）

仓库：`git@github.com:dll/ckgdt.git`，部署分支：`gh-pages`，访问地址：`https://dll.github.io/ckgdt/`

**每次 `flutter build web --base-href "/ckgdt/"` 完成后，按以下流程推送 gh-pages**（不动 master）：

```bash
# 1. 用独立目录组装（避免污染主仓库 .git）
mkdir -p build/_gh-pages-deploy
cp -r build/web/. build/_gh-pages-deploy/

# 2. 初始化 gh-pages 分支并启用 longpaths 处理 URL 编码超长文件名
git -C build/_gh-pages-deploy init -q -b gh-pages
git -C build/_gh-pages-deploy config core.longpaths true
git -C build/_gh-pages-deploy add -A
git -C build/_gh-pages-deploy -c user.email="ldl@github" -c user.name="ldl" \
    commit -q -m "deploy: web v{版本} base=/ckgdt/"

# 3. 推送（首次新分支用普通 push，后续覆盖用 --force）
git -C build/_gh-pages-deploy remote add origin git@github.com:dll/ckgdt.git
git -C build/_gh-pages-deploy push -u --force origin gh-pages

# 4. 清理（占用解除后）
rm -rf build/_gh-pages-deploy
```

> **注意**：base href = `/ckgdt/`（带斜杠尾），**不能写 `/ckgdt`**，否则资源加载 404。
> Gitee 仓库的 `gh-pages` 分支也保留着但 Gitee 个人版没 Pages 服务，不部署。

### 升版三件套（每次升 minor 或 major）

1. 按上面"升版时需同步修改的文件"表逐项替换版本号
2. 三端构建
3. Web push gh-pages

### 三端命名一致性检查

构建前可以一行命令审计：

```bash
grep -E "version:|app_name|BINARY_OUTPUT_NAME|window\.Create|FileDescription|InternalName|OriginalFilename|ProductName|<title>|apple-mobile-web-app-title|application-name|\"name\"|\"short_name\"|MaterialApp.*title:" \
  pubspec.yaml lib/main.dart \
  android/app/src/main/res/values/strings.xml \
  windows/CMakeLists.txt windows/runner/main.cpp windows/runner/Runner.rc \
  web/index.html web/manifest.json
```

---

## 部署产物打包规则（4 端齐发）

构建完 4 端后，把产物打成可分发 zip 放到 `dist/` 目录。**命名风格参考 DevEco Studio 官方包**（如 `devecostudio-windows-6.1.0.850.zip`）：

```
CKGDT+<端名小写>+v<版本号>.zip
```

例（v0.13.0）：
- `CKGDT+windows+v0.13.0.zip`
- `CKGDT+android+v0.13.0.zip`
- `CKGDT+web+v0.13.0.zip`
- `CKGDT+harmonyos+v0.13.0.zip`

### 各端打包内容

| 端 | 源路径 | 包内容 |
|----|--------|--------|
| Windows | `build/windows/x64/runner/Release/` 整个目录 | `*.exe` + 全部 dll + `data/`，**解压双击 EXE 直接运行** |
| Android | `build/app/outputs/flutter-apk/app-release.apk` | apk 文件 + `安装说明.txt`，包大小 ~76M |
| Web | `build/web/` 整个目录 | 静态资源 + `启动说明.txt`（教用户用 python http.server / serve 启动），包大小 ~39M |
| HarmonyOS | `ohos/entry/build/default/outputs/default/entry-default-signed.hap` | **已 OpenHarmony 调试签名** HAP（arm64-v8a 真机专用，模拟器不兼容）+ `安装说明.txt`，~39M |

> **⚠ 鸿蒙模拟器限制（重要）**：flutter_ohos 工具链目前**只产 arm64-v8a 引擎**（`flutter/bin/cache/artifacts/engine/` 仅有 ohos-arm64-release，无 x86 变体）。华为官方手机模拟器（Pura 90 等）使用 **x86_64 镜像**（`abi: x86`），装 HAP 报：
> ```
> code:9568347 install parse native so failed.
> the Abi type supported by the device does not match the Abi type configured in the C++ project
> ```
> **只能装到鸿蒙真机**（任何商用 NEXT 设备都是 arm64）。演示时必须用真机。

### 鸿蒙签名（已就位，无需重签）

凭证已存到 `ohos/signature/{debug.cer, debug.p7b, debug.p12, material/}`，
`ohos/build-profile.json5` 用相对路径 `./signature/*` 引用，team clone 后直接构建即可。
本套是 OpenHarmony 调试签名，仅可装开发者模式设备；商用发布需向华为申请正式证书替换 `ohos/signature/` 内文件。

### 命名规则要点

1. **端名小写**：`windows / android / web / harmonyos`（参考 DevEco 风格）
2. **版本号格式**：`v<主>.<次>.<构建>`（如 `v0.13.0`），与 `pubspec.yaml` 一致
3. **加号分隔**：中文产品名后用 `+` 连接端名，端名后用 `+` 连接版本号
4. **每端配 README**：txt 格式（`安装说明.txt` / `启动说明.txt`），中文，含默认账号

### 一键打包脚本

```bash
# 1. 先确认 4 端构建产物齐全
ls build/windows/x64/runner/Release/*.exe
ls build/app/outputs/flutter-apk/app-release.apk
ls build/web/index.html
ls ohos/entry/build/default/outputs/default/*.hap

# 2. 创建 dist 目录
mkdir -p dist

# 3. Windows（整个 Release 目录打包）
cd build/windows/x64/runner/Release && \
  powershell -NoProfile -Command "Compress-Archive -Path '*' -DestinationPath 'D:\FlutterProjects\knowledge_graph_app\dist\CKGDT+windows+vX.Y.Z.zip' -Force"
cd /d/FlutterProjects/knowledge_graph_app

# 4. Android / Web / HarmonyOS：mkdtemp + cp + 写 README + 打 zip
# （详见 dist/ 历史 zip 的内部结构）
```

### 何时打包

每次完成"升版三件套"+ 4 端构建 + gh-pages 部署后，最后一步打 4 个 zip 入 `dist/` 供分发。

> **注意**：`dist/` 目录已 gitignore（产物大不入库）；如需正式发版，把 zip 上传到 Gitee Release / GitHub Release。

---

## 双仓库发布流程（Gitee + GitHub）

代码主仓托管在 **Gitee**（`origin`），同时镜像到 **GitHub** 用于 GitHub Pages 部署 web 站。每次正式 release 都要：

1. 推 `master` + tag 到两个仓库
2. 在两个仓库各创建 Release + 上传 4 个 zip 资产

### 远程仓库配置

```bash
# Gitee 主仓（已配置为 origin）
git remote -v
# origin  https://...@gitee.com/chzcldl/mad-kgdt.git (push)

# 添加 GitHub 镜像（一次性，配完之后不动）
git remote add github git@github.com:dll/ckgdt.git
git remote -v
# origin  https://...@gitee.com/chzcldl/mad-kgdt.git (push)
# github  git@github.com:dll/ckgdt.git (push)
```

### 打 tag 与双推

```bash
# 1. 在 master 上打带消息的 annotated tag（不要 lightweight tag）
git tag -a v0.13.1 -m "release: v0.13.1 — 修测验空题 + 单一来源版本号"

# 2. 双仓库各推一遍（顺序无所谓）
git push origin master
git push origin v0.13.1
git push github master
git push github v0.13.1
```

> **注意**：`git push --tags` 会把所有本地 tag（含历史误打的）都推上去，**只推单个 tag** 用 `git push <remote> <tagname>`。

### 创建 Release + 上传资产

**GitHub**（用 `gh` CLI）：

```bash
gh release create v0.13.1 \
  --repo dll/ckgdt \
  --title "v0.13.1 — 修测验空题真凶 + 统一版本号" \
  --notes-file dist/RELEASE_NOTES_v0.13.1.md \
  dist/CKGDT+windows+v0.13.1.zip \
  dist/CKGDT+android+v0.13.1.zip \
  dist/CKGDT+web+v0.13.1.zip \
  dist/CKGDT+harmonyos+v0.13.1.zip \
  "dist/一键安装-Windows.bat" \
  dist/安装手册.pdf
```

**Gitee**（个人版没有 CLI，用 Web UI）：

1. 仓库主页 → 右侧 "Releases" → "创建发行版"
2. tag 选 `v0.13.1`，标题填同 GitHub
3. 拖拽 5 个 zip + bat + pdf 上传

或用 Gitee Open API（需个人令牌，参考 https://gitee.com/api/v5/swagger）。**禁止用 curl 上传含中文的 multipart 文件**——Windows curl 用 ANSI/GBK 编码 multipart 的 `filename=`，Gitee 存进去就乱码。**用 `scripts/gitee_upload_assets.py`**（Python `requests`，UTF-8 正确）：

```bash
export GITEE_TOKEN="<your_personal_token>"
python scripts/gitee_upload_assets.py
```

**两个 Gitee 编码坑**（已在脚本里规避，不要回退）：

1. **必须用 Python `requests`，不要 curl on Windows**：curl 把 `Content-Disposition: filename=` 用 ANSI/GBK 编码，Gitee 存的是 GBK 字节，Web UI 按 latin-1 显示 → 乱码。`requests` 始终发 UTF-8，存进去后 Web UI 显示正常。

2. **文件名里的 `+` 必须先转成 `%2B`**：Gitee 服务端会把 multipart filename 当 URL 解码，把 `+` 解成空格（`移动图谱+windows.zip` 会被存成 `移动图谱 windows.zip`）。脚本里的 `safe_name()` 把 `+` 替换成 `%2B`，Gitee 不再二次解码 `%XX`，存进去就是字面量 `+`。

如果手动 curl 测试，**至少**把 `+` 换成 `%2B`，但仍躲不过 ANSI/GBK 坑——直接用脚本。

### 发布前检查清单（每次都过一遍）

- [ ] `BuildInfo.appVersion` 已升 → 跑一遍上文"升版后一致性 grep"，全部对齐
- [ ] 4 端构建产物齐全（windows exe + android apk + web index.html + ohos hap）
- [ ] 4 个 zip 用 `scripts/pack_dist_zip.ps1` 打包（**不要用 PowerShell `Compress-Archive`**，它在 PS 5.1 用 GBK 编码 ZIP entry 名，中文文件名解压会乱码）
- [ ] Windows zip 同时生成 ASCII 别名（`MAD-windows-vX.Y.Z.zip`），避开 Windows 260 字符路径限制
- [ ] 当前 master 已 commit + push 到 origin
- [ ] tag 推到两个 remote（`origin` + `github`）
- [ ] 两个仓库都创建了 Release + 上传 7 个资产
- [ ] gh-pages 重新部署了新构建（`base-href "/ckgdt/"`）

> **历史教训**：`dist/` 不入库（gitignore 不动），release 资产走平台 Release API；这样仓库 master 历史不会因为二进制膨胀。

### ⚠ 环境变量（GH_TOKEN / GITEE_TOKEN）

**存储位置**：`GH_TOKEN` 和 `GITEE_TOKEN` 均在**系统级**（Machine）环境变量。

**关键陷阱**：bash/PowerShell tool 运行在新进程中，`$env:GH_TOKEN` **读不到** User 级变量。必须用：
```powershell
$token = [System.Environment]::GetEnvironmentVariable('GH_TOKEN','Machine')
$env:GH_TOKEN = $token   # 传到当前进程
```

**GitHub Release**：`gh release create` 需要 `GH_TOKEN`。先在当前进程设好 `$env:GH_TOKEN` 再调用 `gh`，或直接用 `Invoke-RestMethod` 调 GitHub REST API。

**Gitee Release**：用 `scripts/gitee_upload_assets.py` 上传资产。先在当前进程设好 `$env:GITEE_TOKEN` 再执行脚本：
```powershell
$env:GITEE_TOKEN = [System.Environment]::GetEnvironmentVariable('GITEE_TOKEN','Machine')
python scripts/gitee_upload_assets.py
```

**rebase 陷阱**：每次 `git push origin master` 可能被 bot 提交拦截（`fetch first`），先用 `git pull --rebase origin master` 解决。

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

## 已知问题与构建修补

### 1. sqlite3.dll Windows 发布版崩溃（0xC0000005）

**症状**：发布版 EXE 启动后立即崩溃 `0xC0000005`（null ptr at +0x8 in ntdll）。调试版正常。

**根因**：`sqlite3_flutter_libs v0.5.42` 预置的 `sqlite3.dll`（1,541,112 bytes）编译参数错误，首次调用 sqlite3 原生函数（`sqlite3_openInMemory`）时在 ntdll 堆管理器中触发访问违例。

**修复**：替换为 `sqflite_common_ffi` 包自带的 sqlite3.dll（3,231,232 bytes，含 FTS5 等扩展）：

```powershell
# 每次 flutter pub get 后执行（pub 会重新下载原包，覆盖修补）
Copy-Item "$env:PUB_CACHE\hosted\pub.flutter-io.cn\sqflite_common_ffi-2.3.7+1\lib\src\windows\sqlite3.dll" `
  "$env:PUB_CACHE\hosted\pub.flutter-io.cn\sqlite3_flutter_libs-0.5.42\windows\prebuilt_sqlite3\sqlite3.dll" -Force
```

或运行项目自带脚本：
```powershell
# 修补
.\scripts\patch_sqlite3.ps1
# 恢复原版
.\scripts\patch_sqlite3.ps1 -Restore
```

修补后需重新构建 Windows：
```powershell
flutter build windows --release
```

> **原理**：`sqflite_common_ffi` 的 sqlite3.dll 编译配置更完善，与当前 Windows 运行库兼容。两个 DLL 都是纯 sqlite3 二进制，API 兼容，直接替换不影响功能。

---

## Git 工作流

| 分支 | 用途 |
|------|------|
| `master` | 主分支（当前活跃） |
| `develop` | 开发集成分支 |
| `feature/xxx` | 功能开发 |

**提交消息格式**：`<类型>: <简短描述>`（类型：feat / fix / refactor / docs / style / test / chore）
