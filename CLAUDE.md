# CLAUDE.md — 知识图谱学习系统项目规则

## 项目概述

**知识图谱学习系统（mad-fd）** 是一套面向移动应用开发课程的 Flutter 学习平台，提供知识图谱浏览、章节测验、视频教程、课程资料、学习进度追踪和学习计划等功能。后台配套 Python 工具链，可自动生成教学视频、PPT 和字幕。

- **仓库地址**：https://gitee.com/osgisOne/mad-fd
- **Flutter SDK**：`>=3.0.0 <4.0.0`
- **应用版本**：`1.0.0+1`
- **主题色**：`#667eea`（紫蓝渐变）

---

## 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | Flutter 3 + Material Design 3 |
| 本地数据库 | sqflite 2.3 + 自定义 DAO |
| 图表 | fl_chart 0.66 |
| 持久化配置 | shared_preferences 2.2 |
| 文件路径 | path_provider 2.1 + path 1.9 |
| 静态分析 | flutter_lints 3.0 |
| 教学视频生成 | Python 3 + moviepy + edge-tts + Pillow |

---

## 目录结构

```
knowledge_graph_app/
├── lib/
│   ├── main.dart                        # 应用入口，初始化DB、主题、竖屏锁定
│   ├── app/                             # （预留）应用级路由/配置
│   ├── core/
│   │   └── constants/                   # （预留）全局常量
│   ├── data/
│   │   ├── models/                      # 纯数据类（无 Flutter 依赖）
│   │   │   ├── user_model.dart
│   │   │   ├── graph_model.dart
│   │   │   ├── node_model.dart
│   │   │   ├── edge_model.dart
│   │   │   ├── question_model.dart
│   │   │   └── quiz_result_model.dart
│   │   ├── local/                       # SQLite 访问层
│   │   │   ├── database_helper.dart     # 单例 DB，启动时从 assets 复制
│   │   │   ├── user_dao.dart
│   │   │   ├── graph_dao.dart
│   │   │   ├── quiz_dao.dart
│   │   │   ├── learning_record_dao.dart
│   │   │   ├── favorite_dao.dart
│   │   │   └── wrong_answer_dao.dart
│   │   └── repositories/                # （预留）Repository 抽象层
│   ├── services/
│   │   ├── auth_service.dart            # 登录/登出/角色判断
│   │   ├── data_service.dart            # JSON 导入导出、DB 备份
│   │   ├── data_loading_service.dart    # 资源加载辅助
│   │   ├── data_migration_service.dart  # DB 版本迁移
│   │   ├── settings_service.dart        # shared_preferences 封装
│   │   └── theme_manager.dart           # 亮/暗主题定义
│   └── presentation/
│       ├── widgets/                     # （预留）可复用 Widget
│       └── pages/
│           ├── login/login_page.dart
│           ├── home/
│           │   ├── home_page.dart       # 底部导航主框架 + 管理员面板
│           │   ├── search_page.dart
│           │   └── settings_page.dart
│           ├── graph/
│           │   ├── graph_list_page.dart
│           │   ├── graph_detail_page.dart
│           │   └── favorites_page.dart
│           ├── quiz/
│           │   ├── quiz_page.dart
│           │   └── wrong_answers_page.dart
│           ├── learning/
│           │   ├── video_page.dart
│           │   ├── document_page.dart
│           │   ├── progress_page.dart
│           │   └── learning_plan_page.dart
│           └── admin/
│               ├── student_manage_page.dart
│               └── data_import_page.dart
├── assets/
│   ├── learning_data.db                 # 预置 SQLite（图谱、题目等）
│   ├── students.json                    # 预置学生名单
│   └── images/
├── tools/                               # Python 视频生成工具链
│   ├── generate_graph_video_v6.py       # 当前主版本视频生成器
│   ├── video_common_v6.py               # 公共工具函数
│   ├── gen_document_v6.py
│   ├── gen_learning_path_v6.py
│   ├── gen_quiz_v6.py
│   └── gen_video_player_v6.py
├── docs/
│   ├── diagrams/                        # PlantUML 源文件 + 导出 PNG
│   │   └── v3/                          # 当前版本架构图
│   ├── testing/                         # 测试用例与报告
│   └── video/                           # 视频生成中间产物（已 gitignore）
├── video_output/                        # 最终视频/PPT 输出
└── test/                                # Flutter 单元/Widget 测试
```

