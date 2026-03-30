# Flutter 知识图谱教学系统开发计划

> 本文档基于以下参考资料整合制定：
> - Python 图谱工具项目功能点梳理
> - MADQA 移动应用开发问答系统开发计划（MAUI/C# 版）
> - Android AI 问答系统实现经验（讯飞/智谱/DeepSeek）

---

## 一、项目定位

**《移动应用开发》课程的知识图谱教学系统**（mad-fd）是一套面向课程教与学的完整 Flutter 平台，涵盖：

| 维度 | 内容 |
|------|------|
| 教师端 | 课件生成、视频脚本生成、UML图谱管理、AI辅助备课 |
| 学生端 | 知识图谱浏览、章节测验、学习进度、视频/资料查阅 |
| 管理端 | 学生管理、数据导入导出、系统统计 |

---

## 二、与 Python 版功能对照

### Python 工具链 → Dart 服务层对照

| Python 脚本 | Dart 实现 | 方式 |
|-------------|-----------|------|
| `generate_graph_video_v6.py` | `SlideGeneratorService` + `AiService.generateScript()` | PDF 课件 + TTS 脚本 |
| `gen_quiz_v6.py` | `AiService.generateQuestions()` + 导入 SQLite | HTTP API |
| `gen_document_v6.py` | `SlideGeneratorService.generateFromAI()` | pdf package |
| `gen_learning_path_v6.py` | `AiService.generateLearningPath()` | HTTP API |
| `gen_video_player_v6.py` | `VideoListPage`（已有）+ AI 脚本导出 | 已实现 |
| `video_common_v6.py` | `AppColors` + `ThemeManager` | 已实现 |
| UML 渲染（PlantUML/Kroki）| `PlantUmlService` | Kroki.io POST |

### Python 业务功能 → Flutter 对照

| Python 模块 | Flutter 现状 | 优先级 |
|-------------|-------------|--------|
| 图谱分析（连通性/中心度）| 部分（GraphDetailPage）| P1 |
| 11种图谱布局 | 自动布局（基础）| P2 |
| 学习推荐引擎 | LearningPlanPage（静态）| P1 |
| 徽章成就系统 | 未实现 | P1 |
| 考核系统（小组/项目）| 未实现 | P2 |
| 作品管理 | 未实现 | P3 |
| 个人中心 | ProgressPage（基础）| P1 |
| AI 助手 | AiAssistPage（新增）| P0 |
| 问卷系统 | 未实现 | P3 |
| 网络同步模式 | 未实现 | P2 |

---

## 三、分阶段开发计划（对齐 MADQA 15周计划）

### 阶段 0：基础完善【已完成】
- [x] Flutter 项目初始化 + 分层架构
- [x] 用户角色系统（学生/教师/管理员）
- [x] 知识图谱浏览（GraphListPage + GraphDetailPage）
- [x] 章节测验（QuizPage + WrongAnswersPage）
- [x] 学习进度（ProgressPage + fl_chart）
- [x] 视频/资料列表（VideoListPage + DocumentListPage）
- [x] 主题色体系（3组预设 + 跟随系统）

### 阶段 1：AI 能力接入【当前阶段】
- [x] AI 服务层（AiService：DeepSeek / 智谱 GLM）
- [x] PlantUML 渲染服务（PlantUmlService：Kroki.io）
- [x] 课件生成（SlideGeneratorService → PDF 输出）
- [x] 素材管理（MaterialDao + MaterialService）
- [x] 素材中心（MaterialsHubPage：4 Tab）
- [x] AI 助手页面（AiAssistPage：chat/script/uml）
- [x] UML 管理（PumlManagerPage：编辑+渲染+保存）
- [x] AI 配置（AiSettingsPage：API Key 管理）
- [ ] AI 生成题目并导入题库（QuizImportFromAi）
- [ ] 视频脚本 TTS 朗读（flutter_tts 集成）

### 阶段 2：学习激励系统【P1】
- [ ] 徽章系统（5级：初学者→专家）
  - 初学者：完成第一张图谱
  - 进阶者：完成3章测验
  - 实践者：学习记录 ≥ 20 节点
  - 精英者：测验平均分 ≥ 80
  - 专家级：完成全部6章
- [ ] 积分系统（学习+1分/节点，测验满分+10分）
- [ ] 排行榜（管理员查看，按积分排序）
- [ ] 学习热图（ProgressPage 新增日历视图）

