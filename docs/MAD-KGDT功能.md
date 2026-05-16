# MAD-KGDT 移动图谱与数字孪生教学系统 — 功能点清单

> **项目名称**：MAD-KGDT（Mobile Application Development - Knowledge Graph & Digital Twin）
> **当前版本**：0.10.0+11
> **技术栈**：Flutter 3 + Material Design 3 + sqflite + 多智能体 + RAG
> **目标平台**：Android、Windows、Web、HarmonyOS（OHOS）、iOS、macOS、Linux

---

## 1. 启动模式与认证流程

### 1.1 平台适配与初始化
- 条件导入模式（`_native.dart` + `_stub.dart`）：文件系统、PlantUML、素材、幻灯片生成等服务按平台加载不同实现。
- `platform_init_native.dart`：原生平台初始化（数据库路径、文件目录）。
- `platform_init_web.dart`：Web 平台初始化（IndexedDB、HTTP 资源）。
- 三层数据库防御策略：种子 DB 复制 → 版本匹配跳过迁移 → 异常时自动修复空数据。

### 1.2 登录与账号管理（`login_page.dart` + `auth_service.dart` + `user_dao.dart`）
- Flutter Material 登录界面，支持账号密码输入与角色快捷登录。
- 角色区分：**学生**（默认）、**教师**、**管理员**（419116）；登录后主界面根据 `role` 动态构建不同导航栏。
- 身份验证：默认密码 = 账号后 6 位（管理员密码固定）。
- 当前登录会话持久化（`current_session` 表），为主界面各模块提供 `current_user` 上下文。
- 教师申请流程：学生可提交教师申请，管理员审核后升级角色（`teacher_application_dao.dart`）。

### 1.3 角色感知导航
- **教师/管理员**（9 个 Tab）：首页 | 图谱 | 教学 | 课堂 | 实验 | 考核 | 作品 | 达成 | 管理（仅管理员）
- **学生**（6 个 Tab）：首页 | 图谱 | 学习 | 实验 | 考核 | 作品
- 全局入口（AppBar + 悬浮按钮）：搜索、通知（带未读 Badge）、用户菜单。
- 悬浮按钮展开：帮助、反馈、三端互通、语音导航、多智能体助手、数字孪生。

---

## 2. 数据层与同步

### 2.1 数据源
- `learning_data.db`：主 SQLite 数据库，共 **59 张表**，种子数据版本 `user_version = 20`。
- `assets/graphs/`：6 大类 32 个知识图谱 Markdown 源文件。
- `assets/students.json`：学生名单种子数据。
- `data/course_config/`：课程配置（manifest、chapters、assessment、lab_tasks、report_templates、resource_index）。

### 2.2 数据管理
- `database_helper.dart`：数据库单例，管理 59 张表的创建、迁移与种子数据加载。
- **26 个 DAO**：覆盖用户、图谱、测验、学习、实验、作品、考核、成绩、课堂、协作、通知等全部业务。
- `data_loading_service.dart`：预设数据加载（图谱 Markdown → 数据库、题库初始化）。
- `data_migration_service.dart`：数据迁移与版本升级。
- `data_service.dart`：条件导入，按平台选择原生或桩实现。

### 2.3 数据同步
- **Gitee 双向同步**（`sync_service.dart` + `gitee_service.dart`）：
  - 学生数据通过 Gitee 仓库 JSON 文件实现师生同步，无需部署后端服务器。
  - `task_id` 重映射：跨设备 ID 不同，通过 `title` 自然键匹配。
  - 批改数据保护：已批改数据不被覆盖。
- **跨平台局域网同步**（`cross_platform/`）：
  - `sync_protocol.dart`：同步协议定义。
  - `sync_client.dart`：同步客户端。
  - `sync_server.dart`：同步服务器（条件导入，IO 实现 + 桩实现）。
  - `session_manager.dart`：会话管理。
  - QR 码扫码快速配对连接（`qr_scan_page.dart`）。

---

## 3. 主界面与通用组件

