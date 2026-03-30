# CLAUDE.md — 《移动应用开发》课程的知识图谱教学系统

## 项目概述

**知识图谱教学系统（mad-fd）** 是一套面向《移动应用开发》课程的 Flutter 教学平台，涵盖知识图谱浏览、章节测验、视频教程、课程资料、学习进度追踪和学习计划等功能，体现"教"（资源组织、图谱结构）与"学"（交互浏览、测验反馈、进度统计）的完整闭环。后台配套 Python 工具链，可自动生成教学视频、PPT 和字幕。

- **仓库地址**：https://gitee.com/osgisOne/mad-fd
- **Flutter SDK**：`>=3.0.0 <4.0.0`
- **应用版本**：`1.0.0+1`
- **主题色**：`#667eea`（紫蓝渐变）
- **用户角色**：学生 / 教师 / 管理员

---

## 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | Flutter 3 + Material Design 3 |
| 本地数据库 | sqflite 2.3 + 自定义 DAO |
| 图谱绘制 | CustomPainter + InteractiveViewer |
| 图表 | fl_chart 0.66（折线图） |
| 持久化配置 | shared_preferences 2.2 |
| 文件路径 | path_provider 2.1 + path 1.9 |
| 静态分析 | flutter_lints 3.0 |
| 教学视频生成 | Python 3 + moviepy 1.0.3 + edge-tts + Pillow + python-pptx |

---

## 课程内容结构（6 章）

| 章节 | 主题 |
|------|------|
| 第 1 章 | 移动应用开发技术体系全景 |
| 第 2 章 | Android 与 iOS 原生开发基础 |
| 第 3 章 | Flutter、React Native 等混合开发技术 |
| 第 4 章 | 微信小程序开发流程 |
| 第 5 章 | 华为 HarmonyOS 多端应用开发 |
| 第 6 章 | 综合开发实践 |

课程资料（PDF / PPT）和视频各约 15 条，均按此 6 章组织，存入 `resource_files` 表，`chapter` 字段与 `learning_records` 共用章节标识，支持进度联动。

---

## 目录结构

