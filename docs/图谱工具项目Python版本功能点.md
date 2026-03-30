# 图谱工具项目 Python 版功能点梳理

## 1. 启动模式与认证流程

### 1.1 模式管理（`main.py` + `server/` + `storage/`）
- 单机模式：本地 SQLite，离线完整功能。
- 服务器模式：内置 Flask REST API（`/api/ping`、`/api/sync/*`、`/api/data/*`），用于教师机/局域网主机。
- 客户端模式：HTTP 连接教师机，支持离线缓存与自动同步（`network_client.py` + `offline_sync.py`）。

### 1.2 设备适配
- PyInstaller 打包/源码运行路径修正。

### 1.3 登录与账号管理（`auth/login_window.py` + `storage/user_store.py`）
- Tk 登录界面、占位提示、快速登录按钮（学生/教师/管理员各一键账号）。
- 角色区分：学生（默认）、教师、管理员（419116）；登录后主界面会根据 `role` 启用不同菜单与权限。
- 身份验证：默认密码 = 账号后 6 位（管理员密码固定）；首次导入时即与 Excel 数据保持一致。
- 设备绑定：读取本机机器码，支持首次绑定、解绑检测，保证课堂场景下账号安全（开发模式可跳过）。
- Excel 导入真实账号（教师 + 计科22选49学生），支持增量导入与重复检测。
- 当前登录会话 `current_session` 持久化，为主界面 Tab（作品、考核等）提供 `current_user` 上下文。

## 2. 数据层与同步

### 2.1 数据源
- `learning_data.db`：主 SQLite，包含用户、图谱、学习、测验、考核、作品等表。
- `data/` 目录：图谱 Markdown、题库、视频、课件、项目 Excel 等。

### 2.2 数据管理
- `sqlite_store.py`：导入 Markdown/Excel 创建图谱、题库、资源；导出备份。
- `db_migration.py`：初始化/迁移数据库结构。
- `user_store.py`：账号增删、Excel 导入、机器码更新、当前会话。
- `offline_sync.py`：客户端离线队列、冲突处理；`network_client.py` 提供 HTTP 请求封装。

## 3. 主界面与通用组件

### 3.1 GraphEditorApp（`gui/main_window.py`）
- 登录后加载主窗口（GraphEditorApp）。
- 包含工具栏、状态栏、属性面板、图谱画布。
- 根据用户角色切换菜单与功能。
- 各业务功能以 Tab 形式组织，共享上下文 (`current_user`、`db_path`)。

### 3.2 UI 组件
- `graph_canvas.py` + `visualization/graph_2d.py`、`graph_3d.py`：图谱渲染、缩放、选中、属性查看。
- `property_panel.py`、`table_editor.py`、`toolbar.py`：属性编辑、表格操作组件。
- `components/builtin_players.py`、`qt_video_player.py`：视频/PPT 播放组件。

## 4. 知识图谱模块

### 4.1 图谱数据模型（`core/`）
- `KnowledgeGraph`、`GraphNode`、`GraphEdge`、`GraphType`、`GraphLayout` 数据结构。

### 4.2 图谱分析（`data_processing/graph_analyzer.py`）
- 连通性、中心度、类型分布、孤立节点分析，生成 Markdown 报告。

### 4.3 图谱可视化（`gui/tabs/graph_tab.py`）
- 画布展示、缩放适配、居中、选中节点；支持 2D/3D（`visualization/graph_2d.py` / `graph_3d.py`）切换。
- Toolbar 提供 **11 种布局**（弹簧/圆形/层次/壳层/随机/网格/力导向/树形/星形/Kamada-Kawai/同心圆），可即时切换并保存到图谱元数据。
- 节点形状与边样式可配置（核心枚举定义），适合区分课程类型或先修关系。
- 节点右键菜单支持“生成学习路径”、“加入测验”等操作，与路径/测验模块打通。
- 支持 Markdown 图谱导入/导出，保留节点属性、关系与分组信息。
- （MAUI 可扩展）Python 版暂未提供的功能：如图谱搜索高亮、节点筛选、批量样式编辑、布局动画，可在 MAUI 版考虑增强。

## 5. 学习路径与推荐

### 5.1 学习路径服务（`services/learning_path_service.py`）
- 学习路径定义、进度跟踪、统计信息。