### 3.1 主页（`home_page.dart`）
- 登录后加载主页，根据用户角色动态构建导航 Tab。
- 首页展示角色差异化功能入口：学生 → 学习中心、测验、作品等；教师 → 教学中心、课堂、管理等。
- 全局搜索（`search_page.dart`）：跨模块内容检索。
- 系统设置（`settings_page.dart`）：主题切换、AI 配置、语音设置等。

### 3.2 可复用组件（`presentation/widgets/`）
- `agent_chat_overlay.dart`：智能体对话浮层，支持 **7 种导航动作**（跳转页面、打开资源、生成内容等）。
- `agent_entry_button.dart`：智能体入口按钮，全局悬浮触发。
- `voice_input_button.dart`：语音输入按钮，长按录音。
- `markdown_bubble.dart`：Markdown 气泡渲染，支持代码高亮、表格、链接。
- `mad_mascot_button.dart`：吉祥物悬浮按钮，快速打开 AI 助手。
- `course_generator_sheet.dart`：一键生课表单，BottomSheet 交互。

### 3.3 主题系统（`app_theme.dart` + `theme_manager.dart`）
- 紫蓝渐变主题色 `#667eea`，Material Design 3 风格。
- 支持亮色/暗色主题切换。
- 自定义技术栈 Logo 绘制器（`tech_logo_painter.dart`）。

---

## 4. 知识图谱模块

### 4.1 图谱数据模型（`data/models/`）
- `graph_model.dart`：图谱定义（ID、名称、描述、类型、布局、节点列表、边列表）。
- `node_model.dart`：节点（ID、标签、类型、位置、属性、分组）。
- `edge_model.dart`：边（ID、源节点、目标节点、关系类型、标签、权重）。

### 4.2 图谱浏览与交互（`presentation/pages/graph/`）
- `knowledge_graph_page.dart`：图谱主页，6 大类 32 个知识图谱分类展示。
- `graph_list_page.dart`：图谱列表，支持搜索与筛选。
- `graph_detail_page.dart`：图谱详情，CustomPainter + InteractiveViewer 实现节点拖拽、缩放、点击。
- `graph_properties_page.dart`：图谱属性查看与编辑。
- `favorites_page.dart`：节点级别收藏管理。

### 4.3 图谱布局算法（`graph_layout_service.dart`）
- 支持多种自动布局算法：力导向、层次、圆形、网格等。
- 布局参数可配置，布局结果持久化到图谱元数据。

### 4.4 图谱导入（`graph_import_service.dart`）
- 支持 Markdown 格式图谱导入，保留节点属性、关系与分组信息。
- 批量导入 `assets/graphs/` 目录下预置图谱。

### 4.5 知识抽取与种子（`knowledge_extract_service.dart` + `knowledge_seed_service.dart`）
- 从课程内容中自动抽取知识概念与关系。
- 知识种子服务：初始化核心知识体系。

### 4.6 节点成就（`node_achievement_service.dart`）
- 节点学习成就追踪，与学习行为联动。

---

## 5. 学习路径与推荐

### 5.1 学习路径模型（`learning_path_model.dart` + `learning_path_dao.dart`）
- 学习路径定义：路径节点序列、进度状态、完成标记。
- 路径节点关联知识图谱节点，支持路径与图谱双向联动。

### 5.2 学习中心（`presentation/pages/learning/`）
- `learning_hub_page.dart`：学习中心主页，视频、文档、PPT、PDF 多媒体资源入口。
- `learning_plan_page.dart`：学习计划，AI 生成个性化学习路径。
- `learning_chain_page.dart`：学习链，知识点之间的关联学习路径。
- `progress_page.dart`：学习进度，可视化学习进度追踪。
- `weakness_diagnosis_page.dart`：薄弱点诊断，AI 分析学习薄弱环节。

### 5.3 学习资源管理
- `video_page.dart` + `video_player_page.dart`：视频列表与播放（桌面端 MediaKit，移动端系统播放器）。
- `document_page.dart`：文档查看。
- `pdf_viewer_page.dart`：PDF 查看器。
- `ppt_viewer_page.dart`：PPT 查看器。
- `courseware_service.dart` + `courseware_download_service.dart`：课件管理与下载（本地优先 + 远程兜底）。
- `course_resource_service.dart`：课程资源服务。