```
knowledge_graph_app/
├── lib/
│   ├── main.dart                          # 应用入口：初始化 DB、主题、竖屏锁定
│   ├── app/                               # （预留）应用级路由/配置
│   ├── core/
│   │   └── constants/                     # （预留）全局常量
│   ├── data/
│   │   ├── models/                        # 纯数据类（无 Flutter 依赖）
│   │   │   ├── user_model.dart
│   │   │   ├── graph_model.dart
│   │   │   ├── node_model.dart
│   │   │   ├── edge_model.dart
│   │   │   ├── question_model.dart
│   │   │   └── quiz_result_model.dart
│   │   ├── local/                         # SQLite 访问层（DAO）
│   │   │   ├── database_helper.dart       # 单例 DB，启动时从 assets 复制
│   │   │   ├── user_dao.dart
│   │   │   ├── graph_dao.dart
│   │   │   ├── quiz_dao.dart
│   │   │   ├── learning_record_dao.dart
│   │   │   ├── favorite_dao.dart
│   │   │   └── wrong_answer_dao.dart
│   │   └── repositories/                  # （预留）Repository 抽象层
│   ├── services/
│   │   ├── auth_service.dart              # 登录/登出/角色判断
│   │   ├── data_service.dart              # JSON 导入导出、DB 备份
│   │   ├── data_loading_service.dart      # 资源加载辅助
│   │   ├── data_migration_service.dart    # DB 版本迁移
│   │   ├── settings_service.dart          # shared_preferences 封装
│   │   └── theme_manager.dart             # 亮/暗主题定义
│   └── presentation/
│       ├── widgets/                       # （预留）可复用 Widget
│       └── pages/
│           ├── login/login_page.dart
│           ├── home/
│           │   ├── home_page.dart         # 底部导航主框架 + 管理员面板
│           │   ├── search_page.dart       # 搜索页（Navigator.push，非 Tab）
│           │   └── settings_page.dart
│           ├── graph/
│           │   ├── graph_list_page.dart
│           │   ├── graph_detail_page.dart # CustomPainter + InteractiveViewer
│           │   └── favorites_page.dart
│           ├── quiz/
│           │   ├── quiz_page.dart
│           │   └── wrong_answers_page.dart
│           ├── learning/
│           │   ├── video_page.dart        # VideoListPage + _initVideoData()
│           │   ├── document_page.dart     # DocumentListPage + TabBar
│           │   ├── progress_page.dart     # TabController + fl_chart
│           │   └── learning_plan_page.dart
│           └── admin/
│               ├── student_manage_page.dart
│               └── data_import_page.dart
├── assets/
│   ├── learning_data.db                   # 预置 SQLite（图谱、题目等）
│   ├── students.json                      # 预置学生名单
│   └── images/
├── tools/                                 # Python 视频生成工具链（v6 为当前版本）
│   ├── generate_graph_video_v6.py         # 知识图谱核心功能教学视频（主版本）
│   ├── gen_quiz_v6.py                     # 测验功能视频
│   ├── gen_learning_path_v6.py            # 学习路径功能视频
│   ├── gen_document_v6.py                 # 课程资料功能视频
│   ├── gen_video_player_v6.py             # 视频播放功能视频
│   ├── video_common_v6.py                 # 公共工具函数（字体、颜色等）
│   └── generate_graph_video_assets.py     # 资产生成辅助脚本
├── docs/
│   ├── diagrams/                          # 功能级架构图（PlantUML + PNG）
│   │   ├── knowledge_graph_feature_architecture.puml/.png
│   │   ├── knowledge_graph_feature_flow.puml/.png
│   │   ├── knowledge_graph_feature_data_model.png
│   │   └── v3/                            # 系统级架构图（当前版本）
│   │       ├── flutter_dart_framework_architecture.puml/.png
│   │       ├── flutter_dart_core_class_diagram.puml/.png
│   │       ├── flutter_dart_core_class_ui_diagram.puml
│   │       ├── graph_feature_sequence_diagram.puml/.png
│   │       └── knowledge_graph_development_process.puml/.png
│   ├── testing/
│   │   ├── test_cases.md                  # 系统化测试用例（TC-LOGIN / TC-GRAPH 等）
│   │   └── test_report.md                 # 测试报告（23 项已通过）
│   └── video/                             # 视频脚本、字幕及中间产物
│       ├── video_script.md / video_script_v2.md   # 早期脚本
│       ├── v3/ ~ v6/                      # 迭代版本脚本与字幕
│       ├── feat_document/                 # 课程资料功能视频
│       │   ├── script.md / subtitles.srt
│       │   └── audio/ crops/ sent/ slides/ temp/
│       ├── feat_learning_path/            # 学习路径功能视频
│       ├── feat_quiz/                     # 测验功能视频
│       ├── feat_video_player/             # 视频播放功能视频
│       ├── slides_v2/                     # 预生成幻灯片 PNG（12 张）
│       └── generated/                     # 早期生成产物
├── video_output/                          # 最终 MP4 / PPTX 输出
└── test/
    ├── widget_test.dart                   # 登录页 UI 测试
    ├── models/model_test.dart             # 6 个数据模型测试
    └── widgets/home_page_widget_test.dart # 首页导航组件测试
```

---

## 数据库设计

数据库首次启动从 `assets/learning_data.db` 复制，由 `DatabaseHelper`（单例）统一管理。

| 表名 | 说明 | 关键字段 |
|------|------|---------|
| `users` | 用户（student/teacher/admin） | `user_id`, `role`, `is_active` |
| `current_session` | 当前登录会话（单行 id=1） | `user_id`, `machine_code`, `login_time` |
| `graphs` | 知识图谱元数据 | `id`, `title`, `graph_type`, `layout` |
| `nodes` | 图谱节点 | `id`, `graph_id`, `title`, `content`, `node_type`, `level`, `x`, `y`, `color`, `parent_id`, `visible`, `metadata_json` |
| `edges` | 图谱边 | `id`, `graph_id`, `source_id`, `target_id`, `edge_type`, `label`, `weight`, `color`, `width`, `style`, `visible` |
| `questions` | 选择题（四选一） | `source`（章节）, `question`, `option_a~d`, `answer_index`（0-3） |
| `quiz_results` | 测验成绩 | `user_id`, `score`, `num_correct`, `num_total`, `chapter`, `completed_at` |
| `learning_records` | 节点学习记录 | `user_id`, `node_id`, `node_title`, `study_time`, `completed_at` |
| `wrong_answers` | 错题本 | `user_id`, `question_id`, `times`（错误次数累加）, `last_wrong_time` |
| `favorites` | 收藏节点 | `user_id`, `node_id`, `node_title`, `favorite_time` |
| `resource_files` | 课程资料与视频 | `file_name`, `file_path`, `file_type`（pdf/ppt/video）, `chapter`, `description` |

### resource_files 数据规模