---

## 数据库设计

数据库文件首次启动时从 `assets/learning_data.db` 复制到设备存储，通过 `DatabaseHelper`（单例）统一访问。

| 表名 | 说明 |
|------|------|
| `users` | 用户（student / teacher / admin），密码 = userId 后 6 位 |
| `current_session` | 当前登录会话（单行，id=1） |
| `graphs` | 知识图谱元数据 |
| `nodes` | 图谱节点（含坐标、颜色、层级、metadata_json） |
| `edges` | 图谱边（含样式、权重、可见性） |
| `questions` | 选择题（ABCD 四选一，answer_index 0-3） |
| `quiz_results` | 测验记录（分数、章节、时间） |
| `learning_records` | 节点学习记录 |
| `wrong_answers` | 错题本（含错误次数累计） |
| `favorites` | 收藏节点 |
| `resource_files` | 课程资料文件索引 |

**默认管理员**：`user_id = '419116'`，密码 = `'419116'`

---

## 用户角色

| 角色 | role 值 | 特权 |
|------|---------|------|
| 学生 | `student` | 基础学习功能 |
| 教师 | `teacher` | 同学生（预留扩展） |
| 管理员 | `admin` | 额外显示"管理"Tab，可管理学生、导入数据 |

`AuthService` 是全局无状态服务，在页面中直接 `final _authService = AuthService()` 实例化使用（非 Provider/Riverpod，保持简单）。

---

## 主题规范

- 主色调：`Color(0xFF667eea)`（紫蓝）
- 渐变：`[Color(0xFF667eea), Color(0xFF764ba2)]`
- 亮色背景：`Color(0xFFF5F7FA)`
- 暗色背景：`Color(0xFF121212)` / 卡片 `Color(0xFF1E1E1E)`
- 卡片圆角：`BorderRadius.circular(16)`
- Material 3：已启用（`useMaterial3: true`）
- 主题切换通过 `SettingsService.isDarkMode()` + `ThemeManager` 实现，在 `MyApp` 的 `State` 中管理

---

## 导航结构

`HomePage` 使用 `NavigationBar`（底部导航），Tab 索引如下：

| 索引 | 页面 | 仅管理员 |
|------|------|---------|
| 0 | 首页（功能菜单卡片网格） | — |
| 1 | 知识图谱列表 | — |
| 2 | 章节测验 | — |
| 3 | 视频教程 | — |
| 4 | 课程资料 | — |
| 5 | 学习进度 | — |
| 6 | 学习计划 | — |
| 7 | 设置 | — |
| 8 | 管理面板（学生管理 + 数据管理） | ✅ |

---

## 开发规范

### Dart / Flutter

1. **分层原则**：`models` 不依赖 Flutter，`dao` 只依赖 sqflite，`services` 组合 DAO，`pages` 只调用 services。
2. **DAO 模式**：每张业务表对应一个 DAO 类，直接操作 `DatabaseHelper.instance.database`，不使用 ORM。
3. **无状态管理框架**：当前不使用 Provider / Riverpod / Bloc，状态在 `StatefulWidget` 内管理。如需引入，优先考虑 Provider。
4. **命名规范**：
   - 文件：`snake_case.dart`
   - 类：`PascalCase`
   - 私有成员：`_camelCase`
   - 常量：`camelCase`（局部）或 `UPPER_SNAKE_CASE`（顶层）
5. **异步**：所有 DB 操作均 `async/await`，UI 层用 `try/catch` 捕获错误，失败时静默降级或显示 SnackBar。
6. **竖屏锁定**：`main()` 中已调用 `SystemChrome.setPreferredOrientations`，不要删除。
7. **导入去重**：`main.dart` 中存在重复 import，新建文件时注意不要引入重复导入。
8. **`withValues`**：使用 `color.withValues(alpha: 0.x)` 代替已废弃的 `withOpacity()`。