### 5.4 学习记录与追踪（`learning_record_dao.dart`）
- 记录学习 Session / Action（节点访问、资源学习、测验提交）。
- 供统计、推荐与成就系统使用。

---

## 6. 学习行为与成就系统

### 6.1 学习行为追踪
- `learning_record_dao.dart`：记录学习行为（访问、学习、提交），供统计与推荐使用。
- `achievement_dao.dart`：成绩达成数据管理。

### 6.2 成绩达成模块（`presentation/pages/achievement/`）
- `achievement_page.dart`：成绩达成主页。
- **四个子标签页**：
  - `overview_tab.dart`：概览（三维成绩总览）。
  - `scores_tab.dart`：成绩（平时成绩、实验成绩、考试成绩）。
  - `analysis_tab.dart`：分析（课程目标达成度可视化：柱状图、雷达图）。
  - `report_tab.dart`：报告（自动生成课程达成度报告）。

### 6.3 成长曲线（`growth_curve_page.dart`）
- 学习成长轨迹可视化，展示知识掌握度变化趋势。

### 6.4 深度实践（`deep_practice_page.dart`）
- 针对薄弱知识点的深度练习推荐。

---

## 7. 测验系统

### 7.1 题库管理（`quiz_dao.dart` + `question_model.dart`）
- 52 道预置四选一题目，按章节分类。
- 题目模型：题干、选项、正确答案、章节、难度、知识点标签。
- 管理员题库管理（`question_manage_page.dart`）：题目增删改查。

### 7.2 测验交互（`presentation/pages/quiz/`）
- `quiz_page.dart`：章节练习、综合测试。
- `wrong_answers_page.dart`：错题本，自动记录错题，支持累加错误次数和最后错误时间。

### 7.3 测验结果（`quiz_result_model.dart` + `wrong_answer_dao.dart`）
- 记录每次测验成绩，支持历史回顾。
- 完成测验后更新徽章、章节按钮状态、成绩排行。

### 7.4 AI 生成题目
- `quiz_agent.dart`：根据知识点自动生成新题目。
- AI 技能页（`ai_skill_page.dart`）：测验生成技能入口。

---

## 8. 实验模块

### 8.1 实验任务管理（`lab_task_dao.dart`）
- 6 个实验：环境搭建、原生开发、跨平台、小程序、鸿蒙、综合实战。
- 实验配置来源：`data/course_config/lab_tasks.json`。
- 管理员实验管理（`lab_task_manage_page.dart`）。

### 8.2 实验交互（`presentation/pages/lab/`）
- `lab_tasks_page.dart`：实验任务列表与提交。
- `student_lab_page.dart`：学生实验页。
- `collaboration_page.dart`：小组协作实验。
- `lab_material_preview_page.dart`：实验材料预览。
- `productization_guide_page.dart`：实验成果产品化指导。

### 8.3 AI 批阅
- `lab_grading_agent.dart`：自动批阅实验报告。
- `ai_grading_tab.dart`：AI 批阅结果展示标签。

### 8.4 实验数据资源
- `data/实验/实验指导/`：实验指导书 + UML 图。
- `data/实验/实验教程/`：6 个实验教程。
- `data/实验/报告模板/`：6 个报告模板。
- `data/实验/移动技术栈/`：9 个技术栈手册。

---

## 9. 考核系统

### 9.1 考核模型（`assessment_dao.dart`）
- 小组、项目、贡献、答辩、成绩模型。
- 考核配置来源：`data/course_config/assessment.json`。

### 9.2 考核交互（`presentation/pages/assessment/`）
- `assessment_page.dart`：项目考核页，分组、项目、贡献、答辩、成绩子页。
- `ai_grading_tab.dart`：AI 批阅标签。

### 9.3 AI 批阅
- `assessment_grading_agent.dart`：自动评分与反馈。
- `assessment_agent.dart`：考核管理智能体。

### 9.4 考核数据资源
- `data/考核/`：考核方案与报告模板。

---

## 10. 作品管理