### 5.2 学习推荐引擎（`learning/learning_recommender.py`）
- 构建知识节点图与路径矩阵。
- 根据 `learning_tracker` 数据生成个性化推荐。

### 5.3 学习资源管理（`gui/tabs/learning_tab.py`）
- 视频、课件、PDF 资源列表，资源数据来自 `data/视频/*.mp4`、`data/课件/*.pptx` 等多套教学材料。
- 内嵌播放器（Tk/Qt 混合控件）或外部打开，调用 `learning_tracker` 记录学习行为、完成时长。
- 章节列表与学习路径联动，可一键跳转到对应资源。

## 6. 学习行为与成就系统

- `learning/learning_tracker.py`：记录 Session / Action（节点访问、资源学习、测验提交），供统计与推荐使用。
- `education/achievement_reporter.py`：生成学习成就、里程碑。
- `education/badge_manager.py`：章节测验成绩自动授予 **5 个徽章等级**（初学者→专家级），并提供进度提示、下一等级目标。
- `education/study_planner.py`：依据学习记录生成计划、提醒。

## 7. 测验系统

- `education/quiz_engine.py`：题库加载、出题、评分、错题本。
- `gui/tabs/quiz_tab.py`：章节练习、综合测试、错题复习。
- `quiz_results` 表与 `user_store` 关联；完成测验后更新徽章、章节按钮状态、成绩排行，并在管理员界面展示统计图。

## 8. 考核系统

- `models/assessment.py`：小组、项目、贡献、答辩、成绩模型。
- `services/assessment_service.py`：小组管理、项目立项、贡献评分、答辩安排、成绩统计，支持 Excel 导入导出。
- `gui/tabs/assessment_tab.py`：分组、项目、贡献、答辩、成绩五大子页，提供表格展示与批量操作。

## 9. 作品管理

- `models/works.py` + `services/works_service.py`：作品信息、上传记录、评分、排行榜。
- `gui/tabs/works_tab.py`：作品列表、搜索、筛选、详情、评分入口。

## 10. 个人中心与问卷

- `services/profile_service.py` + `gui/tabs/profile_tab*.py`：学习统计、成长轨迹、个人设置（学生/教师视角）。
- `services/survey_service.py` + `gui/tabs/survey_dialog.py`：问卷设计、答题记录、汇总统计。

## 11. AI 助手（可选）

- `ai_assistant/services/ai_service.py`：DeepSeek / 智谱模型调用，`config_service` 管理 API Key。
- `history_service.py`、`knowledge_graph_service.py`：对话历史、知识点检索。
- `gui/assistant_window.py`：聊天界面，支持历史记录、知识图谱联动、语音。

## 12. 管理员面板与文档

- `gui/tabs/admin_tab.py`：系统总览、用户管理、数据导出、服务器控制。
- `docs/`：部署指南、模式说明、管理员操作等文档。
- `tests/test_三子系统.py`：自动化回归三大系统。

## 13. 学习路径交互体验

- `gui/tabs/learning_path_tab.py`：路径树 + 画布双视图，支持 **双向互动**：
  - 点击列表节点 → 画布节点闪烁高亮；
  - 单击画布节点 → 自动选中列表行并滚动到可见。
- 可从图谱节点生成路径（GraphEditorApp 的“生成学习路径”命令），再进行导出（图片/Markdown）或开始学习。
- 提供预置教学路径、难度图例、路径资源跳转按钮（开始学习）。

## 14. 资源与数据组织

- `data/课件/`：多套 PPT 课件（含 AI 生成版本）。
- `data/视频/`：MP4 视频资源，按章节命名；学习 Tab 可直接播放。
- `data/项目/`、`data/用户/`、`data/图谱/` 等 Excel/Markdown 作为真实业务数据源，初始化时批量导入。

## 数据流概览
1. 启动 → 模式选择/服务器连接 → 登录（Excel 真实账号 + 机器码） → 进入主界面。
2. 图谱/路径/学习/测验/考核/作品/个人中心 Tab 调用对应服务，操作 `learning_data.db`。
3. 客户端模式通过 `network_client` 调用 Flask 服务，同步离线数据。
4. 业务数据（项目、作品、学习记录、测验成绩、问卷等）持久化在 SQLite，配合 Excel 模板导入导出。