| file_type | 数量 | 来源 | 存储路径前缀 |
|-----------|------|------|-------------|
| `pdf` | ~15 条 | 清言智谱 AI 生成 | `assets/清言智谱/` |
| `ppt` | ~15 条 | 秒出 PPT 生成 | `assets/秒出PPT/` |
| `video` | 15 条 | 课程录制 | `assets/` |

> **视频初始化**：`VideoListPage` 首次加载时检查 `resource_files` 中 `file_type='video'` 的数量，为 0 则调用 `_initVideoData()` 批量插入 15 条记录，用户无感知。

### 默认管理员账号

- `user_id = '419116'`，密码 = userId 后 6 位 = `'419116'`
- 所有用户的密码规则：`userId.substring(userId.length - 6)`

---

## 用户角色

| 角色 | role 值 | 特权 |
|------|---------|------|
| 学生 | `student` | 基础学习功能 |
| 教师 | `teacher` | 同学生（预留扩展） |
| 管理员 | `admin` | 额外显示第 9 个 Tab（学生管理 + 数据管理） |

`AuthService` 是无状态服务，页面中直接 `final _authService = AuthService()` 实例化使用，**不使用** Provider/Riverpod（当前架构）。

---

## 导航结构

`HomePage` 使用 `NavigationBar`（Material 3 底部导航），Tab 索引：

| 索引 | 页面 | Widget | 仅管理员 |
|------|------|--------|---------|
| 0 | 首页（功能菜单卡片网格） | `_buildHome()` | — |
| 1 | 知识图谱列表 | `GraphListPage` | — |
| 2 | 章节测验 | `QuizPage` | — |
| 3 | 视频教程 | `VideoListPage` | — |
| 4 | 课程资料 | `DocumentListPage` | — |
| 5 | 学习进度 | `ProgressPage` | — |
| 6 | 学习计划 | `LearningPlanPage` | — |
| 7 | 设置 | `SettingsPage` | — |
| 8 | 管理面板 | `_AdminToolsPage` | ✅ |

**二级页面**（通过 `Navigator.push`，非 Tab）：`SearchPage`、`WrongAnswersPage`、`FavoritesPage`、`GraphDetailPage`

---

## 核心页面实现要点

### GraphDetailPage（图谱详情）

- `CustomPainter`（`GraphPainter`）绘制节点与边，`InteractiveViewer` 支持缩放/拖拽
- `_calculateNodePositions()` 自动布局节点坐标
- `_handleTap(position)` 命中检测，点击节点弹出详情卡片
- 节点详情卡片提供"**开始学习**"（→ `LearningRecordDao.addRecord()`）和"**收藏**"（→ `FavoriteDao.addFavorite()`）两个动作
- `GraphPainter` 接收 `nodes`、`edges`、`selectedNode`，实现 `paint()` 和 `shouldRepaint()`

### QuizPage（测验）

- `_quizStarted` 状态变量控制视图切换（章节选择 ↔ 答题）
- 选项颜色三状态机：`isSelected` / `isCorrect` / `_answered`（提交前蓝紫高亮，提交后绿色正确/红色错误）
- `_submitAnswer()` → 判题 → 调用 `_recordWrongAnswer()` 异步写错题（try-catch 静默失败）
- `WrongAnswerDao.addWrongAnswer()`：先查重，已存在则 UPDATE `times+1`，否则 INSERT

### DocumentListPage（课程资料）

- `DefaultTabController` 双 Tab：**PDF 文档** / **PPT 课件**
- 页面初始化同时加载 `_pdfList` 和 `_pptList`，切换 Tab 无需再次查库
- `_openDocument()` 当前以 `SnackBar` 展示 `file_path`，后续可替换 `open_file` 插件

### VideoListPage（视频播放）

- 首次启动自动调用 `_initVideoData()` 写入 15 条视频记录
- `_playVideo(filePath)` 当前以 `SnackBar` 展示路径，后续可替换 `video_player` 插件
- `chapter` 字段与 `learning_records` 表共用，播放行为可同步写入学习记录推动进度

### ProgressPage（学习进度）

- `TabController` 两个 Tab：**测验成绩** / **学习记录**
- 测验成绩 Tab：三统计卡片（次数/平均分/正确率）+ `fl_chart LineChart` 成绩趋势 + 最近 10 条历史
- `fl_chart` 关键参数：`isCurved=true`、`barWidth`、`belowBarData`（alpha=0.1 半透明填充）
- 学习记录 Tab：`LearningRecordDao.getStatistics()` 返回总记录数、独立节点数（COUNT DISTINCT）、本周学习数