### 10.1 作品模型（`works_dao.dart`）
- 作品信息、上传记录、评分、评论、点赞、浏览量。
- 查重服务（`plagiarism_service.dart`）：作品查重。

### 10.2 作品交互（`presentation/pages/works/`）
- `works_page.dart`：作品展示页，搜索、筛选、详情、评分入口。
- `ai_grading_tab.dart`：AI 批阅标签。

### 10.3 AI 批阅
- `works_grading_agent.dart`：自动评分与反馈。
- `works_agent.dart`：作品展示指导智能体。

---

## 11. 课堂互动模块

### 11.1 课堂管理（`classroom_dao.dart`）
- 签到功能：课堂签到管理。
- 课堂消息：实时消息推送。
- 课堂提问：互动问答。

### 11.2 课堂交互（`presentation/pages/classroom/`）
- `classroom_page.dart`：课堂互动主页。
- `classroom_question_tab.dart`：课堂提问标签页。

---

## 12. 个人中心与问卷

### 12.1 个人中心（`presentation/pages/profile/`）
- `student_center_page.dart`：学生中心（学习统计、成长轨迹、个人设置）。
- `teacher_workspace_page.dart`：教师工作台（教学统计、班级管理、作品审核）。
- `virtual_twin_page.dart`：数字孪生页。
- `chat_history_page.dart`：聊天历史。

### 12.2 问卷系统（`survey_dao.dart` + `presentation/pages/survey/`）
- `survey_page.dart`：问卷调查答题。
- 管理员问卷管理（`survey_manage_page.dart`）：问卷创建与编辑。
- `survey_stats_page.dart`：问卷统计汇总。

---

## 13. AI 助手与多智能体系统

### 13.1 AI 服务基础（`ai_service.dart` + `rag_service.dart`）
- **多 Provider 支持**：DeepSeek / 智谱 GLM-4，API Key 存数据库（`ai_config_dao.dart`）。
- **RAG 检索增强**（`rag_service.dart`）：检索课程知识库增强对话质量。
- AI 配置管理（`ai_config_model.dart`）：Provider、Model、API Key 灵活配置。

### 13.2 多智能体框架（`services/agent/`）
- **Director 编排模式**：`agent_registry.dart` 根据消息自动选择最佳智能体（关键词匹配 + AI 意图识别）。
- **24 个专业智能体**：

| 智能体 | 文件 | 功能 |
|--------|------|------|
| 语音导航 | `voice_agent.dart` | AI 意图识别，4 层路由（快速路径 → Tab 映射 → 子页面匹配 → AI 兜底） |
| 图谱专家 | `graph_agent.dart` | 图谱查询与分析，支持数据库工具调用 |
| 智能辅导 | `tutor_agent.dart` | 个性化学习辅导 |
| 测验生成 | `quiz_agent.dart` | 根据知识点自动生成题目 |
| 实验指导 | `lab_agent.dart` | 实验步骤与技巧指导 |
| 实验批阅 | `lab_grading_agent.dart` | 自动批阅实验报告 |
| 考核管理 | `assessment_agent.dart` | 考核流程管理 |
| 考核批阅 | `assessment_grading_agent.dart` | 自动评分与反馈 |
| 作品指导 | `works_agent.dart` | 作品展示与优化建议 |
| 作品批阅 | `works_grading_agent.dart` | 自动评分与反馈 |
| 安全审查 | `safety_agent.dart` | 内容安全审查 |
| 课件生成 | `courseware_agent.dart` | AI 生成课件内容 |
| 一键生课 | `course_gen_agent.dart` | 自动生成完整课程内容 |
| 通用助手 | `assistant_agent.dart` | 通用问答与辅助 |
| 学习推荐 | `learning_agent.dart` | 个性化学习路径推荐 |
| 学习计划 | `path_agent.dart` | 学习计划制定 |
| 移动开发专家 | `mobile_expert_agent.dart` | 移动开发技术问答 |
| 学术伦理 | `ethics_agent.dart` | 学术伦理指导 |
| 成绩分析 | `achievement_agent.dart` | 成绩数据分析 |
| 文档转换 | `doc_converter_agent.dart` | 文档格式转换 |
| 仓库分析 | `repo_agent.dart` | Git 仓库分析 |
| 系统指南 | `madkg_agent.dart` | 系统使用指南 |
| 虚拟学生 | `virtual_student_agent.dart` | 数字孪生 — 学生人格模拟 |
| 虚拟教师 | `virtual_teacher_agent.dart` | 数字孪生 — 教师督导辅助 |