### 阶段 3：图谱增强【P1】
- [ ] 图谱搜索高亮（SearchPage 联动 GraphDetailPage）
- [ ] 节点筛选（按类型/章节/完成状态）
- [ ] 多布局支持（层次/圆形/树形，基于 CustomPainter）
- [ ] 图谱分析报告（连通性、中心度、孤立节点）

### 阶段 4：考核与评价系统【P2】
- [ ] 小组管理（GroupModel + GroupDao）
- [ ] 项目立项（ProjectModel）
- [ ] 贡献评分（ContributionModel）
- [ ] 成绩统计（AssessmentPage）

### 阶段 5：网络协同【P2】
- [ ] 教师机 REST API（server mode，与 Python Flask 版对齐）
- [ ] 客户端同步（离线队列 + 冲突处理）
- [ ] WiFi 自动发现（与 MADQA 计划一致）

### 阶段 6：个人中心增强【P1】
- [ ] 完整学习轨迹（时间线视图）
- [ ] 学习统计大盘（图表：每日/每周/章节分布）
- [ ] 自定义学习目标

---

## 四、AI 集成技术规范

### 支持的 AI 服务商

| 服务商 | API Base URL | 推荐模型 | 免费额度 |
|--------|-------------|---------|---------|
| DeepSeek | https://api.deepseek.com | deepseek-chat | 新用户有额度 |
| 智谱清言 | https://open.bigmodel.cn/api/paas/v4 | glm-4-flash | ✅ 免费 |

### PlantUML 渲染

| 服务 | 地址 | 协议 | 说明 |
|------|------|------|------|
| Kroki.io（主） | https://kroki.io/plantuml/png | POST text/plain | 无需编码，推荐 |
| PlantUML 官方（备） | https://www.plantuml.com/plantuml/png/ | GET + 特殊编码 | 备用 |

### 踩坑经验（参考 Android 版 AI 问答系统）

1. **HTTP User-Agent**：部分 API 服务器会检查 UA，建议设置 `Mozilla/5.0 compatible`
2. **超时设置**：AI API 建议 60 秒超时（生成内容较慢），PlantUML 建议 30 秒
3. **JSON 提取**：AI 返回内容可能包含 Markdown 代码块，需用正则提取纯 JSON
4. **中文 PDF 字体**：需在 assets/fonts/ 放置 NotoSansSC 等中文字体，否则汉字显示为方块
5. **智谱 GLM**：`glm-4-flash` 完全免费，适合教学场景演示

---

## 五、数据库版本历史

| 版本 | 新增表 | 说明 |
|------|-------|------|
| v1 | users, current_session, graphs, nodes, edges, questions, quiz_results, learning_records, wrong_answers, favorites, resource_files | 初始版本 |
| v2 | generated_materials, puml_files, ai_configs | 增加 AI 生成素材管理和 PlantUML |

---

## 六、当前实现产出清单

### Flutter 服务层（Dart 替代 Python）

| 服务 | 文件 | 替代 Python |
|------|------|------------|
| AI 内容生成 | `lib/services/ai_service.dart` | DeepSeek/ZhipuAI HTTP API |
| PlantUML 渲染 | `lib/services/plantuml_service.dart` | Kroki.io + PlantUML 官方 |
| 课件生成（PDF）| `lib/services/slide_generator_service.dart` | pdf package |
| 素材管理 | `lib/services/material_service.dart` | 本地 SQLite |

### 新增页面

| 页面 | 文件 | 功能 |
|------|------|------|
| 素材中心 | `materials_hub_page.dart` | 4 Tab：资料/生成/UML/素材库 |
| AI 助手 | `ai_assist_page.dart` | 对话/脚本/UML 生成 |
| 课件生成 | `slide_generator_page.dart` | AI → PDF 课件 |
| UML 管理 | `puml_manager_page.dart` | 编辑+渲染+保存 PUML |
| AI 配置 | `ai_settings_page.dart` | API Key + 服务商选择 |

---

## 七、项目架构图（更新版）

参见 `docs/diagrams/v3/flutter_dart_framework_architecture.puml`（系统架构图）及新增 AI 服务层扩展。

---

## 八、参考资料

1. Python 图谱工具项目功能点：`docs/图谱工具项目Python版本功能点.md`
2. MADQA 开发计划：`D:\development\MAUI\开发文档\MADQA开发计划.md`
3. Android AI 问答系统：讯飞 WebSocket ASR + 智谱/DeepSeek HTTP API 集成经验
4. 视频脚本体系：`docs/video/feat_*/script.md`（v6 版本）
5. 测试文档：`docs/testing/test_cases.md` + `docs/testing/test_report.md`