### LearningPlanPage（学习计划）

- 数据模型：`List<Map<String, dynamic>> _plans`，硬编码在 State，**无持久化**（原型版本）
- 三示例计划：Flutter 入门（60%）/ Android 进阶（30%）/ 跨平台实战（10%）
- 章节详情：`showModalBottomSheet` + `DraggableScrollableSheet`（初始 60%，最小 40%，最大 90%）
- 章节完成判断：`isCompleted = index < completedDays`（双态 UI：绿色对勾 vs 灰色序号）
- 删除计划：`PopupMenuButton` → `_plans.remove(map对象)` → `setState`

### WrongAnswersPage（错题本）

- `ExpansionTile` 可折叠，折叠显示题目摘要和 `times` 错误次数（红色 CircleAvatar）
- 展开显示完整题目、用户答案（红色）vs 正确答案（绿色）对比
- AppBar 清空按钮：确认对话框 → `WrongAnswerDao.clearAll(userId)`

---

## 数据模型约定

所有模型类均：
- 提供 `factory fromMap(Map<String, dynamic> map)` 工厂构造
- 提供 `Map<String, dynamic> toMap()` 方法
- **不依赖** 任何 Flutter/sqflite 包

### 关键派生属性

| 模型 | 派生属性 | 说明 |
|------|---------|------|
| `UserModel` | `password` | `userId.substring(userId.length - 6)` |
| `UserModel` | `isAdmin / isTeacher / isStudent` | role 字符串比较 |
| `QuestionModel` | `options` | `[optionA, optionB, optionC, optionD]` |
| `QuestionModel` | `correctAnswer` | `options[answerIndex]` |
| `QuizResultModel` | `accuracy` | `numCorrect / numTotal * 100`（防除零） |

---

## DAO 方法速查

### GraphDao
| 方法 | 说明 |
|------|------|
| `getAllGraphs()` | 查询所有图谱 |
| `getGraph(graphId)` | 单个图谱 |
| `getNodes(graphId)` | 图谱节点列表 |
| `getEdges(graphId)` | 图谱边列表 |
| `getNode(nodeId)` | 单个节点 |

### QuizDao
| 方法 | 说明 |
|------|------|
| `getChapters()` | `SELECT DISTINCT source … ORDER BY source`（去重排序） |
| `getQuestionsByChapter(chapter)` | 按 `source` 字段过滤题目 |
| `saveQuizResult(result)` | 写入成绩 |
| `getQuizResults(userId)` | 按时间倒序返回历史成绩 |
| `getQuizSummary(userId)` | 一次查询返回：次数/总答对/总题数/平均分 |

### LearningRecordDao
| 方法 | 说明 |
|------|------|
| `addRecord(userId, nodeId, nodeTitle, studyTime)` | 写入学习记录 |
| `getStatistics(userId)` | 返回：总记录数 / `COUNT DISTINCT` 节点数 / 本周学习数 |
| `hasLearned(userId, nodeId)` | 判断是否已学习 |

### WrongAnswerDao
| 方法 | 说明 |
|------|------|
| `addWrongAnswer(...)` | 已存在 → UPDATE `times+1`；不存在 → INSERT |
| `getWrongAnswers(userId)` | 获取错题列表 |
| `removeWrongAnswer(userId, questionId)` | 移除单条 |
| `clearAll(userId)` | 清空全部错题 |

### FavoriteDao
| 方法 | 说明 |
|------|------|
| `addFavorite(userId, nodeId, nodeTitle)` | 先查重再插入 |
| `getFavorites(userId)` | 获取收藏列表 |
| `isFavorite(userId, nodeId)` | 是否已收藏 |
| `removeFavorite(userId, nodeId)` | 取消收藏 |

---

## 主题规范

| 项目 | 值 |
|------|-----|
| 主色 | `Color(0xFF667eea)` |
| 渐变 | `[Color(0xFF667eea), Color(0xFF764ba2)]` |
| 亮色背景 | `Color(0xFFF5F7FA)` |
| 暗色背景 | `Color(0xFF121212)`，卡片 `Color(0xFF1E1E1E)` |
| 卡片圆角 | `BorderRadius.circular(16)` |
| Material 版本 | Material 3（`useMaterial3: true`） |
| 主题切换 | `SettingsService.isDarkMode()` + `ThemeManager` → `MyApp` State |

---

## 开发规范

### 分层原则