### 13.3 对话交互
- `agent_chat_overlay.dart`：全局智能体对话浮层，支持 **7 种导航动作**（跳转页面、打开资源、生成内容、调用工具等）。
- `ai_history_dao.dart`：对话历史持久化。
- `chat_history_page.dart`：历史对话查看与管理。

### 13.4 AI 技能模块（`presentation/pages/skill/`）
- `ai_skill_page.dart`：**9 个 AI 技能**入口（辅导、测验、课件、图谱、脚本、PPT、UML、报告、代码）。

---

## 14. 语音交互模块

### 14.1 语音识别（`voice_service.dart`）
- 讯飞 WebSocket STT 实时语音转文字。
- 长按录音交互（`voice_input_button.dart`）。

### 14.2 语音合成（`tts_service.dart` + `tts_flutter_service.dart`）
- 双引擎 TTS：讯飞在线合成 + Flutter 本地合成。
- 语音设置（`voice_settings_page.dart`）：引擎选择、语速、音量调节。

### 14.3 语音导航（`voice_agent.dart`）
- 自然语言控制页面跳转。
- **4 层路由**：快速路径 → Tab 映射 → 子页面匹配 → AI 兜底。
- 支持语音指令如"打开图谱"、"开始测验"、"查看成绩"等。

---

## 15. 数字孪生模块

### 15.1 孪生档案（`twin_profile_model.dart` + `twin_service.dart`）
- 数字孪生配置管理：学习风格、知识水平、行为模式。
- 孪生档案持久化与更新。

### 15.2 虚拟学生（`virtual_student_agent.dart`）
- 模拟学生学习行为，生成个性化学习建议。
- 基于真实学习数据构建学生画像。

### 15.3 虚拟教师（`virtual_teacher_agent.dart`）
- 辅助教师决策，提供教学建议。
- 基于班级数据生成教学策略。

### 15.4 孪生交互（`virtual_twin_page.dart`）
- 数字孪生可视化展示与交互。

---

## 16. 素材与课件模块

### 16.1 素材管理（`material_dao.dart` + `material_service.dart`）
- 素材信息管理（`material_model.dart`）：生成素材、模板、分类。
- 条件导入：原生平台支持文件系统操作，Web 平台桩实现。

### 16.2 课件工坊（`presentation/pages/materials/`）
- `materials_hub_page.dart`：素材中心主页。
- `courseware_workshop_page.dart`：课件工坊，AI 辅助课件制作。
- `ai_assist_page.dart`：AI 辅助页面。
- `ai_settings_page.dart`：AI 设置页面。
- `resource_viewer_page.dart`：资源查看器。
- `slide_generator_page.dart`：幻灯片生成页面。

### 16.3 课件服务
- `courseware_service.dart`：课件管理。
- `courseware_download_service.dart`：课件下载（本地优先 + 远程兜底）。
- `ppt_export_service.dart`：PPT 导出。
- `slide_generator_service.dart`：幻灯片生成（条件导入）。

### 16.4 PlantUML（`puml_dao.dart` + `plantuml_service.dart`）
- `puml_manager_page.dart`：PlantUML 文件管理。
- UML 图生成与管理（条件导入）。

---

## 17. 管理员面板

### 17.1 用户管理（`presentation/pages/admin/`）
- `student_manage_page.dart`：学生信息管理。
- `student_detail_page.dart`：学生详情查看。
- `teacher_manage_page.dart`：教师信息管理。
- `teacher_application_manage_page.dart`：教师申请审核。
- `teacher_application_page.dart`：教师申请提交。