### 模型类约定

- 提供 `fromMap(Map<String, dynamic>)` 工厂构造
- 提供 `toMap()` 方法返回 `Map<String, dynamic>`
- 不依赖任何 Flutter/sqflite 包

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

## Python 工具链（视频生成）

### 环境依赖

```bash
pip install moviepy==1.0.3 edge-tts Pillow python-pptx pyttsx3
```

### 主要脚本

| 脚本 | 用途 |
|------|------|
| `tools/generate_graph_video_v6.py` | 当前主版本：生成知识图谱功能教学 MP4 + PPTX + SRT |
| `tools/gen_quiz_v6.py` | 测验模块教学视频 |
| `tools/gen_learning_path_v6.py` | 学习路径模块教学视频 |
| `tools/gen_document_v6.py` | 文档模块教学视频 |
| `tools/gen_video_player_v6.py` | 视频播放器模块教学视频 |
| `tools/video_common_v6.py` | 公共函数（字体、颜色、工具函数） |

### 视频生成流程（v6 机制）

1. 旁白按标点自动分句（或由 `voice_segments` 手动指定）
2. 每句用 `edge-tts`（`zh-CN-XiaoxiaoNeural`）生成独立 MP3，获取真实时长
3. 为每句渲染专属 PNG（底部字幕条文字不同）
4. `moviepy` 拼接 `ImageClip + AudioFileClip`，一次性编码消除 AAC 漂移
5. SRT 时间戳 = 各句 MP3 真实时长累加，与视频字幕 100% 对齐

### 输出路径

| 类型 | 路径 |
|------|------|
| 最终 MP4 / PPTX | `video_output/` |
| 字幕 SRT | `docs/video/v6/subtitles_v6.srt` |
| 脚本 Markdown | `docs/video/v6/script_v6.md` |
| 中间产物（slides/audio/crops） | `docs/video/v6/`（已 gitignore） |

### 视频参数

- 分辨率：`1920×1080`，FPS：`30`
- TTS 语音：`zh-CN-XiaoxiaoNeural`，语速：`-5%`
- 字幕栏高度：`115px`，标题栏高度：`84px`
- 中文字体：Windows 系统 `msyhbd.ttc`（微软雅黑粗体）/ `simhei.ttf`

---

## 架构图

架构图源文件（PlantUML）位于 `docs/diagrams/v3/`，包括：

| 文件 | 内容 |
|------|------|
| `flutter_dart_framework_architecture.puml` | Flutter/Dart 框架层次架构 |
| `flutter_dart_core_class_diagram.puml` | 核心类图 |
| `flutter_dart_core_class_ui_diagram.puml` | UI 核心类图 |
| `graph_feature_sequence_diagram.puml` | 图谱功能时序图 |
| `knowledge_graph_development_process.puml` | 开发流程图 |

编辑后使用 PlantUML 重新导出对应 PNG，替换 `docs/diagrams/v3/*.png`。

---

## Git 工作流

- 主分支：`master`
- 功能分支：`feature/xxx`
- 热修复：`hotfix/xxx`
- 发布：`release/xxx`
- 远程：`origin → https://gitee.com/osgisOne/mad-fd.git`

提交消息格式：

```
<类型>: <简短描述>

类型：feat | fix | refactor | docs | style | test | chore
```

---

## 注意事项

1. **不要提交中间产物**：`docs/video/**/audio/`、`slides/`、`temp/`、`crops/`、`assets/` 已在 `.gitignore` 中排除。
2. **数据库不要手动修改**：`assets/learning_data.db` 是预置数据，如需修改请通过管理员界面或专用迁移脚本。
3. **TLS 警告**：当前 Git 仓库存在 TLS 证书验证禁用警告，建议在安全网络环境下推送。
4. **密码规则**：用户密码固定为 `userId` 的后 6 位，不得更改此规则（已有学生数据依赖此逻辑）。
5. **`lib/app/` 和 `lib/core/constants/` 目前为空**：填充前请先讨论整体路由和常量策略，避免混乱。