```
models  →  不依赖任何 Flutter/sqflite 包
dao     →  只依赖 sqflite + DatabaseHelper
services → 组合 DAO，处理业务逻辑
pages   →  只调用 services / dao，不直接操作 DB
```

### Dart / Flutter

1. **DAO 模式**：每张业务表对应一个 DAO 类，直接操作 `DatabaseHelper.instance.database`。
2. **无状态管理框架**：当前不使用 Provider/Riverpod/Bloc，状态在 `StatefulWidget` 内管理；如需引入，优先考虑 Provider。
3. **命名规范**：
   - 文件：`snake_case.dart`
   - 类：`PascalCase`
   - 私有成员：`_camelCase`
   - 顶层常量：`UPPER_SNAKE_CASE`
4. **异步**：所有 DB 操作均 `async/await`；UI 层用 `try/catch` 捕获，失败时静默降级或 `SnackBar` 提示。
5. **竖屏锁定**：`main()` 中已调用 `SystemChrome.setPreferredOrientations`，不要删除。
6. **透明度**：使用 `color.withValues(alpha: 0.x)` 代替已废弃的 `withOpacity()`。
7. **导入去重**：`main.dart` 中存在重复 import，新建文件时注意不要引入重复导入。

### 新增页面

1. 在 `lib/presentation/pages/<模块>/` 下创建文件
2. 如需新 Tab，在 `home_page.dart` 的 `NavigationBar` destinations 和 `_buildBody()` 中同步添加
3. 页面内通过 `Navigator.push` 进行二级跳转，不使用命名路由

---

## 常用开发命令

```bash
# 获取依赖
flutter pub get

# 运行应用（连接设备/模拟器）
flutter run

# 静态分析
flutter analyze

# 运行测试
flutter test

# 构建 Android APK（release）
flutter build apk --release

# 构建 Windows 桌面
flutter build windows --release

# 清理构建缓存
flutter clean
```

---

## 测试现状

| 测试文件 | 测试内容 | 状态 |
|---------|---------|------|
| `test/widget_test.dart` | 登录页基础 UI（标题、输入框、按钮、快捷登录） | ✅ 通过 |
| `test/models/model_test.dart` | 6 个数据模型的 `fromMap/toMap`、派生属性、角色判断 | ✅ 通过 |
| `test/widgets/home_page_widget_test.dart` | 首页底部导航显示、功能卡片、切换图谱页 | ✅ 通过 |

- **合计**：23 项测试全部通过
- **Android APK**：Debug + Release 均已成功构建
- **待补充**：`GraphListPage`、`GraphDetailPage` 组件测试；收藏与学习记录联动测试

### 测试文档（`docs/testing/`）

| 文件 | 内容 |
|------|------|
| `test_cases.md` | 系统化测试用例（TC-LOGIN / TC-HOME / TC-GRAPH / TC-FAV / TC-QUIZ / TC-PROGRESS / TC-DOC / TC-VIDEO / TC-MODEL / TC-BUILD） |
| `test_report.md` | 测试报告（已通过 14 项、待补充 6 项、缺陷记录 5 条） |

---

## Python 视频生成工具链

### 环境依赖

```bash
pip install moviepy==1.0.3 edge-tts Pillow python-pptx pyttsx3
```

### 视频脚本体系（`docs/video/`）

| 路径 | 内容 |
|------|------|
| `video_script.md` / `video_script_v2.md` | 早期脚本（已归档） |
| `v3/` ~ `v6/` | 知识图谱核心功能教学视频迭代版本 |
| `feat_document/` | 课程资料功能教学视频（script.md + subtitles.srt） |
| `feat_learning_path/` | 学习路径功能教学视频 |
| `feat_quiz/` | 测验功能教学视频（18 幻灯片，含测验全流程） |
| `feat_video_player/` | 视频播放功能教学视频（15 幻灯片） |
| `slides_v2/` | 预生成幻灯片 PNG（01_项目概述 ~ 12_结束语，共 12 张） |

每个 `feat_*/` 目录结构：

```
feat_xxx/
├── script.md          # 视频讲解脚本（成片结构 + 旁白）
├── subtitles.srt      # 字幕文件
├── audio/             # 每句 MP3（gitignore）
├── crops/             # UML 裁剪图（gitignore）
├── sent/              # 带字幕帧 PNG（gitignore）
├── slides/            # 基础幻灯片 PNG（gitignore）
└── temp/              # 临时文件（gitignore）
```

### v6 视频生成机制