### 17.2 教学管理
- `class_manage_page.dart`：班级创建与成员管理。
- `teaching_manage_page.dart`：大纲、教案、进度管理。
- `question_manage_page.dart`：题库增删改查。
- `lab_task_manage_page.dart`：实验任务配置。
- `survey_manage_page.dart` + `survey_stats_page.dart`：问卷管理与统计。

### 17.3 数据管理
- `data_import_page.dart`：Excel 批量数据导入。
- `data_export_page.dart`：数据导出。
- `repo_analytics_page.dart`：仓库分析统计。
- `repo_detail_page.dart`：仓库详情查看。

### 17.4 教学中心与评价中心
- `teaching_hub_page.dart`：教学中心（教师专用功能入口）。
- `evaluation_hub_page.dart`：评价中心（成绩、达成度、分析入口）。

---

## 18. 通知与反馈模块

### 18.1 通知系统（`notification_dao.dart` + `notification_service.dart`）
- `notification_list_page.dart`：通知列表（带未读 Badge）。
- `compose_notification_page.dart`：发送通知（教师/管理员）。
- 通知触发与分发机制。

### 18.2 反馈系统（`feedback_dao.dart`）
- `feedback_dialog.dart`：用户反馈对话框。
- `ai_help_dialog.dart`：AI 帮助对话框。
- `feedback_manage_page.dart`：反馈管理（教师/管理员）。

---

## 19. 仓库与代码模块

### 19.1 Git 仓库管理（`repo_agent.dart`）
- `git_repo_page.dart`：Git 仓库管理（教师/管理员），查看学生代码仓库。
- `student_repo_page.dart`：学生仓库视图。
- `student_repo_map.json`：学生仓库映射配置。

### 19.2 仓库分析
- `repo_analytics_page.dart`：仓库提交统计、代码量分析。
- `repo_detail_page.dart`：仓库详情（提交历史、文件结构）。

---

## 20. 跨平台互通模块

### 20.1 跨平台中心（`presentation/pages/cross_platform/`）
- `cross_platform_hub_page.dart`：跨平台同步中心。
- `qr_scan_page.dart`：扫码连接页面。
- `data_sync_page.dart`：数据同步管理。

### 20.2 同步协议
- WebSocket 局域网实时同步。
- QR 码快速配对。
- 会话管理（`session_manager.dart`）。

---

## 21. 帮助与设置模块

### 21.1 帮助系统
- `handbook_page.dart`：使用手册。
- 悬浮按钮快速入口。

### 21.2 设置模块（`presentation/pages/settings/`）
- `settings_page.dart`：系统设置主页。
- `ai_data_page.dart`：AI 数据管理。
- `course_manage_page.dart`：课程管理。
- `voice_settings_page.dart`：语音设置。

---

## 22. 数据库设计概要

数据库由 `database_helper.dart` 单例管理，共 **59 张表**，核心表分类如下：

| 分类 | 表数量 | 关键表 |
|------|--------|--------|
| 用户与会话 | 2 | users, current_session |
| 知识图谱 | 3 | graphs, nodes, edges |
| 测验 | 3 | questions, quiz_results, wrong_answers |
| 学习 | 4 | learning_records, favorites, learning_paths, path_nodes |
| 实验与作品 | 7 | lab_tasks, lab_submissions, student_works, work_scores 等 |
| 考核与成绩 | 8 | assessment_groups, achievement_scores 等 |
| 教学管理 | 10 | courses, classes, syllabus_items, surveys 等 |
| AI 与协作 | 10 | ai_configs, ai_chat_history, notifications 等 |
| 其他 | 12 | knowledge_concepts, generated_materials, puml_files 等 |

---

## 23. 技术栈总览

| 层级 | 技术 | 说明 |
|------|------|------|
| **UI 框架** | Flutter 3 + Material Design 3 | 全平台统一 UI |
| **本地数据库** | sqflite + 自定义 DAO | 59 张表，种子数据预置 |
| **AI 服务** | DeepSeek / 智谱 GLM-4 | 多 Provider 切换，API Key 存 DB |
| **多智能体** | 24 个 Agent + Director 编排 | 关键词匹配 + AI 意图识别 |
| **RAG 检索** | RagService | 课程内容知识库增强 |
| **语音交互** | 讯飞 WebSocket STT + TTS | 实时语音识别与合成 |
| **数据同步** | Gitee 仓库 JSON 双向同步 | 无服务器架构 |
| **跨平台同步** | WebSocket + QR 扫码 | 局域网实时同步 |
| **图谱绘制** | CustomPainter + InteractiveViewer | 自定义绘制 + 手势交互 |
| **图表** | fl_chart | 折线图 / 雷达图 / 柱状图 |
| **视频播放** | MediaKit（桌面）/ 系统播放器（移动） | 条件导入 |
| **PDF/PPT** | pdf + printing 包 | 文档查看与导出 |
| **文件操作** | file_picker + open_filex | 文件选择与打开 |
| **Excel** | excel 包 | 批量数据导入导出 |
| **Markdown** | flutter_markdown | Markdown 内容渲染 |
| **PlantUML** | 自定义服务 | UML 图生成与管理 |
| **PPT 生成** | slide_generator_service | AI 生成幻灯片 |
| **查重** | plagiarism_service | 作品查重 |
| **加密** | crypto 包 | 数据哈希 |
| **二维码** | qr_flutter + mobile_scanner | 二维码生成与扫描 |
| **网络** | http + web_socket_channel | HTTP 请求与 WebSocket |
| **录音** | record 包 | 语音录制 |
| **条件导入** | `_native.dart` + `_stub.dart` 模式 | 跨平台兼容 |

---

## 24. 架构分层

```
┌─────────────────────────────────────────┐
│  presentation/pages (88+ 页面)          │  ← 只调用 services/dao
│  presentation/widgets (6 个组件)        │
├─────────────────────────────────────────┤
│  services (40+ 服务)                    │  ← 组合 DAO，处理业务逻辑
│  services/agent (24 个智能体)           │
├─────────────────────────────────────────┤
│  data/local/dao (26 个 DAO)             │  ← 只依赖 sqflite + DatabaseHelper
│  data/models (12 个模型)                │  ← 纯数据类，无 Flutter 依赖
├─────────────────────────────────────────┤
│  core/constants (6 个工具类)            │  ← 主题、角色守卫、章节辅助
│  platform (3 个条件导入)                │  ← 平台差异初始化
└─────────────────────────────────────────┘
```

---

## 25. 关键设计特点

1. **无服务器架构**：通过 Gitee 仓库 JSON 文件实现师生数据双向同步，无需部署后端服务器。
2. **多智能体 Director 模式**：24 个专业 Agent + Director 编排，关键词匹配 + AI 意图识别自动路由。
3. **角色感知导航**：同一应用根据用户角色（学生/教师/管理员）动态构建不同的导航栏。
4. **条件导入跨平台**：涉及文件系统的服务统一使用 `_native.dart` + `_stub.dart` 条件导入模式。
5. **三层数据库防御**：种子 DB 复制 → 版本匹配跳过迁移 → 异常时自动修复空数据。
6. **4 层语音路由**：快速路径 → Tab 映射 → 子页面匹配 → AI 兜底。
7. **批改数据保护**：同步时已批改数据不被覆盖，task_id 通过 title 自然键重映射。
8. **RAG 检索增强**：课程知识库增强 AI 对话质量，减少幻觉。
9. **数字孪生双角色**：虚拟学生 + 虚拟教师，分别模拟学习行为和教学决策。

---

## 数据流概览

1. 启动 → 平台初始化（条件导入）→ 数据库初始化（三层防御）→ 登录（角色区分）→ 进入主页。
2. 主页根据角色构建导航 Tab，各模块调用对应 Service/DAO，操作 `learning_data.db`。
3. 客户端模式通过 Gitee 仓库 JSON 实现师生数据双向同步，或通过 WebSocket 局域网实时同步。
4. 业务数据（项目、作品、学习记录、测验成绩、问卷等）持久化在 SQLite，配合 Excel 模板导入导出。
5. AI 智能体通过 Director 编排自动路由，RAG 检索增强对话质量，工具调用扩展能力边界。
6. 语音交互通过 4 层路由实现自然语言导航，支持页面跳转、资源打开、内容生成等操作。