1. 旁白按标点自动分句（或 `voice_segments` 手动指定）
2. 每句用 `edge-tts`（`zh-CN-XiaoxiaoNeural`，语速 `-5%`）生成独立 MP3，获取真实时长
3. 为每句渲染专属 PNG（底部字幕条文字不同）
4. `moviepy` 拼接 `ImageClip + AudioFileClip`，一次性编码消除 AAC 漂移
5. SRT 时间戳 = 各句 MP3 真实时长累加，与视频字幕 100% 对齐

### 视频参数

| 参数 | 值 |
|------|-----|
| 分辨率 | 1920 × 1080，FPS 30 |
| TTS 语音 | `zh-CN-XiaoxiaoNeural` |
| 语速 | `-5%` |
| 中文字体 | `C:\Windows\Fonts\msyhbd.ttc`（微软雅黑粗体）/ fallback `simhei.ttf` |
| 字幕栏高度 | 115 px |
| 标题栏高度 | 84 px |
| 句尾停顿 | `CLIP_TAIL = 0.45 s`，段尾 `SLIDE_TAIL = 1.2 s` |

### 输出路径

| 类型 | 路径 |
|------|------|
| 最终 MP4 / PPTX | `video_output/` |
| v6 字幕 | `docs/video/v6/subtitles_v6.srt` |
| v6 脚本 | `docs/video/v6/script_v6.md` |
| feat_* 字幕 | `docs/video/feat_xxx/subtitles.srt` |
| 中间产物 | `docs/video/**/audio/`、`slides/`、`sent/`、`crops/`、`temp/`（已 gitignore） |

---

## 架构图文件（`docs/diagrams/`）

### 功能级图（`docs/diagrams/`）

| 文件 | 内容 |
|------|------|
| `knowledge_graph_feature_architecture.puml` | 三角色（学生/教师/管理员）→ Flutter UI → Service/DAO → SQLite |
| `knowledge_graph_feature_flow.puml` | 图谱功能演示流程（活动图） |
| `knowledge_graph_feature_data_model.png` | 数据模型关系图 |

### 系统级图（`docs/diagrams/v3/`，当前版本）

| 文件 | 内容 |
|------|------|
| `flutter_dart_framework_architecture.puml` | 完整系统架构（UI/Service/DAO/Model/DB 五层） |
| `flutter_dart_core_class_diagram.puml` | 核心类图（含所有类、方法、关系） |
| `flutter_dart_core_class_ui_diagram.puml` | UI 核心类图 |
| `graph_feature_sequence_diagram.puml` | 图谱功能交互顺序图（含收藏/学习记录写入） |
| `knowledge_graph_development_process.puml` | 开发过程活动图（需求 → 建模 → 实现 → 测试） |

> 编辑 `.puml` 后使用 PlantUML 重新导出对应 `.png`，替换 `docs/diagrams/v3/*.png`。

---

## Git 工作流

| 分支 | 用途 |
|------|------|
| `master` | 主分支（当前活跃） |
| `develop` | 开发集成分支 |
| `feature/xxx` | 功能开发 |
| `release/xxx` | 发布准备 |
| `hotfix/xxx` | 紧急修复 |

**提交消息格式**：

```
<类型>: <简短描述>

类型：feat | fix | refactor | docs | style | test | chore
```

---

## 注意事项

1. **不要提交中间产物**：`docs/video/**/audio/`、`slides/`、`sent/`、`temp/`、`crops/` 已在 `.gitignore` 中排除。
2. **不要手动修改预置数据库**：`assets/learning_data.db` 是预置数据源，如需修改请通过管理员界面或专用迁移脚本（`data_migration_service.dart`）操作。
3. **密码规则不可更改**：用户密码固定为 `userId` 的后 6 位，已有学生数据依赖此逻辑。
4. **学习计划无持久化**：`LearningPlanPage` 的 `_plans` 仅存内存，页面销毁后丢失，后续需接入 SQLite 或 SharedPreferences。
5. **`lib/app/` 和 `lib/core/constants/` 目前为空**：填充前请先确定整体路由和常量策略。
6. **`lib/data/repositories/` 目前为空**：当前 DAO 直接被 Service/Page 调用，引入 Repository 层前无需修改现有代码。
7. **TLS 警告**：当前 Git 配置存在 TLS 证书验证禁用警告，建议在安全网络环境下推送。
8. **`main.dart` 重复 import**：文件中存在重复的 `theme_manager.dart` 和 `settings_service.dart` import，后续清理时注意不要引入新的重复。